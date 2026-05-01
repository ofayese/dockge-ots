# Zabbix (server + web + PostgreSQL)

## Purpose

Network and host monitoring with Zabbix Server (PostgreSQL), nginx web frontend, and optional Agent 2. SNMPv3 on Synology DSM is the typical path for NAS metrics (see proposal).

## Ports

| Port | Service |
|------|---------|
| `${ZABBIX_WEB_PORT:-8532}` (host) | Zabbix web (HTTP inside container on 8080) |
| `${ZABBIX_SERVER_PUBLISH:-10051}` (host) | Zabbix server (trapper) |

## Environment

Copy `.env.example` to `.env` and set `POSTGRES_PASSWORD` to a strong value. `STACK_ROOT` is normally written by `scripts/init-nas.sh` at repo root.

## Volumes

| Host path | Container path | Purpose |
|-----------|----------------|---------|
| `${STACK_ROOT}/zabbix/db` | `/var/lib/postgresql/data` | PostgreSQL data |
| `${STACK_ROOT}/zabbix/data` | `/var/lib/zabbix` | Zabbix server state (SNMP traps, export, etc.) |
| `${STACK_ROOT}/zabbix/config` | `/etc/zabbix` | Reserved for optional **zabbix-agent2** (see commented service in `compose.yaml`) |

> `STACK_ROOT` is resolved by `scripts/init-nas.sh` after `git clone`. Default when no repo `stacks/` is detected: `/dockge/stacks`. Directories are created automatically. Override: `STACK_ROOT_OVERRIDE=/your/path sudo bash scripts/init-nas.sh`

## Dependencies

- Docker Compose (Dockge) on Synology or generic Linux host.
- Outbound HTTPS for image pulls.

## Health

- Postgres: `pg_isready` against `POSTGRES_USER` / `POSTGRES_DB`.
- Server: `zabbix_server -R diaginfo`.
- Web: `curl -f http://localhost:8080/ping`.

## Rollback

`docker compose down` in this stack directory; data remains on `${STACK_ROOT}/zabbix/*` until deleted.

## Watchtower

Label `com.centurylinklabs.watchtower.enable=true` on long-running services. Pin or digest-upgrade Zabbix images deliberately in production.

## Security

- No Docker socket mount.
- Replace default DB password before exposing the UI.
- Restrict `10051` / web port at the firewall if the UI is fronted by a reverse proxy.

## Operator notes

- Default Zabbix UI login after first boot: **Admin** / **zabbix** — change immediately.
- For Synology SNMPv3 + community template steps, see `docs/hive/proposals/zabbix/proposal.md`.
