# Healthcheck exemptions

The following stacks intentionally have **no** `healthcheck:` block in `compose.yaml`:

| Stack              | Reason                                                                                                                                   |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| mcp-tools-config   | One-shot Busybox placeholder (`restart: "no"` # intentional). Not a persistent service — a probe is not applicable.                    |
| acme-sh            | Cron-style renewal daemon (`command: daemon`, `network_mode: host`). No stable HTTP/TCP liveness endpoint; renewal success is out-of-band. |

All other stacks under `stacks/*/compose.yaml` should define a `healthcheck:` (or gain a documented row here **before** a Block 3-style audit).

**holyclaude:** uses a **TCP healthcheck** on `127.0.0.1:3000` (see `stacks/holyclaude/compose.yaml`) — not exempt.
