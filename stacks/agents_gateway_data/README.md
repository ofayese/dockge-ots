# agents_gateway_data — MCP gateway (DuckDuckGo)

Experimental **Docker MCP Gateway** wiring for DuckDuckGo search MCP. Uses the host Docker API.

## Ports

| Host (default) | Service            |
| -------------- | ------------------ |
| `8811`         | `mcp-gateway` HTTP |

## Volumes / paths

- **`/var/run/docker.sock`** — required by `docker/mcp-gateway` to orchestrate MCP servers (see compose comments for security note).
- Writable state should live under **`/volume1/docker/dockge/stacks/agents_gateway_data/`** on the NAS (not in the git checkout).

## Environment

Copy [`.env.example`](./.env.example) to `.env` if you add tunables. Defaults follow repo NAS policy: **`PUID`/`PGID` = 0** on Synology.

## Offline / outbound

Images pull from Docker Hub / GHCR; outbound **HTTPS (443)** required. No extra ports documented for runtime beyond MCP HTTP.

## Related compose

- Root [`compose.yaml`](./compose.yaml) — primary stack file Dockge should run.
- [`duckduckgo/compose.yaml`](./duckduckgo/compose.yaml) — alternate layout; avoid running both on the same host port.
