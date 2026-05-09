> **Status:** ✅ SUPERSEDED / ARCHIVED — 2026-05-10

# Code Review Summary — Gordon's Findings

**Reviewer:** Gordon (Docker AI assistant)  
**Date:** 2026-05-10  
**Scope:** Shell scripts + Docker Compose files  
**Result:** 12 bugs identified; task created for fixes  

---

## Quick Reference: All 12 Bugs

### Tier 1 — Critical (5 bugs)
1. **Hardcoded NAS IPs** in compose ports → breaks portability
2. **Unquoted `GIT_SSH_COMMAND`** in `nas-reset.sh` → word-splitting risk
3. **Silent image pull failure** in `dockge-start.sh` → broken containers
4. **Unsafe Perl regex** in `validate-haproxy-proposal.sh` → malformed config
5. **Race condition** in `dockge-start.sh` → duplicate containers

### Tier 2 — Medium (4 bugs)
6. **Missing null-terminator** in `fix-permissions.sh` → breaks on special filenames
7. **Unquoted variables** in `nas-reset.sh` → inconsistent quoting
8. **Unsafe find loop** in `restore-env.sh` → fails on spaces in paths
9. **Bash-only array syntax** in `compose-validate.sh` → non-portable

### Tier 3 — Polish (3 items)
10. **ShellCheck warnings** across all scripts
11. (Optional) `.env` circular reference detection
12. (Documentation) Update comments on portability

---

## Files to Fix

| Category | File | Issue | Fix |
| --- | --- | --- | --- |
| Compose | `stacks/codex-docs/compose.yaml` | Hardcoded IP in ports | Remove IP |
| Compose | `stacks/databases/compose.yaml` | Hardcoded IP in ports | Remove IP |
| Script | `scripts/nas-reset.sh` | Unquoted vars + `GIT_SSH_COMMAND` | Quote all; use `'...'` |
| Script | `scripts/dockge-start.sh` | Silent pull fail + race condition | Add error + lock |
| Script | `scripts/validate-haproxy-proposal.sh` | Unsafe Perl regex | Add flags or use sed |
| Script | `scripts/fix-permissions.sh` | Missing null-terminator | Add `-print0` |
| Script | `scripts/restore-env.sh` | Unsafe find loop + trap | Use `read -d ''` |
| Script | `scripts/compose-validate.sh` | Bash-only array syntax | Use standard syntax |

---

## Implementation

**Task File:** `docs/tasks/CODER_TASK_Shell_Script_And_Compose_Fixes.md`

**Phases:**
1. **Tier 1** (5 fixes) — 30 min
2. **Tier 2** (4 fixes) — 60 min
3. **Tier 3** (shellcheck) — 30 min
4. **Testing** — 30 min

**Total Time:** ~2–3 hours

---

## Status

✅ **Code review complete**  
✅ **Task file created** → `docs/tasks/CODER_TASK_Shell_Script_And_Compose_Fixes.md`  
⏳ **Awaiting delegation to `@coder`**

---

## Key Takeaways

- **Portability matters:** Compose should not hard-wire IPs; macOS `sed` differs from GNU.
- **Shell hardening:** Use `set -e`, quote variables consistently, test with `shellcheck`.
- **Error handling:** Silent failures (image pull, file operations) cause mysterious bugs later.
- **Synchronization:** Concurrent script execution needs locks to prevent race conditions.

---

## Next Steps

1. Review task file: `docs/tasks/CODER_TASK_Shell_Script_And_Compose_Fixes.md`
2. Delegate to `@coder` with: `"Please implement the fixes in the task file. Start with Tier 1, then Tier 2, then verify with shellcheck."`
3. After implementation, run verification commands (see task file testing section).
4. Merge to `main` after passing all checks.
