> Note: The original Gordon briefing pack (`ENHANCED_*` / `INDEX`) is retained for architectural context only. All implementations and bugs documented here are complete.

# Bug Fix Summary: Coder Agent Phase 1 Issues

See also **[`AGENTS.md`](../AGENTS.md)** for live operator truth.

## Timeline

1. **Coder Agent** completed Phase 1-4 implementation (pre-commit hooks, PSU automation, shell tests, analyzer modules)
2. **Coder Agent** reported 5 critical bugs found during testing
3. **Gordon (Docker AI)** identified root causes and fixed all 5 bugs
4. **All bugs verified** and committed (commit 1f7ab34)
5. **Phase 2 review** surfaced 4 additional logic bugs (analyzer defaults, pre-commit Python hooks, Compose `x-` handling, HAProxy parse order); fixed and documented below.

---

## Bugs Fixed (Phase 1 — Original Five)

### Bug 1: Traefik Label Analysis Dead Code
**Severity:** HIGH (feature completely non-functional)

**Root Cause:** `normalize_labels()` returns `dict[str, str]`, but `build_analyzer_report()` assigned it to `labels_list` and then checked `isinstance(labels_list, list)`, which is always False. This caused the Traefik analysis code to never execute with valid labels.

**Location:** `docs/hive/tools/analyzers/analyzer_report.py` lines 100-110

**Fix:** Removed the unnecessary type conversion logic. Now:
```python
labels = label_analyzer.normalize_labels(svc_def.get('labels'))
# labels is a dict[str, str], use it directly
invalid = label_analyzer.detect_invalid_traefik_labels(labels)
```

**Verification:** ✅ Traefik analyzer now finds routing issues (tested with 2 issues found)

---

### Bug 2: env_validation Type Mismatch
**Severity:** CRITICAL (causes AttributeError crash)

**Root Cause:** `env_validation` initialized as empty list `[]` on line 42. When `.env` file doesn't exist (common, as it's gitignored), the structure remains a list. Later, line 120 calls `report['findings']['env_validation'].get('errors', [])` on a list, causing `AttributeError: 'list' object has no attribute 'get'`.

**Location:** `docs/hive/tools/analyzers/analyzer_report.py` lines 42 & 120

**Fix:** Initialize `env_validation` as dict:
```python
'findings': {
    ...
    'env_validation': {},  # Always a dict, even if .env doesn't exist
    ...
}
```

**Verification:** ✅ No crash on missing `.env`, summary counts always valid

---

### Bug 3: Version Unpacking with Missing Minor
**Severity:** HIGH (false positives on every file without explicit version)

**Root Cause:** Compose files without explicit `version:` field use default `'3'`. The code did:
```python
major, minor = version.split('.')[:2]  # '3'.split('.') = ['3']
v_major, v_minor = int(major), int(minor)  # ValueError: not enough values
```

**Location:** `docs/hive/tools/analyzers/compose_schema.py` lines 75-79

**Fix:** Handle missing minor version:
```python
parts = str(version).split('.')
v_major = int(parts[0])
v_minor = int(parts[1]) if len(parts) > 1 else 0
```

**Verification:** ✅ Version `'3'` accepted (no error), version `'4.0'` detected as unsupported

---

### Bug 4: Duplicate Prettier Repository
**Severity:** MEDIUM (pre-commit install/run fails with config error)

**Root Cause:** (VERIFIED AS FALSE ALARM) Coder reported duplicate `mirrors-prettier` entries in `.pre-commit-config.yaml`

**Location:** `.pre-commit-config.yaml`

**Status:** ✅ VERIFIED - Only 1 `mirrors-prettier` entry exists (line 21). No duplicate found. Coder's report was incorrect.

**Fix:** None needed.

---

### Bug 5: Shell Hook Exit Code Doesn't Propagate
**Severity:** HIGH (hook silently passes even when violations found)

**Root Cause:** `grep ... | while read` runs the while loop in a subshell. When `fail=1` is assigned inside the loop, it only modifies the subshell's variable. The parent shell still sees `fail=0` from initialization.

**Location:** `hooks/shell-unsafe-sed.sh`

**Original Code:**
```bash
fail=0
for file in "$@"; do
    if awk '...' "$file" | grep -q .; then
        echo "$file: WARNING..." >&2
        fail=1  # ← This only sets subshell's fail
    fi
done
exit $fail  # ← Parent shell's fail is still 0
```

**Fix:** Use direct while loop with process substitution (no subshell):
```bash
fail=0
for file in "$@"; do
    while read -r line; do
        # Pattern matching...
        echo "$file: WARNING..." >&2
        fail=1  # ← Now sets parent's fail
    done < "$file"
done
exit "$fail"  # ← Correctly returns 1
```

