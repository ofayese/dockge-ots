# Task: Ollama Model Selection and Stack Optimisation — DS723+
# Version: 2026-05-08

/coder
/compound-learning

======================================================================
HARDWARE PROFILE — DS723+ (otsorundscore)
======================================================================

  CPU:  AMD Ryzen R1600 embedded, 2 cores / 4 threads, 2.6 GHz
  RAM:  32 GB
  GPU:  NONE (CPU-only inference)
  OS:   Synology DSM 7.3.2-86009 Update 3
  TZ:   America/New_York

  Current Ollama image: ollama/ollama:0.22.0  ← significantly outdated
  Current mem_limit: 8g  ← conservative, can safely raise to 16g
  Current OLLAMA_NUM_PARALLEL: 1  ← correct for CPU
  Current OLLAMA_MAX_LOADED_MODELS: 1  ← correct for CPU

  RAM BUDGET ANALYSIS:
    32 GB total
    - DSM OS + kernel:             ~2 GB
    - Dockge + running stacks:     ~4 GB (conservatively)
    - Available for ollama:       ~26 GB usable
    - Safe ollama mem_limit:       16 GB (leaves 10 GB headroom for OS + stacks)
    - Peak ollama mem_limit:       20 GB (tight; only if other stacks shut down)
    - NEVER allocate > 24 GB to ollama on this box

  CPU INFERENCE SPEED EXPECTATIONS (R1600, Q4_K_M quantisation):
    Model size | RAM (Q4)  | Tokens/sec | Usability
    ───────────┼───────────┼────────────┼─────────────────
    phi4:mini  | ~2.5 GB   | 8-15 t/s   | Interactive ✓✓
    3B         | ~2.0 GB   | 8-15 t/s   | Interactive ✓✓
    7B / 8B    | ~4.5 GB   | 3-7 t/s    | Interactive ✓
    14B        | ~8.5 GB   | 1-3 t/s    | Slow but usable
    32B        | ~20 GB    | <1 t/s     | Batch/overnight only
    70B        | ~43 GB    | FAILS      | Exceeds RAM

  KEY PRINCIPLE: A well-tuned 7B model running at 5 t/s is more
  useful on this hardware than a 32B model at 0.3 t/s. Prioritise
  small-to-mid models with strong training quality (Qwen 2.5, Phi 4,
  Llama 3.1) over raw parameter count.

======================================================================
PHASE 0 — PRE-FLIGHT READS
======================================================================

  stacks/ollama/compose.yaml
  stacks/ollama/.env.example
  stacks/ollama/README.md

======================================================================
PHASE 1 — UPDATE COMPOSE: image version + mem_limit
======================================================================

FINDING: ollama/ollama:0.22.0 is significantly outdated.
  - 0.22.0 lacks Q4_K_M support for several model families
  - Missing OLLAMA_KEEP_ALIVE env var support
  - Missing improved CPU thread scheduling
  - Tag history: latest by May 2026 is ~0.7.x

CHANGE 1 — Update image tag in stacks/ollama/compose.yaml:

  Current:  image: ollama/ollama:0.22.0
  Change:   image: ollama/ollama:latest

  Rationale: Ollama has a stable API contract; breaking changes are
  rare. Watchtower already manages this stack. Using :latest ensures
  new model format support and CPU optimisations are picked up.

  ALTERNATIVE: Pin to a specific recent tag after checking
  https://hub.docker.com/r/ollama/ollama/tags for the latest stable.
  Preferred on this NAS for auditability: use explicit semver tag.
  Check and update to: ollama/ollama:0.6.8 (or latest at time of deploy)

CHANGE 2 — Raise mem_limit from 8g to 16g:

  Current:  mem_limit: 8g
  Change:   mem_limit: 16g

  Rationale: With 32 GB NAS RAM and ~6 GB consumed by OS/stacks,
  16 GB for ollama allows 14B models (8.5 GB) to load comfortably
  with KV cache headroom. 8g was too restrictive — phi4:mini (2.5 GB)
  left 5.5 GB idle, preventing any 7B+ model from loading.

