# Hive tools

Automation for the dockge-ots hive workflow. Single-script tools, no build step, runnable from any CWD inside the repo.

## Why this exists

[HIVE_OBJECTIVE.md](../../../../HIVE_OBJECTIVE.md) M1 requires every stack to ship `docs/hive/proposals/<stack>/INVENTORY.md` covering services, images, ports, volumes, networks, secrets surface, hostname check, and gaps vs baseline. Hand-writing that for 12 stacks is repetitive and drifts. These tools extract the factual half mechanically so reviewers focus on what humans must judge (scope, intent, risk).

## Tools

### `inventory.py` — generate per-stack `INVENTORY.md`

Parses `<stack>/compose.yaml`, the `.env` / `.env.example` / `README.md` presence in the stack folder, and runs the boundary-aware `(?<!ots)orundscore` hostname check from [acme-sh/AGENTS.md](../../../acme-sh/AGENTS.md). Emits a Markdown file matching the M1 spec:

- Services table (name, container, image, **pin classification**, ports, notes)
- Volumes table (host → container → mode)
- Networks (incl. external)
- `extra_hosts` audit (flags non-`otsorundscore` entries)
- Secrets surface — top-level `secrets:` + per-service env keys (keys only, never values)
- Hostname-check results (stale-token hits or "0 hits")
- Gap matrix vs [`../proposals/_baseline/PROPOSAL.md`](../proposals/_baseline/PROPOSAL.md) (`security_opt`, restart, watchtower label, `mem_limit`, `cpu_shares`, `TZ`, image pin, healthcheck, logging)
- **Auto-detected anomalies** — placeholder secrets (`REPLACE_*`/`CHANGEME`/`PLACEHOLDER`); `docker.sock` mounted rw. Malformed env **list** entries (no `=`) are surfaced once in the env table via `parse_env()` (not duplicated here).

#### Usage

```bash
# Single stack → write docs/hive/proposals/<stack>/INVENTORY.md
python3 docs/hive/tools/inventory.py acme-sh

# All 12 stacks at once
python3 docs/hive/tools/inventory.py --all

# Dump to stdout (no file write) — useful for diffing or piping
python3 docs/hive/tools/inventory.py --stdout portainer

# Override repo-root detection (default: walks up looking for HIVE_OBJECTIVE.md)
python3 docs/hive/tools/inventory.py --repo-root /Volumes/docker/dockge dozzle
```

#### What it deliberately does NOT do

- **Narrative.** Action priority, RACI follow-ups, scope questions, rollback narratives belong in `<stack>/PROPOSAL.md`. INVENTORY is facts; PROPOSAL is judgment.
- **Right-sizing.** `mem_limit` recommendations need `docker stats` runtime data — out of scope for static analysis.
- **Read `.env`.** Per repo `permissions.deny` rules and HIVE_OBJECTIVE.md guardrails, only **presence** of `.env` is reported. Values are never read or rendered.
- **Image-pin resolution.** Reports the pin **class** (digest / semver / latest / floating) but does not call `docker pull` to resolve digests. That's a deliberate apply-time step, not an inventory step.

### Pin classification

| Image string | Class | Notes |
|---|---|---|
| `foo/bar:latest@sha256:abc…` | `digest` | preferred per `_baseline §3` |
| `foo/bar:1.2.3` (any digit-bearing tag) | `semver` | acceptable per `_baseline §3` "Alternate" |
| `foo/bar:latest` (or no tag) | `latest` | ✗ baseline violation |
| `foo/bar:main`, `:edge`, `:nightly`, `:lts`, `:alpine-sts` | `floating` | ✗ baseline violation (rolling alias) |

Note: `:lts`, `:alpine-sts`, etc. are *deliberate* rolling aliases by the upstream maintainer, but for our purposes they behave like floating tags — Watchtower sees a different digest and may auto-update across major version boundaries. Pin to the digest you want, or to a digit-bearing tag.

## Future tools (planned)

### `propose.py` — generate `PROPOSAL.md` skeleton (Tier 2)

Will read the same compose + the gap matrix from `inventory.py`, then emit a starter `PROPOSAL.md` containing the baseline diffs needed to bring this stack to parity. Stack-specific issues (scope, intent, security) still get a `## Stack-specific issues` placeholder for human authorship.

### `check-baseline.sh` — exit-code lint (Tier 3)

Exits non-zero with a checklist when any stack violates `_baseline/PROPOSAL.md`. Drop into a pre-commit hook or CI to block regressions on new stacks.

## Adding a new stack

1. Drop `compose.yaml` into a new folder under `/Volumes/docker/dockge/stacks/<new-stack>/`.
2. Add `<new-stack>` to the `STACKS` constant in `inventory.py` (top of `main`).
3. Run `python3 docs/hive/tools/inventory.py <new-stack>`.
4. Review the generated `docs/hive/proposals/<new-stack>/INVENTORY.md` — pay attention to the "Auto-detected anomalies" section.
5. Author `docs/hive/proposals/<new-stack>/PROPOSAL.md` referencing [`../_baseline/PROPOSAL.md`](../proposals/_baseline/PROPOSAL.md) and addressing whatever the gap matrix flagged.

## Testing

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Covers `parse_env()`, `normalize_labels()`, and `depends_on` formatting from `inventory.py`.

## Coding patterns (cross-language)

- **Shell / `sed`:** avoid interpolating arbitrary paths into `sed` replacement text; use **`awk`** with `ENVIRON` for `.env` line updates (see `scripts/init-nas.sh` `replace_stack_root_in_file`).
- **Bash `[[ =~ ]]`:** prefer explicit string comparisons for HTTP status codes (see `scripts/check-dockge-http.sh`).
- **Docker / compose:** subshells in validation loops must **`|| { echo; exit 1; }`** so failures propagate (see `scripts/compose-validate.sh`).
- **Python:** validate compose map/list shapes before iteration; **`subprocess.run(..., timeout=...)`** with **`TimeoutExpired`** fallback + logging (see `hostname_check` in `inventory.py`).
- **Node (MCP):** register tools with **`z.object({...})`** for `inputSchema` / `outputSchema`; wrap **`server.connect`**; handle **`unhandledRejection`** / **`uncaughtException`**.

## Dependencies

- Python 3.10+ (uses `from __future__ import annotations` + PEP 604 union syntax)
- `PyYAML` (`pip install pyyaml`)
- `ripgrep` for the boundary-aware hostname check (optional — script degrades gracefully if absent)

## Caveats

- The script assumes the stack folder name **matches** the top-level `services:` key when there's only one service. For multi-service stacks (databases, code-server, etc.) it lists every service from `services:`.
- Compose files that use `extends:` or `include:` aren't expanded — only the local file is parsed. None of the 12 current stacks use these.
- The hostname check runs `rg` against the relative path **inside the repo**; if you symlink stacks in from elsewhere, run from the repo root.

## Provenance

Built per HIVE_OBJECTIVE.md M1 to replace hand-written inventory drafts and to make the workflow self-service for any future stacks added. Replaces 12 human-authored `INVENTORY.md` files (~830 lines) with consistent generation from compose.yaml + boundary-aware regex.
