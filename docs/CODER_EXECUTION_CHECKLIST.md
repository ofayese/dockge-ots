# Dockge-OTS Enhancements: Coder Execution Checklist

## Overview
This checklist guides the implementation of four major enhancements to the dockge-ots ecosystem through Cursor/Coder.

**Total Tasks:** 23  
**Estimated Time:** 6-8 hours  
**Dependencies:** Python 3.8+, Bash 4.0+, Node.js 16+, bats (optional, tested by hook)

---

## PHASE 1: PRE-COMMIT ENFORCEMENT SYSTEM (9 tasks)

### Setup
- [ ] **1.1** Read `.pre-commit-config.yaml` template in `docs/ENHANCED_TASK_SPECIFICATION.md`
- [ ] **1.2** Create `./hooks/` directory
- [ ] **1.3** Make all hook scripts executable: `chmod +x ./hooks/*.sh ./hooks/*.js ./hooks/*.py`

### Python Hooks
- [ ] **1.4** Create `./hooks/python-no-timeout-subprocess.py`
  - Check: Detects `subprocess.run()` without `timeout=`
  - Check: Allows if inside comment/string
  - Test: Run on `docs/hive/tools/inventory.py` (has one violation on line 386)
  - Expected: Returns exit code 1, prints violation

- [ ] **1.5** Create `./hooks/python-unsafe-dict-iteration.py`
  - Check: Detects `for k, v in dict.items()` where only one is used
  - Check: Flags direct dict access without `.get()`
  - Test: Run on `docs/hive/tools/inventory.py` (should find issue on line 273)
  - Expected: Returns exit code 1 with violation

### Shell Hooks
- [ ] **1.6** Create `./hooks/shell-unsafe-sed.sh`
  - Check: Detects unescaped sed variables with `/` delimiter
  - Check: Recommends `|` delimiter
  - Test: Run on `scripts/init-nas.sh` (has violations on lines 196, 211)
  - Expected: Returns exit code 1, shows warnings
  - Note: Make Darwin-safe (test BSD sed compatibility)

- [ ] **1.7** Create `./hooks/shell-bash-regex-alternation.sh`
  - Check: Detects `[[ $var =~ ^(a|b)$ ]]` patterns
  - Check: Suggests fixes
  - Test: Run on `scripts/check-dockge-http.sh` (has violation on line 15)
  - Expected: Returns exit code 1 with correction suggestion

- [ ] **1.8** Create `./hooks/shell-docker-compose-no-err.sh`
  - Check: Detects `docker compose` in loops without error handling
  - Check: Recommends `|| exit 1` or `set -e`
  - Test: Run on `scripts/compose-validate.sh` (has violation on line 73)
  - Expected: Returns exit code 1, suggests error handling

### Node.js Hook
- [ ] **1.9** Create `./hooks/node-zod-schema-wrapper.js`
  - Check: Detects `inputSchema: z.string()` not wrapped in `z.object()`
  - Check: Flags violations with file:line
  - Test: Run on `stacks/agents_gateway_data/duckduckgo/src/index.js` (has violation on lines 12-15)
  - Expected: Returns exit code 1, suggests wrapping

### Hook Runners
- [ ] **1.10** Create `./hooks/run-pytest.sh`
  - Command: `python3 -m pytest tests/ -v --tb=short`
  - Exit code: 0 if all pass, 1 if any fail
  - Test: Run manually, should show 1 existing test in `tests/test_inventory.py`

- [ ] **1.11** Create `./hooks/run-bats.sh`
  - Command: `bats tests/shell/*.bats --tap`
  - Skip if bats not installed (exit 0 with warning)
  - Test: Run manually (will skip until bats tests created in Phase 3)

- [ ] **1.12** Create `./hooks/run-analyzer.sh`
  - Command: `python3 docs/hive/tools/inventory.py --all --analyze`
  - Parse output for errors
  - Exit code: 0 if no errors, 1 if errors found
  - Test: Run manually, will fail until analyzer modules created in Phase 4

### Integration
- [ ] **1.13** Update `.pre-commit-config.yaml` (already provided in template)
  - Verify: All custom hooks defined in `local` repo section
  - Verify: File patterns correct (Python files in docs/hive/tools/, etc.)
  - Verify: Test runners have `stages: [commit]` and `verbose: true`
  - Test: `pre-commit install && pre-commit run --all-files --hook-stage commit`
  - Expected: Some violations caught (will fix in Phase 4)

---

## PHASE 2: PSU AUTOMATION LAYER (6 tasks)

