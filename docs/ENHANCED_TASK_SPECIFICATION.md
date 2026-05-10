# Enhanced Task Specification: Dockge-OTS Ecosystem Enhancements
## Comprehensive Implementation Guide

---

## Executive Summary

This document provides an **enhanced, production-ready specification** for implementing four major enhancements to the dockge-ots ecosystem:

1. **Pre-commit Enforcement System** — Cross-language pattern validation
2. **PSU Automation Layer** — Continuous validation and testing
3. **Shell Integration Test Suite** — Comprehensive bats tests
4. **Static Analyzer Extension** — Full inventory.py analyzer framework

**Status:** Ready for immediate Cursor/Coder implementation  
**Estimated Duration:** 6-8 hours  
**Complexity:** High (integrates 4 major subsystems)

---

## PHASE 1: PRE-COMMIT ENFORCEMENT SYSTEM

### Objectives
- Enforce Python safety patterns (subprocess timeouts, dict iteration)
- Enforce Shell safety patterns (sed escaping, bash regex, docker compose error handling)
- Enforce Node.js patterns (Zod schema wrapper validation)
- Block commits if validations fail

### Deliverables

#### 1.1 Enhanced `.pre-commit-config.yaml`
**File:** `./.pre-commit-config.yaml`

**Required sections:**
- Standard hooks (already present): trailing-whitespace, end-of-file-fixer, check-yaml, check-json, prettier, gitleaks, shfmt, shellcheck
- Python hooks: flake8 (line length 120, ignore E203/W503), mypy (strict mode with ignore-missing-imports)
- **NEW custom hooks (local repo):**
  - `python-no-timeout-subprocess` — Detects `subprocess.run()` without `timeout=` parameter
  - `python-unsafe-dict-iteration` — Detects `for k, v in dict.items()` where only `k` is used (missing value)
  - `shell-unsafe-sed` — Detects `sed 's/.../${VAR}/...'` without escaping special chars
  - `shell-bash-regex-alternation` — Detects `[[ $var =~ ^(a|b)$ ]]` (invalid bash regex syntax)
  - `shell-docker-compose-no-err` — Detects `docker compose config` without `|| exit` error handling
  - `node-zod-schema-wrapper` — Detects `inputSchema: { key: z.string() }` (not wrapped in `z.object()`)
- **NEW test runners (local repo):**
  - `pytest-unit-tests` — Runs `pytest` on `tests/*.py` files
  - `bats-shell-integration` — Runs `bats` on `tests/shell/*.bats` files
  - `inventory-static-analyzer` — Runs analyzer on all compose files

**Key settings:**
- `fail_fast: false` — Report all violations before stopping
- Stages: `[commit]` for tests (not on `pre-push`)
- `verbose: true` for test runners

#### 1.2 Custom Hook Scripts
**Directory:** `./hooks/`

**Script 1: `python-no-timeout-subprocess.py`**
- Language: Python 3
- Input: List of `.py` files
- Logic:
  - Parse each file for `subprocess.run(` calls
  - Check if `timeout=` is present on the same line or within the call
  - Flag violations with file:line format
  - Return exit code 1 if violations found
- Regex pattern: `subprocess\.run\([^)]*\)` without `timeout=`
- **Special case:** Allow if inside comment or string literal

**Script 2: `python-unsafe-dict-iteration.py`**
- Language: Python 3
- Input: List of `.py` files
- Logic:
  - Detect `for k, v in dict.items()` patterns
  - Check if both variables are used in the following lines (next 5 lines of context)
  - Flag if one variable is unused (indicates incomplete unpacking)
  - Also flag direct dict access `dict[key]` without `.get()` or `try-except`
- Pattern: `for\s+(\w+),\s+(\w+)\s+in\s+\w+\.items\(\)`
- Return exit code 1 if violations found

**Script 3: `shell-unsafe-sed.sh`**
- Language: Bash
- Input: List of shell files
- Logic:
  - Detect `sed 's/.../${VAR}/...'` with unescaped path-like variables
  - Warn if `/` delimiter used with `${STACK_ROOT}` or similar path vars
  - Recommend `|` delimiter or proper escaping
  - Use extended regex where possible (avoid portable portability issues)
