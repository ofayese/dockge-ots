# Claude / agent notes — Dockge stacks repo

## Dockge path layout

- **Canonical writable bind-mount root** for every Dockge-managed stack is:

  `/volume1/docker/dockge/stacks/<stack-name>/`

- **Standard subdirectories** (create on first deploy via `scripts/init-nas.sh` or when containers start): `data`, `config`, `db`, and stack-specific folders as declared in each stack’s `compose.yaml`.

- **Deprecated:** host paths under `/volume1/docker/<stack-name>/` outside `dockge/stacks/` — do not add new stacks or bind mounts there. Migrate existing references to the layout above.

- **Compose:** always express host paths with `${STACK_ROOT}/<stack>/…` where `STACK_ROOT` resolves to `/volume1/docker/dockge/stacks` on the NAS (see each stack’s `.env.example`).

- **Git repo root** (config, scripts, docs) remains `/volume1/docker/dockge` (or your Mac clone); **runtime data** for stacks lives only under `dockge/stacks/`.

See also [AGENTS.md](AGENTS.md) and [HIVE_OBJECTIVE.md](HIVE_OBJECTIVE.md).
