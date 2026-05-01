# scripts/

- **dockge-start.sh** — Synology rc.d template for the Dockge container (canonical copy for operators).
- **compose-validate** — run from repo root: `bash stacks/scripts/compose-validate.sh` (walks up to `HIVE_OBJECTIVE.md`, validates compose under `stacks/`).

Hive docs and agent dirs live at the **repo root** (`docs/`, `.claude/`, `.claude-flow/`, `.hive-mind/`). `docs/hive/tools/inventory.py` writes proposals under `docs/hive/proposals/` (repo root).