CHANGE 3 — Add OLLAMA_KEEP_ALIVE env var:

  Add to environment block:
    - OLLAMA_KEEP_ALIVE=30m

  Rationale: Default is 5 minutes; on CPU this is too short because
  model reload takes 15-60s. 30 minutes is a better trade-off between
  RAM availability and reuse for interactive sessions.
  Set to -1 (infinite) if only one model is used.
  Set to 5m to conserve RAM between infrequent sessions.

CHANGE 4 — Update DEFAULT_MODELS env var:

  Current:  DEFAULT_MODELS=phi4:mini
  Change:   DEFAULT_MODELS=phi4:mini,qwen2.5-coder:7b,nomic-embed-text

  This pre-loads the three baseline models when open-webui starts.
  nomic-embed-text is required by AnythingLLM for embeddings.

FINAL stacks/ollama/compose.yaml ollama service diff (environment block):

  Add these lines to the environment: section:
    - OLLAMA_KEEP_ALIVE=30m
    - OLLAMA_FLASH_ATTENTION=1

  OLLAMA_FLASH_ATTENTION=1 enables flash attention on CPU — reduces
  memory usage for long contexts with no quality loss.

======================================================================
PHASE 2 — MODEL REGISTRY: pull commands by use case
======================================================================

IMPORTANT: Run ALL pull commands as root on the NAS (docker exec needs
the container running). Models persist in STACK_ROOT/ollama/data/ollama.

  ## Baseline (pull these first — always-available, fast, small)

  # General assistant + quick tasks (already default)
  sudo docker exec otsai-server ollama pull phi4:mini

  # Best-in-class 3B general model — fast, good reasoning
  sudo docker exec otsai-server ollama pull llama3.2:3b

  # Required embedding model for AnythingLLM / RAG pipelines
  sudo docker exec otsai-server ollama pull nomic-embed-text

  ## Coding (for win/linux/osx/server scripts, Docker, YAML, bash)

  # PRIMARY CODING MODEL — outperforms all 7B coding models in 2026
  # Trained specifically on code, excellent at multi-language output
  # Covers: Python, TypeScript, JavaScript, Bash, YAML, Docker Compose
  sudo docker exec otsai-server ollama pull qwen2.5-coder:7b

  # Alternative: deeper context (9B, slower but better at large files)
  # sudo docker exec otsai-server ollama pull qwen2.5-coder:14b

  # For Windows PowerShell / C# / .NET specific tasks:
  # sudo docker exec otsai-server ollama pull qwen2.5-coder:7b
  # (same model — qwen2.5-coder trained on all Windows scripting formats)

  ## Research (document analysis, summarisation, paper reading)

  # Best general-purpose 8B model — strong reasoning + long context
  sudo docker exec otsai-server ollama pull llama3.1:8b

  # Chain-of-thought reasoning — shows thinking steps for analysis
  sudo docker exec otsai-server ollama pull deepseek-r1:7b

  # Strong multilingual research + structured output
  sudo docker exec otsai-server ollama pull qwen2.5:7b

  ## DevOps (Docker, Kubernetes, Ansible, Terraform, NAS admin)

  # qwen2.5-coder:7b (pulled above) — also excellent for:
  #   - Docker Compose YAML generation
  #   - Synology DSM bash scripts
  #   - HAProxy configuration
  #   - Network troubleshooting commands

  # General DevOps + infrastructure reasoning
  # (llama3.1:8b pulled above also covers this well)

  ## MacOS specific (Apple Silicon, Homebrew, macOS scripting)

  # llama3.1:8b handles macOS tasks well
  # phi4:mini is good for quick macOS terminal commands

  ## Server administration (Linux sysadmin, systemd, networking)

  # mistral:7b — fast responses, excellent at Linux commands
  sudo docker exec otsai-server ollama pull mistral:7b

  ## Large models (16GB mem_limit required — load on demand)

  # Best coding model for complex multi-file refactoring
  # Load time: ~45s on R1600. Speed: ~1.5 t/s. Use for deep analysis.
  # sudo docker exec otsai-server ollama pull qwen2.5-coder:14b

  # Complex reasoning for research (Microsoft Phi4 14B)
  # Excellent at math, logic, structured analysis
  # Load time: ~60s on R1600. Speed: ~1.5 t/s.
  # sudo docker exec otsai-server ollama pull phi4:14b

