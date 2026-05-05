# Dockge Homelab — OTS / Misfits NAS Stack Repo

This repo manages all Docker Compose stacks for the Olutech Systems homelab across two Synology NAS devices.

| NAS | Hostname | LAN IP | Namespace |
|---|---|---|---|
| OTS | `otsorundscore.synology.me` | `10.0.1.15` | `*.ots.olutechsys.com` |
| Misfits | `misfitsds.synology.me` | `10.0.1.24` | `*.mft.olutechsys.com` |

**Git operations are Mac-only.** The NAS only does `git pull`.

---

## Fresh NAS bring-up (after reset or first deploy)

Work through these steps in order. Each layer depends on the one above it.

### 1. Prerequisites on the NAS

- Container Manager installed (DSM Package Center)
- SSH enabled (DSM → Administration → System → SSH, LAN only)
- SynoCommunity Git package installed (Package Center → Community)

SSH in:
```bash
ssh -p 24 laolufayese@10.0.1.15
```

---

### 2. Clone the repo

```bash
cd /volume1/docker
git clone git@github.com:ofayese/dockge-ots.git dockge
cd /volume1/docker/dockge
git config --file .git/config --add safe.directory /volume1/docker/dockge
```

If you get `Permission denied (publickey)`, your SSH key is not registered with GitHub. Generate and add one:
```bash
ssh-keygen -t ed25519 -C "dockge-nas" -f ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub   # paste into GitHub → Settings → SSH keys
ssh -T git@github.com       # verify: "Hi ofayese/dockge-ots!"
```

---

### 3. Bootstrap stack directories

```bash
sudo bash scripts/init-nas.sh
```

This creates all volume directories under `STACK_ROOT` (`/volume1/docker/dockge/stacks`),
writes `STACK_ROOT` to `.env`, and fixes permissions. Safe to re-run.

---

### 4. Start Dockge

Dockge is **not** a compose stack — it is a raw `docker run` container started by an rc.d script.

```bash
# Install the startup script
sudo cp scripts/dockge-start.sh /usr/local/etc/rc.d/dockge.sh
sudo chmod +x /usr/local/etc/rc.d/dockge.sh

# Start it (script includes sleep 20 for DSM Docker daemon startup)
sudo sh /usr/local/etc/rc.d/dockge.sh
```

Verify it is running with the correct port mapping:
```bash
docker inspect Dockge --format '{{json .HostConfig.PortBindings}}'
# Must show: {"5001/tcp":[{"HostIp":"0.0.0.0","HostPort":"5571"}]}

curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5571/
# Must show: 200 or 302
```

Open in browser: `http://10.0.1.15:5571`

> **If port shows `5571->5571` instead of `5571->5001`:** the old container is still running with the wrong mapping.
> Fix: `docker stop Dockge && docker rm Dockge` then re-run the rc.d script.

---

### 5. Deploy acme-sh and issue TLS certificates

Traefik and HAProxy both require certs. acme-sh must run first.

#### 5a. Configure acme-sh

```bash
cd /volume1/docker/dockge/stacks/acme-sh
cp .env.example .env
nano .env   # set CF_Token (Cloudflare API token, Zone.DNS:Edit on olutechsys.com)
docker compose up -d
docker logs AcmeSh   # confirm daemon running
```

#### 5b. Create cert output directories

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

#### 5c. Issue all certs (wait ~2 min per cert for DNS propagation)

```bash
# Wildcard — *.olutechsys.com
sudo docker exec AcmeSh acme.sh --issue \
  -d '*.olutechsys.com' -d 'olutechsys.com' \
  -d '*.olutech.systems' -d 'olutech.systems' \
  --keylength 2048 --dns dns_cf --server letsencrypt

# OTS namespace — *.ots.olutechsys.com
sudo docker exec AcmeSh acme.sh --issue \
  -d '*.ots.olutechsys.com' \
  --keylength 2048 --dns dns_cf --server letsencrypt

# MFT namespace — *.mft.olutechsys.com
sudo docker exec AcmeSh acme.sh --issue \
  -d '*.mft.olutechsys.com' \
  --keylength 2048 --dns dns_cf --server letsencrypt

# otsorundscore-sub
sudo docker exec AcmeSh acme.sh --issue \
  -d '*.otsorundscore.olutechsys.com' \
  -d '*.otsorundscore.olutech.systems' \
  --keylength 2048 --dns dns_cf --server letsencrypt

# misfitsds-sub
sudo docker exec AcmeSh acme.sh --issue \
  -d 'misfitsds.olutechsys.com' \
  -d '*.misfitsds.olutechsys.com' \
  -d 'misfitsds.olutech.systems' \
  -d '*.misfitsds.olutech.systems' \
  --keylength 2048 --dns dns_cf --server letsencrypt

# otsmbpro16
sudo docker exec AcmeSh acme.sh --issue \
  -d 'otsmbpro16.olutechsys.com' \
  -d 'otsmbpro16.olutech.systems' \
  --keylength 2048 --dns dns_cf --server letsencrypt

# hpdevcore
sudo docker exec AcmeSh acme.sh --issue \
  -d 'hpdevcore.olutechsys.com' \
  -d 'hpdevcore.olutech.systems' \
  --keylength 2048 --dns dns_cf --server letsencrypt
```

