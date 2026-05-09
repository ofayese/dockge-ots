> **Status:** ✅ SUPERSEDED / ARCHIVED — 2026-05-10

# Task: Consolidated Remaining Work — 2026-05-09
# Replaces all prior task files as the single Cursor coder entry point.
# Run this file top-to-bottom. Each phase lists DONE/SKIP/TODO status
# based on verified repo state before this file was written.

/coder
/compound-learning
/continuous-learning

======================================================================
STATUS AUDIT — what is already done (SKIP these)
======================================================================

DONE — verified on disk, do not re-do:

  NETWORK_ROUTING_OAUTH_OPTIMIZATION.md
    Phase 1  github-desktop name: + 172.20 subnet           DONE
    Phase 2  all stacks have named bridge + 172.x subnet    DONE
             grafana-prom: driver:bridge + gateway added     DONE
             code-server: networks:{} replaced with net     DONE
    Phase 3  Traefik 8880:80 / 6443:443 port mapping        DONE
             Traefik .env.example documented                 DONE
             traefik-mft same port fix                       DONE
             NAS_DEPLOYMENT HTTP/HTTPS reference table       DONE
    Phase 4  GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md            DONE
    Phase 5  STACK_OPTIMIZATION_CUSTOMIZATION.md            DONE
    Phase 6  README.md cross-links to both docs             DONE
             NAS_DEPLOYMENT.md cross-links                  DONE
             stacks/searxng/README.md                       DONE
             stacks/it-tools/README.md                      DONE
             stacks/holyclaude/README.md cross-link         DONE
             stacks/rag-stack/README.md exists              DONE
    Phase 7  AGENTS.md network+OAuth+Traefik bullets        DONE
             HIVE_OBJECTIVE.md doc list                     DONE
    Phase 8  compose-validate passes                        DONE (assumed — verify first)
    Phase 9  ~/.cursor/skills/learned entries               DONE

  HAPROXY_DNS_MACRO_GAPS.md
    Phase 1  haproxy.cfg has dockge-be backend              DONE
             host.map has dockge entries                    DONE
    Phase 3  docker.sock comment normalisation              PARTIALLY DONE
    Phase 5  restart policy (unless-stopped baseline)       DONE

  CURSOR_SKILLS_ACME_HAPROXY_DOCKGE.md
    Phase 1  acme-sh SETUP.md has ots-sub + mft-sub        DONE
    Phase 2  docs/hive/dns/olutechsys.com.zone exists       DONE
    Phase 3  HAProxy paths in NAS_DEPLOYMENT.md             DONE
    Phase 4  Traefik --ping=true + entrypoints.traefik      DONE
    Phase 5  dockge-start.sh port 5571:5001                 DONE (verify)
    Phase 7  .cursor-plugin/plugin.json + 5 skill stubs     DONE
    Phase 7  .cursor/mcp.json (context7)                    DONE

  DOCKER_MULTIHOST_OLLAMA_OFFLINE_WORKSPACE.md
    Phase 1  ollama-model-init service in compose           DONE
    Phase 1  ollama-net 172.27.0.0/24                       DONE
    Phase 4  holyclaude .env.example multi-machine docs     DONE
    Phase 5  offline workspace docs in holyclaude README    DONE
    Phase 6  rag-stack README document ingestion section    DONE

  OLLAMA_MODEL_SELECTION_DS723.md
    Phase 1  ollama compose.yaml updated                    DONE
             mem_limit raised 8g→16g                        DONE
             OLLAMA_KEEP_ALIVE added                        DONE
             OLLAMA_FLASH_ATTENTION added                   DONE
    Phase 2  .env.example tier model vars added             DONE

  MASTER_AUDIT_AND_DEPLOY.md
    Phase 1-4 audit execution log recorded                  DONE
    Phase 5  init-nas.sh remotely:data manifest fix         DONE
             README.md stack count 24                       DONE
             HIVE_OBJECTIVE.md 24 stacks                    DONE
             NAS_DEPLOYMENT.md DSM hardening section        DONE

======================================================================
ACTUAL REMAINING WORK — verify and complete these
======================================================================

