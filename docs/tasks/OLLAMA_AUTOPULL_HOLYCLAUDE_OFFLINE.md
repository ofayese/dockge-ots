# Task: Automated Ollama Model Pulls + Offline AI Stack (HolyClaude + RAG)
# Version: 2026-05-08
# Multi-Docker context: NAS (Container Manager), otsmbpro16 (Mac), hpdevcore (Windows WSL2)

/coder
/compound-learning

======================================================================
CONTEXT
======================================================================

This task implements three related changes:

1. AUTOMATED MODEL PULLS: An `ollama-model-init` one-shot sidecar
   pulls all required models automatically when the ollama stack comes
   online. No manual `docker exec` commands needed after first deploy.

2. HOLYCLAUDE OFFLINE WORKSPACE: HolyClaude workspace changed from
   ${STACK_ROOT}/holyclaude/data to /volume1/homes/laolufayese
   (the DSM user home directory for laolufayese). This makes the user's
   full home directory available as the AI workspace context.

3. DOCKER MULTI-CONTEXT AWARENESS:
   - NAS (Container Manager): primary AI stack host
   - otsmbpro16 (Mac/Apple Silicon): accesses NAS stack via LAN
   - hpdevcore (Windows 11, WSL2): accesses NAS stack via LAN

======================================================================
PHASE 0 — PRE-FLIGHT READS
======================================================================

  stacks/ollama/compose.yaml        (model-init sidecar added)
  stacks/holyclaude/compose.yaml    (workspace + offline env vars)
  stacks/holyclaude/.env.example    (HOLYCLAUDE_WORKSPACE + AI vars)
  stacks/rag-stack/compose.yaml     (named network, better model)
  stacks/rag-stack/.env.example     (qwen2.5-coder:7b as default)
  scripts/init-nas.sh               (verify STACK_MANIFEST)

======================================================================
PHASE 1 — VERIFY CHANGES ALREADY APPLIED
======================================================================

The compose files were updated directly. Verify each gate:

STEP 1A — Ollama init sidecar present:
  Command: grep "ollama-model-init" stacks/ollama/compose.yaml
  Expected: container definition present

STEP 1B — Workspace operator exception in holyclaude:
  Command: grep "HOLYCLAUDE_WORKSPACE\|volume1/homes" stacks/holyclaude/compose.yaml
  Expected: ${HOLYCLAUDE_WORKSPACE:-/volume1/homes/laolufayese}:/workspace

STEP 1C — Offline AI env vars in holyclaude:
  Command: grep "OLLAMA_HOST\|ANYTHINGLLM_API_URL\|QDRANT_URL" \
    stacks/holyclaude/compose.yaml
  Expected: all three present

STEP 1D — rag-net network with subnet:
  Command: grep "172.27.1.0" stacks/rag-stack/compose.yaml
  Expected: subnet 172.27.1.0/24

STEP 1E — ollama-net network with subnet:
  Command: grep "172.27.0.0" stacks/ollama/compose.yaml
  Expected: subnet 172.27.0.0/24

STEP 1F — Better default model in rag-stack:
  Command: grep "ANYTHINGLLM_LLM_MODEL\|qwen2.5-coder" \
    stacks/rag-stack/compose.yaml stacks/rag-stack/.env.example
  Expected: qwen2.5-coder:7b as default

STEP 1G — HOLYCLAUDE_WORKSPACE in .env.example:
  Command: grep "HOLYCLAUDE_WORKSPACE" stacks/holyclaude/.env.example
  Expected: HOLYCLAUDE_WORKSPACE=/volume1/homes/laolufayese

======================================================================
PHASE 2 — UPDATE README: holyclaude offline setup
======================================================================

