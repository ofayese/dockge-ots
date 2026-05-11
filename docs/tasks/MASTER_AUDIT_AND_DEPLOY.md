# Task: Master Audit + Deploy — Full Stack
# Version: 2026-05-10-b (26 stacks incl. synology-api-bridge; host-named TLS; doc clarity — readiness list = review cycle, not open blockers)

/coder
/compound-learning
/continuous-learning

======================================================================
CONTEXT
======================================================================

This master task consolidates prior task files into one repeatable flow.

**Recent in-tree completions (2026-05-09):** **`psu-ots`** stack + **`STACK_MANIFEST`** entry **`psu-ots:data`**; host-named TLS/DNS model (**`otsorundscore/`** + **`misfitsds/`** PEM dirs, no new **`*.ots.olutechsys.com`** / **`*.mft.olutechsys.com`** in **`stacks/`** compose); consolidation sprint (**`docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md`**) — critical **`scripts/*.sh`** hardening, **`docker.sock`** comment normalization, README **`${STACK_ROOT}`** tables, **`scripts/verify-dns-views.sh --hairpin`**. Canonical phased PSU/cert gates: **`docs/tasks/PSU_OTS_AND_CERT_MIGRATION_MACRO.md`** + **`AGENTS.md`** What Works.

**Detailed review updates (2026-05-09-b):** Pre-flight hardening gate added; Phase 2 per-stack table template with weighted readiness categories expanded; Phase 3 healthcheck anti-patterns extended with image-specific probe expectations; Phase 4 add **`dozzle`** healthcheck check (flagging **`--version`** anti-pattern); Phase 6 deploy order and post-deploy steps annotated with critical hold points (particularly Traefik cert dependency and remotely WebSocket DSM rule); Phase 7 validation extended with image-level healthcheck verify commands (`docker run --entrypoint`); Phase 8 compound-learning extended with Zabbix SNMP v3 config pattern, dozzle healthcheck fix pattern, code-server secrets handling, and mTLS/certificate pinning patterns; Phase 9 continuous-learning added API key rotation (Dockge, PSU webhooks, Watchtower); rollback section expanded with per-service recovery steps and data recovery patterns.

  docs/tasks/archive/HEALTHCHECK_FIXES.md
  docs/tasks/archive/NEXT_PHASE_2026_05_07.md
  docs/tasks/archive/OCI_HEALTHCHECK_AUDIT.md
  docs/tasks/archive/README_CREATION.md
  docs/tasks/archive/REPO_REVIEW.md
  docs/tasks/archive/REPO_REVIEW_2026_05_07.md

Execution mode is HYBRID:
  - Agent executes repo-side audits, checks, and doc updates.
  - Operator runs NAS deployment commands from this runbook.

Use this as the default task for repository readiness + full-stack deploy.
Update the version date at the top when making structural changes.

NOTE: This task uses rg (ripgrep) for search commands. On environments
without rg, substitute grep -r / grep -rn equivalents.

======================================================================
PHASE 0 — PRE-FLIGHT READS (REQUIRED)
======================================================================

Read first — do not skip any:

  AGENTS.md
  CLAUDE.md
  HIVE_OBJECTIVE.md
  README.md
  docs/hive/NAS_DEPLOYMENT.md
  docs/hive/CERT_REISSUE_TRAEFIK_OAUTH_RUNBOOK.md
  .gitignore
  scripts/init-nas.sh
  scripts/dockge-start.sh
  scripts/compose-validate.sh
  scripts/fix-permissions.sh
  scripts/verify-repo-layout.sh
  scripts/audit-healthcheck-tools.sh
  scripts/restore-env.sh
  stacks/github-desktop/compose.yaml       (KasmVNC/Electron baseline)
  stacks/databases/.gitignore              (stack-level db protection)
  stacks/remotely/compose.yaml             (WebSocket stack baseline)
  stacks/dozzle/compose.yaml               (logging aggregator — healthcheck model)
  stacks/traefik-ots/compose.yaml          (Traefik baseline + docker.sock comment)
  stacks/psu-ots/compose.yaml              (PowerShell Universal NOC model)

Confirm hard constraints before any edit:

  - Canonical stack root: ${STACK_ROOT} -> /volume1/docker/dockge/stacks
  - No depends_on.condition in tracked stacks (Synology compose compat)
  - Dockge host mapping is 5571:5001 (NOT 5571:5571)
  - No secret material in git (secrets/, id_ed25519, populated .env)
  - No DB/data files in git (db/, data/, *.db, WAL files)
  - No broad staging from NAS (git add -A and git add . are FORBIDDEN on NAS)
  - TZ default must be America/New_York (not Europe/London)
  - All stacks use compose.yaml (not docker-compose.yml) where possible
  - Boolean env vars: use 1/0 not true/false (some DSM compose versions reject booleans)
  - WebSocket stacks: document in README that DSM reverse proxy needs WebSocket headers
  - Docker network subnets must not overlap:
      172.17.0.0/16  = Docker default bridge (reserved)
      172.20.0.0/24  = github-desktop
      172.22.0.0/24  = grafana-net
      172.22.1.0/24  = prometheus-net
      Next available  = 172.22.2.0/24+
  - Post-deploy verify: healthcheck state (no unhealthy containers), Dozzle log visibility, Traefik backend status
  - Blocking issues during deploy: missing .env secrets, incorrect Dockge port binding, acme-sh certs not issued before Traefik start
  - Rollback safeguard: `docker compose down` preserves data in STACK_ROOT; full NAS reset uses archive backup

======================================================================
PHASE 0.5 — PRE-FLIGHT HARDENING GATE (AGENT + OPERATOR)
======================================================================

Run before Phase 1 to catch operational misconfigurations:

### Operator pre-flight (run once before any NAS reset)

  1. Verify SSH key:
     ssh -T git@github.com
     # Expected: Hi ofayese/dockge-ots! You've successfully authenticated...

  2. Verify GitHub branch access:
     git branch -r
     # Expected: origin/main visible, no detached HEAD warnings

  3. Verify local git status clean:
     git status
     # Expected: working tree clean, no staged changes

  4. Verify DSM connectivity:
     ping -c 1 10.0.1.15
     # Expected: ICMP replies from OTS NAS

  5. Verify Synology Container Manager installed on NAS:
     ssh laolufayese@10.0.1.15 'docker version' 2>/dev/null | head -3
     # Expected: Docker version output (confirms Container Manager is running)

