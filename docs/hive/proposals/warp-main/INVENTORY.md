# INVENTORY — warp-main

**Path:** `stacks/warp-main/compose.yaml` · **Manual stub** (2026-04-30; path updated 2026-05-11)

## Services

`warp`, `warp-agent`, `warp-claude-cli-sidecar` — see stack README for ports (`9090`, `8080`).

## Compose notes

`restart: unless-stopped`, healthchecks; **`depends_on` … `condition: service_healthy`** chain (warp → warp-agent → sidecar); `WARP_API_KEY` required.
