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

## If your Dockge path differs from the default

Run with an override before or during init:

```bash
STACK_ROOT_OVERRIDE=/volume1/docker/dockge/stacks \
  sudo bash scripts/init-nas.sh
```

## Keeping the NAS in sync

Preferred: SSH into NAS → `cd /dockge` → `git pull`.

If new stacks were added: re-run `sudo bash scripts/init-nas.sh` so new volume directories exist.

For scheduled or post-receive runs (safe to call repeatedly):

```bash
bash scripts/init-nas.sh --if-changed
```

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

| Stack      | Exclude from Hyper Backup     | Backup method                                        |
| ---------- | ----------------------------- | ---------------------------------------------------- |
| zabbix     | `${STACK_ROOT}/zabbix/db`     | `docker exec` Postgres → `pg_dumpall` → backup.sql   |
| databases  | `${STACK_ROOT}/databases/db` | `docker exec` on each DB service → vendor dump       |
| codex-docs | `${STACK_ROOT}/codex-docs/db` | `docker exec CodexDocs-MongoDB mongodump`            |

All `data/` and `config/` directories are safe to include in Hyper Backup.

## Security Advisor warnings

Security Advisor will report the following warnings for this repo. All are intentional and documented here.

| Warning                             | Cause                                                    | Status                                                                                                                                      |
| ----------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Containers running as root (UID 0)  | `PUID`/`PGID` default to `0` across stacks               | Intentional — Synology Docker default. See UID/GID dual-mode docs in stack `.env.example` files and `HIVE_OBJECTIVE.md`.                    |
| `seccomp: unconfined`               | **github-desktop** (Electron / KasmVNC requirement)      | Intentional — documented in `stacks/github-desktop/compose.yaml`.                                                                         |
| `IPC_LOCK` capability               | **github-desktop** (Electron memory locking)             | Intentional — documented in `stacks/github-desktop/compose.yaml`.                                                                         |
| `privileged: true` on zabbix-agent2 | Docker agent needs host access for container metrics     | Only relevant if **zabbix-agent2** is uncommented. Document the exception here before enabling. See `stacks/zabbix/compose.yaml` comments. |

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