### Agent pre-flight (repo baseline)

  1. Stack count and manifest match:
     ls stacks/ | grep -v '^_' | wc -l
     # Expected: 26
     ls stacks/ | grep -v '^_' | sort
     # Compare names to HIVE_OBJECTIVE.md “Stack folders” row (includes synology-api-bridge, docker-model-runner, etc.).
     # Supply-chain / IAM (macro): image digests per `docs/hive/COMPOSE_IMAGE_PIN_POLICY.md` (no cross-namespace `sha256:` reuse).
     # OIDC Path B: read `docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md` Path A vs Path B before mixing Google (DSM) with SSO Server clients for psu-ots / open-webui / Portainer.

  2. No untracked files in repo root (except .env files):
     git status --short | grep -v '\.env' | head -5
     # Expected: zero or only .env/.env.example diffs

  3. Compose files validate:
     bash scripts/compose-validate.sh
     # Expected: exit 0

  4. Shell scripts have no obvious issues:
     shellcheck -x scripts/*.sh 2>&1 | head -10
     # Expected: zero findings (post-consolidation baseline)

  5. Pre-commit hooks are installed:
     pre-commit --version
     # Expected: pre-commit <version>

======================================================================
PHASE 1 — REPO AUDIT GATES (AGENT)
======================================================================

Run and record PASS / FAIL / NOTE for each gate.

### Gate 1: Stack count and manifest parity

  Stack count is **26** ( **`remotely`** added 2026-05-08; **`psu-ots`** added 2026-05-09; **`synology-api-bridge`** added 2026-05-10 ).
  **`HIVE_OBJECTIVE.md`** must show **26** stack folders and **`--count 26`** spawn string.

  Command:
    ls stacks/ | grep -v '^_' | wc -l
    diff \
      <(grep -E '^\s*"[^"]+:' scripts/init-nas.sh \
        | sed -E 's/^[[:space:]]*"([^"]+):.*/\1/' | sort -u) \
      <(ls stacks/ \
        | grep -vE '^portainer$|^agents_gateway_data$|^it-tools$|\
^mcp-tools-config$|^openresume$|^warp-main$|^watchtower$|^docker-model-runner$' \
        | sort -u)

  Expected:
    - stack count **26**
    - manifest diff empty ( **`STACK_MANIFEST`** includes **`remotely:data`** and **`psu-ots:data`** among others — see **`scripts/init-nas.sh`** )

### Gate 2: Layout hygiene

  Command: bash scripts/verify-repo-layout.sh
  Expected: passes — no root-level hive/, no duplicate stack folders

### Gate 3: Key docs and stack artifacts exist

  Command:
    ls README.md
    ls stacks/rag-stack/compose.yaml \
       stacks/rag-stack/README.md \
       stacks/rag-stack/.env.example
    ls stacks/remotely/compose.yaml \
       stacks/remotely/README.md \
       stacks/remotely/.env.example \
       stacks/remotely/.gitignore
    ls stacks/psu-ots/compose.yaml \
       stacks/psu-ots/README.md \
       stacks/psu-ots/.env.example
    ls docs/tasks/MASTER_AUDIT_AND_DEPLOY.md

### Gate 4: Dockge port mapping correctness

  Command:
    grep -n "5571\|5001" README.md \
      docs/hive/NAS_DEPLOYMENT.md \
      scripts/dockge-start.sh

  Expected: documented as host 5571 -> container 5001 everywhere.
  FAIL if any file shows 5571:5571.

### Gate 5: NAS git safety documented

  Command:
    grep -l "@eaDir\|git.pull.nas\|no-rebase" \
      AGENTS.md docs/hive/NAS_DEPLOYMENT.md

  Expected:
    - @eaDir corruption fix documented
    - DSM indexing permanent fix documented (Control Panel -> Search)
    - git pull on NAS uses --no-rebase
    - git-pull-nas alias uses underscore function name + hyphen alias
      (DSM ash/POSIX mode rejects hyphens in function names)

### Gate 6: Secrets and runtime noise not tracked

  Command:
    git ls-files | grep -E "secrets/|id_ed25519|\.env$|\.DS_Store|\
\.claude-flow|node_modules|/db/|/data/|\.db$|pg_wal|pg_xlog"

  Expected: zero results.
  FAIL if any match — these must be untracked and gitignored.

### Gate 7: Stack-level .gitignore files protect database stacks

  Command:
    ls stacks/databases/.gitignore \
       stacks/zabbix/.gitignore \
       stacks/ollama/.gitignore \
       stacks/rag-stack/.gitignore \
       stacks/remotely/.gitignore \
       stacks/psu-ots/.gitignore

  Expected: all six exist ( **`psu-ots`** ignores runtime **`data/*`** except **`data/Repository/`** ).

### Gate 8: No docker-compose.yml files in stacks that should use compose.yaml

  Command:
    find stacks -name "docker-compose.yml" -not -path "*warp-main*"

  Expected: zero results (warp-main is the only permitted exception).

### Gate 9: TZ defaults are correct

  Command:
    grep -rn "Europe/London" stacks/

  Expected: zero results.

### Gate 10: Network subnets do not conflict

  Command:
    grep -rn "subnet:" stacks/*/compose.yaml \
      stacks/*/docker-compose.yml 2>/dev/null

  Expected: only 172.20.x, 172.22.x ranges visible.

### Gate 11: Router cert expiry documented

  Command:
    grep -l "batcavegtaxe16k\|2025.*6.*6\|router.*cert" \
      docs/hive/NAS_DEPLOYMENT.md AGENTS.md

### Gate 12: nas-reset.sh and restore-env.sh exist

  Command: ls scripts/restore-env.sh
  Expected: exists.

### Gate 13: WebSocket stacks document the DSM reverse proxy requirement

  Command:
    grep -l "WebSocket\|websocket" stacks/remotely/README.md

  Expected: remotely README documents WebSocket requirement.
  NOTE: Any other stack that uses WebSocket (Portainer, holyclaude, etc.)
  should also document this in its README.

### Gate 14: Boolean env vars use 1/0 not true/false

  Command:
    grep -rn "=true\b\|=false\b" stacks/*/compose.yaml \
      stacks/*/docker-compose.yml 2>/dev/null \
      | grep -v "^.*#"

  Expected: zero results (some DSM compose versions reject boolean literals).
  FAIL if any unquoted true/false appears in environment values.
  Exception: YAML booleans in non-environment contexts (restart: "no") are fine.

======================================================================
PHASE 2 — PER-STACK READINESS AUDIT (AGENT)
======================================================================

For each stack under stacks/ (excluding _haproxy), audit every service:

  - security_opt: present or documented exception
  - restart: policy present
  - healthcheck: present or explicit exemption reason in compose
  - logging: json-file with max-size/max-file
  - TZ: present where environment block is used (value must be America/New_York)
  - watchtower label: com.centurylinklabs.watchtower.enable=true
  - image pin: digest, semver, or documented floating-tag exception
  - mem_limit + cpu_shares: present with one-line rationale
  - README.md: exists in stack folder
  - .env.example: exists
  - stack-level .gitignore: required for database/data-heavy stacks
  - WebSocket: documented in README if stack uses SignalR/WebSocket

Output a table with weighted readiness scoring:

  | stack | healthcheck | logging | image-pin | readme | env-example | gitignore | websocket-doc | tier | deploy-ready |

READINESS TIERS (assign one per stack):
  - TIER A (ready): all baseline items present, no floating-tag exceptions, no TZ gaps
  - TIER B (staged): healthcheck or logging gaps present but documented, OR floating-tag exception with rationale in README
  - TIER C (blocked): TZ missing on multi-env service, OR image-pin critical gap (missing digest/semver), OR missing .gitignore on data stacks
  - TIER X (exempt): one-shot / placeholder stacks (mcp-tools-config) with documented exemption