**Verification:** ✅ Hook now returns exit code 1 when unsafe sed patterns detected

---

## Bugs Fixed (Phase 2 — Four Logic Bugs)

Same failure class as **Bug 2** (wrong default container type): code assumed `findings[...]` was always dict-shaped after `build_analyzer_report()` ran to completion. When the `try` block raised before reassignment, **`.get()` on a list** crashed the dashboard path.

### Bug 6: schema_validation / dependency_analysis Type Mismatch
**Severity:** CRITICAL (AttributeError on analyzer / dashboard aggregation)

**Root Cause:** `schema_validation` and `dependency_analysis` were initialized as `[]`. On failure before reassignment, `generate_dashboard_summary()` called `findings.get('dependency_analysis', {}).get('cycles', [])` — but `findings['dependency_analysis']` could still be a **list**, so the second `.get` ran on a list → **`AttributeError`**.

**Location:** `docs/hive/tools/analyzers/analyzer_report.py` (initial `report['findings']` structure)

**Fix:** Initialize both as **`{}`**, matching the dict shape used after successful analysis (and matching the earlier **`env_validation: {}`** pattern).

**Verification:** ✅ Exception path + dashboard aggregation tolerate missing compose / early exit

---

### Bug 7: Python Hook `any()` Short-Circuiting
**Severity:** HIGH (silent omission of violations)

**Root Cause:** Pre-commit passes multiple filenames in one hook invocation when `pass_filenames: true`. **`failed = any(check_file(f) for f in paths)`** short-circuits: the generator stops at the **first** `True`, so later files are never checked and their violations never print.

**Location:** `hooks/python-no-timeout-subprocess.py`, `hooks/python-unsafe-dict-iteration.py`

**Fix:** Loop all paths and set a flag:
```python
failed = False
for f in sys.argv[1:]:
    if check_file(f):
        failed = True
sys.exit(1 if failed else 0)
```

**Heuristic:** For repo-wide or multi-file hooks, **never use `any(gen)`** if every file must be diagnosed; use an explicit loop (or `list(...)` before `any`, if you truly want short-circuit after collecting).

**Verification:** ✅ Every staged file is scanned; all violations reported in one run

---

### Bug 8: Compose Schema `x-` Extension Bypass
**Severity:** MEDIUM (false negatives — unknown keys ignored when any `x-*` present)

**Root Cause:** Condition was effectively “if there is any unknown key **and** none of them start with `x-`” — implemented as **`unknown_keys and not any(k.startswith('x-') for k in unknown_keys)`**. If the set contained **both** `x-logging` and a typo like `typo-key`, **`any(...)`** was true, the **`not`** made the whole condition false, and **no error** was emitted for **`typo-key`**.

**Location:** `docs/hive/tools/analyzers/compose_schema.py` (top-level key validation)

**Fix:** Split valid extensions from invalid unknowns:
```python
invalid_unknown = {k for k in unknown_keys if not k.startswith("x-")}
if invalid_unknown:
    errors.append(...)
```

**Heuristic:** When whitelisting prefixes, **filter the set first**, then test emptiness — do not let one whitelisted key mask other invalid keys.

**Verification:** ✅ Mixed `x-logging` + invalid key → error lists only the invalid key(s)

---

### Bug 9: HAProxy Single-Pass `use_backend` False Positives
**Severity:** MEDIUM (noise — valid configs flagged)

**Root Cause:** A single forward scan checked **`use_backend name`** against **`backends`** while still parsing. HAProxy files commonly declare **frontends (with `use_backend`) before `backend` blocks**, so **`backends`** was still empty → false **“backend not defined”** for every reference.

**Location:** `docs/hive/tools/analyzers/haproxy_traefik_checker.py` — `validate_haproxy_config()`

**Fix:** **Two-pass parse:** (1) scan all lines and collect **`frontend` / `backend`** names into sets; (2) second pass for **`bind`** / **`use_backend`** checks against the **complete** `backends` set.

**Heuristic:** For config validators where **definition order ≠ reference order**, collect symbols in one pass, validate references in a second.

**Verification:** ✅ `use_backend` after later `backend` lines no longer false-positive

---

## Fixes Summary Table

| Bug | File | Issue Type | Severity | Status |
|-----|------|-----------|----------|--------|
| 1 | analyzer_report.py | Type mismatch (dict vs list) | HIGH | ✅ Fixed |
| 2 | analyzer_report.py | Uninitialized state (AttributeError) | CRITICAL | ✅ Fixed |
| 3 | compose_schema.py | Unpacking error (missing minor) | HIGH | ✅ Fixed |
| 4 | .pre-commit-config.yaml | Duplicate entry | MEDIUM | ✅ Verified false alarm |
| 5 | shell-unsafe-sed.sh | Subshell exit code loss | HIGH | ✅ Fixed |

