# PROPOSAL — `_baseline` (M2/M3 fleet-wide standard)

**Owner:** Queen (cross-cutting per HIVE_OBJECTIVE.md RACI)
**Status:** Draft — needs queen approval before per-stack PROPOSALs reference it
**Generated:** 2026-04-30 (M2 Baseline parity + M3 Operability)

## Context

12 INVENTORY.md files (M1) revealed that the same five gaps appear repeatedly across the fleet: missing `logging` blocks, floating image tags, missing `TZ` env, missing `mem_limit`/`cpu_shares` rationale comments, and missing `.env.example` / `README.md`. Rather than copy-paste the same diff 12 times, this proposal defines the canonical pattern; per-stack proposals reference it and only spell out deviations.

This is per HIVE_OBJECTIVE.md M2 (baseline parity) and M3 (operability). Each stack's `compose.yaml` must either match these blocks or carry a documented exception in its own PROPOSAL.

---

## §1 Logging block (Dozzle-friendly)

Every service gets the same block. Dozzle (the cross-cutting log-visibility owner) consumes this; without it, log files grow unbounded.

```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

**Rationale:** `json-file` is the default Synology Docker driver and what Dozzle reads natively. `max-size: 10m` × `max-file: 3` caps each container at ~30 MB of log on disk while preserving enough history for triage. Safe default; tighten per-service later if a chatty container demands it.

**Exceptions:** none expected. Even `dozzle` itself benefits from a logging cap on its own meta-logs.

---

## §2 Timezone

Every service that has an `environment` block adds:

```yaml
    environment:
      - TZ=America/New_York
```

(or equivalent map form — keep style consistent with the rest of the file).

**Rationale:** Synology host runs `America/New_York`. Containers inherit UTC otherwise, which makes log correlation across host and container painful.

**Exceptions:**
- Services with no `environment` block (e.g. `it-tools`, `dozzle`'s redis when added) may add a one-line block solely to set TZ, or skip TZ entirely with a documented exception in the stack PROPOSAL.

---

## §3 Image pinning policy

Two acceptable patterns; **`:latest` is never acceptable** for production:

- **Preferred — digest pin:**
  ```yaml
      image: corentinth/it-tools:latest@sha256:<64-hex>
  ```
  Resolved via `docker pull <image>:<tag>` followed by `docker image inspect --format '{{index .RepoDigests 0}}' <image>`. Watchtower will still notify but won't auto-update; upgrades are deliberate.

- **Alternate — explicit semver tag:**
  ```yaml
      image: codercom/code-server:4.117.0-39
  ```
  Use when digest pinning breaks the image's first-run logic (rare but happens with images that self-detect "latest" features), or when the project's release cadence makes digest pins churn too fast.

**Exception — `containrrr/watchtower`:** explicit semver tag preferred over digest, so Watchtower itself stays current relative to Docker daemon CVE patches without manual intervention beyond the tag bump.

Each stack PROPOSAL must declare the chosen approach per service with one-line rationale.

---

## §4 Resource limits

Every service must have:

```yaml
    mem_limit: <value>     # one-line rationale comment beside this line
    cpu_shares: <value>    # baseline 256 (background) / 512 (typical) / 768 (search/web) / 1024 (heavy)
```

**Right-sizing process:**
1. Check the service's current observed RSS with `docker stats --no-stream`.
2. Set `mem_limit` to ~1.5× observed peak (allow headroom for spikes).
3. `cpu_shares` is relative weight; defaults above are a starting ladder.
4. Add a one-line `# comment` directly above or beside the limit explaining the rationale (image size, model load, peak observed, etc.).

**Currently missing entirely:** `databases` (all 3), `ollama` (both), `portainer` (both). These are the priority targets.

---

## §5 Healthcheck

Every service that listens on a TCP port has a healthcheck. Format:

```yaml
    healthcheck:
      test: ["CMD-SHELL", "<probe>"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
```

**Probe selection (in priority order):**
1. **Native API endpoint** — e.g. `/health`, `/healthz`, `/-/healthz`, `/api/system/status`. Use `wget -qO- http://localhost:<port>/healthz || exit 1` (most upstream images ship with `wget` rather than `curl`).
2. **Service-specific CLI** — `valkey-cli ping`, `mysqladmin ping`, `pg_isready`, `mongosh --eval "db.adminCommand('ping')"`.
3. **HTTP root probe** — `wget -qO- http://localhost:<port>/ >/dev/null || exit 1`. Acceptable when no health endpoint exists.
4. **TCP probe** — `nc -z localhost <port>`. Last resort; only confirms the socket is open, not the app is healthy.

