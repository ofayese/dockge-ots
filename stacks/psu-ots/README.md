# psu-ots — PowerShell Universal (NAS command center)

PowerShell Universal provides **scheduled jobs**, **API endpoints**, and a **NOC dashboard** over the Dockge monorepo bind (`/nas-repo`) and ACME PEMs (`/certs/acme`).

## Prerequisites

- **TLS:** Host-named wildcard PEMs under `${ACME_CERT_ROOT}/otsorundscore/` (OTS NAS) per [`docs/hive/SERVICE_MAP.md`](../../docs/hive/SERVICE_MAP.md). Traefik rule in compose: `psu.otsorundscore.olutechsys.com`.
- **Network:** `traefik-ots` stack must exist (external Docker network `traefik-ots`).
- **DNS:** Public + split-horizon records for `psu.otsorundscore.olutechsys.com` (and `.olutech.systems` if used).

## First deploy

```bash
cd "${STACK_ROOT}/psu-ots"
cp .env.example .env
# set DOCKGE_USERNAME / DOCKGE_PASSWORD for API checks; optional NAS_PULL_APP_TOKEN for future webhook
docker compose up -d
```

Admin UI: `https://psu.otsorundscore.olutechsys.com` (via Traefik) or publish host port temporarily for bootstrap.

## Repository layout

Versioned PSU config lives under **`data/Repository/`** on the NAS (`.universal/*.ps1`, `Scripts/`, `Apps/`). Runtime DB files under `data/` are gitignored.

**Git-tracked templates:** copy [`universal/`](./universal/) into `data/Repository/.universal/` after first deploy (root `.gitignore` ignores `stacks/**/data/`, so templates ship beside the stack instead of under `data/`).

## Security notes

- **`/nas-repo` is `:ro` in compose** — change to `:rw` only if you implement `git pull` from PSU and accept NAS git hygiene rules ([`AGENTS.md`](../../AGENTS.md)).
- **`POST /api/v1/nas/pull`:** Ship as a follow-up in Admin (App Token + role). **`GET /api/v1/nas/health`** (Phase 2) is registered in `universal/endpoints/dockge-api.ps1` and returns the latest NAS + latency JSON reports (**Bearer `PSU_AUTH_TOKEN`** required).

## Automation

| Script                      | Purpose                                            |
| --------------------------- | -------------------------------------------------- |
| `NAS-Fix-Permissions`       | Runs `fix-permissions.sh` against `PSU_STACK_ROOT` |
| `NAS-Check-Dockge-Status`   | Runs `check-dockge-http.sh`                        |
| `NAS-Detect-Config-Drift`   | `git status` drift hints                           |
| `NAS-Validate-SSL-Certs`    | OpenSSL notAfter on `fullchain.pem`                |
| `NAS-Monitor-Dockge-Stacks` | Dockge API inventory (needs credentials)           |

### Phase 2 — templates under `universal/`

Git-tracked PowerShell templates (copy into `data/Repository/.universal/` on the NAS):

| Path | Role |
|------|------|
| `universal/scripts/dockge-jobs.ps1` | Background jobs **A–G** + backup / remediation / gitops stubs. Each `Invoke-PSUJob_*` queues `Start-Job` and writes timestamped JSON under `PSU_REPORTS_ROOT` (default `/data/reports`) with **48h** retention. |
| `universal/endpoints/dockge-api.ps1` | Registers `/api/v1/*` routes; enforces **`Authorization: Bearer`** vs **`PSU_AUTH_TOKEN`**. Optional: `PSU_ALLOW_STACK_RESTART`, `PSU_REMEDIATION_ENABLED`, `PSU_GITOPS_ENABLED`. |
| `universal/endpoints/dockge-endpoints.ps1` | Dot-sources `dockge-api.ps1` (single entry for the `endpoints/` folder). |
| `universal/dashboards/dockge-compliance.ps1` | NOC panels **A–G** (UD auto-refresh) backed by the JSON reports above. |

**Operational notes:** the PSU container does **not** mount `docker.sock`; stack restarts and deep Docker introspection return **503/501** with guidance to use Dockge UI or host-side automation. **Trivy** / **SMART** probes run only when those tools exist in the image or on the host bind. **GitOps / provision / restore** APIs are explicit **501** placeholders until you wire PAT + `:rw` repo mounts.

## Image pin

`ironmansoftware/universal@sha256:069b858b0f010d522144745ac918cc12c8ea022d516f011fe7e2596efc3a03c4` — tag `2026.1.6-ubuntu-24.04`. Re-resolve digest when upgrading.