Update stacks/holyclaude/README.md with:

  ## Workspace

  The container mounts the workspace at `/workspace` inside the container.
  The host path is controlled by `HOLYCLAUDE_WORKSPACE` in `.env`.

  | Machine | .env value |
  |---|---|
  | NAS (default) | `/volume1/homes/laolufayese` |
  | hpdevcore (WSL2) | `/home/laolufayese` |
  | otsmbpro16 (Mac) | `/Users/laolufayese` |

  Create the workspace on the NAS if it doesn't exist:
  ```bash
  sudo mkdir -p /volume1/homes/laolufayese
  sudo chown laolufayese:users /volume1/homes/laolufayese
  ```

  ## Offline AI stack integration

  HolyClaude connects to the local AI stack via LAN IPs. All inference
  is handled by the NAS ollama stack — no internet required for:
  - Document RAG queries (via AnythingLLM)
  - Code completion (via Ollama)
  - Vector search (via Qdrant)

  Set in `.env`:
  ```
  OLLAMA_HOST=http://10.0.1.15:11434         # Ollama LLM API
  ANYTHINGLLM_API_URL=http://10.0.1.15:3002  # RAG API
  ANYTHINGLLM_API_TOKEN=<from AnythingLLM UI → Settings → API Keys>
  QDRANT_URL=http://10.0.1.15:6333           # Vector DB
  ```

  For fully offline use, leave ANTHROPIC_API_KEY blank. HolyClaude
  will fall back to local Ollama for all AI features.

  ## Multi-machine access

  The NAS-hosted AI stack is accessible from any machine on the LAN:

  | Service | URL | Notes |
  |---|---|---|
  | Open WebUI chat | http://10.0.1.15:8893 | Browser UI for Ollama models |
  | Ollama API | http://10.0.1.15:11434 | REST API, OpenAI-compatible at /v1/ |
  | AnythingLLM | http://10.0.1.15:3002 | RAG UI + API |
  | Qdrant dashboard | http://10.0.1.15:6333/dashboard | Vector DB UI |
  | Pipelines | http://10.0.1.15:9099 | Open WebUI pipeline server |

  From otsmbpro16 or hpdevcore, connect Cursor to these same URLs.
  No VPN needed — all services are on the 10.0.1.x LAN.

======================================================================
PHASE 3 — UPDATE README: ollama auto-pull documentation
======================================================================

Update stacks/ollama/README.md to document the init sidecar:

  ## Automated model pulls (ollama-model-init)

  The `ollama-model-init` container is a one-shot sidecar that runs
  automatically when the stack starts. It:
  1. Waits for the Ollama API to be ready
  2. Pulls all required models in priority order
  3. Exits with code 0 (normal — "Exited" in Dockge is expected)

  Model pull order (smallest → largest so interactive use unblocks early):
  1. phi4:mini        — fast general assistant (~2.5 GB)
  2. nomic-embed-text — required for RAG/AnythingLLM (~274 MB)
  3. llama3.2:3b      — fast chat (~2.0 GB)
  4. qwen2.5-coder:7b — primary coding model (~4.4 GB)
  5. llama3.1:8b      — research + devops (~4.7 GB)
  6. mistral:7b       — Linux/server commands (~4.1 GB)
  7. deepseek-r1:7b   — chain-of-thought reasoning (~4.7 GB)
  8. qwen2.5:7b       — general research (~4.4 GB)

  Total download: ~31 GB. On a typical NAS internet connection this
  takes 30-120 minutes. Progress is visible in Dockge logs:
  ```
  Dockge → ollama stack → Logs → Select "ollama-model-init"
  ```

  Model pulls are idempotent — re-running the stack checks existing
  models and only downloads what's missing or outdated.

  ## Manual pull override

  To add a model not in the init list, pull manually:
  ```bash
  sudo docker exec otsai-server ollama pull <model>
  ```

  To see all installed models:
  ```bash
  sudo docker exec otsai-server ollama list
  ```

======================================================================
PHASE 4 — MULTI-DOCKER CONTEXT DOCUMENTATION
======================================================================

