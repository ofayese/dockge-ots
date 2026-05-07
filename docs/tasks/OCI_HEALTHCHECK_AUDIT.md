# Task: OCI Runtime Healthcheck Audit and Fix

/coder
/continuous-learning
/coding-agent-orchestrator
/compound-learning-project-memory
/code-analyzer

======================================================================
BACKGROUND
======================================================================

Stacks are failing to start cleanly on the OTS NAS with:

  OCI runtime exec failed: exec failed: unable to start container
  process: exec: "wget": executable file not found in $PATH

Root cause: healthcheck `test:` arrays use `CMD wget ...` but several
images do not ship wget. The fix depends on what each image actually
provides (curl, wget, nc, a built-in binary, or nothing).

Partial bring-up state on the NAS (stacks known up or expected to come up):
  - dockge        (host container, not compose)
  - portainer     (alpine — wget via busybox OK)
  - dozzle        (uses /dozzle --version — OK)
  - homepage      (SUSPECT — wget in gethomepage image unknown)
  - traefik-ots   (uses wget — traefik:v3 does NOT ship wget)
  - watchtower    (scratch-based — comment already says no wget; uses
                    /watchtower --health-check — OK)
  - it-tools      (nginx:alpine — busybox wget present — likely OK)
  - otsai-webui   (CMD-SHELL with wget||curl fallback — depends on shell)
  - otsai-server  (CMD-SHELL with ollama list — OK if ollama ships shell)
  - searxng       (no healthcheck — OK; redis uses valkey-cli — OK)
  - databases     (adminer uses wget — SUSPECT; mariadb/postgres use
                    native binaries — OK)

======================================================================
PHASE 0 — READ ALL COMPOSE FILES FIRST
======================================================================

Read these files before any analysis. Do not skip any.

  stacks/portainer/compose.yaml
  stacks/dozzle/compose.yaml
  stacks/homepage/compose.yaml
  stacks/traefik-ots/compose.yaml
  stacks/traefik-mft/compose.yaml
  stacks/watchtower/compose.yaml
  stacks/it-tools/compose.yaml
  stacks/ollama/compose.yaml          (contains otsai-server + otsai-webui)
  stacks/searxng/compose.yaml         (contains SearXNG + SearXNG-Redis)
  stacks/databases/compose.yaml       (contains MariaDB + PostgreSQL + Adminer)
  stacks/holyclaude/compose.yaml
  stacks/code-server/compose.yaml
  stacks/grafana-prom/compose.yaml
  stacks/zabbix/compose.yaml
  stacks/openresume/compose.yaml
  stacks/warp-main/compose.yaml
  stacks/codex-docs/compose.yaml
  stacks/github-desktop/compose.yaml
  stacks/rag-stack/compose.yaml       (if exists)
  stacks/agents_gateway_data/compose.yaml

======================================================================
PHASE 1 — IMAGE CAPABILITY AUDIT
======================================================================

For each service with a healthcheck, classify the image into one of:

  TYPE A — Binary probe   : image ships a CLI tool (wget, curl, nc, etc.)
  TYPE B — Own binary     : healthcheck calls the app binary itself
  TYPE C — No shell       : scratch/distroless image, no shell or utils
  TYPE D — Shell + utils  : full shell + wget and/or curl confirmed

