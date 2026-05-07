# AGENTS Memory

## Repo layout (2026-04-30)

- **Git repo root:** `/Volumes/docker/dockge` (NAS: `/volume1/docker/dockge`) — contains `HIVE_OBJECTIVE.md`, `.github/`, `scripts/` (see `scripts/README.txt`), and `stacks/`.
- **Dockge stack root:** `/volume1/docker/dockge/stacks` — compose folders only. Hive docs live at repo `docs/hive/`. `WORKSPACE_PATH` for HolyClaude stays the stack root path. Canonical bind-mount rules: **[CLAUDE.md](CLAUDE.md)** (`## Dockge path layout`).
- **Compose CI:** run `scripts/compose-validate.sh` from any cwd (script locates repo root via `HIVE_OBJECTIVE.md`).
- **Layout guard:** `scripts/verify-repo-layout.sh` (runs in **Stacks compose validate** CI) fails on root-level **`hive/`** (use **`docs/hive/`**) or a repo-root folder whose name duplicates a **`stacks/<stack>/`** child — avoids orphaned duplicates when paths are shown without `stacks/` in multi-root workspaces.
- **NAS permissions:** on DSM, normalize bind-mount ownership with **`scripts/fix-permissions.sh`** (see `HIVE_OBJECTIVE.md` → NAS Deployment Notes). Default **`PUID`/`PGID` (or `SYNO_*`) = `0`** on the NAS unless you override in `.env` for local dev.
- **SMB mounts:** If `stacks/.git` could not be fully removed (Resource busy), delete it when no editors have the volume open, then run `git status` at repo root to confirm Git does not treat `stacks/` as a nested repo.
- **SMB + pre-commit:** Synology SMB mounts often reject in-place writes under `docs/`, `.github/`, and `.cursor/`. `.pre-commit-config.yaml` **excludes** those prefixes from `trailing-whitespace`, `end-of-file-fixer`, and `prettier` so `pre-commit run --all-files` succeeds on `/Volumes/docker/dockge`. Run full markdown/YAML fixups on an APFS clone or on the NAS. **`ruff-format` is omitted** (the only tracked `.py` is `docs/hive/tools/inventory.py`, which is excluded from mutating hooks by path); run `ruff format docs/hive/tools/inventory.py` when needed from a non-SMB checkout.
- **Audit (2026-04-30):** **`stacks/docs` → `../docs` must not exist** — paths like **`…/dockge/stacks/docs/hive/proposals/_haproxy/haproxy.cfg`** are wrong (hive lives at **repo** `docs/hive/`, not under **`stacks/`**). Canonical HAProxy files: **`docs/hive/proposals/_haproxy/haproxy.cfg`** (include wrapper) and **`stacks/_haproxy/haproxy.cfg`** (body). **`stacks/._DAV`** is SMB/Finder noise—delete when idle, never commit. **`.ruff_cache/`** is gitignored. **Compose:** `scripts/compose-validate.sh` passes (includes **`stacks/mcp-tools-config/compose.yaml`** placeholder; **`docker-mcp.yaml`** there remains catalog-only). **Git / `inventory.py`:** if `git pull`/`git merge` fails with **Resource busy** or **EINVAL** on `docs/hive/tools/inventory.py`, close editor handles and retry, or merge from an **APFS git worktree** (`git worktree add -b <tmp-branch> <apfs-path> main` → `git merge origin/main` → `git push origin HEAD:main`). **`origin/main`:** merge `e15c4bd` (includes `1c774b3` — `out_dir` under `repo_root/docs/hive/proposals/…`, not `stacks/…/docs/…`).

## Stack hardening defaults

**Standing rule — `no-new-privileges` in compose stacks**

- **Default:** `no-new-privileges:true` is the **hardening baseline** for stacks in this repo.

- **Exception class — omit `no-new-privileges:true` only when all of the following hold:**

  1. The image ships a **setuid helper** that must elevate at runtime (e.g. Electron `chrome-sandbox`, Chromium, any SUID binary the app relies on).
  2. The **host kernel** does **not** provide unprivileged user namespaces — treat **Synology DSM** as **absent** unless you have explicitly confirmed otherwise.
  3. **No** `--no-sandbox` (or equivalent env) is set in compose to provide an alternative sandbox path.

- **When omitting NNP:**

  - **`compose.yaml`:** document in an **inline comment directly above** `security_opt`, using this pattern:
    - `# Omit no-new-privileges:true: [reason].`
    - `# Do not add --no-sandbox here.`
  - **Stack README:** add a note under **`## Permissions`**.
  - **`docs/hive/NAS_DEPLOYMENT.md`:** add a row or prose under **Security Advisor warnings** for the intentional omission.