Add to docs/hive/NAS_DEPLOYMENT.md under "## Multi-machine access":

  ## Docker multi-context reference

  The homelab has three Docker hosts. AI inference always runs on the
  NAS (Container Manager) — the Mac and Windows machines consume it
  over the LAN.

  | Host | Docker runtime | Role | Connect to NAS AI |
  |---|---|---|---|
  | otsorundscore (NAS) | Container Manager (Docker CE) | AI stack host | localhost |
  | otsmbpro16 (Mac) | Docker Desktop (Apple Silicon) | Dev workstation | http://10.0.1.15:* |
  | hpdevcore (Windows 11) | Docker Desktop + WSL2 | Dev workstation | http://10.0.1.15:* |

  ### otsmbpro16 (Mac) — Cursor remote to NAS

  Deploy Cursor remote server to NAS:
  ```bash
  bash scripts/cursor-remote-update.sh  # from ~/dev/dockge on Mac
  ```
  Then: Cursor → Remote Explorer → otsorundscore

  ### hpdevcore (Windows 11 + WSL2)

  WSL2 Docker daemon runs inside the WSL2 VM. NAS is reachable at
  10.0.1.15 from WSL2 as a standard LAN connection.

  To run holyclaude on hpdevcore instead of NAS:
  ```
  HOLYCLAUDE_WORKSPACE=/home/laolufayese  # WSL2 home dir
  OLLAMA_HOST=http://10.0.1.15:11434      # still use NAS Ollama
  ```

  WSL2 Docker socket path: /var/run/docker.sock (inside WSL2)
  From Windows: \\.\pipe\docker_engine

  ### Connecting Cursor to local Ollama models (all machines)

  In Cursor settings, set OpenAI-compatible base URL:
    http://10.0.1.15:11434/v1
  This routes Cursor's AI features through the NAS Ollama stack.

======================================================================
PHASE 5 — OPERATOR DEPLOYMENT SEQUENCE (NAS)
======================================================================

These steps are run MANUALLY on the NAS. Document them in
docs/hive/NAS_DEPLOYMENT.md under "## Offline AI stack deployment":

  ## Offline AI stack deployment (NAS)

  ### Prerequisites
  1. Ollama stack deployed and healthy (otsai-server on port 11434)
  2. RAG stack deployed (qdrant, anythingllm, pipelines)

  ### Step 1 — Create user workspace directory
  ```bash
  sudo mkdir -p /volume1/homes/laolufayese
  sudo chown laolufayese:administrators /volume1/homes/laolufayese
  chmod 750 /volume1/homes/laolufayese
  ```

  ### Step 2 — Copy holyclaude .env
  ```bash
  cd /volume1/docker/dockge/stacks/holyclaude
  cp .env.example .env
  nano .env
  # Fill: ANTHROPIC_API_KEY (optional), ANYTHINGLLM_API_TOKEN
  # Verify: HOLYCLAUDE_WORKSPACE=/volume1/homes/laolufayese
  ```

  ### Step 3 — Deploy stacks in order
  ```bash
  # 1. Ollama (triggers model-init auto-pull)
  sudo docker compose -f stacks/ollama/compose.yaml up -d

  # 2. Watch model downloads in init container logs
  sudo docker logs -f ollama-model-init

  # 3. Verify all models loaded (after init completes)
  sudo docker exec otsai-server ollama list

  # 4. Deploy RAG stack (needs nomic-embed-text to be pulled first)
  sudo docker compose -f stacks/rag-stack/compose.yaml up -d

  # 5. Deploy holyclaude
  sudo docker compose -f stacks/holyclaude/compose.yaml up -d
  ```

  ### Step 4 — Configure AnythingLLM
  Open http://10.0.1.15:3002
  1. Complete initial setup wizard
  2. Settings → LLM Provider → Ollama → http://10.0.1.15:11434
  3. Model: qwen2.5-coder:7b (or llama3.1:8b for research)
  4. Settings → Embedding → Ollama → nomic-embed-text
  5. Settings → API Keys → Generate → copy to holyclaude .env
     as ANYTHINGLLM_API_TOKEN

  ### Step 5 — Connect Open WebUI to Pipelines
  Open http://10.0.1.15:8893 (admin)
  Settings → Connections → Add Pipelines Server:
    URL: http://10.0.1.15:9099
    API Key: (from rag-stack .env → PIPELINES_API_KEY)

  ### Step 6 — Add documents to AnythingLLM workspace
  Create workspace: "Home" (backed by /volume1/homes/laolufayese)
  Upload documents via UI or API at http://10.0.1.15:3002/api/v1/

======================================================================
PHASE 6 — AGENTS.MD UPDATE
======================================================================

