# Task: Healthcheck Audit Fixes — All Issues

/coder
/compound-learning
/continuous-learning

======================================================================
CONTEXT
======================================================================

A full healthcheck audit was run across all 23 stacks on 2026-05-07.
Six issues were identified. This task fixes all of them.

Do NOT modify any file not listed in this task.

======================================================================
PHASE 0 — READ THESE FILES FIRST
======================================================================

  stacks/dozzle/compose.yaml
  stacks/portainer/compose.yaml
  stacks/searxng/compose.yaml
  stacks/code-server/compose.yaml
  stacks/agents_gateway_data/compose.yaml
  stacks/warp-main/compose.yaml

======================================================================
PHASE 1 — FIX 1: dozzle — replace --version with healthcheck subcommand
======================================================================

FILE: stacks/dozzle/compose.yaml

ISSUE: `CMD /dozzle --version` exits 0 regardless of whether the HTTP
server is actually listening. A crashed or starting container would
still pass this probe.

Dozzle ships a dedicated `healthcheck` subcommand. Use it.

CHANGE the healthcheck block from:

    healthcheck:
      test:
        - CMD
        - /dozzle
        - --version
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

TO:

    # Healthcheck type E: Dozzle built-in healthcheck subcommand.
    # --version exits 0 regardless of HTTP server state — do not use.
    # /dozzle healthcheck probes the actual HTTP listener on :8080.
    healthcheck:
      test:
        - CMD
        - /dozzle
        - healthcheck
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

======================================================================
PHASE 2 — FIX 2: portainer — add healthcheck to portainer_agent
======================================================================

FILE: stacks/portainer/compose.yaml

ISSUE: `portainer_agent` service has no healthcheck. The agent uses
mTLS on port 9001 so an HTTP probe would fail TLS verification.
Use a TCP probe which confirms the port is listening without needing TLS.

ADD a healthcheck block to the portainer_agent service.
Place it after the `cap_add:` block and before `environment:`.

