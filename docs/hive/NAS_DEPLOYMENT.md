# NAS deployment (Synology + Dockge)

## Overview

The repo lives on a Mac (or other dev machine). The NAS receives it via `git clone`. Git operations are Mac-only when SMB or DSM constraints apply; prefer an SSH session on the NAS using a path on local BTRFS (not SMB) when you must run `git` on the NAS.

## Initial NAS deployment

1. On Mac: push latest changes.
2. SSH into the NAS as an operator account in the `administrators` group.
3. `git clone <repo-url> /dockge` (or wherever Dockge reads stacks from).
4. `cd /dockge`
5. `sudo bash scripts/init-nas.sh`

   This script:

   - Auto-detects where Dockge stores its stacks (repo `stacks/`, sibling `../stacks`, or override).
   - Writes the resolved path to `.env` as `STACK_ROOT`.
   - Creates all volume directories under `STACK_ROOT` listed in `scripts/init-nas.sh`.
   - Runs `scripts/fix-permissions.sh` on that root (when invoked as root).

6. Open Dockge UI and deploy stacks.

## Dockge UI and HAProxy (stretch)

- **Dockge** is started by **`scripts/dockge-start.sh`** (install as `/usr/local/etc/rc.d/dockge.sh`). The container listens on **5001** inside the image; the script publishes **host `5571` → container `5001`**. After any script update, re-run the rc script; the script **recreates** the `Dockge` container if the port binding is wrong (for example after an older `5571:5571` map).
- **Smoke test on the NAS:** `bash scripts/check-dockge-http.sh` (defaults to `http://127.0.0.1:5571/`).
- **HAProxy (Dockge-bound layout):** Canonical body is **[stacks/_haproxy/haproxy.cfg](../../stacks/_haproxy/haproxy.cfg)** (next to **`certs/`** and **`maps/`**). The hive proposal path **[docs/hive/proposals/_haproxy/haproxy.cfg](proposals/_haproxy/haproxy.cfg)** is an **`include`** wrapper only. **Do not** keep a copy under **`${STACK_ROOT}/docs/`** — that layout is invalid; hive docs belong only at **`<repo-root>/docs/hive/`**. It binds **`*:443`** with TLS from **`${STACK_ROOT}/_haproxy/certs/`** and routes by **`${STACK_ROOT}/_haproxy/maps/host.map`**. **`init-nas.sh`** creates **`stacks/_haproxy/{certs,maps}`** via **`_haproxy:certs,maps`**.

### HAProxy Synology package paths (DSM)

| Item | Path |
| --- | --- |
| Binary | `/volume1/@appstore/haproxy/sbin/haproxy` |
| Live config | `/volume1/@appdata/haproxy/haproxy.cfg` |
| Repo config | `/volume1/docker/dockge/stacks/_haproxy/haproxy.cfg` |

Validate: `sudo /volume1/@appstore/haproxy/sbin/haproxy -c -f /volume1/@appdata/haproxy/haproxy.cfg`

**CRITICAL — certs/ directory rule:** `haproxy.cfg` uses `bind *:443 ssl crt stacks/_haproxy/certs/`. HAProxy reads **every non-hidden file** in `certs/` as a PEM bundle. Only `*.pem` files and dotfiles (e.g. `.gitkeep`) are allowed. Any `.txt`, `.md`, or other text file causes:

```
[ALERT] unable to load certificate from file '...README.txt': no start line.
```

**Wiring options (pick one):**

- **Option A:** Point HAProxy service at repo config: `-f /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg`
- **Option B:** Keep `/volume1/docker/haproxy.cfg` as a thin wrapper: `include /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg`

## If your Dockge path differs from the default

Run with an override before or during init:

```bash
STACK_ROOT_OVERRIDE=/volume1/docker/dockge/stacks \
  sudo bash scripts/init-nas.sh
```

## Container access — HTTP vs HTTPS reference

