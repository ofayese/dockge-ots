> **Status:** ✅ SUPERSEDED / ARCHIVED — 2026-05-10

# Task Consolidation and Archive — 2026-05-10

**Prepared by:** Gordon (code review + task analysis)  
**Purpose:** Archive completed tasks and consolidate incomplete work into current run  
**Status:** Ready for delegation  

---

## Executive Summary

This document consolidates **task lifecycle management** for the dockge-ots repository. It:

1. **Archives completed tasks** → moved to `docs/tasks/archive/` with superseded headers
2. **Identifies incomplete work** → extracted and consolidated into current run
3. **Creates unified task file** → `docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md` (new master task)

**Result:** Single authoritative task file for `@coder` with clear phases, no conflicts, all pending work included.

---

## Current Active Tasks (in `docs/tasks/`)

| File | Status | Type | Action |
| --- | --- | --- | --- |
| `CONSOLIDATED_REMAINING_WORK.md` | 🔄 **IN PROGRESS** | Consolidation | Keep; use for phases 1-5 sequencing |
| `MASTER_AUDIT_AND_DEPLOY.md` | 📋 **Reference** | Audit/deploy | Keep; periodic re-run template |
| `CODER_TASK_Shell_Script_And_Compose_Fixes.md` | 🆕 **NEW** | Code fixes | Keep; prioritize alongside consolidation |
| `CODER_TASK_Harden_Counter_Increments_Set_E.md` | ✅ **COMPLETE** | Counter hardening | Archive with superseded header |
| `GORDON_CODE_REVIEW_SUMMARY.md` | 📝 **Reference** | Summary | Keep; reference for code review findings |
| `OAuth Automation, Repo Audit & NAS Deploymen.md` | ❓ **UNCLEAR** | Unknown | Review and archive if outdated |
| `Task+HAProxy_Traefik_Master_Audit.md` | ❓ **UNCLEAR** | Unknown | Review and archive if outdated |

---

## Archived Tasks (in `docs/tasks/archive/`)

All of these are **complete** and marked with superseded headers:

✅ `CURSOR_SKILLS_ACME_HAPROXY_DOCKGE.md` (2026-05-08)  
✅ `DOCKER_MULTIHOST_OLLAMA_OFFLINE_WORKSPACE.md` (2026-05-08)  
✅ `HAPROXY_DNS_MACRO_GAPS.md` (2026-05-08)  
✅ `HEALTHCHECK_FIXES.md` (2026-05-07)  
✅ `NETWORK_ROUTING_OAUTH_OPTIMIZATION.md` (2026-05-08)  
✅ `NEXT_PHASE_2026_05_07.md` (2026-05-07)  
✅ `OCI_HEALTHCHECK_AUDIT.md` (2026-05-07)  
✅ `OLLAMA_AUTOPULL_HOLYCLAUDE_OFFLINE.md` (2026-05-08)  
✅ `OLLAMA_MODEL_SELECTION_DS723.md` (2026-05-08)  
✅ `README_CREATION.md` (2026-05-07)  
✅ `REPO_REVIEW.md` (2026-05-07)  
✅ `REPO_REVIEW_2026_05_07.md` (2026-05-07)  

---

## Incomplete Work Extracted from CONSOLIDATED_REMAINING_WORK.md

**PHASES NOT YET STARTED (from that file):**

### Phase 1 — docker.sock Comment Normalisation

**Status:** PARTIALLY DONE (per file comment)  
**Scope:** 10+ compose files  
**Template:** Two-comment system (`:ro` vs `:rw` with reason)  
**Effort:** ~30 min  
**Include in current run:** ✅ YES

---

### Phase 2 — README Volume Tables Sweep

**Status:** NOT STARTED  
**Scope:** 8+ README files  
**Template:** Gold standard with `${STACK_ROOT}` placeholder  
**Effort:** ~90 min (editorial)  
**Include in current run:** ✅ YES

---

### Phase 3 — verify-dns-views.sh --hairpin Mode

**Status:** UNKNOWN (file notes "may be missing")  
**Scope:** Single script enhancement  
**Effort:** ~30-45 min  
**Include in current run:** ✅ YES (verify first)

---

### Phase 4 — AGENTS.md Bullets Update

**Status:** NOT STARTED  
**Scope:** Add 3 dated bullets about Cursor skills, Ollama, offline workspace  
**Effort:** ~15 min (documentation)  
**Include in current run:** ✅ YES (minor)

---

### Phase 5 — Archive Completed Task Files

**Status:** NOT STARTED  
**Scope:** Move 6 files from `docs/tasks/` → `docs/tasks/archive/`  
**Effort:** ~10 min (file operations + superseded headers)  
**Include in current run:** ✅ YES (must be done before closeout)

