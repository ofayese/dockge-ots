# Task: Cursor Skills Integration + Acme-sh/DNS/HAProxy/Dockge Fixes
# Version: 2026-05-08
# Sources:
#   cursor_acme_sh_dns_audit_requirements.md (Cursor session audit)
#   haproxy_+_dockge_access_5e1531d0.plan.md
#   homelab_dns_review_4d799f13.plan.md
#   macro_gaps_review_7306a559.plan.md
#   GitHub: auth0/agent-skills, EveryInc/compound-engineering-plugin,
#           obra/superpowers, upstash/context7, cursor/plugins

/coder
/compound-learning
/continuous-learning

======================================================================
CONTEXT
======================================================================

This task consolidates NEW FINDINGS from the Cursor session audit
transcript and the five Cursor skill repos. It covers:

  1. acme-sh: ots-sub and mft-sub certs not yet in SETUP.md (critical)
  2. HAProxy: live config at /volume1/@appdata/haproxy/haproxy.cfg,
     binary at /volume1/@appstore/haproxy/sbin/haproxy
     README.txt in certs/ causes "no start line" error
  3. Dockge: port fix 5571:5001 (not 5571:5571), dockge.db migration
  4. NAS git: post-clone safe.directory, @eaDir in verify-repo-layout
  5. Traefik: --entrypoints.traefik.address=:8080 and --ping=true
     required for healthcheck when dashboard is off
  6. Cursor skill repos: auth0/agent-skills, compound-engineering,
     obra/superpowers, upstash/context7 integration plan

======================================================================
PHASE 0 — PRE-FLIGHT READS
======================================================================

  stacks/acme-sh/SETUP.md
  stacks/acme-sh/compose.yaml
  stacks/traefik-ots/compose.yaml
  stacks/traefik-mft/compose.yaml
  stacks/agents_gateway_data/compose.yaml
  stacks/mcp-tools-config/compose.yaml
  scripts/dockge-start.sh
  scripts/verify-repo-layout.sh
  docs/hive/dns/olutechsys.com.zone (if exists)
  docs/hive/SERVICE_MAP.md (if exists)
  stacks/_haproxy/haproxy.cfg
  stacks/_haproxy/maps/host.map

======================================================================
PHASE 1 — ACME-SH: ots-sub and mft-sub cert documentation
======================================================================

FINDING FROM AUDIT:
  The audit confirmed ots-sub and mft-sub certs are NOT issued yet and
  NOT documented in SETUP.md. The existing cert tree covers:
    wildcard/, otsorundscore-sub/, misfitsds-sub/, otsmbpro16/, hpdevcore/
  Missing: ots-sub/ (*.ots.olutechsys.com) and mft-sub/ (*.mft.olutechsys.com)

STEP 1A — Verify SETUP.md already has ots-sub and mft-sub sections:
  Command: grep -c "ots-sub\|mft-sub" stacks/acme-sh/SETUP.md
  If count >= 4: PASS — skip to Phase 2.
  If count < 4: Apply the fixes below.