Classification rules (apply in order, no guessing):

  1. Images tagged *:alpine or based on alpine ship busybox wget — TYPE A
  2. Images tagged scratch, distroless, or known minimal:
       - containrrr/watchtower        = TYPE C (scratch)
       - traefik:v*                   = TYPE C (scratch-based, no wget)
       - adminer:*-standalone         = UNKNOWN — verify below
  3. ghcr.io/gethomepage/homepage    = Node.js image — verify below
  4. corentinth/it-tools             = nginx:alpine = TYPE A (busybox wget)
  5. ghcr.io/open-webui/open-webui   = Python image — curl and wget vary
  6. ollama/ollama                   = has shell + ollama CLI = TYPE B
  7. portainer/*:*-alpine            = TYPE A (alpine busybox wget)
  8. amir20/dozzle                   = Go scratch-like — uses own binary
  9. valkey/valkey:*-alpine          = TYPE A (valkey-cli present)

For UNKNOWN images, check Docker Hub image layers by running:

  docker run --rm --entrypoint="" <image> which wget 2>/dev/null && echo HAS_WGET || echo NO_WGET
  docker run --rm --entrypoint="" <image> which curl 2>/dev/null && echo HAS_CURL || echo NO_CURL

Record findings as:
  SERVICE | IMAGE | HAS_WGET | HAS_CURL | HAS_NC | RECOMMENDED_PROBE

======================================================================
PHASE 2 — KNOWN ISSUES FROM PRE-READ (fix these)
======================================================================

The following are confirmed issues based on compose file content:

### ISSUE 1 — traefik-ots and traefik-mft: wget not in image

  Current:
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/ping"]

  traefik:v3 is scratch-based and does not ship wget or curl.
  Traefik ships a built-in /usr/local/bin/traefik binary.

  Fix:
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 15s

  Note: --ping flag requires --ping=true in the traefik command block,
  which is already present in both traefik-ots and traefik-mft compose.yaml.

  Apply to: stacks/traefik-ots/compose.yaml
            stacks/traefik-mft/compose.yaml

### ISSUE 2 — homepage: wget availability unconfirmed

  Current:
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/"]

  ghcr.io/gethomepage/homepage is a Node.js/Next.js image.
  Node images typically do NOT ship wget. curl may be present.

  Preferred fix (curl):
    healthcheck:
      test: ["CMD", "curl", "-fs", "http://localhost:3000/"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s

  Fallback fix (if neither wget nor curl — TCP probe):
    healthcheck:
      test: ["CMD-SHELL", "node -e \"require('http').get('http://localhost:3000/', r => process.exit(r.statusCode < 400 ? 0 : 1)).on('error', () => process.exit(1))\""]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s

  Verify first:
    docker run --rm --entrypoint="" ghcr.io/gethomepage/homepage:v1.12 \
      which curl 2>/dev/null && echo HAS_CURL || echo NO_CURL

  Apply to: stacks/homepage/compose.yaml

### ISSUE 3 — adminer: wget availability unconfirmed

  Current:
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/"]

  adminer:5.4.2-standalone is PHP-based. Verify curl/wget.

  Preferred fix if curl available:
    healthcheck:
      test: ["CMD", "curl", "-fs", "http://localhost:8080/"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s

  Fallback fix (PHP built-in):
    healthcheck:
      test: ["CMD-SHELL", "php -r \"exit(file_get_contents('http://localhost:8080/') !== false ? 0 : 1);\""]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s

  Verify first:
    docker run --rm --entrypoint="" adminer:5.4.2-standalone \
      which curl 2>/dev/null && echo HAS_CURL || echo NO_CURL
    docker run --rm --entrypoint="" adminer:5.4.2-standalone \
      which wget 2>/dev/null && echo HAS_WGET || echo NO_WGET

  Apply to: stacks/databases/compose.yaml (adminer service only)

### ISSUE 4 — otsai-webui: CMD-SHELL with wget||curl fallback

  Current:
    test:
      - CMD-SHELL
      - wget -qO- http://localhost:8080/health >/dev/null 2>&1 ||
        curl -fsS http://localhost:8080/health >/dev/null 2>&1 || exit 1

  CMD-SHELL requires /bin/sh. ghcr.io/open-webui/open-webui is Python
  based (has sh) but wget may not be present. The || fallback to curl
  is correct in principle but only works if the shell is present.

  Cleaner fix — remove the redundancy, use curl directly if available:
    healthcheck:
      test:
        - CMD-SHELL
        - curl -fs http://localhost:8080/health || exit 1
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  If curl not confirmed in image, use Python directly:
    healthcheck:
      test:
        - CMD-SHELL
        - python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  Verify first:
    docker run --rm --entrypoint="" ghcr.io/open-webui/open-webui:v0.9.2 \
      which curl 2>/dev/null && echo HAS_CURL || echo NO_CURL

  Apply to: stacks/ollama/compose.yaml (open-webui service)

### ISSUE 5 — holyclaude: nc (netcat) availability

  Current:
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "3000"]

  coderluii/holyclaude is a custom image. nc may or may not be present.
  It is a dev container (SYS_ADMIN, browser tooling) so curl is likely.

  Safer fix:
    healthcheck:
      test:
        - CMD-SHELL
        - curl -fs http://127.0.0.1:3000/ >/dev/null 2>&1 || nc -z 127.0.0.1 3000 || exit 1
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 90s

  Verify first:
    docker run --rm --entrypoint="" coderluii/holyclaude:latest \
      which nc 2>/dev/null && echo HAS_NC || echo NO_NC
    docker run --rm --entrypoint="" coderluii/holyclaude:latest \
      which curl 2>/dev/null && echo HAS_CURL || echo NO_CURL

  Apply to: stacks/holyclaude/compose.yaml

### ISSUE 6 — it-tools deprecation warning advisory (not blocking)

  The deprecation warning in traefik logs mentions encoded characters
  config. Not related to healthchecks but flag for future coder pass:
    --entrypoints.web.http.redirections.entrypoint.scheme → check v3.7 docs

======================================================================
PHASE 3 — FULL REPO SCAN
======================================================================

After fixing known issues, scan ALL compose files for any remaining
healthcheck patterns that may fail on minimal images:

Command:
  grep -rn "CMD.*wget\|CMD.*curl\|CMD.*nc \|CMD-SHELL" \
    stacks/*/compose.yaml stacks/*/docker-compose.yml 2>/dev/null

For each result:
  1. Identify the image
  2. Classify as TYPE A/B/C/D
  3. Confirm the tool exists in the image or flag for fix

Also scan for CMD-SHELL usage — requires /bin/sh in image:
  grep -rn "CMD-SHELL" stacks/*/compose.yaml 2>/dev/null