### PSU Jobs Configuration
- [ ] **2.1** Create `./stacks/psu-ots/data/Repository/.universal/scripts/dockge-jobs.ps1`
  - Job 1: Pre-commit validation (hourly)
  - Job 2: Shell integration tests (15 min)
  - Job 3: Inventory analyzer (10 min)
  - Job 4: Drift detection (5 min)
  - All jobs follow fire-and-forget pattern with JSON report output
  - Reports go to `/data/reports/{job}-{timestamp}.json`
  - Test: Syntax check in PowerShell (`Test-Path`, etc.)

### PSU API Endpoints
- [ ] **2.2** Create PowerShell API endpoint for `/api/v1/validate/precommit`
  - Input: JSON body with scope and optional files
  - Output: `{ id, status, report_path }`
  - Auth: Require Bearer token from `$PSU_AUTH_TOKEN`
  - Action: Queue job, return immediately

- [ ] **2.3** Create PowerShell API endpoint for `/api/v1/validate/shell`
  - Similar pattern to precommit endpoint

- [ ] **2.4** Create PowerShell API endpoint for `/api/v1/analyzer/run`
  - Similar pattern, with stack selection parameter

- [ ] **2.5** Create PowerShell API endpoint for `/api/v1/analyzer/report`
  - Method: GET (not POST)
  - Input: Query params `?latest=true` or `?id={uuid}`
  - Output: Full report JSON with findings and summary

### PSU Dashboard
- [ ] **2.6** Create `./stacks/psu-ots/data/Repository/.universal/dashboards/dockge-compliance.ps1`
  - Panel 1: Pre-commit compliance (last 5 runs, 24h pass/fail chart)
  - Panel 2: Shell test results (summary, chart, expand details)
  - Panel 3: Analyzer summary (issues by severity, per-stack table)
  - Panel 4: Drift detection (last check time, timeline, details)
  - Panel 5: System health (uptime, next scheduled runs, alerts)
  - Each panel has refresh button and last-updated timestamp

---

## PHASE 3: SHELL INTEGRATION TEST SUITE (4 tasks)

### Test Infrastructure
- [ ] **3.1** Create `./tests/shell/setup.sh` with shared utilities
  - Functions:
    - `setup_temp_compose()` — Create temporary compose.yaml with real syntax
    - `teardown_temp()` — Clean up temporary files
    - `setup_mock_curl()` — Intercept curl, control exit codes
    - `setup_mock_docker()` — Intercept docker compose
    - `assert_file_exists()` — Check file presence
    - `assert_file_contains()` — Check content
  - Note: Use bats `@test` syntax and fixtures
  - Test: `source tests/shell/setup.sh` should not error

### Compose Validation Tests
- [ ] **3.2** Create `./tests/shell/compose-validate.bats`
  - 5 tests:
    1. Valid compose file validates successfully
    2. Invalid compose file fails
    3. Missing secrets directory created
    4. Watchtower bearer token generated
    5. Cleanup on exit works
  - Run: `bats tests/shell/compose-validate.bats -v`
  - Expected: 5 tests pass

### NAS Init Tests
- [ ] **3.3** Create `./tests/shell/init-nas.bats`
  - 6 tests:
    1. STACK_ROOT auto-detection
    2. STACK_ROOT written to .env
    3. .env.example copied if missing
    4. Manifest directories created
    5. Hash file written
    6. --if-changed skips unchanged
  - Run: `bats tests/shell/init-nas.bats -v`
  - Expected: 6 tests pass

### HTTP Check Tests
- [ ] **3.4** Create `./tests/shell/check-dockge-http.bats`
  - 6 tests:
    1. HTTP 200 passes
    2. HTTP 301/302/304 pass
    3. HTTP 500 fails
    4. No response (000) fails
    5. Connection timeout fails
    6. Custom host:port works
  - Mock curl behavior using `setup_mock_curl()`
  - Run: `bats tests/shell/check-dockge-http.bats -v`
  - Expected: 6 tests pass

---

## PHASE 4: STATIC ANALYZER EXTENSION (7 tasks)

### Create Analyzer Modules
- [ ] **4.1** Create `./docs/hive/tools/analyzers/__init__.py`
  - Exports: All analyzer classes
  - Version: "1.0.0"
  - Imports: All 6 modules

- [ ] **4.2** Create `./docs/hive/tools/analyzers/compose_schema.py`
  - Class: `ComposeSchemaValidator`
  - Methods: `validate()`, `check_deprecated_fields()`, `check_depends_on_validity()`
  - Test on: `stacks/acme-sh/compose.yaml`
  - Expected: No errors (valid compose)