#### 5d. Install certs to output paths (run after all issues succeed)

```bash
sudo docker exec AcmeSh acme.sh --install-cert \
  -d '*.olutechsys.com' \
  --cert-file /volume1/certs/acme/wildcard/cert.pem \
  --key-file /volume1/certs/acme/wildcard/privkey.pem \
  --ca-file /volume1/certs/acme/wildcard/chain.pem \
  --fullchain-file /volume1/certs/acme/wildcard/fullchain.pem \
  --reloadcmd "chmod 640 /volume1/certs/acme/wildcard/privkey.pem"

sudo docker exec AcmeSh acme.sh --install-cert \
  -d '*.ots.olutechsys.com' \
  --cert-file /volume1/certs/acme/ots-sub/cert.pem \
  --key-file /volume1/certs/acme/ots-sub/privkey.pem \
  --ca-file /volume1/certs/acme/ots-sub/chain.pem \
  --fullchain-file /volume1/certs/acme/ots-sub/fullchain.pem \
  --reloadcmd "chmod 640 /volume1/certs/acme/ots-sub/privkey.pem"

sudo docker exec AcmeSh acme.sh --install-cert \
  -d '*.mft.olutechsys.com' \
  --cert-file /volume1/certs/acme/mft-sub/cert.pem \
  --key-file /volume1/certs/acme/mft-sub/privkey.pem \
  --ca-file /volume1/certs/acme/mft-sub/chain.pem \
  --fullchain-file /volume1/certs/acme/mft-sub/fullchain.pem \
  --reloadcmd "chmod 640 /volume1/certs/acme/mft-sub/privkey.pem"

sudo docker exec AcmeSh acme.sh --install-cert \
  -d '*.otsorundscore.olutechsys.com' \
  --cert-file /volume1/certs/acme/otsorundscore-sub/cert.pem \
  --key-file /volume1/certs/acme/otsorundscore-sub/privkey.pem \
  --ca-file /volume1/certs/acme/otsorundscore-sub/chain.pem \
  --fullchain-file /volume1/certs/acme/otsorundscore-sub/fullchain.pem \
  --reloadcmd "chmod 640 /volume1/certs/acme/otsorundscore-sub/privkey.pem"

sudo docker exec AcmeSh acme.sh --install-cert \
  -d 'misfitsds.olutechsys.com' \
  --cert-file /volume1/certs/acme/misfitsds-sub/cert.pem \
  --key-file /volume1/certs/acme/misfitsds-sub/privkey.pem \
  --ca-file /volume1/certs/acme/misfitsds-sub/chain.pem \
  --fullchain-file /volume1/certs/acme/misfitsds-sub/fullchain.pem \
  --reloadcmd "chmod 640 /volume1/certs/acme/misfitsds-sub/privkey.pem"

sudo docker exec AcmeSh acme.sh --install-cert \
  -d 'otsmbpro16.olutechsys.com' \
  --cert-file /volume1/certs/acme/otsmbpro16/cert.pem \
  --key-file /volume1/certs/acme/otsmbpro16/privkey.pem \
  --ca-file /volume1/certs/acme/otsmbpro16/chain.pem \
  --fullchain-file /volume1/certs/acme/otsmbpro16/fullchain.pem \
  --reloadcmd "chmod 640 /volume1/certs/acme/otsmbpro16/privkey.pem"

sudo docker exec AcmeSh acme.sh --install-cert \
  -d 'hpdevcore.olutechsys.com' \
  --cert-file /volume1/certs/acme/hpdevcore/cert.pem \
  --key-file /volume1/certs/acme/hpdevcore/privkey.pem \
  --ca-file /volume1/certs/acme/hpdevcore/chain.pem \
  --fullchain-file /volume1/certs/acme/hpdevcore/fullchain.pem \
  --reloadcmd "chmod 640 /volume1/certs/acme/hpdevcore/privkey.pem"
```

#### 5e. Verify

```bash
sudo docker exec AcmeSh acme.sh --list
# Should show 7 rows, all expiring ~90 days out

ls /volume1/certs/acme/ots-sub/
# Should show: cert.pem  chain.pem  fullchain.pem  privkey.pem
```

Full runbook including misfitsds deploy scripts: `stacks/acme-sh/SETUP.md`

---

### 6. Deploy Traefik (OTS NAS)

Certs must exist before this step or Traefik will start with a self-signed fallback.

```bash
cd /volume1/docker/dockge/stacks/traefik-ots
cp .env.example .env
# Edit .env: verify STACK_ROOT and ACME_CERT_ROOT
docker compose up -d

# Verify healthy
docker exec traefik-ots wget -qO- http://127.0.0.1:8080/ping
# Expected: OK
```

