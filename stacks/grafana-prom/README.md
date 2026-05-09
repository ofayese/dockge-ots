# grafana-prom — Grafana + Prometheus stack

Synology-oriented **Grafana** + **Prometheus** + exporters (`node-exporter`, `snmp-exporter`, **cAdvisor**). Compose file: [`compose.yaml`](./compose.yaml).

## Ports (defaults)

| Service       | Host port       | Notes                                 |
| ------------- | --------------- | ------------------------------------- |
| Grafana       | `3340`          | Web UI                                |
| Prometheus    | internal `9090` | Scrapes targets defined in `prom.yml` |
| SNMP exporter | `9116`          |                                       |
| Node exporter | `9100`          |                                       |
| cAdvisor      | `8080`          | Container metrics UI                  |

## Volumes

| Host path                                                        | Container path                            | Purpose                                                                   |
| ---------------------------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------- |
| `${STACK_ROOT}/grafana-prom/data/grafana`                        | `/var/lib/grafana`                        | Grafana UI state, dashboards, plugins                                     |
| `${STACK_ROOT}/grafana-prom/data/prometheus`                     | `/prometheus`                             | Prometheus TSDB                                                           |
| `${STACK_ROOT}/grafana-prom/prom.yml`                            | `/etc/prometheus/prometheus.yml`          | Prometheus scrape config                                                  |
| `${STACK_ROOT}/grafana-prom/snmp.yml`                            | `/etc/snmp_exporter/snmp.yml`             | SNMP exporter config                                                      |
| `${STACK_ROOT}/grafana-prom/secrets/watchtower_bearer_token.txt` | `/etc/prometheus/watchtower_bearer_token` | Bearer token file for Watchtower metrics scrape (read-only in Prometheus) |

> `STACK_ROOT` is written by `scripts/init-nas.sh` after `git clone`. On Synology use **`/volume1/docker/dockge/stacks`** (see each stack’s `.env.example` and repo `CLAUDE.md`).

## Bootstrap (first deploy)

```bash
mkdir -p "${STACK_ROOT}/grafana-prom/data/grafana" "${STACK_ROOT}/grafana-prom/data/prometheus"
sudo bash scripts/fix-permissions.sh
```

Run `fix-permissions.sh` from the **git repo root** (the directory that contains `HIVE_OBJECTIVE.md`).

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
