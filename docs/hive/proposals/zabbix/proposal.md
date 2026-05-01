# Zabbix stack — proposal

## Goal

Run Zabbix Server (PostgreSQL backend), web UI, and optional Agent 2 under Dockge with `${STACK_ROOT}` bind mounts, Synology-safe compose (no `depends_on` conditions), and documented SNMPv3 integration for DiskStation monitoring.

## References (consulted, not copied verbatim)

- [Marius Hosting — Zabbix on Synology](https://mariushosting.com/how-to-install-zabbix-on-your-synology-nas/) — image families (`postgres`, `zabbix-server-pgsql`, `zabbix-web-nginx-pgsql`), reverse-proxy port pattern (host **8532** → container **8080**), DSM SNMPv3 enablement, and community template link.
- [Zabbix community templates — Synology SNMPv3 (6.4)](https://github.com/zabbix/community-templates/blob/main/Storage_Devices/Synology/template_synology_diskstation_snmpv3/6.4/template_synology_diskstation_snmpv3.yaml) — template macros for credentials (see below).

## SNMPv3 template macros (6.4 YAML)

The 6.4 community template defines macros including:

- `{$SNMP_USERNAME}`
- `{$SNMP_AUTHPASS}`
- `{$SNMP_PRIVPASS}`

Map these in the Zabbix UI to your DSM SNMPv3 user and authentication/privacy passphrases. (Some docs use alternate spellings such as `{$SNMP_USER}` / `{$SNMP_AUTH_PASSWORD}` / `{$SNMP_PRIV_PASSWORD}`; align names to the imported template version.)

## Images

- `postgres:15-alpine` — pinned major aligned with repo baseline; Marius guide used `postgres:16`; operator may bump via proposal.
- `zabbix/zabbix-server-pgsql:7.4-alpine` and `zabbix/zabbix-web-nginx-pgsql:7.4-alpine` — track Marius “7.4.x” line; upgrade via digest or explicit tag after `docker pull` inspection.

## Volumes

See stack `README.md` — host paths use `${STACK_ROOT}/zabbix/...` created by `scripts/init-nas.sh`.

## Rollback

- `docker compose down` in stack folder (data retained on bind mounts unless operator removes dirs).
- Restore Postgres from backup if needed; Zabbix metadata lives under `${STACK_ROOT}/zabbix/db`.

## Risks

- Default `POSTGRES_PASSWORD` in `.env.example` must be replaced before production.
- Zabbix trapper port `10051` exposed; restrict at firewall if not required LAN-wide.