======================================================================
PHASE 3 — MODEL SELECTION MATRIX
======================================================================

  ## Quick-reference: which model for which task

  USE CASE                        | PRIMARY           | FALLBACK
  ─────────────────────────────── | ───────────────── | ─────────────
  Chat / general assistant        | phi4:mini         | llama3.2:3b
  Coding: Python/JS/TS            | qwen2.5-coder:7b  | llama3.1:8b
  Coding: Bash/Shell scripts      | qwen2.5-coder:7b  | mistral:7b
  Coding: Docker/YAML/config      | qwen2.5-coder:7b  | qwen2.5:7b
  Coding: Win PowerShell/C#       | qwen2.5-coder:7b  | llama3.1:8b
  Coding: macOS/Swift/Obj-C       | qwen2.5-coder:7b  | llama3.1:8b
  Research: summarisation         | llama3.1:8b       | qwen2.5:7b
  Research: reasoning/analysis    | deepseek-r1:7b    | llama3.1:8b
  Research: document QA / RAG     | qwen2.5:7b        | llama3.1:8b
  DevOps: Docker Compose          | qwen2.5-coder:7b  | qwen2.5:7b
  DevOps: networking/firewall     | mistral:7b        | llama3.1:8b
  DevOps: Synology NAS admin      | qwen2.5-coder:7b  | mistral:7b
  DevOps: Ansible/Terraform       | qwen2.5-coder:7b  | llama3.1:8b
  Embeddings / RAG                | nomic-embed-text  | REQUIRED for AnythingLLM
  Complex reasoning (slow OK)     | phi4:14b          | deepseek-r1:7b

======================================================================
PHASE 4 — OPEN-WEBUI CONFIGURATION
======================================================================

STEP 4A — Set default model per workspace in Open WebUI:
  URL: http://10.0.1.15:8893
  Settings → Admin Settings → Models → Set defaults:
    - Default model: phi4:mini (fast for casual use)
    - Coding workspace: qwen2.5-coder:7b
    - Research workspace: llama3.1:8b

STEP 4B — Update DEFAULT_MODELS in stacks/ollama/.env.example:
  DEFAULT_MODELS=phi4:mini,qwen2.5-coder:7b,nomic-embed-text

  NOTE: DEFAULT_MODELS tells open-webui which models to show by default
  in the dropdown. It does NOT auto-pull models — you must pull manually
  using the docker exec commands in Phase 2.

STEP 4C — Update OLLAMA_BASE_URL if needed:
  Current: OLLAMA_BASE_URL=http://10.0.1.15:11434
  This is correct — keep as-is.

STEP 4D — Configure SearXNG integration in Open WebUI:
  Settings → Web Search → Enable web search
  URL: http://10.0.1.15:8888
  No auth needed (same LAN).
  This gives research queries real web results alongside model reasoning.

======================================================================
PHASE 5 — ANYTHINGLLM INTEGRATION (rag-stack)
======================================================================

AnythingLLM in rag-stack connects to Ollama for:
  1. Chat model: qwen2.5-coder:7b or llama3.1:8b
  2. Embedding model: nomic-embed-text (REQUIRED — pull this first)

