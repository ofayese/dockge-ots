# databases

MariaDB + PostgreSQL + Adminer for any service that needs a shared DB. Distinct from `code-server`'s embedded MySQL (which is project-local).

## Services

- **mariadb** — file-based secrets at `/run/secrets/{mariadb_root_pw,mariadb_app_pw}`
- **postgres** — file-based secret at `/run/secrets/postgres_pw`
- **adminer** (8895) — UI; depends on both DBs being healthy

## Volumes

| Host path                             | Container path             | Purpose                |
| ------------------------------------- | -------------------------- | ---------------------- |
| `${STACK_ROOT}/databases/db/mariadb`  | `/var/lib/mysql`           | MariaDB engine data    |
| `${STACK_ROOT}/databases/db/postgres` | `/var/lib/postgresql/data` | PostgreSQL engine data |

> `STACK_ROOT` is resolved by `scripts/init-nas.sh` after `git clone`. On Synology use **`/volume1/docker/dockge/stacks`** (see `.env.example` and repo `CLAUDE.md`).

## Secrets (file-based, outside `.env`)

Create **gitignored** files under `${STACK_ROOT}/databases/secrets/` (mode `0600`):

- `${STACK_ROOT}/databases/secrets/mariadb_root_pw.txt`
- `${STACK_ROOT}/databases/secrets/mariadb_app_pw.txt`
- `${STACK_ROOT}/databases/secrets/postgres_pw.txt`

Verify with:

```bash
ls -la "${STACK_ROOT}/databases/secrets/"
git check-ignore "${STACK_ROOT}/databases/secrets/mariadb_root_pw.txt"   # expect: prints path = ignored
```

If any file is mode `0644` or worse: `chmod 0600 "${STACK_ROOT}/databases/secrets/"*.txt`.

## Health

- mariadb: `healthcheck.sh --connect --innodb_initialized`
- postgres: `pg_isready -U appuser -d appdb`
- adminer: HTTP 200 on `/`

## Rollback

```bash
git checkout -- compose.yaml
docker compose up -d
```

Data persists under `${STACK_ROOT}/databases/db/`. Back up before any major-version bump.

## Backup

| Directory                    | Hyper Backup | Method                                                                                          |
| ---------------------------- | ------------ | ----------------------------------------------------------------------------------------------- |
| `${STACK_ROOT}/databases/db` | **Exclude**  | Database dumps (`docker exec` → vendor tools; see `docs/hive/NAS_DEPLOYMENT.md` → Hyper Backup) |

There is no separate app-level `data/` bind for this stack; engine files live under **`db/`** only.

## Out of scope

Backup strategy lives in `docs/hive/proposals/_backups/PROPOSAL.md` (queen-led).