- **New LinuxServer.io KasmVNC / Electron-style stacks:**

  - **Assume NNP must be omitted** until confirmed safe with NNP on the target DSM.
  - **`seccomp:unconfined`** — required for KasmVNC / Electron in this class of image.
  - **`IPC_LOCK`** — required for Electron memory locking.
  - Check **upstream image release notes** before adding `--no-sandbox` as a workaround.

- **Audit trigger:** any `compose.yaml` that lists **`seccomp:unconfined`** and **`no-new-privileges:true`** in the **same** `security_opt` block should be **flagged for review** — the combination is often incompatible with setuid sandbox helpers (verify stack-by-stack; not every `seccomp:unconfined` stack is Electron).

- **Reference commits:** **`c75af1b`** — `no-new-privileges:true` added to **github-desktop** (incorrect for Electron); **`bfa07bd`** — removed with documented rationale. Stack-specific detail remains in the **What Works** bullet for **github-desktop**.

## What Works

- [2026-05-07] **Next-phase fixes (port conflict, depends_on, homepage, README, OCI):** **rag-stack:** anythingllm previously published **3001** on the host — same as HolyClaude. Remapped to **`10.0.1.15:3002:3001`**; do not assign host **3001** to AnythingLLM with HolyClaude in the fleet. **depends_on:** dropped `condition: service_healthy` on **anythingllm** / **pipelines** in favor of plain lists for Synology Package Center compose. **homepage** `config/services.yaml`: Portainer Agent **siteMonitor** removed (mTLS → `HPE_CLOSED_CONNECTION`); DSM **siteMonitor** set to **`https://10.0.1.15:5001/`**; Portainer widget **`key: ${PORTAINER_API_KEY}`** (`.env.example` documents the variable). **`stacks/rag-stack/README.md`** added. **OCI probes (2026-05-07, `docker run --entrypoint="" … sh -c "which wget; which curl"` where applicable):** **qdrant** — no wget/curl → healthcheck uses **perl `IO::Socket::INET`** GET `/readyz`; **anythingllm** / **pipelines** → **curl**; **warp** — **wget**; **warp-agent** — **curl**; **warp-claude-cli-sidecar** — **node** `http.get`; **open-resume** — image pull denied locally → **node** `http.get` + **`# TODO: verify`**; **mcp-gateway** — **wget** (unchanged).
- [2026-05-07] **OCI healthcheck audit — exec: `wget` not found hardening:** `traefik-ots` and `traefik-mft` now use built-in probes (`["CMD","traefik","healthcheck","--ping"]`) with `--ping=true` already present; `adminer` switched from `wget` to `curl -fs`; `open-webui` simplified from `wget||curl` fallback to `curl -fs`; `holyclaude` moved off `nc` (not present in image) to `curl`/`wget` HTTP probe fallback. Live image audits verified `wget`/`curl`/`nc` availability before changes, and the rule stands: do not assume `wget` on non-alpine images; verify via `docker run --rm --entrypoint=\"\" <image> which wget` (and likewise for `curl`/`nc`). Standardized healthcheck type comments (A/B/C/D/E) were added to updated blocks.
- [2026-05-07] **Session: NAS partial bring-up and git hygiene (2026-05-07):**
  - holyclaude upstream port is 3001 (not 3000). compose.yaml corrected: ports `3001:3001`, healthcheck probes `3001`. BREAKING if you cached bookmarks or probes on 3000.
  - holyclaude `@/shared` error is caused by stale bundled cloudcli inside the image. Fix: `sudo docker pull coderluii/holyclaude:latest` (force fresh pull) then recreate container. In-container `npm install` is a workaround only — lost on container recreate.
  - Homepage widget errors are expected during partial bring-up. Only two are structural config bugs: (1) Portainer Agent siteMonitor removed (mTLS, not HTTP) → `HPE_CLOSED_CONNECTION`; (2) DSM siteMonitor was port 5000, corrected to `https://10.0.1.15:5001/`. Remaining `ECONNREFUSED` errors clear as stacks deploy.
  - Homepage Portainer widget needs `PORTAINER_API_KEY` in `stacks/homepage/.env`. Generate: Portainer → Account Settings → Access Tokens → Add.
  - Homepage Dockge widget needs `DOCKGE_USERNAME` + `DOCKGE_PASSWORD` in `stacks/homepage/.env`. Without these, widget times out (`ETIMEDOUT`) even when the Dockge container is healthy.
  - Synology `@eaDir` git ref corruption pattern: DSM file indexer enters `.git/refs/heads/` and creates `@eaDir/` subdirectory; git reads it as a branch named `@eaDir/main@SynoEAStream`. Breaks every git pull. Fix: `find .git/refs -name "*eaDir*" | xargs rm -f 2>/dev/null`. Permanent fix: DSM → Control Panel → Search → Indexed Locations → remove `/volume1/docker`. Add `git-pull-nas` alias that auto-cleans refs (see **`docs/hive/NAS_DEPLOYMENT.md`** → **Git safety on the NAS**).
  - Secrets committed to GitHub from NAS: `stacks/databases/secrets/*.txt`, `stacks/grafana-prom/secrets/watchtower_bearer_token.txt`, and `stacks/ollama/data/id_ed25519` (SSH private key) were pushed. `id_ed25519` must be treated as compromised and rotated. Files removed via `git rm --cached`; `.gitignore` updated with `**/secrets/*.txt` and `**/id_ed25519` rules. NEVER run `git add` from the NAS without checking `git status --short` first.
  - Git operations on the NAS must use `--no-rebase` for pull (not `--rebase`) because HEAD detach during rebase fails when untracked files exist.
  - NAS ownership fix before git ops: `sudo chown -R laolufayese:users /volume1/docker/dockge` — required after any `sudo docker compose` operation that creates files in the repo directory.
  - **`scripts/audit-healthcheck-tools.sh`:** verifies `wget`, `curl`, `nc`, `sh` availability in each image before assuming a probe tool is present. Key finding: `traefik:v3` has `wget` (not scratch-based as assumed); the probe fix to `CMD traefik healthcheck --ping` is still correct (uses app binary) but that assumption was wrong.
