> Superseded by `docs/tasks/MASTER_AUDIT_AND_DEPLOY.md` on 2026-05-08. Kept for history.

# Task: Next Phase — Port Conflicts, Homepage Fixes, OCI Remaining, rag-stack

# SLASH COMMANDS IN USE:
# /coder                — Cursor AI coding agent: reads files, applies changes,
#                         runs compose-validate + pre-commit gates.
#                         NOTE: scripts/pipeline.py does not exist in this repo;
#                         run the gate commands manually as specified in Phase 6.
# /compound-learning    — Updates AGENTS.md with dated project-specific learnings.
#                         (Correct name; NOT /compound-learning-project-memory)
# /continuous-learning  — Extracts reusable patterns to ~/.cursor/skills/learned/
#                         at session end. Configured as a Stop Hook.
#
# NOTE: /code-analyzer is NOT a defined skill in this repo and has been removed.
# Phase 4 OCI probes (docker run --entrypoint="" ...) must be run on the NAS
# or Mac with Docker Desktop before applying healthcheck fixes. The coder
# applies fixes based on the probe results documented in the task.

/coder
/compound-learning
/continuous-learning

======================================================================
CONTEXT
======================================================================

This is the next phase after the 2026-05-07 session. The following
issues were identified by reading compose files directly. Address all
of them in order. Do not skip any phase.

======================================================================
PHASE 0 — READ THESE FILES FIRST
======================================================================

  stacks/rag-stack/compose.yaml
  stacks/holyclaude/compose.yaml
  stacks/warp-main/compose.yaml
  stacks/openresume/compose.yaml
  stacks/agents_gateway_data/compose.yaml
  stacks/codex-docs/compose.yaml
  stacks/homepage/config/services.yaml
  AGENTS.md (deploy table section only)
  scripts/init-nas.sh (STACK_MANIFEST section)

======================================================================
PHASE 1 — CRITICAL: PORT CONFLICT (blocking)
======================================================================

ISSUE: rag-stack anythingllm and holyclaude both map host port 3001.

  stacks/rag-stack/compose.yaml:
    anythingllm: ports: - 10.0.1.15:3001:3001

  stacks/holyclaude/compose.yaml:
    ports: - "3001:3001"

Both stacks cannot run simultaneously. One must change.

DECISION (apply this):
  holyclaude is the primary interactive workstation — keep 3001:3001.
  anythingllm is a backend API — change to a non-conflicting port.
  AnythingLLM default is 3001 internally; remap host to 3002.

FIX in stacks/rag-stack/compose.yaml — anythingllm service:

  Change:
    ports:
      - 10.0.1.15:3001:3001

  To:
    ports:
      - 10.0.1.15:3002:3001

Also update the comment in compose.yaml header:
  Change: "HolyClaude can call the AnythingLLM REST API at http://10.0.1.15:3001/api/v1/"
  To:     "HolyClaude can call the AnythingLLM REST API at http://10.0.1.15:3002/api/v1/"

======================================================================
PHASE 2 — CRITICAL: rag-stack Synology depends_on violation
======================================================================

ISSUE: rag-stack uses condition: service_healthy in depends_on which
breaks Synology Package Center docker compose compatibility.

AGENTS.md guardrail (verbatim):
  "tracked stacks use plain depends_on lists (no condition:) for
  Synology Package Center docker compose compatibility"

Current violations in stacks/rag-stack/compose.yaml:

  anythingllm:
    depends_on:
      qdrant:
        condition: service_healthy   VIOLATION

  pipelines:
    depends_on:
      qdrant:
        condition: service_healthy   VIOLATION

FIX: Replace both with plain depends_on lists and add inline comment:

  anythingllm:
    # Plain depends_on (no condition:) for Synology Package Center
    # docker compose compatibility. Healthcheck + restart: unless-stopped
    # provides resilience instead of Compose v2 condition forms.
    depends_on:
      - qdrant

  pipelines:
    # Plain depends_on — same rationale as anythingllm above.
    depends_on:
      - qdrant

======================================================================
PHASE 3 — HOMEPAGE services.yaml: fix two config bugs in repo copy
======================================================================

The NAS-local services.yaml was edited during the session but the repo
copy (stacks/homepage/config/services.yaml) was not updated. Fix these
in the repo copy so the next git pull lands the correct config on NAS.

FIX 1 — Portainer Agent: remove siteMonitor (agent uses mTLS not HTTP)

  Change:
    - Portainer Agent:
        ...
        container: portainer_agent
        siteMonitor: http://10.0.1.15:9001/

  To:
    - Portainer Agent:
        ...
        container: portainer_agent
        # siteMonitor omitted: agent uses mTLS — HTTP probe returns
        # HTTP/1.0 400 → HPE_CLOSED_CONNECTION in Homepage logs.

FIX 2 — Synology DSM: correct siteMonitor port (5000 → 5001, http → https)

  Change:
    - Synology DSM:
        ...
        siteMonitor: http://10.0.1.15:5000/

  To:
    - Synology DSM:
        ...
        siteMonitor: https://10.0.1.15:5001/

