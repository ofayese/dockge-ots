# acme.sh — Let's Encrypt cert automation

Issues and auto-renews RSA certificates via Cloudflare DNS (`--keylength 2048`
by default). PEMs go to `/volume1/certs/acme/`; deploy scripts read from there
but do not auto-push. RSA orders use paths without the `_ecc` suffix (ECDSA
is not used).

For 4096-bit RSA, substitute `--keylength 4096` in every `--issue` block below
(same policy for all certs).

```text
/volume1/certs/acme/               (= /Volumes/certs/acme/ on Mac)
├── wildcard/                      *.olutechsys.com + *.olutech.systems
├── otsorundscore-sub/             apex + wildcards on both zones + optional `*.ots` / `*.mft` SANs (see SETUP)
├── misfitsds-sub/                 apex + wildcards on both zones + optional `*.ots` / `*.mft` SANs (see SETUP)
├── otsmbpro16/                    otsmbpro16.olutechsys.com
├── hpdevcore/                     hpdevcore.olutechsys.com
├── ots-sub/                       *.ots.olutechsys.com
├── mft-sub/                       *.mft.olutechsys.com
├── deploy-otsorundscore.bash         run on the Mac → stage otsorundscore-nas-upload/
├── deploy-misfitsds.bash          run on misfitsds (SSH)
├── deploy-otsmbpro16.bash         run on the Mac (PEMs → ~/certs/otsmbpro16/)
├── deploy-hpdevcore.bash          run on the laptop
├── tests/                         `bash tests/run-all.bash` — script checks
├── daemon-tls.json                Docker TLS-only reference (`tlsverify: false`, **legacy/lab-only**, loopback default)
├── daemon-mtls.json               Docker mTLS reference (`tlsverify: true`, **recommended when remote TCP is needed**, loopback default)
├── docker-mtls-init-ca.bash       initialize Docker mTLS CA (isolated PKI)
├── docker-mtls-issue-server.bash  issue daemon server cert (per daemon host)
├── docker-mtls-issue-client.bash  issue client cert (per user/device)
└── deploy-otsorundscore-mtls.bash    stage mTLS bundle for manual NAS upload
```

> **`*.asus.com` cannot be issued.** ASUSTeK owns that DNS zone.
> Use `olutechsys.com` or `olutech.systems` for device hostnames.

## NAS hosts & LAN IPs (reference)

Use these for firewall rules, HAProxy/Traefik backends, split-DNS, or `/etc/hosts` — **not** as Let’s Encrypt certificate names.

| Role | Hostname (examples) | Typical LAN IP | Notes |
| ---- | ------------------- | -------------- | ----- |
| OTS NAS | `otsorundscore`, `otsorundscore.olutechsys.com` | **`10.0.1.15`** | Runs Dockge stacks; HAProxy examples bind backends here; Docker narrow-TCP examples use this IP |
| MFT NAS | `misfitsds`, `misfitsds.olutechsys.com` | **`10.0.1.24`** | Separate Synology; same DNS-01 / pem layout under `${ACME_CERT_ROOT}` after issue |

Adjust IPs if your VLAN differs. Optionally mirror them as comments in `acme-sh/.env` (see `.env.example` — compose does not consume those vars).

### Can I put NAS IPs on the Let’s Encrypt cert?

**Not for private LAN addresses (e.g. `10.x`, `192.168.x`).** Let’s Encrypt does not issue certificates whose SANs are **RFC1918/private IPs**. This stack validates with **Cloudflare DNS-01**, which proves control of **DNS names**, not arbitrary IP identifiers.

**What to do instead**

- Serve HTTPS by **hostname** (`*.ots.…`, `*.otsorundscore.…`, etc.) and resolve those names on the LAN via **split DNS**, **`/etc/hosts`**, or your router — the PEM from acme.sh stays valid for those names.
- Need TLS **to an IP** or **Docker daemon** identity? Use **hostname + DNS** for LE-backed services, or **private PKI** (e.g. mTLS scripts under your acme tree: `SAN_IPS=10.0.1.15` for daemon certs — not the same as LE).

---

## Deploy acme-sh end-to-end (checklist)

Do this on **each Synology** that runs the acme-sh container (often **OTS only** if one NAS issues for all zones via Cloudflare).

### 1. Prerequisites

- Cloudflare API token (`Zone.DNS:Edit`) on **`olutechsys.com`** and **`olutech.systems`** (grey-cloud / DNS-only on wildcards you use for Synology DDNS is OK for issuance).
- Repo path on NAS: `${STACK_ROOT}/acme-sh` (e.g. `/volume1/docker/dockge/stacks/acme-sh`).
- Parent dirs exist for **`${ACME_CERT_ROOT}`** (default `/volume1/certs/acme`).

### 2. Configure `.env`

```bash
cd /volume1/docker/dockge/stacks/acme-sh
test -f .env || sudo cp .env.example .env
# Edit: CF_Token, STACK_ROOT, ACME_CERT_ROOT (if not default), optional DISCORD_WEBHOOK_URL
```

### 3. Start the stack

```bash
sudo docker compose up -d
sudo docker logs AcmeSh --tail 30
```

Expect daemon mode (cron); no HTTP port — renewals run inside the container.

### 4. Create PEM output directories

```bash
sudo mkdir -p \
  /volume1/certs/acme/wildcard \
  /volume1/certs/acme/otsorundscore-sub \
  /volume1/certs/acme/misfitsds-sub \
  /volume1/certs/acme/ots-sub \
  /volume1/certs/acme/mft-sub \
  /volume1/certs/acme/otsmbpro16 \
  /volume1/certs/acme/hpdevcore
```

(Omit dirs you never issue.)

### 5. Issue certificates