- [2026-05-01] **Block 3 post-rework gates (healthcheck, paths, manifest, HIVE audit):** **`HEALTHCHECK POLICY`** — every stack must have a `healthcheck:` block **or** a documented `# No healthcheck:` reason in `compose.yaml`. Exemptions (no `healthcheck:` in compose) are listed in `docs/hive/HEALTHCHECK_EXEMPTIONS.md`: **`mcp-tools-config`** (one-shot Busybox), **`acme-sh`** (cron-style daemon, no stable HTTP/TCP probe). **`holyclaude`** has an in-compose type-B HTTP healthcheck (`curl` → `127.0.0.1:3001/`, upstream CloudCLI UI port, `start_period: 90s`) — documented in that file as **not** exempt. **`github-desktop`** has the same pattern (type B on 3000, `start_period: 90s`) and is **not** exempt. **`DATABASES` stack:** manifest entry `"databases:db/mariadb,db/postgres"`; MariaDB and Postgres data both under `db/`; no separate app-level `databases/data` bind — intentional. Leaf subdirs are listed explicitly because Synology Docker (Container Manager) does not auto-create bind-mount source paths and fails with `Bind mount failed: '<path>' does not exist`. **`HIVE_OBJECTIVE.md`:** stack names live in a markdown table (backtick list in the “Stack folders” row), not `-` bullets — parity vs `ls stacks/` uses the table-aware command in `docs/hive/NAS_DEPLOYMENT.md` (`grep "Stack folders"` + `grep -oE` on backtick names). **Path hygiene:** no bare `dockge/stacks/` in `stacks/` comments or examples without `STACK_ROOT` context (audit: `grep -rn "dockge/stacks/" stacks/ | grep -v "STACK_ROOT"`). **`github-desktop`** (post–Block 3 **`c75af1b`**, NNP fix **`bfa07bd`**): manifest `"github-desktop:config"`; **`security_opt` contains only `seccomp:unconfined`** — **`no-new-privileges:true` is intentionally absent** (Electron setuid `chrome-sandbox` vs `PR_NO_NEW_PRIVS`; DSM; no `--no-sandbox` in compose — **do not add NNP back**); `cap_add: IPC_LOCK`; `restart: unless-stopped`; PUID/PGID dual-mode; `${STACK_ROOT}/github-desktop/config:/config:rw`. Rationale in `compose.yaml` comments, `stacks/github-desktop/README.md`, `docs/hive/NAS_DEPLOYMENT.md`.
- [2026-04-30] **Compose validate** lives only at repo root **`scripts/compose-validate.sh`** (not under `stacks/scripts/`). CI runs that path; Dockge stack root stays compose-only.
- [2026-04-30] Keep pre-commit language/file matching type-driven where possible: use `types` / `types_or` for JS/TS, Python, shell, Go, Rust, and PowerShell; only use regex `files` when a stable type tag is unavailable.
- [2026-04-30] For local formatter hooks that depend on host tooling (`gofmt`, `rustfmt`, `dotnet`, `pwsh`), use `language: unsupported` and fail-fast entry checks with explicit install commands so contributors get actionable errors instead of opaque failures.
- [2026-04-30] Keep fast commit loops by putting heavy checks on `pre-push` or `manual` stages (for example, `.NET` analyzer/build gates) while preserving lightweight formatting on default commit stage.
- [2026-04-30] This repo has no Dockerfiles or Go/Rust/.NET sources under version control; keep `.pre-commit-config.yaml` limited to hooks that actually match tracked files so `meta: check-hooks-apply` passes. Re-add language-specific hooks when those paths exist.

