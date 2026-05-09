# Task: Docker Multi-Machine + Ollama Auto-Pull + Offline Workspace
# Version: 2026-05-08
#
# Machines:
#   NAS (otsorundscore)  — DS723+, DSM 7.3.2, Container Manager (Synology Docker package)
#   otsmbpro16           — Mac (Apple Silicon), Docker Desktop
#   hpdevcore            — Windows 11 + WSL2, Docker Engine in WSL2
#
# Goal: Automated model pull on ollama stack start, full offline
#       workspace via HolyClaude + RAG-Stack, multi-machine Docker
#       deployment documentation.

/coder
/compound-learning

======================================================================
CONTEXT
======================================================================

Three Docker environments must be accounted for:

  NAS (Container Manager / DSM):
    - Synology DSM 7.3.2 — Package Center installs Docker as "Container Manager"
    - `depends_on` without `condition:` required (old compose CLI in Package Center)
    - Dockge manages stacks via `docker compose` called from the NAS shell
    - Git ops: NAS is DEPLOY ONLY — all commits from Mac (otsmbpro16)
    - Model storage: STACK_ROOT/ollama/data/ollama (persists across restarts)

  otsmbpro16 (Mac / Apple Silicon):
    - Docker Desktop (standard Mac install)
    - Workspace path: /Users/laolufayese
    - Can connect to NAS ollama at 10.0.1.15:11434 over LAN
    - Mac-native ollama is an alternative but NAS is the shared inference server

  hpdevcore (Windows 11 / WSL2):
    - Docker Engine running inside WSL2 (not Docker Desktop for Windows)
    - Workspace path inside WSL2: /home/laolufayese
    - Windows home also accessible at: /mnt/c/Users/laolufayese
    - Connects to NAS ollama at 10.0.1.15:11434 over LAN
    - GPU acceleration possible via NVIDIA GPU + WSL2 CUDA (if GPU present)

======================================================================
PHASE 0 — PRE-FLIGHT READS
======================================================================

  stacks/ollama/compose.yaml
  stacks/ollama/.env.example
  stacks/holyclaude/compose.yaml
  stacks/holyclaude/.env.example
  stacks/rag-stack/compose.yaml
  stacks/rag-stack/.env.example

======================================================================
PHASE 1 — VERIFY OLLAMA AUTO-PULL (compose.yaml already updated)
======================================================================

WHAT WAS DONE:
  The ollama compose.yaml was updated to include:
    - ollama-model-init service (restart: "no", one-shot puller)
    - ollama-net bridge network (172.27.0.0/24)
    - OLLAMA_FLASH_ATTENTION=1 env var
    - mem_limit raised from 8g to 16g
    - OLLAMA_KEEP_ALIVE env var

STEP 1A — Verify compose is valid:
  Command: docker compose -f stacks/ollama/compose.yaml config > /dev/null && echo PASS
  Expected: PASS (env warnings for SECRET vars are acceptable)

STEP 1B — Verify model-init service has restart: "no":
  Command: grep -A2 "ollama-model-init:" stacks/ollama/compose.yaml | grep restart
  Expected: restart: "no" # intentional

STEP 1C — Verify ollama-net subnet:
  Command: grep "172.27.0" stacks/ollama/compose.yaml
  Expected: subnet: 172.27.0.0/24

STEP 1D — Verify no condition: in depends_on (NAS compatibility):
  Command: grep "condition:" stacks/ollama/compose.yaml
  Expected: zero matches

======================================================================
PHASE 2 — HOW THE AUTO-PULL WORKS (documentation)
======================================================================

