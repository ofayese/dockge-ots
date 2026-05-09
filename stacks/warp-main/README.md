# warp-main — Warp Docker sample

Sample **Warp** app (`warpdotdev/warp`) plus `warp-agent` and Claude sidecar, using [`docker-compose.yaml`](./docker-compose.yaml).

## Ports

| Host   | Service                   |
| ------ | ------------------------- |
| `9090` | `warp` UI                 |
| `8080` | `warp-claude-cli-sidecar` |

## Environment

Copy [`.env.example`](./.env.example) → `.env` and set **`WARP_API_KEY`** (Warp → Settings → Platform).

## Volumes

No persistent volumes — stateless.

## Outbound

Requires **HTTPS 443** to Warp and image registries for pulls and API calls.

## Compose

Uses **`restart: unless-stopped`** and healthchecks for Synology-aligned operability. `warp-agent` **`user`** is `${PUID:-0}:${PGID:-0}` (same default as upstream `0:0`; set **`PUID`/`PGID`** in `.env` per `HIVE_OBJECTIVE.md`).