FIX 3 — Portainer widget: use env var not hardcoded placeholder

  Change:
    key: REPLACE_WITH_PORTAINER_API_KEY

  To:
    # Set PORTAINER_API_KEY in stacks/homepage/.env (gitignored)
    # Generate: Portainer → Account Settings → Access Tokens → Add
    key: ${PORTAINER_API_KEY}

======================================================================
PHASE 4 — OCI HEALTHCHECK: remaining stacks
======================================================================

NOTE: Image capability probes must be run before applying fixes.
Run the probe script on the NAS or Mac with Docker Desktop:
  bash scripts/audit-healthcheck-tools.sh 2>&1 | tee /tmp/oci-phase2.txt

Then apply fixes based on actual probe results. Use the same fix
patterns as the Phase 1 audit (commit 023ce18):
  HAS_WGET → keep, add type comment
  NO_WGET + HAS_CURL → change to CMD curl -fs
  NO_WGET + NO_CURL + HAS_SH → CMD-SHELL with python3 or node fallback
  NO_WGET + NO_CURL + NO_SH → use app binary or TCP probe

### 4a — openresume (stacks/openresume/compose.yaml)
  Image: xitanggg/open-resume:latest (Next.js)
  Current probe: CMD wget -qO- http://localhost:3000/
  Apply fix per probe result. Add type comment above healthcheck block.

### 4b — warp-main (stacks/warp-main/compose.yaml)
  Images: warpdotdev/warp:0.0.32, warpdotdev/warp-agent:latest,
          warpdotdev/warp-claude-cli-sidecar:latest
  Current probe on all three: CMD wget ...
  Probe each image separately — results may differ.
  Apply fix per probe result per service.

### 4c — agents_gateway_data (stacks/agents_gateway_data/compose.yaml)
  Image: docker/mcp-gateway:v0.42.0 (Go binary)
  Current probe: CMD wget -qO- http://127.0.0.1:8811/health
  Apply fix per probe result.

### 4d — rag-stack (stacks/rag-stack/compose.yaml)
  Images: qdrant/qdrant:v1.14.0 (Rust), mintplexlabs/anythingllm:1.7.6,
          ghcr.io/open-webui/pipelines:main (Python)
  Current probe on all three: CMD wget ...
  Probe each image. Qdrant fallback if no wget/curl:
    test: ["CMD-SHELL", "curl -fs http://127.0.0.1:6333/readyz || exit 1"]
  Apply fix per probe result per service.

If probe results are not available, make a best-effort fix based on
image base type (Rust → no wget; Python → has sh + likely curl;
Node.js → has sh + wget varies) and add a TODO comment:
  # TODO: verify probe tool availability via scripts/audit-healthcheck-tools.sh

======================================================================
PHASE 5 — rag-stack: add missing README.md
======================================================================

stacks/rag-stack/ is missing README.md (deploy table shows "—").
Create stacks/rag-stack/README.md following the standard stack README
format. Use stacks/searxng/README.md as the template.

Content must include:

  ## Purpose
    RAG pipeline: Qdrant vector DB + AnythingLLM + Open WebUI Pipelines.
    Connects to the ollama stack (otsai-server on 11434) and extends
    open-webui (otsai-webui) with LangChain/LangGraph pipeline support.

  ## Services
    | Service          | Container         | Internal | Host             | Image |
    |------------------|-------------------|----------|------------------|-------|
    | qdrant           | rag-qdrant        | 6333/6334| 10.0.1.15:6333/6334 | qdrant/qdrant:v1.14.0 |
    | anythingllm      | rag-anythingllm   | 3001     | 10.0.1.15:3002   | mintplexlabs/anythingllm:1.7.6 |
    | pipelines        | rag-pipelines     | 9099     | 10.0.1.15:9099   | ghcr.io/open-webui/pipelines:main |

  ## Prerequisites
    - ollama stack (otsai-server) running on 11434
    - open-webui (otsai-webui) running on 8893
    - Pull embedding model: docker exec otsai-server ollama pull nomic-embed-text

  ## Required .env values
    ANYTHINGLLM_JWT_SECRET  (generate: openssl rand -hex 32)
    PIPELINES_API_KEY       (set in Open WebUI → Settings → Connections)
    QDRANT_API_KEY          (optional — leave blank to disable)

  ## Port reference
    10.0.1.15:6333  Qdrant REST API + web UI
    10.0.1.15:6334  Qdrant gRPC
    10.0.1.15:3002  AnythingLLM web UI + REST API
                    NOTE: port 3001 conflicts with holyclaude — always use 3002
    10.0.1.15:9099  Open WebUI Pipelines API

  ## Health meaning
    rag-qdrant:      GET /readyz returns 200 — vector DB ready
    rag-anythingllm: GET /api/ping returns 200 — API server ready
    rag-pipelines:   GET / returns 200 — pipeline server ready

  ## First deploy
    sudo mkdir -p /volume1/docker/dockge/stacks/rag-stack/{data/qdrant,data/anythingllm,config/pipelines}
    cp .env.example .env && nano .env
    docker compose up -d

  ## Rollback
    docker compose down
    (data persists in ${STACK_ROOT}/rag-stack/data/ — safe to redeploy)

