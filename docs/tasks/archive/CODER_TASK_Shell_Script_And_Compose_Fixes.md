> **Status:** ✅ SUPERSEDED / ARCHIVED — 2026-05-10

# Coder Task: Shell Script and Compose File Bug Fixes

**Created by:** Gordon (code review)  
**Assignee:** @coder  
**Priority:** CRITICAL  
**Status:** Ready for Implementation  
**Est. Time:** 2-3 hours  

---

## Executive Summary

Gordon's codebase review identified **12 bugs** across shell scripts and compose files, ranging from critical security/reliability issues to portability problems. This task consolidates all fixes into executable phases.

**Outcome:** Production-ready scripts that pass `shellcheck`, portable compose files, and improved deployment reliability.

---

## Bugs Found and Fixes Required

### TIER 1: Critical (Do First)

#### 1.1 — Remove Hardcoded NAS IPs from Compose Ports

**Files:**
- `stacks/codex-docs/compose.yaml` line ~52
- `stacks/databases/compose.yaml` line ~68

**Problem:** Binding containers to `10.0.1.15` breaks local dev, multi-NAS setups, and Mac testing. Traefik/HAProxy handle routing; Compose should not hard-wire IPs.

**Current:**
```yaml
ports:
  - 10.0.1.15:8896:3000
```

**Fixed:**
```yaml
ports:
  - "8896:3000"
```

**Verification:** Compose file still validates; port is published on all interfaces.

---

#### 1.2 — Fix Unquoted GIT_SSH_COMMAND in `scripts/nas-reset.sh`

**File:** `scripts/nas-reset.sh` line ~39

**Problem:** Double quotes allow word-splitting if path contains spaces; SSH key becomes inaccessible.

**Current:**
```bash
export GIT_SSH_COMMAND="ssh -i /var/services/homes/laolufayese/.ssh/id_ed25519 -o StrictHostKeyChecking=no"
```

**Fixed:**
```bash
export GIT_SSH_COMMAND='ssh -i /var/services/homes/laolufayese/.ssh/id_ed25519 -o StrictHostKeyChecking=no'
```

**Verification:** `shellcheck -x scripts/nas-reset.sh` should report no SC2086 on this line.

---

#### 1.3 — Add Error Handling to Image Pull in `scripts/dockge-start.sh`

**File:** `scripts/dockge-start.sh` line ~32

**Problem:** Silent image pull failures leave stale/broken images; container starts with old code or fails mysteriously.

**Current:**
```bash
$DOCKER pull "$IMAGE"
```

**Fixed:**
```bash
$DOCKER pull "$IMAGE" || { echo "ERROR: Failed to pull $IMAGE" >&2; exit 1; }
```

**Verification:** Manually disconnect from network, run script, confirm it fails with clear error message.

---

#### 1.4 — Fix Unsafe Perl Regex in `scripts/validate-haproxy-proposal.sh`

**File:** `scripts/validate-haproxy-proposal.sh` line ~76

**Problem:** Non-capturing group `(?:...)` requires proper flags; regex may silently fail or produce malformed config.

**Current:**
```bash
perl -0777 -pe 's/\nring httplog\n(?:[ \t].*\n)+/\n/s' >"${TMP}/haproxy.cfg"
```

**Fixed (Option A — add flag):**
```bash
perl -0777 -pe 's/\nring httplog\n(?:[ \t].*\n)+/\n/gs' >"${TMP}/haproxy.cfg"
```

**Fixed (Option B — use portable sed):**
```bash
sed -e '/^[[:space:]]*ring httplog$/,/^$/{ /^$/!d; }' "${cfg}" >"${TMP}/haproxy.cfg"
```

**Verification:** Run validation script; `haproxy -c` should pass without errors.

---

#### 1.5 — Fix Race Condition in `scripts/dockge-start.sh`

**File:** `scripts/dockge-start.sh` main logic

**Problem:** Concurrent restarts can spawn duplicate containers if Docker state changes between checks. Two `docker run` commands execute simultaneously.

**Current:** No synchronization between `exists()`, `dockge_port_map_ok()`, and `create_container()`.

**Fixed:** Add lock mechanism before container logic:

```bash
# Add after set -e at script top
LOCK_FILE="/tmp/dockge-start.lock"

# Add before main container check (after docker pull)
if ! mkdir "${LOCK_FILE}" 2>/dev/null; then
	echo "dockge-start: locked by another instance; aborting" >&2
	exit 0  # Exit cleanly; another copy is running
fi
trap 'rmdir "${LOCK_FILE}" 2>/dev/null' EXIT
```

**Verification:** Start two `dockge-start.sh` processes in parallel; confirm only one creates/updates container, other exits 0 with lock message.

---

### TIER 2: Medium (Fix After Tier 1)

#### 2.1 — Fix Missing Null-Terminator in `scripts/fix-permissions.sh`

**File:** `scripts/fix-permissions.sh` line ~56

