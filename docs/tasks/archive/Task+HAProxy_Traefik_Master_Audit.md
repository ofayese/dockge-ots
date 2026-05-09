<!--
SUPERSEDED — archived 2026-05-10
All phases verified complete. See AGENTS.md ## What Works for outcomes.
This file is retained for historical reference only.
Consolidated into: docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md
-->

### Task: HAProxy & Traefik: Master Audit, Config Generation, and Deployment
### Version: 2026-05-10-combined-canonical
### Target: Synology DSM HAProxy Package & Traefik Stacks
/coder /compound-learning-project-memory /continuous-learning

### ======================================================================
### AGENT ASSIGNMENTS
- **Queen Agent (Cursor/Coder):** Executes Phases 0 through 8 (repository audit, config generation, SAN auditing, runbook authoring, and commit preparation).
- **NAS Operator (Human):** Executes Phase 9 (applying config on Synology NAS and reloading the package).

### ======================================================================
### CONTEXT
This is the unified end-to-end macro for validating HAProxy canonical config against the M5 spec, scanning Traefik service inventory, auditing certificate SANs, automating safe repo-wide fixes, and generating the NAS operator runbook.
Detailed command examples and longer templates are kept in:
`docs/tasks/OAuth Automation, Repo Audit & NAS Deploymen.md` (supporting detail doc).

**Strict Constraints:**
- **No per-service DNS:** Stick to wildcard `*.ots.olutechsys.com` and `*.mft.olutechsys.com` CNAMEs.
- **No OAuth stack creation:** Repository remains at the strict 24 canonical stacks.
- **No wholesale HAProxy rewrite:** Audit `stacks/_haproxy/haproxy.cfg` and propose targeted fixes only.

### ======================================================================
### PHASE 0 — PRE-FLIGHT VALIDATION
**Objective:** Verify repository readiness and read canonical docs.  
**Reads:** `HIVE_OBJECTIVE.md`, `AGENTS.md`, `stacks/_haproxy/README.md`, `stacks/_haproxy/haproxy.cfg`, `docs/hive/NAS_DEPLOYMENT.md`

**Actions:**
1. Verify git state is reviewed and intentional (`git status --short` inspected).
2. Verify compose structure is valid (`bash scripts/compose-validate.sh`).
3. Ensure canonical HAProxy and Traefik files exist and are readable.

**Failure Action:** Abort and fix prerequisites before continuing.

### ======================================================================
### PHASE 1 — SCAN SERVICE INVENTORY & DOMAIN MAPPINGS
**Objective:** Build canonical service-to-domain mapping from compose files.

**Actions:**
1. Scan `stacks/*/compose.yaml` for service names, published ports, and Traefik routing labels (`rule=Host(...)`).
2. Extract subdomain routing and validate domain patterns against wildcard SAN policy.
3. Build CSV map `<subdomain> -> <backend-name> -> <IP:Port>`, ensuring backend IPs target `10.0.1.15`.
4. Store at: `stacks/_haproxy/.metadata/service-inventory.csv`.

### ======================================================================
### PHASE 2 — GENERATE HAPROXY HOST.MAP
**Objective:** Create/update host-to-backend mapping file.

**Actions:**
1. Read `stacks/_haproxy/.metadata/service-inventory.csv`.
2. Update `stacks/_haproxy/maps/host.map` with lowercase FQDNs mapped to backend names, tab-separated (example: `dockge.ots.olutechsys.com    dockge-be`).

### ======================================================================
### PHASE 3 — AUDIT & PROPOSE HAPROXY CONFIG FIXES
**Objective:** Validate `stacks/_haproxy/haproxy.cfg` against `HIVE_OBJECTIVE.md` M5 requirements. Do not rewrite wholesale.

**Actions:**
1. Audit for M5 spec:
   - `timeout client 30s`
   - `timeout server 30s`
   - `timeout connect 5s`
   - `option forwardfor if-none`
   - `http-request set-header X-Forwarded-Proto https`
   - Backends target `10.0.1.15:<port>`
