> Superseded by `docs/tasks/MASTER_AUDIT_AND_DEPLOY.md` on 2026-05-08. Kept for history.

# Task: Updated Repo State Review — Post Session 2026-05-07

/coding-agent-orchestrator
/continuous-learning
/compound-learning-project-memory

Read-only audit phase first. Do not modify any file until directed.
End the audit phase with: REPO-AUDIT: COMPLETE

======================================================================
CONTEXT — WHAT CHANGED THIS SESSION
======================================================================

This session covered a NAS reset recovery and partial stack bring-up.
The following changes were made and need to be reflected in memory
and documentation:

COMMITTED THIS SESSION (partial list — verify against git log):
  - holyclaude/compose.yaml: port 3000:3000 → 3001:3001 (upstream default)
  - holyclaude/compose.yaml: healthcheck updated to probe port 3001
  - stacks with OCI wget healthcheck fixes (023ce18)
  - .gitignore: added DS_Store, secrets, bak, zip, node_modules rules
  - README.md: created at repo root (10b848c)
  - docs/tasks/README_CREATION.md: coder task file
  - docs/tasks/REPO_REVIEW.md: previous review task
  - docs/tasks/OCI_HEALTHCHECK_AUDIT.md: OCI audit task
  - scripts/audit-healthcheck-tools.sh: image probe script

KNOWN OUTSTANDING ISSUES DISCOVERED THIS SESSION:
  1. holyclaude @/shared error — image has broken nested cloudcli
     (manual npm install inside container as workaround; force pull needed)
  2. holyclaude upstream port is 3001 not 3000 — compose fixed
  3. Homepage config errors — Portainer 401, DSM wrong port, Dockge timeout
  4. git @eaDir refs — recurring Synology indexer corruption
     (DSM indexer now disabled for /volume1/docker — permanent fix applied)
  5. Secrets and runtime files were committed to git from NAS
     (cleaned via git rm --cached; .gitignore updated)
  6. NAS .gitignore still missing runtime dir rules for data/, logs/,
     .claude-flow/, .cursor/ — these show as ?? in git status

======================================================================
PHASE 0 — READ THESE FILES FIRST
======================================================================

  AGENTS.md
  HIVE_OBJECTIVE.md
  .gitignore
  README.md
  scripts/dockge-start.sh
  scripts/init-nas.sh (STACK_MANIFEST section only)
  stacks/holyclaude/compose.yaml
  stacks/homepage/compose.yaml
  stacks/traefik-ots/compose.yaml
  docs/hive/NAS_DEPLOYMENT.md (Known outstanding issues section)

======================================================================
PHASE 1 — AUDIT GATES
======================================================================

### Gate 1: .gitignore covers all NAS runtime dirs

Check that .gitignore includes ALL of these patterns:
  data/
  logs/
  .claude-flow/
  .claude/
  .cursor/
  stacks/**/.env
  stacks/**/data/
  stacks/**/secrets/
  stacks/**/config/logs/

FAIL if any are missing.

### Gate 2: holyclaude port is correct in compose.yaml

  grep "ports:" -A3 stacks/holyclaude/compose.yaml
  Expected: 3001:3001 (NOT 3000:3000)

### Gate 3: holyclaude healthcheck probes port 3001

  grep "3000\|3001" stacks/holyclaude/compose.yaml
  Expected: all references are 3001, none are 3000

### Gate 4: holyclaude image tag advisory current

  Check AGENTS.md deploy table row for holyclaude
  Note: image is :latest — upstream recommends force-pull for bug fixes
  Note: @/shared error requires fresh image pull not in-container fix

### Gate 5: homepage config issues documented

  Check if AGENTS.md or NAS_DEPLOYMENT.md notes the following:
  - Portainer widget requires API key (PORTAINER_API_KEY in .env)
  - DSM siteMonitor must use https://10.0.1.15:5001/ not 5000
  - Portainer Agent siteMonitor removed (agent uses mTLS not HTTP)
  - Dockge widget requires DOCKGE_USERNAME + DOCKGE_PASSWORD in .env

### Gate 6: @eaDir git corruption documented

  Check if AGENTS.md or NAS_DEPLOYMENT.md notes:
  - Synology indexer creates @eaDir/ inside .git/refs/
  - Fix: find .git/refs -name "*eaDir*" | xargs rm -f
  - Permanent fix: disable DSM indexer for /volume1/docker
  - git-pull-nas alias pattern