Add to AGENTS.md ## Stack Operations Memory:

  [2026-05-08] Automated ollama model pulls:
  - ollama-model-init: one-shot sidecar using ollama image + OLLAMA_HOST
    pointing to the server. Plain depends_on (no condition:) for Synology
    compatibility; wait loop in command handles startup race.
  - "Exited (0)" status in Dockge for ollama-model-init is CORRECT —
    it is a one-shot init container, not a long-running service.
  - Model pulls are idempotent — re-running the stack is safe.
  - $$model in compose command: double $ prevents Compose variable
    interpolation of shell variables.

  [2026-05-08] HolyClaude workspace operator exception:
  - HOLYCLAUDE_WORKSPACE: EXEMPT from STACK_ROOT convention.
    Mount targets /volume1/homes/laolufayese (DSM user home).
    Override per machine in .env:
      NAS:            /volume1/homes/laolufayese
      hpdevcore WSL2: /home/laolufayese
      otsmbpro16 Mac: /Users/laolufayese
  - Offline AI vars: OLLAMA_HOST, ANYTHINGLLM_API_URL, QDRANT_URL
    all point to NAS LAN IPs (10.0.1.15:*).

  [2026-05-08] Multi-Docker host context:
  - NAS (Container Manager): primary AI stack host, all inference here
  - otsmbpro16 (Mac): Docker Desktop, consumes NAS stack via LAN
  - hpdevcore (Windows 11 + WSL2): Docker Desktop + WSL2, same
  - WSL2 Docker socket: /var/run/docker.sock (inside WSL2 VM)
  - Cursor remote to NAS: bash scripts/cursor-remote-update.sh (from Mac)

  [2026-05-08] rag-stack model update:
  - ANYTHINGLLM_LLM_MODEL default changed phi4:mini → qwen2.5-coder:7b
  - qwen2.5-coder:7b outperforms all 7B models for coding + research in 2026
  - Context window raised 4096 → 8192 (qwen2.5-coder:7b supports 32K)
  - nomic-embed-text: still required, still auto-pulled by ollama-model-init

======================================================================
PHASE 7 — VALIDATION
======================================================================

  scripts/compose-validate.sh
  Expected: All compose files validated OK.

  # Ollama init sidecar
  docker compose -f stacks/ollama/compose.yaml config \
    | grep -A3 "ollama-model-init"
  Expected: restart "no", OLLAMA_HOST=http://ollama:11434

  # Holyclaude workspace
  grep "HOLYCLAUDE_WORKSPACE" stacks/holyclaude/compose.yaml
  Expected: ${HOLYCLAUDE_WORKSPACE:-/volume1/homes/laolufayese}:/workspace

  # No $$model issue (double $ correct for Compose)
  grep "for model in" stacks/ollama/compose.yaml
  Expected: $$model (not $model — single $ would be Compose variable)

  # Networks have name: override
  grep "name:" stacks/ollama/compose.yaml stacks/rag-stack/compose.yaml
  Expected: name: ollama-net and name: rag-net present

  # Subnets allocated correctly
  grep "172.27" stacks/ollama/compose.yaml stacks/rag-stack/compose.yaml
  Expected: 172.27.0.0/24 in ollama, 172.27.1.0/24 in rag-stack

  pre-commit run --files \
    stacks/ollama/compose.yaml \
    stacks/holyclaude/compose.yaml \
    stacks/holyclaude/.env.example \
    stacks/rag-stack/compose.yaml \
    stacks/rag-stack/.env.example
  Expected: all hooks pass

  git add \
    stacks/ollama/compose.yaml \
    stacks/ollama/.env.example \
    stacks/holyclaude/compose.yaml \
    stacks/holyclaude/.env.example \
    stacks/rag-stack/compose.yaml \
    stacks/rag-stack/.env.example
  git commit -m \
    "feat: ollama-model-init auto-pull sidecar; holyclaude workspace /volume1/homes/laolufayese; \
offline AI stack integration (OLLAMA_HOST/AnythingLLM/Qdrant); rag-net + ollama-net subnets"
  git push

======================================================================
FINAL PRINT
======================================================================

OLLAMA-AUTOPULL-HOLYCLAUDE-OFFLINE: COMPLETE
