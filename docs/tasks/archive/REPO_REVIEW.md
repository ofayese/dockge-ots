> Superseded by `docs/tasks/MASTER_AUDIT_AND_DEPLOY.md` on 2026-05-08. Kept for history.

# Task: Repo state review, gap analysis, and continuous learning update

/coding-agent-orchestrator
/continuous-learning
/compound-learning-project-memory

Read-only audit phase first. Do not modify any file until directed.
End the audit phase with: REPO-AUDIT: COMPLETE

Then proceed to the fix phase as directed.

======================================================================
PHASE 0 — CONTEXT
======================================================================

The repo has just gone through a NAS reset recovery. Several things were
discovered to be misaligned between the repo's documented state and what
was actually deployed or working. This task asks you to:

1. Audit the repo for gaps, stale counts, and missing documentation
2. Advise on needed adjustments with priority order
3. Apply safe documentation-only fixes
4. Update AGENTS.md compound memory with the current confirmed state
5. Use /continuous-learning to extract reusable patterns

======================================================================
PHASE 1 — READ-ONLY AUDIT
======================================================================

Read each of the following and note discrepancies:

FILES TO READ:
  - AGENTS.md
  - HIVE_OBJECTIVE.md
  - CLAUDE.md
  - scripts/init-nas.sh (STACK_MANIFEST section)
  - scripts/dockge-start.sh
  - stacks/ (ls — count actual stack folders)
  - docs/hive/NAS_DEPLOYMENT.md
  - docs/hive/SERVICE_MAP.md
  - stacks/acme-sh/SETUP.md

AUDIT GATES (record PASS / FAIL / NOTE for each):

### Gate: Stack count consistency
  Command: ls stacks/ | grep -v '^_' | wc -l
  Check HIVE_OBJECTIVE.md "Stack folders" row count
  Check AGENTS.md "22" / "23" references
  Check scripts/init-nas.sh STACK_MANIFEST entry count
  Expected: all three agree
  Note any discrepancy — rag-stack may be missing from AGENTS.md count

### Gate: STACK_MANIFEST covers all stacks
  Command:
    diff \
      <(grep -E '^\s*"[^"]+:' scripts/init-nas.sh \
        | sed -E 's/^[[:space:]]*"([^"]+):.*/\1/' | sort) \
      <(ls stacks/ \
        | grep -vE \
            "^portainer$|^agents_gateway_data$|^it-tools$|\
^mcp-tools-config$|^openresume$|^warp-main$|^watchtower$|\
^docker-model-runner$|^_haproxy$" \
          | sort)
  Expected: empty (no diff)

### Gate: rag-stack has compose.yaml and README.md
  Command: ls stacks/rag-stack/
  Note: if these are missing, rag-stack is incomplete

### Gate: Dockge port mapping documented correctly
  Check AGENTS.md Dockge section for "5571:5001" (not "5571:5571")
  Check docs/hive/NAS_DEPLOYMENT.md for correct port reference
  Note: this was fixed in dockge-start.sh but docs may still say 5571:5571

### Gate: README.md exists at repo root
  Command: ls README.md
  Expected: exists (this is being created by a parallel task)

### Gate: acme-sh SETUP.md covers ots-sub and mft-sub
  Command: grep -c "ots-sub\|mft-sub" stacks/acme-sh/SETUP.md
  Expected: >= 4

### Gate: traefik-ots and traefik-mft compose.yaml image is pinned
  Command:
    grep "image:" stacks/traefik-ots/compose.yaml
    grep "image:" stacks/traefik-mft/compose.yaml
  Note: "traefik:v3" is a floating major tag — operator pin recommended

### Gate: unpinned :latest images in any compose
  Command:
    grep -rn ":latest" stacks/*/compose.yaml stacks/*/docker-compose.yml 2>/dev/null \
      | grep -v "^Binary"
  Note stacks with :latest for operator action

### Gate: holyclaude .env.example exists
  Command: ls stacks/holyclaude/.env.example