---

### Phase 6 — Final Validation

**Status:** NOT STARTED  
**Scope:** Run all shell scripts, compose validate, git checks  
**Effort:** ~20 min  
**Include in current run:** ✅ YES (before commit)

---

### Phase 7 — Memory Update

**Status:** NOT STARTED  
**Scope:** Add compound learning and continuous learning entries  
**Effort:** ~10 min  
**Include in current run:** ✅ YES (cleanup)

---

## NEW Bug Fixes from Gordon's Code Review

**12 bugs identified across shell scripts and compose files**

**Status:** Task file created (`CODER_TASK_Shell_Script_And_Compose_Fixes.md`)  
**Scope:** 3 tiers (critical, medium, polish)  
**Effort:** ~2-3 hours  
**Include in current run:** ✅ **YES — PRIORITY**

These bugs are **independent** of the consolidated remaining work but overlap in:
- `scripts/nas-reset.sh` (quoting issues appear in both)
- `scripts/fix-permissions.sh` (null-terminator fix)
- `scripts/restore-env.sh` (find loop safety)
- `scripts/compose-validate.sh` (array syntax, trap logic)

**Recommendation:** Execute bug fixes (Tier 1 + 2) **before** running consolidated remaining work phases 1-5, because:
1. Fixes improve script robustness → subsequent phases run safer
2. Both documents touch the same scripts; fixes prevent conflicts
3. Bugs are critical; consolidation work is medium-priority polish

---

## Unclear Tasks to Review

### `OAuth Automation, Repo Audit & NAS Deploymen.md`

**Status:** Filename suggests OAuth + audit scope but content unknown  
**Action:** Review first; likely superseded by MASTER_AUDIT_AND_DEPLOY.md  
**Decision:** ⏸️ REVIEW BEFORE DECIDING

### `Task+HAProxy_Traefik_Master_Audit.md`

**Status:** Filename suggests HAProxy/Traefik audit  
**Action:** Review first; likely superseded by CONSOLIDATED_REMAINING_WORK phases 1-5  
**Decision:** ⏸️ REVIEW BEFORE DECIDING

---

## Recommendation: Unified Current Task File

Create **`docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md`** that consolidates:

1. **Gordon's 12 bug fixes** (Tier 1, 2, 3 from CODER_TASK_Shell_Script_And_Compose_Fixes.md)
2. **Consolidated remaining phases** (1-7 from CONSOLIDATED_REMAINING_WORK.md)
3. **Execution order** to prevent conflicts
4. **Archive instructions** for completed tasks

**Structure:**
- Phase 0: Pre-flight (required first)
- **Phases 1-3: Code Fixes (Tier 1 critical)** ← Bug fixes, immediate impact
- **Phases 4-6: Consolidation Phases 1-5** ← Editorial + script enhancements
- Phase 7: Validation + archiving
- Phase 8: Memory updates

---

## Archive Template for Completed Tasks

All tasks being archived receive this header (prepend to existing content):

```markdown
<!--
SUPERSEDED — archived 2026-05-10
All phases verified complete. See AGENTS.md ## What Works for outcomes.
This file is retained for historical reference only.
Consolidated into: docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md
-->
```

---

## Files to Archive (Ready Now)

These can be moved immediately:

| File | Destination | Note |
| --- | --- | --- |
| `CODER_TASK_Harden_Counter_Increments_Set_E.md` | `archive/` | Mark superseded |
| `CONSOLIDATED_REMAINING_WORK.md` (after consolidation) | `archive/` | Or keep as historical reference |
| `MASTER_AUDIT_AND_DEPLOY.md` | **KEEP** | Periodic re-run template |

**Files to KEEP in `docs/tasks/`:**
- `MASTER_AUDIT_AND_DEPLOY.md` — periodic re-run entry point
- `GORDON_CODE_REVIEW_SUMMARY.md` — reference for this code review

**Files to CREATE:**
- `CODEBASE_HARDENING_AND_CONSOLIDATION.md` — unified current task file

---

## Execution Sequence (Recommended)

### **Run 1: Code Hardening (2-3 hours)**
Execute: `docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md` Phases 1-3 (bug fixes)
- Fixes applied to scripts and compose files
- Shellcheck passes
- Compose validates
- Commit: `fix: harden shell scripts and remove hardcoded IPs`

### **Run 2: Consolidation Work (3-4 hours)**
Execute: `docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md` Phases 4-6 (remaining work)
- docker.sock comments normalized
- README volume tables updated
- DNS verify script enhanced
- AGENTS.md bullets added
- Validation suite runs
- Commit: `chore: consolidate remaining work; normalize docker.sock comments; update READMEs`

