# grafana-prom — Grafana + Prometheus stack

Synology-oriented **Grafana** + **Prometheus** + exporters (`node-exporter`, `snmp-exporter`, **cAdvisor**). Compose file: [`docker-compose.yml`](./docker-compose.yml).

## Ports (defaults)

| Service       | Host port       | Notes                                 |
| ------------- | --------------- | ------------------------------------- |
| Grafana       | `3340`          | Web UI                                |
| Prometheus    | internal `9090` | Scrapes targets defined in `prom.yml` |
| SNMP exporter | `9116`          |                                       |
| Node exporter | `9100`          |                                       |
| cAdvisor      | `8080`          | Container metrics UI                  |

## Paths (NAS)

All bind mounts in `docker-compose.yml` use **absolute** paths under `/volume1/​docker/dockge​/stacks/grafana-prom/` (data dirs, `prom.yml`, `snmp.yml`, `secrets/`). Create data dirs before first start:

```bash
mkdir -p /volume1/​docker/dockge​/stacks/grafana-prom/data/grafana \
  /volume1/​docker/dockge​/stacks/grafana-prom/data/prometheus
sudo bash /volume1/​docker/dockge/scripts/fix-permissions.sh
```

## Environment

Copy [`.env.example`](./.env.example) → `.env`. **`SYNO_UID` / `SYNO_GID`** default to **0** (root) for NAS; see `HIVE_OBJECTIVE.md` for rationale.

## cAdvisor / docker.sock

**cAdvisor** mounts host `/`, `/sys`, `/var/run`, and **`/var/run/docker.sock` (ro)** for metrics. This is a **documented NAS exception** (see `HIVE_OBJECTIVE.md` → NAS Deployment Notes). Do not widen mounts without review.

## Offline / outbound

Image pulls require **HTTPS 443** to container registries and (for plugins) Grafana.net unless mirrored.

## Backup

This stack does **not** use a host `db/` bind for a database engine; Prometheus and Grafana state live under **`${STACK_ROOT}/grafana-prom/data/`**.

| Directory                                                     | Hyper Backup | Method    |
| ------------------------------------------------------------- | ------------ | --------- |
| `${STACK_ROOT}/grafana-prom/data`                             | Include      | File copy |
| `${STACK_ROOT}/grafana-prom/prom.yml`, `snmp.yml`, `secrets/` | Include      | File copy |

Use **Hyper Backup** for off-device retention; pair with **Snapshot Replication** on the BTRFS volume per `docs/hive/NAS_DEPLOYMENT.md`.
