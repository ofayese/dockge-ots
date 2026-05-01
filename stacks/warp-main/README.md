# warp-main — Warp Docker sample

Sample **Warp** app (`warpdotdev/warp`) plus `warp-agent` and Claude sidecar, using [`docker-compose.yaml`](./docker-compose.yaml).

## Ports

| Host   | Service                   |
| ------ | ------------------------- |
| `9090` | `warp` UI                 |
| `8080` | `warp-claude-cli-sidecar` |

## Environment

Copy [`.env.example`](./.env.example) → `.env` and set **`WARP_API_KEY`** (Warp → Settings → Platform).

## Paths / data

No bind-mounted app data in-repo; add absolute paths under `/volume1/docker/dockge/stacks/warp-main/` if you need persistence (never write mutable state into the git tree on the NAS).

## Outbound

Requires **HTTPS 443** to Warp and image registries for pulls and API calls.

## Compose

Uses **`restart: on-failure:5`** and healthchecks for Synology-aligned operability. `warp-agent` runs as `user: "0:0"` per upstream sample.