- [ ] **4.3** Create `./docs/hive/tools/analyzers/env_validator.py`
  - Class: `EnvValidator`
  - Methods: `validate_env_file()`, `validate_against_example()`, `parse_env()`
  - Test on: `stacks/acme-sh/.env` vs `.env.example`
  - Expected: Find any missing keys or placeholders

- [ ] **4.4** Create `./docs/hive/tools/analyzers/label_analyzer.py`
  - Class: `LabelAnalyzer`
  - Methods: `validate_traefik_labels()`, `check_router_service_pairing()`
  - Test on: Services with traefik labels
  - Expected: Validate label structure

- [ ] **4.5** Create `./docs/hive/tools/analyzers/dependency_graph.py`
  - Class: `DependencyGraph`
  - Methods: `build_graph()`, `detect_cycles()`, `find_orphaned_services()`, `topological_sort()`
  - Use: `networkx` library (or implement simple graph)
  - Test on: `stacks/databases/compose.yaml` (has mariadb, postgres)
  - Expected: No cycles detected

- [ ] **4.6** Create `./docs/hive/tools/analyzers/haproxy_traefik_checker.py`
  - Class: `HAProxyTraefikChecker`
  - Methods: `validate_haproxy_config()`, `validate_traefik_dynamic_config()`, `check_hostname_consistency()`
  - Test on: `stacks/traefik-ots/` and `stacks/_haproxy/`
  - Expected: Detect any hostname mismatches

- [ ] **4.7** Create `./docs/hive/tools/analyzers/analyzer_report.py`
  - Class: `AnalyzerReport`
  - Methods: `generate_json()`, `generate_markdown()`, `add_finding()`, `aggregate_from_all_stacks()`
  - Output formats:
    - JSON: `{ "timestamp", "stacks": [ ... ], "summary": { "errors", "warnings", "info" } }`
    - Markdown: Formatted tables with counts
  - Test: Generate report manually
  - Expected: Valid JSON and Markdown output

### Integrate Into Inventory
- [ ] **4.8** Modify `./docs/hive/tools/inventory.py`
  - Add CLI flags: `--analyze`, `--json`, `--report-file`, `--severity`
  - Add integration:
    ```python
    if args.analyze:
        from analyzers import *
        findings = []
        # Run validators
        # Generate report
    ```
  - Backwards compatibility: `inventory.py acme-sh` still works as before
  - Test: `python3 docs/hive/tools/inventory.py acme-sh --analyze --stdout`
  - Expected: Shows INVENTORY + analyzer findings

---

## PHASE 5: VALIDATION & TESTING (5 tasks)

### Unit Tests
- [ ] **5.1** Run existing pytest tests
  - Command: `python3 -m pytest tests/ -v`
  - Expected: 1 test passes (test_inventory.py)

### Pre-commit Validation
- [ ] **5.2** Run all pre-commit hooks locally
  - Command: `pre-commit run --all-files --stages commit --hook-stage commit`
  - Expected: Some violations caught (will be fixed below)
  - Expected fixes needed:
    - `inventory.py` line 386: subprocess.run without timeout
    - `inventory.py` line 273: depends_on dict iteration
    - `init-nas.sh` lines 196, 211: sed with unescaped variables
    - `check-dockge-http.sh` line 15: bash regex alternation
    - `compose-validate.sh` line 73: docker compose in loop without error handling
    - `index.js` lines 12-15: Zod schema not wrapped

### Fix Violations
- [ ] **5.3** Fix `inventory.py` violations
  - Line 386: Add `timeout=10` to subprocess.run call
  - Line 273: Use `str(v)` instead of `str(k)` in depends_on dict iteration
  - Test: Re-run hook, should pass

- [ ] **5.4** Fix shell script violations
  - `init-nas.sh`: Use sed with `|` delimiter or proper escaping
  - `check-dockge-http.sh`: Fix regex to `[[ ${code} =~ ^(200|30[1234])$ ]]`
  - `compose-validate.sh`: Add error handling to docker compose in loop
  - Test: Re-run hooks, should pass

- [ ] **5.5** Fix `index.js` Zod schema
  - Wrap `inputSchema` in `z.object({ timezone: z.string() })`
  - Test: Re-run hook, should pass

### Full Test Suite
- [ ] **5.6** Run shell integration tests
  - Command: `bats tests/shell/*.bats -v`
  - Expected: 17 tests pass (5 + 6 + 6)
  - Note: compose-validate.bats may need temp directory setup

- [ ] **5.7** Run analyzer end-to-end
  - Command: `python3 docs/hive/tools/inventory.py --all --analyze --json`
  - Expected: JSON output with findings for all stacks
  - Expected: No fatal errors (warnings OK)