2. If gaps are found, document them in the existing repo audit report section for HAProxy fixes (`docs/hive/REPO_AUDIT_REPORT.md`) with current state, targeted change, and rationale.

### ======================================================================
### PHASE 4 — CERTIFICATE HYGIENE & SAN AUDIT
**Objective:** Ensure `stacks/_haproxy/certs/` contains valid PEM inputs and SANs are compliant.

**Actions:**
1. Verify `stacks/_haproxy/certs/` contains no `.txt` or `.md` files (avoids HAProxy `[ALERT] no start line`).
2. Move operator notes to `stacks/_haproxy/README.txt`.
3. Document missing/expiring certs and SAN gaps for NAS operator renewal via `acme-sh`.

### ======================================================================
### PHASE 5 — REPOSITORY AUDIT & SAFE AUTO-FIX
**Objective:** Scan repository for policy compliance and auto-correct where safe.

**Actions:**
1. Validate 24-stack manifest parity against `AGENTS.md` and `scripts/init-nas.sh`.
2. Check for missing `.env.example` and accidentally tracked `.env` secrets.
3. Validate networking policy:
   - No `192.168.x.x` subnets in compose files.
   - Declared custom `networks:` blocks include explicit `name:`.
4. Auto-fix literal YAML booleans (`true`/`false`) in `environment:` only where semantically safe to `1`/`0`.
5. Run `bash scripts/compose-validate.sh` for integrity confirmation.

### ======================================================================
### PHASE 6 — GENERATE NAS OPERATOR RUNBOOK
**Objective:** Create deployment instructions for NAS operator.

**Actions:**
1. Create/update `stacks/_haproxy/README_NAS_DEPLOYMENT.md`.
2. Include `.pem` bundling step:
   - `cat fullchain.pem privkey.pem > cert.pem`
3. Include strict validation command:
   - `sudo /volume1/@appstore/haproxy/sbin/haproxy -c -f /volume1/@appdata/haproxy/haproxy.cfg`
4. Include package restart command:
   - `sudo synopkg restart haproxy 2>/dev/null`

### ======================================================================
### PHASE 7 — GENERATE FINAL AUDIT REPORT
**Objective:** Consolidate findings into one executive summary.

**Actions:**
1. Update `docs/hive/REPO_AUDIT_REPORT.md` with phase statuses (`✅/⚠️/❌`), identified issues, and required operator actions.

### ======================================================================
### PHASE 8 — VALIDATION & COMMIT (QUEEN AGENT FINAL)
**Actions:**
1. Run `pre-commit run --files <changed-files-only>`.
2. Stage generated audit artifacts, updated `host.map`, and safe auto-fixed compose files.
3. Commit:
   - `git commit -m "feat(proxy): haproxy/traefik audit, host.map generation, and repo validation"`
   - include trailer: `Co-authored-by: Cursor <cursoragent@cursor.com>` when required by workflow.
4. Stop here. Do not simulate NAS execution.

### ======================================================================
### PHASE 9 — NAS DEPLOYMENT (NAS OPERATOR)
*(Executed by human operator on NAS after Queen Agent commits are available)*

1. **Pull changes safely:**
   - `cd /volume1/docker/dockge && find .git/refs -name "*eaDir*" | xargs rm -f 2>/dev/null; git pull --no-rebase`
2. **Build PEM bundles:** Follow `README_NAS_DEPLOYMENT.md` to populate `stacks/_haproxy/certs/`.
3. **Validate HAProxy:**
   - `sudo /volume1/@appstore/haproxy/sbin/haproxy -c -f /volume1/@appdata/haproxy/haproxy.cfg`
4. **Reload HAProxy:**
   - `sudo synopkg restart haproxy`
5. **Test edge connectivity:** Verify HTTPS routing via Traefik and HAProxy endpoints.

### ======================================================================
### FINAL PRINT
HAPROXY-TRAEFIK-MASTER-AUDIT: COMPLETE