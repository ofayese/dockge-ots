# Python Security Audit Report

**Date:** 2026-08-06
**Scope:** All `.py` files in the repository (14 files)
**Auditor:** Automated security audit (Cursor Cloud Agent)

## Executive Summary

Audited 14 Python files across `docs/hive/tools/`, `stacks/synology-api-bridge/`, `hooks/`, and `tests/`. Found **5 findings** ranging from Low to Medium severity. No critical or high-severity vulnerabilities were identified. The codebase follows defensive patterns (e.g., `yaml.safe_load`, list-form `subprocess.run`, allowlisted API endpoints), but has areas where hardening would reduce risk in automated or multi-tenant deployment scenarios.

---

## Finding 1: Path Traversal via CLI `stack` Argument

**Severity:** Medium
**File:** `docs/hive/tools/inventory.py`
**Lines:** 527–535

### Vulnerable Code

```python
def process(stack_name: str, repo_root: Path, write: bool) -> str:
    sr = stacks_root(repo_root)
    stack_path = sr / stack_name           # ← no sanitization of ".." components
    if not stack_path.is_dir():
        sys.exit(f"ERROR: stack folder not found: {stack_path}")
    facts = load_stack(stack_path, repo_root)
    md = render_inventory(facts)
    if write:
        out_dir = repo_root / "docs" / "hive" / "proposals" / stack_name  # ← traversal
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "INVENTORY.md").write_text(md)
```

### Attack Chain

1. Attacker (or compromised automation) invokes: `python inventory.py "../../../tmp/evil"`
2. `stack_path` resolves to a directory outside `stacks/` (e.g., `/tmp/evil`) — if it exists, `is_dir()` passes.
3. `load_stack` searches for a compose file in that directory; if one exists (attacker-planted), its content is parsed.
4. The write path `repo_root / "docs/hive/proposals/../../../tmp/evil/INVENTORY.md"` resolves outside the intended output tree, creating or overwriting files in arbitrary directories relative to `repo_root`.

### Exploitability Assessment

**Requires:** CLI access or an automated pipeline that passes untrusted `stack` values. The `--all` flag uses a hardcoded list and is not affected. The `is_dir()` gate and compose-file lookup limit blind exploitation, but a targeted attacker who controls a directory outside the repo can trigger arbitrary file writes.

### Recommended Fix

```python
stack_path = (sr / stack_name).resolve()
if not stack_path.is_relative_to(sr):
    sys.exit(f"ERROR: stack path escapes stacks root: {stack_name}")
```

Apply the same check to `out_dir` before writing.

---

## Finding 2: Timing Side-Channel in Secret Comparison

**Severity:** Low–Medium
**File:** `stacks/synology-api-bridge/app/main.py`
**Lines:** 22–26

### Vulnerable Code

```python
def _check_secret(x_bridge_secret: str | None) -> None:
    if not EXPECTED_SECRET:
        raise HTTPException(status_code=503, detail="BRIDGE_SHARED_SECRET not configured")
    if not x_bridge_secret or x_bridge_secret != EXPECTED_SECRET:   # ← not constant-time
        raise HTTPException(status_code=401, detail="invalid or missing X-Bridge-Secret")
```

### Attack Chain

1. Python's `!=` operator on strings returns `False` early when it encounters the first differing byte.
2. An attacker with network access can time HTTP responses to `/v1/dsm/ping` or `/v1/syno-api/info` with varying `X-Bridge-Secret` headers.
3. By measuring response latency across many requests, the attacker can infer the secret value one character at a time.

### Exploitability Assessment

**Requires:** Network access to the bridge service, ability to send many timed requests, and the secret must be short enough for the timing difference to be measurable. Practical exploitation is difficult over noisy networks but feasible on localhost or LAN (which is the deployment model for this bridge). Standard cryptographic best practice mandates constant-time comparison for secrets.

### Recommended Fix

```python
import hmac

def _check_secret(x_bridge_secret: str | None) -> None:
    if not EXPECTED_SECRET:
        raise HTTPException(status_code=503, detail="BRIDGE_SHARED_SECRET not configured")
    if not x_bridge_secret or not hmac.compare_digest(x_bridge_secret, EXPECTED_SECRET):
        raise HTTPException(status_code=401, detail="invalid or missing X-Bridge-Secret")
```

---

## Finding 3: Internal Network Topology Leakage via Error Messages

**Severity:** Low
**File:** `stacks/synology-api-bridge/app/main.py`
**Lines:** 51, 66

### Vulnerable Code

```python
# Line 51
raise HTTPException(status_code=502, detail=f"dsm unreachable: {exc!s}") from exc

# Line 66
raise HTTPException(status_code=502, detail=f"syno api info failed: {exc!s}") from exc
```

### Attack Chain

1. An authenticated attacker (holding a valid `X-Bridge-Secret`) sends requests to `/v1/dsm/ping` or `/v1/syno-api/info`.
2. If `DSM_BASE_URL` points to a host that is down, misconfigured, or responds with unexpected errors, the full `httpx.HTTPError` string is returned in the HTTP response body.
3. This can leak: internal IP addresses, hostnames, port numbers, TLS certificate details, DNS resolution errors, and connection timeout details — mapping the internal network topology.

### Exploitability Assessment

**Requires:** Valid `X-Bridge-Secret`. Information disclosure only — no code execution. The bridge is designed for internal use, but defense in depth recommends generic error messages for API responses.

### Recommended Fix

Log the full error server-side; return only a generic message to the caller:

```python
except httpx.HTTPError as exc:
    logger.error("DSM ping failed: %s", exc)
    raise HTTPException(status_code=502, detail="upstream DSM unreachable") from exc
```

---

## Finding 4: Partial Secret Exposure in `.env` Validation Error Messages

**Severity:** Low
**File:** `docs/hive/tools/analyzers/env_validator.py`
**Lines:** 70, 85

### Vulnerable Code

```python
# Line 70 — malformed entry includes up to 50 chars of line content
errors.append(f"{env_path}:{i}: malformed entry (no '='): {line_stripped[:50]}")

# Line 85 — warning includes up to 30 chars of env value
logger.warning(f"{env_path}:{i}: value with spaces (should be quoted?): {key}={value[:30]}")
```

### Attack Chain

1. A `.env` file contains a malformed line where a secret value has been accidentally concatenated without an `=` separator (e.g., `API_SECRETsk-proj-abc123...`).
2. The validator includes up to 50 characters of that line in the error output.
3. If the analyzer report is written to a shared JSON report (via `analyzer_report.py` → `render_json_report`), the partial secret is persisted in the report file and potentially displayed on the PSU dashboard.

### Exploitability Assessment

**Requires:** A malformed `.env` file that happens to contain secrets on broken lines. Accidental exposure rather than targeted attack. The truncation limits exposure, but even partial API keys/tokens can be useful to an attacker.

### Recommended Fix

Redact content from error messages — report the line number and error type without echoing the line content:

```python
errors.append(f"{env_path}:{i}: malformed entry (no '=')")
```

---

## Finding 5: Broad Exception Handler Leaks Internal State to Reports

**Severity:** Low
**File:** `docs/hive/tools/analyzers/analyzer_report.py`
**Lines:** 127–129

### Vulnerable Code

```python
except Exception as e:
    logger.error(f"Error building analyzer report: {e}")
    report['findings']['error'] = str(e)   # ← full exception text in JSON output
```

### Attack Chain

1. An unexpected exception during analysis (e.g., YAML parse error on a crafted compose file, file permission error, or import error) produces an exception string that includes file paths, Python tracebacks, or internal state.
2. The exception text is stored in `report['findings']['error']` and subsequently serialized to JSON (via `render_json_report`) or displayed in Markdown.
3. If reports are shared (e.g., PSU dashboard), internal filesystem paths and Python environment details are disclosed.

### Exploitability Assessment

**Requires:** An error condition during analysis. Low direct impact, but contributes to information gathering for further attacks.

### Recommended Fix

Classify exceptions and return only a safe message:

```python
except Exception as e:
    logger.error("Error building analyzer report: %s", e, exc_info=True)
    report['findings']['error'] = "Analysis failed — see server logs for details"
```

---

## Positive Security Observations

The following defensive patterns are correctly implemented and should be preserved:

| Pattern | Location | Assessment |
|---|---|---|
| `yaml.safe_load()` | `inventory.py:279`, `analyzer_report.py:60` | Prevents unsafe YAML deserialization (no `yaml.load()` anywhere) |
| List-form `subprocess.run` | `inventory.py:238-244, 251-258, 224-230` | Prevents shell injection (no `shell=True`) |
| `timeout=` on all `subprocess.run` | `inventory.py:230, 244, 258` | Prevents process hangs (enforced by pre-commit hook) |
| Allowlisted API endpoints | `synology-api-bridge/main.py:19` | Only `SYNO.API.Info` is accessible; no generic DSM proxy |
| Auth-gated endpoints | `synology-api-bridge/main.py:41, 54, 81` | All non-health endpoints require `X-Bridge-Secret` |
| Fail-closed when unconfigured | `synology-api-bridge/main.py:23-24` | Empty `BRIDGE_SHARED_SECRET` returns 503, not open access |
| Unimplemented File Station | `synology-api-bridge/main.py:82-86` | File Station endpoint returns 501; no directory traversal via API |
| No `eval`/`exec`/`pickle` | All files | No dynamic code execution or unsafe deserialization |
| No SQL | All files | No database code; no SQL injection surface |
| `httpx.AsyncClient(timeout=...)` | `synology-api-bridge/main.py:47, 63` | Outbound HTTP has explicit timeout (prevents SSRF amplification) |

## Files Audited

| File | Lines | Findings |
|---|---|---|
| `docs/hive/tools/inventory.py` | 637 | 1 (path traversal) |
| `docs/hive/tools/analyzers/analyzer_report.py` | 275 | 1 (exception leak) |
| `docs/hive/tools/analyzers/compose_schema.py` | 208 | 0 |
| `docs/hive/tools/analyzers/env_validator.py` | 192 | 1 (partial secret exposure) |
| `docs/hive/tools/analyzers/dependency_graph.py` | 170 | 0 |
| `docs/hive/tools/analyzers/label_analyzer.py` | 174 | 0 |
| `docs/hive/tools/analyzers/haproxy_traefik_checker.py` | 176 | 0 |
| `stacks/synology-api-bridge/app/main.py` | 87 | 2 (timing, info leak) |
| `stacks/synology-api-bridge/app/__init__.py` | 0 | 0 |
| `hooks/python-no-timeout-subprocess.py` | 47 | 0 |
| `hooks/python-unsafe-dict-iteration.py` | 52 | 0 |
| `tests/test_inventory.py` | 59 | 0 |
| `tests/__init__.py` | 0 | 0 |
| `docs/hive/tools/analyzers/__init__.py` | 63 | 0 |