STEP 1B — Add to stacks/acme-sh/SETUP.md if missing:

  1. Add to the cert directory tree section:
       ├── ots-sub/   *.ots.olutechsys.com
       ├── mft-sub/   *.mft.olutechsys.com

  2. Add to mkdir -p block:
       /volume1/certs/acme/ots-sub \
       /volume1/certs/acme/mft-sub

  3. Add "## Issue ots and mft namespace certs" section:

     ```bash
     sudo docker exec AcmeSh acme.sh --issue \
       -d '*.ots.olutechsys.com' \
       --keylength 2048 \
       --dns dns_cf --server letsencrypt
     ```

     Wait ~2 min for DNS propagation.

     ```bash
     sudo docker exec AcmeSh acme.sh --issue \
       -d '*.mft.olutechsys.com' \
       --keylength 2048 \
       --dns dns_cf --server letsencrypt
     ```

  4. Add "## Configure ots and mft output paths" section:

     ```bash
     sudo docker exec AcmeSh acme.sh --install-cert \
       -d '*.ots.olutechsys.com' \
       --cert-file      /volume1/certs/acme/ots-sub/cert.pem \
       --key-file       /volume1/certs/acme/ots-sub/privkey.pem \
       --ca-file        /volume1/certs/acme/ots-sub/chain.pem \
       --fullchain-file /volume1/certs/acme/ots-sub/fullchain.pem \
       --reloadcmd      "chmod 640 /volume1/certs/acme/ots-sub/privkey.pem"
     ```

     ```bash
     sudo docker exec AcmeSh acme.sh --install-cert \
       -d '*.mft.olutechsys.com' \
       --cert-file      /volume1/certs/acme/mft-sub/cert.pem \
       --key-file       /volume1/certs/acme/mft-sub/privkey.pem \
       --ca-file        /volume1/certs/acme/mft-sub/chain.pem \
       --fullchain-file /volume1/certs/acme/mft-sub/fullchain.pem \
       --reloadcmd      "chmod 640 /volume1/certs/acme/mft-sub/privkey.pem"
     ```

  5. Add to "What this stack manages" table:
     | OTS namespace | ots-sub/ (*.ots.olutechsys.com) | acme.sh | Traefik le-dns |
     | MFT namespace | mft-sub/ (*.mft.olutechsys.com) | acme.sh | Traefik le-dns |

======================================================================
PHASE 2 — DNS ZONE FILE: verify and create if missing
======================================================================

FINDING FROM AUDIT:
  The audit found NO zone file in the repo at audit time (commit 401885b
  created it). Verify it exists and has the correct content.

STEP 2A — Check:
  Command: ls docs/hive/dns/olutechsys.com.zone 2>/dev/null || echo MISSING