Flag any CMD-SHELL in TYPE C (scratch/distroless) images.

======================================================================
PHASE 4 — APPLY FIXES
======================================================================

Apply all confirmed fixes from Phase 2. For each change:

  1. Edit the compose.yaml using str_replace (surgical, minimal context)
  2. Run: docker compose -f stacks/<stack>/compose.yaml config > /dev/null
     Expected: no errors (env var warnings for STACK_ROOT are acceptable)
  3. Add inline comment above the healthcheck block explaining the probe type:
       # Healthcheck type B: uses own binary — image does not ship wget/curl

COMMENT STANDARD (use consistently across all fixes):
  # Healthcheck type A: wget/curl via busybox (alpine-based image)
  # Healthcheck type B: own binary probe (image ships CLI tool for this)
  # Healthcheck type C: TCP probe via nc (no HTTP client in image)
  # Healthcheck type D: CMD-SHELL + Python fallback (no wget/curl)
  # Healthcheck type E: built-in binary healthcheck (traefik, watchtower)

======================================================================
PHASE 5 — VALIDATION
======================================================================

Run the full compose validation suite:
  Command: scripts/compose-validate.sh
  Expected: "All compose files validated OK."

Run pre-commit on all changed files:
  Command: pre-commit run --files <list of changed compose.yaml files>
  Expected: all hooks pass.

Run manifest diff to confirm no regressions:
  diff \
    <(grep -E '^\s*"[^"]+:' scripts/init-nas.sh \
      | sed -E 's/^[[:space:]]*"([^"]+):.*/\1/' | sort -u) \
    <(ls stacks/ \
      | grep -vE \
          "^portainer$|^agents_gateway_data$|^it-tools$|\
^mcp-tools-config$|^openresume$|^warp-main$|^watchtower$|\
^docker-model-runner$|^_haproxy$" \
        | sort -u)
  Expected: empty

Commit all changes:
  git add stacks/traefik-ots/compose.yaml \
          stacks/traefik-mft/compose.yaml \
          stacks/homepage/compose.yaml \
          stacks/databases/compose.yaml \
          stacks/ollama/compose.yaml \
          stacks/holyclaude/compose.yaml
  git commit -m \
    "fix: replace wget healthchecks with image-native probes (OCI exec fix)"

