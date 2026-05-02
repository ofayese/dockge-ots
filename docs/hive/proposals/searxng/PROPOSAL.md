# PROPOSAL — searxng

**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md)

## Summary

Mostly compliant — has security_opt, restart, watchtower, mem/cpu, healthcheck on redis, and good cap-drop posture. Four gaps:

1. Pin `searxng/searxng:latest` (redis is already pinned to `valkey:8-alpine`).
2. Add healthcheck to `searxng` (redis already has one).
3. Add `TZ` env to both services.
4. Add `logging` blocks.
5. Add `.env.example` and `README.md`.
6. **Verify** `settings.yml` `secret_key` is not committed.

## Changes (ordered)

### Change 1 — Verify `settings.yml` is gitignored (operator action)

```bash
cd /Volumes/docker/dockge/stacks
git ls-files searxng/settings.yml
# Expected: empty (= ignored). If it prints the path, settings.yml is tracked.
```

If tracked, check whether it contains `secret_key`:
```bash
grep -i 'secret_key' searxng/settings.yml
```

If a real secret_key is present in a tracked file, **rotate it** (generate new with `openssl rand -hex 32`) and add `searxng/settings.yml` to root `.gitignore`. Commit the gitignore update; the rotation makes the historical-git-history exposure low-impact.

### Change 2 — `.env.example` and `README.md`

`searxng/.env.example`:
```
# Stack: searxng
# All keys are tunables, not secrets (the secret_key lives in settings.yml).
TZ=America/New_York
UWSGI_WORKERS=4
UWSGI_THREADS=4
SEARXNG_BASE_URL=https://search.otsorundscore.olutechsys.com/
```

`searxng/README.md`:
```markdown
# searxng
Privacy-respecting metasearch engine, backed by Valkey (Redis fork) for caching.

## Services
- redis (Valkey) — ephemeral cache (`--save "" --appendonly no`)
- searxng (8888) — uWSGI web frontend; depends on redis healthcheck

## Public hostname
- search.otsorundscore.olutechsys.com (frontend; via HAProxy stretch when ready)

## Required state
- /volume1/docker/dockge/stacks/searxng/config/settings.yml (NOT in git; contains secret_key)

## Health
- redis: `valkey-cli ping` returns PONG
- searxng: HTTP 200 on `/` (or `/healthz` if your version exposes it)

## Rollback
- `git checkout -- searxng/compose.yaml && docker compose -f searxng/compose.yaml up -d`
- Cache is ephemeral; no data loss on restart.
- settings.yml NOT touched by `git checkout` (it's gitignored).

## Capability whitelist
searxng runs with `cap_drop: ALL` and only adds `CHOWN/SETGID/SETUID` (needed for first-run permission fixups). Do not narrow without testing — settings.yml writes will fail otherwise.
```

### Change 3 — Pin `searxng` image, add healthcheck + TZ + logging

```bash
docker pull searxng/searxng:latest
docker image inspect --format '{{index .RepoDigests 0}}' searxng/searxng:latest
```

```yaml
  searxng:
    container_name: SearXNG
    image: searxng/searxng:latest@sha256:<resolved>      # was :latest
    mem_limit: 512m
    cpu_shares: 768
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped
    ports:
      - 10.0.1.15:8888:8080
    volumes:
      - /volume1/docker/dockge/stacks/searxng/config:/etc/searxng:rw
    environment:
      - SEARXNG_BASE_URL=${SEARXNG_BASE_URL:-https://search.otsorundscore.olutechsys.com/}
      - SEARXNG_REDIS_URL=redis://redis:6379/0
      - UWSGI_WORKERS=${UWSGI_WORKERS:-4}
      - UWSGI_THREADS=${UWSGI_THREADS:-4}
      - TZ=${TZ:-America/New_York}
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - bridge
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/healthz >/dev/null 2>&1 || wget -qO- http://localhost:8080/ >/dev/null || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    labels:
      - com.centurylinklabs.watchtower.enable=true
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

(redis service: add `TZ=${TZ:-America/New_York}` env and `logging:` block. Already has healthcheck.)

**Healthcheck note:** `/healthz` exists on newer searxng builds; the fallback to `/` covers older versions.

## Verification

```bash
cd /Volumes/docker/dockge/stacks/searxng
docker compose -f compose.yaml config
docker compose -f compose.yaml up -d
sleep 30
docker inspect --format '{{.State.Health.Status}}' SearXNG-Redis SearXNG
# Expect: both healthy
curl -fs 'http://10.0.1.15:8888/search?q=test&format=json' | jq '.results[0].title'
# Expect: a search result
```

## Rollback

```bash
git checkout -- searxng/compose.yaml searxng/README.md
docker compose -f searxng/compose.yaml up -d
```

## Open questions (operator)

1. **Image-pinning preference:** digest or semver tag? `searxng/searxng` doesn't tag explicit semver — they ship `:latest` plus date-suffixed tags. Digest is the realistic option.
2. **Public exposure via HAProxy** — once HAProxy stretch lands and `search.otsorundscore...` is live publicly, audit `settings.yml` for bot/CAPTCHA settings, rate limits, and `instance_name`. Out of scope here.
3. **`/healthz` endpoint** — confirm it exists in the version you pin to. Fallback in the proposed healthcheck handles the case where it doesn't, but the cleaner option is to know.
