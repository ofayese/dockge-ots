# Olutech Homelab — Dockge Stack Repo

Dockge Compose stack definitions for two Synology NAS hosts (OTS and MFT), plus **`stacks/_haproxy/`** for the optional Synology HAProxy edge. The Dockge **host** container is **not** a stack here: it is started by [`scripts/dockge-start.sh`](scripts/dockge-start.sh) (install to rc.d). TLS is issued with **`acme-sh`** (DNS-01) to **`/volume1/certs/acme/`**; Traefik and HAProxy consume those PEMs. Full architecture and hive milestones: [`HIVE_OBJECTIVE.md`](HIVE_OBJECTIVE.md).

| NAS | Hostname                    | LAN IP      | DNS namespace          |
| --- | --------------------------- | ----------- | ---------------------- |
| OTS | `otsorundscore.synology.me` | `10.0.1.15` | `*.ots.olutechsys.com` |
| MFT | `misfitsds.synology.me`     | `10.0.1.24` | `*.mft.olutechsys.com` |

---

## 1. After a NAS reset: bring-up order

Do these in order. Long command sequences live in linked docs—do not skip them.

1. **Container Manager** — Install from DSM Package Center.
2. **SSH** — Enable for your operator user; install Git if you use NAS-side `git pull` ([`docs/hive/NAS_DEPLOYMENT.md`](docs/hive/NAS_DEPLOYMENT.md) covers `safe.directory`, SSH keys, and DSM quirks).
3. **Clone** — `git clone git@github.com:ofayese/dockge-ots.git /volume1/docker/dockge` then `cd /volume1/docker/dockge`. If Git reports dubious ownership:
   `git config --file .git/config --add safe.directory /volume1/docker/dockge`
4. **Bootstrap dirs** — `sudo bash scripts/init-nas.sh` (creates `STACK_ROOT` paths, writes repo `.env`; see [`scripts/README.txt`](scripts/README.txt)).
5. **Dockge host** — `sudo cp scripts/dockge-start.sh /usr/local/etc/rc.d/dockge.sh && sudo chmod +x /usr/local/etc/rc.d/dockge.sh && sudo sh /usr/local/etc/rc.d/dockge.sh`. Verify **`5571` → `5001`** and HTTP: [`scripts/dockge-start.sh`](scripts/dockge-start.sh), [`scripts/check-dockge-http.sh`](scripts/check-dockge-http.sh).
6. **acme-sh** — `cd stacks/acme-sh`, `cp .env.example .env`, set **`CF_Token`**, `docker compose up -d`. Create **`/volume1/certs/acme/...`** dirs and run **`--issue` / `--install-cert`** for all bundles: [`stacks/acme-sh/SETUP.md`](stacks/acme-sh/SETUP.md) (**Issue all certs**, **Configure output paths**). Seven cert profiles: wildcard, otsorundscore-sub, misfitsds-sub, otsmbpro16, hpdevcore, ots-sub, mft-sub. Check: `sudo docker exec AcmeSh acme.sh --list`.
7. **Traefik** — Deploy **`stacks/traefik-ots/`** (and **`traefik-mft/`** on MFT) **only after** PEMs exist; wrong or missing **`ACME_CERT_ROOT`** ⇒ browser sees self-signed. Flow: [`docs/hive/NAS_DEPLOYMENT.md`](docs/hive/NAS_DEPLOYMENT.md) (Traefik section). Ping: `docker exec traefik-ots wget -qO- http://127.0.0.1:8080/ping`.
8. **Other stacks** — Dockge UI `http://<NAS>:5571`: per stack `cp .env.example .env`, secrets, deploy. Suggested order: Portainer → acme-sh → Traefik → rest.
9. **HAProxy** — Synology **HAProxy** package: point **`-f`** at [`stacks/_haproxy/haproxy.cfg`](stacks/_haproxy/haproxy.cfg) or **`include`** it from [`/volume1/docker/haproxy.cfg`](docs/hive/NAS_DEPLOYMENT.md). **`stacks/_haproxy/certs/`** must contain **only** combined **`.pem`** files (no README). Build bundles from acme output then validate:
   `sudo /volume1/@appstore/haproxy/sbin/haproxy -c -f /volume1/@appdata/haproxy/haproxy.cfg`
   Details: [`stacks/_haproxy/README.txt`](stacks/_haproxy/README.txt), [`docs/hive/NAS_DEPLOYMENT.md`](docs/hive/NAS_DEPLOYMENT.md).

