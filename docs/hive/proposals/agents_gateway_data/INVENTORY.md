# INVENTORY — agents_gateway_data

**Path:** `stacks/agents_gateway_data/compose.yaml` · **Manual stub** (2026-04-30)

## Services

| Name | Container | Image | Ports | Notes |
|------|-----------|-------|-------|-------|
| `mcp-gateway` | (default) | `docker/mcp-gateway:v0.42.0` | `8811` | Host `docker.sock` mounted for MCP orchestration |

## Volumes

| Host | Container | Mode |
|------|-----------|------|
| `/var/run/docker.sock` | `/var/run/docker.sock` | rw (required by image) |

## Secrets / env

`.env.example` present for optional `PUID`/`PGID`/`TZ`. No stack secrets in-repo.

## Gaps vs baseline

| Item | Status |
|------|--------|
| `docker.sock` | Documented security trade-off in compose |
| Healthcheck | Not set (image tooling unknown) |
