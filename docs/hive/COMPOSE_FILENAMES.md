# Compose filename conventions

Most stacks use Dockge-friendly `compose.yaml` at the stack root.

## Documented exceptions

| Path | Filename | Rationale |
|------|-----------|-----------|
| `grafana-prom/` | `docker-compose.yml` | Historical Synology / community template layout; referenced in ops runbooks. |
| `warp-main/` | `docker-compose.yaml` | Upstream Warp sample layout. |
| `docker-model-runner/` | `docker-compose.yml` | Upstream Docker Model Runner sample. |
| `mcp-tools-config/docker-mcp.yaml` | (not Compose) | **Docker Desktop MCP catalog** (registry metadata YAML). Kept alongside Dockge-facing [`compose.yaml`](../../stacks/mcp-tools-config/compose.yaml) (minimal placeholder) so CI validates the stack folder. |

All other stacks under this repo use `compose.yaml` unless a new exception is added here with owner approval.

## CI validation

[`scripts/compose-validate.sh`](../../scripts/compose-validate.sh) (repo root) discovers `compose.yaml`, `docker-compose.yml`, and `docker-compose.yaml` up to depth four and runs `docker compose config -q` for static checks. The `find` pipeline **explicitly excludes `docker-mcp.yaml`** so Docker Desktop MCP catalog YAML is never passed to `docker compose` (see inline comment in the script). Under **`mcp-tools-config/`**, only **`compose.yaml`** is Compose; **`docker-mcp.yaml`** remains catalog-only (see table above).
