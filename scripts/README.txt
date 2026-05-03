# scripts/

- **dockge-start.sh** — Synology rc.d template for the Dockge container (canonical copy for operators). Publishes **host 5571 → container 5001**; recreates the container if the binding is wrong.
- **check-dockge-http.sh** — on the NAS after Dockge starts: `bash scripts/check-dockge-http.sh` (HTTP probe default `127.0.0.1:5571`).
- **validate-haproxy-proposal.sh** — copies `stacks/_haproxy/maps/host.map`, builds a temp PEM, rewrites `_haproxy` paths in `stacks/_haproxy/haproxy.cfg`, then runs `haproxy -c` (host binary) or `docker run … haproxy -c` (Alpine image); smoke-checks an `include` chain. Requires `openssl`; skips if neither `haproxy` nor `docker` is available.
- **compose-validate.sh** — run from repo root: `bash scripts/compose-validate.sh` (walks up to `HIVE_OBJECTIVE.md`, validates compose under `stacks/`). CI: `.github/workflows/stacks-compose-validate.yml`.
- **verify-repo-layout.sh** — run from repo root: `bash scripts/verify-repo-layout.sh`; fails if **`hive/`** exists at repo root (use **`docs/hive/`**) or if any **`stacks/<name>/`** stack folder name is duplicated as **`/<name>/`** at repo root. CI runs this before compose validate.
- **fix-permissions.sh** — on the NAS only, as root: normalizes ownership `root:root` and `755`/`644` under `${STACK_ROOT}` (optional second path). See `HIVE_OBJECTIVE.md` → NAS Deployment Notes.
- **init-nas.sh** — run once after clone on the NAS (`sudo bash scripts/init-nas.sh`): resolves `STACK_ROOT`, writes repo-root `.env`, creates per-stack `data`/`config`/`db` dirs, runs `fix-permissions.sh`. No-op `: "stack:subdir"` lines at EOF are consumed by CI `grep -oP` manifest checks (GNU grep; use Linux CI or `grep -oE` on BSD).

Hive docs and agent dirs live at the **repo root** (`docs/`, `.claude/`, `.claude-flow/`, `.hive-mind/`). `docs/hive/tools/inventory.py` writes proposals under `docs/hive/proposals/` (repo root).