**Problem:** Standard newline-separated output breaks on directory names with embedded newlines (rare but possible). No error if `find` returns nothing.

**Current:**
```bash
while IFS= read -r stack_dir; do
	...
done < <(find "${STACKS_ROOT}" -maxdepth 1 -mindepth 1 -type d)
```

**Fixed:**
```bash
while IFS= read -r -d '' stack_dir; do
	echo "  → ${stack_dir}"
	chown -R 0:0 "${stack_dir}"
	find "${stack_dir}" -type d -exec chmod 755 {} \;
	find "${stack_dir}" -type f -exec chmod 644 {} \;
done < <(find "${STACKS_ROOT}" -maxdepth 1 -mindepth 1 -type d -print0)
```

Also add early safety check:
```bash
if [[ ! -d "${STACKS_ROOT}" ]]; then
	echo "ERROR: ${STACKS_ROOT} does not exist. Run init-nas.sh first." >&2
	exit 1
fi
```

**Verification:** Test with directory names containing spaces and special chars; `shellcheck` should pass.

---

#### 2.2 — Consistently Quote Variables in `scripts/nas-reset.sh`

**File:** `scripts/nas-reset.sh` throughout (lines ~67, 82, 119, 142, etc.)

**Problem:** Unquoted vars in echo and assignments can word-split if paths contain spaces.

**Examples to fix:**

Line 67:
```bash
# Current
echo "  This will MOVE $DOCKGE_DIR to a timestamped backup"

# Fixed
echo "  This will MOVE ${DOCKGE_DIR} to a timestamped backup"
```

Line 82:
```bash
# Current
mv "$BACKUP_DIR" "$DOCKGE_DIR" || fail "mv failed — aborting before clone"

# Fixed (already correct; verify all similar lines use quotes)
mv "${BACKUP_DIR}" "${DOCKGE_DIR}" || fail "mv failed — aborting before clone"
```

Line 119:
```bash
# Current
echo "==> Cloning $REPO_URL → $DOCKGE_DIR"

# Fixed
echo "==> Cloning ${REPO_URL} → ${DOCKGE_DIR}"
```

**Verification:** `shellcheck -x scripts/nas-reset.sh` should report zero SC2086 warnings.

---

#### 2.3 — Fix Unsafe Find Loop in `scripts/restore-env.sh`

**File:** `scripts/restore-env.sh` line ~108

**Problem:** Unquoted `$ENV_FILES` word-splits on whitespace; filenames with spaces or newlines break the loop.

**Current:**
```bash
ENV_FILES=$(find "$BACKUP_DIR" -name ".env")

# ... later ...

for src in $ENV_FILES; do
	label="${src#"$BACKUP_DIR"/}"
	...
done
```

**Fixed:**
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

**Alternative (bash-safe):**
```bash
mapfile -t -d '' ENV_FILES < <(find "$BACKUP_DIR" -name ".env" -print0)

for src in "${ENV_FILES[@]}"; do
	...
done
```

**Verification:** Create `.env` files with spaces in path; confirm script processes them correctly.

---

#### 2.4 — Fix Cleanup Trap in `scripts/compose-validate.sh`

**File:** `scripts/compose-validate.sh` lines ~50-57

**Problem:** Bash-only array syntax `[@]+` is not POSIX-portable. Cleanup runs even on early exit; env files deleted before validation completes.

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

**Fixed:**
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

**Verification:** Run in CI; confirm dummy env files are removed only after `docker compose config` completes.

---

### TIER 3: Polish and Verification

#### 3.1 — Run ShellCheck and Fix All Warnings

**Command:**
```bash
shellcheck -x scripts/*.sh
```

**Expected issues to fix:**

| Code | Example | Fix |
| --- | --- | --- |
| **SC2086** | `echo $var` (unquoted) | Use `"$var"` or `${var}` |
| **SC2015** | `[ $x ] && [ $y ] \|\| z` | Wrap in `if` block for clarity |
| **SC2012** | `ls \| grep` | Use `find` directly |

**Action Items:**
1. Run shellcheck on all scripts.
2. Fix all `error`-level issues.
3. Document `info`-level suppressions with `# shellcheck disable=SCXXXX` when necessary.

**Verification:**
```bash
shellcheck -x scripts/*.sh 2>&1 | grep -i error
# Should output: (nothing)
```

---

#### 3.2 — (Optional) Add `.env` Validation for Circular References

**File:** `scripts/restore-env.sh` function `process_env()`

**Enhancement:** Flag unresolved variable expansions (e.g., `KEY=${UNDEFINED}`).

**Code to add (after line validation):**
```bash
if printf '%s' "$val" | grep -q '\${'; then
	printf '  WARN line %3d: unresolved variable expansion → %s\n' "$lineno" "$val"
fi
```

**Note:** This is informational only; do not block restore on it.

---

## Implementation Steps

### Phase 1: Critical Fixes (Tier 1)