---

### 7. Deploy remaining stacks via Dockge

Open `http://10.0.1.15:5571` and deploy stacks in this order:

1. `databases` (if needed by other stacks)
2. `portainer`
3. `watchtower`
4. Service stacks — `homepage`, `searxng`, `dozzle`, etc.

For each stack: copy `.env.example` to `.env` in the stack directory and fill in secrets before deploying.

---

### 8. HAProxy TLS (external HTTPS access)

Build PEM bundles — HAProxy requires fullchain + key concatenated into one file per cert:

```bash
sudo sh -c 'cat /volume1/certs/acme/ots-sub/fullchain.pem \
  /volume1/certs/acme/ots-sub/privkey.pem \
  > /volume1/docker/dockge/stacks/_haproxy/certs/ots.olutechsys.com.pem'

# Validate config syntax
sudo /volume1/@appstore/haproxy/sbin/haproxy -c \
  -f /volume1/@appdata/haproxy/haproxy.cfg
# Expected: Configuration file is valid

# Reload HAProxy from DSM Package Center
```

---

## Day-to-day operations

### Pull latest changes from GitHub

```bash
ssh -p 24 laolufayese@10.0.1.15
cd /volume1/docker/dockge
git pull
sudo bash scripts/init-nas.sh --if-changed   # only runs if init-nas.sh changed
```

### Validate all stacks (Mac)

```bash
bash scripts/compose-validate.sh
pre-commit run --all-files
```

### Fix permissions after git pull (if Docker cannot write to bind mounts)

```bash
sudo bash scripts/fix-permissions.sh
```

### Check Dockge is responding

```bash
bash scripts/check-dockge-http.sh
```

### Check acme-sh cert status

```bash
sudo docker exec AcmeSh acme.sh --list
```

### Force cert renewal

```bash
sudo docker exec AcmeSh acme.sh --renew -d '*.ots.olutechsys.com' --force
```

---

## Port reference

| Service | Host port | Notes |
|---|---|---|
| Dockge | `5571` | Maps to container `5001` — do not confuse with DSM port 5001 |
| Portainer | `9443` | HTTPS |
| HAProxy HTTPS | `443` | External TLS termination |
| HAProxy HTTP | `8080` | Redirects to HTTPS |
| HAProxy stats | `8280` | Internal stats page |
| Traefik HTTPS | `443` | Via HAProxy or direct |
| SSH (NAS) | `24` | Non-default port |
| Router admin | `8443` | HTTPS only |

---

## Key file locations

| What | Path |
|---|---|
| Stack compose files | `/volume1/docker/dockge/stacks/<stack>/compose.yaml` |
| Stack data / config / db | `/volume1/docker/dockge/stacks/<stack>/data\|config\|db/` |
| TLS certs (PEM) | `/volume1/certs/acme/<cert-dir>/` |
| HAProxy config (body) | `/volume1/docker/dockge/stacks/_haproxy/haproxy.cfg` |
| HAProxy TLS bundles | `/volume1/docker/dockge/stacks/_haproxy/certs/` |
| HAProxy host map | `/volume1/docker/dockge/stacks/_haproxy/maps/host.map` |
| Dockge startup script | `/usr/local/etc/rc.d/dockge.sh` (copy of `scripts/dockge-start.sh`) |
| Stack manifest | `scripts/init-nas.sh` → `STACK_MANIFEST` |
| Full NAS deployment docs | `docs/hive/NAS_DEPLOYMENT.md` |
| acme-sh full runbook | `stacks/acme-sh/SETUP.md` |
| Service map | `docs/hive/SERVICE_MAP.md` |
| DNS zone reference | `docs/hive/dns/olutechsys.com.zone` |

---

## Troubleshooting

**Dockge: "connection dropped" on port 5571**
Wrong port mapping (`5571:5571` instead of `5571:5001`).
```bash
docker stop Dockge && docker rm Dockge
sudo sh /usr/local/etc/rc.d/dockge.sh
```

**acme-sh: cert issue fails**
Check `docker logs AcmeSh`. Most common cause: `CF_Token` not set or missing `Zone.DNS:Edit` on `olutechsys.com`.

**Traefik: browser shows certificate warning**
Cert path missing at startup. Issue certs via acme-sh first, then restart:
```bash
docker compose -f /volume1/docker/dockge/stacks/traefik-ots/compose.yaml restart
```

**git pull: "detected dubious ownership"**
```bash
git config --file /volume1/docker/dockge/.git/config \
  --add safe.directory /volume1/docker/dockge
```

**git pull: "Permission denied (publickey)"**
Run `git pull` as `laolufayese`, not as root. Root has no GitHub SSH key.

**HAProxy: "no start line" on cert**
A non-PEM file (e.g. README.txt) is in the `certs/` directory. HAProxy reads every file in that folder as a certificate bundle. Remove the non-PEM file.

**HAProxy: "no SSL certificate specified"**
The `certs/` directory is empty. Build PEM bundles from step 8 above.