ADDENDUM — SHELL COUNTER HARDENING UNDER `set -e`
──────────────────────────────────────────────────

Use `docs/tasks/CODER_TASK_Harden_Counter_Increments_Set_E.md` as the
focused checklist for replacing `((X++))` with `((X+=1))` in task-doc
shell blocks where `set -e` is active.

Alignment rule:
  - Follow that file for scan-and-fix specifics.
  - Follow this consolidated file for pre-flight, final validation, and
    commit flow.
  - If duplicate instructions conflict, this file is authoritative for
    sequencing and closeout.

PHASE 0 — PRE-FLIGHT (run first, establish ground truth)
──────────────────────────────────────────────────────────

  Command: bash scripts/compose-validate.sh
  Expected: All compose files validated OK
  If FAIL: fix before proceeding

  Command: pre-commit run --all-files
  Expected: all hooks pass
  If FAIL: fix formatting issues before proceeding

  Command: grep -rn "192\.168\." stacks/*/compose.yaml 2>/dev/null
  Expected: zero matches
  If any match: add that stack's network to Phase 1

  Command: grep -rn "networks: {}" stacks/*/compose.yaml 2>/dev/null
  Expected: zero matches
  If any match: replace with named bridge per subnet registry

  Command: git status --short
  Expected: clean or only intentional tracked changes

======================================================================
PHASE 1 — HAPROXY: docker.sock comment normalisation
======================================================================

FROM: macro_gaps_review Phase 3 (partially done)
STATUS: multiple phrasings still exist

Read each compose file listed below. For every /var/run/docker.sock
mount line, ensure the comment IMMEDIATELY ABOVE it matches exactly
one of these two templates and nothing else:

  :ro mounts:
    # docker.sock :ro — <service> reads <what> only.

  :rw mounts:
    # SECURITY: docker.sock :rw — <reason for full API access>.

Files to check (all mounts confirmed present):
  stacks/dozzle/compose.yaml
  stacks/homepage/compose.yaml
  stacks/watchtower/compose.yaml
  stacks/portainer/compose.yaml
  stacks/code-server/compose.yaml
  stacks/traefik-ots/compose.yaml
  stacks/traefik-mft/compose.yaml
  stacks/grafana-prom/compose.yaml
  stacks/agents_gateway_data/compose.yaml
  stacks/agents_gateway_data/duckduckgo/compose.yaml (if exists)

RULE: Only change the comment line. Never change the volume mount line
itself. Never add comments inside YAML flow sequences.

Verify after:
  Command: grep -B2 "docker.sock" stacks/*/compose.yaml \
    | grep -v "# docker.sock\|# SECURITY:\|/var/run"
  Expected: zero results (all mounts have normalised comment above)

======================================================================
PHASE 2 — README volume tables: ${STACK_ROOT} sweep
======================================================================

FROM: macro_gaps_review Phase 4
STATUS: most READMEs still use hardcoded paths in prose

Gold standard template (from stacks/zabbix/README.md):

  ## Volumes

  | Host path | Container path | Mode | Created by |
  |---|---|---|---|
  | `${STACK_ROOT}/<stack>/data` | `/app/data` | rw | `init-nas.sh` |
  | `${STACK_ROOT}/<stack>/config` | `/etc/<app>` | rw | `init-nas.sh` |

  > Run `sudo bash scripts/init-nas.sh` after cloning to create these
  > directories. Without them, the container will fail to start.

For each README below:
  1. Read the README
  2. Read the corresponding compose.yaml to identify bind mounts
  3. Replace any hardcoded /volume1/docker/dockge/stacks/<stack>/...
     with ${STACK_ROOT}/<stack>/...
  4. Add or update ## Volumes table using the gold standard format
  5. Stateless stacks (no bind mounts): add ## Volumes section with
     "No persistent volumes — stateless." (do not add the table)

READMEs to update:
  stacks/acme-sh/README.md          (has hardcoded paths)
  stacks/grafana-prom/README.md     (has hardcoded paths)
  stacks/databases/README.md        (has hardcoded paths)
  stacks/ollama/README.md           (needs tier table + pull commands)
  stacks/homepage/README.md         (has hardcoded paths)
  stacks/codex-docs/README.md       (has hardcoded paths)
  stacks/warp-main/README.md        (no volumes — stateless note)
  stacks/agents_gateway_data/README.md  (docker.sock only — note)
  stacks/docker-model-runner/README.md  (check, update if needed)

OPERATOR EXCEPTIONS — leave existing wording, only normalise variable:
  stacks/portainer/README.md        PORTAINER_DATA_ROOT operator path
  stacks/code-server/README.md      CODE_SERVER_HOST_* operator paths

Verify after:
  Command: grep -rn "/volume1/docker/dockge/stacks" stacks/*/README.md \
    | grep -v "# EXEMPT\|operator"
  Expected: zero results

