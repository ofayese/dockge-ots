# Quick Reference: Pre-Commit Hooks & Violations Found

## Current Code Violations (Found in Review)

### 🔴 CRITICAL: Python Violations

#### Violation 1: Subprocess without timeout
- **File:** `docs/hive/tools/inventory.py`
- **Line:** 386
- **Code:**
  ```python
  stale = subprocess.run(
      ["rg", "--pcre2", "(?<!ots)orundscore", str(rel)],
      cwd=repo_root, capture_output=True, text=True, timeout=10,
  )
  ```
- **Issue:** Has timeout ✓ (Actually CORRECT)
- **Status:** Review more carefully for other patterns

#### Violation 2: Dict iteration misuse
- **File:** `docs/hive/tools/inventory.py`
- **Line:** 273
- **Code:**
  ```python
  depends_on = [
      f"{k} ({v.get('condition', 'started')})" if isinstance(v, dict) else str(k)
      for k, v in depends.items()
  ]
  ```
- **Issue:** When `v` is not dict, uses `str(k)` instead of `str(v)` — loses value
- **Fix:** Change to `str(v)` in the else branch
- **Status:** ❌ MUST FIX

### 🔴 CRITICAL: Shell Violations

#### Violation 3: Sed with unescaped variables
- **File:** `scripts/init-nas.sh`
- **Line:** 196 (also 211)
- **Code:**
  ```bash
  sed -i "s|^STACK_ROOT=.*|STACK_ROOT=${STACK_ROOT}|" "${REPO_ENV}"
  ```
- **Issue:** `${STACK_ROOT}` can contain special chars; path vars need escaping
- **Fix:** Use `sed -i "s|^STACK_ROOT=.*|STACK_ROOT=$(printf '%s\n' "$STACK_ROOT" | sed -e 's/[\/&]/\\&/g')|" "${REPO_ENV}"`
- **Status:** ❌ MUST FIX

#### Violation 4: Bash regex alternation
- **File:** `scripts/check-dockge-http.sh`
- **Line:** 15
- **Code:**
  ```bash
  [[ "${code}" =~ ^(200|301|302|304)$ ]] || exit 1
  ```
- **Issue:** Bash regex doesn't support `()` alternation in `[[ =~ ]]`
- **Fix:** Change to `[[ "${code}" =~ ^(200|30[1234])$ ]]` or use pattern matching
- **Status:** ❌ MUST FIX

#### Violation 5: Docker compose in loop without error handling
- **File:** `scripts/compose-validate.sh`
- **Line:** 73
- **Code:**
  ```bash
  while IFS= read -r f; do
      [[ -n "${f}" ]] || continue
      rel="${f#"${ROOT}"/}"
      dir="$(dirname "${f}")"
      base="$(basename "${f}")"
      echo "compose config: ${rel}"
      (
          cd "${dir}"
          docker compose --env-file "${COMPOSE_ENV_FILE}" -f "${base}" config -q
      )
  done < <(...)
  ```
- **Issue:** Subshell with `set -e` doesn't propagate failure to parent loop; loop continues silently
- **Fix:** Add `|| { echo "ERROR validating $f"; exit 1; }` after docker compose command
- **Status:** ❌ MUST FIX

### 🔴 CRITICAL: Node.js Violations

#### Violation 6: Zod schema not wrapped
- **File:** `stacks/agents_gateway_data/duckduckgo/src/index.js`
- **Lines:** 12-15
- **Code:**
  ```javascript
  inputSchema: {
      timezone: z
          .string()
          .describe("Timezone in IANA format, e.g., America/New_York"),
  },
  ```
- **Issue:** MCP spec requires `inputSchema: z.object({ ... })`, not raw object
- **Fix:**
  ```javascript
  inputSchema: z.object({
      timezone: z
          .string()
          .describe("Timezone in IANA format, e.g., America/New_York"),
  }),
  ```
- **Status:** ❌ MUST FIX

## Hook Detection Patterns (for Coder implementation)

### Python Hooks

**Hook 1: subprocess-no-timeout**
```python
# FAIL: subprocess.run() without timeout=
subprocess.run(["docker", "pull", "image"], capture_output=True)

# PASS: Has timeout
subprocess.run(["docker", "pull", "image"], capture_output=True, timeout=30)

# PASS: Inside comment or string
# subprocess.run without timeout is bad
code = "subprocess.run(...)"
```