## What Failed

- [2026-04-30] Using `language: system` in local hooks is deprecated in modern pre-commit; migrate to `language: unsupported` to avoid forward-compatibility issues.
- [2026-04-30] Relying only on extension regex for shell scripts (for example `.sh` / `.bash`) misses valid shebang scripts without those extensions; prefer `types: [shell]`.

## Recurring Bugs

- [2026-05-07] Running `git add` / `commit` / `push` from the NAS without reviewing `git status` first led to secrets, SSH keys, `.DS_Store`, `.claude-flow/`, `node_modules/`, and backup archives being committed to GitHub. Rule: ALWAYS run `git status --short` before any `git add` on the NAS. The NAS working tree contains many untracked runtime dirs that must never be staged. Use `git add <specific-file>` not `git add -A` or `git add .`.
- [2026-05-07] Synology DSM file indexer (`@eaDir`) corrupts `.git/refs` on any git repo stored on a Synology volume. Symptom: `fatal: bad object refs/heads/@eaDir/main@SynoEAStream` on every git pull. Permanent fix: disable DSM indexing for `/volume1/docker`. Workaround: `find .git/refs -name "*eaDir*" | xargs rm -f` before pull. See **`docs/hive/NAS_DEPLOYMENT.md`** → **Git safety on the NAS**.
- [2026-04-30] Teams often hit missing-tool errors in local hooks (`gofmt`, `rustfmt`, `dotnet`, `Invoke-Formatter`). Prevent this by embedding prerequisite checks and install hints directly in each hook `entry`.
- [2026-04-30] Mixed understanding of pre-commit "languages" vs identify "types" causes misconfiguration. Treat runtime `language` (hook execution environment) and file `types` (selection filter) as separate concerns.
- [2026-05-07] **`code-server` runtime config can leak secrets:** the image writes `/home/coder/.config/code-server/config.yaml` with a generated plaintext `password:` and `bind-addr: 127.0.0.1:8080` if no config exists. With `${STACK_ROOT}/code-server/config:/home/coder/.config/code-server`, that file lands in the repo. Commit `552cf44` shipped a plaintext password in that file (removed in `a8138f4`; literal value intentionally not reproduced here — recoverable via `git show 552cf44` for incident response only). **Mitigation in tree:** `.gitignore` covers `stacks/code-server/config/code-server/`, and the active `stacks/code-server/config/config.yaml` uses `bind-addr: 0.0.0.0:8080` with `auth: password` driven by `PASSWORD=${CODE_SERVER_PASSWORD}` from gitignored `stacks/code-server/.env`. **History not rewritten** — single-use credential, public from the moment of push, rotated on the NAS; `scripts/rewrite-history-redact.sh` is kept in the repo for the next incident. Pre-flight check before any code-server edit: `git ls-files stacks/code-server/config/code-server/ | wc -l` must be `0`.

## Update Workflow

- [2026-04-30] Run `pre-commit autoupdate` in a dedicated maintenance PR on a regular cadence, then run `pre-commit run --all-files` before merge. Default to tag-based updates; use `--bleeding-edge` only when specifically needed.
- [2026-04-30] Use `agents-memory-updater` as the preferred periodic consolidation path when refreshing repository memory entries.

## Dockge UI compose editor

- **Environment:** Prefer list syntax (`- KEY=value`) over map syntax (`KEY: value`) in `compose.yaml` so Dockge’s stack **form** view does not warn _Environment Variables — Long syntax is not supported here. Please use the YAML editor._
- **Networks:** Do not add empty `networks: {}` (service or top level); omit `networks` when the default bridge is sufficient.
- **Named networks:** Stacks that declare a top-level `networks:` block with options (`driver`, `name`, etc.) — e.g. **`traefik-ots`**, **`traefik-mft`**, **`zabbix`**, **`warp-main`** — may still show _Networks — Long syntax is not supported_ in the form view; that is expected — edit those stacks in Dockge’s **YAML** editor.