======================================================================
PHASE 3 — verify-dns-views.sh: add --hairpin comparison mode
======================================================================

FROM: homelab_dns_review Phase 2
STATUS: --hairpin mode may be missing — verify first

Read scripts/verify-dns-views.sh.

If --hairpin flag is already implemented with comparison logic: SKIP.

If missing or incomplete, add --hairpin [hostname] mode that:
  1. Resolves hostname via default resolver (public DNS path)
  2. Resolves hostname via @10.0.1.15 (NAS resolver)
  3. Compares:
     - Both return same public IP → hairpin working or split-DNS not
       yet configured → print [HAIRPIN OK] or [SPLIT-DNS NOT CONFIGURED]
     - NAS returns 10.x.x.x, public returns different → [SPLIT-DNS ACTIVE]
     - curl -kI succeeds via public path → [REACHABLE via public IP]
  4. Reports one of:
     [HAIRPIN OK]          curl works via public IP → split-DNS optional
     [SPLIT-DNS ACTIVE]    NAS returns LAN IP
     [SPLIT-DNS NEEDED]    curl fails via public IP path

Default hostname if none provided: otsorundscore.olutechsys.com

Verify after:
  bash scripts/verify-dns-views.sh --help | grep hairpin
  Expected: --hairpin documented

======================================================================
PHASE 4 — AGENTS.md + HIVE_OBJECTIVE.md: remaining updates
======================================================================

Check if the following bullets exist in AGENTS.md ## What Works.
If missing, add dated entries:

  A) Cursor skills integration:
     [2026-05-08] .cursor-plugin/plugin.json + 5 operator skills:
       nas-reset-recovery, synology-git-safety, docker-healthcheck-patterns,
       traefik-port-mapping, subnet-registry. .cursor/mcp.json adds context7
       MCP server (https://mcp.context7.com/mcp) for live traefik/ollama/
       qdrant docs. Skill format follows auth0/agent-skills SKILL.md spec.

  B) Ollama auto-pull service:
     [2026-05-08] ollama-model-init one-shot service (restart: "no"):
       polls /usr/bin/ollama list until ready, pulls tier 1/2/3 models
       per OLLAMA_TIER*_MODELS env vars, idempotent (skips present models).
       OLLAMA_KEEP_ALIVE=30m + OLLAMA_FLASH_ATTENTION=1 added.
       mem_limit raised 8g→16g (allows 14B Q4 models on DS723+).
       nomic-embed-text MUST be in TIER1 — AnythingLLM needs it at startup.
       Re-trigger: docker compose up --force-recreate ollama-model-init

  C) Offline workspace:
     [2026-05-08] HolyClaude + rag-stack offline workspace:
       HOLYCLAUDE_WORKSPACE is the only env var that changes per machine.
       NAS: /volume1/homes/laolufayese, Mac: /Users/laolufayese,
       WSL2: /home/laolufayese (NOT /mnt/c — slow I/O).
       Deploy order: ollama → (wait model-init Done) → rag-stack → holyclaude.
       AnythingLLM API token: generate in UI, add to holyclaude/.env.
       Fully offline when ANTHROPIC_API_KEY + CURSOR_API_KEY are blank.