STEP 5A — Verify AnythingLLM Ollama connection:
  Open AnythingLLM at http://10.0.1.15:3002
  Settings → LLM Provider → Ollama
  Base URL: http://10.0.1.15:11434
  Model: qwen2.5-coder:7b (or llama3.1:8b for research)

STEP 5B — Configure embeddings:
  Settings → Embedding Provider → Ollama
  Model: nomic-embed-text
  This is the REQUIRED embedding model for vector search.

STEP 5C — Pull nomic-embed-text immediately after stack restart:
  sudo docker exec otsai-server ollama pull nomic-embed-text
  (Small model ~274 MB — pulls quickly)

======================================================================
PHASE 6 — COMPOSE.YAML UPDATES
======================================================================

Read stacks/ollama/compose.yaml then apply these targeted edits:

  1. Update image version (check Docker Hub for latest stable):
     image: ollama/ollama:latest
     OR pin to latest stable tag from https://hub.docker.com/r/ollama/ollama/tags

  2. Raise mem_limit:
     mem_limit: 16g

  3. Add to environment block:
     - OLLAMA_KEEP_ALIVE=30m
     - OLLAMA_FLASH_ATTENTION=1

  4. Update DEFAULT_MODELS in open-webui service:
     - DEFAULT_MODELS=phi4:mini,qwen2.5-coder:7b,nomic-embed-text

  Run: scripts/compose-validate.sh stacks/ollama/compose.yaml
  Expected: config valid (env warnings acceptable)

======================================================================
PHASE 7 — README UPDATE: model docs + pull reference
======================================================================

Update stacks/ollama/README.md with:

  ## Hardware profile (DS723+)
  CPU: AMD Ryzen R1600 (2 cores / 4 threads), 2.6 GHz, CPU-only
  RAM: 32 GB NAS (16 GB allocated to this stack via mem_limit)
  GPU: None — all inference is CPU-bound

  ## Recommended model tiers

  ### Tier 1 — Always available (fast, small, ≤5 GB)
  | Model | Pull command | Size | Best for |
  |---|---|---|---|
  | phi4:mini | ollama pull phi4:mini | ~2.5 GB | General assistant, quick tasks |
  | llama3.2:3b | ollama pull llama3.2:3b | ~2.0 GB | Fast chat, lightweight tasks |
  | qwen2.5-coder:7b | ollama pull qwen2.5-coder:7b | ~4.4 GB | All coding tasks |
  | nomic-embed-text | ollama pull nomic-embed-text | ~274 MB | RAG embeddings (required) |

  ### Tier 2 — On demand (moderate, 4-9 GB, 2-5 t/s)
  | Model | Pull command | Size | Best for |
  |---|---|---|---|
  | llama3.1:8b | ollama pull llama3.1:8b | ~4.7 GB | Research, documentation, devops |
  | qwen2.5:7b | ollama pull qwen2.5:7b | ~4.4 GB | Research, structured output |
  | deepseek-r1:7b | ollama pull deepseek-r1:7b | ~4.7 GB | Chain-of-thought reasoning |
  | mistral:7b | ollama pull mistral:7b | ~4.1 GB | Linux commands, fast responses |

  ### Tier 3 — Heavy (slow, 8-9 GB, <2 t/s — use for batch tasks)
  | Model | Pull command | Size | Best for |
  |---|---|---|---|
  | phi4:14b | ollama pull phi4:14b | ~8.5 GB | Complex reasoning, math |
  | qwen2.5-coder:14b | ollama pull qwen2.5-coder:14b | ~9 GB | Large code analysis |

  ## CPU inference speed reference
  3B model: 8-15 t/s (interactive)
  7B model: 3-7 t/s  (interactive)
  14B model: 1-3 t/s  (usable — slow)
  32B model: <1 t/s   (batch only; not recommended on R1600)
  70B model: will OOM — DO NOT PULL on this hardware

  ## Pull all recommended models
  ```bash
  # Run on the NAS as root:
  sudo docker exec otsai-server ollama pull phi4:mini
  sudo docker exec otsai-server ollama pull llama3.2:3b
  sudo docker exec otsai-server ollama pull nomic-embed-text
  sudo docker exec otsai-server ollama pull qwen2.5-coder:7b
  sudo docker exec otsai-server ollama pull llama3.1:8b
  sudo docker exec otsai-server ollama pull deepseek-r1:7b
  sudo docker exec otsai-server ollama pull mistral:7b
  sudo docker exec otsai-server ollama pull qwen2.5:7b
  ```

  ## Model management
  ```bash
  # List loaded/available models
  sudo docker exec otsai-server ollama list

  # Remove models you no longer use
  sudo docker exec otsai-server ollama rm <model-name>

  # Check model info
  sudo docker exec otsai-server ollama show qwen2.5-coder:7b

  # API health check
  curl http://10.0.1.15:11434/api/tags
  ```