1. ✅ Edit `stacks/codex-docs/compose.yaml` — remove IP from ports
2. ✅ Edit `stacks/databases/compose.yaml` — remove IP from ports
3. ✅ Edit `scripts/nas-reset.sh` — quote `GIT_SSH_COMMAND`
4. ✅ Edit `scripts/dockge-start.sh` — add error handling to pull + add lock
5. ✅ Edit `scripts/validate-haproxy-proposal.sh` — fix Perl regex
6. ✅ Commit with message: `fix: harden shell scripts and remove hardcoded IPs`

### Phase 2: Medium Fixes (Tier 2)

7. ✅ Edit `scripts/fix-permissions.sh` — add `-print0` and null terminator
8. ✅ Edit `scripts/nas-reset.sh` — consistently quote all variables
9. ✅ Edit `scripts/restore-env.sh` — fix find loop and trap
10. ✅ Edit `scripts/compose-validate.sh` — fix array syntax and trap
11. ✅ Commit with message: `fix: improve shell script robustness and portability`

### Phase 3: Verification (Tier 3)

12. ✅ Run `shellcheck -x scripts/*.sh` locally
13. ✅ Fix all reported errors
14. ✅ Commit with message: `fix: resolve shellcheck warnings`
15. ✅ Run `scripts/compose-validate.sh` to confirm no regressions
16. ✅ Run `scripts/verify-repo-layout.sh` to confirm no regressions
17. ✅ Final commit with message: `chore: verification complete — all shell scripts hardened`

---

## Testing and Verification

### Local Testing (before committing)

```bash
# 1. Lint all scripts
shellcheck -x scripts/*.sh

# 2. Validate compose files
bash scripts/compose-validate.sh

# 3. Verify repo layout
bash scripts/verify-repo-layout.sh

# 4. Test init-nas.sh (list mode, no changes)
bash scripts/init-nas.sh --list-expected-dirs

# 5. Check for obvious syntax errors
bash -n scripts/*.sh
```

### NAS Testing (after approval, staging only)

```bash
# 1. Clone this branch on NAS
cd /volume1/docker
git clone -b <branch> git@github.com:ofayese/dockge-ots.git dockge-test

# 2. Test init-nas.sh
cd dockge-test
sudo bash scripts/init-nas.sh --list-expected-dirs | head -10

# 3. Test fix-permissions.sh
sudo bash scripts/fix-permissions.sh /volume1/docker/dockge/stacks

# 4. Test dockge-start.sh (in dry-run mode or with no-op)
DOCKGE_ROOT=/tmp/test-dockge bash scripts/dockge-start.sh
```

---

## Files Modified

| File | Changes | Lines | Tier |
| --- | --- | --- | --- |
| `stacks/codex-docs/compose.yaml` | Remove IP from ports | ~52 | 1 |
| `stacks/databases/compose.yaml` | Remove IP from ports | ~68 | 1 |
| `scripts/nas-reset.sh` | Quote vars, sign GIT_SSH_COMMAND | ~39, 67, 82, 119, 142+ | 1, 2 |
| `scripts/dockge-start.sh` | Add error handling + lock | ~32, ~5-10 | 1 |
| `scripts/validate-haproxy-proposal.sh` | Fix Perl regex | ~76 | 1 |
| `scripts/fix-permissions.sh` | Add null-terminator + early check | ~45, ~56 | 2 |
| `scripts/restore-env.sh` | Fix find loop + trap | ~108, ~50 | 2 |
| `scripts/compose-validate.sh` | Fix array syntax + trap | ~50-57 | 2 |
| **All scripts** | Shellcheck fixes | varies | 3 |

---

## Success Criteria

- ✅ `shellcheck -x scripts/*.sh` returns zero errors
- ✅ `scripts/compose-validate.sh` exits 0
- ✅ `scripts/verify-repo-layout.sh` exits 0
- ✅ Hardcoded IPs removed from compose files
- ✅ All shell scripts use consistent quoting and null-safe loops
- ✅ Error handling added to critical paths (pull, lock)
- ✅ No new secrets or unquoted paths introduced in diffs

---

## Rollback Plan

All changes are backward-compatible. If a fix causes a regression:

```bash
# Revert single file
git checkout HEAD -- <file>

# Revert entire commit
git revert <commit-hash>
```

**Impact:** Minimal. Changes are defensive (error handling, safer loops, portability). Existing behavior is preserved.

---

## References

- **ShellCheck Docs:** https://www.shellcheck.net/
- **Bash Strict Mode:** http://redsymbol.net/articles/unofficial-bash-strict-mode/
- **POSIX Shell:** https://pubs.opengroup.org/onlinepubs/9699919799/

---

## Notes

- **Do not commit secrets** (CF_Token, SSH keys, passwords) — `.env` files stay local.
- **Test on Mac** if possible — macOS `sed`/`grep` differ from GNU versions.
- **NAS testing is optional** — local shellcheck + compose validate should be sufficient for approval.
- **Estimated time:** 2–3 hours including testing and shellcheck fixes.

Delegate to `@coder` when ready.