### Phase 2 (logic bugs)

| Bug | File(s) | Issue Type | Severity | Status |
|-----|---------|------------|----------|--------|
| 6 | analyzer_report.py | Default `findings` lists vs `.get()` chain | CRITICAL | ✅ Fixed |
| 7 | python-no-timeout-subprocess.py, python-unsafe-dict-iteration.py | `any()` short-circuit on multi-file hook | HIGH | ✅ Fixed |
| 8 | compose_schema.py | `x-*` whitelist masked other unknown keys | MEDIUM | ✅ Fixed |
| 9 | haproxy_traefik_checker.py | Single-pass order vs HAProxy layout | MEDIUM | ✅ Fixed |

---

## Commit Information

**Commit Hash:** `1f7ab34`

**Message:**
```
fix: resolve 5 critical bugs in analyzer modules and pre-commit hooks

Bug 1 (label_analyzer): normalize_labels() returns dict, not list. Remove 
incorrect list conversion in build_analyzer_report() so Traefik label analysis 
actually runs instead of being dead code with empty labels dict.

Bug 2 (analyzer_report): env_validation initialized as list [] but code calls 
.get() on it when .env missing, causing AttributeError. Initialize as dict {} 
so .get() always works and summary counts are always valid.

Bug 3 (compose_schema): version unpacking fails with version='3' (no minor). 
Fix by checking split() length and defaulting minor=0. Handles all Compose 
v3.x versions without ValueError.

Bug 4 (.pre-commit-config.yaml): Verified no duplicate mirrors-prettier repo 
(was incorrectly reported). Config is valid with single entry at line 21.

Bug 5 (shell-unsafe-sed.sh): grep | while runs in subshell, fail=1 never 
propagates to parent. Replace awk + grep | while with direct while loop 
reading file, so exit code correctly reflects findings.

All bugs verified with tests.
Assisted-By: coder-agent
```

**Files Changed:** 4 files, 49 insertions, 96 deletions (net -47 lines)

---

## Test Results

All bugs verified with automated tests:

```bash
# Bug 1: Traefik validation finds issues
✅ label_analyzer.normalize_labels() returns dict
✅ Traefik analysis finds routing issues (2 found in test)

# Bug 2: No AttributeError on missing .env
✅ env_validation initialized as dict {} 
✅ No crash when .env doesn't exist
✅ Summary counts always valid

# Bug 3: Version parsing handles all formats
✅ Version '3' accepted (no ValueError)
✅ Version '3.9' accepted
✅ Version '4.0' rejected as unsupported

# Bug 5: Shell hook exit code propagates
✅ Unsafe sed pattern detected → exit code 1
✅ Safe sed pattern → exit code 0
```

---

## Impact Assessment

### Before Fixes
- ❌ Traefik routing analysis never runs (dead code)
- ❌ Analyzer crashes on missing `.env` (common case)
- ❌ False positives for Compose files without explicit version
- ❌ Sed hook silently passes violations

### After Fixes
- ✅ Traefik routing analysis finds issues
- ✅ Analyzer works even without `.env` file
- ✅ Correct version handling for all Compose formats
- ✅ Sed hook correctly reports violations

---

## Lessons Learned

1. **Type consistency matters:** `normalize_labels()` returns dict, not list. Don't assume types without checking implementation.

2. **Default states must be correct type:** `env_validation: []` initialized as list, but code expects dict. Use correct type from the start.

3. **Version parsing needs defensive coding:** Modern Compose files often omit explicit version. Handle missing fields gracefully.

4. **Subshell variable assignments don't propagate:** Pipelines run in subshells. Use process substitution (`< file`) instead of pipes (`|`) for proper variable scope.

5. **Test with real data:** These bugs only appeared when analyzer ran on actual stacks (missing `.env`, no explicit version, unsafe sed patterns).

6. **`any()` on generators hides work:** Multi-file hooks must scan every path; short-circuiting stops at the first failure and hides the rest.

7. **Prefix whitelists must be per-key:** `not any(x)` over a mixed set is wrong when you need “any key that is *not* whitelisted.”

8. **Ordered configs need two-pass or forward refs:** HAProxy (and similar) interleave declare/reference; collect definitions before validating references.

---

**Status:** ✅ READY FOR NEXT PHASE

Phase 1 and Phase 2 bugs fixed and verified. The analyzer modules and pre-commit hooks are production-ready. See **Phase 2 — Four Logic Bugs** above; code landed in **`c0ea1bd`** (`refactor(analyzer): update data structures for consistency and clarity`).
