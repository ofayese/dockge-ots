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

If you are **replacing** an older RSA order whose primary `-d` was only `*.otsorundscore.olutechsys.com` and you need **both TLDs** on one cert, remove the old order first (see [`stacks/acme-sh/SETUP.md`](../../stacks/acme-sh/SETUP.md) **Re-issue** note), then re-run **A4**.

### A4 — Issue (DNS-01)

**OTS wildcard (both TLDs):**

```bash
sudo docker exec AcmeSh acme.sh --issue \
  -d '*.otsorundscore.olutechsys.com' \
  -d '*.otsorundscore.olutech.systems' \
  --keylength 2048 \
  --dns dns_cf --server letsencrypt
```

**MFT wildcard (both TLDs):**

```bash
sudo docker exec AcmeSh acme.sh --issue \
  -d '*.misfitsds.olutechsys.com' \
  -d '*.misfitsds.olutech.systems' \
  --keylength 2048 \
  --dns dns_cf --server letsencrypt
```

Wait for **success** in logs (`docker logs -f AcmeSh`). DNS propagation is typically 1–2 minutes per order.

### A5 — Install PEMs to Traefik-facing dirs

Primary `-d` must match the order shown in `acme.sh --list` (usually the **first** `-d` from **A4**).

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d '*.otsorundscore.olutechsys.com' \
  --cert-file      /volume1/certs/acme/otsorundscore/cert.pem \
  --key-file       /volume1/certs/acme/otsorundscore/privkey.pem \
  --ca-file        /volume1/certs/acme/otsorundscore/chain.pem \
  --fullchain-file /volume1/certs/acme/otsorundscore/fullchain.pem \
  --reloadcmd      "chmod 640 /volume1/certs/acme/otsorundscore/privkey.pem"
```

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d '*.misfitsds.olutechsys.com' \
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
- Optional from the NAS host: `curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/ping` when **`8080`** is the published dashboard/ping port (see `TRAEFIK_DASHBOARD_PORT` in `.env`).

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