- Key check: `sed.*'s[|/].*\${[A-Z_][A-Z0-9_]*}`
- Return exit code 1 if violations found
- **Note:** Make script Darwin-safe (test on both BSD and GNU)

**Script 4: `shell-bash-regex-alternation.sh`**
- Language: Bash
- Input: List of shell files
- Logic:
  - Detect `[[ $var =~ ^(a|b)$ ]]` patterns (bash extended regex doesn't support `()` alternation)
  - Correct syntax is `[[ $var =~ ^(a|b)$ ]]` with `ERE` (Extended Regular Expression) or use `[[ $var == a || $var == b ]]`
  - Flag with file:line and suggest fix
- Key pattern: `\[\[\s*.*=~.*\([^)]*\|[^)]*\)`
- Return exit code 1 if violations found

**Script 5: `shell-docker-compose-no-err.sh`**
- Language: Bash
- Input: List of shell files
- Logic:
  - Detect `docker compose ... config` inside loops or subshells without error handling
  - Check for `|| exit`, `|| return`, `set -e` in parent context
  - Warn if loop continues silently on failure (e.g., `while IFS= read; do ... docker compose config ... done`)
  - Suggest: Add `|| { echo ERROR; exit 1; }` or use `set -e` at function level
- Key pattern: `docker compose.*\n.*done` (loop without error catch)
- Return exit code 1 if violations found

**Script 6: `node-zod-schema-wrapper.js`**
- Language: Node.js / JavaScript
- Input: List of `.js`/`.ts` files
- Logic:
  - Parse files for `inputSchema:` or `outputSchema:` assignments
  - Check if value is directly `z.string()`, `z.object()`, etc. without outer wrapper
  - For `inputSchema`, enforce `z.object({ ... })` wrapper (required by MCP spec)
  - For `outputSchema`, recommend `z.object()` (best practice)
  - Flag violations with file:line
- Pattern: `\b(inputSchema|outputSchema)\s*:\s*(?!z\.object)z\.`
- Return exit code 1 if violations found

#### 1.3 Hook Runner Scripts
**Directory:** `./hooks/`

**Script 7: `run-pytest.sh`**
- Runs: `python3 -m pytest tests/ -v --tb=short`
- Fails if any test fails
- Output goes to stdout (pre-commit will capture)
- Exit code 0 if all pass, 1 if any fail

**Script 8: `run-bats.sh`**
- Checks if `bats` is installed: `command -v bats` or `bats --version`
- Runs: `bats tests/shell/*.bats --tap`
- If bats not installed: warn and skip (exit 0)
- Exit code 0 if all pass or skipped, 1 if any fail

**Script 9: `run-analyzer.sh`**
- Runs: `python3 docs/hive/tools/inventory.py --all --analyze`
- Checks for warnings/errors in output
- Exit code 0 if no errors, 1 if errors found
- Output to stdout for pre-commit

---

## PHASE 2: PSU AUTOMATION LAYER

### Objectives
- Create scheduled jobs in PowerShell Universal (PSU) for continuous validation
- Add REST API endpoints for manual triggering
- Create dashboard panels for real-time monitoring
- Enable fire-and-forget background task pattern

### Deliverables

#### 2.1 PSU Jobs Configuration
**File:** `./stacks/psu-ots/data/Repository/.universal/scripts/dockge-jobs.ps1`

**Job 1: Pre-commit Validation (Hourly)**
- Name: `Pre-commit Enforcement`
- Schedule: Every 60 minutes
- Command: Execute `/nas-repo/scripts/pre-commit-runner.sh --all`
- Report: Save to `/data/reports/precommit-$(date +%s).json`
- Retention: Keep last 24 reports

**Job 2: Shell Integration Tests (15 minutes)**
- Name: `Shell Integration Tests`
- Schedule: Every 15 minutes
- Command: Execute `bats /nas-repo/tests/shell/*.bats --tap --no-parallelize`
- Report: Save to `/data/reports/bats-$(date +%s).json`
- Retention: Keep last 96 reports (24 hours)

**Job 3: Inventory Analyzer (10 minutes)**
- Name: `Static Analyzer`
- Schedule: Every 10 minutes
- Command: Execute `python3 /nas-repo/docs/hive/tools/inventory.py --all --analyze --json`
- Report: Save to `/data/reports/analyzer-latest.json` (always overwrite)
- Retention: Keep last 288 reports (48 hours)

**Job 4: Drift Detection (5 minutes)**
- Name: `Drift Detection`
- Schedule: Every 5 minutes
- Command: Compare git HEAD vs working tree, check compose file consistency
- Report: Save to `/data/reports/drift-$(date +%s).json`
- Retention: Keep last 576 reports (48 hours)

**Common Job Pattern:**
```powershell
# All jobs follow this pattern:
try {
    $output = & "path/to/command" @args
    $result = @{
        timestamp = Get-Date -Format "o"
        status = "success"
        output = $output
        duration_ms = $stopwatch.ElapsedMilliseconds
    }
    $result | ConvertTo-Json -Depth 10 | Out-File $reportPath
} catch {
    $result = @{
        timestamp = Get-Date -Format "o"
        status = "error"
        error = $_.Exception.Message
        duration_ms = $stopwatch.ElapsedMilliseconds
    }
    $result | ConvertTo-Json -Depth 10 | Out-File $reportPath
}
```

#### 2.2 PSU REST API Endpoints
**File:** `./stacks/psu-ots/data/Repository/.universal/endpoints/dockge-api.ps1`

**Endpoint 1: POST `/api/v1/validate/precommit`**
- Body: `{ "scope": "all" | "files", "files": ["path1", "path2"] }`
- Response: 
  ```json
  {
    "id": "uuid",
    "status": "queued",
    "report_path": "/data/reports/precommit-{id}.json"
  }
  ```
- Queues job and returns immediately (fire-and-forget)

**Endpoint 2: POST `/api/v1/validate/shell`**
- Body: `{ "file": "optional/path/to/test.bats" }`
- Response: Same structure as above

**Endpoint 3: POST `/api/v1/analyzer/run`**
- Body: `{ "stack": "acme-sh" | "all" }`
- Response: Same structure as above

**Endpoint 4: GET `/api/v1/analyzer/report`**
- Query: `?latest=true` or `?id={uuid}`
- Response: 
  ```json
  {
    "id": "uuid",
    "timestamp": "2025-01-15T10:30:00Z",
    "status": "complete",
    "findings": [ ... ],
    "summary": { "errors": 0, "warnings": 3, "info": 12 }
  }
  ```

**Authentication:**
- All endpoints require `Authorization: Bearer {token}` header
- Token from environment: `$PSU_AUTH_TOKEN` (set in compose.yaml)

#### 2.3 PSU Dashboard Panels
**File:** `./stacks/psu-ots/data/Repository/.universal/dashboards/dockge-compliance.ps1`

**Panel 1: Pre-commit Compliance**
- Display: Last 5 runs with status badges (✓ pass, ✗ fail)
- Chart: Pass/fail ratio over 24 hours
- Action: Manual trigger button

**Panel 2: Shell Test Results**
- Display: Last test run summary (N passed, M failed)
- Chart: Test pass rate over time
- Details: Expand to show failing tests

**Panel 3: Analyzer Summary**
- Display: Total issues, breakdown by severity (error/warning/info)
- Stacks table: Per-stack issue count
- Details: Click to expand stack findings

**Panel 4: Drift Detection**
- Display: Last drift check timestamp
- Chart: Drift occurrence timeline
- Details: Show files that drifted

**Panel 5: System Health**
- Display: Uptime, last run times, next scheduled runs
- Alerts: Show if jobs are stuck or failing

---

## PHASE 3: SHELL INTEGRATION TEST SUITE

### Objectives
- Create comprehensive bats test suite for critical shell scripts
- Test valid and invalid scenarios
- Mock external dependencies (curl, docker, etc.)
- Integrate with pre-commit enforcement

### Deliverables

#### 3.1 Bats Test Infrastructure
**File:** `./tests/shell/setup.sh` (shared test utilities)

```bash
# Helper functions:
setup_temp_compose()     # Create temporary compose.yaml
setup_mock_curl()        # Mock curl for HTTP tests
setup_mock_docker()      # Mock docker compose
assert_file_exists()     # Check file presence
assert_file_contains()   # Check file content
```

#### 3.2 Compose Validation Tests
**File:** `./tests/shell/compose-validate.bats`

**Test 1: Valid compose file validates successfully**
- Setup: Create valid compose.yaml
- Run: `bash scripts/compose-validate.sh`
- Assert: Exit code 0

**Test 2: Invalid compose file fails**
- Setup: Create malformed compose.yaml
- Run: `bash scripts/compose-validate.sh`
- Assert: Exit code 1

**Test 3: Missing secrets directory created**
- Setup: Remove `/tmp/test-stacks/grafana-prom/secrets`
- Run: `bash scripts/compose-validate.sh`
- Assert: Directory created, exit code 0

**Test 4: Watchtower bearer token generated**
- Setup: Remove token file
- Run: `bash scripts/compose-validate.sh`
- Assert: Token file created with content

**Test 5: Cleanup on exit**
- Setup: Create temporary .env files
- Run: `bash scripts/compose-validate.sh`
- Assert: Temp files cleaned up, exit code 0

#### 3.3 NAS Init Tests
**File:** `./tests/shell/init-nas.bats`

**Test 1: STACK_ROOT auto-detection works**
- Setup: Create test repo structure
- Run: `bash scripts/init-nas.sh --list-expected-dirs`
- Assert: Correct paths listed

**Test 2: STACK_ROOT written to .env**
- Setup: Create .env
- Run: `bash scripts/init-nas.sh`
- Assert: `STACK_ROOT=` line updated

**Test 3: .env.example copied if .env missing**
- Setup: Remove .env, keep .env.example
- Run: `bash scripts/init-nas.sh`
- Assert: .env created from example

**Test 4: Manifest directories created**
- Setup: Remove all volume directories
- Run: `bash scripts/init-nas.sh`
- Assert: All directories in STACK_MANIFEST created

**Test 5: Hash file written after full init**
- Setup: Fresh run
- Run: `bash scripts/init-nas.sh`
- Assert: `.manifest-hash` file created

**Test 6: --if-changed skips unchanged script**
- Setup: Previous hash file exists and matches
- Run: `bash scripts/init-nas.sh --if-changed`
- Assert: Early exit, no directories created

#### 3.4 HTTP Check Tests
**File:** `./tests/shell/check-dockge-http.bats`

**Test 1: HTTP 200 response passes**
- Setup: Mock curl returning 200
- Run: `bash scripts/check-dockge-http.sh 127.0.0.1:5571`
- Assert: Exit code 0

**Test 2: HTTP 301/302/304 responses pass**
- Setup: Mock curl returning 30X
- Run: Test each code
- Assert: Exit code 0 for all

**Test 3: HTTP 500 response fails**
- Setup: Mock curl returning 500
- Run: `bash scripts/check-dockge-http.sh`
- Assert: Exit code 1

**Test 4: No response fails**
- Setup: Mock curl returning no code (000)
- Run: `bash scripts/check-dockge-http.sh`
- Assert: Exit code 1

**Test 5: Connection timeout fails**
- Setup: Mock curl timeout
- Run: `bash scripts/check-dockge-http.sh`
- Assert: Exit code 1

**Test 6: Custom host:port works**
- Setup: Mock curl on custom address
- Run: `bash scripts/check-dockge-http.sh custom.host:9999`
- Assert: curl called with correct address

---

## PHASE 4: STATIC ANALYZER EXTENSION

### Objectives
- Extend `inventory.py` with 6 new analyzer modules
- Validate compose files against Docker Compose v3.9 schema
- Detect environment variable drift and missing keys
- Validate Traefik and HAProxy configuration consistency
- Generate JSON + Markdown reports

### Deliverables

#### 4.1 New Analyzer Modules
**Directory:** `./docs/hive/tools/analyzers/`

**Module 1: `compose_schema.py`**
- Class: `ComposeSchemaValidator`
- Methods:
  - `validate(compose_dict)` → List[ValidationError]
  - `check_deprecated_fields(compose_dict)` → List[str]
  - `check_depends_on_validity(services)` → List[str]
- Checks:
  - Top-level fields (version, services, networks, volumes, secrets)
  - Service fields (image, ports, volumes, environment, networks, etc.)
  - Port format: `"8080"`, `"8080:8080"`, `"8080:8080/tcp"`
  - Invalid `depends_on` references to non-existent services
  - Deprecated v2 fields (links, build, extends)

**Module 2: `env_validator.py`**
- Class: `EnvValidator`
- Methods:
  - `validate_env_file(path)` → List[ValidationError]
  - `validate_against_example(env_path, example_path)` → List[str] (missing keys)
  - `parse_env(path)` → Dict[str, str]
- Checks:
  - Malformed entries (no `=` sign)
  - Empty keys or values
  - Placeholder values (`CHANGEME`, `REPLACE_ME`, `TODO`)
  - Missing keys vs `.env.example`
  - Environment variable syntax (allow `${}`, `$VAR`)

**Module 3: `label_analyzer.py`**
- Class: `LabelAnalyzer`
- Methods:
  - `validate_traefik_labels(labels_dict)` → List[ValidationError]
  - `check_router_service_pairing(services)` → List[str]
- Checks:
  - Traefik router rules validity
  - Service/middleware name consistency
  - Missing entrypoint declarations
  - Duplicate router names across services
  - Invalid middleware references

**Module 4: `dependency_graph.py`**
- Class: `DependencyGraph`
- Methods:
  - `build_graph(services)` → Graph
  - `detect_cycles()` → List[List[str]]
  - `find_orphaned_services()` → List[str]
  - `topological_sort()` → List[str]
- Uses: `networkx` or custom graph implementation
- Checks:
  - Circular dependencies
  - Unreachable services
  - Services depending on non-existent services

**Module 5: `haproxy_traefik_checker.py`**
- Class: `HAProxyTraefikChecker`
- Methods:
  - `validate_haproxy_config(path)` → List[ValidationError]
  - `validate_traefik_dynamic_config(path)` → List[ValidationError]
  - `check_hostname_consistency(haproxy_map, traefik_labels)` → List[str]
- Checks:
  - HAProxy backend/frontend definitions
  - Traefik dynamic config YAML syntax
  - Hostname/routing consistency
  - Port binding conflicts

**Module 6: `analyzer_report.py`**
- Class: `AnalyzerReport`
- Methods:
  - `generate_json()` → Dict
  - `generate_markdown()` → str
  - `add_finding(severity, module, message)` → None
  - `aggregate_from_all_stacks()` → Report
- Output formats:
  - JSON: `{ "timestamp", "stacks": [ { "name", "findings": [...] } ], "summary": { "errors", "warnings" } }`
  - Markdown: Formatted tables with counts per stack and module

**Module 7: `__init__.py`**
- Exports all analyzer classes
- Version string
- Constants (schema version, etc.)

#### 4.2 Enhanced `inventory.py`
**File:** `./docs/hive/tools/inventory.py` (modified)

**New CLI flags:**
- `--analyze` — Run full analyzer suite on output
- `--json` — Output as JSON (for API consumption)
- `--report-file PATH` — Write report to file
- `--severity [error|warning|info]` — Filter findings

**New integration:**
```python
if args.analyze:
    from analyzers import ComposeSchemaValidator, EnvValidator, etc.
    findings = []
    # Run all validators...
    # Generate report
```

---

## PHASE 5: MEMORY STORAGE

### What to Store

**Category: enforcement**
- Pre-commit hook list (names, purposes, severity)
- Custom hook detection patterns (regex)
- Cross-language rules (Python, Shell, Node.js)

**Category: analyzer**
- Analyzer module architecture
- Schema validation rules (Compose v3.9)
- Dependency graph algorithm
- Report generation templates

**Category: psu-automation**
- Job scheduling intervals
- API endpoint contracts
- Dashboard panel configurations
- Fire-and-forget task pattern

**Category: testing**
- Bats test structure
- Mock strategies for external dependencies
- Test fixture patterns
- Shell test harness design

---

## PHASE 6: CONTINUAL LEARNING

### Patterns to Extract

1. **Safe Shell Scripting:**
   - Always use `set -euo pipefail` at top
   - Escape variables in sed: `sed "s|${VAR}|new|g"` (use `|` as delimiter)
   - Use `|| { echo ERROR; exit 1; }` after critical commands
   - Never use `[[ var =~ ^(a|b)$ ]]` — use `||` or extended regex

2. **Safe Python Subprocess:**
   - Always include `timeout=` parameter
   - Set reasonable timeout (10-30 seconds for most tasks)
   - Wrap in try-except or check return code
   - Use `capture_output=True` to prevent output spam

3. **PSU Automation Pattern:**
   - Fire-and-forget: Execute job, return immediately
   - Store results in files with timestamps
   - Use JSON for machine-readable reports
   - Implement cleanup/retention policy (keep 24-48 hours)

4. **Analyzer Design:**
   - Modular validators (one class per concern)
   - Collect findings, don't fail on first error
   - Generate both machine-readable (JSON) and human-readable (Markdown)
   - Integrate with dashboards/APIs

---

## Implementation Checklist

- [ ] Phase 1: Enhanced `.pre-commit-config.yaml`
- [ ] Phase 1: 6 custom hook scripts (Python, Shell, Node)
- [ ] Phase 1: 3 hook runner scripts (pytest, bats, analyzer)
- [ ] Phase 2: 3 PSU job configuration scripts
- [ ] Phase 2: 4 REST API endpoint definitions
- [ ] Phase 2: 5 dashboard panels
- [ ] Phase 3: Shared test utilities (`setup.sh`)
- [ ] Phase 3: 3 bats test suites (17 tests total)
- [ ] Phase 4: 6 analyzer modules
- [ ] Phase 4: Enhanced `inventory.py` integration
- [ ] Phase 5: Run all pre-commit hooks locally
- [ ] Phase 5: Run pytest suite
- [ ] Phase 5: Run bats tests
- [ ] Phase 5: Run analyzer end-to-end
- [ ] Phase 5: Validate PSU jobs manually
- [ ] Phase 6: Single commit with all enhancements
- [ ] Phase 7: Store patterns in compound-project-memory
- [ ] Phase 8: Extract lessons for continual-learning

---

## Success Criteria

✅ Pre-commit hooks block commits with pattern violations  
✅ All 17 shell tests pass with 100% coverage  
✅ Analyzer runs on all stacks without errors  
✅ PSU jobs execute on schedule  
✅ API endpoints respond with correct JSON  
✅ Dashboard panels display real-time data  
✅ All code is documented and tested  
✅ Single commit with message referencing all 4 enhancements

---

## Quick Reference: File Structure

```
./
├── .pre-commit-config.yaml                    (enhanced)
├── hooks/
│   ├── python-no-timeout-subprocess.py
│   ├── python-unsafe-dict-iteration.py
│   ├── shell-unsafe-sed.sh
│   ├── shell-bash-regex-alternation.sh
│   ├── shell-docker-compose-no-err.sh
│   ├── node-zod-schema-wrapper.js
│   ├── run-pytest.sh
│   ├── run-bats.sh
│   └── run-analyzer.sh
├── tests/
│   ├── shell/
│   │   ├── setup.sh
│   │   ├── compose-validate.bats
│   │   ├── init-nas.bats
│   │   └── check-dockge-http.bats
│   └── test_inventory.py             (existing)
├── docs/hive/tools/
│   ├── inventory.py                  (modified)
│   └── analyzers/
│       ├── __init__.py
│       ├── compose_schema.py
│       ├── env_validator.py
│       ├── label_analyzer.py
│       ├── dependency_graph.py
│       ├── haproxy_traefik_checker.py
│       └── analyzer_report.py
└── stacks/psu-ots/data/Repository/.universal/
    ├── scripts/
    │   ├── dockge-jobs.ps1
    │   └── dockge-api.ps1
    ├── endpoints/
    │   └── dockge-compliance-api.ps1
    └── dashboards/
        └── dockge-compliance.ps1
```

---

**Document Version:** 1.0  
**Last Updated:** 2025-01-15  
**Status:** Ready for Implementation
