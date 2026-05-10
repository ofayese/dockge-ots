# ADR: ACME PEM deploy hook — host-run script vs in-container

**Status:** Accepted  
**Date:** 2026-05-10  
**Scope:** `stacks/acme-sh/` renewals → Traefik file mounts, HAProxy PEM bundles, optional verify.

## Context

- **Issuer:** only **acme.sh** (this repo’s `acme-sh` stack); no Certbot.
- **Consumers:** Traefik (`traefik-ots` / `traefik-mft`) reads PEM trees from the host; HAProxy loads combined PEM bundles from `${STACK_ROOT}/_haproxy/certs/` (directory must contain **only** `.pem` files).
- **Platform:** Synology DSM + Docker Compose + optional Synology HAProxy package.
- **Risk:** in-container hooks run as the acme-sh container user, lack a stable path to **one** Traefik project dir, and cannot reliably invoke the DSM `haproxy` binary or validate against the **live** `@appdata` config without mounting extra host paths and the Docker socket (undesired expansion of blast radius).

## Decision

**Prefer a host-run deploy script** (`stacks/acme-sh/scripts/deploy_certs.sh`) executed by the operator (or NAS cron/PSU) **after** acme.sh writes PEMs under `${ACME_CERT_ROOT}/<profile>/`. Operators may set **`ACME_PROFILE=otsorundscore`** or **`misfitsds`** (with **`BUNDLE_SPECS` unset**) to stage a **single** HAProxy bundle with the default filename mapping documented in the script header.

## Rationale

1. **Least privilege for acme-sh:** the issuance container keeps host networking for ACME only; it does not need Docker socket, Traefik compose project access, or HAProxy binaries.
2. **Correct reload scope:** Traefik reload must target **only** the stack that owns the profile (`TRAEFIK_PROFILE=ots|mft` or explicit `TRAEFIK_STACK`). A host script with `STACK_ROOT` can `docker compose` in the right directory without cross-restarting both edges by default.
3. **HAProxy safety:** atomic PEM writes, `openssl` checks, then `haproxy -c` against the repo config (or `HAPROXY_CFG`) with **rollback to last-known-good** on validation failure matches DSM operator practice documented in `NAS_DEPLOYMENT.md` / `_haproxy/README.txt`.
4. **DSM cert import:** DSM UI/API steps for **control panel TLS** remain **manual** (see `SETUP.md`); no “pinned DSM version” automation until explicitly scoped.

## Consequences

- Operators wire `--reloadcmd` / cron to call the host script (or run it after `acme.sh --cron` notifications).
- In-container `--reloadcmd` stays limited to chmod/chown on PEM paths if desired; heavy consumers use the script.
- Verification drills use `verify_serving.sh` (OpenSSL SNI) and optional `DISCORD_WEBHOOK_URL` for failures.

## Alternatives considered

- **In-container deploy:** rejected for DSM + dual Traefik + HAProxy validation reasons above unless the image is rebuilt with a dedicated sidecar and explicit mounts (higher coupling).
- **Certbot:** out of scope per repo policy.