### Gate: rag-stack in deploy-readiness table in AGENTS.md
  Command: grep "rag-stack" AGENTS.md
  Expected: appears in deploy table — FAIL if absent

### Gate: NAS_DEPLOYMENT.md references correct Dockge port (5571->5001)
  Command: grep "5001\|5571" docs/hive/NAS_DEPLOYMENT.md | head -10
  Note whether it correctly states host 5571 -> container 5001

### Gate: router SSL cert expiry noted anywhere
  Note: router cert expired 2025/6/6 — is this documented in any
  docs/hive/ file as a known outstanding issue?

REPO-AUDIT: COMPLETE

======================================================================
PHASE 2 — ADVISORY REPORT
======================================================================

After completing the audit, produce a prioritised advisory report:

Format:
  ## Priority 1 — Blocking (prevents HTTPS / services)
  ## Priority 2 — Correctness (wrong docs, wrong counts)
  ## Priority 3 — Hardening (unpinned images, missing README)
  ## Priority 4 — Nice-to-have (minor polish)

For each item include:
  - What is wrong
  - Where it is wrong (file + line if possible)
  - Recommended fix
  - Whether it is safe to apply now (docs-only vs needs NAS access)

======================================================================
PHASE 3 — APPLY SAFE DOC-ONLY FIXES
======================================================================

Apply the following fixes WITHOUT requiring NAS access.
These are documentation corrections only — no compose.yaml changes.

FIX 1 — Stack count in AGENTS.md
  If AGENTS.md says "22" in the deploy-readiness table header or
  "What Works" bullets but ls stacks/ returns 23 (rag-stack present),
  update all "22" references to "23" in AGENTS.md.
  Also update HIVE_OBJECTIVE.md if it disagrees.

FIX 2 — rag-stack in AGENTS.md deploy table
  If rag-stack is absent from the deploy-readiness table in AGENTS.md,
  add a row for it using the same format as other rows.
  Mark deploy-ready as per what you find in stacks/rag-stack/.

FIX 3 — Dockge port in NAS_DEPLOYMENT.md
  If docs/hive/NAS_DEPLOYMENT.md still references the old wrong
  5571:5571 mapping anywhere, correct to 5571:5001 with note that
  the container image listens on 5001.

