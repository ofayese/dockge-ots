# Runbook — Reissue certs, bring up Traefik, Google OAuth (Path A Step 1)

> **Audience:** Operator on the Synology NAS (or SSH session to it) with Dockge stacks under `${STACK_ROOT}` (default `/volume1/docker/dockge/stacks`).
> **Canonical detail:** Full `--issue` / `--install-cert` matrix lives in [`stacks/acme-sh/SETUP.md`](../../stacks/acme-sh/SETUP.md). This doc is the **ordered** checklist.

---

## 0 — Prerequisites

1. **DNS (Cloudflare)** — Wildcard CNAMEs match the host-named model (see [`docs/hive/dns/olutechsys.com.zone`](dns/olutechsys.com.zone)):
   - `*.otsorundscore.olutechsys.com` and `*.otsorundscore.olutech.systems` → `otsorundscore.synology.me.` (OTS).
   - `*.misfitsds.olutechsys.com` and `*.misfitsds.olutech.systems` → `misfitsds.synology.me.` (MFT).
   - Grey-cloud / DNS-only for those wildcards (no orange-cloud proxy to DDNS).
2. **Cloudflare API token** — `Zone.DNS:Edit` on **`olutechsys.com`** and **`olutech.systems`**.
3. **Repo on NAS** — `${STACK_ROOT}/acme-sh` and `${STACK_ROOT}/traefik-ots` (or `traefik-mft`) exist; `scripts/init-nas.sh` already run if this is a fresh tree.
4. **Paths** — `${ACME_CERT_ROOT}` defaults to `/volume1/certs/acme` (see `stacks/acme-sh/.env`).

---

## Part A — Reissue host-named Traefik PEMs (OTS and MFT)

Perform **on the NAS that runs `acme-sh`** (often **OTS only** if one container issues for both zones).

### A1 — Start acme-sh

```bash
cd "${STACK_ROOT:-/volume1/docker/dockge/stacks}/acme-sh"
test -f .env || sudo cp .env.example .env
# Edit .env: CF_Token, ACME_CERT_ROOT if non-default, STACK_ROOT
sudo docker compose up -d
sudo docker logs AcmeSh --tail 30
```

### A2 — Ensure output directories exist

```bash
sudo mkdir -p /volume1/certs/acme/otsorundscore /volume1/certs/acme/misfitsds
```

### A3 — List existing orders (decide whether to remove)

```bash
sudo docker exec AcmeSh acme.sh --list
```

If **Main_Domain** in the list is `*.otsorundscore.olutechsys.com` or `*.misfitsds.olutechsys.com` (wildcard-primary) and you want a **new** apex-primary order from **A4**, remove that old order first — acme.sh keeps one directory per Main_Domain.

**Do not** remove an order whose Main_Domain is already `otsorundscore.olutechsys.com` / `misfitsds.olutechsys.com` unless you intend to wipe and re-create it; in that case prefer `acme.sh --issue ... --force` to expand SANs on the existing order when acme.sh allows it (see logs). Full detail: [`stacks/acme-sh/SETUP.md`](../../stacks/acme-sh/SETUP.md) **Re-issue** / **otsorundscore-sub**.

### A3b — Remove wildcard-primary orders (manual)

Use the **exact** Main_Domain string from `acme.sh --list`. Typical cleanup when moving to apex-first **A4**:

```bash
# ECC first (ignore errors if you never had ECC orders)
sudo docker exec AcmeSh acme.sh --remove -d '*.otsorundscore.olutechsys.com' --ecc
sudo docker exec AcmeSh acme.sh --remove -d '*.misfitsds.olutechsys.com' --ecc

# RSA
sudo docker exec AcmeSh acme.sh --remove -d '*.otsorundscore.olutechsys.com'
sudo docker exec AcmeSh acme.sh --remove -d '*.misfitsds.olutechsys.com'
```

Confirm: `sudo docker exec AcmeSh acme.sh --list` — those Main_Domain rows should be gone.

### A3c — Same cleanup, idempotent (automation-friendly)

Runs **inside** the container so `*` is not expanded by the host shell. Safe to run before **A4** even if an order is already absent (`|| true` swallows “not found” style failures).