**Document impossibility** instead of forcing impossible probes:
- `acme-sh` runs `command: daemon` with no listener → no probe meaningful → exception.
- `network_mode: host` services may need `0.0.0.0` instead of `localhost`.

**`start_period` matters:** services with slow first-run init (mysql initdb, mongo data dir setup) need `30s`–`60s` to avoid restart loops on cold start.

---

## §6 `.env.example` per stack

Every stack with any environment variables (secret OR tunable) gets a top-level `.env.example` listing all keys with placeholder values. Format:

```
# Stack: <name>
# Required (secrets):
SECRET_KEY=
ANOTHER_SECRET=

# Optional (tunables):
TZ=America/New_York
LOG_LEVEL=info
```

**Rationale:** lets a fresh operator copy `.env.example` → `.env`, fill in real values, and bring up the stack without diving into compose.yaml to reverse-engineer requirements. Real `.env` stays gitignored (root `.gitignore` should already cover this — verify per stack).

**Currently present:** `code-server`, `portainer`. **Missing:** the other 10 stacks.

---

## §7 `README.md` per stack

One-page document covering: purpose, services, ports, env vars, dependencies, what "healthy" means, rollback procedure. ~30–60 lines.

**Currently present:** `homepage` (also has `CONTAINER_MAPPING.md`). **Missing:** the other 11 stacks.

---

## §8 `restart` baseline

HIVE_OBJECTIVE.md specifies `restart: on-failure:5`. Three stacks currently use `restart: always` (`code-server`, `portainer`).

**Decision needed (queen):**
- **Option A:** rewrite `always` → `on-failure:5` everywhere for strict baseline parity.
- **Option B:** keep `always` for IDE / orchestration UI services where you genuinely want them back regardless of exit code (operator convenience), and document the exception per-stack.

Recommend **Option B** — `always` for `code-server` and `portainer` is operator-friendly and the cost is bounded (Synology's Docker reaper handles runaway restarts). Per-stack PROPOSALs will document the exception inline.

---

## §9 Application order

When applying these baseline changes, batch by phase to limit blast radius:

1. **Phase A — non-runtime (safe to apply anytime):**
   - Add `.env.example` files
   - Add `README.md` files
   - These are repo-only changes, no container restart needed.

2. **Phase B — additive runtime (rolling restart per stack):**
   - Add `logging:` blocks
   - Add `TZ` envs
   - Add `mem_limit` / `cpu_shares` where missing
   - Apply via `docker compose up -d <service>` per stack; brief restart only.

3. **Phase C — image-pinning pass:**
   - Resolve current `:latest`/floating tags to specific digests or tags
   - Apply per-stack with operator review of the resolved digests
   - One stack at a time — easier rollback if a digest pin lands on a broken build.

4. **Phase D — healthcheck additions:**
   - Apply alongside Phase B or after, depending on whether dependent stacks use `condition: service_healthy`.

5. **Phase E — security tightening:**
   - `docker.sock :ro` (dozzle)
   - `security_opt` on missing services (code-server `db`, portainer_agent)

---

## §10 Out of scope for this proposal

These are tracked separately and require separate consensus:

- **Cross-cutting `_logging/`, `_monitoring/`, `_backups/`, `_haproxy/`** — per HIVE_OBJECTIVE.md RACI, these are queen-only proposals.
- **HAProxy/TLS gating policy:** HAProxy/TLS routing for any stack is allowed only after that stack passes baseline acceptance criteria.
- **Major image bumps** — explicitly forbidden without separate approval.
- **Removing `network_mode: host` from `acme-sh`** — explicitly forbidden.
- **Modifying `/volume1/certs/acme/`** — explicitly forbidden.
- **Splitting/merging the `code-server` (mysql) and `databases` (mariadb+postgres) stacks** — scope question; needs queen decision; a separate `_db-consolidation/` proposal would handle it.

---

## Verification (before merging this proposal)

- [ ] Queen confirms §3 pinning policy ladder (digest preferred / semver acceptable).
- [ ] Queen confirms §4 mem/cpu ladder (256/512/768/1024 cpu_shares; mem_limit at 1.5× observed RSS).
- [ ] Queen confirms §8 restart decision (recommend Option B).
- [ ] Per-stack PROPOSALs reference this file by relative path (`../_baseline/PROPOSAL.md`) and only diff against it.

## Rollback

This proposal is documentation-only. Per-stack PROPOSALs that reference it carry their own rollbacks (typically `git revert <commit>` after each Phase B/C/D/E batch).
