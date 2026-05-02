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

Alternative rsync (if git on NAS is impractical):

```bash
rsync -av --delete --exclude='.git' --exclude='.env' \
  ~/path/to/repo/ <user>@<nas-ip>:/dockge/
```

Then: `sudo bash scripts/init-nas.sh`

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

## Permissions

```bash
sudo bash scripts/fix-permissions.sh
```

When run with no arguments, `fix-permissions.sh` resolves the repo root (via `HIVE_OBJECTIVE.md`), reads `STACK_ROOT` from repo-root `.env` if present, and otherwise uses `/dockge/stacks`.

```bash
sudo bash scripts/fix-permissions.sh /custom/path
```

Use an explicit path when `.env` is not yet created or you need a one-off target.
