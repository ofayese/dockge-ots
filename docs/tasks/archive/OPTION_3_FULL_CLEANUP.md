> **Status:** ✅ SUPERSEDED / ARCHIVED — 2026-05-10

# Option 3: Full Cleanup + Mark Complete (10 min)

**Purpose:** Archive unclear task files AND mark sprint task as complete  
**Time:** ~10 minutes  
**Result:** Clean task directory + clear completion record  

---

## Step 1: Archive Unclear Task Files (5 min)

Run on your local machine:

```bash /Users/laolufayese/dev/dockge
cd 

# Move unclear task files to archive
git mv "docs/tasks/OAuth Automation, Repo Audit & NAS Deploymen.md" docs/tasks/archive/
git mv docs/tasks/Task+HAProxy_Traefik_Master_Audit.md docs/tasks/archive/

# Verify they moved
ls docs/tasks/archive/ | grep -E "OAuth|HAProxy"
# Expected: both files listed
```

---

## Step 2: Add Superseded Headers (3 min)

```bash
# Go to archive directory
cd docs/tasks/archive/

# Add superseded header to OAuth file
HEADER='<!--
SUPERSEDED — archived 2026-05-10
All phases verified complete. See AGENTS.md ## What Works for outcomes.
This file is retained for historical reference only.
Consolidated into: docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md
-->

'

# For OAuth file
(printf '%s\n' "$HEADER" && cat "OAuth Automation, Repo Audit & NAS Deploymen.md") > temp && mv temp "OAuth Automation, Repo Audit & NAS Deploymen.md"

# For HAProxy file
(printf '%s\n' "$HEADER" && cat "Task+HAProxy_Traefik_Master_Audit.md") > temp && mv temp "Task+HAProxy_Traefik_Master_Audit.md"

# Go back to root
cd ../..

# Verify headers were added
head -5 docs/tasks/archive/"OAuth Automation, Repo Audit & NAS Deploymen.md"
head -5 docs/tasks/archive/Task+HAProxy_Traefik_Master_Audit.md
# Expected: both show the superseded header
```

---

## Step 3: Mark Sprint Task Complete (2 min)

Edit `docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md` header:

**Find this line (line 6):**
```markdown
**Status:** Ready for Execution
```

**Change to:**
```markdown
**Status:** ✅ COMPLETED — 2026-05-10 (Commits: f7cf6f1, ccbd96e)
```

Save the file.

---

## Step 4: Commit Everything (Optional but Recommended)

```bash
# Stage all changes
git add docs/tasks/

# Verify what's staged
git status --short
# Expected: 
#   A  docs/tasks/archive/OAuth Automation...
#   A  docs/tasks/archive/Task+HAProxy...
#   M  docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md

# Commit
git commit -m "chore: archive unclear task files and mark sprint complete

- Moved OAuth Automation task to archive (unclear scope)
- Moved HAProxy Traefik task to archive (unclear scope)
- Added superseded headers to archived files
- Marked CODEBASE_HARDENING_AND_CONSOLIDATION.md as complete
- Repository task organization now clean and clear

All phases of the sprint verified and deployed to main."

# Push
git push origin HEAD:main
```

---

## Step 5: Verify (1 min)

```bash
# Check local state is clean
git status --short
# Expected: (nothing — all clean)

# Verify files in archive
ls docs/tasks/archive/ | grep -E "OAuth|HAProxy"
# Expected: both files listed

# Verify sprint task header was updated
grep "Status:" docs/tasks/CODEBASE_HARDENING_AND_CONSOLIDATION.md | head -1
# Expected: ✅ COMPLETED — 2026-05-10

# Verify push succeeded
git log --oneline -2
# Expected: your new commit + previous ccbd96e
```

---

## Final Result

✅ Unclear task files archived with proper headers  
✅ Sprint task marked as complete  
✅ Clean task directory  
✅ All changes pushed to main  

**Time taken:** ~10 minutes  
**Result:** Fully organized, clear task history, production-ready repository

---

## Checklist

- [ ] Run archive move commands
- [ ] Add superseded headers
- [ ] Update sprint task header
- [ ] Commit and push
- [ ] Verify git status is clean
- [ ] Done! ✅

---

**After Option 3 is complete, your task directory will be:**

```
docs/tasks/
├── MASTER_AUDIT_AND_DEPLOY.md        (kept — periodic re-run)
├── GORDON_CODE_REVIEW_SUMMARY.md     (kept — reference)
├── POST_SPRINT_ACTION_ITEMS.md       (kept — this guide)
├── SPRINT_COMPLETION_REPORT_2026_05_10.md (kept — completion record)
├── archive/
│   ├── CODER_TASK_Harden_Counter_Increments_Set_E.md (from sprint)
│   ├── OAuth Automation, Repo Audit & NAS Deploymen.md (NEW - archived)
│   ├── Task+HAProxy_Traefik_Master_Audit.md (NEW - archived)
│   └── [11 other historical tasks]
```

---

**You're done! Repository is now fully organized and production-ready.** 🎉
