# PROPOSAL — `grafana-prom`

**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md)  
**Status:** Draft  
**Owner:** Queen (with stack worker support)

## Scope

Grafana + Prometheus + exporters stack (`grafana-prom/docker-compose.yml`). Observability for the NAS and container metrics.

## Baseline inheritance

- **Logging:** `json-file` with `max-size` / `max-file` on all services.
- **Images:** Pinned semver tags (Grafana `13.0.1`, Prometheus `v3.11.3`, node-exporter `v1.11.1`, snmp-exporter `v0.30.1`, cAdvisor unchanged digest-style tag).
- **Env:** `SYNO_UID` / `SYNO_GID` in `.env` (see `.env.example`) — avoids bash `UID`/`GID` reserved names in tooling.
- **Secrets:** `grafana-prom/.env` is gitignored; never commit tokens or NAS-specific credentials.
- **Watchtower:** Fleet upgrades are owned **only** by [`../../../../watchtower/compose.yaml`](../../../../watchtower/compose.yaml). This stack must not run a second Watchtower instance. Prometheus scrapes Watchtower metrics at `10.0.1.15:18787/v1/metrics` using `bearer_token_file` → bind-mount of `grafana-prom/secrets/watchtower_bearer_token.txt` (same file as the Watchtower Docker secret; see [`../../../../grafana-prom/secrets/README.md`](../../../../grafana-prom/secrets/README.md)).

## HAProxy / TLS gate

No HAProxy routing changes until this stack meets baseline acceptance and evidence is recorded per [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md).

## Prometheus / Watchtower metrics

`prom.yml` includes a `watchtower` job: bearer token from `secrets/watchtower_bearer_token.txt` (see `secrets/README.md`), target `10.0.1.15:18787` (fleet Watchtower HTTP API port published in `watchtower/compose.yaml`).

## Filename exception

Compose file is `docker-compose.yml` (not `compose.yaml`) — see [`../../COMPOSE_FILENAMES.md`](../../COMPOSE_FILENAMES.md).
