# Task: Master Audit + Deploy — Full Stack
# Version: 2026-05-08-b (added remotely stack + Marius DSM best practices)

/coder
/compound-learning
/continuous-learning

======================================================================
CONTEXT
======================================================================

This master task consolidates prior task files into one repeatable flow:

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

======================================================================
PHASE 1 — REPO AUDIT GATES (AGENT)
======================================================================

Run and record PASS / FAIL / NOTE for each gate.

### Gate 1: Stack count and manifest parity

  Stack count is now 24 (remotely added 2026-05-08).
  Update HIVE_OBJECTIVE.md "Stack folders" row and worker count if still at 23.

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
    - stack count 24
    - manifest diff empty after remotely is added to STACK_MANIFEST in init-nas.sh

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
       stacks/remotely/.gitignore

  Expected: all five exist.

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

Output a table:

  | stack | healthcheck | logging | image-pin | readme | env-example | gitignore | websocket-doc | deploy-ready |

Known deploy-readiness blockers from prior audit (verify still apply):
  - codex-docs: :latest image needs operator pin (digest)
  - openresume: :latest image needs operator pin (digest)
  - watchtower: :latest image needs operator pin
  - github-desktop: :latest — document floating-tag exception
  - holyclaude: :latest — documented dev image exception
  - traefik-ots/mft: traefik:v3 floating major tag — pin advisory in README
  - agents_gateway_data: TZ missing
  - warp-main: TZ partial
  - remotely: :latest — OPERATOR PIN NEEDED (no semver tags published upstream)

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

Mandatory checks — these have known correct forms:

  dozzle:
    MUST use: ["CMD", "/dozzle", "healthcheck"]
    NOT:      ["CMD", "/dozzle", "--version"]

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

Optional runtime tool audit:
  bash scripts/audit-healthcheck-tools.sh 2>&1 | tee /tmp/healthcheck-audit.txt

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

Apply docs-only corrections:

1. Root README.md:
   - Stack count: update from 23 to 24 (remotely added)
   - Port table: add remotely (5371)
   - Must reflect nas-reset.sh as reset entry point

2. HIVE_OBJECTIVE.md:
   - Update stack count from 23 to 24 in "Stack folders" row
   - Add remotely to the stack name list
   - Update worker count from 21 to 22

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

5. AGENTS.md deploy-readiness table:
   - Add remotely row (24th stack)
   - Verify healthcheck column for searxng main service

6. scripts/init-nas.sh STACK_MANIFEST:
   - ADD: "remotely:data"  # SQLite DB + agent installers

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

    cd /volume1/docker/dockge/stacks/acme-sh
    cp .env.example .env
    # Edit .env: set CF_Token
    sudo docker compose up -d
    sudo mkdir -p \
      /volume1/certs/acme/wildcard \
      /volume1/certs/acme/otsorundscore-sub \
      /volume1/certs/acme/misfitsds-sub \
      /volume1/certs/acme/otsmbpro16 \
      /volume1/certs/acme/hpdevcore \
      /volume1/certs/acme/ots-sub \
      /volume1/certs/acme/mft-sub

  Full --issue and --install-cert sequence: stacks/acme-sh/SETUP.md

### Step 5 — Deploy Traefik stacks (after certs exist)

    cd /volume1/docker/dockge/stacks/traefik-ots
    cp .env.example .env
    sudo docker compose up -d
    sudo docker exec traefik-ots wget -qO- http://127.0.0.1:8080/ping
    # Expected: OK

