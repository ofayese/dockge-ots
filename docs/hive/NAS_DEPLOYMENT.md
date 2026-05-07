# NAS deployment (Synology + Dockge)

## Overview

The repo lives on a Mac (or other dev machine). The NAS receives it via `git clone`. Git operations are Mac-only when SMB or DSM constraints apply; prefer an SSH session on the NAS using a path on local BTRFS (not SMB) when you must run `git` on the NAS.

## Initial NAS deployment

1. On Mac: push latest changes.
2. SSH into the NAS.
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
- **HAProxy (Dockge-bound layout):** Canonical body is **[stacks/_haproxy/haproxy.cfg](../../stacks/_haproxy/haproxy.cfg)** (next to **`certs/`** and **`maps/`**). The hive proposal path **[docs/hive/proposals/_haproxy/haproxy.cfg](proposals/_haproxy/haproxy.cfg)** is an **`include`** wrapper only. **Do not** keep a copy under **`${STACK_ROOT}/docs/`** (e.g. **`…/stacks/docs/hive/…`**) — that layout is invalid; hive docs belong only at **`<repo-root>/docs/hive/`** (see **`AGENTS.md`** audit). It binds **`*:443`** with TLS from **`${STACK_ROOT}/_haproxy/certs/`** and routes by **`${STACK_ROOT}/_haproxy/maps/host.map`**. **`init-nas.sh`** creates **`stacks/_haproxy/{certs,maps}`** via **`_haproxy:certs,maps`**. If the NAS (or Synology HAProxy) already uses **`/volume1/docker/haproxy.cfg`** next to the repo root, either (a) change the service to **`haproxy -f /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg`**, or (b) replace that file with a one-line **`include /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg`**, or (c) keep local-only stanzas in **`/volume1/docker/haproxy.cfg`** and **`include`** the stacks file from there — avoid duplicating backends in two places. Run **`bash scripts/validate-haproxy-proposal.sh`** off-box or **`haproxy -c -f`** on the NAS before reload; open **DSM → Security → Firewall** for **443** (and **8080** for redirect). **Traefik** stacks stay separate; **`dockge-be`** → **`10.0.1.15:5571`**.

## If your Dockge path differs from the default

Run with an override before or during init:

```bash
STACK_ROOT_OVERRIDE=/volume1/docker/dockge/stacks \
  sudo bash scripts/init-nas.sh
```

## Known outstanding issues

### Router SSL certificate (batcavegtaxe16k.asuscomm.com)