### Gate 7: secrets-in-repo incident documented

  Check if AGENTS.md "Recurring Bugs" or "What Failed" notes:
  - NAS-committed secrets: databases/secrets/*.txt, grafana-prom/secrets/
  - SSH key: stacks/ollama/data/id_ed25519 was pushed to GitHub
  - Fix: git rm --cached + .gitignore rules
  - Key rotation requirement for id_ed25519

### Gate 8: README.md exists and is current

  ls README.md
  head -5 README.md
  Expected: exists, title "Olutech Homelab — Dockge Stack Repo"

### Gate 9: docs/tasks/ directory exists

  ls docs/tasks/
  Expected: README_CREATION.md, REPO_REVIEW.md, OCI_HEALTHCHECK_AUDIT.md

### Gate 10: Stack count still 23

  ls stacks/ | grep -v '^_' | wc -l
  Expected: 23

REPO-AUDIT: COMPLETE

======================================================================
PHASE 2 — ADVISORY REPORT
======================================================================

Format:
  ## Priority 1 — Blocking / Security
  ## Priority 2 — Correctness
  ## Priority 3 — Hardening
  ## Priority 4 — Documentation gaps

======================================================================
PHASE 3 — APPLY SAFE FIXES
======================================================================

FIX 1 — .gitignore: add missing NAS runtime dir rules

If Gate 1 FAILED, append to .gitignore:

  # NAS runtime dirs — local only, never commit
  data/
  logs/
  .claude-flow/
  .claude/
  .cursor/
  stacks/**/data/
  stacks/**/config/logs/

Note: stacks/**/.env and stacks/**/secrets/ should already be present
from this session's gitignore update — only add what is missing.

FIX 2 — AGENTS.md: add [2026-05-07] session bullet under What Works

Add this bullet under "## What Works" with today's date:

  [2026-05-07] **Session: NAS partial bring-up and git hygiene (2026-05-07):**
  - holyclaude upstream port is 3001 (not 3000). compose.yaml corrected:
    ports 3001:3001, healthcheck probes 3001. BREAKING if you cached 3000.
  - holyclaude @/shared error is caused by stale bundled cloudcli inside
    the image. Fix: sudo docker pull coderluii/holyclaude:latest (force
    fresh pull) then recreate container. In-container npm install is a
    workaround only — lost on container recreate.
  - Homepage widget errors are expected during partial bring-up. Only two
    are config bugs: (1) Portainer Agent siteMonitor removed (mTLS, not HTTP)
    → HPE_CLOSED_CONNECTION; (2) DSM siteMonitor was port 5000, corrected
    to https://10.0.1.15:5001/. Remaining ECONNREFUSED errors clear as
    stacks deploy.
  - Homepage Portainer widget needs PORTAINER_API_KEY in stacks/homepage/.env.
    Generate: Portainer → Account Settings → Access Tokens → Add.
  - Homepage Dockge widget needs DOCKGE_USERNAME + DOCKGE_PASSWORD in
    stacks/homepage/.env. Without these, widget times out (ETIMEDOUT) even
    though the container is healthy.
  - Synology @eaDir git ref corruption pattern: DSM file indexer enters
    .git/refs/heads/ and creates @eaDir/ subdirectory; git reads it as a
    branch named "@eaDir/main@SynoEAStream". Breaks every git pull.
    Fix: find .git/refs -name "*eaDir*" | xargs rm -f 2>/dev/null
    Permanent fix: DSM → Control Panel → Search → Indexed Locations →
    remove /volume1/docker. Add git-pull-nas alias that auto-cleans refs.
  - Secrets committed to GitHub from NAS: stacks/databases/secrets/*.txt,
    stacks/grafana-prom/secrets/watchtower_bearer_token.txt, and
    stacks/ollama/data/id_ed25519 (SSH private key) were pushed.
    id_ed25519 must be treated as compromised and rotated. Files removed
    via git rm --cached; .gitignore updated with **/secrets/*.txt and
    **/id_ed25519 rules. NEVER run git add from the NAS without checking
    git status --short first.
  - git operations on the NAS must use --no-rebase for pull (not --rebase)
    because HEAD detach during rebase fails when untracked files exist.
  - NAS ownership fix before git ops: sudo chown -R laolufayese:users
    /volume1/docker/dockge — required after any sudo docker compose operation
    that creates files in the repo directory.
  - scripts/audit-healthcheck-tools.sh: added to scripts/ — verifies wget,
    curl, nc, sh availability in each image. Run before assuming a probe
    tool is present. Key finding: traefik:v3 HAS wget (not scratch-based
    as assumed); the probe fix to CMD traefik healthcheck --ping is still
    correct (uses app binary) but the assumption was wrong.

FIX 3 — AGENTS.md: add to Recurring Bugs

Add under "## Recurring Bugs" (or What Failed):

  - [2026-05-07] Running git add/commit/push from the NAS without reviewing
    git status first led to secrets, SSH keys, .DS_Store, .claude-flow/,
    node_modules/, and backup archives being committed to GitHub. Rule:
    ALWAYS run git status --short before any git add on the NAS. The NAS
    working tree contains many untracked runtime dirs that must never be
    staged. Use git add <specific-file> not git add -A or git add .

  - [2026-05-07] Synology DSM file indexer (@eaDir) corrupts .git/refs
    on any git repo stored on a Synology volume. Symptom: "fatal: bad
    object refs/heads/@eaDir/main@SynoEAStream" on every git pull.
    Permanent fix: disable DSM indexing for /volume1/docker.
    Workaround: find .git/refs -name "*eaDir*" | xargs rm -f before pull.

FIX 4 — docs/hive/NAS_DEPLOYMENT.md: add git safety section