### Git Commit
- [ ] **5.8** Stage all changes and commit
  - Command:
    ```bash
    git add -A
    git commit -m "feat: add pre-commit enforcement, PSU automation, shell integration tests, and full static analyzer
    
    Phase 1: Pre-commit enforcement system with 6 custom hooks (Python subprocess 
    safety, unsafe dict iteration, sed escaping, bash regex, docker compose error 
    handling, Zod schema wrapper) and 3 hook runners (pytest, bats, analyzer).

    Phase 2: PSU automation layer with 4 scheduled jobs (pre-commit validation hourly, 
    shell tests 15min, analyzer 10min, drift detection 5min) and 4 REST API endpoints 
    for triggering validations and fetching reports. Dashboard with real-time 
    compliance panels.

    Phase 3: Shell integration test suite with bats tests for compose-validate.sh, 
    init-nas.sh, and check-dockge-http.sh, including test fixtures and mock environments.

    Phase 4: Full static analyzer framework with 6 modular validators (compose schema 
    v3.9, env drift, Traefik labels, service dependencies, HAProxy/Traefik consistency) 
    integrated into inventory.py with --analyze flag.

    All code production-ready, tested, and immediately executable.
    " --trailer="Assisted-By: gordon-docker-ai"
    ```
  - Expected: Commit succeeds (pre-commit hooks should all pass)

---

## PHASE 6: MEMORY & LEARNING

### Store Patterns
- [ ] **6.1** Document pre-commit enforcement architecture
  - Stored in compound-project-memory with category "enforcement"

- [ ] **6.2** Document analyzer architecture
  - Stored in compound-project-memory with category "analyzer"

- [ ] **6.3** Document PSU automation patterns
  - Stored in compound-project-memory with category "psu-automation"

- [ ] **6.4** Document testing patterns
  - Stored in compound-project-memory with category "testing"

### Extract Lessons
- [ ] **6.5** Create summary for continual-learning
  - Safe shell scripting patterns
  - Safe Python subprocess patterns
  - PSU fire-and-forget automation
  - Modular analyzer design
  - Custom pre-commit hook development

---

## Success Verification Checklist

Run this before considering the task complete:

```bash
# 1. Pre-commit hooks all pass
pre-commit run --all-files --stages commit

# 2. Python unit tests pass
python3 -m pytest tests/ -v

# 3. Shell integration tests pass
bats tests/shell/*.bats -v

# 4. Analyzer runs end-to-end
python3 docs/hive/tools/inventory.py --all --analyze

# 5. All files created and executable
ls -la hooks/ | wc -l          # Should be 9
ls -la tests/shell/*.bats | wc -l  # Should be 3
ls -la docs/hive/tools/analyzers/*.py | wc -l  # Should be 7

# 6. Git status clean
git status                      # Should show clean working tree
git log --oneline -1            # Should show commit message

# 7. PSU scripts present
ls -la stacks/psu-ots/data/Repository/.universal/scripts/
ls -la stacks/psu-ots/data/Repository/.universal/endpoints/
ls -la stacks/psu-ots/data/Repository/.universal/dashboards/
```

---

## Debugging Tips

| Issue | Solution |
|-------|----------|
| Hook script permission denied | `chmod +x ./hooks/*.py ./hooks/*.sh ./hooks/*.js` |
| Pre-commit hook not found | Check `.pre-commit-config.yaml` file paths vs actual file locations |
| Bats not found | `brew install bats-core` (macOS) or `apt-get install bats` (Linux) |
| Python import error in analyzer | Check `from analyzers import ...` path; run from repo root |
| PSU scripts won't run | Check PowerShell execution policy: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned` |
| Compose validation fails | Ensure mock environment variables are set in test setup |

---

## Timeline Estimate

| Phase | Tasks | Time | Status |
|-------|-------|------|--------|
| Phase 1 | 1.1-1.13 | 90 min | Pre-commit system |
| Phase 2 | 2.1-2.6 | 60 min | PSU automation |
| Phase 3 | 3.1-3.4 | 90 min | Shell tests |
| Phase 4 | 4.1-4.8 | 120 min | Analyzer modules |
| Phase 5 | 5.1-5.8 | 60 min | Validation & commit |
| Phase 6 | 6.1-6.5 | 30 min | Memory & learning |
| **Total** | **23** | **~450 min (7.5 hrs)** | **Ready** |

---

**Document Status:** Ready for Cursor/Coder Implementation  
**Last Updated:** 2025-01-15  
**Dependencies:** Defined and versioned