======================================================================
PHASE 6 — VALIDATE
======================================================================

NOTE: scripts/pipeline.py does not exist. Run gates manually.

STEP 1 — Compose validation:
  Command: scripts/compose-validate.sh
  Expected: All compose files validated OK.

STEP 2 — Per-file config check:
  docker compose -f stacks/rag-stack/compose.yaml config > /dev/null
  docker compose -f stacks/warp-main/compose.yaml config > /dev/null
  docker compose -f stacks/openresume/compose.yaml config > /dev/null
  docker compose -f stacks/agents_gateway_data/compose.yaml config > /dev/null
  Expected: no errors (env var warnings OK)

STEP 3 — Port conflict check:
  grep -rn "3001:" stacks/*/compose.yaml
  Expected: only holyclaude shows 3001:3001
            rag-stack shows 10.0.1.15:3002:3001

STEP 4 — depends_on condition check:
  grep -rn "condition:" stacks/*/compose.yaml
  Expected: zero results

STEP 5 — Pre-commit on changed files:
  pre-commit run --files \
    stacks/rag-stack/compose.yaml \
    stacks/rag-stack/README.md \
    stacks/warp-main/compose.yaml \
    stacks/openresume/compose.yaml \
    stacks/agents_gateway_data/compose.yaml \
    stacks/homepage/config/services.yaml
  Expected: all hooks pass.

STEP 6 — Commit:
  git add \
    stacks/rag-stack/compose.yaml \
    stacks/rag-stack/README.md \
    stacks/warp-main/compose.yaml \
    stacks/openresume/compose.yaml \
    stacks/agents_gateway_data/compose.yaml \
    stacks/homepage/config/services.yaml
  git commit -m \
    "fix: rag-stack port 3001→3002, drop condition: depends_on, OCI healthcheck remaining, homepage services.yaml"
  git push

======================================================================
PHASE 7 — COMPOUND MEMORY UPDATE
======================================================================

/compound-learning

Add a dated bullet to AGENTS.md under "## What Works":

  [$(date +%Y-%m-%d)] Next-phase fixes (port conflict, depends_on, OCI remaining):
  - rag-stack anythingllm port conflict with holyclaude: both used 3001.
    Fixed to 10.0.1.15:3002:3001. NEVER assign anythingllm host port 3001.
  - rag-stack depends_on condition: violated Synology guardrail. Converted
    to plain lists. Rule: no condition: in depends_on in any tracked stack.
  - Homepage services.yaml: Portainer Agent siteMonitor removed (mTLS probe
    causes HPE_CLOSED_CONNECTION); DSM corrected to https://...:5001/;
    Portainer key uses ${PORTAINER_API_KEY} env var.
  - rag-stack README.md: created. Deploy table README column now green.
  - OCI phase 2: warp-main, openresume, agents_gateway_data, rag-stack
    healthchecks audited and fixed per image capability probes.

Update deploy-readiness table in AGENTS.md:
  holyclaude row: healthcheck column "—" → "✓" (probes port 3001)
  rag-stack row: README column "—" → "✓"

======================================================================
PHASE 8 — CONTINUOUS LEARNING
======================================================================

/continuous-learning

Extract to ~/.cursor/skills/learned/:

Pattern: rag-stack-port-conflicts.md
  Title: RAG Stack Port Conflict with HolyClaude
  AnythingLLM default internal port is 3001. holyclaude also uses 3001.
  In this repo: anythingllm is always mapped to host port 3002.
  Never assign host port 3001 to anythingllm when holyclaude is in the stack.

Pattern: synology-depends-on-no-condition.md
  Title: Synology docker compose depends_on must not use condition:
  Synology Package Center ships an older docker compose version.
  condition: service_healthy causes compose up to fail with parse error.
  Always use plain depends_on lists. Use healthcheck + restart policies
  for resilience instead of condition-based orchestration.

======================================================================
FINAL PRINT
======================================================================

  | Stack               | Fix                                   | Status |
  |---------------------|---------------------------------------|--------|
  | rag-stack           | Port 3001→3002 (holyclaude conflict)  | DONE   |
  | rag-stack           | depends_on condition: removed          | DONE   |
  | rag-stack           | README.md created                     | DONE   |
  | rag-stack           | OCI healthcheck probes + fixes        | DONE   |
  | homepage            | Portainer Agent siteMonitor removed   | DONE   |
  | homepage            | DSM siteMonitor https://...:5001/     | DONE   |
  | homepage            | Portainer key → env var               | DONE   |
  | openresume          | OCI healthcheck verified + fixed      | DONE   |
  | warp-main           | OCI healthcheck verified + fixed      | DONE   |
  | agents_gateway_data | OCI healthcheck verified + fixed      | DONE   |

NEXT-PHASE: COMPLETE
