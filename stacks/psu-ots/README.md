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
- **`POST /api/v1/nas/pull`:** Ship as a follow-up in Admin (App Token + role). A **GET** `/api/v1/nas/health` stub is defined for probes.

## Automation

| Script                      | Purpose                                            |
| --------------------------- | -------------------------------------------------- |
| `NAS-Fix-Permissions`       | Runs `fix-permissions.sh` against `PSU_STACK_ROOT` |
| `NAS-Check-Dockge-Status`   | Runs `check-dockge-http.sh`                        |
| `NAS-Detect-Config-Drift`   | `git status` drift hints                           |
| `NAS-Validate-SSL-Certs`    | OpenSSL notAfter on `fullchain.pem`                |
| `NAS-Monitor-Dockge-Stacks` | Dockge API inventory (needs credentials)           |

## Image pin

`ironmansoftware/universal@sha256:069b858b0f010d522144745ac918cc12c8ea022d516f011fe7e2596efc3a03c4` — tag `2026.1.6-ubuntu-24.04`. Re-resolve digest when upgrading.
