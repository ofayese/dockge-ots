# PROPOSAL — databases

**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md)

## Summary

Five gaps to close, plus one verification:

1. **HIGH** — add `mem_limit` / `cpu_shares` to all three services (currently missing on every one).
2. Pin `mariadb:lts` (rolling alias) and `adminer:latest` to specific tags or digests.
3. Add healthcheck to `adminer` (the only service in the stack without one).
4. Add `TZ=America/New_York` to all services.
5. Add `logging` blocks.
6. Add stack `README.md`.
7. **Verify** secrets directory is gitignored and files are mode `0600`.

## Changes (ordered by phase per `_baseline §9`)

### Phase A — non-runtime: stack `README.md`

`databases/README.md`:
```markdown
# databases
MariaDB + PostgreSQL + Adminer for any service that needs a shared DB. Distinct from `code-server`'s embedded MySQL (which is project-local).

## Services
- mariadb — file-based secrets at /run/secrets/{mariadb_root_pw,mariadb_app_pw}
- postgres — file-based secret at /run/secrets/postgres_pw
- adminer (8895) — UI; depends on both DBs being healthy

## Secrets (file-based; outside `.env` to avoid env-var disclosure)
- /volume1/docker/dockge/stacks/databases/secrets/mariadb_root_pw.txt   (mode 0600)
- /volume1/docker/dockge/stacks/databases/secrets/mariadb_app_pw.txt    (mode 0600)
- /volume1/docker/dockge/stacks/databases/secrets/postgres_pw.txt       (mode 0600)

## Health
- mariadb: `healthcheck.sh --connect --innodb_initialized`
- postgres: `pg_isready -U appuser -d appdb`
- adminer: HTTP 200 on `/`

## Rollback
- `git checkout -- databases/compose.yaml && docker compose -f databases/compose.yaml up -d`
- Data persists at `/volume1/docker/dockge/stacks/databases/{mariadb,postgres}` — back up before any major-version bump.

## Backup (out of scope here; see _backups/PROPOSAL.md)
```

### Phase B — additive runtime: `mem_limit`, `cpu_shares`, `TZ`, `logging`

Apply to all three services. Suggested values (right-size with `docker stats` after a week):

```yaml
  mariadb:
    # ... existing keys ...
    mem_limit: 1g           # rationale: typical small-app workload; bump to 2g if buffer pool needs it
    cpu_shares: 512
    environment:
      - MYSQL_ROOT_PASSWORD_FILE=/run/secrets/mariadb_root_pw
      - MYSQL_DATABASE=appdb
      - MYSQL_USER=appuser
      - MYSQL_PASSWORD_FILE=/run/secrets/mariadb_app_pw
      - TZ=America/New_York
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  postgres:
    mem_limit: 512m         # rationale: small-app workload; bump if shared_buffers tuned higher
    cpu_shares: 512
    environment:
      - POSTGRES_DB=appdb
      - POSTGRES_USER=appuser
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_pw
      - TZ=America/New_York
    logging:  # (same block)

  adminer:
    mem_limit: 256m         # rationale: PHP UI, low resource ceiling
    cpu_shares: 256
    environment:
      - ADMINER_DEFAULT_SERVER=mariadb
      - ADMINER_DESIGN=hydra
      - TZ=America/New_York
    logging:  # (same block)
```

### Phase C — pinning

**Before:** `mariadb:lts`, `adminer:latest`
**After (option A — digest):** resolve via `docker pull` then paste the digest:
```yaml
    image: mariadb:lts@sha256:<resolved>
    image: adminer:latest@sha256:<resolved>
```

**After (option B — explicit semver, recommended for mariadb):**
```yaml
    image: mariadb:11.4         # or whatever the current LTS major is
    image: adminer:4.8.1        # latest stable as of recent
```

`postgres:16-alpine` is fine as semver; optionally upgrade to digest.

### Phase D — healthcheck for `adminer`

Add to the `adminer` service:
```yaml
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/ >/dev/null || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
```

### Phase E — secrets verification (no compose change; operator action)

```bash
# 1. Confirm secret files exist
ls -la /volume1/docker/dockge/stacks/databases/secrets/

# 2. Confirm permissions are 0600 (or tighter)
stat -f '%N %Mp%Lp' /volume1/docker/dockge/stacks/databases/secrets/*.txt
# Expected: 0600 — readable only by owner

# 3. Confirm gitignored
cd /Volumes/docker/dockge/stacks
git check-ignore databases/secrets/mariadb_root_pw.txt
# Expected: prints the path (= ignored). If silent, ADD `databases/secrets/` to root .gitignore.
```

If any file is mode 0644 or worse, fix:
```bash
chmod 0600 /volume1/docker/dockge/stacks/databases/secrets/*.txt
```

## Verification

```bash
cd /Volumes/docker/dockge/stacks/databases
docker compose -f compose.yaml config
docker compose -f compose.yaml up -d
sleep 60       # mariadb cold start can take time
docker inspect --format '{{.State.Health.Status}}' MariaDB PostgreSQL Adminer
# Expect all three: healthy
curl -fs http://10.0.1.15:8895/                                # adminer login page
docker exec MariaDB mysqladmin ping -uroot -p"$(cat /volume1/docker/dockge/stacks/databases/secrets/mariadb_root_pw.txt)"
docker exec PostgreSQL pg_isready -U appuser -d appdb
```

## Rollback

```bash
git checkout -- databases/compose.yaml databases/README.md
docker compose -f databases/compose.yaml up -d
```

If a digest pin lands on a broken build, `git checkout` reverts to the prior tag/digest within seconds.

## Open questions (operator)

1. **Image-pinning preference: A (digest) or B (semver tag)?** Recommend B for `mariadb` (Watchtower can pull patch versions automatically) and A for `adminer` (rare to re-deploy).
2. **Right-sizing**: 1g / 512m / 256m above are starting points. After Phase B, run `docker stats --no-stream MariaDB PostgreSQL Adminer` for a week and adjust.
3. **Scope vs `code-server.db`**: see `code-server/PROPOSAL.md` open question 1. Same scope question.