Under a new subsection "## Git safety on the NAS" add:

  ### Never use `git add -A` or `git add .` on the NAS

  The NAS working tree always contains untracked runtime dirs (.env files,
  data/, logs/, secrets/, .claude-flow/, .cursor/) that must never enter
  the repo. Always use:

    git status --short          # review before any add
    git add <specific-file>     # stage only what you intend

  If you accidentally stage a secrets file:
    git rm --cached <file>
    echo "<file-pattern>" >> .gitignore
    git add .gitignore
    git commit -m "chore: untrack <file>"

  ### @eaDir git ref corruption

  Symptom: `fatal: bad object refs/heads/@eaDir/main@SynoEAStream`
  
  Cause: DSM file indexer enters .git/refs/heads/ and creates @eaDir/
  subdirectory which git reads as a branch.

  Immediate fix:
    find /volume1/docker/dockge/.git/refs -name "*eaDir*" | xargs rm -f
    git pull --no-rebase

  Permanent fix: DSM → Control Panel → Search → Indexed Locations →
  remove /volume1/docker from the list.

  ### Recommended alias (~/.bashrc on NAS)

    git-pull-nas() {
      find /volume1/docker/dockge/.git/refs -name "*eaDir*" \
        | xargs rm -f 2>/dev/null
      git -C /volume1/docker/dockge pull --no-rebase
    }

  ### Ownership fix before git operations

  After any sudo docker compose operation, files in the repo dir may
  be owned by root. Fix before git pull:

    sudo chown -R laolufayese:users /volume1/docker/dockge

======================================================================
PHASE 4 — VALIDATION
======================================================================

  pre-commit run --files .gitignore AGENTS.md docs/hive/NAS_DEPLOYMENT.md
  Expected: all hooks pass.

  git status
  Expected: only the changed files, no surprise additions.

  Commit:
    git add .gitignore AGENTS.md docs/hive/NAS_DEPLOYMENT.md
    git commit -m \
      "docs: session 2026-05-07 — holyclaude port, git hygiene, @eaDir, secrets incident"
    git push

======================================================================
PHASE 5 — CONTINUOUS LEARNING EXTRACTION
======================================================================

/continuous-learning

Extract to ~/.cursor/skills/learned/:

Pattern 1: synology-git-eadir-corruption.md
  Title: Synology @eaDir Git Ref Corruption
  Trigger: Any git repo on a Synology volume using DSM file indexer
  Symptom: "fatal: bad object refs/heads/@eaDir/main@SynoEAStream"
  Root cause: DSM indexer enters .git/refs/heads/ and creates @eaDir/
  Fix (immediate): find .git/refs -name "*eaDir*" | xargs rm -f
  Fix (permanent): Disable DSM indexing for the volume/folder in
    Control Panel → Search → Indexed Locations
  Prevention: touch /path/repo/.git/.no_auto_index
  Alias pattern: git-pull-nas() with ref cleanup before every pull

Pattern 2: nas-git-add-safety.md
  Title: Never git add -A on a NAS Working Tree
  Context: Any git repo on Synology NAS with Docker stacks
  Problem: NAS working tree always has runtime dirs (.env, data/,
    secrets/, .claude-flow/) that must not enter git
  Rule: Always git status --short before any git add
  Rule: Always git add <specific-file>, never git add -A or git add .
  Recovery: git rm --cached <file> + add to .gitignore + commit
  Critical: SSH private keys and secrets committed to GitHub must be
    treated as compromised and rotated immediately

Pattern 3: holyclaude-port-and-image.md
  Title: HolyClaude Docker Image Port and Image Quirks
  Port: The holyclaude image listens on 3001 internally (CloudCLI web UI)
    NOT 3000. Compose must map 3001:3001.
  Image bug: @siteboon/claude-code-ui bundles @cloudcli-ai/cloudcli
    at a broken version. Symptom: "@/shared not found" in logs on loop.
    Fix: docker pull coderluii/holyclaude:latest (force fresh pull)
    NOT npm install inside container (lost on recreate)
  Health endpoint: http://localhost:3001/ (not 3000)
  Access URL: http://10.0.1.15:3001

Pattern 4: homepage-widget-config.md
  Title: Homepage Widget Common Configuration Errors
  Portainer widget: Needs API key. Generate: Portainer → Account
    Settings → Access Tokens → Add. Set PORTAINER_API_KEY in .env.
    Never use env: 1 without verifying the environment ID in Portainer.
  Portainer Agent siteMonitor: Remove it. Agent uses mTLS, returns
    HTTP/1.0 400 to plain HTTP probes → HPE_CLOSED_CONNECTION in logs.
  DSM siteMonitor: Use https://10.0.1.15:5001/ not http://10.0.1.15:5000/
    DSM is HTTPS on 5001 in modern DSM versions.
  Dockge widget: Needs DOCKGE_USERNAME + DOCKGE_PASSWORD in .env.
    Without credentials, widget times out silently (ETIMEDOUT).
  ECONNREFUSED errors: Expected during partial bring-up.
    Clear as stacks are deployed. Not a Homepage bug.

======================================================================
FINAL PRINT
======================================================================

Print:
  REPO-REVIEW-UPDATED: COMPLETE