---

## 2. Dockge (host)

- Image **`louislam/dockge:1`** (not **`:base`**).
- Publish **`5571:5001`** (host 5571 → container 5001). Wrong **`5571:5571`** breaks the UI; the start script recreates the container when the binding is wrong.
- Local probe: `curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5571/` → **200** or **302**.

---

## 3. Certificates (acme-sh)

- Container name **`AcmeSh`**.
- PEMs under **`/volume1/certs/acme/<profile>/`** per [`stacks/acme-sh/SETUP.md`](stacks/acme-sh/SETUP.md).
- Issue with **`--issue`**, wait for DNS-01 (~2 min), then **`--install-cert`**; daemon renews (~60 days)—no extra cron if the container stays up.

---

## 4. Traefik

- Stacks **`traefik-ots`** / **`traefik-mft`**; services join via **labels** + **`traefik-ots`** network.
- **Hard dependency:** acme-sh issued certs and **`ACME_CERT_ROOT`** correct before first meaningful TLS.

---

## 5. HAProxy

- Package on DSM, not Compose. Canonical config: [`stacks/_haproxy/haproxy.cfg`](stacks/_haproxy/haproxy.cfg); host map [`stacks/_haproxy/maps/host.map`](stacks/_haproxy/maps/host.map).
- Example bundle for HAProxy **`crt`** directory (one file per hostname/SNI bundle):

```bash
sudo sh -c 'cat /volume1/certs/acme/ots-sub/fullchain.pem /volume1/certs/acme/ots-sub/privkey.pem > /volume1/docker/dockge/stacks/_haproxy/certs/ots.olutechsys.com.pem'
```

- Adjust source paths to the acme profile you use; paths must match what acme-sh installed.

---

## 6. Namespace and DNS

`*.ots.olutechsys.com` targets the OTS NAS (Traefik / published ports); `*.mft.olutechsys.com` targets MFT. Cloudflare records for ACME are typically **DNS-only** (grey cloud) for DNS-01. Adding a service behind Traefik is usually **labels + network**, not a new public DNS name. Full inventory: [`docs/hive/SERVICE_MAP.md`](docs/hive/SERVICE_MAP.md); zone data: [`docs/hive/dns/olutechsys.com.zone`](docs/hive/dns/olutechsys.com.zone).

---

## 7. Day-to-day

- **Sync:** on NAS `cd /volume1/docker/dockge && git pull`; after new stack folders, `sudo bash scripts/init-nas.sh` or `bash scripts/init-nas.sh --if-changed` — see [`docs/hive/NAS_DEPLOYMENT.md`](docs/hive/NAS_DEPLOYMENT.md) **Keeping the NAS in sync**.
- **New stack:** add `stacks/<name>/`, extend **`STACK_MANIFEST`** in [`scripts/init-nas.sh`](scripts/init-nas.sh), run init, deploy in Dockge.
- **Layout guard:** `bash scripts/verify-repo-layout.sh` (CI). Hive docs live under **`docs/hive/`**, not under **`stacks/docs/`**.
- **Permissions:** `sudo bash scripts/fix-permissions.sh` on the NAS when bind mounts need **`root:root`**.

---

## 8. Port quick reference