STEP 2B — If missing, create docs/hive/dns/olutechsys.com.zone:

  ; olutechsys.com DNS zone — BIND-style reference
  ; Managed in Cloudflare. This file is documentation only.
  ; Last updated: 2026-05-08

  $ORIGIN olutechsys.com.
  $TTL 300

  ; ── OTS namespace (NAS #1 — otsorundscore.synology.me) ───────────
  ; Cert: /volume1/certs/acme/ots-sub/ (*.ots.olutechsys.com)
  ; Grey cloud in Cloudflare — do NOT proxy wildcard CNAMEs
  ots             IN  CNAME   otsorundscore.synology.me.
  *.ots           IN  CNAME   otsorundscore.synology.me.

  ; ── MFT namespace (NAS #2 — misfitsds.synology.me) ───────────────
  ; Cert: /volume1/certs/acme/mft-sub/ (*.mft.olutechsys.com)
  mft             IN  CNAME   misfitsds.synology.me.
  *.mft           IN  CNAME   misfitsds.synology.me.

  ; ── Future namespaces (reserved — not yet active) ─────────────────
  ;lab            IN  CNAME   otsorundscore.synology.me.
  ;*.lab           IN  CNAME   otsorundscore.synology.me.
  ;dev             IN  CNAME   otsorundscore.synology.me.
  ;*.dev           IN  CNAME   otsorundscore.synology.me.

STEP 2C — Verify CNAMEs:
  Command: grep -E "^ots|^\*\.ots|^mft|^\*\.mft" docs/hive/dns/olutechsys.com.zone
  Expected: 4 lines

  Command: grep -E "^lab|^dev" docs/hive/dns/olutechsys.com.zone
  Expected: zero (must be commented with ;)

======================================================================
PHASE 3 — HAPROXY: NAS path documentation and README.txt fix
======================================================================

FINDING FROM AUDIT:
  HAProxy on DSM uses these specific paths:
    Binary:      /volume1/@appstore/haproxy/sbin/haproxy
    Live config: /volume1/@appdata/haproxy/haproxy.cfg
  The repo config lives at stacks/_haproxy/haproxy.cfg
  The live config includes the repo config OR is a copy of it.

  CRITICAL BUG FOUND AND FIXED in session:
    stacks/_haproxy/certs/README.txt was present.
    HAProxy treats every non-dotfile in certs/ as a PEM bundle.
    README.txt has no start line → HAProxy config parse FAIL.
    Fix: remove README.txt from certs/. Use stacks/_haproxy/README.txt.

STEP 3A — Verify README.txt is not in certs/:
  Command: ls stacks/_haproxy/certs/README.txt 2>/dev/null && echo PRESENT || echo ABSENT
  Expected: ABSENT (if PRESENT → remove it, it will break HAProxy)

STEP 3B — If README.txt is in certs/, remove it and move notes:
  Move all operator notes to stacks/_haproxy/README.txt (parent dir).
  The certs/ directory should contain ONLY *.pem files and dotfiles.

STEP 3C — Update stacks/_haproxy/README.txt with NAS-specific paths:

  ## Synology HAProxy package paths (DSM)
  Binary:      /volume1/@appstore/haproxy/sbin/haproxy
  Live config: /volume1/@appdata/haproxy/haproxy.cfg
  Validate:    sudo /volume1/@appstore/haproxy/sbin/haproxy -c \
                 -f /volume1/@appdata/haproxy/haproxy.cfg

  ## Wiring the repo config to the live config (pick one)
  Option A — Point HAProxy service at repo config directly:
    Set HAProxy package to use:
    -f /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg

  Option B — Thin wrapper (keep /volume1/docker/haproxy.cfg):
    Replace /volume1/docker/haproxy.cfg body with:
    include /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg

  ## certs/ directory rule (CRITICAL)
  haproxy.cfg uses `bind *:443 ssl crt stacks/_haproxy/certs/`
  HAProxy reads EVERY non-hidden file in certs/ as a PEM bundle.
  Only *.pem files and dotfiles are allowed in certs/.
  README.txt, notes.txt, any text file WILL cause:
    [ALERT] unable to load certificate from file '...README.txt': no start line.

  ## Generating a test PEM (syntax check without real cert)
  sudo openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
    -keyout /tmp/test.key -out /tmp/test.crt -subj "/CN=localhost"
  sudo sh -c 'cat /tmp/test.crt /tmp/test.key \
    > stacks/_haproxy/certs/_syntax-check.pem'
  sudo rm /tmp/test.key /tmp/test.crt

STEP 3D — Add to docs/hive/NAS_DEPLOYMENT.md under HAProxy section:

  ## HAProxy Synology package paths

  | Item | Path |
  |---|---|
  | Binary | /volume1/@appstore/haproxy/sbin/haproxy |
  | Live config | /volume1/@appdata/haproxy/haproxy.cfg |
  | Repo config | /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg |

  Validate: sudo /volume1/@appstore/haproxy/sbin/haproxy -c \
    -f /volume1/@appdata/haproxy/haproxy.cfg

  CRITICAL: certs/ directory must contain ONLY *.pem files.
  Any .txt file causes [ALERT] no start line and HAProxy refuses to start.

======================================================================
PHASE 4 — TRAEFIK: healthcheck entrypoint fix
======================================================================

FINDING FROM AUDIT:
  The wget /ping healthcheck fails when dashboard is off unless
  --entrypoints.traefik.address=:8080 and --ping=true are in command.
  The audit-verified traefik command block requires BOTH these flags.
  Verify both traefik stacks have them.

STEP 4A — Check both traefik stacks:
  Command:
    grep "entrypoints.traefik\|ping" \
      stacks/traefik-ots/compose.yaml \
      stacks/traefik-mft/compose.yaml

  Expected: both --entrypoints.traefik.address=:8080 and --ping=true
  present in each file.

STEP 4B — If missing from either file, add to command block:
    - --entrypoints.traefik.address=:8080
    - --ping=true

  Also update healthcheck to use traefik binary (not wget):
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 15s

  NOTE: wget probe on /ping also works if the image has wget.
  Traefik binary probe (CMD traefik healthcheck --ping) is preferred
  as it uses the built-in mechanism (Type E).

STEP 4C — Verify STACK_ROOT and ACME_CERT_ROOT vars in both .env.example:
  Command:
    grep "STACK_ROOT\|ACME_CERT_ROOT" \
      stacks/traefik-ots/.env.example \
      stacks/traefik-mft/.env.example
  Expected: both vars documented in each file.

  ACME_CERT_ROOT default is /volume1/certs/acme
  STACK_ROOT default is /volume1/docker/dockge/stacks

======================================================================
PHASE 5 — DOCKGE: port fix and migration verification
======================================================================

FINDING FROM AUDIT:
  CRITICAL BUG: dockge-start.sh used -p 5571:5571 but louislam/dockge:1
  listens on internal port 5001, not 5571. Nothing was on host 5571.
  Fix: -p 5571:5001

  SECONDARY: The data mount changed from …/dockge/data:/app/data to
  …/dockge:/app/data. A migration function handles legacy dockge.db.
  Edge case: migration skips if root dockge.db exists but is empty.
  Fix: only skip migration if root dockge.db is non-empty (-s test).

STEP 5A — Verify port mapping in scripts/dockge-start.sh:
  Command: grep "5571" scripts/dockge-start.sh
  Expected: -p 5571:5001 (NOT -p 5571:5571)
  FAIL if: -p 5571:5571 → change to 5571:5001

STEP 5B — Verify migration function handles empty root dockge.db:
  Command: grep -A5 "migrate_legacy\|dockge.db" scripts/dockge-start.sh | head -30
  Expected: migration condition uses -s (non-empty size check) not just -f (exists)

  If migration uses -f instead of -s, change:
    if [ -f "${DOCKGE_ROOT}/dockge.db" ]; then
  To:
    if [ -s "${DOCKGE_ROOT}/dockge.db" ]; then

STEP 5C — Add to docs/hive/NAS_DEPLOYMENT.md under Dockge section:

  ## Dockge port mapping (critical)

  Dockge image (louislam/dockge:1) listens on internal port 5001.
  Host port 5571 must map to container port 5001:
    -p 5571:5001  ← CORRECT
    -p 5571:5571  ← WRONG (nothing listens on 5571 inside container)

  Verify the running container:
    docker inspect Dockge --format '{{json .HostConfig.PortBindings}}'
    # Expected: {"5001/tcp":[{"HostIp":"0.0.0.0","HostPort":"5571"}]}

  ## Dockge app state layout

  Old layout: -v …/dockge/data:/app/data (required data/ subdirectory)
  New layout: -v …/dockge:/app/data (repo root is app data)
  Migration: dockge-start.sh auto-migrates dockge.db from data/ to root.

======================================================================
PHASE 6 — NAS GIT: post-clone setup documentation
======================================================================

FINDING FROM AUDIT:
  The following are recurring issues on NAS git operations:
  1. Git 2.35+ "dubious ownership" when repo is root-owned
  2. ~/.gitconfig.lock prevents git config --global
  3. SSH key permissions (0777 causes "load pubkey" failure)
  4. git clone typo: "git clonegit@..." (missing space)
  5. @eaDir in stacks/ causes false positive in verify-repo-layout.sh
  6. git pull as root fails with permission denied (publickey)

STEP 6A — Verify verify-repo-layout.sh ignores @eaDir:
  Command: grep "@eaDir" scripts/verify-repo-layout.sh
  Expected: @eaDir present with a skip/continue statement

STEP 6B — If @eaDir skip is missing, add to verify-repo-layout.sh:
  After the basename line in the stack-scan loop, add:
    # Synology/macOS SMB: @eaDir is AppleDouble metadata, not a Dockge stack.
    [ "${name}" = "@eaDir" ] && continue

STEP 6C — Add complete NAS fresh-start sequence to NAS_DEPLOYMENT.md:

  ## Complete NAS fresh-start sequence (after DSM reset)

  ### Prerequisites
    1. DSM → Package Center → install Container Manager
    2. SSH as laolufayese (Port 28)
    3. SSH key setup:
         ssh-keygen -t ed25519 -C "nas-deploy" -f ~/.ssh/id_ed25519
         chmod 700 ~/.ssh
         chmod 600 ~/.ssh/id_ed25519
         # Add ~/.ssh/id_ed25519.pub to GitHub Settings → SSH keys
         ssh -T git@github.com  # confirm: Hi ofayese/dockge-ots!

  ### Clone and bootstrap
    mkdir -p /volume1/docker
    cd /volume1/docker
    git clone git@github.com:ofayese/dockge-ots.git dockge
    cd /volume1/docker/dockge
    # Set safe.directory in repo config (avoids ~/.gitconfig.lock issues)
    git config --file .git/config --add safe.directory /volume1/docker/dockge
    sudo bash scripts/init-nas.sh

  ### If safe.directory is needed globally (gitconfig not locked)
    git config --global --add safe.directory /volume1/docker/dockge
    # If .gitconfig.lock exists: sudo rm -f ~/.gitconfig.lock first

  ### Start Dockge
    sudo cp scripts/dockge-start.sh /usr/local/etc/rc.d/dockge.sh
    sudo chmod +x /usr/local/etc/rc.d/dockge.sh
    sudo sh /usr/local/etc/rc.d/dockge.sh
    # Verify: docker inspect Dockge shows 5001→5571 binding
    # Access: http://10.0.1.15:5571/

  ### Git pull as non-root (always)
    # git pull must run as the user who owns the repo (not root)
    # root has no GitHub SSH key → Permission denied (publickey)
    # Use: ssh as laolufayese, then git pull (no sudo)
    # If files are root-owned: sudo chown -R laolufayese:administrators /volume1/docker/dockge
    # Then git pull as laolufayese

======================================================================
PHASE 7 — CURSOR SKILLS INTEGRATION
======================================================================

The five repos provide actionable integration patterns for this repo.
This phase documents what to adopt from each.

### 7A — auth0/agent-skills (Auth0 official skills)

WHAT IT IS:
  Official Auth0 SDK skills following the Anthropic Agent Skills Spec.
  Each skill is a directory with SKILL.md containing YAML frontmatter:
    ---
    name: auth0-nextjs
    description: Add authentication to Next.js apps using @auth0/nextjs-auth0
    ---

RELEVANCE TO THIS REPO:
  The Google Workspace OAuth guide (docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md)
  documents OAuth for NAS login. Auth0 skills provide the pattern for
  documenting OAuth integration in a reusable skill format.

ACTION:
  Create .cursor/skills/auth-patterns/ with skill stubs for:
    - oauth-dsm-sso.md  (DSM SSO Client OAuth pattern)
    - oauth-google-workspace.md (Google Workspace OIDC pattern)

  These are NOT auth0 SDK skills — they are homelab operator skills
  following the same SKILL.md format for reuse in Cursor Agent tasks.

  Format for each (follow Anthropic Agent Skills Spec):
    ---
    name: oauth-dsm-sso
    description: Configure Synology DSM SSO Client with Google Workspace OIDC
    ---
    # OAuth DSM SSO Pattern
    See docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md for full guide.
    Key constraints:
    - Origins: scheme + host only (no paths, no wildcards)
    - Redirect URIs: exact full path (no wildcards)
    - All must agree: Authorized Domains, Origins, Redirect URIs,
      DSM hostname, TLS cert SANs

### 7B — EveryInc/compound-engineering-plugin (14.9k stars)

WHAT IT IS:
  Official Compound Engineering plugin for Claude Code, Codex, Cursor.
  This is the /compound-learning methodology already used in this repo.
  The plugin provides structured memory accumulation across sessions.

RELEVANCE TO THIS REPO:
  Already integrated via /compound-learning slash command.
  The plugin's CLAUDE.md pattern is what AGENTS.md ## What Works implements.

ACTION:
  Verify .cursor/ directory has compound-learning configured:
    ls .cursor/ 2>/dev/null || echo "No .cursor dir"
    ls .cursor/skills/ 2>/dev/null || echo "No cursor skills"

  If .cursor/skills/ is missing, create it with compound-learning stub:
    mkdir -p .cursor/skills
    (The skill files live in /mnt/skills/user/ in the Claude environment
    and are referenced via the system prompt — no repo files needed.)

  Add to AGENTS.md ## What Works:
    [2026-05-08] Cursor plugin integration:
    - compound-engineering-plugin (EveryInc/14.9k stars): already used
      as /compound-learning. No additional setup needed.
    - auth0/agent-skills pattern: SKILL.md format adopted for operator
      skills under .cursor/skills/

### 7C — obra/superpowers (agentic skills framework)

WHAT IT IS:
  An agentic skills framework and software development methodology.
  Has a .cursor-plugin directory. Skills cover TDD, debugging,
  collaboration, code quality. Jesse Vincent's original "Superpowers".

RELEVANCE TO THIS REPO:
  The TDD and debugging skills are directly applicable to:
  - scripts/ validation (compose-validate, verify-repo-layout)
  - healthcheck verification (audit-healthcheck-tools.sh)
  - Pre-commit hooks and CI gates

WHAT TO ADOPT:
  The Superpowers methodology introduces structured task execution:
    1. Read → understand before acting
    2. Plan → outline what will change
    3. Execute → make changes
    4. Verify → confirm changes correct
    5. Commit → only after verification

  This maps directly to the MASTER_AUDIT_AND_DEPLOY.md phase structure.
  The repo already follows this pattern. Reinforce it by documenting
  the methodology in AGENTS.md.

ACTION:
  Add to AGENTS.md ## What Works:
    Superpowers methodology (obra/superpowers): Read → Plan → Execute
    → Verify → Commit. Already embedded in task file phase structure.
    Key rule: never commit without running compose-validate + pre-commit.

### 7D — upstash/context7 (live documentation MCP server)

WHAT IT IS:
  Context7 MCP server — pulls version-specific docs and code examples
  from source repos into LLM context. Prevents hallucinated API calls
  by providing real, current documentation.

RELEVANCE TO THIS REPO:
  Direct value for:
  - traefik:v3 configuration (Traefik docs change between major versions)
  - ollama API endpoints (ollama list, ollama run syntax)
  - qdrant REST API (/readyz, /collections endpoints)
  - valkey/redis CLI syntax
  - docker compose syntax differences between versions

INTEGRATION:
  Context7 runs as an MCP server. Add to stacks/agents_gateway_data/
  or as a separate mcp-context7 stack:

  Option A — Add to existing agents_gateway_data MCP gateway:
    The docker/mcp-gateway already supports multiple --servers flags.
    Check if context7 is available as an MCP server name:
      --servers=duckduckgo,context7

  Option B — Add a dedicated context7 service to agents_gateway_data:
    This is the cleaner approach since context7 requires its own
    Upstash Redis connection and config.

  ACTION:
    Update stacks/agents_gateway_data/README.md with:
      ## Context7 (upstash/context7)
      Context7 provides live documentation lookup for LLM coding agents.
      When coding with Claude/Cursor, prefix library names with "use context7"
      to pull current API docs instead of relying on training data.
      Integration: configure via Upstash Redis connection or local mode.
      MCP server URL: https://mcp.context7.com/mcp (Upstash hosted)
      Add to Cursor MCP config in .cursor/mcp.json:
        {
          "mcpServers": {
            "context7": {
              "type": "url",
              "url": "https://mcp.context7.com/mcp"
            }
          }
        }

  CREATE .cursor/mcp.json if it doesn't exist:

  {
    "mcpServers": {
      "context7": {
        "type": "url",
        "url": "https://mcp.context7.com/mcp",
        "note": "Context7 live docs for traefik, ollama, qdrant, docker compose"
      }
    }
  }

### 7E — cursor/plugins (official Cursor plugin format)

WHAT IT IS:
  Official Cursor plugin format. Plugins live in .cursor-plugin/
  directory. Each plugin has:
    - plugin.json (manifest: name, version, description)
    - skills/ directory with SKILL.md files

RELEVANCE TO THIS REPO:
  The .cursor/ directory convention is where project-scoped Cursor
  config lives. Skills installed here are available to Cursor Agent
  for this project only.

ACTION:
  Create .cursor-plugin/plugin.json (project-level plugin manifest):

  {
    "name": "dockge-homelab",
    "version": "1.0.0",
    "description": "Homelab infrastructure skills for the OTS/MFT NAS dockge repo",
    "skills": [
      "skills/nas-reset-recovery.md",
      "skills/synology-git-safety.md",
      "skills/docker-healthcheck-patterns.md",
      "skills/traefik-port-mapping.md",
      "skills/subnet-registry.md"
    ]
  }

  Create .cursor-plugin/skills/ with the five skill stubs.
  Each skill follows the Agent Skills Spec format (SKILL.md with
  YAML frontmatter name + description).

  Content for each:
    nas-reset-recovery.md: nas-reset.sh workflow, SSH key setup,
      git safe.directory, dockge port fix, dockge.db migration
    synology-git-safety.md: never git add -A on NAS, @eaDir handling,
      git pull as non-root, administrators group
    docker-healthcheck-patterns.md: all type A-E patterns confirmed
      for each image type (Rust/Go/Node.js/Python/Debian)
    traefik-port-mapping.md: :80/:443 internal, 8880/6443 host,
      dashboard trailing slash, connection drop diagnosis
    subnet-registry.md: full 172.x allocation table, no 192.168.x

======================================================================
PHASE 8 — SERVICE MAP: verify or create
======================================================================

FINDING FROM AUDIT:
  docs/hive/SERVICE_MAP.md was created in commit 401885b with the
  full service inventory. Verify it exists and covers both NASes.

STEP 8A:
  Command: grep -c "ots.olutechsys.com\|mft.olutechsys.com" \
    docs/hive/SERVICE_MAP.md 2>/dev/null || echo MISSING
  Expected: 7 or more matches

  If missing, create per the content in NETWORK_ROUTING_OAUTH_OPTIMIZATION.md
  Task Phase 3.

STEP 8B — Verify Hyper Backup section includes cert dirs:
  Command: grep -c "ots-sub\|mft-sub" docs/hive/NAS_DEPLOYMENT.md
  Expected: 2 or more matches (cert dirs in Hyper Backup table)
  If missing, add the cert backup table from the audit session.

======================================================================
PHASE 9 — VALIDATION
======================================================================

  scripts/compose-validate.sh
  Expected: All compose files validated OK.

  # Traefik stacks have healthcheck with ping
  grep -n "healthcheck:\|ping" \
    stacks/traefik-ots/compose.yaml \
    stacks/traefik-mft/compose.yaml
  Expected: healthcheck present with ping probe in each

  # No README.txt in certs/
  ls stacks/_haproxy/certs/README.txt 2>/dev/null && echo FAIL || echo PASS

  # ots-sub and mft-sub in SETUP.md
  grep -c "ots-sub\|mft-sub" stacks/acme-sh/SETUP.md
  Expected: 4+

  # Dockge port is 5001
  grep "5571" scripts/dockge-start.sh | grep "5001"
  Expected: -p 5571:5001

  # @eaDir skip in verify-repo-layout.sh
  grep "@eaDir" scripts/verify-repo-layout.sh
  Expected: skip/continue statement present

  # DNS zone has 4 CNAME lines
  grep -E "^ots|^\*\.ots|^mft|^\*\.mft" docs/hive/dns/olutechsys.com.zone \
    | wc -l
  Expected: 4

  # .cursor/mcp.json exists
  ls .cursor/mcp.json 2>/dev/null || echo MISSING

  pre-commit run --all-files
  Expected: all hooks pass

  git add -A
  git commit -m \
    "feat: cursor skills integration, acme ots/mft certs, HAProxy paths, \
traefik healthcheck, dockge port fix, NAS git sequence, .cursor-plugin"
  git push

======================================================================
PHASE 10 — COMPOUND MEMORY UPDATE
======================================================================

/compound-learning

Add to AGENTS.md ## What Works:

  [2026-05-08] Cursor session audit findings + skill repo integration:

  ACME-SH:
  - ots-sub and mft-sub certs are new — NOT covered by existing wildcards.
  - *.ots.olutechsys.com requires --issue -d '*.ots.olutechsys.com'
  - Always mkdir -p /volume1/certs/acme/ots-sub before --install-cert
  - acme-sh owns cert lifecycle; Traefik is cert-consumer only (:ro mount)

  HAPROXY DSM PATHS:
  - Binary: /volume1/@appstore/haproxy/sbin/haproxy
  - Live config: /volume1/@appdata/haproxy/haproxy.cfg
  - Repo config: stacks/_haproxy/haproxy.cfg
  - CRITICAL: certs/ must contain ONLY *.pem files. Any .txt/.md file
    causes [ALERT] no start line → HAProxy refuses to start.
    Always verify with haproxy -c before reload.

  TRAEFIK PING HEALTHCHECK:
  - --entrypoints.traefik.address=:8080 AND --ping=true BOTH required
  - Without these, /ping is unreachable when dashboard is off
  - Use CMD traefik healthcheck --ping (Type E) over wget (Type A)

  DOCKGE PORT (CONFIRMED):
  - louislam/dockge:1 listens on internal port 5001, not 5571
  - Host mapping MUST be 5571:5001 (not 5571:5571)
  - Verify: docker inspect Dockge --format '{{json .HostConfig.PortBindings}}'

  NAS GIT SEQUENCE:
  - git pull MUST run as laolufayese (not root) — root has no GitHub key
  - After root-caused file changes: chown -R laolufayese:administrators
  - safe.directory: set in repo config (not global) to avoid .gitconfig.lock:
      git config --file .git/config --add safe.directory /volume1/docker/dockge
  - @eaDir in stacks/: AppleDouble metadata, not a stack — skip in scripts

  CURSOR SKILL REPOS:
  - auth0/agent-skills: Agent Skills Spec format (SKILL.md + YAML frontmatter)
    Adopted for .cursor-plugin/skills/ operator skill stubs
  - compound-engineering-plugin: already integrated as /compound-learning
  - obra/superpowers: Read→Plan→Execute→Verify→Commit methodology
    already embedded in phase-ordered task files
  - upstash/context7: MCP server for live docs; add to .cursor/mcp.json
    Value: prevents hallucinated API calls for traefik/ollama/qdrant
  - cursor/plugins: .cursor-plugin/plugin.json manifest format adopted
    for project-level skill discovery

======================================================================
PHASE 11 — CONTINUOUS LEARNING
======================================================================

/continuous-learning

Extract to ~/.cursor/skills/learned/:

  haproxy-dsm-paths.md:
    Title: HAProxy Synology DSM Package Paths
    Binary: /volume1/@appstore/haproxy/sbin/haproxy
    Config: /volume1/@appdata/haproxy/haproxy.cfg
    Validate: sudo /volume1/@appstore/haproxy/sbin/haproxy -c -f <config>
    CRITICAL: certs/ dir must have ONLY *.pem files — no README, no .txt
    Symptom: [ALERT] no start line = non-PEM file in certs/ directory

  acme-sh-ots-mft-certs.md:
    Title: acme-sh New Namespace Cert Issuance Pattern
    Two new certs needed: ots-sub (*.ots.olutechsys.com) and
    mft-sub (*.mft.olutechsys.com)
    These are THIRD-level wildcards — not covered by *.olutechsys.com
    Pattern: --issue -d '*.ots.olutechsys.com' --dns dns_cf
    Then: --install-cert with explicit output paths

  context7-mcp-integration.md:
    Title: Context7 MCP Server for Live Docs
    URL: https://mcp.context7.com/mcp
    Config: .cursor/mcp.json → mcpServers → context7
    Use: prefix library name with "use context7" in Cursor prompts
    Value: prevents hallucinated API calls for actively-developed libs
    Best for: traefik v3, qdrant, ollama, docker compose syntax

  agent-skills-spec.md:
    Title: Anthropic Agent Skills Spec (SKILL.md Format)
    Format: directory with SKILL.md, YAML frontmatter: name + description
    Location: .cursor-plugin/skills/ (project) or ~/.cursor/skills/ (user)
    Discovery: Cursor Agent reads skills on session start
    Plugin manifest: .cursor-plugin/plugin.json
    Reference: auth0/agent-skills, obra/superpowers, cursor/plugins

======================================================================
FINAL PRINT
======================================================================

CURSOR-SKILLS-ACME-HAPROXY-DOCKGE: COMPLETE