======================================================================
PHASE 6 — COMPOUND MEMORY UPDATE
======================================================================

/compound-learning-project-memory

Add a dated bullet to AGENTS.md under "## What Works":

  [$(date +%Y-%m-%d)] OCI healthcheck audit — exec: "wget" not found fixes:
  - traefik:v3 is scratch-based — no wget or curl.
    Use: test: ["CMD", "traefik", "healthcheck", "--ping"]
    Requires --ping=true in traefik command block (already set).
  - adminer:standalone and ghcr.io/gethomepage/homepage — wget not confirmed.
    Prefer curl; fallback to image-native (PHP/Node) if curl absent.
  - ghcr.io/open-webui/open-webui — CMD-SHELL wget||curl pattern works
    but wget is not guaranteed; simplify to curl or python3 fallback.
  - holyclaude — nc probe; verify nc in image before relying on it.
  - RULE: never assume wget in non-alpine images. Always verify with:
      docker run --rm --entrypoint="" <image> which wget
  - Healthcheck type comments (A/B/C/D/E) added above each healthcheck
    block to document why the probe was chosen.

======================================================================
PHASE 7 — CONTINUOUS LEARNING EXTRACTION
======================================================================

/continuous-learning

Extract to ~/.cursor/skills/learned/oci-healthcheck-patterns.md:

  Title: OCI Healthcheck Tool Availability by Image Type
  
  Rule 1 — Alpine images:
    busybox ships wget and sh. CMD wget is safe.
    Examples: postgres:*-alpine, valkey:*-alpine, nginx:alpine,
              portainer:*-alpine, corentinth/it-tools (nginx:alpine base)

  Rule 2 — Scratch / scratch-based images:
    NO shell, NO wget, NO curl. Only CMD with the app binary.
    Examples: traefik:v*, containrrr/watchtower
    Fix: use the app's own binary:
      traefik: ["CMD", "traefik", "healthcheck", "--ping"]
      watchtower: ["CMD", "/watchtower", "--health-check"]

  Rule 3 — Node.js images (node:*, Next.js apps):
    Shell present. curl may be present (Debian base) or absent (slim).
    wget usually absent. Use curl or node -e http.get() fallback.
    Examples: ghcr.io/gethomepage/homepage

  Rule 4 — Python images:
    Shell present. curl varies. python3 always present.
    Use: python3 -c "import urllib.request; urllib.request.urlopen('...')"
    Examples: ghcr.io/open-webui/open-webui

  Rule 5 — PHP images:
    Shell present. curl usually present (most PHP images include libcurl).
    php -r "file_get_contents(...)" is ultimate fallback.
    Examples: adminer, phpmyadmin

  Rule 6 — Go images with minimal base:
    Varies. Check for static binary healthcheck flag in image docs.
    Examples: amir20/dozzle (uses own --version flag)

  Rule 7 — Custom dev containers:
    Assume curl and nc are present. Verify with docker run --entrypoint="".
    Examples: coderluii/holyclaude

  VERIFICATION COMMAND (always run for unknown images):
    docker run --rm --entrypoint="" <image> \
      sh -c "which wget; which curl; which nc" 2>/dev/null

  NEVER use CMD-SHELL in scratch/distroless images — no shell present.
  NEVER blindly copy wget healthchecks across images without checking.

======================================================================
FINAL PRINT
======================================================================

Print a summary table:

  | Stack          | Service      | Old probe     | New probe         | Changed |
  |----------------|--------------|---------------|-------------------|---------|
  | traefik-ots    | traefik      | CMD wget      | CMD traefik hc    | YES     |
  | traefik-mft    | traefik      | CMD wget      | CMD traefik hc    | YES     |
  | homepage       | homepage     | CMD wget      | CMD curl / node   | YES/NO  |
  | databases      | adminer      | CMD wget      | CMD curl / php    | YES/NO  |
  | ollama         | open-webui   | CMD-SHELL     | CMD-SHELL curl    | YES/NO  |
  | holyclaude     | holyclaude   | CMD nc        | CMD-SHELL curl/nc | YES/NO  |

Then print:
  OCI-HEALTHCHECK-AUDIT: COMPLETE
