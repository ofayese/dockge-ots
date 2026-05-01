# Hive Report

## 2026-04-30 — HolyClaude rollout evidence

### Scope

- Added HolyClaude dev stack artifacts and proposal.
- Added HAProxy proposal entries for `hcld` hostnames (proposal/config level only).

### Verification evidence

- Compose validation succeeded using local env file.
- Container start and port mapping validated on `3059 -> 3001`.
- In-container `.claude-flow` read/write checks passed.
- Persistence checks passed for recreate and down/up cycles (without `-v`).
- Named volumes confirmed:
  - `holyclaude_claude-home`
  - `holyclaude_cloudcli-data`
- Notify toggle file created at `/home/claude/.claude/notify-on`.

### Risks / notes

- HAProxy apply remains gated behind syntax validation on target package path and controlled reload.
- `docker compose down -v` will remove HolyClaude named volumes and persisted state.

### 2026-04-30 — Secret hygiene and HAProxy stats redaction

- Removed tracked `grafana-prom/.env` and `searxng/settings.yml`; added templates and `.gitignore` coverage for operator secrets.
- HAProxy proposal stats UI line now uses a placeholder password — operators must set real credentials on the NAS only.
- Rotation and optional history rewrite: [`../security/HISTORY_SCRUB.md`](../security/HISTORY_SCRUB.md).

### Rollback (HAProxy `hcld` route)

Revert these additions in `docs/hive/proposals/_haproxy/haproxy.cfg`:

1. `acl host_hcld ...`
2. `use_backend hcld-be if host_hcld`
3. `backend hcld-be` block

After revert:

- Validate config: `haproxy -c -f <path>`
- Reload/apply HAProxy package config
