# scripts/

- **dockge-start.sh** — Synology rc.d template for the Dockge container (canonical copy for operators).
- **compose-validate.sh** — run from repo root: `bash scripts/compose-validate.sh` (walks up to `HIVE_OBJECTIVE.md`, validates compose under `stacks/`). CI: `.github/workflows/stacks-compose-validate.yml`.
- **verify-repo-layout.sh** — run from repo root: `bash scripts/verify-repo-layout.sh`; fails if **`hive/`** exists at repo root (use **`docs/hive/`**) or if any **`stacks/<name>/`** stack folder name is duplicated as **`/<name>/`** at repo root. CI runs this before compose validate.
- **fix-permissions.sh** — on the NAS only, as root: normalizes ownership `root:root` and `755`/`644` under `/volume1/docker/dockge/stacks` (optional second path). See `HIVE_OBJECTIVE.md` → NAS Deployment Notes.

Hive docs and agent dirs live at the **repo root** (`docs/`, `.claude/`, `.claude-flow/`, `.hive-mind/`). `docs/hive/tools/inventory.py` writes proposals under `docs/hive/proposals/` (repo root).
