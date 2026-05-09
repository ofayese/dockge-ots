<!--
SUPERSEDED — archived 2026-05-10
All phases verified complete. See AGENTS.md ## What Works for outcomes.
This file is retained for historical reference only.
Consolidated into: docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md
-->

---
title: "Coder Task: Apply Increment-Safety Pattern to Remaining Counter Blocks"
type: "follow-up"
parent_task: "Bug Verification & Fixes: docs/tasks/OAuth Automation, Repo Audit & NAS Deploymen.md"
depends_on: ["docs/tasks/OAuth Automation, Repo Audit & NAS Deploymen.md"]
status: "pending"
priority: "medium"
---

# Coder Task: Harden Counter Increments Across All Shell Scripts

## Context

4 critical bugs were verified and fixed in `docs/tasks/OAuth Automation, Repo Audit & NAS Deploymen.md`:

1. ✅ **HAProxy template invalid syntax** — Replaced nginx-style `map` with valid HAProxy dynamic routing
2. ✅ **Quoted heredoc prevented `$(date)` expansion** — Removed quotes to allow variable expansion
3. ✅ **`set -e` + post-increment exits script** — Replaced `((X++))` with `((X+=1))`
4. ✅ **`df` percent value compared as integer** — Stripped `%` before numeric comparison

**Validation completed:**
- All 4 buggy patterns removed from the file
- ReadLints diagnostic run — no errors
- File is now linter-clean

---

## Objective

Apply the increment-safety pattern (`((COUNTER+=1))` instead of `((COUNTER++))`) to remaining shell snippets that run under `set -e`.

**Scope:** task docs and related markdown runbooks that contain executable shell blocks.
**Coordination note:** this task is a focused follow-up under `docs/tasks/CONSOLIDATED_REMAINING_WORK.md`; use that file for shared pre-flight, validation, and commit flow.

---

## Why This Matters

Under `set -e`, arithmetic commands can terminate a script when they evaluate to `0`.

```bash
set -e

COUNT=0
((COUNT++))   # expression value is 0 -> exit status 1 -> script can exit unexpectedly

((COUNT+=1))  # expression value is 1 (or greater) -> exit status 0 in normal counter use
```

For counter increments in fail-fast scripts, `+=1` avoids the zero-value trap of post-increment.

---

## Files to Scan & Harden

**Primary targets (task docs with shell scripts):**

1. `docs/tasks/OAuth Automation, Repo Audit & NAS Deploymen.md`
   - Status: ✅ Already fixed (4 instances)
   - Verify: No remaining `((...++))` patterns exist

2. `docs/tasks/Task+HAProxy_Traefik_Master_Audit.md`
   - Scan Phase 1, 4, 5, 7, 8, 9, 10 for any counter blocks
   - Find & replace: `((X++))` → `((X+=1))`

3. `docs/tasks/CODER_TASK_Execute_HAProxy_Audit_Phases_0-11.md`
   - Scan for any shell scripts with counters
   - Apply same pattern if found

4. `HAProxy_Traefik_Audit_Macro_REVISED.md` (if tracked/finalized)
   - Scan all Phase code blocks
   - Harden any `((...++))` patterns

**Secondary targets (any other markdown docs with shell snippets):**
```bash
rg -n '\(\([A-Za-z_][A-Za-z0-9_]*\+\+\)\)' docs/tasks docs/hive
```

---

## Search Pattern

Use this to find post-increment arithmetic expressions:

```regex
\(\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\+\+\s*\)\)
```

Then manually replace each match with:

```bash
(($VAR+=1))
```

Manual verification is required: only change true counter increments in `set -e` script paths.

---

## Execution Steps

### Step 1: Identify remaining post-increment patterns
```bash
rg -n '\(\([A-Za-z_][A-Za-z0-9_]*\+\+\)\)' docs/tasks docs/hive
```

### Step 2: For each match, verify context
- Is it inside a `set -e` block?
- Is it a loop counter, error counter, or pass/fail counter?
- Would replacing with `+=1` make sense?

### Step 3: Apply fix
```bash
# Example in docs/tasks/Task+HAProxy_Traefik_Master_Audit.md Phase 7:
# OLD: ((COMPOSE_ERRORS++))
# NEW: ((COMPOSE_ERRORS+=1))
```

### Step 4: Validate
```bash
rg -n '\(\([A-Za-z_][A-Za-z0-9_]*\+\+\)\)' docs/tasks docs/hive
# Expected: no matches in the sections you hardened.
```

### Step 5: Complete through consolidated flow

> Superseded: the previous standalone commit procedure in this file.

This follow-up does not define a separate commit flow.
Use `docs/tasks/CONSOLIDATED_REMAINING_WORK.md` for final validation and commit sequencing.

---

## Success Criteria

- [ ] All 4 bug patterns verified removed from OAuth doc
- [ ] Task + Master Audit docs scanned for remaining `((...++))`
- [ ] All found instances replaced with `((X+=1))`
- [ ] Heredocs use unquoted `EOF` (not `'EOF'`)
- [ ] Markdown remains readable after edits
- [ ] Final validation handled via consolidated task flow

---

## Verification Checklist

After completion, run:

```bash
# 1. No post-increments remain in task docs
rg -n '\(\([A-Za-z_][A-Za-z0-9_]*\+\+\)\)' docs/tasks docs/hive

# 2. All heredocs properly quoted (unquoted EOF)
rg -n "cat > .* << 'EOF'" docs/tasks docs/hive

# 3. Quick placeholder sanity check near edited docs
rg -n 'TODO|TBD' docs/tasks/CODER_TASK_Harden_Counter_Increments_Set_E.md docs/tasks/CONSOLIDATED_REMAINING_WORK.md
```

---

## Notes

- **Why not just `set +e` + manual error handling?**  
  `set -e` is safer for task automation — we want scripts to fail fast on unexpected errors.

- **Edge case:** If a counter is legitimately used in a boolean context (e.g., `if ((COUNT++))`), consider refactoring to `if ((COUNT>0))` or similar.

- **Future prevention:** Add to PR checklist: "All shell blocks under `set -e` use `+=` for counters, not `++`."

---

## References

- **Original bug fixes:** `docs/tasks/OAuth Automation, Repo Audit & NAS Deploymen.md` (4 bugs verified ✅)
- **Bash `set -e` behavior:** https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
- **Counter safety patterns:** Bash arithmetic evaluation returns the value of expression; post-increment can be tricky under `set -e`

---

**Task Status:** ◻️ PENDING (managed through consolidated remaining work flow)  
**Assigned To:** Cursor Agent  
**Created:** 2026-05-10  
**Expected Completion:** After scanning + hardening all task docs + commit