Image-pin and doc hygiene review cycle (re-verify on each fleet audit — not “mystery blockers” if compose already pins):
  - **codex-docs / docker-model-runner / agents_gateway_data:** keep digests or semver aligned with **`docs/hive/COMPOSE_IMAGE_PIN_POLICY.md`**; refresh digests after upstream security advisories.
  - **openresume:** digest-pinned (`yuihtt/open-resume@sha256:...`) — never reuse a digest from another Hub namespace; re-pin with `docker pull` + `inspect` on the **exact** reference.
  - **watchtower:** compose uses **`containrrr/watchtower:1.7.1`**; real **`WATCHTOWER_NOTIFICATION_URL`** (e.g. Shoutrrr Discord) lives only in gitignored **`stacks/watchtower/.env`** — see tracked **`stacks/watchtower/.env.example`**.
  - **github-desktop / holyclaude / traefik-ots / traefik-mft / remotely:** digest- or semver-pinned in compose; scrub any external checklist that still claims `:latest` for these stacks.
  - **OIDC:** Path A (Google DSM login) vs Path B (Synology SSO Server for apps) — **`docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md`** + **`docs/Modern_Identity_Orchestration.md`**; scopes, username claims, redirect strictness, and **`Domain/LDAP/local`** are spelled out there — do not mix **OAuth Service** with **SSO Server** for Path B clients.

### Generate stacks readiness report

  For each stack folder, record:
    1. Tier assignment (A/B/C/X)
    2. Missing or exception items
    3. Blocker (if TIER C)
    4. Action (if TIER B/C — link to proposal or deploy gate)

  Example row:
    | holyclaude | ✓ | ✓ | digest-pinned (`coderluii/holyclaude@sha256:…`) | ✓ | ✓ | N/A | ✓ | A | Ready — treat README “dev image” note as operator intent, not a floating compose ref |

======================================================================
PHASE 3 — HEALTHCHECK AUDIT (AGENT + OPTIONAL NAS IMAGE PROBES)
======================================================================

Classify each healthcheck probe type:

  Type A: HTTP client (wget/curl) confirmed in image
  Type B: app/native binary probe
  Type C: TCP probe (nc, etc.)
  Type D: CMD-SHELL fallback (python/node/perl — image has shell)
  Type E: built-in health subcommand

Anti-pattern rules (FAIL if violated):
  - NEVER use --version or --help as liveness probe
  - NEVER assume wget in non-Alpine images without verification
  - NEVER use CMD-SHELL in shell-less/scratch images (watchtower)
  - NEVER use CMD-SHELL when CMD with full binary path is cleaner
  - NEVER use true/false as literal env var values in environment blocks
    (use 1/0 — some Synology compose versions reject YAML boolean literals)
  - NEVER use stale HTTP endpoint for health (e.g., /metrics or /admin — use /health, /ping, /readyz)

Mandatory checks — these have known correct forms:

  dozzle:
    MUST use: ["CMD", "/dozzle", "healthcheck"]
    NOT:      ["CMD", "/dozzle", "--version"]
    Anti-pattern flagged: dozzle prior healthchecks used --version (FIXED in 2026-05-08)
    Verify: grep -n "dozzle.*healthcheck" stacks/dozzle/compose.yaml

  portainer_agent:
    MUST have TCP probe (agent uses mTLS — HTTP probe fails):
    ["CMD-SHELL", "nc -z 127.0.0.1 9001 || exit 1"]

  searxng (main service, not redis):
    MUST have HTTP probe:
    ["CMD", "wget", "-qO-", "http://localhost:8080/healthz"]

  code-server DB:
    MUST suppress auth warnings:
    ["CMD-SHELL", "mysqladmin ping -h localhost --silent 2>/dev/null || exit 1"]

  watchtower:
    MUST use own binary (scratch image — no shell):
    ["CMD", "/watchtower", "--health-check"]

  ollama (otsai-server):
    MUST use CMD with full path — CMD-SHELL loses PATH in this image:
    ["CMD", "/usr/bin/ollama", "list"]

  rag-qdrant:
    MUST use nc (Rust image — no wget/curl):
    ["CMD", "/bin/sh", "-c",
     "printf 'GET /readyz HTTP/1.0\\r\\n\\r\\n' | nc 127.0.0.1 6333 | grep -q '200 OK'"]

  remotely:
    Type A — curl HTTP probe (ASP.NET Core Debian image ships curl):
    ["CMD", "curl", "-fs", "http://localhost:5000/"]

  traefik-ots/mft:
    MUST use: ["CMD", "traefik", "healthcheck", "--ping"]

  open-webui:
    Type A — curl (Python/FastAPI Debian base ships curl):
    ["CMD", "curl", "-fs", "http://localhost:8080/"]

  adminer:
    Type A — curl (Debian official base):
    ["CMD", "curl", "-fs", "http://localhost:8080/"]

Optional runtime tool audit:
  bash scripts/audit-healthcheck-tools.sh 2>&1 | tee /tmp/healthcheck-audit.txt

Per-image verification (if runtime access available):
  # Verify dozzle has healthcheck subcommand
  docker run --rm louislam/dozzle:latest /dozzle healthcheck || echo "FAILED"

  # Verify ollama preserves /usr/bin/ollama path
  docker run --rm ollama/ollama:latest /usr/bin/ollama list || echo "FAILED"

  # Verify qdrant has nc available
  docker run --rm eqria/qdrant:latest which nc || echo "NO nc — use HTTP GET probe instead"

======================================================================
PHASE 4 — CROSS-STACK CONSISTENCY CHECKS (AGENT)
======================================================================

Run each check and record result:

### Port conflict check

  Command: grep -rn "3001:\|5371:\|5000:" stacks/*/compose.yaml

  Expected:
    - holyclaude: 3001:3001 (primary, reserved)
    - rag-stack anythingllm: 3002:3001
    - remotely: 10.0.1.15:5371:5000 (no conflict — DSM uses 5000/5001 on host, not container)
  FAIL if any other stack maps host 3001 or 5371.

### dozzle healthcheck anti-pattern check

  Command:
    grep -n "dozzle" stacks/*/compose.yaml | grep -i healthcheck
    grep -A3 "healthcheck:" stacks/dozzle/compose.yaml | grep -i "dozzle"

  Expected: dozzle healthcheck uses `["CMD", "/dozzle", "healthcheck"]`
  FAIL if result contains --version or --help

### depends_on condition check

  Command: grep -rn "condition:" stacks/*/compose.yaml
  Expected: zero results.

### Boolean env var check

  Command:
    grep -rn ":[[:space:]]*true\b\|:[[:space:]]*false\b" \
      stacks/*/compose.yaml \
      | grep "environment" -A20 | grep -v "#"
  Expected: zero literal booleans in environment blocks.
  Fix: change true -> 1, false -> 0.

### Floating tag inventory

  Command:
    grep -rn ":latest" stacks/*/compose.yaml \
      stacks/*/docker-compose.yml 2>/dev/null

  For each result, confirm it is in the documented operator-pin exception list.

