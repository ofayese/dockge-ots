# Healthcheck exemptions

The following stacks intentionally have **no** `healthcheck:` block in `compose.yaml`:

| Stack              | Reason                                                                                                                                   |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| mcp-tools-config   | One-shot Busybox placeholder (`restart: "no"` # intentional). Not a persistent service — a probe is not applicable.                    |
| acme-sh            | Cron-style renewal daemon (`command: daemon`, `network_mode: host`). No stable HTTP/TCP liveness endpoint; renewal success is out-of-band. |

All other stacks under `stacks/*/compose.yaml` should define a `healthcheck:` (or gain a documented row here **before** a Block 3-style audit).

**holyclaude:** uses a **TCP healthcheck** (type B, `nc -z 127.0.0.1:3000`, `start_period: 90s`; see `stacks/holyclaude/compose.yaml`) — **not** a “no healthcheck” exemption; Block 3 audit outcome is documented here so agents do not treat it like `mcp-tools-config` / `acme-sh`.

**github-desktop:** same type-B pattern on internal port **3000** (`stacks/github-desktop/compose.yaml`) — **not** exempt.