```bash
sudo docker exec AcmeSh sh -c '
  for d in "*.otsorundscore.olutechsys.com" "*.misfitsds.olutechsys.com"; do
    acme.sh --remove -d "$d" --ecc 2>/dev/null || true
    acme.sh --remove -d "$d" 2>/dev/null || true
  done
  acme.sh --list
'
```

There is **no** built-in acme-sh compose hook in this repo that runs this automatically on `docker compose up`; keep it as an explicit operator (or NAS cron) step before the first `--issue` after a migration. Optional: wrap the `sh -c` block in a small script under `${STACK_ROOT}/acme-sh/scripts/` on your NAS if you want a named command.

### A4 — Issue (DNS-01)

**Wildcard vs apex:** A name like `*.otsorundscore.olutechsys.com` does **not** cover the apex `otsorundscore.olutechsys.com` (one DNS label only). Put **apex first** or **wildcard first** on the same `--issue` line; only the **first** `-d` matters for acme.sh’s **order key** and for **`--install-cert -d`** in **A5** (must match `acme.sh --list` **Main_Domain**).

**OTS — apex + wildcards (both TLDs):**

```bash
sudo docker exec AcmeSh acme.sh --issue \
  -d 'otsorundscore.olutechsys.com' \
  -d 'otsorundscore.olutech.systems' \
  -d '*.otsorundscore.olutechsys.com' \
  -d '*.otsorundscore.olutech.systems' \
  --keylength 2048 \
  --dns dns_cf --server letsencrypt
```

**MFT — apex + wildcards (both TLDs):**

```bash
sudo docker exec AcmeSh acme.sh --issue \
  -d 'misfitsds.olutechsys.com' \
  -d 'misfitsds.olutech.systems' \
  -d '*.misfitsds.olutechsys.com' \
  -d '*.misfitsds.olutech.systems' \
  --keylength 2048 \
  --dns dns_cf --server letsencrypt
```

Wait for **success** in logs (`docker logs -f AcmeSh`). DNS propagation is typically 1–2 minutes per order.

### A5 — Install PEMs to Traefik-facing dirs

`--install-cert -d` must match **Main_Domain** from `acme.sh --list` (the **first** `-d` from **A4** — here the apex on `.olutechsys.com`).

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d 'otsorundscore.olutechsys.com' \
  --cert-file      /volume1/certs/acme/otsorundscore/cert.pem \
  --key-file       /volume1/certs/acme/otsorundscore/privkey.pem \
  --ca-file        /volume1/certs/acme/otsorundscore/chain.pem \
  --fullchain-file /volume1/certs/acme/otsorundscore/fullchain.pem \
  --reloadcmd      "chmod 640 /volume1/certs/acme/otsorundscore/privkey.pem"
```

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d 'misfitsds.olutechsys.com' \
  --cert-file      /volume1/certs/acme/misfitsds/cert.pem \
  --key-file       /volume1/certs/acme/misfitsds/privkey.pem \
  --ca-file        /volume1/certs/acme/misfitsds/chain.pem \
  --fullchain-file /volume1/certs/acme/misfitsds/fullchain.pem \
  --reloadcmd      "chmod 640 /volume1/certs/acme/misfitsds/privkey.pem"
```

### A6 — Verify PEMs on disk

```bash
sudo ls -la /volume1/certs/acme/otsorundscore/
sudo ls -la /volume1/certs/acme/misfitsds/
openssl x509 -in /volume1/certs/acme/otsorundscore/fullchain.pem -noout -subject -dates 2>/dev/null || true
```

### A7 — HAProxy bundles (optional edge)

If Synology **HAProxy** terminates TLS using combined PEMs under `${STACK_ROOT}/_haproxy/certs/`, rebuild from acme output (example OTS hostname bundle):

```bash
sudo sh -c 'cat /volume1/certs/acme/otsorundscore/fullchain.pem /volume1/certs/acme/otsorundscore/privkey.pem > /volume1/docker/dockge/stacks/_haproxy/certs/otsorundscore.olutechsys.com.pem'
```

Details: [`stacks/_haproxy/README.txt`](../../stacks/_haproxy/README.txt). Reload HAProxy after updating PEMs.

