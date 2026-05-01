# databases

MariaDB + PostgreSQL + Adminer for any service that needs a shared DB. Distinct from `code-server`'s embedded MySQL (which is project-local).

## Services

- **mariadb** — file-based secrets at `/run/secrets/{mariadb_root_pw,mariadb_app_pw}`
- **postgres** — file-based secret at `/run/secrets/postgres_pw`
- **adminer** (8895) — UI; depends on both DBs being healthy

## Secrets (file-based, outside `.env`)

- `/volume1/docker/dockge/stacks/databases/secrets/mariadb_root_pw.txt` (mode `0600`)
- `/volume1/docker/dockge/stacks/databases/secrets/mariadb_app_pw.txt` (mode `0600`)
- `/volume1/docker/dockge/stacks/databases/secrets/postgres_pw.txt` (mode `0600`)

Verify with:

```bash
ls -la /volume1/docker/dockge/stacks/databases/secrets/
git check-ignore databases/secrets/mariadb_root_pw.txt   # expect: prints path = ignored
```

If any file is mode `0644` or worse: `chmod 0600 /volume1/docker/dockge/stacks/databases/secrets/*.txt`.

## Health

- mariadb: `healthcheck.sh --connect --innodb_initialized`
- postgres: `pg_isready -U appuser -d appdb`
- adminer: HTTP 200 on `/`

## Rollback

```bash
git checkout -- databases/compose.yaml
docker compose -f databases/compose.yaml up -d
```

Data persists at `/volume1/docker/dockge/stacks/databases/{mariadb,postgres}`. Back up before any major-version bump.

## Out of scope

Backup strategy lives in `docs/hive/proposals/_backups/PROPOSAL.md` (queen-led).