ADD:

    # Healthcheck type C: TCP probe on agent port.
    # Agent uses mTLS — HTTP probe fails TLS. TCP confirms port is listening.
    healthcheck:
      test: ["CMD-SHELL", "nc -z 127.0.0.1 9001 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s

======================================================================
PHASE 3 — FIX 3: searxng — add healthcheck to searxng service
======================================================================

FILE: stacks/searxng/compose.yaml

ISSUE: Only the `redis` service has a healthcheck. The `searxng`
service itself has none. SearXNG serves HTTP on port 8080 and ships
wget in its Alpine-based image.

ADD a healthcheck block to the searxng service.
Place it after the `cap_add:` block and before `logging:`.

ADD:

    # Healthcheck type A: wget HTTP probe — SearXNG Alpine image has busybox wget.
    # /healthz is the SearXNG health endpoint (returns 200 when ready).
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s

======================================================================
PHASE 4 — FIX 4: code-server — fix mysqladmin ping missing password
======================================================================

FILE: stacks/code-server/compose.yaml

ISSUE: `mysqladmin ping -h localhost -uroot --silent` does not pass
a password. MySQL 8.3 requires auth even for ping operations. This
probe may emit warnings or fail intermittently depending on the
auth plugin configured.

Use the socket-based approach which bypasses TCP auth entirely, or
suppress the warning with stderr redirection.

CHANGE the db service healthcheck from:

    healthcheck:
      test:
        - CMD
        - mysqladmin
        - ping
        - -h
        - localhost
        - -uroot
        - --silent
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

TO:

    # Healthcheck type B: mysqladmin ping via socket (no password needed for socket auth).
    # TCP ping with -uroot --silent can fail on MySQL 8.3 auth plugin changes;
    # socket auth bypasses this cleanly.
    healthcheck:
      test:
        - CMD-SHELL
        - mysqladmin ping -h localhost --silent 2>/dev/null || exit 1
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

======================================================================
PHASE 5 — FIX 5: agents_gateway_data — add re-verify comment
======================================================================

FILE: stacks/agents_gateway_data/compose.yaml

ISSUE: wget was verified present in docker/mcp-gateway:v0.42.0 on
2026-05-07. This is unusual for a Go image. Add a re-verify reminder
so if the image is updated, the probe is re-checked.

CHANGE the healthcheck comment from:

    # Healthcheck type: A — HTTP /health probe (wget — verified 2026-05-07)
    # Port 8811 per published port mapping; upstream example uses /health
    # Source: https://raw.githubusercontent.com/docker/mcp-gateway/main/examples/health/compose.yaml

TO:

    # Healthcheck type: A — HTTP /health probe (wget confirmed in image — verified 2026-05-07).
    # NOTE: wget in a Go image is unusual. Re-verify after any image version bump:
    #   docker run --rm --entrypoint="" docker/mcp-gateway:<new-tag> which wget
    # Port 8811 per published port mapping; upstream example uses /health.
    # Source: https://raw.githubusercontent.com/docker/mcp-gateway/main/examples/health/compose.yaml

======================================================================
PHASE 6 — FIX 6: warp-main — add verification comment for warp-agent port
======================================================================

FILE: stacks/warp-main/compose.yaml

ISSUE: warp-agent healthcheck probes http://127.0.0.1:8080/ but
warp-claude-cli-sidecar also exposes port 8080 to the host. The probe
hits loopback so they don't conflict, but the agent's listening port
should be confirmed to avoid a false-passing probe.

CHANGE the warp-agent healthcheck comment from:

    # Healthcheck type: B — HTTP probe (curl; image has curl — verified 2026-05-07)

TO:

    # Healthcheck type: B — HTTP probe (curl confirmed — verified 2026-05-07).
    # NOTE: warp-agent must listen on 8080 internally for this probe to be valid.
    # warp-claude-cli-sidecar also exposes host port 8080 — no conflict since probe
    # hits 127.0.0.1 (loopback). Re-verify if warp-agent port changes upstream.

======================================================================
PHASE 7 — VALIDATE
======================================================================

STEP 1 — Compose validation for changed files:
  docker compose -f stacks/dozzle/compose.yaml config > /dev/null
  docker compose -f stacks/portainer/compose.yaml config > /dev/null
  docker compose -f stacks/searxng/compose.yaml config > /dev/null
  docker compose -f stacks/code-server/compose.yaml config > /dev/null
  docker compose -f stacks/agents_gateway_data/compose.yaml config > /dev/null
  docker compose -f stacks/warp-main/compose.yaml config > /dev/null
  Expected: no errors (env var warnings acceptable)

STEP 2 — Full repo validation:
  scripts/compose-validate.sh
  Expected: All compose files validated OK.

STEP 3 — Check no --version probes remain:
  grep -rn "\-\-version" stacks/*/compose.yaml | grep "healthcheck" -A2
  Expected: zero results

STEP 4 — Check no unhealthy healthchecks remain (no shell in scratch images):
  grep -rn "CMD-SHELL\|CMD-SHELL" stacks/watchtower/compose.yaml
  Expected: zero results (watchtower is scratch — CMD-SHELL must not be used)

STEP 5 — Pre-commit on changed files:
  pre-commit run --files \
    stacks/dozzle/compose.yaml \
    stacks/portainer/compose.yaml \
    stacks/searxng/compose.yaml \
    stacks/code-server/compose.yaml \
    stacks/agents_gateway_data/compose.yaml \
    stacks/warp-main/compose.yaml
  Expected: all hooks pass.

STEP 6 — Commit:
  git add \
    stacks/dozzle/compose.yaml \
    stacks/portainer/compose.yaml \
    stacks/searxng/compose.yaml \
    stacks/code-server/compose.yaml \
    stacks/agents_gateway_data/compose.yaml \
    stacks/warp-main/compose.yaml
  git commit -m \
    "fix: healthcheck audit — dozzle subcommand, portainer agent TCP probe, searxng probe, mysqladmin socket, re-verify comments"
  git push

======================================================================
PHASE 8 — COMPOUND MEMORY UPDATE
======================================================================

/compound-learning

Add a dated bullet to AGENTS.md under "## What Works":

  [$(date +%Y-%m-%d)] Healthcheck audit fixes (all stacks):
  - dozzle: CMD /dozzle --version is not a health probe — always exits 0.
    Correct probe: CMD /dozzle healthcheck (built-in subcommand).
    Rule: never use --version or --help as a healthcheck test.
  - portainer_agent: uses mTLS on 9001 — HTTP probe fails TLS.
    Use TCP probe: nc -z 127.0.0.1 9001. No HTTP client needed.
  - searxng: service had no healthcheck. /healthz endpoint returns 200
    when ready. busybox wget is available in the Alpine image.
  - mysqladmin ping without password: MySQL 8.3 auth plugin changes can
    cause --silent ping to fail or emit warnings. Use socket auth:
    mysqladmin ping -h localhost --silent 2>/dev/null
  - Go images with wget: unusual. Always re-verify after image updates.
  - Probe port conflicts: when two services share a network and a port,
    loopback probes (127.0.0.1) do not conflict — but the probed service
    must actually listen on that loopback port.

======================================================================
PHASE 9 — CONTINUOUS LEARNING
======================================================================

/continuous-learning

Extract to ~/.cursor/skills/learned/healthcheck-antipatterns.md:

  Title: Docker Healthcheck Anti-patterns
  
  Anti-pattern 1: --version as health probe
    WRONG: test: ["CMD", "/app", "--version"]
    WHY: exits 0 regardless of server state — startup/crash invisible
    CORRECT: use the app's own healthcheck subcommand or HTTP probe
    Examples: /dozzle healthcheck, /watchtower --health-check

  Anti-pattern 2: HTTP probe on mTLS-only port
    WRONG: test: ["CMD", "wget", "https://127.0.0.1:9001/"]
    WHY: TLS verification fails without cert, probe always fails
    CORRECT: TCP probe — nc -z 127.0.0.1 9001
    When to use TCP: agent ports, gRPC ports, any TLS-only endpoint

  Anti-pattern 3: mysqladmin ping without password in MySQL 8.3+
    WRONG: mysqladmin ping -h localhost -uroot --silent
    WHY: auth plugin changes in MySQL 8.3 may require password for TCP
    CORRECT: mysqladmin ping -h localhost --silent 2>/dev/null
    (socket auth bypasses password requirement)

  Anti-pattern 4: Missing healthcheck on dependent services
    Pattern: if service A depends_on service B, service B should have
    a healthcheck. Without one, depends_on is purely cosmetic.
    Check: any service in depends_on list should have healthcheck.

  Anti-pattern 5: Assuming wget in Go/Rust/scratch images
    Go and Rust images are often minimal — verify with:
      docker run --rm --entrypoint="" <image> which wget
    If absent: use nc, curl, or the app's own binary probe.

======================================================================
FINAL PRINT
======================================================================

Print summary table:

  | Stack               | Service          | Issue                         | Fix                                | Done |
  |---------------------|------------------|-------------------------------|-------------------------------------|------|
  | dozzle              | Dozzle           | --version not a health probe  | CMD /dozzle healthcheck             | YES  |
  | portainer           | portainer_agent  | No healthcheck                | TCP nc -z 127.0.0.1 9001            | YES  |
  | searxng             | SearXNG          | No healthcheck                | CMD wget /healthz                   | YES  |
  | code-server         | CodeServerDB     | mysqladmin ping no password   | socket auth 2>/dev/null             | YES  |
  | agents_gateway_data | mcp-gateway      | Re-verify comment missing     | Comment added                       | YES  |
  | warp-main           | warp-agent       | Port verification comment     | Comment added                       | YES  |

HEALTHCHECK-FIXES: COMPLETE