Add to stacks/ollama/README.md under new section "## Automated model pull":

  ## Automated model pull (ollama-model-init)

  When you run `docker compose up -d` (or click Deploy in Dockge), the
  `ollama-model-init` service starts alongside Ollama. It:

    1. Polls /usr/bin/ollama list every 5 seconds until Ollama is ready.
       Gives up after 5 minutes (60 × 5s) and exits with error.
    2. Pulls models in tier order — Tier 1 first (small/fast/required),
       then Tier 2 (primary working models), then Tier 3 (secondary).
    3. Skips models already on disk — idempotent; safe to re-run.
    4. Exits cleanly (restart: "no" — does not keep restarting).

  Model storage persists in `STACK_ROOT/ollama/data/ollama` across
  restarts. Models survive container recreation.

  ### Controlling which models are pulled

  Set in stacks/ollama/.env (or the Dockge stack env editor):

    # Tier 1: baseline — always pull (nomic-embed-text is REQUIRED for RAG)
    OLLAMA_TIER1_MODELS=phi4:mini nomic-embed-text llama3.2:3b

    # Tier 2: primary working models (~15-25 min on first pull)
    OLLAMA_TIER2_MODELS=qwen2.5-coder:7b llama3.1:8b

    # Tier 3: secondary — set to "" to skip
    OLLAMA_TIER3_MODELS=deepseek-r1:7b mistral:7b qwen2.5:7b

  ### Re-running the model init (to pull new models)

  The service exits after first run. To re-trigger it:

    # On the NAS — force-recreate only the init container
    sudo docker compose -f stacks/ollama/compose.yaml \
      up -d --force-recreate ollama-model-init

  ### Checking pull progress

  The init container logs every pull in real time:

    # On the NAS
    sudo docker logs ollama-model-init --follow
    # or in Dozzle at http://10.0.1.15:8892

  ### Total disk space (all recommended models)

    phi4:mini          ~2.5 GB
    nomic-embed-text   ~274 MB
    llama3.2:3b        ~2.0 GB
    qwen2.5-coder:7b   ~4.4 GB
    llama3.1:8b        ~4.7 GB
    deepseek-r1:7b     ~4.7 GB
    mistral:7b         ~4.1 GB
    qwen2.5:7b         ~4.4 GB
    ─────────────────────────
    Total:             ~27.1 GB

  The ollama data volume should be on a volume with at least 30 GB free.
  Check: df -h /volume1/docker/dockge/stacks/ollama/data/ollama

======================================================================
PHASE 3 — MULTI-MACHINE DOCKER DEPLOYMENT
======================================================================

