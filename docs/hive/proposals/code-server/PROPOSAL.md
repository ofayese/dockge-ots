# PROPOSAL — code-server

**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md)

## Summary

This stack is one of the better-built ones — explicit semver tags, healthchecks present, `.env.example` exists. Three changes:

1. Add `security_opt: [no-new-privileges:true]` to `db` (only service in this stack missing it).
2. ~~Decision on `restart`~~ — resolved: all services use `restart: unless-stopped` per repo conventions (2026-05-01).
3. Add `logging` blocks to all three services.
4. Add stack `README.md`.

Plus a **scope question** for the queen (see Open questions) — `db`/`phpmyadmin` here overlap with the separate `databases` stack.

## Changes (ordered)

### Change 1 — `security_opt` on `db`

**Before** (compose.yaml line 38–43):
```yaml
  db:
    image: mysql:8.3
    container_name: CodeServerDB
    mem_limit: 2g
    cpu_shares: 512
    restart: unless-stopped
```

**After:**
```yaml
  db:
    image: mysql:8.3
    container_name: CodeServerDB
    mem_limit: 2g
    cpu_shares: 512
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped
```

**Rationale:** `code-server` and `phpmyadmin` already have it; `db` is the lone exception in this stack. mysql:8.3 supports `no-new-privileges` without issue.

### Change 2 — `restart` baseline

All three services use **`restart: unless-stopped`** per `HIVE_OBJECTIVE.md` conventions (no `always` / `on-failure:5` exceptions in tracked compose).

### Change 3 — Add `logging` block to all three services

Per `_baseline §1`:
```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

Identical block on `code-server`, `db`, `phpmyadmin`.

### Change 4 — Stack `README.md`

Skeleton at `code-server/README.md`:
```markdown
# code-server
Browser-based VS Code (`code-server`) with adjacent MySQL (`db`) and phpMyAdmin (`phpmyadmin`).

## Services
- code-server (8377) — IDE; mounts host `docker.sock` (rw) and project paths
- db (3307) — MySQL 8.3, project-scoped data via named volume `mysql_data`
- phpmyadmin (8378) — DB admin UI, depends on `db` healthcheck

## Required env (.env)
- CODE_SERVER_HASHED_PASSWORD — bcrypt hash; generate with `caddy hash-password` or `htpasswd -bnBC 12 "" $pw | tr -d ':\n'`
- MYSQL_ROOT_PASSWORD
- PMA_CONTROLPASS  (also used as MYSQL_PASSWORD for the appuser)
- PMA_BLOWFISH_SECRET — 32-char random; `openssl rand -hex 16`
- (optional) PUID, PGID, TZ, DOCKER_USER, MYSQL_DATABASE, MYSQL_USER, PMA_*

## Health
- code-server: HTTP 200 on `/`
- db: `mysqladmin ping` succeeds
- phpmyadmin: HTTP 200 on `/`

## Rollback
- `git checkout -- code-server/compose.yaml && docker compose -f code-server/compose.yaml up -d`
- DB data persists in named volume `mysql_data` — survives stack rebuild but NOT `docker volume rm mysql_data`.

## Trust assumption
The IDE has rw access to `/var/run/docker.sock` and `/volume1/{docker,homes/ofayese}`. Effectively root on host. Acceptable for personal lab; flag if access model widens.
```

## Verification

```bash
cd /Volumes/docker/dockge/stacks/code-server
docker compose -f compose.yaml config       # confirm syntax
docker compose -f compose.yaml up -d
sleep 30
docker inspect --format '{{.State.Health.Status}}' CodeServer CodeServerDB CodeServerPMA
# Expect all three: healthy
curl -fs http://10.0.1.15:8377/             # code-server (login page)
curl -fs http://10.0.1.15:8378/             # phpmyadmin
docker exec CodeServerDB mysqladmin ping -uroot -p"$MYSQL_ROOT_PASSWORD"
```

## Rollback

```bash
git checkout -- code-server/compose.yaml code-server/README.md
docker compose -f code-server/compose.yaml up -d
```

## Open questions (operator)

1. **Scope: db duplication.** `code-server.db` (mysql:8.3) coexists with `databases.mariadb` + `databases.postgres`. Are they intentionally separate (project DBs vs admin DBs), or is one redundant? A separate `_db-consolidation/` proposal would address this if needed; this PROPOSAL leaves both stacks as-is.

2. **Image pinning — already on semver tags; do you want digest pins?** `mysql:8.3` and `phpmyadmin/phpmyadmin:5.2.3-apache` are explicit minor tags. Per `_baseline §3` they qualify as "Alternate (semver)" — acceptable. Upgrade to digests only if you've been bitten by silent minor-version drift.

3. **`docker.sock` rw on `code-server`** — flagged by inventory.py auto-detection. Keep rw (IDE features that exec containers, build images, etc. need it) or narrow to `:ro` and accept a smaller IDE feature set?