Run the **`--issue`** blocks in [Issue all certs](#issue-all-certs) that you need (DNS propagation ~1–2 minutes each). Watch logs:

```bash
sudo docker logs -f AcmeSh
```

### 6. Install PEMs to `${ACME_CERT_ROOT}`

Run matching **`--install-cert`** blocks in [Configure output paths](#configure-output-paths-run-once-per-cert-after-issue). Use each order’s **primary** `-d` from:

```bash
sudo docker exec AcmeSh acme.sh --list
```

### 7. Reload consumers

After new or renewed PEMs:

- **Traefik** (`traefik-ots` / `traefik-mft`): restart or reload so file certs pick up changes (see Traefik stack README).
- **HAProxy**: `haproxy -c` then reload Synology HAProxy package if it reads `_haproxy/certs/`.
- **DSM / deploy scripts**: run `deploy-otsorundscore.bash` / `deploy-misfitsds.bash` from your workflow when you push DSM/Docker TLS copies.

### 8. Verify

```bash
openssl x509 -in /volume1/certs/acme/ots-sub/fullchain.pem -noout -subject -dates 2>/dev/null || true
sudo docker exec AcmeSh acme.sh --list
```

---

## Deploy script tests

From a machine where the acme tree is available:

```bash
bash /Volumes/certs/acme/tests/run-all.bash
```

---

## Docker remote access profiles (SSH-first, narrow TCP only when needed)

Recommended posture, in order:

| Profile                       | `tlsverify` | Server auth     | Client auth                | When to use                                 |
| ----------------------------- | ----------- | --------------- | -------------------------- | ------------------------------------------- |
| **SSH context**               | n/a         | SSH host key    | SSH user key               | **Default — admin access for everything**   |
| **mTLS context** (narrow TCP) | `true`      | Private CA      | Private CA                 | Only when remote TCP is explicitly required |
| TLS-only                      | `false`     | Public/LE chain | **none — lab/legacy only** | Avoid; kept for back-compat                 |

> **SSH context is the recommended default.** It rides Docker's normal
> SSH transport over `unix:///var/run/docker.sock` on the daemon host, so
> it works without opening any TCP listener at all and is independent of
> `daemon.json` `hosts`. Reach for **mTLS** only when something genuinely
> requires `tcp://…:2376` (e.g., an integration that cannot speak Docker
> over SSH). TLS-only is **legacy/lab-only** — encrypted wire, no client
> authentication; treat a reachable port as remote root.

**Reference `daemon-*.json` defaults (committed in this repo):** both
`daemon-tls.json` and `daemon-mtls.json` bind to **`tcp://127.0.0.1:2376`
(loopback only)** so the safe default cannot accidentally expose Docker
on the LAN. To allow narrow remote TCP, edit `hosts` to a single,
firewalled lab IP **before** merging — for this lab that is
`tcp://10.0.1.15:2376` for otsorundscore (`10.0.1.15`); misfitsds is
`10.0.1.24` (no Docker daemon TLS bundle in this tree). For **private Docker mTLS**
certs only, add that IP to server SANs (`SAN_IPS` in the mTLS scripts) — **not**
on Let’s Encrypt DNS-01 certs (see [Can I put NAS IPs on the Let’s Encrypt cert?](#can-i-put-nas-ips-on-the-lets-encrypt-cert)). Tighten the firewall to the trusted client subnet.

1. **SSH context (recommended default — no TCP needed):**

```bash
docker context create otsorundscore-ssh --docker "host=ssh://YOUR_USER@otsorundscore"
docker --context otsorundscore-ssh info
```

This works regardless of the TCP listener state — even if
`daemon.json` has no `tcp://…` entry at all. Use this as the primary
admin path; reach for mTLS only when SSH cannot satisfy the consumer.

1. **mTLS context (narrow TCP — only when SSH is not enough):**
   - Daemon uses private CA + server cert + `tlsverify=true`
   - Client presents a cert signed by the same CA
   - Keeps Docker PKI isolated under `/volume1/certs/acme/docker-mtls/`
   - Client artifacts live under a **dedicated, per-context path**
     (`~/.docker/contexts/otsorundscore-mtls/`) so they cannot be clobbered by
     `deploy-otsmbpro16.bash`, which manages the default `~/.docker/ca.pem`,
     `cert.pem`, `key.pem` from the public LE chain.

```bash
mkdir -p "$HOME/.docker/contexts/otsorundscore-mtls"
docker context create otsorundscore-mtls --docker \
  "host=tcp://otsorundscore.olutechsys.com:2376,\
ca=$HOME/.docker/contexts/otsorundscore-mtls/ca.pem,\
cert=$HOME/.docker/contexts/otsorundscore-mtls/cert.pem,\
key=$HOME/.docker/contexts/otsorundscore-mtls/key.pem"
docker --context otsorundscore-mtls info
```

> **Per-context TLS files are the default pattern.** Keeping each
> context's PEMs under its own `~/.docker/contexts/<name>/` directory
> means an mTLS context cannot be silently overwritten by tools that
> manage the default `~/.docker/{ca,cert,key}.pem` (such as
> `deploy-otsmbpro16.bash`).
>
> **`DOCKER_CERT_PATH` is an optional alternative** for one-off, non-context
> flows: point Docker at any directory containing `ca.pem`/`cert.pem`/`key.pem`
> without registering a context — for example,
> `DOCKER_HOST=tcp://otsorundscore.olutechsys.com:2376
DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH="$HOME/.docker/contexts/otsorundscore-mtls"
docker info`. Prefer `docker context` for anything persistent;
> `DOCKER_CERT_PATH` is for ad-hoc shells and CI jobs.

---

## Pitfalls / common gotchas

These are easy to get wrong and have bitten this stack before. Read
before editing `daemon.json` or restarting Docker.

### 1. Don't duplicate `hosts` between systemd and `daemon.json`

On Linux hosts that run Docker via systemd, the unit may pass `-H
fd://` or `-H tcp://…` to `dockerd`. **`daemon.json` must NOT also
declare `hosts`** in that case — Docker refuses to start with
"unable to configure the Docker daemon with file /etc/docker/daemon.json:
the following directives are specified both as a flag and in the
configuration file: hosts". Pick exactly one source of truth:

- Edit the systemd drop-in (`/etc/systemd/system/docker.service.d/override.conf`)
  and remove `-H` flags from `ExecStart`, **or**
- Keep the systemd flags and remove `hosts` from `daemon.json`.

This trap does **not** apply to Synology Container Manager (no systemd
unit; the package launcher honors `daemon.json` `hosts` directly), but
will bite any Linux host you migrate this config to.

### 2. Synology Container Manager — daemon path & restart semantics

DSM's Container Manager / Docker package uses a non-standard layout:

- The active config file is **`/volume1/​docker/daemon.json`**, not
  `/etc/docker/daemon.json`. Edits to the latter are silently ignored.
- The correct restart command is **`sudo synopkg restart ContainerManager`**
  (older DSM: `sudo synopkg restart Docker`). `systemctl restart docker`
  does not exist.
- DSM package upgrades may rewrite or replace `daemon.json`. Always
  back it up before merging (`cp -n /volume1/​docker/daemon.json
/volume1/​docker/daemon.json.bak`) and re-apply your fragment after a
  package update if the diff disappears.
- `synoservicectl --reload nginx` is what reloads DSM's reverse proxy
  after replacing `cert.pem`/`chain.pem` in
  `/usr/syno/etc/certificate/system/default/`.

### 3. Always merge `daemon.json` atomically

Never do `jq … daemon.json | sudo tee daemon.json` — the same file is
both input and output of the pipeline and the read can race the
truncating write, leaving an empty `daemon.json` and a daemon that
won't start. Always go through a temp file:

```bash
TMP=$(sudo mktemp /volume1/​docker/.daemon.json.XXXXXX)
sudo jq -s '.[0] * .[1]' \
  /volume1/​docker/daemon.json \
  /volume1/certs/acme/daemon-mtls.json > "${TMP}"
sudo mv -f "${TMP}" /volume1/​docker/daemon.json
```

`mv -f` within the same filesystem is atomic, so a reader either sees
the old file or the new one — never a half-written file.

### 4. Per-context TLS, not shared `~/.docker/{ca,cert,key}.pem`

Always write mTLS client material under
`~/.docker/contexts/<context-name>/` so unrelated tooling that manages
the default `~/.docker/` files (e.g. `deploy-otsmbpro16.bash`, IDEs,
Docker Desktop) cannot clobber it. `DOCKER_CERT_PATH` is acceptable
for non-context shells and CI; do not set it as a permanent shell
default while you also have multiple contexts.

---

## Prerequisites

1. Fill in `.env` (Cloudflare API token, Discord webhook)
2. Cloudflare API token: `Zone > DNS > Edit` for **both** `olutechsys.com`
   and `olutech.systems`
3. Container started at least once so the acme.sh data volume is initialised

---

## Migrating from ECDSA (`*_ecc`)

Older ECDSA certs live under `*_ecc/` in the acme.sh data volume. After
migration, PEMs stay at the same paths under `/volume1/certs/acme/`.

**Order:** backup → remove ECC (step 2) → issue RSA 2048 (step 3) →
`--install-cert` (step 4) → verify (step 5).

1. **Backup:** copy `/volume1/​docker/dockge​/stacks/acme-sh/data` and optionally
   `/volume1/certs/acme/`.
2. **Remove ECDSA orders** before re-issue. Run the block; skip errors for
   names that were never ECC. Match `-d` to each ECC row’s primary domain in
   `sudo docker exec AcmeSh acme.sh --list` if yours differ from these:

   ```bash
   sudo docker exec AcmeSh acme.sh --remove -d '*.olutechsys.com' --ecc
   sudo docker exec AcmeSh acme.sh --remove -d '*.otsorundscore.olutechsys.com' --ecc
   sudo docker exec AcmeSh acme.sh --remove -d '*.misfitsds.olutechsys.com' --ecc
   sudo docker exec AcmeSh acme.sh --remove -d 'otsmbpro16.olutechsys.com' --ecc
   sudo docker exec AcmeSh acme.sh --remove -d 'hpdevcore.olutechsys.com' --ecc
   sudo docker exec AcmeSh acme.sh --remove -d '*.ots.olutechsys.com' --ecc
   sudo docker exec AcmeSh acme.sh --remove -d '*.mft.olutechsys.com' --ecc
   ```

3. **Issue:** run each block in [Issue all certs](#issue-all-certs) (`--keylength 2048`).
4. **Install:** run each block in [Configure output paths](#configure-output-paths-run-once-per-cert-after-issue). Use the same primary `-d` as in `--issue`.
5. **Verify** RSA key material and chain trust:

   ```bash
   openssl x509 -in /volume1/certs/acme/wildcard/fullchain.pem -noout -text \
     | grep -E 'Public Key Algorithm|RSA Public-Key'
   openssl verify -CAfile /volume1/certs/acme/wildcard/chain.pem \
     /volume1/certs/acme/wildcard/cert.pem
   ```

   Repeat the `openssl` pair for other dirs (`otsorundscore-sub/`, etc.) as needed.

---

## First-time setup

### 1. Start the container

```bash
cd /volume1/​docker/dockge​/stacks/acme-sh
docker compose up -d
```

### 2. Enable Discord notifications

```bash
sudo docker exec AcmeSh acme.sh --set-notify --notify-hook discord
```

---

## Issue all certs

Run each block once (DNS ~1–2 min per cert). Default key is `--keylength 2048`.

Primary `-d` strings (for `--install-cert`, `--renew`, and non-`--ecc` remove):
`*.olutechsys.com`, `otsorundscore.olutechsys.com` (otsorundscore-sub), `misfitsds.olutechsys.com` (misfitsds-sub),
`otsmbpro16.olutechsys.com`, `hpdevcore.olutechsys.com`, `*.ots.olutechsys.com`,
`*.mft.olutechsys.com` — confirm with
`acme.sh --list` if anything differs.

### wildcard — \*.olutechsys.com + \*.olutech.systems

```bash
sudo docker exec AcmeSh acme.sh --issue \
  -d '*.olutechsys.com'  -d 'olutechsys.com' \
  -d '*.olutech.systems' -d 'olutech.systems' \
  --keylength 2048 \
  --dns dns_cf --server letsencrypt
```

### otsorundscore-sub — apex + `*.otsorundscore.*` (+ optional namespace wildcards)

First `-d` is the acme.sh order key (CN / “main” in many UIs); remaining `-d` values are SANs.

Optional `*.ots.olutechsys.com` and `*.mft.olutechsys.com` duplicate coverage from dedicated
`ots-sub/` and `mft-sub/` orders — omit those two lines if you prefer separate cert rotation only.

```bash
sudo docker exec AcmeSh acme.sh --issue \
  -d 'otsorundscore.olutechsys.com' \
  -d 'otsorundscore.olutech.systems' \
  -d '*.otsorundscore.olutechsys.com' \
  -d '*.otsorundscore.olutech.systems' \
  -d '*.ots.olutechsys.com' \
  -d '*.mft.olutechsys.com' \
  --keylength 2048 \
  --dns dns_cf --server letsencrypt
```

**Re-issue after an older order used `*.otsorundscore.olutechsys.com` as primary:** remove the old RSA order first, then issue again (match `-d` from `acme.sh --list`):

```bash
sudo docker exec AcmeSh acme.sh --remove -d '*.otsorundscore.olutechsys.com'
```

### misfitsds-sub — apex + `*.misfitsds.*` (+ optional namespace wildcards)

Same optional SAN overlap note as otsorundscore-sub.

```bash
sudo docker exec AcmeSh acme.sh --issue \
  -d 'misfitsds.olutechsys.com' \
  -d 'misfitsds.olutech.systems' \
  -d '*.misfitsds.olutechsys.com' \
  -d '*.misfitsds.olutech.systems' \
  -d '*.ots.olutechsys.com' \
  -d '*.mft.olutechsys.com' \
  --keylength 2048 \
  --dns dns_cf --server letsencrypt
```

### otsmbpro16 — MacBook

```bash
sudo docker exec AcmeSh acme.sh --issue \
  -d 'otsmbpro16.olutechsys.com' \
  -d 'otsmbpro16.olutech.systems' \
  --keylength 2048 \
  --dns dns_cf --server letsencrypt
```

### hpdevcore — Laptop

```bash
sudo docker exec AcmeSh acme.sh --issue \
  -d 'hpdevcore.olutechsys.com' \
  -d 'hpdevcore.olutech.systems' \
  --keylength 2048 \
  --dns dns_cf --server letsencrypt
```

## Issue ots and mft namespace certs

Dedicated `ots-sub/` and `mft-sub/` PEM dirs are still recommended for Traefik stacks that mount only those paths. If you already included `*.ots.olutechsys.com` / `*.mft.olutechsys.com` as extra SANs on **otsorundscore-sub** or **misfitsds-sub**, you can skip the duplicate orders below (same names on two certs = two independent renewals).

```bash
sudo docker exec AcmeSh acme.sh --issue \
  -d '*.ots.olutechsys.com' \
  --keylength 2048 \
  --dns dns_cf --server letsencrypt
```

```bash
sudo docker exec AcmeSh acme.sh --issue \
  -d '*.mft.olutechsys.com' \
  --keylength 2048 \
  --dns dns_cf --server letsencrypt
```

---

## Configure output paths (run once per cert after issue)

Run each block once; paths are persisted in the acme.sh data volume. `-d` must
match the RSA order’s primary domain from `acme.sh --list` (same as `--issue`
unless the list shows otherwise).

Create dirs first (acme.sh does not create parents):

```bash
sudo mkdir -p \
  /volume1/certs/acme/wildcard \
  /volume1/certs/acme/otsorundscore-sub \
  /volume1/certs/acme/misfitsds-sub \
  /volume1/certs/acme/otsmbpro16 \
  /volume1/certs/acme/hpdevcore \
  /volume1/certs/acme/ots-sub \
  /volume1/certs/acme/mft-sub
```

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d '*.olutechsys.com' \
  --cert-file      /volume1/certs/acme/wildcard/cert.pem \
  --key-file       /volume1/certs/acme/wildcard/privkey.pem \
  --ca-file        /volume1/certs/acme/wildcard/chain.pem \
  --fullchain-file /volume1/certs/acme/wildcard/fullchain.pem \
  --reloadcmd      "chmod 640 /volume1/certs/acme/wildcard/privkey.pem"
```

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d 'otsorundscore.olutechsys.com' \
  --cert-file      /volume1/certs/acme/otsorundscore-sub/cert.pem \
  --key-file       /volume1/certs/acme/otsorundscore-sub/privkey.pem \
  --ca-file        /volume1/certs/acme/otsorundscore-sub/chain.pem \
  --fullchain-file /volume1/certs/acme/otsorundscore-sub/fullchain.pem \
  --reloadcmd      "chmod 640 /volume1/certs/acme/otsorundscore-sub/privkey.pem"
```

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d 'misfitsds.olutechsys.com' \
  --cert-file      /volume1/certs/acme/misfitsds-sub/cert.pem \
  --key-file       /volume1/certs/acme/misfitsds-sub/privkey.pem \
  --ca-file        /volume1/certs/acme/misfitsds-sub/chain.pem \
  --fullchain-file /volume1/certs/acme/misfitsds-sub/fullchain.pem \
  --reloadcmd      "chmod 640 /volume1/certs/acme/misfitsds-sub/privkey.pem"
```

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d 'otsmbpro16.olutechsys.com' \
  --cert-file      /volume1/certs/acme/otsmbpro16/cert.pem \
  --key-file       /volume1/certs/acme/otsmbpro16/privkey.pem \
  --ca-file        /volume1/certs/acme/otsmbpro16/chain.pem \
  --fullchain-file /volume1/certs/acme/otsmbpro16/fullchain.pem \
  --reloadcmd      "chmod 640 /volume1/certs/acme/otsmbpro16/privkey.pem"
```

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d 'hpdevcore.olutechsys.com' \
  --cert-file      /volume1/certs/acme/hpdevcore/cert.pem \
  --key-file       /volume1/certs/acme/hpdevcore/privkey.pem \
  --ca-file        /volume1/certs/acme/hpdevcore/chain.pem \
  --fullchain-file /volume1/certs/acme/hpdevcore/fullchain.pem \
  --reloadcmd      "chmod 640 /volume1/certs/acme/hpdevcore/privkey.pem"
```

## Configure ots and mft output paths

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d '*.ots.olutechsys.com' \
  --cert-file      /volume1/certs/acme/ots-sub/cert.pem \
  --key-file       /volume1/certs/acme/ots-sub/privkey.pem \
  --ca-file        /volume1/certs/acme/ots-sub/chain.pem \
  --fullchain-file /volume1/certs/acme/ots-sub/fullchain.pem \
  --reloadcmd      "chmod 640 /volume1/certs/acme/ots-sub/privkey.pem"
```

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d '*.mft.olutechsys.com' \
  --cert-file      /volume1/certs/acme/mft-sub/cert.pem \
  --key-file       /volume1/certs/acme/mft-sub/privkey.pem \
  --ca-file        /volume1/certs/acme/mft-sub/chain.pem \
  --fullchain-file /volume1/certs/acme/mft-sub/fullchain.pem \
  --reloadcmd      "chmod 640 /volume1/certs/acme/mft-sub/privkey.pem"
```

---

## Deploy to each device

Run the relevant script from each device after the cert files appear in
`/volume1/certs/acme/`. Re-run these whenever you want to push a renewed cert.

### otsorundscore — stage on Mac, upload, apply on NAS

`deploy-otsorundscore.bash` **only builds** `otsorundscore-nas-upload/` under your acme tree
(e.g. `/Volumes/certs/acme/otsorundscore-nas-upload/`). It does not SSH into the NAS.

```bash
bash /Volumes/certs/acme/deploy-otsorundscore.bash
```

Zip or copy that folder to the NAS (File Station, `scp`, etc.), then as **root** on
otsorundscore: copy the staged `dsm-*` and `docker-tls/` PEMs into the DSM and Docker paths
shown in the script header, merge TLS into `/volume1/​docker/daemon.json`, reload nginx,
and restart Container Manager.

**First run only — apply the full Docker daemon config.** The bundled
`daemon-tls.json` binds Docker TCP to **`tcp://127.0.0.1:2376` (loopback
only)** by default — the safe, no-LAN-exposure posture. SSH context
access (`docker context … ssh://…`) uses the Unix socket on the NAS and
is unaffected by this bind. **If you actually need narrow LAN TCP** for
this otsorundscore host (and SSH is not enough), edit `hosts` to
`tcp://10.0.1.15:2376` **before** merge and pair it with mTLS plus a
firewall rule restricting `:2376` to the trusted client subnet. Use a
temp file and atomic `mv` to update `daemon.json`; piping
`jq ... | tee daemon.json` is unsafe because the same file is on both
sides of the pipeline.

```bash
# On otsorundscore, as root:
sudo cp -n /volume1/​docker/daemon.json /volume1/​docker/daemon.json.bak
TMP=$(sudo mktemp /volume1/​docker/.daemon.json.XXXXXX)
sudo jq -s '.[0] * .[1]' \
  /volume1/​docker/daemon.json \
  /volume1/certs/acme/daemon-tls.json > "${TMP}"
sudo mv -f "${TMP}" /volume1/​docker/daemon.json
sudo synopkg restart ContainerManager
```

If `daemon.json` doesn't exist yet:

```bash
sudo install -m 0644 /volume1/certs/acme/daemon-tls.json /volume1/​docker/daemon.json
sudo synopkg restart ContainerManager
```

### otsorundscore — Docker mTLS bundle (parallel path, non-destructive)

The TLS-only path above remains valid. For hardened mTLS, use the dedicated
`docker-mtls/` PKI subtree and mTLS daemon config.

**Input validation:** `docker-mtls-issue-*.bash` and `deploy-otsorundscore-mtls.bash`
validate **CLIENT_NAME**, **HOSTNAME** / **DOCKER_HOSTNAME**, and comma-separated
**SAN_DNS_EXTRA** / **SAN_IPS** (DNS labels or FQDNs; IPv4 literals only; no `/`,
`..`, whitespace, or control characters). Invalid values exit with an explicit
`ERROR:` message. Shared rules live in `docker-mtls-input-validate.bash` next to
the issue scripts.

**Single-threaded issuance (same CA):** `docker-mtls-issue-client.bash` and
`docker-mtls-issue-server.bash` both update the shared OpenSSL `-CAserial` file
under `docker-mtls/ca/serial`. **Do not run two issue scripts at the same time**
against the same `MTLS_DIR` / `docker-mtls/` tree. While signing, each script
acquires an exclusive `mkdir` lock at `docker-mtls/ca/.issue.lock` (portable on
macOS and Linux); a second process waits up to ~5 minutes, then exits with an
error instead of corrupting the serial. For batch issuance, run the commands
**sequentially** in one shell or a script — do not background multiple issue
invocations against one CA. The lock and serial bootstrap are implemented in
`docker-mtls-issue-common.bash` (sourced by both issue scripts).

1. Initialize a private CA once:

```bash
bash /volume1/certs/acme/docker-mtls-init-ca.bash
```

1. Issue one server cert per Docker daemon hostname:

```bash
HOSTNAME=otsorundscore.olutechsys.com \
  SAN_IPS=10.0.1.15 \
  bash /volume1/certs/acme/docker-mtls-issue-server.bash
```

1. Issue one client cert per user/device:

```bash
CLIENT_NAME=otsmbpro16 bash /volume1/certs/acme/docker-mtls-issue-client.bash
CLIENT_NAME=hpdevcore bash /volume1/certs/acme/docker-mtls-issue-client.bash
```

1. Stage NAS upload bundle (Mac or any mounted host):

```bash
DOCKER_HOSTNAME=otsorundscore.olutechsys.com \
  bash /Volumes/certs/acme/deploy-otsorundscore-mtls.bash
```

1. On otsorundscore (as root), apply mTLS daemon config (atomic temp-file
   merge — never `jq | tee daemon.json` against the same file):

```bash
mkdir -p /volume1/​docker/mtls
chmod 0700 /volume1/​docker/mtls
install -m 0644 /volume1/certs/acme/otsorundscore-nas-upload-mtls/docker-mtls/ca.pem          /volume1/​docker/mtls/ca.pem
install -m 0644 /volume1/certs/acme/otsorundscore-nas-upload-mtls/docker-mtls/server-cert.pem /volume1/​docker/mtls/server-cert.pem
install -m 0400 /volume1/certs/acme/otsorundscore-nas-upload-mtls/docker-mtls/server-key.pem  /volume1/​docker/mtls/server-key.pem

# docker-daemon-mtls.json updates tls/tlsverify/tlscacert/tlscert/tlskey only.
# It intentionally does NOT set `hosts`; existing listener values are preserved.
cp -n /volume1/​docker/daemon.json /volume1/​docker/daemon.json.bak
TMP=$(mktemp /volume1/​docker/.daemon.json.XXXXXX)
jq -s '.[0] * .[1]' \
  /volume1/​docker/daemon.json \
  /volume1/certs/acme/otsorundscore-nas-upload-mtls/docker-daemon-mtls.json > "${TMP}"
mv -f "${TMP}" /volume1/​docker/daemon.json
synopkg restart ContainerManager
```

> If you also need to enforce a specific `hosts` value from the reference file,
> merge `daemon-mtls.json` directly (or edit `daemon.json` manually) before restart.
> Example to enforce loopback-only:
>
> ```bash
> TMP=$(mktemp /volume1/​docker/.daemon.json.XXXXXX)
> jq -s '.[0] * .[1]' \
>   /volume1/​docker/daemon.json \
>   /volume1/certs/acme/daemon-mtls.json > "${TMP}"
> mv -f "${TMP}" /volume1/​docker/daemon.json
> synopkg restart ContainerManager
> ```
>
> The bundled `daemon-mtls.json` defaults to the same loopback bind
> (`tcp://127.0.0.1:2376`). With mTLS plus a narrow LAN bind
> (`tcp://10.0.1.15:2376`), only clients holding a cert signed by your
> lab CA can authenticate; still firewall `:2376` to trusted subnets.
> Prefer SSH context for admin access whenever possible. misfitsds
> (`10.0.1.24`) uses `deploy-misfitsds.bash` for DSM certs only — there
> is no Docker daemon TLS bundle for misfitsds in this tree unless you
> add one separately.

### misfitsds — SSH in, provide cert source

`deploy-misfitsds.bash` still runs **on misfitsds**. It needs `wildcard/` and
`misfitsds-sub/` under `SOURCE_DIR` — same layout as on the otsorundscore share or your Mac.
See the script header for the **Mac staging flow for otsorundscore** vs **misfitsds**
options (mount, rsync/scp placeholders).

```bash
ssh YOUR_USER@misfitsds

# Example: share already mounted at SOURCE_DIR
SOURCE_DIR=/mnt/your-acme-mount/acme bash /volume1/certs/acme/deploy-misfitsds.bash

# Example: copy dirs into /tmp/acme first, then run
SOURCE_DIR=/tmp/acme bash /volume1/certs/acme/deploy-misfitsds.bash
```

### otsmbpro16 — run on the Mac (NAS already mounted)

```bash
# From the acme directory so default SOURCE_DIR resolves to ./otsmbpro16/
cd /Volumes/certs/acme && bash ./deploy-otsmbpro16.bash
```

PEMs install to **`~/certs/otsmbpro16/`** by default (`DEST_DIR` override optional).
The script removes old `~/.docker/cert.pem` / `key.pem` and writes `~/.docker/ca.pem`
from `wildcard/chain.pem` (the Docker CLI still opens `ca.pem` when
`DOCKER_TLS_VERIFY=1`). After running, connect to Docker with:

```bash
# If otsorundscore.olutechsys.com is Cloudflare-proxied, public DNS points at CF
# (172.67.x.x) and :2376 times out — CF does not forward Docker TLS to the NAS.
#
# Best fix on the Mac: map the hostname to your NAS LAN IP (cert still matches), e.g.:
#   sudo sh -c 'echo "YOUR_NAS_LAN_IP otsorundscore.olutechsys.com" >> /etc/hosts'
# Then:
export DOCKER_HOST=tcp://otsorundscore.olutechsys.com:2376
export DOCKER_TLS_VERIFY=1
docker info
```

Using `DOCKER_HOST=tcp://YOUR_NAS_LAN_IP:2376` alone can fail TLS hostname checks (the
leaf is for `*.olutechsys.com`, not the raw IP). Prefer `/etc/hosts` or a
**DNS-only** (grey cloud) A record for a name that matches the cert.

Add both exports to `~/.zshrc` or `~/.bash_profile` to persist.

### Docker client mTLS install (otsmbpro16/hpdevcore)

Install client artifacts into a **dedicated, per-context path** so they
cannot be clobbered by `deploy-otsmbpro16.bash` (which writes the public
LE chain into `~/.docker/ca.pem`, `cert.pem`, `key.pem`).

```bash
# Example for otsmbpro16
CTX_DIR="$HOME/.docker/contexts/otsorundscore-mtls"
mkdir -p "$CTX_DIR"
chmod 0700 "$CTX_DIR"
install -m 0644 /Volumes/certs/acme/docker-mtls/ca/ca-cert.pem                "$CTX_DIR/ca.pem"
install -m 0644 /Volumes/certs/acme/docker-mtls/clients/otsmbpro16/cert.pem    "$CTX_DIR/cert.pem"
install -m 0400 /Volumes/certs/acme/docker-mtls/clients/otsmbpro16/key.pem     "$CTX_DIR/key.pem"
```

The matching `docker context create` command in [Docker remote access
profiles](#docker-remote-access-profiles-ssh-first-narrow-tcp-only-when-needed) points the context at
`$CTX_DIR/{ca,cert,key}.pem`, so this never touches the default `~/.docker/`
files.

Then verify:

```bash
docker --context otsorundscore-mtls version
```

Negative test (expected fail without the client cert when the daemon has
`tlsverify=true`):

```bash
CTX_DIR="$HOME/.docker/contexts/otsorundscore-mtls"
mv "$CTX_DIR/cert.pem" "$CTX_DIR/cert.pem.bak"
mv "$CTX_DIR/key.pem"  "$CTX_DIR/key.pem.bak"
docker --context otsorundscore-mtls version || true
mv "$CTX_DIR/cert.pem.bak" "$CTX_DIR/cert.pem"
mv "$CTX_DIR/key.pem.bak"  "$CTX_DIR/key.pem"
```

### hpdevcore — run on the laptop

```bash
# Mount the NAS share first (adjust server, path, and user for your setup):
sudo mount -t cifs //YOUR_FILESERVER/certs /mnt/nas-certs -o user=YOUR_USER

SOURCE_DIR=/mnt/nas-certs/acme/hpdevcore \
  bash /mnt/nas-certs/acme/deploy-hpdevcore.bash
```

---

## Auto-renewal

acme.sh in `daemon` mode checks for renewals every 24 hours and auto-copies
updated certs to `/volume1/certs/acme/` via the configured `--install-cert`
paths. You still need to run the device deploy scripts after each renewal.

### Optional: automate device deploys

Otsorundscore DSM/Docker PEMs are staged **on a Mac** with `deploy-otsorundscore.bash` after
acme.sh renews; schedule that (or a wrapper that uploads) on the machine that mounts
`/Volumes/certs/acme/`, not as an on-NAS cron that assumed the old in-place script.

```bash
# Example — Mac launchd/cron after renew: stage bundle (then upload manually or via your automation)
0 4 * * * bash /Volumes/certs/acme/deploy-otsorundscore.bash >>"$HOME/certs/deploy-otsorundscore.log" 2>&1
```

Check all managed certs and expiry:

```bash
sudo docker exec AcmeSh acme.sh --list
```

Force renewal (RSA only; do not pass `--ecc`). Use each cert’s primary `-d` from
`acme.sh --list` (see [Issue all certs](#issue-all-certs)):

```bash
sudo docker exec AcmeSh acme.sh --renew -d '*.olutechsys.com' --force
sudo docker exec AcmeSh acme.sh --renew -d 'hpdevcore.olutechsys.com' --force
```

Repeat for `otsorundscore.olutechsys.com`, `misfitsds.olutechsys.com`,
`otsmbpro16.olutechsys.com`, `*.ots.olutechsys.com`, `*.mft.olutechsys.com`, etc. (each cert’s primary `-d` from `acme.sh --list`).

---

## Migration notes — TLS-only to mTLS

- Existing TLS-only mode remains supported with `daemon-tls.json`
  (`tlsverify: false`) but is **legacy/lab-only**: it does not authenticate
  clients. Both reference daemon configs default to the safe loopback
  bind **`tcp://127.0.0.1:2376`**. To allow remote LAN access on
  otsorundscore, edit `hosts` to the narrow lab bind
  **`tcp://10.0.1.15:2376`** before merge and combine it with mTLS plus
  a firewall rule pinning `:2376` to the trusted client subnet. Keep an
  **SSH context** working first — that path does not depend on any TCP
  bind at all.
- mTLS mode is opt-in via `daemon-mtls.json` and `deploy-otsorundscore-mtls.bash`.
- Keep Docker mTLS PKI only under `/volume1/certs/acme/docker-mtls/`:
  - `ca/` (private CA, dir mode `0700`, key mode `0400`)
  - `servers/<daemon-host>/`
  - `clients/<client-name>/`
- Do not store Docker mTLS keys in existing ACME leaf folders (`wildcard/`,
  `*-sub/`, host leaf dirs), and do not use `~/.docker/{ca,cert,key}.pem`
  for the mTLS context — those are managed by `deploy-otsmbpro16.bash`.

Safe migration sequence:

1. Keep an SSH context working first (`docker --context otsorundscore-ssh info`).
2. Generate CA/server/client certs (CA is now hardened — see below).
3. Stage and apply `docker-daemon-mtls.json` merge using the temp-file
   pattern in [otsorundscore — Docker mTLS bundle](#otsorundscore--docker-mtls-bundle-parallel-path-non-destructive).
4. Install client certs into `~/.docker/contexts/otsorundscore-mtls/`.
5. Validate the mTLS context, then run the negative test.
6. Keep `daemon-tls.json` for rollback if needed; revert by re-merging it
   the same way and restarting `ContainerManager`.

---

## CA hardening rationale

`docker-mtls-init-ca.bash` enforces several defenses; understand why before
weakening any of them:

- **`umask 077` at the top of the script.** Every file the script creates
  (CSRs, extension configs, temp files) is `rw-------` by default. Without
  this, an interactive shell that ran `umask 022` earlier would leak the
  CA's intermediate working files world-readable.
- **`CA_DIR` chmod `0700`.** The CA private key (`ca-key.pem`) is the root
  of trust for every Docker daemon and client in this lab. If any other
  local user can read it, they can mint a valid client cert and connect to
  Docker as root. Closing the directory closes the directory traversal as
  well as the file.
- **`basicConstraints = critical, CA:TRUE, pathlen:0`.** Marks the cert as
  a CA (so OpenSSL accepts signatures from it), but `pathlen:0` forbids it
  from issuing **intermediate** CAs — only end-entity (leaf) certs. This
  matches how the issue scripts use it and prevents accidental
  delegation.
- **`keyUsage = critical, keyCertSign, cRLSign`.** Restricts what the CA
  key can do at the X.509 layer: sign certs and sign CRLs only. No data
  signing, no key encipherment. Marking it `critical` means any client
  that doesn't understand `keyUsage` must reject the cert.
- **Random serial-number prefix.** The original script started serial at
  `1000` and incremented. Predictable serials make CRL-style revocation
  attacks marginally easier and reduce uniqueness across multiple labs.
  We seed serial with `openssl rand -hex 4`.

Pre-existing CAs created by the older script keep working; only
`FORCE=1` re-init writes the new format.

---

## Revocation / rotation runbook

This lab CA is intentionally minimal — there is no OpenSSL `index.txt` CA
database, so a full CRL-based revocation flow is not in scope. For a
compromised client cert (laptop lost, key leaked, contractor offboarded),
the supported response is **rotation**: re-issue the affected leaves, or
in the worst case rotate the CA itself.

Choose the smallest blast radius:

### A. One client compromised (most common)

```bash
# 1. Revoke from the daemon's perspective by removing the offender from the
#    list of clients you trust — the simplest control here is just to NOT
#    re-issue it. There is no per-leaf revocation without a CRL.
# 2. Re-issue a fresh cert for that client name with FORCE=1:
FORCE=1 CLIENT_NAME=otsmbpro16 \
  bash /volume1/certs/acme/docker-mtls-issue-client.bash
# 3. On the affected client, replace the cert in its dedicated context dir:
CTX_DIR="$HOME/.docker/contexts/otsorundscore-mtls"
install -m 0644 /Volumes/certs/acme/docker-mtls/clients/otsmbpro16/cert.pem "$CTX_DIR/cert.pem"
install -m 0400 /Volumes/certs/acme/docker-mtls/clients/otsmbpro16/key.pem  "$CTX_DIR/key.pem"
docker --context otsorundscore-mtls version
```

> **Limitation:** the _old_ client cert is still valid against the daemon
> until it expires (`DAYS=825` by default) because there is no published
> CRL. If the threat is real, follow path **C** (rotate the CA) — the only
> ironclad way to invalidate every cert previously signed by this CA.

### B. Daemon server cert compromised

```bash
FORCE=1 HOSTNAME=otsorundscore.olutechsys.com SAN_IPS=10.0.1.15 \
  bash /volume1/certs/acme/docker-mtls-issue-server.bash
DOCKER_HOSTNAME=otsorundscore.olutechsys.com \
  bash /Volumes/certs/acme/deploy-otsorundscore-mtls.bash
# Then re-apply the daemon config on the NAS using the temp-file merge in
# "otsorundscore — Docker mTLS bundle" and restart ContainerManager.
```

Clients keep their old certs; only the server changed.

### C. CA private key compromised — full rotation

This is the nuclear option and the only way to invalidate every cert this
CA ever signed.

```bash
# 1. (Recommended) Keep an SSH context working as a fallback so you can
#    still reach the daemon if mTLS breaks mid-rotation.
docker --context otsorundscore-ssh info

# 2. Re-init the CA from scratch (this writes a NEW key+cert with a new
#    subjectKeyIdentifier; everything signed by the old CA stops chaining).
FORCE=1 bash /volume1/certs/acme/docker-mtls-init-ca.bash

# 3. Re-issue the daemon server cert for every Docker host.
FORCE=1 HOSTNAME=otsorundscore.olutechsys.com SAN_IPS=10.0.1.15 \
  bash /volume1/certs/acme/docker-mtls-issue-server.bash

# 4. Re-issue every client cert (one per device/operator).
for c in otsmbpro16 hpdevcore; do
  FORCE=1 CLIENT_NAME="$c" \
    bash /volume1/certs/acme/docker-mtls-issue-client.bash
done

# 5. Stage and re-apply the mTLS daemon bundle on the NAS, then restart.
DOCKER_HOSTNAME=otsorundscore.olutechsys.com \
  bash /Volumes/certs/acme/deploy-otsorundscore-mtls.bash
# (see "otsorundscore — Docker mTLS bundle" for the on-NAS apply step)

# 6. On every client, re-install the new ca/cert/key under
#    ~/.docker/contexts/otsorundscore-mtls/. The daemon will reject the old
#    client certs immediately because the CA chain no longer matches.
```

### Emergency containment (no rotation yet)

If you can't rotate immediately and a leak is suspected, narrow the
network surface first — that buys time:

```bash
# On otsorundscore: re-merge daemon-tls/mtls config with hosts pinned to
# 127.0.0.1 (no LAN listener), then restart. This breaks remote LAN
# Docker access entirely until rotation is complete.
TMP=$(sudo mktemp /volume1/​docker/.daemon.json.XXXXXX)
sudo jq '.hosts = ["unix:///var/run/docker.sock", "tcp://127.0.0.1:2376"]' \
  /volume1/​docker/daemon.json > "${TMP}"
sudo mv -f "${TMP}" /volume1/​docker/daemon.json
sudo synopkg restart ContainerManager
```

---

## What this stack manages

| Component                              | Cert                                                | Auto-renewed                  | Deployed by                      |
| -------------------------------------- | --------------------------------------------------- | ----------------------------- | -------------------------------- |
| DSM HTTPS — otsorundscore              | `wildcard/` (`*.olutechsys.com`)                    | acme.sh                       | `deploy-otsorundscore.bash`      |
| DSM HTTPS — misfitsds                  | `wildcard/` (`*.olutechsys.com`)                    | acme.sh                       | `deploy-misfitsds.bash`          |
| Docker daemon TLS — otsorundscore      | `wildcard/fullchain.pem`                            | acme.sh                       | `deploy-otsorundscore.bash`      |
| Docker daemon mTLS — otsorundscore     | `docker-mtls/servers/otsorundscore.olutechsys.com/` | local `docker-mtls-*` scripts | `deploy-otsorundscore-mtls.bash` |
| DSM cert slot — otsorundscore services | `otsorundscore-sub/`                                | acme.sh                       | `deploy-otsorundscore.bash`      |
| DSM cert slot — misfitsds services     | `misfitsds-sub/`                                    | acme.sh                       | `deploy-misfitsds.bash`          |
| MacBook (otsmbpro16)                   | `otsmbpro16/`                                       | acme.sh                       | `deploy-otsmbpro16.bash`         |
| Laptop (hpdevcore)                     | `hpdevcore/`                                        | acme.sh                       | `deploy-hpdevcore.bash`          |
| OTS namespace services                 | `ots-sub/` (`*.ots.olutechsys.com`)                 | acme.sh                       | Traefik le-dns resolver          |
| MFT namespace services                 | `mft-sub/` (`*.mft.olutechsys.com`)                 | acme.sh                       | Traefik le-dns resolver          |

The previous local CA codebase (`setup-docker-tls.bash`, `deploy-nas-cert.bash`)
has been retired and archived to `/volume1/certs/archives/scripts-2026-04-27/`.
Recommended posture, in order:

- **SSH context** — preferred default for admin access. Works without any
  Docker TCP listener at all and is unaffected by `daemon.json` `hosts`.
- **mTLS** (`daemon-mtls.json`, `tlsverify: true`, client cert required) —
  use only when remote TCP is genuinely needed. Defaults to the safe
  loopback bind `tcp://127.0.0.1:2376`; widen to a narrow lab bind
  (e.g. `tcp://10.0.1.15:2376` for otsorundscore) only with a matching
  firewall rule.
- **TLS-only** (`daemon-tls.json`, `tlsverify: false`) — **legacy/lab-only**,
  retained for back-compat. Same loopback default in the reference file;
  treat as remote root if a TCP listener is reachable without client
  auth. Prefer SSH or mTLS instead.
