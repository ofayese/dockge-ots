# Compose filename conventions

Most stacks use Dockge-friendly `compose.yaml` at the stack root.

## Documented exceptions

| Path | Filename | Rationale |
|------|-----------|-----------|
| `grafana-prom/` | `docker-compose.yml` | Historical Synology / community template layout; referenced in ops runbooks. |
| `warp-main/` | `docker-compose.yaml` | Upstream Warp sample layout. |
| `docker-model-runner/` | `docker-compose.yml` | Upstream Docker Model Runner sample. |

All other stacks under this repo use `compose.yaml` unless a new exception is added here with owner approval.

## CI validation

[`stacks/scripts/compose-validate.sh`](../../scripts/compose-validate.sh) discovers `compose.yaml`, `docker-compose.yml`, and `docker-compose.yaml` up to depth four and runs `docker compose config -q` for static checks.