======================================================================
PHASE 8 — .ENV.EXAMPLE UPDATE
======================================================================

Update stacks/ollama/.env.example with new tunables:

  # Stack: ollama (otsai-server + otsai-webui)
  # DS723+ hardware: AMD Ryzen R1600, 2 cores, 32 GB RAM, no GPU.
  # CPU-only inference. See docs/tasks/OLLAMA_MODEL_SELECTION_DS723.md
  # for model recommendations and pull commands.

  TZ=America/New_York

  # Parallel requests — keep at 1 for CPU-only inference
  # Increasing to 2 allows concurrent requests but halves per-request speed
  OLLAMA_NUM_PARALLEL=1

  # Max models in memory simultaneously — 1 for CPU to avoid swapping
  OLLAMA_MAX_LOADED_MODELS=1

  # Model idle timeout before unloading
  # 30m: good trade-off for interactive sessions
  # -1:  keep loaded indefinitely (use if only one model ever runs)
  # 5m:  conserve RAM between infrequent sessions
  OLLAMA_KEEP_ALIVE=30m

  # Flash attention reduces KV cache memory for long contexts (recommended)
  OLLAMA_FLASH_ATTENTION=1

  # Open-WebUI default model dropdown (does not auto-pull — pull manually)
  DEFAULT_MODELS=phi4:mini,qwen2.5-coder:7b,nomic-embed-text

  # Override if HAProxy frontend hostname changes
  WEBUI_URL=https://ai.otsorundscore.olutechsys.com

  # Host bind-mount root (init-nas.sh sets this on the NAS)
  STACK_ROOT=/volume1/docker/dockge/stacks
  PUID=0
  PGID=0

======================================================================
PHASE 9 — VALIDATION
======================================================================

  scripts/compose-validate.sh
  Expected: All compose files validated OK.

  docker compose -f stacks/ollama/compose.yaml config > /dev/null && echo PASS
  Expected: PASS (env warnings acceptable)

  # Verify mem_limit was raised
  grep "mem_limit" stacks/ollama/compose.yaml
  Expected: 16g (not 8g)

  # Verify OLLAMA_KEEP_ALIVE is present
  grep "OLLAMA_KEEP_ALIVE" stacks/ollama/compose.yaml
  Expected: match

  # Verify OLLAMA_FLASH_ATTENTION is present
  grep "OLLAMA_FLASH_ATTENTION" stacks/ollama/compose.yaml
  Expected: match

  pre-commit run --files \
    stacks/ollama/compose.yaml \
    stacks/ollama/.env.example \
    stacks/ollama/README.md
  Expected: all hooks pass

  git add \
    stacks/ollama/compose.yaml \
    stacks/ollama/.env.example \
    stacks/ollama/README.md
  git commit -m \
    "feat(ollama): DS723+ model guide — qwen2.5-coder:7b + llama3.1:8b + \
deepseek-r1:7b + mistral:7b, raise mem_limit 8g→16g, add KEEP_ALIVE/FLASH_ATTENTION"
  git push

