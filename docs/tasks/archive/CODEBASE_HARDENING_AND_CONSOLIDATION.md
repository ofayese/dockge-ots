> **Status:** ✅ SUPERSEDED / ARCHIVED — 2026-05-10

# Unified Task: Codebase Hardening + Consolidation Sprint

**Created:** 2026-05-10  
**Prepared for:** @coder  
**Scope:** Shell script hardening + consolidation work + archiving  
**Estimated Time:** 5-6 hours (all-in-one) OR 2-3 hours (just fixes)  
**Status:** ✅ COMPLETED — 2026-05-10 (Commits: f7cf6f1, ccbd96e)  

---

## Overview

This is a **single, consolidated task file** combining:

1. **Critical code fixes** (12 bugs from Gordon's review) — Tiers 1, 2, 3
2. **Consolidation work** (7 phases from CONSOLIDATED_REMAINING_WORK.md)
3. **Archiving & cleanup** (completed task files)

**Execution Options:**
- **Option A:** Run everything in sequence (recommended) — ~5-6 hours
- **Option B:** Just code fixes first (Tiers 1-3 only) — ~2-3 hours, commit, then consolidation later
- **Option C:** Just consolidation work (skip code fixes) — ~3-4 hours

**This document defaults to Option A (everything).** Pick your path at the start.

---

## Pre-Flight (REQUIRED — Run First)

```bash
cd /Volumes/docker/dockge  # or your clone location

# Verify clean state
git status --short
# Expected: clean or only intentional changes

# Verify no uncommitted hard constraints violations
bash scripts/compose-validate.sh
# Expected: All compose files validated OK

pre-commit run --all-files
# Expected: all hooks pass

# Check initial state of files we'll edit
wc -l scripts/nas-reset.sh scripts/dockge-start.sh \
    scripts/validate-haproxy-proposal.sh \
    scripts/fix-permissions.sh scripts/restore-env.sh \
    scripts/compose-validate.sh
```

If any of these fail, **STOP** and fix before proceeding.

---

## TIER 1: Critical Code Fixes (Do First)

These 5 fixes address **security/reliability issues**. All are low-risk and backward-compatible.

### Fix 1.1 — Remove Hardcoded NAS IPs from Compose Ports

**Files:**
- `stacks/codex-docs/compose.yaml` line ~52
- `stacks/databases/compose.yaml` line ~68

**Current:**
```yaml
ports:
  - 10.0.1.15:8896:3000
```

**Change to:**
```yaml
ports:
  - "8896:3000"
```

**Why:** Hardcoding IPs breaks local dev, Mac testing, and multi-NAS setups. Traefik/HAProxy handle routing.

**Verification:**
```bash
docker compose -f stacks/codex-docs/compose.yaml config -q
docker compose -f stacks/databases/compose.yaml config -q
# Both must succeed with no errors
```

**Commits After Fix:**
```bash
git add stacks/codex-docs/compose.yaml stacks/databases/compose.yaml
git commit -m "fix: remove hardcoded NAS IPs from compose ports"
```

---

### Fix 1.2 — Quote GIT_SSH_COMMAND in scripts/nas-reset.sh

**File:** `scripts/nas-reset.sh` line ~39

**Current:**
```bash
export GIT_SSH_COMMAND="ssh -i /var/services/homes/laolufayese/.ssh/id_ed25519 -o StrictHostKeyChecking=no"
```

**Change to:**
```bash
export GIT_SSH_COMMAND='ssh -i /var/services/homes/laolufayese/.ssh/id_ed25519 -o StrictHostKeyChecking=no'
```

**Why:** Double quotes allow word-splitting if path contains spaces. Single quotes protect the entire string.

**Verification:**
```bash
shellcheck -x scripts/nas-reset.sh | grep -i "SC2086.*GIT_SSH"
# Expected: no output (no SC2086 on this line)
```

---

### Fix 1.3 — Add Error Handling to Image Pull in scripts/dockge-start.sh

**File:** `scripts/dockge-start.sh` line ~32

**Current:**
```bash
$DOCKER pull "$IMAGE"
```

**Change to:**
```bash
$DOCKER pull "$IMAGE" || { echo "ERROR: Failed to pull $IMAGE" >&2; exit 1; }
```

**Why:** Silent failures leave stale/broken images. Fail fast with clear messaging.

**Verification:**
```bash
# Simulate network failure (optional — for real testing)
# Set IMAGE to an invalid tag and run script
# Expected: script exits with "ERROR: Failed to pull..." message
```

---

### Fix 1.4 — Fix Unsafe Perl Regex in scripts/validate-haproxy-proposal.sh

**File:** `scripts/validate-haproxy-proposal.sh` line ~76

**Current:**
```bash
perl -0777 -pe 's/\nring httplog\n(?:[ \t].*\n)+/\n/s' >"${TMP}/haproxy.cfg"
```

**Change to (portable sed version):**
```bash
sed -e '/^[[:space:]]*ring httplog$/,/^$/{ /^$/!d; }' "${cfg}" >"${TMP}/haproxy.cfg"
```

**Or (Perl with explicit flags):**
```bash
perl -0777 -pe 's/\nring httplog\n(?:[ \t].*\n)+/\n/gs' >"${TMP}/haproxy.cfg"
```

**Why:** Non-capturing group syntax requires proper flags; portable sed is safer.

**Verification:**
```bash
bash scripts/validate-haproxy-proposal.sh
# Expected: exits 0 with "validate-haproxy-proposal: OK (canonical cfg + proposal include path)"
```

---

### Fix 1.5 — Fix Race Condition in scripts/dockge-start.sh

**File:** `scripts/dockge-start.sh` main logic

**Problem:** Concurrent restarts spawn duplicate containers. Multiple `docker run` commands can execute simultaneously.

**Solution:** Add lock mechanism. Insert this **after `set -e` at script top** (~line 5):

```bash
# Add after set -e
LOCK_FILE="/tmp/dockge-start.lock"

# Add this block before the main container check (before "if container_exists")
if ! mkdir "${LOCK_FILE}" 2>/dev/null; then
	echo "dockge-start: locked by another instance; aborting" >&2
	exit 0  # Exit cleanly; another copy is running
fi
trap 'rmdir "${LOCK_FILE}" 2>/dev/null' EXIT
```

**Why:** Prevents multiple simultaneous executions creating duplicate containers.

**Verification:**
```bash
# Start two dockge-start.sh processes in background
bash scripts/dockge-start.sh &
bash scripts/dockge-start.sh &
wait
# Expected: one creates/updates, other exits 0 with "locked by another instance"
```

---

### ✅ Commit Tier 1

```bash
git add scripts/nas-reset.sh scripts/dockge-start.sh \
        scripts/validate-haproxy-proposal.sh
git commit -m "fix(critical): harden shell scripts — error handling, locks, quoting"
```

**Verification After Commit:**
```bash
bash scripts/compose-validate.sh
pre-commit run --all-files
# Both must pass
```

---

## TIER 2: Medium Robustness Fixes

These 4 fixes improve **portability and safety** for edge cases.

### Fix 2.1 — Add Null-Terminator to scripts/fix-permissions.sh

**File:** `scripts/fix-permissions.sh` lines ~45-56

**Current:**
```bash
while IFS= read -r stack_dir; do
	echo "  → ${stack_dir}"
	chown -R 0:0 "${stack_dir}"
	find "${stack_dir}" -type d -exec chmod 755 {} \;
	find "${stack_dir}" -type f -exec chmod 644 {} \;
done < <(find "${STACKS_ROOT}" -maxdepth 1 -mindepth 1 -type d)
```

**Change to:**
```bash
while IFS= read -r -d '' stack_dir; do
	echo "  → ${stack_dir}"
	chown -R 0:0 "${stack_dir}"
	find "${stack_dir}" -type d -exec chmod 755 {} \;
	find "${stack_dir}" -type f -exec chmod 644 {} \;
done < <(find "${STACKS_ROOT}" -maxdepth 1 -mindepth 1 -type d -print0)
```

Also add early safety check **before the while loop** (~line 45):

```bash
if [[ ! -d "${STACKS_ROOT}" ]]; then
	echo "ERROR: ${STACKS_ROOT} does not exist. Run init-nas.sh first." >&2
	exit 1
fi
```

**Why:** Protects against directory names with newlines (rare but possible). Adds defensive check.

**Verification:**
```bash
shellcheck -x scripts/fix-permissions.sh
# Expected: no errors
```

---

### Fix 2.2 — Consistently Quote Variables in scripts/nas-reset.sh

**File:** `scripts/nas-reset.sh` throughout (multiple lines)

**Scope:** Replace all unquoted `$VAR` with `${VAR}` in echo and string assignments.

**Examples to fix:**

Line ~67:
```bash
# Before
echo "  This will MOVE $DOCKGE_DIR to a timestamped backup"
# After
echo "  This will MOVE ${DOCKGE_DIR} to a timestamped backup"
```

Line ~119:
```bash
# Before
echo "==> Cloning $REPO_URL → $DOCKGE_DIR"
# After
echo "==> Cloning ${REPO_URL} → ${DOCKGE_DIR}"
```

**Run this to find all instances:**
```bash
grep -n '\$[A-Z_]' scripts/nas-reset.sh | grep -v '\${' | head -20
# Fix each line shown
```

**Why:** Consistent quoting prevents word-splitting if paths contain spaces.

**Verification:**
```bash
shellcheck -x scripts/nas-reset.sh | grep -c "SC2086"
# Expected: 0
```

---

### Fix 2.3 — Fix Unsafe Find Loop in scripts/restore-env.sh

**File:** `scripts/restore-env.sh` line ~108-145

**Current:**
```bash
ENV_FILES=$(find "$BACKUP_DIR" -name ".env")

# ... later ...

for src in $ENV_FILES; do
	label="${src#"$BACKUP_DIR"/}"
	...
done
```

**Change to:**
```bash
find "$BACKUP_DIR" -name ".env" | while read -r src; do
	label="${src#"$BACKUP_DIR"/}"
	dest="$NEW_REPO/$label"
	fixed_copy="${TMPDIR_FIXED}/${label}"
	
	mkdir -p "$(dirname "$fixed_copy")"
	
	if ! process_env "$src" "$fixed_copy"; then
		TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
	fi
done
```

**Why:** Unquoted `$ENV_FILES` word-splits on whitespace; filenames with spaces break the loop.

**Verification:**
```bash
# Test with spaces in .env filename (optional)
touch "/tmp/test .env"
# Run script — must handle gracefully
```

---

### Fix 2.4 — Fix Bash-Only Array Syntax in scripts/compose-validate.sh

**File:** `scripts/compose-validate.sh` lines ~50-57

**Current:**
```bash
created_env_files=()
cleanup() {
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
		for p in "${created_env_files[@]+"${created_env_files[@]}"}"; do
			rm -f "${p}"
		done
	fi
}
trap cleanup EXIT
```

**Change to:**
```bash
created_env_files=()
cleanup() {
	local status=$?
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
		for p in "${created_env_files[@]}"; do
			[[ -f "${p}" ]] && rm -f "${p}"
		done
	fi
	return ${status}
}
trap cleanup EXIT
```

**Why:** The `[@]+` syntax is Bash-only; also ensures cleanup preserves exit code.

**Verification:**
```bash
bash scripts/compose-validate.sh
# Expected: passes; dummy env files cleaned up after validation
```

---

### ✅ Commit Tier 2

```bash
git add scripts/fix-permissions.sh scripts/nas-reset.sh \
        scripts/restore-env.sh scripts/compose-validate.sh
git commit -m "fix(medium): improve shell script robustness — quoting, null-terminators, array syntax"
```

**Verification After Commit:**
```bash
shellcheck -x scripts/*.sh 2>&1 | grep -i "error"
# Expected: zero errors
bash scripts/compose-validate.sh
# Expected: OK
```

---

## TIER 3: ShellCheck Hardening and Polish

### Fix 3.1 — Run ShellCheck and Fix All Warnings

```bash
# Comprehensive check
shellcheck -x scripts/*.sh > /tmp/shellcheck-report.txt 2>&1
cat /tmp/shellcheck-report.txt
```

**Expected warnings to address:**

| Code | Pattern | Fix |
| --- | --- | --- |
| **SC2086** | `echo $var` (unquoted) | Use `"$var"` |
| **SC2015** | `[ $x ] && [ $y ] \|\| z` | Wrap in `if` |
| **SC2012** | `ls \| grep` | Use `find` directly |
| **SC2211** | `./<script>` | Use `./` notation consistently |

**For each error, apply fix and verify:**

```bash
# Example: fix SC2086 in a specific line
# Before: echo file is $1
# After: echo "file is $1"

# Then re-run shellcheck on just that file
shellcheck -x scripts/<file>.sh
```

**After fixing all errors:**
```bash
shellcheck -x scripts/*.sh
# Expected: no error-level issues
```

---

### ✅ Commit Tier 3

```bash
git add scripts/*.sh
git commit -m "fix(polish): resolve all shellcheck warnings"
```

---

## CONSOLIDATION WORK: Phases 1-5 (from CONSOLIDATED_REMAINING_WORK.md)

These phases handle **documentation, script enhancement, and normalization**. They can run in parallel with code fixes or sequentially afterward.

### PHASE 0 — Consolidation Pre-Flight

**REQUIRED FIRST:**

```bash
# Should all pass already (from Tier 1-3)
bash scripts/compose-validate.sh
pre-commit run --all-files

# Check current state
grep -rn "192\.168\." stacks/*/compose.yaml 2>/dev/null
# Expected: zero matches

grep -rn "networks: {}" stacks/*/compose.yaml 2>/dev/null
# Expected: zero matches

git status --short
# Expected: clean
```

---

### PHASE 1 — docker.sock Comment Normalisation

**Status:** PARTIALLY DONE (verify first)  
**Scope:** 10+ compose files with `/var/run/docker.sock` mounts

**Template System (two-option only):**

For **`:ro` (read-only) mounts**, comment must be:
```yaml
# docker.sock :ro — <service> reads <what> only.
```

For **`:rw` (read-write) mounts**, comment must be:
```yaml
# SECURITY: docker.sock :rw — <reason for full API access>.
```

**Files to check:**
```
stacks/dozzle/compose.yaml
stacks/homepage/compose.yaml
stacks/watchtower/compose.yaml
stacks/portainer/compose.yaml
stacks/code-server/compose.yaml
stacks/traefik-ots/compose.yaml
stacks/traefik-mft/compose.yaml
stacks/grafana-prom/compose.yaml
stacks/agents_gateway_data/compose.yaml
```

**Audit:**
```bash
grep -B2 "/var/run/docker.sock" stacks/*/compose.yaml | grep -v "^\-\-$"
# Review every comment line; ensure it matches one of the two templates exactly
```

**Fix each file:**

For each docker.sock mount, replace the comment line above it with the appropriate template.

**Verification:**
```bash
grep -B2 "/var/run/docker.sock" stacks/*/compose.yaml \
  | grep -v "# docker.sock\|# SECURITY:\|/var/run\|^--$"
# Expected: zero results (all mounts have normalised comment)

bash scripts/compose-validate.sh
# Expected: OK
```

**Commit:**
```bash
git add stacks/*/compose.yaml
git commit -m "chore: normalise docker.sock comments to two-template system"
```

---

### PHASE 2 — README Volume Tables Sweep

**Status:** NOT STARTED  
**Scope:** 8 README files  

**Gold Standard Template** (from `stacks/zabbix/README.md`):

```markdown
## Volumes

| Host path | Container path | Mode | Created by |
|---|---|---|---|
| `${STACK_ROOT}/<stack>/data` | `/app/data` | rw | `init-nas.sh` |
| `${STACK_ROOT}/<stack>/config` | `/etc/<app>` | rw | `init-nas.sh` |

> Run `sudo bash scripts/init-nas.sh` after cloning to create these
> directories. Without them, the container will fail to start.
```

For **stateless stacks** (no volumes):
```markdown
## Volumes

No persistent volumes — stateless.
```

**READMEs to update:**

| File | Action |
| --- | --- |
| `stacks/acme-sh/README.md` | Add/update volume table; use `${STACK_ROOT}` |
| `stacks/grafana-prom/README.md` | Add/update volume table |
| `stacks/databases/README.md` | Add/update volume table |
| `stacks/ollama/README.md` | Add table + tier model docs |
| `stacks/homepage/README.md` | Add/update volume table |
| `stacks/codex-docs/README.md` | Add/update volume table |
| `stacks/warp-main/README.md` | Add "No persistent volumes" |
| `stacks/agents_gateway_data/README.md` | Add docker.sock note |

**Operator Exception (leave as-is, only normalize variables):**
- `stacks/portainer/README.md` — document `PORTAINER_DATA_ROOT` operator path
- `stacks/code-server/README.md` — document `CODE_SERVER_HOST_*` operator paths

**Process for each README:**

1. Open the README and corresponding `compose.yaml`
2. Identify all bind mounts in the compose file
3. Replace any hardcoded `/volume1/docker/dockge/stacks/<stack>/...` with `${STACK_ROOT}/<stack>/...`
4. Add or update the `## Volumes` section using the gold standard format

**Verification:**
```bash
grep -rn "/volume1/docker/dockge/stacks" stacks/*/README.md \
  | grep -v "# EXEMPT\|operator"
# Expected: zero results

bash scripts/compose-validate.sh
# Expected: OK
```

**Commit:**
```bash
git add stacks/*/README.md
git commit -m "chore: normalize README volume tables to use \${STACK_ROOT}"
```

---

### PHASE 3 — Verify DNS Views Script Enhancement

**Status:** VERIFY FIRST  
**File:** `scripts/verify-dns-views.sh`

**Check if --hairpin mode exists:**
```bash
grep -A10 "hairpin" scripts/verify-dns-views.sh
```

**If MISSING or INCOMPLETE, add --hairpin mode that:**

1. Resolves hostname via default resolver (public path)
2. Resolves hostname via `@10.0.1.15` (NAS resolver)
3. Compares results and reports one of:
   - `[HAIRPIN OK]` — both return same IP, OR hairpin working
   - `[SPLIT-DNS ACTIVE]` — NAS returns 10.x.x.x, public returns different
   - `[SPLIT-DNS NEEDED]` — curl fails via public IP path
   - `[REACHABLE via public IP]` — curl succeeds via public IP

**Default hostname:** `otsorundscore.olutechsys.com`

**Implementation example:**
```bash
#!/bin/bash
# ... existing code ...

if [[ "$1" == "--hairpin" ]]; then
    HOSTNAME="${2:-otsorundscore.olutechsys.com}"
    
    PUBLIC_IP=$(dig +short "$HOSTNAME" @8.8.8.8 | tail -1)
    NAS_IP=$(dig +short "$HOSTNAME" @10.0.1.15 | tail -1)
    
    if [ "$PUBLIC_IP" == "$NAS_IP" ]; then
        echo "[HAIRPIN OK] Same public IP from both resolvers"
    else
        echo "[SPLIT-DNS ACTIVE] NAS returns $NAS_IP, public returns $PUBLIC_IP"
    fi
    
    if curl -kI "https://$HOSTNAME" >/dev/null 2>&1; then
        echo "[REACHABLE via public IP]"
    else
        echo "[SPLIT-DNS NEEDED] curl fails via public IP path"
    fi
    exit 0
fi
```

**Verification:**
```bash
bash scripts/verify-dns-views.sh --help | grep hairpin
# Expected: --hairpin documented

bash scripts/verify-dns-views.sh --hairpin otsorundscore.olutechsys.com
# Expected: one of the status messages above
```

**Commit (if changes made):**
```bash
git add scripts/verify-dns-views.sh
git commit -m "feat: add --hairpin comparison mode to verify-dns-views.sh"
```

---

### PHASE 4 — AGENTS.md Bullets Update

**File:** `AGENTS.md`

**Add these dated entries under `## What Works` if not already present:**

```markdown
- [2026-05-10] **Shell script hardening complete:**
  - Tier 1 critical fixes: hardcoded IPs removed, quoting fixed, error handling added, race condition locked
  - Tier 2 robustness fixes: null-terminators, array syntax, variable quoting standardized
  - All scripts pass shellcheck with zero error-level issues
  - Fixes are backward-compatible; no behavior change for end users

- [2026-05-10] **Consolidation work complete:**
  - docker.sock comments normalized to two-template system repo-wide
  - README volume tables use ${STACK_ROOT} placeholder fleet-wide
  - verify-dns-views.sh --hairpin comparison mode added
  - All prior task files archived under docs/tasks/archive/
  - Single entry point: docs/tasks/MASTER_AUDIT_AND_DEPLOY.md

- [2026-05-10] **Code review findings:**
  - Gordon reviewed 8+ shell scripts and 24+ compose files
  - Identified 12 bugs (5 critical, 4 medium, 3 polish)
  - All fixed in this session with no regressions
  - Recommendations: prioritize local testing before NAS deploy
```

**Verification:**
```bash
grep -c "2026-05-10" AGENTS.md
# Expected: 3 (three new dated bullets)
```

**Commit:**
```bash
git add AGENTS.md
git commit -m "docs: update AGENTS.md with consolidation completion bullets"
```

---

### PHASE 5 — Archive Completed Task Files

**Move these files from `docs/tasks/` to `docs/tasks/archive/`:**

```bash
cd docs/tasks/archive

# Files to move (if still in docs/tasks/ — check first)
git mv ../CODER_TASK_Harden_Counter_Increments_Set_E.md . || echo "Already archived"

# Prepend superseded header to the moved file
HEADER="<!--
SUPERSEDED — archived 2026-05-10
All phases verified complete. See AGENTS.md ## What Works for outcomes.
This file is retained for historical reference only.
Consolidated into: docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md
-->

"

# Use sed to prepend (the proper way)
# First, create temp file with header + original content
sed '1s/^/'"$(printf '%s\n' "$HEADER" | sed -e 's/[\/&]/\\&/g')"'/' \
  CODER_TASK_Harden_Counter_Increments_Set_E.md > CODER_TASK_Harden_Counter_Increments_Set_E.md.tmp

mv CODER_TASK_Harden_Counter_Increments_Set_E.md.tmp CODER_TASK_Harden_Counter_Increments_Set_E.md

cd ../
git add docs/tasks/archive/
git commit -m "chore: archive CODER_TASK_Harden_Counter_Increments_Set_E.md with superseded header"
```

**Files to KEEP in `docs/tasks/` (not archived):**
- `MASTER_AUDIT_AND_DEPLOY.md` — periodic re-run template
- `GORDON_CODE_REVIEW_SUMMARY.md` — reference for code review
- `TASK_CONSOLIDATION_AND_ARCHIVE.md` — this consolidation reference

**Verification:**
```bash
ls docs/tasks/ | wc -l
# Should be fewer files after archiving

ls docs/tasks/archive/ | wc -l
# Should have grown
```

**Commit:**
```bash
git add docs/tasks/archive/ docs/tasks/
git commit -m "chore: archive completed task files; keep MASTER_AUDIT_AND_DEPLOY for periodic re-run"
```

---

### PHASE 6 — Final Validation Suite

**Run all verification commands:**

```bash
# 1. Compose validation
bash scripts/compose-validate.sh
# Expected: All compose files validated OK

# 2. Pre-commit hooks
pre-commit run --all-files
# Expected: all hooks pass

# 3. No hardcoded volume paths in READMEs
grep -rn "/volume1/docker/dockge/stacks" stacks/*/README.md \
  | grep -v "# EXEMPT\|operator"
# Expected: zero results

# 4. All docker.sock mounts have normalized comment
grep -B2 "/var/run/docker.sock" stacks/*/compose.yaml \
  | grep -v "# docker.sock\|# SECURITY:\|/var/run\|^--$"
# Expected: zero results

# 5. No 192.168.x subnets
grep -rn "192\.168\." stacks/*/compose.yaml
# Expected: zero results

# 6. No networks: {} remaining
grep -rn "networks: {}" stacks/*/compose.yaml
# Expected: zero results

# 7. Shell script linting
shellcheck -x scripts/*.sh 2>&1 | grep -i "error"
# Expected: zero errors (warnings OK)

# 8. Git clean state
git status --short
# Expected: clean
```

**If any verification fails, STOP and fix before proceeding to commit.**

---

### PHASE 7 — Memory Updates and Final Commit

**Add to compound/continuous learning (optional per your setup):**

If you maintain memory files, add:

```markdown
## Hive Hardening Session 2026-05-10

- Gordon conducted code review: 12 bugs found (5 critical, 4 medium, 3 polish)
- All bugs fixed in single sprint: shell scripts now pass shellcheck, compose portable
- Consolidation work aligned across 7 phases
- Task files archived; single entry point is now MASTER_AUDIT_AND_DEPLOY.md

Key learnings for future:
- Always shellcheck scripts before NAS deploy
- Never hardcode IPs in compose ports
- Lock files prevent concurrent script race conditions
- Find loops need -print0 for safety with special filenames
```

---

### FINAL COMMIT

```bash
git add -A
git commit -m \
  "chore: complete hardening and consolidation sprint
  
  Tier 1 fixes: remove hardcoded IPs, quote GIT_SSH_COMMAND, add error handling,
  fix Perl regex, prevent race condition
  
  Tier 2 fixes: null-terminators, variable quoting, array syntax, find loops
  
  Tier 3 polish: resolve all shellcheck warnings
  
  Consolidation phases:
  - Phase 1: normalize docker.sock comments
  - Phase 2: update README volume tables
  - Phase 3: add --hairpin mode to verify-dns-views.sh
  - Phase 4: update AGENTS.md bullets
  - Phase 5: archive completed task files
  - Phase 6: final validation passing
  
  No breaking changes; all improvements are backward-compatible.
  See GORDON_CODE_REVIEW_SUMMARY.md for detailed findings."

git push origin HEAD:main
```

---

## Execution Checklist

| Phase | Task | Status | Time |
| --- | --- | --- | --- |
| Pre-Flight | Verify environment | ⏳ | 5m |
| Tier 1.1 | Remove hardcoded IPs | ⏳ | 5m |
| Tier 1.2 | Quote GIT_SSH_COMMAND | ⏳ | 5m |
| Tier 1.3 | Add pull error handling | ⏳ | 5m |
| Tier 1.4 | Fix Perl regex | ⏳ | 10m |
| Tier 1.5 | Fix race condition | ⏳ | 10m |
| ✅ Commit Tier 1 | **Verify & commit** | ⏳ | 10m |
| Tier 2.1 | Null-terminators | ⏳ | 10m |
| Tier 2.2 | Quote variables | ⏳ | 15m |
| Tier 2.3 | Find loop safety | ⏳ | 10m |
| Tier 2.4 | Array syntax fix | ⏳ | 10m |
| ✅ Commit Tier 2 | **Verify & commit** | ⏳ | 10m |
| Tier 3 | ShellCheck fixes | ⏳ | 30m |
| ✅ Commit Tier 3 | **Verify & commit** | ⏳ | 10m |
| Phase 0 | Consolidation pre-flight | ⏳ | 10m |
| Phase 1 | docker.sock comments | ⏳ | 30m |
| ✅ Commit Phase 1 | **Verify & commit** | ⏳ | 10m |
| Phase 2 | README volume tables | ⏳ | 90m |
| ✅ Commit Phase 2 | **Verify & commit** | ⏳ | 10m |
| Phase 3 | DNS verify --hairpin | ⏳ | 30-45m |
| ✅ Commit Phase 3 | **Verify & commit** | ⏳ | 10m |
| Phase 4 | AGENTS.md bullets | ⏳ | 15m |
| ✅ Commit Phase 4 | **Verify & commit** | ⏳ | 5m |
| Phase 5 | Archive task files | ⏳ | 10m |
| ✅ Commit Phase 5 | **Verify & commit** | ⏳ | 5m |
| Phase 6 | Validation suite | ⏳ | 20m |
| Phase 7 | Memory updates | ⏳ | 10m |
| **FINAL COMMIT** | **Push to main** | ⏳ | 5m |
| **TOTAL** | | ⏳ | **5-6 hours** |

---

## Execution Options

### Option A: Everything (Recommended)
Run all phases in order as written. ~5-6 hours total. Single large commit or multiple per-phase commits (up to you).

### Option B: Code Fixes Only
Stop after "Commit Tier 3." Skip consolidation work (phases 0-7). This gets critical bugs fixed. ~2-3 hours. Consolidation work can happen in a follow-up session.

### Option C: Just Consolidation
If someone else already fixed the code bugs, skip Tiers 1-3 and start with "PHASE 0 — Consolidation Pre-Flight." ~3-4 hours.

---

## Success Criteria

✅ All shell scripts pass `shellcheck -x` with zero error-level issues  
✅ `scripts/compose-validate.sh` exits 0  
✅ `scripts/verify-repo-layout.sh` exits 0  
✅ Hardcoded IPs removed from compose files  
✅ All docker.sock comments normalized  
✅ All README volume tables use `${STACK_ROOT}`  
✅ `scripts/verify-dns-views.sh --hairpin` works (if modified)  
✅ AGENTS.md updated with completion bullets  
✅ Completed task files archived with superseded headers  
✅ Pre-commit hooks pass  
✅ `git status` clean after final commit  

---

## Rollback Plan

All changes are **backward-compatible**. If something goes wrong:

```bash
# Revert last commit
git reset --soft HEAD~1
git reset -- .
git checkout -- .

# Or revert specific file
git checkout HEAD -- <file>

# Or full revert
git revert <commit-sha>
```

**Impact of rollback:** Minimal. All changes are defensive (error handling, safer patterns, documentation). No behavior change for users.

---

## Questions?

- **Pre-flight issues?** Run each verification command individually; report which one fails.
- **ShellCheck unclear?** Run `shellcheck -f json scripts/<file>.sh` for detailed output.
- **Compose validation fails?** Run `docker compose config -q` on that specific file for error details.
- **Git issues?** Check `git status` and review what files have changed since the last commit.

---

**Ready to delegate to @coder. Pick your execution option (A/B/C) and proceed.**
