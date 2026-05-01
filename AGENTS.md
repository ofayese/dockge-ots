# AGENTS Memory

## Repo layout (2026-04-30)

- **Git repo root:** `/Volumes/docker/dockge` (NAS: `/volume1/docker/dockge`) — contains `HIVE_OBJECTIVE.md`, `.github/`, `scripts/` (see `scripts/README.txt`), and `stacks/`.
- **Dockge stack root:** `/volume1/docker/dockge/stacks` — compose folders only. Hive docs live at repo `docs/hive/`. `WORKSPACE_PATH` for HolyClaude stays the stack root path.
- **Compose CI:** run `scripts/compose-validate.sh` from any cwd (script locates repo root via `HIVE_OBJECTIVE.md`).
- **Layout guard:** `scripts/verify-repo-layout.sh` (runs in **Stacks compose validate** CI) fails on root-level **`hive/`** (use **`docs/hive/`**) or a repo-root folder whose name duplicates a **`stacks/<stack>/`** child — avoids orphaned duplicates when paths are shown without `stacks/` in multi-root workspaces.
- **NAS permissions:** on DSM, normalize bind-mount ownership with **`scripts/fix-permissions.sh`** (see `HIVE_OBJECTIVE.md` → NAS Deployment Notes). Default **`PUID`/`PGID` (or `SYNO_*`) = `0`** on the NAS unless you override in `.env` for local dev.
- **SMB mounts:** If `stacks/.git` could not be fully removed (Resource busy), delete it when no editors have the volume open, then run `git status` at repo root to confirm Git does not treat `stacks/` as a nested repo.
- **SMB + pre-commit:** Synology SMB mounts often reject in-place writes under `docs/`, `.github/`, and `.cursor/`. `.pre-commit-config.yaml` **excludes** those prefixes from `trailing-whitespace`, `end-of-file-fixer`, and `prettier` so `pre-commit run --all-files` succeeds on `/Volumes/docker/dockge`. Run full markdown/YAML fixups on an APFS clone or on the NAS. **`ruff-format` is omitted** (the only tracked `.py` is `docs/hive/tools/inventory.py`, which is excluded from mutating hooks by path); run `ruff format docs/hive/tools/inventory.py` when needed from a non-SMB checkout.
- **Audit (2026-04-30):** **`stacks/docs` → `../docs` must not exist**; **`stacks/._DAV`** is SMB/Finder noise—delete when idle, never commit. **`.ruff_cache/`** is gitignored. **Compose:** `scripts/compose-validate.sh` passes (includes **`stacks/mcp-tools-config/compose.yaml`** placeholder; **`docker-mcp.yaml`** there remains catalog-only). **Git / `inventory.py`:** if `git pull`/`git merge` fails with **Resource busy** or **EINVAL** on `docs/hive/tools/inventory.py`, close editor handles and retry, or merge from an **APFS git worktree** (`git worktree add -b <tmp-branch> <apfs-path> main` → `git merge origin/main` → `git push origin HEAD:main`). **`origin/main`:** merge `e15c4bd` (includes `1c774b3` — `out_dir` under `repo_root/docs/hive/proposals/…`, not `stacks/…/docs/…`).

## What Works

- [2026-04-30] **Compose validate** lives only at repo root **`scripts/compose-validate.sh`** (not under `stacks/scripts/`). CI runs that path; Dockge stack root stays compose-only.
- [2026-04-30] Keep pre-commit language/file matching type-driven where possible: use `types` / `types_or` for JS/TS, Python, shell, Go, Rust, and PowerShell; only use regex `files` when a stable type tag is unavailable.
- [2026-04-30] For local formatter hooks that depend on host tooling (`gofmt`, `rustfmt`, `dotnet`, `pwsh`), use `language: unsupported` and fail-fast entry checks with explicit install commands so contributors get actionable errors instead of opaque failures.
- [2026-04-30] Keep fast commit loops by putting heavy checks on `pre-push` or `manual` stages (for example, `.NET` analyzer/build gates) while preserving lightweight formatting on default commit stage.
- [2026-04-30] This repo has no Dockerfiles or Go/Rust/.NET sources under version control; keep `.pre-commit-config.yaml` limited to hooks that actually match tracked files so `meta: check-hooks-apply` passes. Re-add language-specific hooks when those paths exist.

## What Failed