The GT-AXE16000 router admin certificate (Let's Encrypt on the ASUS DDNS hostname) **expired 2025-06-06**. The UI remains reachable at **`https://10.0.1.1:8443`** but browsers show an expired cert. Renew from the router: **Administration → System** and use the control next to the certificate (“click here to manage” / ASUS certificate UI), or trigger renewal from the DDNS / certificate page. The DDNS hostname must resolve to the current WAN IP for validation to succeed.

## Keeping the NAS in sync

Preferred: SSH into NAS → `cd /dockge` → `git pull`.

If **`git pull`** fails with **detected dubious ownership**, the repo directory is owned by another user (often **root** after `sudo` operations) while you run **git** as your login user. Either mark the path trusted once (per user):

```bash
git config --global --add safe.directory /volume1/docker/dockge
```

(use your real repo path if it differs), or align ownership with your NAS Git workflow (see **`scripts/fix-permissions.sh`** / operator policy for **`${STACK_ROOT}`** vs repo root).

If **`git pull`** fails with **`Permission denied (publickey)`** against **`git@github.com`**, you are running **git** as a user whose **`~/.ssh`** has no key **GitHub** accepts (common when using **`sudo su`** / **root**: root’s **`~/.ssh`** is not the same as your DSM user’s). Prefer **`git pull`** as the **same DSM account** that owns the deploy SSH key, or add a **read-only deploy key** for this repo (GitHub → **Settings → Deploy keys**) and install its private key only for the user that runs **`git pull`**. Alternatively switch **`origin`** to **HTTPS** and use a **fine-grained PAT** with **`repo`** scope (store via DSM / `git credential` — never commit tokens).

If new stacks were added: re-run `sudo bash scripts/init-nas.sh` so new volume directories exist.

For scheduled or post-receive runs (safe to call repeatedly):

```bash
bash scripts/init-nas.sh --if-changed
```

Hashes **`init-nas.sh` itself** (via `$0`). Skips `.env` writes, `mkdir`, and `fix-permissions.sh` when the script file has not changed since the last **successful** run. The hash is written **only** after a successful full init — a failed run never poisons the stored marker, so the next `--if-changed` retries.

For forced full re-init (after adding new stacks or changing `STACK_MANIFEST` in `init-nas.sh`):

```bash
sudo bash scripts/init-nas.sh
```

Alternative rsync (if git on NAS is impractical):

```bash
rsync -av --delete --exclude='.git' --exclude='.env' \
  ~/path/to/repo/ <user>@<nas-ip>:/dockge/
```

Then: `sudo bash scripts/init-nas.sh`

## Git safety on the NAS

### Never use `git add -A` or `git add .` on the NAS

The NAS working tree always contains untracked runtime dirs (`.env` files, `data/`, `logs/`, `secrets/`, `.claude-flow/`, `.cursor/`) that must never enter the repo. Always use:

```bash
git status --short          # review before any add
git add <specific-file>    # stage only what you intend
```

If you accidentally stage a secrets file:

```bash
git rm --cached <file>
echo "<file-pattern>" >> .gitignore
git add .gitignore
git commit -m "chore: untrack <file>"
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

```bash
git-pull-nas() {
  find /volume1/docker/dockge/.git/refs -name "*eaDir*" \
    | xargs rm -f 2>/dev/null
  git -C /volume1/docker/dockge pull --no-rebase
}
```

### Ownership fix before git operations

After any `sudo docker compose` operation, files in the repo dir may be owned by root. Fix before `git pull`:

```bash
sudo chown -R laolufayese:users /volume1/docker/dockge
```

## Git workflow options

### Option A — GitHub as remote (default, no extra packages needed)

Mac → `git push` → GitHub → NAS `git pull` (manual or scheduled).

### Option B — NAS Git Server as remote (Synology Git Server package)

Mac → `git push` → NAS Git Server → post-receive hook auto-deploys.

To set up Option B:

1. Install Synology Git Server from Package Center.
2. Create a bare repo on the NAS:

   ```bash
   ssh <user>@<nas-ip>
   git init --bare /volume1/git/dockge.git
   ```

3. Add a post-receive hook:

   ```bash
   cat > /volume1/git/dockge.git/hooks/post-receive << 'EOF'
   #!/usr/bin/env bash
   set -euo pipefail
   WORKING_COPY="/dockge"
   echo "Post-receive: updating working copy..."
   git -C "$WORKING_COPY" pull --ff-only
   bash "$WORKING_COPY/scripts/init-nas.sh" --if-changed
   echo "Deploy complete."
   EOF
   chmod +x /volume1/git/dockge.git/hooks/post-receive
   ```

4. On Mac: `git remote add nas ssh://<user>@<nas-ip>/volume1/git/dockge.git`
5. `git push nas main`

### Option C — GitHub Desktop stack (browser-based)

Access `https://<NAS_IP>:3405` and use the GUI to clone, commit, and push the repo directly from the NAS browser interface. No SSH required. See [stacks/github-desktop/README.md](../stacks/github-desktop/README.md).

### Git on NAS — policy

Options B and C enable full git operations on the NAS. The Mac remains the primary development environment. Never `git push` from the NAS if the Mac has unpushed commits — pull first.

## Volume paths

All writable data lives under `${STACK_ROOT}/<stack>/<sub-folder>`. The resolved absolute path is written to repo-root `.env` by `init-nas.sh`. Do not edit `.env` manually — re-run `init-nas.sh` to align `STACK_ROOT` and defaults.

### Restart policy

Stacks use **`restart: unless-stopped`** by default. One-shot compose services (for example the `mcp-tools-config` Busybox placeholder) use **`restart: "no"`** with an **`# intentional`** comment in the stack `compose.yaml`.

## STACK_ROOT exemptions

The following stacks have **no persistent `${STACK_ROOT}` host bind mounts** and correctly **do not reference `STACK_ROOT`** in `compose.yaml`:

- **agents_gateway_data** — `docker.sock` only
- **it-tools** — no volumes
- **mcp-tools-config** — catalog / one-shot placeholder only
- **openresume** — no volumes
- **warp-main** — no volumes
- **watchtower** — `docker.sock` only

This is expected. Post-change verification that requires `STACK_ROOT` in every `compose.yaml` must **exclude** these stack names (and **portainer**, which uses operator env paths instead).

## Verifying staged directories

### On Mac (development — no filesystem required)

List paths `init-nas.sh` would create under the resolved `STACK_ROOT` (no `mkdir`, no `.env` writes):

```bash
bash scripts/init-nas.sh --list-expected-dirs
```

Line count should match the total number of **comma-separated sub-folders** in `STACK_MANIFEST` (for example `code-server:data,config` counts as **2**).

### On NAS (after running init-nas.sh)

Confirm directories exist on disk:

```bash
find "${STACK_ROOT}" -mindepth 2 -maxdepth 2 -type d | sort
```

The Mac command verifies **manifest** correctness. The NAS command verifies **filesystem** state. Both should describe the same set of paths.

### Manifest exhaustiveness (BSD-safe `diff`)

Compare sorted stack names from `STACK_MANIFEST` against `ls stacks/`, excluding stacks in `MANIFEST_EXEMPT` in `scripts/init-nas.sh` (same names as **STACK_ROOT exemptions** plus **`docker-model-runner`** and **`portainer`**):

```bash
diff \
  <(grep -E '^\s*"[^"]+:' scripts/init-nas.sh \
    | sed -E 's/^[[:space:]]*"([^"]+):.*/\1/' | sort) \
  <(ls stacks/ \
    | grep -vE \
      "^portainer$|^agents_gateway_data$|^it-tools$|\
^mcp-tools-config$|^openresume$|^warp-main$|^watchtower$|\
^docker-model-runner$" \
    | sort)
```

Expected: **empty output** (no diff).

### HIVE_OBJECTIVE.md stack list parity (table row)

Stack names in `HIVE_OBJECTIVE.md` live in a **markdown table** (backtick list in the “Stack folders” row), not as `-` bullets. To compare `ls stacks/` to that list:

```bash
diff \
  <(ls stacks/ | sort) \
  <(grep "Stack folders" HIVE_OBJECTIVE.md \
    | grep -oE '`[a-z][a-z0-9_-]*`' | tr -d '`' | sort -u)
```

Expected: **empty output** (no diff).

## Snapshot Replication (recommended — btrfs volumes only)

Configure Snapshot Replication in DSM to snapshot the shared folder containing `${STACK_ROOT}`:

- **Hourly:** retain 24 snapshots
- **Daily:** retain 7 snapshots
- **Weekly:** retain 4 snapshots

Before running `init-nas.sh` or deploying a new stack, take a manual snapshot: **Snapshot Replication** → select shared folder → **Take Snapshot**.

Snapshots are instant and consume no extra space until data changes. They do **not** replace Hyper Backup — snapshots live on the same disk.

## Hyper Backup (off-device backup)

Back up `${STACK_ROOT}` to a remote destination (Synology C2, S3, Backblaze, another NAS, etc.) on a schedule.

### Database directory exclusions

Running database engines cannot be backed up consistently by file copy. Exclude all `db/` directories from Hyper Backup and use database dumps instead:

| Stack        | Exclude from Hyper Backup      | Backup method                                                                 |
| ------------ | ------------------------------- | ----------------------------------------------------------------------------- |
| zabbix       | `${STACK_ROOT}/zabbix/db`       | `docker exec` Postgres → `pg_dumpall` → backup.sql                            |
| databases    | `${STACK_ROOT}/databases/db`    | `docker exec` on each DB service → vendor dump                                |
| codex-docs   | `${STACK_ROOT}/codex-docs/db`   | `docker exec mongodb mongodump` (compose **service** name `mongodb`)           |
| grafana-prom | `${STACK_ROOT}/grafana-prom/db` | `docker exec postgres pg_dumpall` → backup.sql (only if you add a `db/` bind) |

Default **grafana-prom** compose has **no** Postgres `db/` bind — back up **`data/`** with Hyper Backup; add a row-style dump only if you introduce a DB engine under `db/`.

All data/ and config/ directories are safe to include in Hyper Backup.

The following are also safe to include:

| Path | Contents | Notes |
| --- | --- | --- |
| /volume1/certs/acme/wildcard/ | PEM files | Safe — no live database |
| /volume1/certs/acme/ots-sub/ | PEM files | Safe — no live database |
| /volume1/certs/acme/mft-sub/ | PEM files | Safe — no live database |
| /volume1/certs/acme/otsorundscore-sub/ | PEM files | Safe — no live database |
| /volume1/certs/acme/misfitsds-sub/ | PEM files | Safe — no live database |
| /volume1/certs/acme/otsmbpro16/ | PEM files | Safe — no live database |
| /volume1/certs/acme/hpdevcore/ | PEM files | Safe — no live database |

Note: /volume1/certs/acme/docker-mtls/ (CA private key tree) is also safe to back up but treat as sensitive — restrict Hyper Backup destination access accordingly.

## OTS and MFT namespaces

Two second-level subdomains route traffic to each NAS:

- `*.ots.olutechsys.com` → otsorundscore NAS (`traefik-ots` stack)
- `*.mft.olutechsys.com` → misfitsds NAS (`traefik-mft` stack)

Both are wildcard CNAMEs to the NAS DDNS hostname — no per-service DNS entry is needed. Add a new service by adding Traefik labels to its `compose.yaml` and joining the `traefik-ots` or `traefik-mft` network.

See [docs/hive/SERVICE_MAP.md](SERVICE_MAP.md) for the full service inventory.  
See [docs/hive/dns/olutechsys.com.zone](dns/olutechsys.com.zone) for the DNS zone reference.

## Traefik deployment

Traefik runs as a container on each NAS in its own Dockge stack. It is **not** part of the service stacks — it is a shared infrastructure stack deployed once per NAS.

### Deploy order

1. Deploy `traefik-ots` (or `traefik-mft`) stack first via Dockge.
2. Confirm Traefik is healthy:

   ```bash
   docker exec traefik-ots wget -qO- http://127.0.0.1:8080/ping
   ```

3. Deploy service stacks — they join the `traefik-ots` / `traefik-mft` network and appear in Traefik automatically.

### Cert bind-mount dependency

Traefik reads certs from `/volume1/certs/acme/ots-sub/` (or `mft-sub/`). Issue certs via **acme-sh** before deploying Traefik (see `SETUP.md` in `stacks/acme-sh/`). If the cert path is missing at startup, Traefik starts but serves a self-signed fallback — browsers will warn. Issue the cert first.

### Updating service ports

Edit the service's `compose.yaml` labels:

`traefik.http.services.<name>.loadbalancer.server.port=<port>`

Restart the service container. No Traefik restart needed.

### Security Advisor warning

Traefik mounts `/var/run/docker.sock` read-only. Security Advisor will flag this. It is intentional and documented in `stacks/traefik-ots/compose.yaml` and `stacks/traefik-mft/compose.yaml`.

## Security Advisor warnings

Security Advisor will report the following warnings for this repo. All are intentional and documented here.

| Warning                             | Cause                                                    | Status                                                                                                                                      |
| ----------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Containers running as root (UID 0)  | `PUID`/`PGID` default to `0` across stacks               | Intentional — Synology Docker default. See UID/GID dual-mode docs in stack `.env.example` files and `HIVE_OBJECTIVE.md`.                    |
| `seccomp: unconfined`               | **github-desktop** (Electron / KasmVNC requirement)      | Intentional — documented in `stacks/github-desktop/compose.yaml`.                                                                         |
| `IPC_LOCK` capability               | **github-desktop** (Electron memory locking)             | Intentional — documented in `stacks/github-desktop/compose.yaml`.                                                                         |
| `no-new-privileges` omitted         | **github-desktop** (Electron setuid sandbox vs DSM)    | Intentional — **`bfa07bd`**. Do not re-add NNP. Documented in `stacks/github-desktop/compose.yaml`.                                      |
| `privileged: true` on zabbix-agent2 | Docker agent needs host access for container metrics     | Only relevant if **zabbix-agent2** is uncommented. Document the exception here before enabling. See `stacks/zabbix/compose.yaml` comments. |
| `/var/run/docker.sock` mount        | **traefik-ots** and **traefik-mft** (Docker label discovery) | Read-only (`:ro`). Required for Traefik service auto-discovery. Documented in `compose.yaml`. |

**github-desktop** intentionally **omits** `no-new-privileges:true`: Electron’s setuid sandbox cannot work under `PR_NO_NEW_PRIVS` on typical DSM kernels, which can crash or blank the UI. Other stacks in this repo may still use `no-new-privileges:true` as the fleet baseline.

Acknowledge these in **Security Advisor → Mark as acknowledged**. Do not remove settings from `compose.yaml` solely to silence warnings.

## Native vs Docker alternatives (SynoCommunity)

Some functionality in this repo can be run as native SynoCommunity packages instead of Docker stacks. The Docker stacks remain in the repo for portability and consistency. Choose native if you prefer lower overhead and tighter DSM integration.

| Docker stack              | SynoCommunity alternative      | Notes                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| acme-sh                   | cloudflared (Cloudflare Tunnel) | Cloudflare Tunnel handles external HTTPS without cert management. If using Cloudflare, `acme-sh` is redundant for public-facing certs.                                                                                                                                                                                                                                                                      |
| nginx-proxy-manager       | cloudflared (Cloudflare Tunnel) | Cloudflare Tunnel replaces external reverse proxy. nginx-proxy-manager remains useful for internal routing.                                                                                                                                                                                                                                                                                                  |
| zabbix-agent2 (Docker)    | Zabbix Agent (SynoCommunity)    | Native agent reports to the Zabbix Server container on `127.0.0.1:10051` and sees full DSM host metrics without privileged mode. Docker agent requires privileged + bind mounts to see host resources. Use native for NAS OS-level monitoring; use Docker agent only if you specifically need Docker container metrics in Zabbix. SNMPv3 (already configured) covers NAS hardware health without either. |
| databases (Adminer UI)    | Adminer (SynoCommunity)         | Adminer native package provides the same database management UI without a Docker container.                                                                                                                                                                                                                                                                                                                |
| agents_gateway_data       | —                              | No direct SynoCommunity equivalent.                                                                                                                                                                                                                                                                                                                                                                        |

Installing **cloudflared** (SynoCommunity) natively:

1. Add SynoCommunity repo to Package Center.
2. Install Cloudflare Tunnel package.
3. Configure tunnel via DSM UI or `cloudflared` CLI.
4. Point tunnel to internal services on `localhost:<port>`.

If you do this: disable or remove the **acme-sh** stack (certs no longer needed for public endpoints). nginx-proxy-manager becomes optional.

## SynoCommunity dev tools (install for better NAS workflow)

Synology DSM ships with **bash** already installed — no bash package is needed. Install these from **Package Center → Community** after adding the SynoCommunity repository source:

| Package    | Purpose               | Impact on this repo                                      |
| ---------- | --------------------- | -------------------------------------------------------- |
| **Git**    | `git` client on NAS   | Enables `git pull` / `git push` from NAS (see Git workflow options) |
| **ShellCheck** | Shell script linter | Run `shellcheck` on the NAS itself, not only on Mac      |

**Do not** install a third-party bash package — DSM already includes bash. Installing a third-party bash may create `PATH` conflicts.

## Permissions

```bash
sudo bash scripts/fix-permissions.sh
```

When run with no arguments, `fix-permissions.sh` resolves the repo root (via `HIVE_OBJECTIVE.md`), reads `STACK_ROOT` from repo-root `.env` if present, and otherwise uses `/dockge/stacks`.

```bash
sudo bash scripts/fix-permissions.sh /custom/path
```

Use an explicit path when `.env` is not yet created or you need a one-off target.