Add to docs/hive/NAS_DEPLOYMENT.md under "## Multi-machine Docker":

  ## Multi-machine Docker deployment

  Three Docker environments use this repo's stacks:

  ### NAS — otsorundscore (Container Manager)
  Environment: Synology DSM 7.3.2, AMD Ryzen R1600, 32 GB, CPU-only
  Docker:  Container Manager (Synology Package Center)
  Deploy:  Via Dockge at http://10.0.1.15:5571 or docker compose CLI via SSH
  Role:    Primary inference server, shared RAG backend, offline workspace host
  Compose: Synology Package Center ships an older compose CLI.
           Constraint: depends_on WITHOUT condition: in all stacks.
           Constraint: no user namespacing (PUID/PGID default to 0 = root).
  Git:     DEPLOY ONLY — commit from otsmbpro16, then git pull on NAS.

  ### otsmbpro16 — Mac (Apple Silicon)
  Environment: macOS, Apple Silicon (M-series), Docker Desktop
  Docker:  Docker Desktop for Mac (standard install)
  Role:    Development, git commits, repo authoring, Cursor IDE
  Connection to NAS ollama: http://10.0.1.15:11434 (LAN)
  HolyClaude workspace: /Users/laolufayese
  Ollama .env override for local deploy:
    HOLYCLAUDE_WORKSPACE=/Users/laolufayese
    OLLAMA_HOST=http://10.0.1.15:11434
  Note: Mac-native ollama (brew install ollama) is an alternative
  inference server. Connect HolyClaude to whichever is running.

  ### hpdevcore — Windows 11 + WSL2
  Environment: Windows 11, WSL2 (Linux kernel), Docker Engine in WSL2
  Docker:  Docker Engine inside WSL2 distribution (not Docker Desktop for Windows)
  Role:    Development workstation, code execution, Windows-side testing
  Connection to NAS ollama: http://10.0.1.15:11434 (LAN)
  HolyClaude workspace options:
    Option A — WSL2 home: /home/laolufayese
    Option B — Windows home: /mnt/c/Users/laolufayese (slower I/O)
  Recommended: Option A (native Linux path in WSL2 = fast I/O)
  HolyClaude .env override:
    HOLYCLAUDE_WORKSPACE=/home/laolufayese
    OLLAMA_HOST=http://10.0.1.15:11434
  Note: If hpdevcore has an NVIDIA GPU, ollama can run with GPU
  acceleration locally. Install ollama in WSL2 natively for max speed.

  ### Connection matrix
  | Service | NAS port | otsmbpro16 | hpdevcore |
  |---|---|---|---|
  | Ollama API | 10.0.1.15:11434 | ✓ LAN | ✓ LAN |
  | Open WebUI | 10.0.1.15:8893 | ✓ LAN | ✓ LAN |
  | AnythingLLM | 10.0.1.15:3002 | ✓ LAN | ✓ LAN |
  | Qdrant | 10.0.1.15:6333 | ✓ LAN | ✓ LAN |
  | Pipelines | 10.0.1.15:9099 | ✓ LAN | ✓ LAN |
  | HolyClaude | per-machine | localhost:3001 | localhost:3001 |
  | Dockge | 10.0.1.15:5571 | ✓ LAN | ✓ LAN |

======================================================================
PHASE 4 — HOLYCLAUDE: multi-machine .env.example
======================================================================

CURRENT STATE: holyclaude .env.example already documents per-machine
workspace paths. Verify and extend with hpdevcore WSL2 specifics.

STEP 4A — Read current holyclaude .env.example:
  Verify HOLYCLAUDE_WORKSPACE line documents all three machines.

STEP 4B — If WSL2 guidance is missing, add to .env.example:

  # ── Workspace per machine (OPERATOR EXCEPTION — not under STACK_ROOT) ─────
  # Change HOLYCLAUDE_WORKSPACE to match the machine you are deploying on.
  #
  # NAS (Container Manager / DSM 7.3):
  #   HOLYCLAUDE_WORKSPACE=/volume1/homes/laolufayese
  #
  # otsmbpro16 (Mac / Apple Silicon):
  #   HOLYCLAUDE_WORKSPACE=/Users/laolufayese
  #
  # hpdevcore (Windows 11 / WSL2):
  #   Option A — WSL2 native home (recommended, fast I/O):
  #   HOLYCLAUDE_WORKSPACE=/home/laolufayese
  #   Option B — Windows home via WSL2 (slower I/O):
  #   HOLYCLAUDE_WORKSPACE=/mnt/c/Users/laolufayese
  #
  # NAS default (set for NAS deploy):
  HOLYCLAUDE_WORKSPACE=/volume1/homes/laolufayese

STEP 4C — Add per-machine ollama host guidance to .env.example:

  # ── Ollama inference server ────────────────────────────────────────────────
  # Primary: NAS shared inference server (all machines on LAN can use this)
  OLLAMA_HOST=http://10.0.1.15:11434
  #
  # Alternative: local ollama (when not on LAN or for lower latency)
  # Mac (brew install ollama): http://localhost:11434
  # WSL2 native ollama:        http://localhost:11434
  # Mac Docker:                http://host.docker.internal:11434

STEP 4D — Verify compose.yaml workspace mount uses correct variable:
  Command: grep "HOLYCLAUDE_WORKSPACE" stacks/holyclaude/compose.yaml
  Expected: - ${HOLYCLAUDE_WORKSPACE:-/volume1/homes/laolufayese}:/workspace

  The default in compose.yaml matches the NAS path. On other machines,
  operators override HOLYCLAUDE_WORKSPACE in their local .env file.