### Step 6 — Deploy remaining stacks via Dockge UI

  Open http://10.0.1.15:5571

  Recommended deploy order:
    1. portainer
    2. homepage       (needs Portainer API key + Dockge creds in .env)
    3. databases      (postgres + mariadb)
    4. ollama         (AI backend for rag-stack)
    5. rag-stack
    6. remotely       (register first account immediately after deploy)
    7. searxng
    8. grafana-prom   (needs watchtower bearer token)
    9. zabbix         (needs postgres)
    10. code-server
    11. remaining stacks

  For each stack:
    - cp .env.example .env
    - fill required secrets (do NOT git add .env files)
    - deploy via Dockge UI or docker compose up -d

  Post-deploy for remotely:
    # Enable WebSocket in DSM Reverse Proxy for remotely (required for remote sessions)
    # DSM → Control Panel → Login Portal → Advanced → Reverse Proxy
    # → Select remotely rule → Edit → Custom Header → Create → WebSocket → Save
    # Then navigate to http://10.0.1.15:5371 and register first admin account

  Post-deploy dirs (if not created by init-nas.sh):
    sudo mkdir -p /volume1/docker/dockge/stacks/grafana-prom/data/grafana
    sudo mkdir -p /volume1/docker/dockge/stacks/grafana-prom/data/prometheus
    sudo mkdir -p /volume1/docker/dockge/stacks/remotely/data

### Step 7 — HAProxy (optional front door)

    sudo sh -c 'cat /volume1/certs/acme/ots-sub/fullchain.pem \
      /volume1/certs/acme/ots-sub/privkey.pem \
      > /volume1/docker/dockge/stacks/_haproxy/certs/ots.olutechsys.com.pem'
    sudo /volume1/@appstore/haproxy/sbin/haproxy -c \
      -f /volume1/@appdata/haproxy/haproxy.cfg

### Step 8 — Post-deploy validation

    sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | sort
    sudo docker ps --filter health=unhealthy \
      --format 'table {{.Names}}\t{{.Status}}'
    bash /volume1/docker/dockge/scripts/compose-validate.sh

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

  # Stack-level gitignore on database/data stacks
  for s in databases zabbix ollama rag-stack remotely; do
    ls stacks/$s/.gitignore || echo "MISSING: stacks/$s/.gitignore"
  done

  # Stack count is 24
  ls stacks/ | grep -v '^_' | wc -l

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
  - dozzle: /dozzle healthcheck subcommand.
  - remotely: curl -fs http://localhost:5000/ (ASP.NET Core Debian, curl confirmed).

  [2026-05-08] remotely stack added (24th stack):
  - Image: immybot/remotely:latest (no semver tags — pin by digest after first pull)
  - Port: 10.0.1.15:5371:5000
  - Requires WebSocket in DSM reverse proxy for remote sessions
  - REMOTELY_KNOWN_PROXY env var required when behind reverse proxy
  - REMOTELY_SERVER_URL must match the public HTTPS hostname
  - First account registered = admin (register immediately after deploy)
  - Uses outgoing WebSocket only — no inbound firewall ports needed beyond 5371

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

  synology-git-eadir-corruption.md (update if exists):
    Add: @eaDir returns after DSM updates even if indexer was disabled.
    git-pull-nas alias is the safety net regardless of indexer state.

  oci-healthcheck-patterns.md (update if exists):
    Add: ollama/ollama image loses PATH in CMD-SHELL — use CMD + full path.
    Add: qdrant (Rust image) has no wget/curl — use nc HTTP GET probe.
    Add: dozzle healthcheck subcommand exists — use it, not --version.
    Add: remotely (ASP.NET Core Debian) has curl — use curl -fs probe.

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

Repo changes:
  git restore --staged <file>
  git checkout -- <file>

Committed changes:
  git revert <sha>

NAS runtime rollback (per stack):
  sudo docker compose -f stacks/<stack>/compose.yaml down
  # Data persists in STACK_ROOT/<stack>/data/ — safe to redeploy

Full NAS rollback (if nas-reset.sh ran):
  sudo mv /volume1/docker/dockge /volume1/docker/dockge-failed
  sudo mv /volume1/docker/archive/dockge-backup-<ts> /volume1/docker/dockge

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

- Per-stack readiness matrix generated (`24` stack folders + `_haproxy`)
- Cross-stack checks executed (`3001` reservation, `depends_on condition`, floating tags, empty `networks: {}`)
- Healthcheck pattern scan executed; notable anti-pattern retained for follow-up: `dozzle` using `--version`

======================================================================
FINAL PRINT
======================================================================

MASTER-AUDIT-AND-DEPLOY: COMPLETE