| Container | Port | Protocol | URL | Notes |
| --- | --- | --- | --- | --- |
| Dockge | 5571 | HTTP | `http://10.0.1.15:5571` | Plain HTTP |
| Portainer | 9000 | HTTP | `http://10.0.1.15:9000` | Portainer CE HTTP |
| Portainer | 9443 | HTTPS | `https://10.0.1.15:9443` | TLS — use `https://` |
| Portainer Agent | 9001 | HTTPS (mTLS) | Internal only | Not browser-accessible |
| Dozzle | 8892 | HTTP | `http://10.0.1.15:8892` | Plain HTTP |
| Homepage | 7575 | HTTP | `http://10.0.1.15:7575` | Plain HTTP |
| IT-Tools | 8894 | HTTP | `http://10.0.1.15:8894` | Plain HTTP |
| SearXNG | 8888 | HTTP | `http://10.0.1.15:8888` | Plain HTTP |
| Grafana | 3340 | HTTP | `http://10.0.1.15:3340` | Plain HTTP |
| HolyClaude | 3001 | HTTP | `http://10.0.1.15:3001` | Plain HTTP |
| otsai-webui (Open WebUI) | 8893 | HTTP | `http://10.0.1.15:8893` | Plain HTTP |
| AnythingLLM | 3002 | HTTP | `http://10.0.1.15:3002` | NOT 3001 — conflicts with HolyClaude |
| Qdrant | 6333 | HTTP | `http://10.0.1.15:6333/dashboard` | REST API; requires `QDRANT_API_KEY` if set |
| Pipelines | 9099 | HTTP | `http://10.0.1.15:9099` | Plain HTTP |
| Remotely | 5371 | HTTP | `http://10.0.1.15:5371` | Plain HTTP; TLS at reverse proxy |
| Adminer | 8895 | HTTP | `http://10.0.1.15:8895` | Plain HTTP |
| GitHub Desktop | 3405 | HTTP | `http://10.0.1.15:3405` | KasmVNC web UI |
| Zabbix Web | 8532 | HTTP | `http://10.0.1.15:8532` | Plain HTTP |
| CodexDocs | 8896 | HTTP | `http://10.0.1.15:8896` | Plain HTTP |
| OpenResume | 8889 | HTTP | `http://10.0.1.15:8889` | Plain HTTP |
| Watchtower metrics | 18787 | HTTP | `http://10.0.1.15:18787` | API/metrics |

**"Client sent an HTTP request to an HTTPS server"** — you accessed a TLS port with `http://`. Fix: change to `https://`. Affected ports: **9443** (Portainer HTTPS), **443** (HAProxy HTTPS), **9001** (Portainer Agent — mTLS, not meant for browser `http://`/`https://` checks).

**"server unexpectedly dropped the connection"** — host port published but no container listener. Common causes: stale HAProxy backend port, service not listening on the published host port, or DNS entry mapping to the wrong backend.

## Known outstanding issues

### Router SSL certificate (batcavegtaxe16k.asuscomm.com)

