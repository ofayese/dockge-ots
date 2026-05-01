# mcp-tools-config — Docker MCP catalog (reference)

This folder holds **reference YAML** for Docker Desktop MCP tooling.

## Files

| File                                            | Purpose                                                                                                                                                                                                             |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`docker-mcp.yaml`](./docker-mcp.yaml)          | **Docker MCP catalog** (metadata/registry entries). **Not** a Docker Compose file — `scripts/compose-validate.sh` does not parse it (see [`docs/hive/COMPOSE_FILENAMES.md`](../../docs/hive/COMPOSE_FILENAMES.md)). |
| `config.yaml`, `registry.yaml`, `tools.yaml`, … | Operator-edited MCP configuration fragments.                                                                                                                                                                        |

## NAS / git

- Treat this directory as **config-only**; keep large or machine-generated artifacts out of git when possible.
- Prefer editing on a Mac/Linux checkout and **rsync** to the NAS per `HIVE_OBJECTIVE.md` → NAS Deployment Notes.

## Outbound

Catalog references remote README/tool URLs; runtime MCP servers still need **HTTPS 443** when pulled or invoked.