## Dockge Host Container (2026-04-30)

### Key facts

- **Startup script location (NAS):** `/usr/local/etc/rc.d/dockge.sh` — Synology rc.d; NOT a compose stack.
- **Improved version in repo:** `scripts/dockge-start.sh` — drop-replace for the NAS script; apply with `chmod +x` and test with `sh scripts/dockge-start.sh`.
- **Image:** Original used `louislam/dockge:base` — that is the **builder base layer**, not the application. Correct production image is `louislam/dockge:1` (tracks latest stable, currently `1.5.0`). **Replace `:base` with `:1` on the NAS.**
- **Host port:** `5571` → container port `5001`. The homepage config previously pointed to `5001` (Synology DSM's port) — now corrected to `5571`.
- **Container name:** `Dockge` (capital D). Homepage `server: my-docker` + `container: Dockge` now enabled.
- **Path symmetry (correct):** `/volume1/docker/dockge/stacks:/volume1/docker/dockge/stacks` — inside-path = outside-path as required by Dockge.
- **App state:** `scripts/dockge-start.sh` mounts **`${DOCKGE_ROOT}/data`** (default **`/volume1/docker/dockge/data`**) at **`/app/data`** so **`dockge.db`** and related files stay **out of the git repo root**. **`stacks/`** is still mounted separately. **One-time migration:** if a non-empty **`dockge.db`** still sits at **`${DOCKGE_ROOT}/`** from an older script that used **`-v ${DOCKGE_ROOT}:/app/data`**, the script moves **`dockge.db`**, **`dockge.db-shm`**, **`dockge.db-wal`**, and **`db-config.json`** into **`${DOCKGE_ROOT}/data/`** before (re)creating the container. The container is **recreated** if **`/app/data`** is not bound to **`${DOCKGE_ROOT}/data`** (e.g. after this layout change).
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
bash scripts/check-dockge-http.sh                      # → HTTP 200/301/302 from Dockge
```

### Recurring reminders

- [2026-04-30] Dockge is NOT compose-managed — it is a raw `docker run` container started by a Synology rc.d script. Never try to manage it with `docker compose` from the stacks repo.
- [2026-04-30] `louislam/dockge:base` is a builder image, NOT the Dockge app. Always use `:1` or an explicit semver tag like `:1.5.0` for production.
- [2026-04-30] Dockge host port is **5571**, not 5001. Port 5001 on this NAS is Synology DSM. These two must not be confused in homepage config, HAProxy backends, or siteMonitor entries.
- [2026-04-30] Dockge has a native Homepage widget (`type: dockge`) that shows running/stopped stack counts. Requires login credentials in `.env`.
- [2026-05-02] **HAProxy stretch:** Canonical **`stacks/_haproxy/haproxy.cfg`** (TLS **`${STACK_ROOT}/_haproxy/certs/`**, map **`.../maps/host.map`**, **`dockge-be`** → **`10.0.1.15:5571`**); **`docs/hive/proposals/_haproxy/haproxy.cfg`** is **`include`** only. NAS may still load **`/volume1/docker/haproxy.cfg`** — use **`include /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg`** there or repoint **`-f`**. **`init-nas.sh`** creates **`_haproxy/{certs,maps}`**. See **`docs/hive/NAS_DEPLOYMENT.md`**; **`bash scripts/validate-haproxy-proposal.sh`** (`openssl` + temp paths; `haproxy` or `docker`).

## Deploy-Readiness Audit (2026-04-30)

### Baseline Status — Dockge compose stacks (**23**) + **`_haproxy/`** under **`stacks/`**

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
| holyclaude          | ✓ (mixed)       | ✓                            | ✓                          | ✓         | ✓         | ✓                   | `:latest` — dev image                                   | ✓      | ✓            | ⚠           |
| homepage            | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | semver v1.12                                            | ✓      | ✓            | ✓            |
| it-tools            | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | semver 2024.10.22                                       | ✓      | ✓            | ✓            |
| mcp-tools-config    | ✓ (placeholder) | `restart: "no"` (one-shot)   | —                          | ✓         | N/A       | N/A                 | `busybox:1.36` + separate **`docker-mcp.yaml`** catalog | ✓      | —            | ⚠           |
| ollama              | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | semver pinned; plain `depends_on` (Synology compat)     | ✓      | ✓            | ✓            |
| openresume          | ✓               | ✓                            | ✓                          | ✓         | ✓         | ✓                   | **:latest — OPERATOR PIN NEEDED**                       | ✓      | ✓            | ⚠           |
| portainer           | ✓               | always (CE default)          | ✓                          | ✓         | ✓         | ✓                   | semver 2.41.0-alpine                                    | ✓      | ✓            | ✓            |
| rag-stack           | ✓               | ✓                            | ✓ (3 svcs)                 | ✓         | ✓         | ✓                   | semver / pinned images                                  | ✓      | ✓            | ⚠           |
| searxng             | ✓               | ✓                            | ✓ (redis)                  | ✓ applied | ✓ applied | ✓                   | searxng: date-tag; valkey: 8-alpine                     | ✓      | ✓            | ✓            |
| traefik-mft         | ✓               | ✓                            | ✓                          | ✓ applied | ✓         | ✓                   | `traefik:v3` — operator pin recommended                 | ✓      | ✓            | ⚠           |
| traefik-ots         | ✓               | ✓                            | ✓                          | ✓ applied | ✓         | ✓                   | `traefik:v3` — operator pin recommended                 | ✓      | ✓            | ⚠           |
| warp-main           | ✓               | ✓                            | ✓ (warp + agent + sidecar) | ✓         | partial   | ✓                   | semver / `:latest` mix                                  | ✓      | ✓            | ⚠           |
| watchtower          | ✓               | ✓                            | ✓ applied                  | ✓         | ✓         | N/A (is watchtower) | **:latest — OPERATOR PIN NEEDED**                       | ✓      | ✓            | ⚠           |
| zabbix              | ✓               | unless-stopped               | ✓                          | ✓         | ✓         | ✓                   | semver 7.4-alpine (operator digest pin recommended)     | ✓      | ✓            | ⚠           |

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

- [2026-05-06] **REPO_REVIEW audit:** **`ls stacks/ | grep -v '^_' | wc -l`** is **23** and matches **HIVE_OBJECTIVE.md**, the deploy-readiness table, and **`STACK_MANIFEST`** coverage. When diffing manifest stack names vs **`ls stacks/`**, use **`sort -u`** on the manifest side so **traefik-ots** / **traefik-mft** (each listed twice for config+data) do not false-fail the check; include **`_haproxy`** on the **`ls`** side (do not exclude it). **NAS_DEPLOYMENT.md** and **dockge-start.sh** agree on **host 5571 → container 5001**. Router admin cert callout lives under **docs/hive/NAS_DEPLOYMENT.md → Known outstanding issues**. **rag-stack** has **compose.yaml**, **.env.example**, and **README.md**.
- [2026-05-03] **Post-reset recovery patterns (NAS reset 2026-05):** Dockge MUST use **5571:5001** (not **5571:5571**) — image listens on **5001**; recreate **`Dockge`** (stop/rm/re-run rc script) if binding is wrong. **acme-sh** PEMs under **`/volume1/certs/acme/`** are not implied across a DSM reset — re-**issue**/**install-cert** before Traefik or HAProxy can serve real HTTPS. **Order:** Container Manager → **`git clone`** → **`init-nas.sh`** → Dockge rc.d → **acme-sh** (all certs) → **traefik-ots** / **traefik-mft** → other stacks → HAProxy bundles in **`stacks/_haproxy/certs/`** (**.pem only**; non-PEM files cause **`no start line`**). Router: **NFS off** still leaves **rpcbind :111** — block on WAN via **`/jffs/scripts/firewall-start`** if required. **ASUS admin TLS** (**batcavegtaxe16k.asuscomm.com**) expired **2025-06-06** — renew via router **Administration → System**. **Root [`README.md`](README.md)** is the operator entry point after reset.
- [2026-05-02] **OTS/MFT namespace architecture (canonical; commits `401885b`, `7f1c157`, `87babca`):** **DNS:** `*.ots.olutechsys.com` → CNAME `otsorundscore.synology.me.` (OTS NAS); `*.mft.olutechsys.com` → CNAME `misfitsds.synology.me.` (MFT NAS); wildcard CNAMEs → **no per-service DNS**; **DNS-only (grey cloud)** — Cloudflare cannot proxy wildcard CNAMEs to third-party DDNS; **`lab`/`dev`** reserved, commented in `docs/hive/dns/olutechsys.com.zone`. **Certs (acme-sh only, RSA 2048, DNS-01 CF):** `ots-sub/` → `*.ots.olutechsys.com` → `/volume1/certs/acme/ots-sub/`; `mft-sub/` → `*.mft.olutechsys.com` → `/volume1/certs/acme/mft-sub/`; auto-renew **acme-sh**; Traefik reads PEMs via **read-only** bind + `config/tls.yaml` file provider — **no Traefik ACME resolver**. **Traefik stacks:** `stacks/traefik-ots/`, `stacks/traefik-mft/`; **`STACK_MANIFEST`:** `"traefik-ots:config"`, `"traefik-mft:config"` (tls.yaml — no runtime data dir). **Compose pattern:** `docker.sock` `:ro` + comment above; `${ACME_CERT_ROOT}` cert mount `:ro`; `PUID`/`PGID` dual-mode; `restart: unless-stopped`; healthcheck type A (`wget` → `/ping` on 8080); **no** top-level `version:`; bridge **`traefik-ots`** / **`traefik-mft`**; services join **`external: true`**. **Deploy order:** (1) issue `ots-sub`/`mft-sub` via **acme-sh**, (2) deploy Traefik, (3) deploy services — missing cert path at Traefik start → self-signed fallback / browser warning. **New service:** Traefik labels + join Traefik network; **no** DNS or wildcard cert change; update **`docs/hive/SERVICE_MAP.md`**. **Docs (401885b):** `docs/hive/dns/olutechsys.com.zone`, `docs/hive/SERVICE_MAP.md`, full `stacks/traefik-ots/` + `stacks/traefik-mft/`, `stacks/acme-sh/SETUP.md` (`ots-sub`/`mft-sub`). **`/continuous-learning`:** Cursor user-hook pattern under **`~/.cursor/hooks/`** — **not** an in-repo file; session-end extraction configured there separately (no repo hook added for this task).
- [2026-05-01] **23** Dockge stack folders under **`stacks/`** (including **`rag-stack`**, **`traefik-mft`**, **`traefik-ots`**, **`zabbix`**); repo-root **`scripts/init-nas.sh`** + **`docs/hive/NAS_DEPLOYMENT.md`** document `${STACK_ROOT}` bootstrap. **`mcp-tools-config`** uses **`compose.yaml`** for CI/Dockge validate plus **`docker-mcp.yaml`** catalog.
- [2026-05-01] **`scripts/init-nas.sh`** (post–Block 3 / `c75af1b`): flags — **`--list-expected-dirs`** (manifest-derived paths, no filesystem, Mac-safe, exit 0); **`--if-changed`** (hashes **`$0`**; skips full init when `${REPO_ROOT}/.manifest-hash` matches; **`IF_CHANGED_MODE=1`** only when hash differs; hash written **only** at successful script end via `[[ "${IF_CHANGED_MODE:-0}" -eq 1 ]]` so a failed run never poisons the file); **no flag** = full init always. **`LIST_ONLY=0`** and **`IF_CHANGED_MODE=0`** initialized at top with **`set -euo pipefail`**. User-facing lines (verbatim): `init-nas.sh: unchanged — skipping directory creation.` / `init-nas.sh: changed — running full init.` / `init-nas.sh: hash updated for next --if-changed run.` **`scripts/fix-permissions.sh`** accepts optional `$1` (default `/dockge/stacks`); called by `init-nas.sh` after full init. **`.manifest-hash`** is gitignored.
- [2026-05-01] `docs/hive/NAS_DEPLOYMENT.md` now documents Git workflows A/B/C for keeping the NAS clone in sync with the canonical repo (including `scripts/init-nas.sh --if-changed` semantics), DSM Snapshot Replication and Hyper Backup schedules (with `codex-docs` backups via `docker exec ... mongodump` and `grafana-prom` data stored under `data/` unless an additional `db/` bind is added), the intentional Docker Security Advisor rows (including **traefik-ots** / **traefik-mft** `docker.sock`), the native-vs-Docker alternatives for core services, and the SynoCommunity dev tools baseline (Git + ShellCheck only — no extra `bash` package since DSM already ships `bash`).
- [2026-04-30] **Pre-/coder baseline (preflight):** before a coding pass, **`git status`** clean and **`scripts/compose-validate.sh`** + **`pre-commit run --all-files`** green; **`scripts/fix-permissions.sh`** present, executable, shellcheck-clean; **`scripts/verify-repo-layout.sh`** passes (no root-level **`hive/`** or duplicate stack names). **UID/GID:** compose uses **`${PUID:-0}`/`${PGID:-0}`** where **`user:`** is wired from env (`code-server`, `github-desktop`, `holyclaude`, **`warp-main` `warp-agent`**); **`grafana-prom`** uses **`${SYNO_UID:-0}`/`${SYNO_GID:-0}`**; other stacks rely on image defaults + NAS ownership via **`fix-permissions.sh`**. **MCP:** `stacks/mcp-tools-config/compose.yaml` validates; **`docker-mcp.yaml`** is catalog-only (`version: 3` / `registry:`). **Warp:** `warp-agent` healthcheck probes **`127.0.0.1:8080`**. **Rule:** never create root-level copies of **`stacks/<stack>/`** or **`docs/hive/proposals/`** — CI enforces via **`verify-repo-layout.sh`**.
- [2026-05-01] **Canonical layout:** **`stacks/`** holds **23** compose stack folders plus **`_haproxy/`** (HAProxy assets, not a Dockge stack); proposals under **`docs/hive/proposals/<stack>/`**. Writable binds use **`${STACK_ROOT}/<stack>/…`** (see **`HIVE_OBJECTIVE.md`** + **`NAS_DEPLOYMENT.md`**); **documented exceptions:** Portainer and code-server operator paths. **`HIVE_OBJECTIVE.md`** spawn strings use **`--count 23`** (one worker per compose stack folder).
- [2026-04-30] Hive `docs/hive/proposals/<stack>/` exists for stacks in the deploy table above (including auxiliary folders); \_baseline and \_haproxy proposals also exist.
- [2026-04-30] No stale `orundscore` hostname (without `ots` prefix) in any live compose file; hive proposal docs only reference the boundary-aware grep pattern in comments, not in live config.
- [2026-04-30] `searxng/searxng` is already pinned to a date-commit tag (`2026.4.29-cba0cffa8`), not `:latest` — this is the correct pattern for SearXNG's rolling release model.
- [2026-04-30] `databases` stack uses Docker secrets (`_FILE` pattern) for all credentials — this is the gold standard for secret handling in this repo.
- [2026-04-30] Watchtower `healthcheck` now uses `/v1/health` (unauthenticated) rather than `/v1/metrics` (auth-gated) — always probe the unprotected liveness endpoint when the service has mixed-auth routes.

### Recurring Issues Found

- [2026-04-30] `:latest` / floating tags on **`codex-docs`**, **`openresume`**, **`watchtower`**, **`github-desktop`**, **`holyclaude`**, and **`traefik:v3`** stacks are operator-pin candidates. Prefer semver or digest per stack README / **`HIVE_OBJECTIVE.md`** image policy.
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
- [2026-05-01] Zabbix monitoring on the NAS uses three layers: (1) SNMPv3 as the default for hardware metrics (disks, RAID, temperatures, fans, UPS, network, volume) with the server polling UDP 161 and no agent; (2) the SynoCommunity native agent with `Server=127.0.0.1`, `ServerActive=127.0.0.1:10051`, and `HostnameItem=system.hostname` (never `Hostname=` alongside), where the Zabbix UI Host name must exactly match the DSM hostname and DSM renames require updating the Host name or active checks go silent; and (3) an optional Docker `zabbix-agent2` container for container metrics only, running privileged with host binds and explicitly documented Security Advisor flags, not a replacement for SNMP or the native agent.
- [2026-05-01] `stacks/zabbix/compose.yaml` carries a commented `zabbix-agent2` section using `zabbix/zabbix-agent2:7.4-alpine` (aligned with the `7.4` server) with plain-text comments (no special symbols) that point to `stacks/zabbix/README.md` (Agent options, Option 1) for enabling the Docker agent; uncommenting this block is an explicit operator choice.
- [2026-05-02] **Docker Security Advisor — full intentional list** (acknowledge in DSM; do not strip settings to silence warnings only): **`seccomp:unconfined`** — **github-desktop** (Electron/KasmVNC); **`IPC_LOCK`** — **github-desktop** (Electron memory locking); **`no-new-privileges` absent** — **github-desktop** (intentional, **`bfa07bd`**); **containers as root (UID 0)** — fleet-wide (`PUID`/`PGID` default `0`); **`/var/run/docker.sock`** read-only — **traefik-ots**, **traefik-mft** (label discovery); **`privileged: true`** — **zabbix-agent2** only if uncommented. See `docs/hive/NAS_DEPLOYMENT.md` → **Security Advisor warnings**; **## Stack hardening defaults** above.