FIX 4 — Router cert expiry
  Add a note to docs/hive/NAS_DEPLOYMENT.md under a new subsection
  "## Known outstanding issues" (or append to an existing section):

    ### Router SSL certificate (batcavegtaxe16k.asuscomm.com)
    The GT-AXE16000 router admin cert expired 2025/6/6 (Let's Encrypt).
    The router UI is accessible at https://10.0.1.1:8443 but presents
    an expired cert. To renew: Administration -> System ->
    "Click here to manage" next to the certificate, or trigger renewal
    via the ASUS DDNS/cert UI. Requires the DDNS hostname to resolve
    to the current WAN IP.

FIX 5 — traefik:v3 pin advisory
  In stacks/traefik-ots/README.md and stacks/traefik-mft/README.md,
  add a note under a "## Image pinning" section:
    The compose.yaml uses traefik:v3 (floating major tag).
    For production: pin to a specific semver, e.g. traefik:v3.3.4.
    Check https://hub.docker.com/_/traefik/tags for current stable.

After all fixes, run:
  pre-commit run --all-files
  Expected: all hooks pass.

Run manifest diff to confirm no regressions:
  diff \
    <(grep -E '^\s*"[^"]+:' scripts/init-nas.sh \
      | sed -E 's/^[[:space:]]*"([^"]+):.*/\1/' | sort) \
    <(ls stacks/ \
      | grep -vE \
          "^portainer$|^agents_gateway_data$|^it-tools$|\
^mcp-tools-config$|^openresume$|^warp-main$|^watchtower$|\
^docker-model-runner$|^_haproxy$" \
        | sort)
  Expected: empty.

Commit:
  git add -A
  git commit -m "docs: repo audit fixes — stack count, rag-stack table, port docs, router cert note"

======================================================================
PHASE 4 — COMPOUND MEMORY UPDATE
======================================================================

/compound-learning-project-memory

Update AGENTS.md with a new dated bullet under "## What Works":

  [$(date +%Y-%m-%d)] **Post-reset recovery patterns (NAS reset 2026-05):**
  - Dockge MUST use 5571:5001 (not 5571:5571) — image listens on 5001.
    Container must be recreated (stop/rm/re-run rc script) to fix wrong mapping.
  - acme-sh certs are NOT persistent across NAS resets — must re-issue all
    certs after every reset before Traefik or HAProxy can serve HTTPS.
  - Deploy order after reset: Container Manager -> git clone -> init-nas.sh ->
    Dockge -> acme-sh (issue certs) -> traefik-ots -> other stacks.
  - stacks/_haproxy/certs/ must contain only .pem bundles (fullchain + key
    concatenated). Any non-PEM file causes haproxy -c to fail with "no start line".
  - Router NFS (rpcbind port 111) runs independently of NFSD — disabling NFS
    service stops port 2049 but NOT port 111. Block port 111 in iptables
    via /jffs/scripts/firewall-start for persistence across reboots.
  - Router admin SSL cert (batcavegtaxe16k.asuscomm.com) expired 2025/6/6.
    Needs manual renewal via Administration -> System in router UI.
  - README.md at repo root is the operator's entry point for post-reset
    recovery. Its absence costs days of recovery time.

======================================================================
PHASE 5 — CONTINUOUS LEARNING EXTRACTION
======================================================================

/continuous-learning

Extract the following patterns to ~/.cursor/skills/learned/:

Pattern 1: nas-reset-recovery-order.md
  Title: NAS Reset Recovery Sequence
  Context: Synology DSM reset / Container Manager reinstall
  Pattern: The correct bring-up order matters:
    1. Container Manager package
    2. git clone + init-nas.sh (creates STACK_ROOT dirs)
    3. Dockge host container (rc.d script, 5571:5001)
    4. acme-sh stack (issue ALL certs before any TLS consumer)
    5. traefik-ots / traefik-mft (AFTER certs, BEFORE services)
    6. All other stacks
  Failure mode: Deploying Traefik before certs = self-signed fallback.
    Deploying HAProxy before certs = startup failure (no cert specified).

Pattern 2: dockge-port-mapping.md
  Title: Dockge Container Port Mapping
  Context: louislam/dockge:1 image
  Pattern: The Dockge image listens on port 5001 internally.
    Host mapping must be 5571:5001 NOT 5571:5571.
    Symptom of wrong mapping: "connection dropped" in browser.
    Fix: stop/rm container, re-run startup script.
    Verification: docker inspect Dockge --format '{{json .HostConfig.PortBindings}}'
    Must show: {"5001/tcp":[{"HostIp":"0.0.0.0","HostPort":"5571"}]}

Pattern 3: haproxy-certs-dir.md
  Title: HAProxy TLS Certificate Directory Rules
  Context: haproxy bind *:443 ssl crt <directory>
  Pattern: When using a directory for crt, HAProxy reads EVERY
    non-hidden file as a PEM bundle. Any non-PEM file (README.txt,
    .gitkeep with content, etc.) causes "no start line" error.
    Rules:
      - Only .pem files in the certs/ directory
      - Each .pem must be fullchain + privkey concatenated
      - .gitkeep (0 bytes, hidden) is safe — HAProxy skips hidden files
      - README.txt is NOT safe — causes parse failure
    Build bundle: cat fullchain.pem privkey.pem > hostname.pem

Pattern 4: router-rpcbind-nfs.md
  Title: Router rpcbind Persists After NFS Disable
  Context: ASUS GT-AXE16000, Synology NFSD service
  Pattern: Disabling NFSD stops port 2049 but NOT port 111 (rpcbind).
    rpcbind runs independently and cannot be stopped via the UI.
    Must block via iptables on the WAN interface.
    Persistent rule location: /jffs/scripts/firewall-start
    Requires: JFFS custom scripts enabled in router Administration -> System.

======================================================================
FINAL PRINT
======================================================================

Print:
  REPO-REVIEW: COMPLETE
