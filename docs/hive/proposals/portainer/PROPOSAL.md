# PROPOSAL — portainer

**Owner:** worker `portainer` · **Generated:** 2026-04-30
**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md)
**Priority:** HIGH (one critical fix: malformed env line)

## Summary

Three changes:
1. **CRITICAL** — fix the malformed `environment` line on `portainer` (currently `- https://10.0.1.15:9001` with no `KEY=value`).
2. Add `security_opt: [no-new-privileges:true]` to `portainer_agent` (consistency with portainer service and fleet baseline).
3. Apply baseline (logging, mem/cpu, healthcheck, pinning) per [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md).

`restart: always` is kept on both services as documented exception per `_baseline §8` Option B (operator convenience for orchestration UI).

## Changes (ordered)

### Change 1 — Fix malformed env line (CRITICAL)

**File:** `portainer/compose.yaml` lines 16–17

**Before:**
```yaml
    environment:
      - https://10.0.1.15:9001
```

**After (option A — remove, if the value was unused):**
```yaml
    # environment block removed — prior entry was malformed and not a real env var
```

**After (option B — interpret as edge-agent pairing URL, if intentional):**
```yaml
    environment:
      - EDGE_AGENT_URL=https://10.0.1.15:9001
```

**Rationale:** Compose `environment` list items must be `KEY=value`. The current entry has no `=` so Compose silently treats `https://10.0.1.15:9001` as the *name* of an env var to inherit from the host shell, which never exists. Either way it does nothing today; on a future Compose validator upgrade it could become a hard error.

**Decision needed (operator):** A or B? If you don't remember why this was added, A is safe.

### Change 2 — Add `security_opt` to `portainer_agent`

**Before (line 22):**
```yaml
  portainer_agent:
    image: portainer/agent:2.39.1
    container_name: portainer_agent
```

**After:**
```yaml
  portainer_agent:
    image: portainer/agent:2.39.1
    container_name: portainer_agent
    security_opt:
      - no-new-privileges:true
```

**Rationale:** Matches the `portainer` service already in this stack and fleet baseline. The agent runs with `cap_drop: ALL` already, so this is belt-and-suspenders.

### Change 3 — Add baseline blocks to both services

For each service, add (per `_baseline §1, §4, §5`):

```yaml
    mem_limit: 256m       # Portainer + agent are lightweight UIs/control planes
    cpu_shares: 512
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:9000/api/system/status >/dev/null || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

**For `portainer_agent`** the healthcheck differs:
```yaml
    healthcheck:
      test: ["CMD-SHELL", "nc -z localhost 9001 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
```

**Rationale:** agent has no public health endpoint; TCP probe on 9001 is the next-best signal per `_baseline §5`.

**Right-sizing:** 256m is a starting point. Run `docker stats portainer portainer_agent --no-stream` after a week and adjust if observed RSS > 170m.

## Verification

```bash
# 1. Compose syntax + interpolation
cd /Volumes/docker/dockge/stacks/portainer
docker compose -f compose.yaml config

# 2. Apply
docker compose -f compose.yaml up -d

# 3. Healthcheck status (wait ~30s)
docker inspect --format '{{.State.Health.Status}}' portainer
docker inspect --format '{{.State.Health.Status}}' portainer_agent

# 4. Confirm UI still reachable
curl -k https://10.0.1.15:9443/  # portainer UI
curl     http://10.0.1.15:9001/  # agent — expect connection (TLS handshake or 4xx)

# 5. Confirm log size cap took effect
docker inspect --format '{{json .HostConfig.LogConfig}}' portainer
```

Expect: `compose config` exits 0; both containers report `healthy` within 60s; UI loads; agent port responds.

## Rollback

```bash
cd /Volumes/docker/dockge/stacks
git diff portainer/compose.yaml         # review what changed
git checkout -- portainer/compose.yaml  # restore
docker compose -f portainer/compose.yaml up -d
```

If the issue is only the healthcheck (e.g. wrong endpoint), `git checkout -p` lets you revert just the healthcheck hunk.

## Open questions

1. **Change 1 — A or B?** Was `https://10.0.1.15:9001` intended as a real env var (and if so, what's the var name)?
2. **Healthcheck endpoint** — `/api/system/status` is the documented health route in modern Portainer CE. Confirm against the version you're pinned to (`portainer-ce:alpine-sts`).

## Out of scope (deferred)

- Splitting `portainer` and `portainer_agent` into separate Dockge stacks (currently one stack — fine; not worth the churn).
- Switching `image: portainer/portainer-ce:alpine-sts` → digest pin. Reasoning: `:alpine-sts` is already a deliberate sustained-release alias; treat like a semver tag per `_baseline §3` "Alternate" path, with the rationale logged here.
