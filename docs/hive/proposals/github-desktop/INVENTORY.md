# INVENTORY — github-desktop

**Path:** `stacks/github-desktop/compose.yaml` · **Manual stub** (2026-04-30)

## Services

| Name | Image | Ports | Notes |
|------|-------|-------|-------|
| `github-desktop` | `ghcr.io/linuxserver/github-desktop:latest` | `3405:3001` | KasmVNC; `PASSWORD` required |

## Volumes

| Host | Container |
|------|-------------|
| `/volume1/docker/dockge/stacks/github-desktop/config` | `/config` |

## Environment

`PUID`/`PGID` default **0** on NAS; `PASSWORD`, `TZ`, optional `HOST_PORT`.