======================================================================
PHASE 10 — NAS DEPLOYMENT SEQUENCE (OPERATOR MANUAL STEPS)
======================================================================

These steps are run MANUALLY on the NAS after the git push lands.

  ### Step 1 — Pull changes
  cd /volume1/docker/dockge
  git pull --no-rebase

  ### Step 2 — Recreate ollama with new settings
  sudo docker compose -f stacks/ollama/compose.yaml down
  sudo docker compose -f stacks/ollama/compose.yaml up -d

  ### Step 3 — Wait for healthy status (60s for open-webui to initialise)
  sleep 30 && sudo docker ps --filter name=otsai --format \
    'table {{.Names}}\t{{.Status}}'

  ### Step 4 — Pull models in priority order
  # Start with small models; each takes 30s-5min depending on size

  # Always-available baseline (pull these first)
  sudo docker exec otsai-server ollama pull phi4:mini
  sudo docker exec otsai-server ollama pull nomic-embed-text
  sudo docker exec otsai-server ollama pull llama3.2:3b

  # Primary coding + research models
  sudo docker exec otsai-server ollama pull qwen2.5-coder:7b
  sudo docker exec otsai-server ollama pull llama3.1:8b

  # Secondary models (pull in background — will take time)
  sudo docker exec otsai-server ollama pull deepseek-r1:7b
  sudo docker exec otsai-server ollama pull mistral:7b
  sudo docker exec otsai-server ollama pull qwen2.5:7b

  ### Step 5 — Verify all models loaded
  sudo docker exec otsai-server ollama list

  ### Step 6 — Configure AnythingLLM embeddings
  # Open http://10.0.1.15:3002
  # Settings → Embedding Provider → Ollama → nomic-embed-text

  ### Step 7 — Test via API
  curl http://10.0.1.15:11434/api/tags | python3 -m json.tool
  # Expected: JSON listing all pulled models

  ### Step 8 — Optional: test a model
  curl -s http://10.0.1.15:11434/api/generate \
    -d '{"model":"qwen2.5-coder:7b","prompt":"Write a bash one-liner to show disk usage by directory","stream":false}' \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['response'])"

======================================================================
PHASE 11 — COMPOUND MEMORY UPDATE
======================================================================

/compound-learning

Add to AGENTS.md ## What Works:

  [2026-05-08] Ollama DS723+ model selection:
  - Hardware: AMD Ryzen R1600 (2 cores), 32GB RAM, CPU-only, no GPU
  - mem_limit raised 8g→16g (was too conservative; allows 14B models)
  - OLLAMA_FLASH_ATTENTION=1 reduces KV cache memory (always enable CPU)
  - OLLAMA_KEEP_ALIVE=30m (default 5m is too short for CPU reload latency)
  - ollama/ollama:0.22.0 is outdated — update to current stable
  - Speed rule: 7B Q4 ≈ 3-7 t/s, 14B Q4 ≈ 1-3 t/s, 32B Q4 < 1 t/s
  - Never pull 70B+ models — OOM on 32GB with other stacks running
  - nomic-embed-text: REQUIRED for AnythingLLM embeddings — pull first
  - Best coding model: qwen2.5-coder:7b (outperforms all 7B coders in 2026)
  - Best general: llama3.1:8b (research, devops, documentation)
  - Best reasoning: deepseek-r1:7b (chain-of-thought, shows thinking steps)
  - Best fast: phi4:mini (default, ~2.5GB, 8-15 t/s on R1600)
  - Linux/DevOps: mistral:7b (fastest structured output for commands)
  - DEFAULT_MODELS env var: sets open-webui dropdown, does NOT auto-pull
  - Pull commands need: sudo docker exec otsai-server ollama pull <model>

======================================================================
FINAL PRINT
======================================================================

OLLAMA-MODEL-SELECTION-DS723: COMPLETE