**Hook 2: unsafe-dict-iteration**
```python
# FAIL: for k, v in dict but only using k
for k, v in depends.items():
    result.append(str(k))  # ← v unused

# PASS: Both variables used
for k, v in depends.items():
    result.append(f"{k}={v}")

# FAIL: Direct dict access without .get()
value = config["key"]  # ← KeyError potential

# PASS: Safe access
value = config.get("key", "default")
```

### Shell Hooks

**Hook 3: unsafe-sed**
```bash
# FAIL: / delimiter with ${VAR} containing /
sed 's/^STACK_ROOT=.*/STACK_ROOT=${STACK_ROOT}/' file

# PASS: | delimiter (safe for paths)
sed 's|^STACK_ROOT=.*|STACK_ROOT=${STACK_ROOT}|' file

# PASS: Escaped special chars
sed "s|^STACK_ROOT=.*|STACK_ROOT=$(printf '%s\n' "$STACK_ROOT" | sed -e 's/[\/&]/\\&/g')|" file
```

**Hook 4: bash-regex-alternation**
```bash
# FAIL: () alternation in [[ =~ ]]
[[ $code =~ ^(200|301)$ ]]  # ← Invalid bash syntax

# PASS: Character class
[[ $code =~ ^(200|30[1-4])$ ]]

# PASS: || operator
[[ $code == 200 || $code == 301 || $code == 302 ]]
```

**Hook 5: docker-compose-no-err**
```bash
# FAIL: Loop continues on docker compose failure
while read -r file; do
    docker compose config "$file"  # ← Silently fails if error
done < <(find ...)

# PASS: Error handling
while read -r file; do
    docker compose config "$file" || { echo "ERROR"; exit 1; }
done < <(find ...)

# PASS: set -e at function level
validate_all() {
    set -e
    docker compose config file1
    docker compose config file2
}
```

### Node.js Hook

**Hook 6: zod-schema-wrapper**
```javascript
// FAIL: inputSchema not wrapped
inputSchema: {
    timezone: z.string(),
},

// PASS: Wrapped in z.object()
inputSchema: z.object({
    timezone: z.string(),
}),

// PASS: outputSchema (recommended but not required)
outputSchema: z.object({
    result: z.string(),
}),
```

## How to Verify Fixes

```bash
# Run specific hook against a file
python3 hooks/python-unsafe-dict-iteration.py docs/hive/tools/inventory.py
bash hooks/shell-unsafe-sed.sh scripts/init-nas.sh
bash hooks/shell-bash-regex-alternation.sh scripts/check-dockge-http.sh

# Run all hooks (pre-commit)
pre-commit run --all-files --stages commit

# Run specific hook
pre-commit run python-unsafe-dict-iteration --all-files
pre-commit run shell-unsafe-sed --all-files
```

## Violation Summary Table

| # | File | Line | Violation Type | Severity | Status |
|---|------|------|---|---|---|
| 1 | inventory.py | 273 | dict iteration (wrong var) | 🔴 HIGH | ❌ UNFIXED |
| 2 | init-nas.sh | 196, 211 | sed unescaped variable | 🔴 HIGH | ❌ UNFIXED |
| 3 | check-dockge-http.sh | 15 | bash regex alternation | 🔴 HIGH | ❌ UNFIXED |
| 4 | compose-validate.sh | 73 | docker compose no err | 🔴 HIGH | ❌ UNFIXED |
| 5 | index.js | 12-15 | Zod not wrapped | 🔴 HIGH | ❌ UNFIXED |

**Total violations:** 5 issues across 5 files  
**Blocking commit:** YES (all violations block until fixed)  
**Estimated fix time:** 15-20 minutes

---

## Implementation Order for Coder

1. ✅ **Create hooks/** directory and all 9 hook scripts
2. ✅ **Create/enhance .pre-commit-config.yaml** with all hooks
3. ✅ **Run pre-commit --all-files** (expect 5 violations)
4. ✅ **Fix violations** in inventory.py, init-nas.sh, check-dockge-http.sh, compose-validate.sh, index.js
5. ✅ **Re-run pre-commit** (should pass now)
6. ✅ **Continue with Phases 2-5**

---

**Document Status:** Quick Reference for Cursor/Coder  
**Created:** 2025-01-15  
**For Use During:** Phases 1 & 5 (hook development and validation)