The GT-AXE16000 router admin certificate (Let's Encrypt on the ASUS DDNS hostname) **expired 2025-06-06**. The UI remains reachable at **`https://10.0.1.1:8443`** but browsers show an expired cert. Renew from the router: **Administration → System** and use the control next to the certificate ("click here to manage" / ASUS certificate UI), or trigger renewal from the DDNS / certificate page. The DDNS hostname must resolve to the current WAN IP for validation to succeed.

## DSM reverse proxy + platform hardening checklist

Apply once per NAS (or re-validate after DSM upgrades):

- **HTTP/2:** Control Panel → Network → Connectivity → Enable HTTP/2
- **HTTP compression:** Control Panel → Security → Advanced → Enable HTTP Compression
- **Reuseport:** Control Panel → Network → Connectivity → Enable Reuseport
- **Access Control Profiles:** restrict source IPs per reverse proxy rule
- **DDNS indexing hygiene:** set server header to `noindex` where applicable
- **HSTS:** enable per reverse proxy rule where the upstream is HTTPS-only

### WebSocket requirement (reverse proxy)

Some stacks require WebSocket for core features (`remotely`, `holyclaude`, and similar interactive apps):

1. Control Panel → Login Portal → Advanced → Reverse Proxy
2. Edit target rule
3. Custom Header → Create → **WebSocket**

DSM auto-adds:

- `Upgrade: websocket`
- `Connection: Upgrade`

Without this, SignalR/WebSocket sessions fail behind HTTPS even when regular page loads work.

### Reverse proxy timeout for slow stacks

For database-heavy or slow initialization paths, increase reverse proxy advanced timeouts:

- Proxy connection timeout: **600s**
- Proxy send timeout: **600s**
- Proxy read timeout: **600s**

Path: Control Panel → Login Portal → Advanced → Reverse Proxy → Advanced Settings.

### Reverse proxy 400 Bad Request HTTPS fix

If a container serves HTTPS internally, configure HTTPS consistently in the reverse proxy rule.
Using HTTP to an HTTPS backend can cause immediate `400 Bad Request` responses.

## Keeping the NAS in sync

Preferred: SSH into NAS → `cd /dockge` → `git pull`.

If **`git pull`** fails with **detected dubious ownership**, the repo directory is owned by another user (often **root** after `sudo` operations) while you run **git** as your login user. Either mark the path trusted once (per user):

```bash
git config --file .git/config --add safe.directory /volume1/docker/dockge
```

(Use `--file .git/config` to avoid `~/.gitconfig.lock` issues on DSM.)

If **`git pull`** fails with **`Permission denied (publickey)`** against **`git@github.com`**, you are running **git** as a user whose **`~/.ssh`** has no key **GitHub** accepts (common when using **`sudo su`** / **root**). Prefer **`git pull`** as the **same DSM account** that owns the deploy SSH key.

When root execution is unavoidable and keys only exist in the operator home, preserve SSH identity:

```bash
export GIT_SSH_COMMAND="ssh -i /var/services/homes/laolufayese/.ssh/id_ed25519"
sudo -E git -C /volume1/docker/dockge pull --no-rebase
```

If new stacks were added: re-run `sudo bash scripts/init-nas.sh` so new volume directories exist.

### Full reset helper

For post-reset recovery, prefer `scripts/nas-reset.sh` from `/volume1/docker` to automate:

- archive old clone
- fresh clone
- `.env` restoration (`scripts/restore-env.sh`)
- `init-nas.sh` + permissions normalization

For forced full re-init (after adding new stacks or changing `STACK_MANIFEST` in `init-nas.sh`):

```bash
sudo bash scripts/init-nas.sh
```

## Complete NAS fresh-start sequence (after DSM reset)

### Prerequisites

1. DSM → Package Center → install **Container Manager**
2. SSH as `laolufayese` (Port 28)
3. SSH key setup:
   ```bash
   ssh-keygen -t ed25519 -C "nas-deploy" -f ~/.ssh/id_ed25519
   chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_ed25519
   # Add ~/.ssh/id_ed25519.pub to GitHub Settings → SSH keys
   ssh -T git@github.com  # confirm: Hi ofayese/dockge-ots!
   ```

### Clone and bootstrap

```bash
mkdir -p /volume1/docker
cd /volume1/docker
git clone git@github.com:ofayese/dockge-ots.git dockge
cd /volume1/docker/dockge
# Set safe.directory in repo config (avoids ~/.gitconfig.lock issues)
git config --file .git/config --add safe.directory /volume1/docker/dockge
sudo bash scripts/init-nas.sh
```

### Start Dockge

```bash
sudo cp scripts/dockge-start.sh /usr/local/etc/rc.d/dockge.sh
sudo chmod +x /usr/local/etc/rc.d/dockge.sh
sudo sh /usr/local/etc/rc.d/dockge.sh
# Verify port: docker inspect Dockge shows 5001→5571 binding
# Access: http://10.0.1.15:5571/
```

### Git pull rule (always)

`git pull` must run as `laolufayese` (not root). Root has no GitHub SSH key → Permission denied (publickey). If files are root-owned after docker operations: `sudo chown -R laolufayese:administrators /volume1/docker/dockge` then `git pull`.

## Git safety on the NAS

### Never use `git add -A` or `git add .` on the NAS

The NAS working tree always contains untracked runtime dirs (`.env` files, `data/`, `logs/`, `secrets/`, `.claude-flow/`, `.cursor/`) that must never enter the repo. Always use:

```bash
git status --short          # review before any add
git add <specific-file>    # stage only what you intend
```

### `@eaDir` git ref corruption

Symptom: `fatal: bad object refs/heads/@eaDir/main@SynoEAStream`.

Cause: DSM file indexer enters `.git/refs/heads/` and creates `@eaDir/` subdirectory which git reads as a branch.

Immediate fix:

```bash
find /volume1/docker/dockge/.git/refs -name "*eaDir*" | xargs rm -f
git pull --no-rebase
```

Permanent fix: DSM → Control Panel → Search → Indexed Locations → remove `/volume1/docker` from the list.

### Recommended alias (~/.bashrc on NAS)

DSM symlinks `/bin/sh -> /usr/bin/bash`, and bash invoked as `sh` enters POSIX mode — POSIX mode **rejects hyphens in function names**. Define with underscore, alias with hyphen:

```bash
git_pull_nas() {
    find /volume1/docker/dockge/.git/refs \( -name "*eaDir*" -o -name "*SynoEAStream*" \) -delete 2>/dev/null
    git -C /volume1/docker/dockge pull --no-rebase
}
alias git-pull-nas='git_pull_nas'
```

Keep `~/.profile` minimal — DSM already sources `~/.bashrc` via `/etc.defaults/.bashrc_profile`. Do not source `~/.bashrc` again from `~/.profile` (causes double-parse and duplicate error messages).

### Ownership fix before git operations

After any `sudo docker compose` operation, files in the repo dir may be owned by root. Fix before `git pull`:

```bash
sudo chown -R laolufayese:administrators /volume1/docker/dockge
```

Note: use `administrators` group (not `users` — `users` group has zero members on this NAS).

## Git workflow options

### Option A — GitHub as remote (default)

Mac → `git push` → GitHub → NAS `git pull` (manual or scheduled).

### Option B — NAS Git Server as remote

Mac → `git push` → NAS Git Server → post-receive hook auto-deploys.

### Option C — GitHub Desktop stack (browser-based)

Access `https://<NAS_IP>:3405` and use the GUI. No SSH required.

## Volume paths

All writable data lives under `${STACK_ROOT}/<stack>/<sub-folder>`. The resolved absolute path is written to repo-root `.env` by `init-nas.sh`. Do not edit `.env` manually — re-run `init-nas.sh` to align `STACK_ROOT` and defaults.

Stack-level `.gitignore` files are required for data-heavy stacks (`databases`, `zabbix`, `ollama`, `rag-stack`, `remotely`) so generated runtime/db artifacts never enter git.

## Docker network subnet registry

All container networks must use `172.17.0.0/8` broken into `/24` segments. `192.168.x.x` is **forbidden** — DSM Container Manager auto-assigns from that range for stacks without explicit network blocks.

Always set `name:` explicitly on every `networks:` block. Without it Docker prepends the project name, creating double-name artefacts (e.g. `github-desktop_github-desktop-net` instead of `github-desktop-net`).

| Stack / network | Subnet | Network name |
| --- | --- | --- |
| Docker host bridge (reserved) | `172.17.0.0/16` | `docker0` — **do not use** |
| `github-desktop-net` | `172.20.0.0/24` | `github-desktop-net` |
| `grafana-net` | `172.22.0.0/24` | `grafana-net` |
| `prometheus-net` | `172.22.1.0/24` | `prometheus-net` |
| `portainer-net` | `172.24.0.0/24` | `portainer-net` |
| `dozzle-net` | `172.24.1.0/24` | `dozzle-net` |
| `homepage-net` | `172.24.2.0/24` | `homepage-net` |
| `watchtower-net` | `172.24.3.0/24` | `watchtower-net` |
| `it-tools-net` | `172.24.4.0/24` | `it-tools-net` |
| `databases-net` | `172.25.0.0/24` | `databases-net` |
| `zabbix-net` | `172.25.1.0/24` | `zabbix-net` |
| `searxng-net` | `172.26.0.0/24` | `searxng-net` |
| `ollama-net` | `172.27.0.0/24` | `ollama-net` |
| `rag-net` | `172.28.7.0/24` | `rag-net` |
| `holyclaude` | `172.28.0.0/24` | *(named volume stack — no bridge)* |
| `remotely-net` | `172.28.1.0/24` | `remotely-net` |
| `code-server-net` | `172.28.2.0/24` | `code-server-net` |
| `warp-network` | `172.28.3.0/24` | `warp-network` |
| `agents-net` | `172.28.4.0/24` | `agents-net` |
| `codex-docs-net` | `172.28.5.0/24` | `codex-docs-net` |
| `openresume-net` | `172.28.6.0/24` | `openresume-net` |
| Next free | `172.28.8.0/24+` | — |

To check existing subnets on the NAS before adding a network:

```bash
sudo docker network inspect $(sudo docker network ls -q) \
  --format '{{.Name}}: {{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null | grep -v '^:'
```

### Restart policy

Stacks use **`restart: unless-stopped`** by default. One-shot compose services use **`restart: "no"`** with an **`# intentional`** comment.

## Dockge stack lifecycle (Compose v2)

Tracked multi-service stacks use **`depends_on` … `condition: service_healthy`** so dependents start only after upstream **`healthcheck`** passes. On the NAS, confirm **`docker compose version`** shows **v2.x** (Compose plugin).

### Pick up compose changes (stack already running)

1. `cd /volume1/docker/dockge` (or your clone root on BTRFS-backed paths — avoid SMB for `git` if you hit lock/metadata issues; see **Git safety on the NAS** below).
2. `git pull --no-rebase` (or rsync `stacks/` + `scripts/` from a dev machine, then skip pull).
3. Per stack: `cd stacks/<stack>` (example: `stacks/zabbix`).
4. Optional: `docker compose pull` when `image:` / digests changed.
5. `docker compose up -d` — recreates or starts services; dependents may stay in **starting** until Postgres/Qdrant/Redis/exporters report **healthy** (often 30–120s on first cold start).
6. `docker compose ps` — expect **running** (and **healthy** where defined). If one service is **unhealthy** after roughly twice the slowest **`start_period`**, inspect `docker compose logs <service>`.

If a **web** UI briefly errors on DB while the **server** or **DB** is still importing (Zabbix): wait, then `docker compose restart zabbix-web` (service name may differ — use the service key from `compose.yaml`).

### First bring-up (stack never deployed on this host)

1. Run **`sudo bash scripts/init-nas.sh`** once so `${STACK_ROOT}/…` volume paths exist.
2. In `stacks/<stack>/`: **`cp .env.example .env`**, fill secrets, create any **`secrets/*.txt`** files the README requires.
3. **`docker compose up -d`**.
4. Before sharing URLs, confirm dependencies are **healthy** (`docker compose ps`) for stacks ordered on DB or vector DB (zabbix, rag-stack, databases, grafana-prom, etc.).

### Soft vs hard restart

- **In-place process restart:** `docker compose restart` or `docker compose restart <service>`.
- **Recreate from current compose:** `docker compose up -d --force-recreate` (or `docker compose up -d` after image/env changes — Compose reconciles state).
- **Stop stack, keep data:** `docker compose down` — bind mounts under **`${STACK_ROOT}`** are unchanged unless you delete host dirs.

### Hosts that cannot parse `condition: service_healthy`

Use a local **`compose.override.yaml`** next to **`compose.yaml`** with **plain** `depends_on` lists (Compose merges files), or upgrade the NAS so **`docker compose version`** is v2. Do not commit host-specific overrides that contain secrets.

## Authentication and Identity

→ See [docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md](GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md) for Google Workspace OAuth NAS login guide (Path A: DSM SSO Client, Path B: Synology SSO Server).

## Stack tuning and customisation

→ See [docs/hive/STACK_OPTIMIZATION_CUSTOMIZATION.md](STACK_OPTIMIZATION_CUSTOMIZATION.md) for per-stack tuning knobs for holyclaude, searxng, it-tools, and rag-stack.

## Multi-machine Docker deployment

Three Docker environments use this repo's stacks:

### NAS — otsorundscore (Container Manager / DSM 7.3.2)

Environment: AMD Ryzen R1600, 32 GB, CPU-only, no GPU
Docker: Container Manager (Synology Package Center)
Deploy: Via Dockge at `http://10.0.1.15:5571` or `docker compose` CLI via SSH
Role: Primary inference server, shared RAG backend, offline workspace host
**Compose:** Tracked multi-service stacks use **`depends_on` … `condition: service_healthy`** where dependencies have healthchecks (**Docker Compose v2**). Verify with `docker compose version` on the NAS (e.g. v2.20+). If an older DSM image rejects `condition:`, use plain `depends_on` in a local override or downgrade only that host.
**Constraint:** PUID/PGID default to 0 (root)
Git: DEPLOY ONLY — commit from otsmbpro16, then `git pull` on NAS

### otsmbpro16 — Mac (Apple Silicon)

Docker: Docker Desktop for Mac
Workspace: `/Users/laolufayese` → `/workspace` in HolyClaude
Override in `.env`: `HOLYCLAUDE_WORKSPACE=/Users/laolufayese`
Connects to NAS ollama: `http://10.0.1.15:11434`

### hpdevcore — Windows 11 + WSL2

Docker: Docker Engine in WSL2 (not Docker Desktop for Windows)
Workspace: `/home/laolufayese` → `/workspace` in HolyClaude (recommended)
Alternative workspace: `/mnt/c/Users/laolufayese` (slower I/O — avoid)
Override in `.env`: `HOLYCLAUDE_WORKSPACE=/home/laolufayese`
Connects to NAS ollama: `http://10.0.1.15:11434`

### Connection matrix

| Service | NAS port | otsmbpro16 | hpdevcore |
| --- | --- | --- | --- |
| Ollama API | `10.0.1.15:11434` | ✓ LAN | ✓ LAN |
| Open WebUI | `10.0.1.15:8893` | ✓ LAN | ✓ LAN |
| AnythingLLM | `10.0.1.15:3002` | ✓ LAN | ✓ LAN |
| Qdrant | `10.0.1.15:6333` | ✓ LAN | ✓ LAN |
| HolyClaude | per-machine | `localhost:3001` | `localhost:3001` |

`HOLYCLAUDE_WORKSPACE` is the **only** env var that changes per machine. All other services point to the NAS at `10.0.1.15` from all three machines.

## STACK_ROOT exemptions

The following stacks have **no persistent `${STACK_ROOT}` host bind mounts**:

- **agents_gateway_data** — `docker.sock` only
- **it-tools** — no volumes
- **mcp-tools-config** — catalog / one-shot placeholder only
- **openresume** — no volumes
- **warp-main** — no volumes
- **watchtower** — `docker.sock` only

This is expected. Post-change verification that requires `STACK_ROOT` in every `compose.yaml` must **exclude** these stack names (and **portainer**, which uses operator env paths instead).

## OTS and MFT namespaces

Two second-level subdomains route traffic to each NAS:

- `*.otsorundscore.olutechsys.com` / `*.otsorundscore.olutech.systems` → otsorundscore NAS (HAProxy host map)
- `*.misfitsds.olutechsys.com` / `*.misfitsds.olutech.systems` → misfitsds NAS (HAProxy host map)

Both are wildcard CNAMEs to the NAS DDNS hostname — no per-service DNS entry is needed. Add a new service by publishing a host port and mapping hostname → backend in `stacks/_haproxy/maps/host.map`.

See [docs/hive/SERVICE_MAP.md](SERVICE_MAP.md) for the full service inventory.
See [docs/hive/dns/olutechsys.com.zone](dns/olutechsys.com.zone) for the DNS zone reference.

## HAProxy deployment

HAProxy is the shared HTTPS edge on each NAS. Service stacks publish LAN ports and HAProxy routes hostnames to those backends via `stacks/_haproxy/maps/host.map`.

### Deploy order

1. **Issue and install PEMs** with **`stacks/acme-sh`** first (DNS-01). Keep host-named cert trees (`otsorundscore/`, `misfitsds/`) current.
2. Build/update combined PEM bundles in `stacks/_haproxy/certs/` and validate config:
   ```bash
   sudo /volume1/@appstore/haproxy/sbin/haproxy -c -f /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg
   ```
3. Reload HAProxy.
4. Deploy/update service stacks and host.map/backend entries.

## Security Advisor warnings

Security Advisor will report the following warnings for this repo. All are intentional and documented here.

| Warning | Cause | Status |
| --- | --- | --- |
| Containers running as root (UID 0) | `PUID`/`PGID` default to `0` across stacks | Intentional — Synology Docker default |
| `seccomp: unconfined` | **github-desktop** (Electron / KasmVNC requirement) | Intentional — documented in `stacks/github-desktop/compose.yaml` |
| `IPC_LOCK` capability | **github-desktop** (Electron memory locking) | Intentional — documented in `stacks/github-desktop/compose.yaml` |
| `no-new-privileges` omitted | **github-desktop** (Electron setuid sandbox vs DSM) | Intentional — `bfa07bd`. Do not re-add NNP |
| `privileged: true` on zabbix-agent2 | Docker agent needs host access for container metrics | Only relevant if **zabbix-agent2** is uncommented |

Acknowledge these in **Security Advisor → Mark as acknowledged**. Do not remove settings from `compose.yaml` solely to silence warnings.

## Volume paths

All writable data lives under `${STACK_ROOT}/<stack>/<sub-folder>`. The resolved absolute path is written to repo-root `.env` by `init-nas.sh`. Do not edit `.env` manually — re-run `init-nas.sh` to align `STACK_ROOT` and defaults.

## Snapshot Replication (recommended — btrfs volumes only)

Configure Snapshot Replication in DSM to snapshot the shared folder containing `${STACK_ROOT}`:

- **Hourly:** retain 24 snapshots
- **Daily:** retain 7 snapshots
- **Weekly:** retain 4 snapshots

## Hyper Backup (off-device backup)

Back up `${STACK_ROOT}` to a remote destination on a schedule.

### Database directory exclusions

| Stack | Exclude from Hyper Backup | Backup method |
| --- | --- | --- |
| zabbix | `${STACK_ROOT}/zabbix/db` | `docker exec` Postgres → `pg_dumpall` |
| databases | `${STACK_ROOT}/databases/db` | `docker exec` on each DB service |
| codex-docs | `${STACK_ROOT}/codex-docs/db` | `docker exec mongodb mongodump` |

All `data/` and `config/` directories are safe to include in Hyper Backup.

The following are also safe to include:

| Path | Contents | Notes |
| --- | --- | --- |
| `/volume1/certs/acme/wildcard/` | PEM files | Safe — no live database |
| `/volume1/certs/acme/otsorundscore/` | PEM files | Source for HAProxy-staged OTS cert bundles; safe — no live database |
| `/volume1/certs/acme/misfitsds/` | PEM files | Source for HAProxy-staged MFT cert bundles; safe — no live database |
| `/volume1/certs/acme/otsorundscore-sub/` | PEM files | Optional broader SAN profile; safe — no live database |
| `/volume1/certs/acme/misfitsds-sub/` | PEM files | Optional broader SAN profile; safe — no live database |
| `/volume1/certs/acme/otsmbpro16/` | PEM files | Safe — no live database |
| `/volume1/certs/acme/hpdevcore/` | PEM files | Safe — no live database |

Note: `/volume1/certs/acme/docker-mtls/` (CA private key tree) is also safe to back up but treat as sensitive — restrict Hyper Backup destination access accordingly.

## Permissions

```bash
sudo bash scripts/fix-permissions.sh
```

When run with no arguments, `fix-permissions.sh` resolves the repo root (via `HIVE_OBJECTIVE.md`), reads `STACK_ROOT` from repo-root `.env` if present, and otherwise uses `/dockge/stacks`.

```bash
sudo bash scripts/fix-permissions.sh /custom/path
```

Use an explicit path when `.env` is not yet created or you need a one-off target.