======================================================================
PHASE 5 — OFFLINE WORKSPACE SETUP: HolyClaude + RAG-Stack
======================================================================

Add to stacks/holyclaude/README.md under new "## Offline workspace":

  ## Offline workspace — HolyClaude + RAG-Stack

  HolyClaude provides a full offline AI workspace when connected to the
  Ollama and RAG stacks on the NAS. No cloud API key is required.

  ### Architecture
  ```
  HolyClaude (3001)
    ├── /workspace → /volume1/homes/laolufayese (or per-machine path)
    ├── → Ollama API (10.0.1.15:11434)  — LLM inference
    ├── → AnythingLLM REST (10.0.1.15:3002)  — RAG document search
    └── → Qdrant REST (10.0.1.15:6333)  — direct vector search

  RAG-Stack
    ├── Qdrant (6333) — vector database
    ├── AnythingLLM (3002) — RAG UI + REST API
    └── Pipelines (9099) — Open WebUI LangChain pipeline server
  ```

  ### Deploy order (critical)
  1. **Ollama stack** — must be running and models pulled
     Wait for ollama-model-init to finish (check logs)
  2. **RAG-Stack** — depends on nomic-embed-text being available in Ollama
  3. **HolyClaude** — can start anytime, connects lazily to above services

  ### First-time NAS deploy sequence
  ```bash
  # 1. Deploy ollama stack (starts model init automatically)
  sudo docker compose -f /volume1/docker/dockge/stacks/ollama/compose.yaml up -d

  # 2. Watch model init (ctrl+C when done — init will still run)
  sudo docker logs ollama-model-init --follow

  # 3. Deploy rag-stack (requires nomic-embed-text to be available)
  #    First: fill rag-stack/.env (ANYTHINGLLM_JWT_SECRET, PIPELINES_API_KEY)
  sudo docker compose -f /volume1/docker/dockge/stacks/rag-stack/compose.yaml up -d

  # 4. Deploy holyclaude
  sudo docker compose -f /volume1/docker/dockge/stacks/holyclaude/compose.yaml up -d

  # 5. Access
  # HolyClaude: http://10.0.1.15:3001
  # AnythingLLM: http://10.0.1.15:3002
  # Open WebUI: http://10.0.1.15:8893
  ```

  ### Workspace path
  The workspace is mounted at `/workspace` inside the HolyClaude container.
  Host path: `/volume1/homes/laolufayese` (NAS default).

  This means `/workspace` inside the container maps to your DSM user home.
  All files created in `/workspace` persist on the NAS under your home dir.

  Per-machine workspace:
  | Machine | HOLYCLAUDE_WORKSPACE | Container path |
  |---|---|---|
  | NAS (DSM) | /volume1/homes/laolufayese | /workspace |
  | otsmbpro16 (Mac) | /Users/laolufayese | /workspace |
  | hpdevcore (WSL2) | /home/laolufayese | /workspace |

  ### Configure AnythingLLM token for HolyClaude
  1. Open AnythingLLM at http://10.0.1.15:3002
  2. Settings → API Keys → Generate new key
  3. Copy the key into stacks/holyclaude/.env:
       ANYTHINGLLM_API_TOKEN=<generated-key>
  4. Restart HolyClaude: docker compose restart holyclaude

  ### Deploy on otsmbpro16 (Mac)
  ```bash
  cd ~/dev/dockge
  # Create local .env with Mac-specific paths
  cat > stacks/holyclaude/.env << 'EOF'
  HOLYCLAUDE_WORKSPACE=/Users/laolufayese
  OLLAMA_HOST=http://10.0.1.15:11434
  ANYTHINGLLM_API_URL=http://10.0.1.15:3002
  ANYTHINGLLM_API_TOKEN=<your-token>
  QDRANT_URL=http://10.0.1.15:6333
  TZ=America/New_York
  PUID=0
  PGID=0
  EOF
  docker compose -f stacks/holyclaude/compose.yaml up -d
  # Access: http://localhost:3001
  ```

  ### Deploy on hpdevcore (Windows 11 / WSL2)
  ```bash
  # In WSL2 terminal:
  cd ~/dev/dockge   # or wherever repo is cloned in WSL2
  cat > stacks/holyclaude/.env << 'EOF'
  HOLYCLAUDE_WORKSPACE=/home/laolufayese
  OLLAMA_HOST=http://10.0.1.15:11434
  ANYTHINGLLM_API_URL=http://10.0.1.15:3002
  ANYTHINGLLM_API_TOKEN=<your-token>
  QDRANT_URL=http://10.0.1.15:6333
  TZ=America/New_York
  PUID=0
  PGID=0
  EOF
  docker compose -f stacks/holyclaude/compose.yaml up -d
  # Access: http://localhost:3001
  ```

  ### Fully offline operation
  HolyClaude works fully offline when ANTHROPIC_API_KEY and CURSOR_API_KEY
  are left empty. All inference routes through the NAS Ollama stack.
  Internet is not required after initial model pull.

  ### Using Ollama models in HolyClaude
  The OLLAMA_HOST env var tells HolyClaude where to find the inference server.
  Inside the Claude Code workspace, models are accessible via the Ollama API.
  When using Continue (VS Code extension) with HolyClaude, configure:
    Ollama base URL: http://10.0.1.15:11434 (or localhost if running locally)

