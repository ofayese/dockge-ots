# INVENTORY — warp-main

**Path:** `stacks/warp-main/docker-compose.yaml` · **Manual stub** (2026-04-30)

## Services

`warp`, `warp-agent`, `warp-claude-cli-sidecar` — see stack README for ports (`9090`, `8080`).

## Compose notes

`restart: unless-stopped`, healthchecks added for Synology operability; `WARP_API_KEY` required.
