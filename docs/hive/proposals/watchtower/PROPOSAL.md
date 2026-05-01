# PROPOSAL — watchtower

**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md)

## Summary

Watchtower is the fleet's image-update agent — pinning policy here is special-cased per `_baseline §3` (semver-tag preferred over digest, so the agent stays current on Docker daemon CVE patches without manual digest rotation).

Four changes:

1. Pin `containrrr/watchtower:latest` to an explicit semver tag.
2. Add healthcheck.
3. Add `logging` block.
4. Add `.env.example` and `README.md`.

## Changes (ordered by phase)

### Phase A — non-runtime

`watchtower/.env.example`:
```
# Stack: watchtower
# All keys are tunables, not secrets. Override the URL to enable real notifications.
TZ=America/New_York
WATCHTOWER_LABEL_ENABLE=true
WATCHTOWER_CLEANUP=true
WATCHTOWER_INCLUDE_STOPPED=false
WATCHTOWER_SCHEDULE=0 0 4 * * *
WATCHTOWER_NOTIFICATIONS=shoutrrr
WATCHTOWER_NOTIFICATION_URL=logger://
WATCHTOWER_NOTIFICATION_REPORT=true
```

`watchtower/README.md`:
```markdown
# watchtower
Scheduled image-update agent. Updates only containers labeled `com.centurylinklabs.watchtower.enable=true` (opt-in).

## Schedule
Daily at 04:00 America/New_York (`WATCHTOWER_SCHEDULE=0 0 4 * * *`).
Cron format: sec min hour dom mon dow.

## Behavior
- Only opt-in containers (`WATCHTOWER_LABEL_ENABLE=true`)
- Cleans up old images after update (`WATCHTOWER_CLEANUP=true`)
- Skips stopped containers
- Notifies via `WATCHTOWER_NOTIFICATION_URL` — currently `logger://` (logs only). Change to a Discord/Slack webhook for real alerts.

## Pinning policy interaction
Watchtower will pull patch/minor updates for any opt-in image whose tag is itself rolling (e.g. `:latest`, `:lts`, `:main`). For digest-pinned images, Watchtower notifies but cannot update — upgrades are manual by changing the digest in compose.yaml.

## Health
HTTP probe on `/v1/health` (verify endpoint exists in pinned version).

## Rollback
`git checkout -- watchtower/compose.yaml && docker compose -f watchtower/compose.yaml up -d`
```

### Phase B — runtime: healthcheck + logging + TZ

```yaml
services:
  watchtower:
    container_name: Watchtower
    image: containrrr/watchtower:1.7.1     # see Phase C — pin to current semver, not :latest
    mem_limit: 128m
    cpu_shares: 256
    security_opt:
      - no-new-privileges:true
    restart: on-failure:5
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - TZ=${TZ:-America/New_York}
      - WATCHTOWER_LABEL_ENABLE=${WATCHTOWER_LABEL_ENABLE:-true}
      - WATCHTOWER_CLEANUP=${WATCHTOWER_CLEANUP:-true}
      - WATCHTOWER_INCLUDE_STOPPED=${WATCHTOWER_INCLUDE_STOPPED:-false}
      - WATCHTOWER_SCHEDULE=${WATCHTOWER_SCHEDULE:-0 0 4 * * *}
      - WATCHTOWER_NOTIFICATIONS=${WATCHTOWER_NOTIFICATIONS:-shoutrrr}
      - WATCHTOWER_NOTIFICATION_URL=${WATCHTOWER_NOTIFICATION_URL:-logger://}
      - WATCHTOWER_NOTIFICATION_REPORT=${WATCHTOWER_NOTIFICATION_REPORT:-true}
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/v1/health >/dev/null 2>&1 || exit 1"]
      interval: 60s          # checked once a minute is plenty for a cron agent
      timeout: 5s
      retries: 3
      start_period: 15s
    networks:
      - bridge
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

networks:
  bridge:
    external: true
```

**Notes:**
- Watchtower's `/v1/health` endpoint requires `WATCHTOWER_HTTP_API_METRICS=true` or `WATCHTOWER_HTTP_API_PERIODIC_POLLS=true` in some versions — **verify** against `1.7.1` (or whichever version you pin). If endpoint isn't enabled, the alternative healthcheck is a process check: `["CMD", "pgrep", "watchtower"]`.
- `:latest` → `1.7.1` is illustrative; replace with the actual current latest at apply time. Per `_baseline §3` exception: prefer semver tag over digest **here** so security patches arrive without operator action.
- All env values now use `${VAR:-default}` interpolation, so `.env` overrides take precedence and the in-tree compose carries safe defaults.

### Phase C — image pinning

```bash
# Find current latest:
docker pull containrrr/watchtower:latest
docker inspect containrrr/watchtower:latest --format '{{.Config.Labels.org.opencontainers.image.version}}'
# → outputs e.g. "1.7.1" (or check Docker Hub directly)
```

Then write `image: containrrr/watchtower:1.7.1` in compose.yaml. Bump the tag deliberately when CVEs require.

### Phase D — Watchtower itself

Watchtower does **not** auto-update itself by label even with the watchtower-enable label set on its own container — by design (avoid the agent updating the agent mid-run). Manual tag bumps remain the operator's job. Document this in README.

## Verification

```bash
cd /Volumes/docker/dockge/stacks/watchtower
docker compose -f compose.yaml config
docker compose -f compose.yaml up -d
sleep 30
docker inspect --format '{{.State.Health.Status}}' Watchtower
# Expect: healthy
docker logs Watchtower --tail 20
# Expect: "Watchtower 1.7.1" or similar version banner; "Scheduling first run..."
```

## Rollback

```bash
git checkout -- watchtower/compose.yaml watchtower/README.md
docker compose -f watchtower/compose.yaml up -d
```

## Open questions (operator)

1. **Real notification channel** — `WATCHTOWER_NOTIFICATION_URL=logger://` only logs locally. Want a Discord webhook (`discord://<token>@<channel-id>`) or Slack? If yes, move to `.env`.
2. **Rolling restarts** — set `WATCHTOWER_ROLLING_RESTART=true` to update one container at a time? Reduces downtime if a stack has multiple replicas (none of yours do today, but worth flagging).
3. **Rollback policy** — Watchtower has no built-in rollback. If a new image fails, the container is down until the next operator intervention. Consider whether `WATCHTOWER_LIFECYCLE_HOOKS` should run a smoke test before/after update.