======================================================================
PHASE 6 — RAG-STACK: workspace document ingestion
======================================================================

Add to stacks/rag-stack/README.md under "## Offline document workspace":

  ## Offline document workspace

  AnythingLLM at http://10.0.1.15:3002 is the primary interface for
  ingesting and querying documents offline using the local Ollama models.

  ### Ingest documents from workspace

  Method 1 — Via AnythingLLM UI:
    1. Open http://10.0.1.15:3002
    2. Create a workspace (e.g. "NAS Admin", "Coding Reference")
    3. Upload documents → AnythingLLM embeds using nomic-embed-text
    4. Chat with your documents using qwen2.5-coder:7b or llama3.1:8b

  Method 2 — Via REST API (for automation):
    # Upload a file to AnythingLLM workspace
    curl -X POST http://10.0.1.15:3002/api/v1/document/upload \
      -H "Authorization: Bearer $ANYTHINGLLM_API_TOKEN" \
      -F "file=@/path/to/document.pdf"

    # Query a workspace
    curl -X POST http://10.0.1.15:3002/api/v1/workspace/$WORKSPACE_SLUG/chat \
      -H "Authorization: Bearer $ANYTHINGLLM_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"message":"summarise this document","mode":"chat"}'

  ### Recommended workspaces to create
  | Workspace | Purpose | Suggested docs to ingest |
  |---|---|---|
  | NAS Admin | Synology/Docker/HAProxy reference | SETUP.md, NAS_DEPLOYMENT.md, haproxy.cfg |
  | Coding | Project code reference | Repo README files, API docs |
  | Research | Personal reading / papers | PDFs, markdown notes |
  | DevOps | Infrastructure runbooks | Task files, op docs |

  ### HolyClaude → AnythingLLM integration
  HolyClaude's ANYTHINGLLM_API_URL and ANYTHINGLLM_API_TOKEN connect it to
  this stack's REST API. Claude Code sessions can search your ingested docs
  by calling the AnythingLLM API from within HolyClaude workspace scripts.

======================================================================
PHASE 7 — DOCKER COMPATIBILITY: Container Manager vs Docker Desktop
======================================================================

