# psu-ots — INVENTORY

| Item | Value |
|------|--------|
| Stack | `stacks/psu-ots/` |
| Image | `ironmansoftware/universal@sha256:069b858b0f010d522144745ac918cc12c8ea022d516f011fe7e2596efc3a03c4` (linux, `2026.1.6-ubuntu-24.04`) |
| Ports | **5000** (HTTP) inside container; published on host `${PSU_HOST_IP}:${PSU_HOST_PORT}` for HAProxy backend |
| Volumes | `${STACK_ROOT}/psu-ots/data:/data`; `${DOCKGE_REPO_ROOT:-${STACK_ROOT}/..}:/nas-repo:ro`; `${ACME_CERT_ROOT}:/certs/acme:ro` |
| Networks | default bridge |
| Secrets | `.env`: `DOCKGE_*`, optional `NAS_PULL_APP_TOKEN` (not in git) |
| Health | `curl -fs http://127.0.0.1:5000/` |
| Watchtower | `com.centurylinklabs.watchtower.enable=true` |

## Gaps / follow-up

- Implement secured **`POST /api/v1/nas/pull`** (App Token + role) after first admin login.
- Tighten **`Monitor-DockgeStack.ps1`** against Dockge API JSON for your Dockge version.
- Universal Dashboard cmdlets may need minor edits for your exact PSU build — validate in UI.