### **Run 3: Archiving (30 min)**
Execute: `docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md` Phase 7 (cleanup)
- Archive completed task files
- Add superseded headers
- Update memory
- Commit: `chore: archive completed task files; update memory`

---

## Quick Decision Matrix

| Task | Status | Next Action | Time | Priority |
| --- | --- | --- | --- | --- |
| Shell script bug fixes | 🆕 Created | Execute Tier 1, 2, 3 | 2-3h | 🔴 CRITICAL |
| docker.sock normalization | 📋 Designed | Execute Phase 1 | 30m | 🟡 HIGH |
| README volume tables | 📋 Designed | Execute Phase 2 | 90m | 🟡 HIGH |
| DNS verify --hairpin | 📋 Designed | Verify + execute Phase 3 | 30-45m | 🟡 HIGH |
| AGENTS.md bullets | 📋 Designed | Execute Phase 4 | 15m | 🟢 LOW |
| Archive task files | 📋 Designed | Execute Phase 5 | 10m | 🟢 LOW |
| Validation + commit | 📋 Designed | Execute Phase 6 | 20m | 🟡 HIGH |
| Memory updates | 📋 Designed | Execute Phase 7 | 10m | 🟢 LOW |
| Review unclear tasks | ⏸️ BLOCKED | Review first | 15m | ? |

---

## Delegation Instructions for @coder

### If you want **everything in one go:**

> I'm delegating a complete hardening and consolidation run. Here's the sequence:
>
> 1. **Start with bug fixes:** `docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md` Phases 1-3 (shell script hardening). Commit after Phase 3.
>
> 2. **Then consolidation work:** Phases 4-6 (docker.sock, READMEs, dns verify, AGENTS bullets). Commit after Phase 6.
>
> 3. **Finally cleanup:** Phase 7 (archiving, memory). Final commit.
>
> Estimated time: **5-6 hours total**

### If you want **just the critical bugs first:**

> Start with `docs/tasks/CODEBASE_HARDENING_AND_COMPOSEFILE_FIXES.md` Tier 1 + 2. Test locally and commit. We'll handle consolidation work in a separate session after this lands.
>
> Estimated time: **2-3 hours**

### If you want **just the consolidation work:**

> Execute `docs/tasks/CONSOLIDATED_REMAINING_WORK.md` Phases 0-7. This assumes shell scripts are already hardened (we'll do that separately). Do NOT include the bug fixes.
>
> Estimated time: **3-4 hours**

---

## Status and Next Steps

✅ **Code review complete** (12 bugs identified)  
✅ **Task files created** (bug fixes, consolidation)  
✅ **Sequence recommended** (three-run or one-run options)  
✅ **Archive plan ready** (superseded headers + file moves)  

⏳ **Awaiting:**
- Decision on execution mode (all-in-one vs. phased)
- Review of unclear tasks (OAuth/HAProxy files)
- Delegation to @coder

---

## Files Created in This Session

1. `docs/tasks/CODER_TASK_Shell_Script_And_Compose_Fixes.md` — bug fixes task
2. `docs/tasks/GORDON_CODE_REVIEW_SUMMARY.md` — code review summary
3. `docs/tasks/TASK_CONSOLIDATION_AND_ARCHIVE.md` — this file

---

## Appendix: Archive Move Commands

```bash
# After approving this plan, run these to archive completed tasks:

cd docs/tasks/archive

# Supersede existing archived files (already have headers — no change)

# Archive the hardening task (COMPLETE)
git mv ../CODER_TASK_Harden_Counter_Increments_Set_E.md . && \
  sed -i '1s/^/<!--\nSUPERSEDED — archived 2026-05-10\nAll phases verified complete. See AGENTS.md ## What Works for outcomes.\nThis file is retained for historical reference only.\n-->\n\n/' CODER_TASK_Harden_Counter_Increments_Set_E.md

# Do NOT move CONSOLIDATED_REMAINING_WORK yet (still in progress reference)
# Do NOT move MASTER_AUDIT_AND_DEPLOY (periodic re-run template)

cd ../
git add docs/tasks/archive/
git commit -m "chore: archive completed counter-hardening task"
```

---

## References

- **Code Review:** `docs/tasks/GORDON_CODE_REVIEW_SUMMARY.md`
- **Bug Fixes Task:** `docs/tasks/CODER_TASK_Shell_Script_And_Compose_Fixes.md`
- **Consolidation Task:** `docs/tasks/CONSOLIDATED_REMAINING_WORK.md`
- **Master Template:** `docs/tasks/MASTER_AUDIT_AND_DEPLOY.md`

---

**Prepared for delegation. Ready to proceed when approved.**
