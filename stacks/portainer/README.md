# portainer

Container management UI (server) + agent for daemon access on the host.

## Services

- **portainer** (9000 HTTP, 9443 HTTPS) — UI; mounts host `docker.sock` and `/volume1/​docker/portainer` for state
- **portainer_agent** (9001) — daemon-side agent; runs with `cap_drop: ALL` and only `cap_add: NET_RAW`; mounts `/` as `/host` for full filesystem visibility

## Bootstrap (bind mounts)

`compose.yaml` requires **`PORTAINER_DATA_ROOT`** and **`PORTAINER_CERT_ROOT`** to exist on the host before `docker compose up`. If either path is missing (for example `/tmp/portainer-certs` from an old `.env.example`), the daemon returns **Bind mount failed: … does not exist**. Create dirs and install agent TLS material first — see **`stacks/portainer/.env.example`** comments.

## TLS certs (agent)

`/volume1/​docker/portainer/certs/` — mount read-only at `/certs`; files must be named **`cert.pem`** and **`key.pem`** (see `compose.yaml`). Issue or copy TLS material separately; do not commit keys to git.

## Health

- portainer: HTTP 200 on `/api/system/status`
- portainer_agent: TCP open on 9001

## Trust posture

`portainer_agent` mounts `/` as `/host` plus `docker.sock` — this is the **highest privilege surface** of any stack. Access is gated by the agent-cluster TLS certs.

## Rollback

```bash
git checkout -- portainer/compose.yaml
docker compose -f portainer/compose.yaml up -d
```

Portainer DB (settings, registries, endpoints) persists at `/volume1/​docker/portainer`. Loss = re-create endpoints and re-pair the agent.

## History

Compose previously had a malformed `environment: - https://10.0.1.15:9001` entry (no `KEY=value`). Cleaned up; see `docs/hive/proposals/portainer/PROPOSAL.md` Change 1.
