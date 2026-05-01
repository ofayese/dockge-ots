# PROPOSAL — codex-docs

**Owner:** worker `codex-docs` · **Generated:** 2026-04-30
**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md)

## Summary

This stack ships with `APP_SECRET=REPLACE_WITH_RANDOM_SECRET` literally hardcoded into `compose.yaml`. That is either:
- (a) a placeholder from initial scaffolding that was never finished, or
- (b) actively running with a known-bad secret in production.

Either way it must move out of `compose.yaml` into a gitignored `.env` before any other change.

Beyond that: standard baseline (pin codex-docs image, add codex-docs healthcheck, add TZ, logging).

## **PRECONDITION — operator confirmation needed**

Before applying anything below, confirm:

1. **Is this stack in active use?** If no (suspected — placeholder secret implies abandoned), the right action is `claude-flow hive-mind` flag-for-removal rather than baseline-parity. Don't waste cycles hardening a stack you intend to drop.
2. **If yes — has a real `APP_SECRET` ever been generated?** If no, this stack has been running with a guessable secret. Generate one immediately:
   ```bash
   openssl rand -hex 32
   ```
   and treat any data in MongoDB as compromised pending review.

## Changes (ordered, contingent on operator confirmation)

### Change 1 — Move `APP_SECRET` to `.env` (REQUIRED if stack stays)

**Before (`compose.yaml` line 39):**
```yaml
    environment:
      - MONGODB_URI=mongodb://mongodb:27017/codexdocs
      - APP_SECRET=REPLACE_WITH_RANDOM_SECRET
      - PORT=3000
```

**After:**
```yaml
    environment:
      - MONGODB_URI=mongodb://mongodb:27017/codexdocs
      - APP_SECRET=${APP_SECRET}
      - PORT=3000
      - TZ=America/New_York
```

**New file:** `codex-docs/.env.example`
```
# Stack: codex-docs
# Required (secrets):
APP_SECRET=                         # generate: openssl rand -hex 32

# Optional (tunables):
TZ=America/New_York
```

**New file:** `codex-docs/.env` (gitignored — verify root `.gitignore` covers `*/.env`):
```
APP_SECRET=<actual-random-hex-from-openssl>
TZ=America/New_York
```

**Rationale:** `compose.yaml` is committed; secrets must not be. Dockge / `docker compose` reads `<stack>/.env` automatically when the file is at the same level as `compose.yaml`.

### Change 2 — Add healthcheck to `codex-docs` service

**Before:**
```yaml
  codex-docs:
    container_name: CodexDocs
    image: codexteam/codex.docs:latest
    ...
    depends_on:
      mongodb:
        condition: service_healthy
```

**After (insert before `depends_on`):**
```yaml
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:3000/ >/dev/null || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
```

**Rationale:** mongodb has a healthcheck; the app does not. Without it, restart loops on bad config aren't detectable, and other services can't safely depend on this one.

### Change 3 — Pin `codex-docs` image

**Before:**
```yaml
    image: codexteam/codex.docs:latest
```

**After (digest pin — preferred):**
```yaml
    image: codexteam/codex.docs:latest@sha256:<resolve-with-docker-pull>
```

Resolve via:
```bash
docker pull codexteam/codex.docs:latest
docker image inspect --format '{{index .RepoDigests 0}}' codexteam/codex.docs:latest
```
Paste the `sha256:...` portion into `compose.yaml`.

**Or — semver tag (if upstream publishes one):**
```yaml
    image: codexteam/codex.docs:2.x.y
```

(Last verified: codexteam publishes `latest` mostly; semver tag availability needs a quick Docker Hub check.)

### Change 4 — Pin `mongo`

**Before:** `mongo:7`
**After:** `mongo:7.0.x` (specific minor) or `mongo:7@sha256:<digest>`.

`mongo:7` is a major-version alias and accepts any 7.x.y. Pinning the minor stops surprise upgrades.

### Change 5 — Apply remaining baseline blocks

For both services add per [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md) §1:
```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

Add `TZ=America/New_York` to `mongodb`'s environment (extend the existing one-key block).

### Change 6 — Stack `README.md`

Skeleton:

```markdown
# codex-docs
Internal documentation hub powered by codex.team's codex.docs CMS, backed by MongoDB.

## Services
- mongodb — data store, internal-only
- codex-docs — Node.js app, listens on 10.0.1.15:8896

## Required env (.env)
- APP_SECRET — random 64-char hex; rotate on compromise

## Health
- mongodb: `mongosh ping`
- codex-docs: HTTP 200 on `/`

## Rollback
- `git checkout -- codex-docs/compose.yaml && docker compose -f codex-docs/compose.yaml up -d`
- Mongo data persists at `/volume1/docker/dockge/stacks/codex-docs/mongodb`; never `rm -rf` without a snapshot.
```

## Verification

```bash
cd /Volumes/docker/dockge/stacks/codex-docs

# After creating .env from .env.example with real APP_SECRET:
docker compose -f compose.yaml config             # confirm interpolation worked
docker compose -f compose.yaml up -d
sleep 30
docker inspect --format '{{.State.Health.Status}}' CodexDocs CodexDocs-MongoDB
curl -fs http://10.0.1.15:8896/                   # expect 200

# Confirm secret no longer hardcoded:
grep 'APP_SECRET' compose.yaml                    # expect ${APP_SECRET}, not the literal
git ls-files codex-docs/.env                      # expect empty (file is gitignored)
```

## Rollback

```bash
git checkout -- codex-docs/compose.yaml
# Keep .env / .env.example — they shouldn't be tracked anyway.
docker compose -f codex-docs/compose.yaml up -d
```

## Open questions (operator)

1. **Active use?** — If no, route to a removal proposal instead.
2. **Secret status?** — Has the literal placeholder ever been replaced in the running container? Check `docker inspect CodexDocs --format '{{range .Config.Env}}{{println .}}{{end}}' | grep APP_SECRET`. If it shows `REPLACE_WITH_RANDOM_SECRET`, the running app has been using that since boot.
3. **Image pinning preference** — digest or semver?
