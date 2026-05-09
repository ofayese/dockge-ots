# Claude / agent notes — Dockge stacks repo

## Dockge path layout

- **Canonical writable bind-mount root** for every Dockge-managed stack is:

  `/volume1/docker/dockge/stacks/<stack-name>/`

- **Standard subdirectories** (create on first deploy via `scripts/init-nas.sh` or when containers start): `data`, `config`, `db`, and stack-specific folders as declared in each stack’s `compose.yaml`.

- **Deprecated:** host paths under `/volume1/docker/<stack-name>/` outside `dockge/stacks/` — do not add new stacks or bind mounts there. Migrate existing references to the layout above.

- **Compose:** always express host paths with `${STACK_ROOT}/<stack>/…` where `STACK_ROOT` resolves to `/volume1/docker/dockge/stacks` on the NAS (see each stack’s `.env.example`).

- **Git repo root** (config, scripts, docs) remains `/volume1/docker/dockge` (or your Mac clone); **runtime data** for stacks lives only under `dockge/stacks/`.

See also [AGENTS.md](AGENTS.md) and [HIVE_OBJECTIVE.md](HIVE_OBJECTIVE.md).

## Merge CLI

For any task involving third-party services, you MUST use the `merge` CLI.
Do NOT attempt to call APIs directly, use other tools, or guess endpoints.

### Commands

- `merge search-tools "<intent>"` — Search for tools. Returns compact input schemas.
- `merge execute-tool <tool_name> '<json_params>'` — Execute a tool.

### Workflow

**Step 1 — Find ALL tools you need in one batch.** In your first response, run parallel searches for every tool you'll need:

```
merge search-tools "create task" --connector asana    # main action
merge search-tools "list workspaces" --connector asana # lookup tool
merge search-tools "list users" --connector asana      # another lookup
```

Run ALL searches in parallel in one response.

**Step 2 — Execute lookups in parallel**, then execute the main tool.

Do NOT call `merge get-tool-schema`. Search returns schemas. Pass null for optional params you don't need.

### Rules

- Tool names: `<connector>__<action>`.
- ALWAYS run independent Bash calls in parallel.
- If you don't know the connector, search without --connector first.