Add to AGENTS.md ## What Works:

  [2026-05-08] Multi-machine Docker deployment — three environments:

  NAS (Container Manager / DSM 7.3.2):
  - Docker version: older compose CLI bundled by Synology Package Center
  - MUST NOT use depends_on with condition: service_healthy
  - MUST NOT use --health-check in compose depends_on
  - Use plain depends_on: [service-name] only
  - Resilience via restart: unless-stopped (healthchecks are advisory only)
  - Container Manager = Synology's branded Docker package; same Docker Engine
    underneath but exposed through DSM UI with limited compose support
  - Dockge bypasses Container Manager UI and calls docker compose directly

  otsmbpro16 (Mac / Apple Silicon):
  - Docker Desktop — full compose v2 support, condition: allowed
  - Workspace: /Users/laolufayese → /workspace in holyclaude
  - LAN access to NAS at 10.0.1.15 for all services
  - Mac-native ollama (brew) is alternative to NAS ollama

  hpdevcore (Windows 11 / WSL2):
  - Docker Engine in WSL2 — full compose v2 support, condition: allowed
  - Workspace: /home/laolufayese → /workspace in holyclaude (recommended)
  - Windows home via WSL2: /mnt/c/Users/laolufayese (slower I/O, avoid)
  - PUID/PGID: use WSL2 user UID/GID, not root (run: id laolufayese)
  - LAN access to NAS at 10.0.1.15 for all services

  HOLYCLAUDE_WORKSPACE override is the ONLY env var that changes per machine.
  All other services point to the NAS at 10.0.1.15 regardless of client machine.

======================================================================
PHASE 8 — VALIDATION
======================================================================

  # Compose validates (NAS compatible — no condition:)
  scripts/compose-validate.sh
  Expected: All compose files validated OK

  # Model init service has restart: "no"
  grep -A2 "restart:" stacks/ollama/compose.yaml | grep '"no"'
  Expected: match

  # Workspace mount uses variable correctly
  grep "HOLYCLAUDE_WORKSPACE" stacks/holyclaude/compose.yaml
  Expected: ${HOLYCLAUDE_WORKSPACE:-/volume1/homes/laolufayese}

  # No condition: in ollama or rag-stack compose
  grep "condition:" \
    stacks/ollama/compose.yaml \
    stacks/rag-stack/compose.yaml
  Expected: zero matches

  # ollama-net subnet allocated
  grep "172.27.0" stacks/ollama/compose.yaml
  Expected: subnet: 172.27.0.0/24

  pre-commit run --files \
    stacks/ollama/compose.yaml \
    stacks/ollama/.env.example \
    stacks/holyclaude/.env.example \
    stacks/holyclaude/README.md \
    stacks/rag-stack/README.md

  Expected: all hooks pass

  git add \
    stacks/ollama/compose.yaml \
    stacks/ollama/.env.example \
    stacks/holyclaude/.env.example \
    stacks/holyclaude/README.md \
    stacks/rag-stack/README.md \
    docs/hive/NAS_DEPLOYMENT.md
  git commit -m \
    "feat: ollama-model-init auto-pull service; multi-machine Docker guide; \
holyclaude offline workspace (NAS/Mac/WSL2); rag-stack document ingestion docs"
  git push