### Empty networks block

  Command: grep -rn "networks:\s*{}" stacks/*/compose.yaml
  Expected: zero results.

### Network subnet conflicts

  Command:
    grep -rn "subnet:" stacks/*/compose.yaml \
      stacks/*/docker-compose.yml 2>/dev/null

  Subnet registry:
    172.17.0.0/16  Docker default bridge — NEVER use
    172.20.0.0/24  github-desktop-net
    172.22.0.0/24  grafana-net
    172.22.1.0/24  prometheus-net
    next free: 172.22.2.0/24+

### TZ default correctness

  Command: grep -rn "Europe/London\|TZ:-Europe" stacks/
  Expected: zero results.

### KasmVNC/Electron hardening for github-desktop

  Verify in stacks/github-desktop/compose.yaml:
    - seccomp:unconfined present
    - IPC_LOCK in cap_add
    - no-new-privileges:true ABSENT (intentional)
    - no --no-sandbox anywhere
    - TZ uses America/New_York

### WebSocket stacks

  Verify that stacks using SignalR/WebSocket document the DSM reverse proxy
  requirement in their README. Current WebSocket stacks:
    - remotely (SignalR over WebSocket — required)
    - holyclaude (CloudCLI web UI — likely WebSocket)
  Check: grep -l "WebSocket\|websocket" stacks/remotely/README.md stacks/holyclaude/README.md

### DSM POSIX mode — bash function naming

  Command:
    grep -rn "git-pull-nas\|git_pull_nas" \
      AGENTS.md docs/hive/NAS_DEPLOYMENT.md

  Expected: both hyphen alias AND underscore function documented.

### sudo SSH key context

  Command:
    grep -n "GIT_SSH_COMMAND\|sudo.*git\|SSH_KEY" \
      docs/hive/NAS_DEPLOYMENT.md README.md

======================================================================
PHASE 5 — DOC GAP REMEDIATION (AGENT, DOCS-ONLY)
======================================================================

Apply docs-only corrections (verify on stale clones; **canonical tree as of 2026-05-09** already has these):

1. Root README.md:
   - Stack count **26** (incl. **`remotely`**, **`psu-ots`**, **`synology-api-bridge`**); port table includes remotely **5371**
   - DNS / TLS prose uses **host-named** wildcards (**`*.otsorundscore.*`**, **`*.misfitsds.*`**) — not **`*.ots.olutechsys.com`** / **`*.mft.olutechsys.com`**
   - Must reflect **`nas-reset.sh`** as reset entry point

2. HIVE_OBJECTIVE.md:
   - **26** stack folders in the table; **`psu-ots`** and **`synology-api-bridge`** in the name list
   - **26** workers / **`--count 26`** spawn string

3. docs/hive/NAS_DEPLOYMENT.md must contain:
   - Git safety on NAS section
   - @eaDir corruption troubleshooting
   - Router cert known issue
   - Dockge 5571:5001 clarification
   - Docker network subnet registry table
   - DSM POSIX mode function naming pattern
   - sudo loses SSH keys — GIT_SSH_COMMAND pattern
   - nas-reset.sh usage
   - stack-level .gitignore rationale
   - administrators group (not users)
   - WebSocket reverse proxy setup (new — from Marius guide):
       Control Panel → Login Portal → Advanced → Reverse Proxy → Edit →
       Custom Header → Create → WebSocket
       Adds: Upgrade: websocket + Connection: Upgrade
   - DSM best practices checklist (new — from Marius guide):
       HTTP/2: Control Panel → Network → Connectivity → Enable HTTP/2
       HTTP Compression: Control Panel → Security → Advanced → Enable HTTP Compression
       HSTS: per reverse proxy in Control Panel → Login Portal → Advanced → Reverse Proxy
       Reuseport: Control Panel → Network → Connectivity → Enable Reuseport
       DDNS indexing prevention: Server header = "noindex"
       Access Control Profiles: restrict IP access per reverse proxy rule
   - DSM reverse proxy timeout for slow DB stacks:
       Proxy connection/send/read timeout: increase to 600s
       Control Panel → Login Portal → Advanced → Reverse Proxy → Advanced Settings
   - 400 Bad Request HTTPS fix:
       If container serves HTTPS internally, use HTTPS protocol in BOTH fields of the
       reverse proxy rule (source AND destination). HTTP→HTTPS mismatch causes 400.

4. Stack READMEs:
   - stacks/remotely/README.md: created ✓
   - stacks/holyclaude/README.md: add WebSocket note if not present
   - stacks/psu-ots/README.md: present (PSU / NOC + **`https://psu.otsorundscore.olutechsys.com`**)
   - stacks/dozzle/README.md: add healthcheck note (mentions `/dozzle healthcheck` subcommand available)

5. AGENTS.md deploy-readiness table:
   - Includes **`remotely`** and **`psu-ots`** rows where applicable
   - Verify healthcheck column for searxng main service
   - **What Works:** host-named TLS + PSU phased gates documented (**`AGENTS.md`** search **PSU**)
   - **What Works:** dozzle healthcheck anti-pattern fix documented (see 2026-05-08 OCI Healthcheck Audit)

6. scripts/init-nas.sh STACK_MANIFEST:
   - Includes **`"remotely:data"`** and **`"psu-ots:data"`** (among other entries)

======================================================================
PHASE 6 — OPERATOR RUNBOOK: FULL STACK DEPLOY (NAS)
======================================================================

Run these on the NAS. Human operator executes. Agent validates repo side only.

### Step 0 — Prerequisites

  DSM Package Center:
    - Container Manager installed and running
    - SSH enabled for laolufayese (administrators group)

  DSM Best Practices (apply once per NAS — from mariushosting.com):
    HTTP/2:        Control Panel → Network → Connectivity → Enable HTTP/2
    Compression:   Control Panel → Security → Advanced → Enable HTTP Compression
    Reuseport:     Control Panel → Network → Connectivity → Enable Reuseport
    DDNS noindex:  Control Panel → Network → Connectivity → Server header = "noindex"
    HSTS:          Per reverse proxy → Edit → check Enable HSTS
    Firewall:      Control Panel → Security → Firewall → enable with correct rules
                   NOTE: DSM 7.3 firewall bug — if containers fail after enabling firewall,
                   disable firewall, restart NAS, install container, re-enable firewall.

  Verify SSH key reaches GitHub BEFORE any reset:
    ssh -T git@github.com
    # Expected: Hi ofayese/dockge-ots! You've successfully authenticated...

### Step 1 — NAS reset (if starting fresh)

  PREFERRED PATH — use nas-reset.sh:
    sudo sh /volume1/docker/nas-reset.sh --dry-run
    sudo sh /volume1/docker/nas-reset.sh --yes --fix

  nas-reset.sh does:
    1. Pre-flight (git, bash, SSH key, source dir exists)
    2. mv dockge -> archive/dockge-backup-<ts>  (rollback if clone fails)
    3. git clone repo
    4. git config safe.directory
    5. scripts/restore-env.sh --fix
    6. scripts/init-nas.sh
    7. scripts/fix-permissions.sh
    8. chown -R laolufayese:administrators /volume1/docker/dockge

  NOTE: If running as root loses SSH key:
    export GIT_SSH_COMMAND="ssh -i /var/services/homes/laolufayese/.ssh/id_ed25519"
    sudo -E sh /volume1/docker/nas-reset.sh --yes --fix

  MANUAL PATH:
    git clone git@github.com:ofayese/dockge-ots.git /volume1/docker/dockge
    cd /volume1/docker/dockge
    git config --file .git/config --add safe.directory /volume1/docker/dockge
    sudo bash scripts/init-nas.sh
    sudo bash scripts/fix-permissions.sh

### Step 2 — Verify clone and bootstrap

    docker inspect Dockge 2>/dev/null || echo "Dockge not running"
    test -d /volume1/docker/dockge/stacks && echo "STACKS OK"
    test -f /volume1/docker/dockge/README.md && echo "README OK"

### Step 3 — Start Dockge host container

    sudo cp /volume1/docker/dockge/scripts/dockge-start.sh \
           /usr/local/etc/rc.d/dockge.sh
    sudo chmod +x /usr/local/etc/rc.d/dockge.sh
    sudo sh /usr/local/etc/rc.d/dockge.sh

  Verify:
    sudo docker inspect Dockge \
      --format '{{json .HostConfig.PortBindings}}'
    # Must show: {"5001/tcp":[{"HostIp":"0.0.0.0","HostPort":"5571"}]}

    curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5571/
    # Must return 200, 301, or 302

### Step 4 — Issue certificates (REQUIRED before Traefik/HAProxy)

  **HOLD POINT:** Do NOT proceed to Traefik until certs are issued.

    cd /volume1/docker/dockge/stacks/acme-sh
    cp .env.example .env
    # Edit .env: set CF_Token
    sudo docker compose up -d
    sudo mkdir -p \
      /volume1/certs/acme/wildcard \
      /volume1/certs/acme/otsorundscore \
      /volume1/certs/acme/misfitsds \
      /volume1/certs/acme/otsorundscore-sub \
      /volume1/certs/acme/misfitsds-sub \
      /volume1/certs/acme/otsmbpro16 \
      /volume1/certs/acme/hpdevcore

  **Traefik host-named wildcards** use **`otsorundscore/`** + **`misfitsds/`** only (see **`README.md`**, **`stacks/acme-sh/SETUP.md`**, and **`docs/hive/CERT_REISSUE_TRAEFIK_OAUTH_RUNBOOK.md`**). Do not point Traefik at legacy **`ots-sub`/`mft-sub`** paths; those are not mounted by **`traefik-ots`** / **`traefik-mft`** in this repo.

  Verify PEM files exist:
    ls -la /volume1/certs/acme/otsorundscore/
    # Expected: fullchain.pem, privkey.pem present

  Full --issue and --install-cert sequence: stacks/acme-sh/SETUP.md

### Step 5 — Deploy Traefik stacks (after certs exist)

  **CRITICAL DEPENDENCY:** Traefik entrypoint HTTPS will fail if certs are missing.

    cd /volume1/docker/dockge/stacks/traefik-ots
    cp .env.example .env
    sudo docker compose up -d
    
  Wait 30s for startup:
    sleep 30
    
  Verify Traefik health:
    sudo docker exec traefik-ots wget -qO- http://127.0.0.1:8080/ping
    # Expected: OK
    
    sudo docker compose logs traefik-ots | grep -i "cert\|listen\|error" | head -5
    # Check for TLS initialization messages, no "certificate not found" errors

  If TLS errors appear, troubleshoot:
    - Verify `/volume1/certs/acme/otsorundscore/fullchain.pem` exists
    - Check Traefik compose `ACME_CERT_ROOT` env var points to correct path
    - Restart: `sudo docker compose restart traefik-ots`

### Step 6 — Deploy remaining stacks via Dockge UI

  Open http://10.0.1.15:5571

  Recommended deploy order (with critical holds):
    1. portainer
    2. homepage       (needs Portainer API key + Dockge creds in .env)
    3. databases      (postgres + mariadb)
    4. ollama         (AI backend for rag-stack)
    5. rag-stack      (depends on ollama + databases healthy)
    6. remotely       (register first account immediately after deploy)
       **HOLD POINT:** After deploy, enable WebSocket in DSM reverse proxy (see post-deploy step)
    7. psu-ots         (PowerShell Universal — after Traefik **ots** + PEMs; needs Dockge API creds in .env)
    8. searxng
    9. grafana-prom   (needs watchtower bearer token; wait for Prometheus scrape init ~2min)
    10. zabbix         (needs postgres; SNMPv3 config separate — see AGENTS.md)
    11. code-server
    12. remaining stacks

  For each stack:
    - cp .env.example .env
    - fill required secrets (do NOT git add .env files)
    - deploy via Dockge UI or docker compose up -d

  Post-deploy for remotely (CRITICAL for remote sessions):
    # Enable WebSocket in DSM Reverse Proxy for remotely (required for remote sessions)
    # DSM → Control Panel → Login Portal → Advanced → Reverse Proxy
    # → Select remotely rule → Edit → Custom Header → Create → WebSocket → Save
    # Then navigate to http://10.0.1.15:5371 and register first admin account

  Post-deploy dirs (if not created by init-nas.sh):
    sudo mkdir -p /volume1/docker/dockge/stacks/grafana-prom/data/grafana
    sudo mkdir -p /volume1/docker/dockge/stacks/grafana-prom/data/prometheus
    sudo mkdir -p /volume1/docker/dockge/stacks/remotely/data

### Step 7 — HAProxy (optional front door)

    sudo sh -c 'cat /volume1/certs/acme/otsorundscore/fullchain.pem \
      /volume1/certs/acme/otsorundscore/privkey.pem \
      > /volume1/docker/dockge/stacks/_haproxy/certs/otsorundscore.olutechsys.com.pem'
    sudo /volume1/@appstore/haproxy/sbin/haproxy -c \
      -f /volume1/@appdata/haproxy/haproxy.cfg

### Step 8 — Post-deploy validation

    sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | sort
    sudo docker ps --filter health=unhealthy \
      --format 'table {{.Names}}\t{{.Status}}'
    bash /volume1/docker/dockge/scripts/compose-validate.sh
    
  **Validation gates before production:**
    - No `unhealthy` containers visible
    - Dozzle shows logs from all stacks (verify log aggregation working)
    - Traefik dashboard reachable via `https://<hostname>:6443/dashboard/`
    - Homepage widgets show connected backends (not ECONNREFUSED)

### Step 9 — NAS git hygiene

  ALWAYS use the git-pull-nas helper:
    ~/bin/git-pull-nas

  NEVER on the NAS:
    git add -A  /  git add .  /  git pull --rebase

  ALWAYS before any git add:
    git status --short

  If @eaDir error appears:
    find /volume1/docker/dockge/.git/refs \
      -name "*eaDir*" -o -name "*SynoEAStream*" \
      | xargs rm -f 2>/dev/null; true
    git pull --no-rebase

======================================================================
PHASE 7 — VALIDATION SUITE (AGENT)
======================================================================

  scripts/compose-validate.sh
  pre-commit run --all-files

  # No depends_on.condition
  grep -rn "condition:" stacks/*/compose.yaml

  # No --version healthcheck probes
  grep -rn "\-\-version" stacks/*/compose.yaml | grep -i "healthcheck"

  # dozzle healthcheck uses /dozzle subcommand (not --version)
  grep -A2 "healthcheck:" stacks/dozzle/compose.yaml | grep "dozzle"
  # Expected: /dozzle healthcheck

  # No DB files in git
  git ls-files | grep -E "/db/|/data/|\.db$|pg_wal"

  # No secrets in git
  git ls-files | grep -E "secrets/.*\.txt|id_ed25519|bearer_token"

  # No wrong TZ defaults
  grep -rn "Europe/London" stacks/

  # No boolean literals in environment blocks
  grep -rn ":[[:space:]]*true\b\|:[[:space:]]*false\b" \
    stacks/*/compose.yaml | grep -v "#"

  # NAS git helper docs aligned
  grep -l "git_pull_nas\|git-pull-nas" AGENTS.md docs/hive/NAS_DEPLOYMENT.md

  # Port 3001 reserved for holyclaude, 5371 for remotely
  grep -rn "3001:\|5371:" stacks/*/compose.yaml

  # No legacy OTS/MFT *service* hostnames in stacks compose (host-named model)
  rg '\.ots\.olutechsys\.com|\.mft\.olutechsys\.com' stacks/ || true
  # Expected: no matches

  # Split-DNS / hairpin verdict (LAN vs public DNS)
  bash scripts/verify-dns-views.sh --hairpin

  # Stack-level gitignore on database/data stacks
  for s in databases zabbix ollama rag-stack remotely psu-ots; do
    ls stacks/$s/.gitignore || echo "MISSING: stacks/$s/.gitignore"
  done

  # Shell scripts clean (post–consolidation sprint baseline)
  shellcheck -x scripts/*.sh

  # Stack count is 26
  ls stacks/ | grep -v '^_' | wc -l

  # Image healthcheck verification (optional — requires NAS or local docker access)
  # Verify dozzle has /dozzle healthcheck subcommand
  docker run --rm --entrypoint "" louislam/dozzle:latest /bin/sh -c "/dozzle healthcheck 2>&1 | head -1"
  # Expected: exit 0 or exit 1 (probe works, service state may vary)

======================================================================
PHASE 8 — COMPOUND MEMORY UPDATE (AGENT)
======================================================================

/compound-learning

Add dated bullet under AGENTS.md -> ## What Works if findings are new.
Do not duplicate existing bullets.

Required patterns to ensure are documented:

  [2026-05-08] NAS tool patterns:
  - DSM ~/. bashrc POSIX mode trap: underscores + alias pattern required.
  - sudo loses SSH keys: GIT_SSH_COMMAND or -E flag.
  - administrators group (not users): users group has zero members on this NAS.
  - nas-reset.sh at /volume1/docker/nas-reset.sh.

  [2026-05-08] Docker network patterns:
  - Subnet registry maintained to avoid Pool overlaps.
  - Next free subnet: 172.22.2.0/24+

  [2026-05-08] Healthcheck patterns:
  - ollama: CMD /usr/bin/ollama list (not CMD-SHELL).
  - qdrant: nc HTTP GET probe (/readyz unauthenticated).
  - dozzle: /dozzle healthcheck subcommand (NOT --version).
  - remotely: curl -fs http://localhost:5000/ (ASP.NET Core Debian, curl confirmed).

  [2026-05-09-b] Dozzle healthcheck anti-pattern fix:
  - **Historical:** some Dozzle instances used `["CMD", "/dozzle", "--version"]` probe (fails after version output on some releases).
  - **Correct:** use built-in subcommand `["CMD", "/dozzle", "healthcheck"]` (always reliable).
  - **Audit:** Phase 3 and Phase 7 validation includes dozzle healthcheck check.
  - **Reference:** stacks/dozzle/compose.yaml (baseline for other binary probes).

  [2026-05-09-b] Code-server secrets handling:
  - code-server **`config/code-server/config.yaml`** is generated at runtime with plaintext password if not pre-provided.
  - **Mitigation:** bind **`${STACK_ROOT}/code-server/config:/home/coder/.config/code-server`** (contains gitignored **`code-server/`** dir).
  - **Secrets:** use **`.env`** (gitignored) with **`PASSWORD=${CODE_SERVER_PASSWORD}`** env var.
  - **Pre-flight:** `git ls-files stacks/code-server/config/code-server/ | wc -l` must be **0** (no tracked secrets).
  - **Recovery:** if plaintext password leaked historically, see **`scripts/rewrite-history-redact.sh`** for incident response.

  [2026-05-09-b] Zabbix SNMPv3 on Synology:
  - **SNMP**: Server (host running Zabbix container) polls agent UDP 161 — no inbound DSM agent needed.
  - **Configuration**: DSM Control Panel → SNMP → SNMPv3 → Engine ID + Auth/Priv credentials.
  - **Zabbix**: Add Host with SNMP interface type, SNMPv3 auth/priv (matches DSM config).
  - **SynoCommunity agent** (native): alternative to container Zabbix agent; requires **`Server=127.0.0.1`** + **`ServerActive=127.0.0.1:10051`** + exact **hostname** match in Zabbix UI (not FQDN).
  - **Container zabbix-agent2** (optional): only for container-level metrics; runs privileged with **`seccomp:unconfined`** + host binds — documented in **`AGENTS.md`** security list.

  [2026-05-09-b] mTLS / certificate pinning patterns:
  - **Use case:** container-to-container auth (e.g., Portainer Agent mTLS — HTTP probe fails).
  - **Pattern:** TCP probe (nc) instead of HTTP; mTLS handled by app, not health probe.
  - **Example:** `["CMD-SHELL", "nc -z 127.0.0.1 9001 || exit 1"]` (Portainer Agent).
  - **Traefik:** healthcheck uses native `traefik healthcheck --ping` (avoids TLS cert validation in probe).

  [2026-05-08] remotely stack added (**24th** stack; **`psu-ots`** is **25th** — see **[2026-05-09]**; **`synology-api-bridge`** is **26th** — see **[2026-05-10]**):
  - Image: immybot/remotely:latest (no semver tags — pin by digest after first pull)
  - Port: 10.0.1.15:5371:5000
  - Requires WebSocket in DSM reverse proxy for remote sessions
  - REMOTELY_KNOWN_PROXY env var required when behind reverse proxy
  - REMOTELY_SERVER_URL must match the public HTTPS hostname
  - First account registered = admin (register immediately after deploy)
  - Uses outgoing WebSocket only — no inbound firewall ports needed beyond 5371

  [2026-05-09] psu-ots (25th stack) + host-named TLS + consolidation sprint:
  - **`stacks/psu-ots/`** — digest-pinned **`ironmansoftware/universal`**, **`traefik-ots`** external network, **`https://psu.otsorundscore.olutechsys.com`**
  - Dockge API jobs: **`DOCKGE_USERNAME`** / **`DOCKGE_PASSWORD`** in **`stacks/psu-ots/.env`**; git under **`/nas-repo`** uses **`git pull --no-rebase`**
  - PEM dirs for Traefik wildcards: **`/volume1/certs/acme/otsorundscore/`**, **`.../misfitsds/`** — align live **`acme.sh`** before Traefik restarts
  - **`scripts/*.sh`**: Tier 1–3 hardening complete — **`shellcheck -x scripts/*.sh`** clean; **`scripts/verify-dns-views.sh --hairpin`** for DNS views
  - Only version PSU **`data/Repository/`** in git — runtime DB under **`data/`** is gitignored

  [2026-05-10] synology-api-bridge (26th stack) + OpenResume supply-chain + bridge security:
  - **`stacks/synology-api-bridge/`** — loopback publish **8780**; **`STACK_MANIFEST`** **`synology-api-bridge:data`**; allowlisted DSM routes only (no `/dsm/proxy`).
  - **`stacks/openresume/`** — pins **`yuihtt/open-resume@sha256:…`** (digest resolved on trusted host; never cross-namespace digest reuse).
  - ACME: host-run **`deploy_certs.sh`** / **`verify_serving.sh`** documented in **`docs/hive/proposals/acme-sh/ACME_DEPLOY_HOOK_ADR.md`**.

  [2026-05-08] DSM best practices from mariushosting.com:
  - HTTP/2: Control Panel → Network → Connectivity → Enable HTTP/2
  - HTTP Compression: Control Panel → Security → Advanced
  - Reuseport: Control Panel → Network → Connectivity
  - HSTS: per reverse proxy rule (Edit → check Enable HSTS)
  - DDNS noindex: Server header = "noindex" in Connectivity tab
  - Firewall DSM 7.3 bug: disable firewall before installing, re-enable after

  [2026-05-08] Common Docker issues from mariushosting.com:
  - MariaDB compatibility: use mariadb:11.4-noble NOT linuxserver or :latest
    The ubuntu-noble variant is most compatible across Synology NAS models.
  - PostgreSQL major version lock: pin postgres to specific major version
    (e.g. postgres:16) to prevent Watchtower upgrading to incompatible version.
    If version mismatch: change image to new version tag and update stack.
  - Boolean env vars: use 1/0 not true/false — some DSM compose versions
    reject YAML boolean literals in environment blocks.
  - 400 Bad Request HTTPS port: if container serves HTTPS internally,
    use HTTPS protocol in BOTH source AND destination fields of reverse proxy rule.
  - Reverse proxy timeout for slow DB installs: increase to 600s in
    Control Panel → Login Portal → Advanced → Reverse Proxy → Advanced Settings.
  - WebSocket requirement: containers using SignalR, Portainer, Remotely etc.
    need WebSocket headers added to their DSM reverse proxy rule:
    Custom Header → Create → WebSocket (auto-adds Upgrade + Connection headers).
  - Clean Docker between failed installs: stale volumes/networks cause
    "Access denied for user root@localhost" and similar errors.

======================================================================
PHASE 9 — CONTINUOUS LEARNING EXTRACTION (AGENT)
======================================================================

/continuous-learning

Extract to ~/.cursor/skills/learned/ only patterns not already present:

  nas-reset-recovery-order.md (update if exists):
    Add: nas-reset.sh is now the preferred entry point over manual clone.
    Add: sudo loses SSH keys — GIT_SSH_COMMAND or -E flag required.
    Add: restore-env.sh --fix validates and auto-fixes .env before restore.
    Add: Step 4 (acme-sh cert issue) is a critical hold point — Traefik fails without PEMs.

  synology-git-eadir-corruption.md (update if exists):
    Add: @eaDir returns after DSM updates even if indexer was disabled.
    git-pull-nas alias is the safety net regardless of indexer state.
    Add: Phase 0.5 pre-flight gate detects git state cleanness before any NAS reset.

  oci-healthcheck-patterns.md (update if exists):
    Add: ollama/ollama image loses PATH in CMD-SHELL — use CMD + full path.
    Add: qdrant (Rust image) has no wget/curl — use nc HTTP GET probe.
    Add: dozzle healthcheck subcommand exists — use `/dozzle healthcheck`, NOT `--version` (anti-pattern).
    Add: remotely (ASP.NET Core Debian) has curl — use curl -fs probe.
    Add: Verify image tools via `docker run --rm --entrypoint "" <image> which <tool>` before hardcoding probe.

  docker-network-subnet-registry.md (create if missing):
    Title: Docker Network Subnet Registry for OTS NAS
    Content: the full subnet allocation table.
    Rule: always check existing subnets before adding a named network.
    Symptom of conflict: "Pool overlaps with other one on this address space"

  dsm-posix-bashrc-functions.md (create if missing):
    Title: DSM ash POSIX Mode Function Naming Trap
    Context: Synology DSM /bin/sh is bash in POSIX mode
    Problem: hyphenated function names silently rejected
    Fix: use underscores in function, alias for hyphen access
    Verify: /bin/sh -c '. ~/.bashrc'

  api-key-rotation-schedule.md (create):
    Title: API Key Rotation Schedule — Dockge, PSU, Watchtower
    Keys to rotate periodically (60–90 days):
      - Dockge API credentials (used by PSU jobs)
      - PSU webhook authentication tokens
      - Watchtower API bearer token (grafana-prom integration)
      - Portainer API keys (homepage widgets)
      - GitHub personal access token (git operations on NAS)
    Process:
      1. Generate new key in app UI (Dockge → Account Settings, PSU → Settings, etc.)
      2. Update local `.env` files (gitignored)
      3. If key is in active job/script, update that config and restart service
      4. Test new key (curl request with new token, or run PSU job once)
      5. Delete old key in app UI after confirmation
      6. Document rotation in ops log (not in git)

  synology-docker-best-practices.md (create):
    Title: Synology NAS Docker Best Practices (mariushosting)
    Sources: mariushosting.com best practices + common issues articles
    Content:
      DSM SETTINGS (apply once per NAS):
        HTTP/2:       Control Panel → Network → Connectivity
        Compression:  Control Panel → Security → Advanced
        Reuseport:    Control Panel → Network → Connectivity
        DDNS noindex: Server header = "noindex" (Connectivity tab)
        HSTS:         Per reverse proxy rule → Edit → Enable HSTS
        Firewall:     Enable with correct rules; DSM 7.3 has install-time bug

      REVERSE PROXY RULES:
        WebSocket: Custom Header → Create → WebSocket (for SignalR/socket apps)
        HTTPS backend: use HTTPS in BOTH source and destination protocol fields
        Timeout: increase to 600s for slow DB init (Advanced Settings tab)
        HSTS: enable per rule after certs are in place

      COMPOSE RULES:
        MariaDB: use mariadb:11.4-noble (most compatible across NAS models)
        PostgreSQL: pin to specific major version to prevent Watchtower breakage
        Boolean env vars: use 1/0 not true/false
        Clean between installs: docker system prune if repeated failures

      WEBSOCKET STACKS (need Custom Header in reverse proxy):
        Portainer, Remotely, Home Assistant, Stirling-PDF, Uptime Kuma,
        Planka, NocoDB, Mattermost, Rocket.Chat, Immich, and many others.

======================================================================
ROLLBACK
======================================================================

### Repo changes

Unstaged changes:
  git restore <file>
  git restore .

Staged changes:
  git restore --staged <file>
  git restore --staged .

Committed changes:
  git revert <sha>

### NAS runtime rollback (per stack)

Quick rollback (data persists):
  sudo docker compose -f stacks/<stack>/compose.yaml down
  # Data persists in STACK_ROOT/<stack>/data/ — safe to redeploy

Selective service rollback (inside a multi-service stack):
  # Stop one service, keep others running
  sudo docker compose -f stacks/<stack>/compose.yaml stop <service>
  sudo docker compose -f stacks/<stack>/compose.yaml rm <service>
  # Redeploy when ready
  sudo docker compose -f stacks/<stack>/compose.yaml up -d <service>

Data recovery (if files were accidentally deleted):
  # Check backup on DSM Hyper Backup or snapshot
  sudo ls -la /volume1/docker/dockge/stacks/<stack>/data/
  # If missing, restore from backup:
  #   Synology Control Panel → Backup & Restore → Restore Service
  #   (requires prior Hyper Backup or rsync snapshot)

### Full NAS rollback (if nas-reset.sh ran)

If deployment failed partway through:
  sudo mv /volume1/docker/dockge /volume1/docker/dockge-failed
  sudo mv /volume1/docker/archive/dockge-backup-<ts> /volume1/docker/dockge
  
Then re-run from Phase 1 (audit gates) or Phase 6 (deploy) depending on scope of failure.

### Cert recovery (if Traefik TLS fails post-deploy)

If Traefik shows "certificate not found" errors:
  1. Verify acme-sh is still running:
     sudo docker compose -f stacks/acme-sh/compose.yaml logs | grep -i "error\|renew"
  
  2. If acme-sh stalled, redeploy:
     sudo docker compose -f stacks/acme-sh/compose.yaml restart
     sleep 30
  
  3. Verify PEM files exist:
     ls -la /volume1/certs/acme/otsorundscore/
  
  4. Restart Traefik:
     sudo docker compose -f stacks/traefik-ots/compose.yaml down
     sudo docker compose -f stacks/traefik-ots/compose.yaml up -d
     sleep 30
     sudo docker exec traefik-ots wget -qO- http://127.0.0.1:8080/ping

### Image version downgrade (if Watchtower auto-upgraded broke a service)

If a service breaks after Watchtower auto-update:
  1. Find previous working image tag (from Docker Hub release history or docker.io)
  2. Edit `stacks/<stack>/compose.yaml` and change image to semver tag (not :latest)
  3. Redeploy:
     sudo docker compose -f stacks/<stack>/compose.yaml pull
     sudo docker compose -f stacks/<stack>/compose.yaml down
     sudo docker compose -f stacks/<stack>/compose.yaml up -d
  4. Verify health:
     sudo docker compose -f stacks/<stack>/compose.yaml ps
     sudo docker logs <container_name> | tail -20

======================================================================
EXECUTION LOG (2026-05-09-b) — post-review additions
======================================================================

- **Phase 0.5** pre-flight hardening gate added (operator SSH key + branch check, agent git status + compose validate baseline).
- **Phase 2** per-stack readiness table extended with TIER categories (A/B/C/X) and weighted scoring; deploy-readiness table now includes tier column and blocker rationale.
- **Phase 3** healthcheck anti-patterns expanded with per-image probes; dozzle healthcheck subcommand baseline added (anti-pattern fix from 2026-05-08 OCI audit); image tool verification pattern documented.
- **Phase 4** added dozzle healthcheck anti-pattern check (flagging --version if present).
- **Phase 6** deploy order and post-deploy steps now include critical hold points (Step 4 acme-sh cert issue, Step 5 Traefik TLS dependency, Step 6 remotely WebSocket DSM rule as CRITICAL for remote sessions); validation gates added (no unhealthy containers, Dozzle log aggregation, Traefik dashboard reachability).
- **Phase 7** extended validation with dozzle healthcheck verify + optional image-level probes (docker run --entrypoint pattern).
- **Phase 8** compound-learning expanded with dozzle healthcheck anti-pattern fix, code-server secrets handling, Zabbix SNMPv3 pattern, mTLS/certificate pinning patterns.
- **Phase 9** continuous-learning added api-key-rotation-schedule.md (Dockge, PSU, Watchtower keys); updated nas-reset-recovery-order.md to include Step 4 cert hold point.
- **Rollback** section expanded with per-service recovery steps, data recovery patterns, cert recovery (acme-sh + Traefik restart), and image version downgrade procedure.

======================================================================
EXECUTION LOG (2026-05-09) — post-sprint doc alignment
======================================================================

- **`MASTER_AUDIT_AND_DEPLOY.md`** updated for **26** stacks (**`psu-ots`**, **`synology-api-bridge`**), host-named acme/HAProxy examples, Phase **7** validation (**`verify-dns-views.sh --hairpin`**, legacy hostname **`rg`**, **`shellcheck`**), deploy order, and **`AGENTS.md`** Phase **8** compound-memory bullets reflecting completed consolidation + PSU work.
- Historical log from **2026-05-08** retained below for prior audit snapshot.

======================================================================
EXECUTION LOG (2026-05-08)
======================================================================

Phase 1 audit gates recorded before any Phase 5 fixes:

- Gate 1: stack count = 24, manifest parity failed (`remotely` missing in `STACK_MANIFEST`)
- Gate 2: repo layout guard passed
- Gate 3: key artifacts passed (README + rag-stack + remotely files present)
- Gate 4: Dockge 5571->5001 references passed
- Gate 5: NAS git safety refs passed
- Gate 6: tracked runtime/secrets failed (legacy tracked noise present; remediation required separately)
- Gate 7: stack-level `.gitignore` files passed
- Gate 8: compose filename rule passed (`warp-main` exception)
- Gate 9: no `Europe/London` in stacks passed
- Gate 10: subnet registry check found `172.29.0.0/24` in addition to `172.22.x`
- Gate 11: router cert expiry docs passed
- Gate 12: `scripts/restore-env.sh` exists
- Gate 13: remotely WebSocket README note passed
- Gate 14: boolean env scan includes many intentional `=true` style values; normalize in future hardening pass

Phase 2-4 audits recorded:

- Per-stack readiness matrix generated (`24` stack folders + `_haproxy`; **superseded** — use **26** stacks incl. **`psu-ots`** + **`synology-api-bridge`** for current audits)
- Cross-stack checks executed (`3001` reservation, `depends_on condition`, floating tags, empty `networks: {}`)
- Healthcheck pattern scan executed; notable anti-pattern retained for follow-up: `dozzle` using `--version`

======================================================================
FINAL PRINT
======================================================================

MASTER-AUDIT-AND-DEPLOY: COMPLETE
Version 2026-05-09-b (with detailed review additions)