---

## Part B — Bring Traefik up (per NAS)

**Rule:** PEMs must exist **before** the first meaningful HTTPS test.

### B1 — OTS NAS (`traefik-ots`)

```bash
cd "${STACK_ROOT:-/volume1/docker/dockge/stacks}/traefik-ots"
test -f .env || cp .env.example .env
# Confirm ACME_CERT_ROOT matches where PEMs were installed (default /volume1/certs/acme)
sudo docker compose up -d
sleep 15
sudo docker exec traefik-ots traefik healthcheck --ping
```

**Smoke tests:**

- `sudo docker exec traefik-ots traefik healthcheck --ping` (authoritative).
- Optional from the NAS host: `curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9080/ping` when using the default `TRAEFIK_DASHBOARD_PORT=9080` (see `.env`).

See [`stacks/traefik-ots/README.md`](../../stacks/traefik-ots/README.md) for ports, `tls.yaml`, and label examples.

### B2 — MFT NAS (`traefik-mft`)

Repeat **B1** on the **MFT** host using `${STACK_ROOT}/traefik-mft` and container name **`traefik-mft`**. PEM source is **`misfitsds/`** on that NAS (or copy/sync if you centralise issuance).

### B3 — After PEM rotation

Restart Traefik so the process reloads file-based certs if you replaced PEMs in place:

```bash
cd "${STACK_ROOT}/traefik-ots" && sudo docker compose restart
```

(MFT: same with `traefik-mft`.)

---

## Part C — Google Workspace OAuth Path A — **Step 1 only** (Google Cloud Console)

Full DSM wiring (Steps 2–3), validation, and errors: [`docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md`](GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md).

### C1 — OAuth consent screen

1. Open [Google Cloud Console](https://console.cloud.google.com) → **APIs & Services → OAuth consent screen**.
2. User type: **Internal** (Workspace-only).
3. App name (example): `Olutech NAS`.
4. **Authorized domains:** `olutechsys.com` (and add **`olutech.systems`** in the same field if DSM or users will hit OAuth on that TLD).
5. Save.

### C2 — OAuth 2.0 Client ID (Web application)

1. **APIs & Services → Credentials → Create Credentials → OAuth client ID**.
2. Application type: **Web application**.
3. Name (example): `OTS NAS DSM SSO`.

**Authorized JavaScript origins** — scheme + host only, no path, no trailing slash:

```
https://nas.otsorundscore.olutechsys.com
```

If the DSM Login Portal will also use **`.olutech.systems`**, add a **second** origin line:

```
https://nas.otsorundscore.olutech.systems
```

**Authorized redirect URIs** — must match DSM exactly:

```
https://nas.otsorundscore.olutechsys.com/__ssolib/oauth/callback
```

If you added the `.olutech.systems` origin, add the matching redirect URI:

```
https://nas.otsorundscore.olutech.systems/__ssolib/oauth/callback
```

4. **Create** → copy **Client ID** and **Client Secret** immediately (store in a password manager; never commit to git).
5. Optionally download the JSON credentials for offline backup.

### C3 — TLS check before DSM SSO test

The browser hostname you use for DSM SSO must match **both** a registered **Origin** and the cert SAN. Wildcard certs **`*.otsorundscore.olutechsys.com`** / **`*.otsorundscore.olutech.systems`** cover `nas.otsorundscore.*` when issued per **Part A**.

---

## Related docs

| Doc | Purpose |
| --- | --- |
| [`stacks/acme-sh/SETUP.md`](../../stacks/acme-sh/SETUP.md) | All cert profiles, wildcard, sub-orders, mTLS scripts |
| [`docs/hive/NAS_DEPLOYMENT.md`](NAS_DEPLOYMENT.md) | Fleet layout, Traefik port mapping, Security Advisor |
| [`docs/hive/SERVICE_MAP.md`](SERVICE_MAP.md) | Service URLs and PEM dir index |
| [`docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md`](GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md) | DSM SSO Client (Steps 2–3), checklist, rollback |

---

*Last aligned with repo Traefik mounts (`otsorundscore/`, `misfitsds/`) — 2026-05-09.*