| Service       | Host port     | Notes                                                                             |
| ------------- | ------------- | --------------------------------------------------------------------------------- |
| Dockge UI     | **5571**      | Maps to container **5001** (not DSM **5001**)                                     |
| Portainer     | **9443**      | HTTPS                                                                             |
| DSM           | **5000/5001** | Synology — do not confuse with Dockge                                             |
| Traefik ping  | **8080**      | In-container; lock down for prod                                                  |
| HAProxy HTTPS | **443**       | Package listener                                                                  |
| HAProxy HTTP  | **8080**      | Redirect to HTTPS in [`stacks/_haproxy/haproxy.cfg`](stacks/_haproxy/haproxy.cfg) |

---

## 9. Key scripts and files

| Path                                                                           | Role                         |
| ------------------------------------------------------------------------------ | ---------------------------- |
| [`scripts/dockge-start.sh`](scripts/dockge-start.sh)                           | Dockge host container (rc.d) |
| [`scripts/init-nas.sh`](scripts/init-nas.sh)                                   | Post-clone dirs + `.env`     |
| [`scripts/fix-permissions.sh`](scripts/fix-permissions.sh)                     | Bind-mount ownership         |
| [`scripts/compose-validate.sh`](scripts/compose-validate.sh)                   | All Compose files (CI)       |
| [`scripts/check-dockge-http.sh`](scripts/check-dockge-http.sh)                 | Probe Dockge on 5571         |
| [`scripts/verify-repo-layout.sh`](scripts/verify-repo-layout.sh)               | Hive / stack path guard      |
| [`scripts/validate-haproxy-proposal.sh`](scripts/validate-haproxy-proposal.sh) | HAProxy `-c` off-box         |
| [`stacks/acme-sh/SETUP.md`](stacks/acme-sh/SETUP.md)                           | Cert issue/install runbook   |
| [`docs/hive/NAS_DEPLOYMENT.md`](docs/hive/NAS_DEPLOYMENT.md)                   | Full NAS reference           |
| [`AGENTS.md`](AGENTS.md)                                                       | Agent memory and conventions |

---

## 10. Troubleshooting (short)

| Symptom                          | Likely cause                                   | Action                                                                                                        |
| -------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Dockge dies / wrong port         | **`5571:5571`**                                | `docker stop Dockge && docker rm Dockge`, rerun [`scripts/dockge-start.sh`](scripts/dockge-start.sh) via rc.d |
| Traefik self-signed              | Certs not issued or wrong **`ACME_CERT_ROOT`** | [`stacks/acme-sh/SETUP.md`](stacks/acme-sh/SETUP.md), restart Traefik                                         |
| HAProxy **no start line**        | Non-`.pem` in **`stacks/_haproxy/certs/`**     | Remove stray files; PEMs only                                                                                 |
| HAProxy **no SSL certificate**   | Empty **`certs/`**                             | Install PEM bundles (see §5)                                                                                  |
| **`git pull`** dubious ownership | Owner ≠ git user                               | `git config --file .git/config --add safe.directory /volume1/docker/dockge`                                   |
| **`publickey`** as root          | Root has no GitHub key                         | Run **`git`** as the DSM user with **`~/.ssh`** keys                                                          |

---

## 11. Security notes (router / edge)

Keep NFS off on the router USB app if unused; block **rpcbind** on WAN where applicable; disable **FTP** to WAN; use HTTPS for router admin. Renew router/Let’s Encrypt certs before expiry (see your router docs).

---

## Repository layout

- **`stacks/`** — **23** Dockge stack folders (see [`HIVE_OBJECTIVE.md`](HIVE_OBJECTIVE.md)) plus **`_haproxy/`** (HAProxy config, **`certs/`**, **`maps/`**).
- **`docs/hive/`** — Operator docs (**`NAS_DEPLOYMENT.md`**, **`SERVICE_MAP.md`**, proposals).
- **`scripts/`** — Bootstrap, Dockge, validation, permissions.
- **`AGENTS.md`** / **`HIVE_OBJECTIVE.md`** — Agent context and architecture brief.