======================================================================
PHASE 9 — NAS OPERATOR SEQUENCE (manual, after git push)
======================================================================

  ### On NAS after git pull:

  ## 1. Create rag-stack secrets
  cd /volume1/docker/dockge/stacks/rag-stack
  cp .env.example .env
  # Fill in:
  ANYTHINGLLM_JWT_SECRET=$(openssl rand -hex 32)
  PIPELINES_API_KEY=$(openssl rand -hex 24)
  # Add to .env file (not committed)

  ## 2. Deploy in order: ollama → rag-stack → holyclaude

  # ollama (starts model init automatically)
  sudo docker compose -f /volume1/docker/dockge/stacks/ollama/compose.yaml up -d
  # Watch init progress:
  sudo docker logs ollama-model-init --follow
  # Wait until "Done. Container will exit" is logged before proceeding.

  # rag-stack (nomic-embed-text must be pulled — ollama-model-init does this)
  sudo docker compose -f /volume1/docker/dockge/stacks/rag-stack/compose.yaml up -d

  # holyclaude
  sudo docker compose -f /volume1/docker/dockge/stacks/holyclaude/compose.yaml up -d

  ## 3. Configure AnythingLLM
  # Open http://10.0.1.15:3002
  # Complete setup wizard:
  #   LLM: Ollama → URL: http://10.0.1.15:11434 → Model: qwen2.5-coder:7b
  #   Embeddings: Ollama → URL: http://10.0.1.15:11434 → Model: nomic-embed-text
  #   Vector DB: Qdrant → URL: http://qdrant:6333 (internal) or http://10.0.1.15:6333
  # Settings → API Keys → Generate → copy to holyclaude/.env ANYTHINGLLM_API_TOKEN

  ## 4. Restart holyclaude with token
  # Edit /volume1/docker/dockge/stacks/holyclaude/.env with the token
  sudo docker compose -f /volume1/docker/dockge/stacks/holyclaude/compose.yaml restart

  ## 5. Access points
  # HolyClaude workspace UI: http://10.0.1.15:3001
  # AnythingLLM:             http://10.0.1.15:3002
  # Open WebUI:              http://10.0.1.15:8893
  # Qdrant dashboard:        http://10.0.1.15:6333/dashboard
  # Pipelines:               http://10.0.1.15:9099

======================================================================
PHASE 10 — COMPOUND MEMORY UPDATE
======================================================================

/compound-learning

Add to AGENTS.md ## What Works:

  [2026-05-08] Multi-machine Docker + auto-pull + offline workspace:

  OLLAMA AUTO-PULL (ollama-model-init service):
  - One-shot service, restart: "no", depends_on: ollama (no condition:)
  - Polls /usr/bin/ollama list until ready (5s intervals, 5min timeout)
  - pull_if_missing: checks ollama list before pulling — idempotent
  - Tier 1/2/3 models configured via env vars in .env
  - nomic-embed-text MUST be in Tier 1 — AnythingLLM needs it at startup
  - Re-trigger: docker compose up --force-recreate ollama-model-init
  - Models persist in STACK_ROOT/ollama/data/ollama across restarts

  MULTI-MACHINE DOCKER ENVIRONMENTS:
  - NAS (Container Manager): depends_on WITHOUT condition: REQUIRED
    Synology's bundled compose CLI doesn't support condition: service_healthy
    All resilience via restart: unless-stopped + healthchecks (advisory only)
  - otsmbpro16 (Mac): Docker Desktop, full compose v2, condition: OK
  - hpdevcore (Windows WSL2): Docker Engine in WSL2, condition: OK
  - All machines connect to NAS ollama at 10.0.1.15:11434 over LAN

  HOLYCLAUDE WORKSPACE:
  - HOLYCLAUDE_WORKSPACE is the only env var that changes per machine
  - NAS: /volume1/homes/laolufayese (DSM user home)
  - Mac: /Users/laolufayese
  - WSL2: /home/laolufayese (NOT /mnt/c/Users/laolufayese — slow I/O)
  - Default in compose.yaml: /volume1/homes/laolufayese (NAS)

  OFFLINE WORKFLOW:
  - Deploy order: ollama → (wait for model-init) → rag-stack → holyclaude
  - AnythingLLM API token: generate in UI, add to holyclaude/.env
  - Fully offline: ANTHROPIC_API_KEY and CURSOR_API_KEY can be blank
  - Workspace persists at /volume1/homes/laolufayese on NAS

======================================================================
FINAL PRINT
======================================================================

DOCKER-MULTIHOST-OLLAMA-OFFLINE-WORKSPACE: COMPLETE