- [2026-04-30] Using `language: system` in local hooks is deprecated in modern pre-commit; migrate to `language: unsupported` to avoid forward-compatibility issues.
- [2026-04-30] Relying only on extension regex for shell scripts (for example `.sh` / `.bash`) misses valid shebang scripts without those extensions; prefer `types: [shell]`.

## Recurring Bugs

- [2026-04-30] Teams often hit missing-tool errors in local hooks (`gofmt`, `rustfmt`, `dotnet`, `Invoke-Formatter`). Prevent this by embedding prerequisite checks and install hints directly in each hook `entry`.
- [2026-04-30] Mixed understanding of pre-commit "languages" vs identify "types" causes misconfiguration. Treat runtime `language` (hook execution environment) and file `types` (selection filter) as separate concerns.

## Update Workflow

- [2026-04-30] Run `pre-commit autoupdate` in a dedicated maintenance PR on a regular cadence, then run `pre-commit run --all-files` before merge. Default to tag-based updates; use `--bleeding-edge` only when specifically needed.
- [2026-04-30] Use `agents-memory-updater` as the preferred periodic consolidation path when refreshing repository memory entries.

## Dockge Host Container (2026-04-30)

### Key facts

- **Startup script location (NAS):** `/usr/local/etc/rc.d/dockge.sh` — Synology rc.d; NOT a compose stack.
- **Improved version in repo:** `scripts/dockge-start.sh` — drop-replace for the NAS script; apply with `chmod +x` and test with `sh scripts/dockge-start.sh`.
- **Image:** Original used `louislam/dockge:base` — that is the **builder base layer**, not the application. Correct production image is `louislam/dockge:1` (tracks latest stable, currently `1.5.0`). **Replace `:base` with `:1` on the NAS.**
- **Host port:** `5571` → container port `5001`. The homepage config previously pointed to `5001` (Synology DSM's port) — now corrected to `5571`.
- **Container name:** `Dockge` (capital D). Homepage `server: my-docker` + `container: Dockge` now enabled.
- **Path symmetry (correct):** `/volume1/docker/dockge/stacks:/volume1/docker/dockge/stacks` — inside-path = outside-path as required by Dockge.
- **PUID/PGID:** Added to startup script for correct stack file ownership (`1026`/`100` for `ofayese`/`users`).

### Homepage widget

Added `type: dockge` widget to `homepage/config/services.yaml`. Requires `DOCKGE_USERNAME` and `DOCKGE_PASSWORD` in `homepage/.env` (gitignored). Template keys added to `homepage/.env.example`.

### What to do on the NAS

```bash
# 1. Copy improved script
cp /volume1/docker/dockge/scripts/dockge-start.sh /usr/local/etc/rc.d/dockge.sh
chmod +x /usr/local/etc/rc.d/dockge.sh

# 2. Pull the correct image and recreate container
docker pull louislam/dockge:1
docker stop Dockge && docker rm Dockge
sh /usr/local/etc/rc.d/dockge.sh

# 3. Verify
docker inspect Dockge --format '{{.Config.Image}}'  # → louislam/dockge:1
docker inspect Dockge --format '{{.State.Status}}'   # → running
curl -s http://127.0.0.1:5571/ | head -5             # → HTML response from Dockge
```

### Recurring reminders

- [2026-04-30] Dockge is NOT compose-managed — it is a raw `docker run` container started by a Synology rc.d script. Never try to manage it with `docker compose` from the stacks repo.
- [2026-04-30] `louislam/dockge:base` is a builder image, NOT the Dockge app. Always use `:1` or an explicit semver tag like `:1.5.0` for production.
- [2026-04-30] Dockge host port is **5571**, not 5001. Port 5001 on this NAS is Synology DSM. These two must not be confused in homepage config, HAProxy backends, or siteMonitor entries.
- [2026-04-30] Dockge has a native Homepage widget (`type: dockge`) that shows running/stopped stack counts. Requires login credentials in `.env`.

## Deploy-Readiness Audit (2026-04-30)

### Baseline Status — Dockge stack folders (18 under `stacks/`)

| Stack               | security_opt    | restart                      | healthcheck                | logging   | TZ        | watchtower          | image-pin                                               | README | .env.example | Deploy-Ready |
| ------------------- | --------------- | ---------------------------- | -------------------------- | --------- | --------- | ------------------- | ------------------------------------------------------- | ------ | ------------ | ------------ |
| acme-sh             | ✓               | ✓                            | exception documented       | ✓ applied | ✓         | ✓                   | semver 3.1.3                                            | ✓      | ✓            | ✓            |
| agents_gateway_data | ✓               | ✓                            | —                          | ✓         | —         | ✓                   | semver gateway pin                                      | ✓      | ✓            | ⚠           |
| code-server         | ✓               | always (exception commented) | ✓                          | ✓         | ✓         | ✓                   | semver 4.117.0-39                                       | ✓      | ✓            | ✓            |
| codex-docs          | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | **:latest — OPERATOR PIN NEEDED**                       | ✓      | ✓            | ⚠           |
| databases           | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | semver pinned                                           | ✓      | ✓            | ✓            |
| docker-model-runner | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | semver image pin                                        | ✓      | ✓            | ⚠           |
| dozzle              | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | semver v10.5.1                                          | ✓      | ✓            | ✓            |
| github-desktop      | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | `:latest` — pin for prod                                | ✓      | ✓            | ⚠           |
| grafana-prom        | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | semver pinned                                           | ✓      | ✓            | ✓            |
| holyclaude          | ✓ (mixed)       | ✓                            | —                          | ✓         | ✓         | ✓                   | `:latest` — dev image                                   | ✓      | ✓            | ⚠           |
| homepage            | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | semver v1.12                                            | ✓      | ✓            | ✓            |
| it-tools            | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | semver 2024.10.22                                       | ✓      | ✓            | ✓            |
| mcp-tools-config    | ✓ (placeholder) | `restart: "no"` (one-shot)   | —                          | ✓         | N/A       | N/A                 | `busybox:1.36` + separate **`docker-mcp.yaml`** catalog | ✓      | —            | ⚠           |
| ollama              | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | semver pinned; plain `depends_on` (Synology compat)     | ✓      | ✓            | ✓            |
| openresume          | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | **:latest — OPERATOR PIN NEEDED**                       | ✓      | ✓            | ⚠           |
| portainer           | ✓               | always (CE default)          | ✓                          | ✓         | ✓         | ✓                   | semver 2.41.0-alpine                                    | ✓      | ✓            | ✓            |
| searxng             | ✓               | ✓                            | ✓ (redis)                  | ✓ applied | ✓ applied | ✓                   | searxng: date-tag; valkey: 8-alpine                     | ✓      | ✓            | ✓            |
| warp-main           | ✓               | ✓                            | ✓ (warp + agent + sidecar) | ✓         | partial   | ✓                   | semver / `:latest` mix                                  | ✓      | ✓            | ⚠           |
| watchtower          | ✓               | ✓                            | ✓ applied                  | ✓         | ✓         | N/A (is watchtower) | **:latest — OPERATOR PIN NEEDED**                       | ✓      | ✓            | ⚠           |

### Changes Applied (this session)

- [2026-04-30] `acme-sh/compose.yaml`: Added `logging` block (json-file 10m/3); added inline comment documenting healthcheck exception (network_mode:host + daemon = no socket to probe).
- [2026-04-30] `searxng/compose.yaml`: Added `TZ=America/New_York` + `logging` block to both `redis` and `searxng` services. Both services previously had neither.
- [2026-04-30] `watchtower/compose.yaml`: Added `healthcheck` using `/v1/health` endpoint (no auth required, HTTP API already enabled). probe: `wget -qO- http://127.0.0.1:8080/v1/health`.
- [2026-04-30] `code-server/compose.yaml`: Added inline `# restart: always — documented exception` comment to all three services (code-server, db, phpmyadmin) explaining the baseline deviation.
- [2026-04-30] **`mcp-tools-config`:** Added minimal **`compose.yaml`** (Busybox one-shot) so `scripts/compose-validate.sh` includes the folder; **`docker-mcp.yaml`** stays the Docker Desktop MCP catalog (not Compose). Updated **`docs/hive/COMPOSE_FILENAMES.md`** and **`stacks/mcp-tools-config/README.md`**.
- [2026-04-30] **`warp-main/docker-compose.yaml`:** Added **`healthcheck`** on **`warp-agent`** (`wget` → `http://127.0.0.1:8080/`), aligned with sidecar `WARP_AGENT_PORT=8080`.

### Operator Actions Required (cannot be applied without NAS access)

- [2026-04-30] **codex-docs**: `codexteam/codex.docs:latest` must be pinned. Run on NAS: `docker pull codexteam/codex.docs:latest && docker image inspect --format '{{index .RepoDigests 0}}' codexteam/codex.docs:latest`. Replace `:latest` with `@sha256:<digest>` in compose.yaml. Proposal: `docs/hive/proposals/codex-docs/PROPOSAL.md`.
- [2026-04-30] **openresume**: `xitanggg/open-resume:latest` must be pinned. Same resolution flow as above.
- [2026-04-30] **watchtower**: `containrrr/watchtower:latest` must be pinned to a semver tag (prefer explicit tag over digest so Watchtower can self-identify). Run: `docker pull containrrr/watchtower:latest && docker inspect containrrr/watchtower:latest --format '{{index .RepoTags 0}}'` — use the resolved semver tag if available, else digest.
- [2026-04-30] **Compose `depends_on`:** tracked stacks use **plain** `depends_on` lists (no `condition:`) for **Synology Package Center** `docker compose` compatibility — see `HIVE_OBJECTIVE.md` guardrails.

### What Works

- [2026-04-30] All **18** Dockge stack folders have `README.md` where applicable; **`.env.example`** present for stacks that use env interpolation (`mcp-tools-config` uses **`compose.yaml`** for CI only plus **`docker-mcp.yaml`** catalog; no separate `.env.example` unless operators add one).
- [2026-04-30] Hive `docs/hive/proposals/<stack>/` exists for stacks in the deploy table above (including auxiliary folders); \_baseline and \_haproxy proposals also exist.
- [2026-04-30] No stale `orundscore` hostname (without `ots` prefix) in any live compose file; hive proposal docs only reference the boundary-aware grep pattern in comments, not in live config.
- [2026-04-30] `searxng/searxng` is already pinned to a date-commit tag (`2026.4.29-cba0cffa8`), not `:latest` — this is the correct pattern for SearXNG's rolling release model.
- [2026-04-30] `databases` stack uses Docker secrets (`_FILE` pattern) for all credentials — this is the gold standard for secret handling in this repo.
- [2026-04-30] Watchtower `healthcheck` now uses `/v1/health` (unauthenticated) rather than `/v1/metrics` (auth-gated) — always probe the unprotected liveness endpoint when the service has mixed-auth routes.

### Recurring Issues Found

- [2026-04-30] `:latest` tags on `codex-docs`, `openresume`, and `watchtower` are the only remaining image-pinning violations. All three upstream projects publish date or semver tags — consult Docker Hub before pinning to ensure the tag is stable.
- [2026-04-30] `logging` and `TZ` tend to be forgotten on secondary/sidecar services (redis, agent containers) when the primary service gets them. Always audit every service block in a multi-service compose, not just the main container.

## Stack Operations Memory

- [2026-04-30] Keep HolyClaude runtime privileges enabled by default (`SYS_ADMIN`, `SYS_PTRACE`, `seccomp:unconfined`, `shm_size: 2g`) unless an explicit change request says otherwise.
- [2026-04-30] Default HolyClaude image is `coderluii/holyclaude:latest`; only change image source through an explicit migration decision.
- [2026-04-30] Keep populated `.env` files local-only and never commit secrets to this repository.
- [2026-04-30] Apply baseline-first rollout: do not integrate HAProxy/TLS for any stack until that stack passes baseline acceptance criteria.
- [2026-04-30] HolyClaude persistence requires named volume `cloudcli-data` mounted at `/home/claude/.cloudcli`; verify persistence across rebuild, recreate, and down/up flows (without `-v`).
- [2026-04-30] Validate `.claude-flow` behavior in-container by running `ls /workspace/.claude-flow` and a write/remove test file before marking stack checks complete.
- [2026-04-30] Use absolute notify toggle path `touch /home/claude/.claude/notify-on` because `docker exec` context can resolve `~` to `/root`.
- [2026-04-30] Keep `WORKSPACE_PATH` pointed at the stack root (`/volume1/docker/dockge/stacks` on NAS) so `/workspace/.claude-flow` validation is meaningful.
- [2026-04-30] Reference HolyClaude environment details in `holyclaude/data/claude/CLAUDE.md`; keep this root memory file as the concise operational index.
- [2026-04-30] Keep `.claude-flow` runtime state/log files and `.DS_Store` untracked (`.gitignore`), because these files churn continuously and drown real config/code review signal.
- [2026-04-30] Keep `.claude/settings.local.json` local-only and untracked; it can contain permissive local command policy that should never be committed.
- [2026-04-30] After daemon threshold tuning, verify effective runtime values in startup logs match config intent before relying on automation behavior.
- [2026-04-30] Treat sustained low-memory worker deferrals as an ops gate: pause automation-dependent validation until memory headroom recovers.