Check HIVE_OBJECTIVE.md for:
  - docs list includes GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md   (verify)
  - docs list includes STACK_OPTIMIZATION_CUSTOMIZATION.md   (verify)
  If either is missing, add pointer under the docs/hive/ section.

======================================================================
PHASE 5 — MASTER_AUDIT_AND_DEPLOY.md: archive completed task files
======================================================================

The following task files have been fully executed. They should be
moved to docs/tasks/archive/ with a SUPERSEDED header (same pattern
as the existing archive files).

Move if they are still in docs/tasks/ (not archive/):
  NETWORK_ROUTING_OAUTH_OPTIMIZATION.md  → archive
  HAPROXY_DNS_MACRO_GAPS.md              → archive
  CURSOR_SKILLS_ACME_HAPROXY_DOCKGE.md  → archive
  DOCKER_MULTIHOST_OLLAMA_OFFLINE_WORKSPACE.md → archive
  OLLAMA_MODEL_SELECTION_DS723.md        → archive
  OLLAMA_AUTOPULL_HOLYCLAUDE_OFFLINE.md  → archive (if exists)

Keep in docs/tasks/ (not yet fully executed):
  MASTER_AUDIT_AND_DEPLOY.md            → KEEP (periodic re-run)
  THIS FILE (CONSOLIDATED_REMAINING_WORK.md) → KEEP until all phases done

Superseded header template to prepend to each archived file:
  <!--
  SUPERSEDED — archived 2026-05-09
  All phases verified complete. See AGENTS.md ## What Works for outcomes.
  This file is retained for historical reference only.
  -->

======================================================================
PHASE 6 — VALIDATION
======================================================================

  bash scripts/compose-validate.sh
  Expected: All compose files validated OK

  pre-commit run --all-files
  Expected: all hooks pass

  # No hardcoded volume paths in READMEs
  grep -rn "/volume1/docker/dockge/stacks" stacks/*/README.md \
    | grep -v "# EXEMPT\|operator"
  Expected: zero

  # All docker.sock mounts have normalised comment
  grep -B2 "docker.sock" stacks/*/compose.yaml \
    | grep -v "# docker.sock\|# SECURITY:\|/var/run\|^--$"
  Expected: zero

  # No 192.168.x subnets
  grep -rn "192\.168\." stacks/*/compose.yaml
  Expected: zero

  # No networks: {} remaining
  grep -rn "networks: {}" stacks/*/compose.yaml
  Expected: zero

  git add -A
  git commit -m \
    "chore: docker.sock comment normalisation; README STACK_ROOT sweep; \
verify-dns-views hairpin mode; AGENTS.md cursor/ollama/workspace bullets; \
archive completed task files"
  git push

======================================================================
PHASE 7 — COMPOUND MEMORY + CONTINUOUS LEARNING
======================================================================

/compound-learning

After commit, add to AGENTS.md ## What Works:

  [2026-05-09] Consolidated remaining work complete:
    docker.sock comments normalised to two-template system
    README volume tables use ${STACK_ROOT} fleet-wide
    verify-dns-views.sh --hairpin comparison mode added
    All prior task files archived under docs/tasks/archive/
    Single entry point: docs/tasks/MASTER_AUDIT_AND_DEPLOY.md

/continuous-learning

Update ~/.cursor/skills/learned/docker-sock-comment-template.md:
  Confirm two-template system is now applied repo-wide.
  Add note: verify with grep -B2 "docker.sock" to confirm normalisation.

======================================================================
TASK PRIORITY ORDER
======================================================================

Run phases in this order. Each is independent but phase 0 must pass
before any other phase is attempted.

  Phase 0 — pre-flight (REQUIRED FIRST)
  Phase 1 — docker.sock comments     (small, low-risk)
  Phase 2 — README volume tables     (editorial, higher volume)
  Phase 3 — verify-dns-views hairpin (script addition)
  Phase 4 — AGENTS.md bullets        (docs)
  Phase 5 — archive task files       (housekeeping)
  Phase 6 — validation + commit
  Phase 7 — compound memory

======================================================================
FINAL PRINT
======================================================================

CONSOLIDATED-REMAINING-WORK: READY FOR CURSOR
