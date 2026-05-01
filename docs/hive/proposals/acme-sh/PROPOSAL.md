# PROPOSAL — acme-sh

**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md), [`../../../acme-sh/AGENTS.md`](../../../acme-sh/AGENTS.md)

## Summary

This stack is a special case — `network_mode: host` for ACME challenges, `command: daemon` with no listening socket, and operates on cert material outside compose's purview. The baseline gaps reduce to:

1. Pin `neilpang/acme.sh:latest` to a digest. Cert-issuance state is durable on disk, so a digest pin is safe and prevents surprise breakage.
2. Add `.env.example` (currently missing despite `.env` being present and required).
3. Add `logging` block.
4. **Document** the healthcheck exception (host networking + daemon-mode → no meaningful probe).
5. Add stack `README.md`.

## Hard constraints (per HIVE_OBJECTIVE.md guardrails — DO NOT TOUCH)

- `network_mode: host` — required for ACME challenges. Removing it forbidden.
- `/volume1/certs/acme:/volume1/certs/acme` mount and contents — forbidden to modify.
- `CF_Token` and `DISCORD_WEBHOOK_URL` env vars must remain in (gitignored) `.env`.

## Changes (ordered)

### Change 1 — `.env.example` (REQUIRED)

`acme-sh/.env.example`:
```
# Stack: acme-sh
# Required (secrets):
CF_Token=                              # Cloudflare API token with DNS:Edit on relevant zones
DISCORD_WEBHOOK_URL=                   # Optional — Discord webhook for issue/renew notifications

# Optional (tunables — usually not changed):
TZ=America/New_York
```

`.env` already exists (per inventory). Verify it's gitignored:
```bash
cd /Volumes/docker/dockge/stacks
git check-ignore acme-sh/.env
# Expected: prints `acme-sh/.env`. If silent, add to root .gitignore.
```

### Change 2 — Pin image by digest

```bash
docker pull neilpang/acme.sh:latest
docker image inspect --format '{{index .RepoDigests 0}}' neilpang/acme.sh:latest
# → e.g. neilpang/acme.sh@sha256:<hex>
```

**Before (line 3):**
```yaml
    image: neilpang/acme.sh:latest
```

**After:**
```yaml
    image: neilpang/acme.sh:latest@sha256:<resolved-digest>
```

**Rationale:** ACME state lives on disk (`/acme.sh` mount) and is portable across image versions. Digest pin = no surprise on `docker compose up`. Watchtower notifies on new digests; bumps are operator-deliberate per AGENTS.md "perform a fresh `acme.sh --issue` after DNS is live" guidance.

### Change 3 — Add `logging` block

Per `_baseline §1`:
```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

### Change 4 — Document healthcheck exception (no compose change; comment only)

Add a comment to the service block:
```yaml
  acme-sh:
    image: neilpang/acme.sh:latest@sha256:<resolved>
    container_name: AcmeSh
    # No healthcheck — `command: daemon` with `network_mode: host` and no listening
    # socket means there is no meaningful liveness probe. Operational signal comes
    # from log lines and successful renewals (visible in DISCORD_WEBHOOK_URL alerts).
```

### Change 5 — Stack `README.md`

Skeleton (cross-reference the existing rich AGENTS.md and SETUP.md instead of duplicating):

```markdown
# acme-sh
Containerized acme.sh in daemon mode — issues and renews TLS certificates via Cloudflare DNS-01.

## Operating posture
- `network_mode: host` (required for ACME challenges)
- `command: daemon` — runs `acme.sh --cron` indefinitely; renewals every 60 days by default

## State on disk
- `/volume1/docker/dockge/stacks/acme-sh/data/` → `/acme.sh` (issuance state, account keys, order history)
- `/volume1/certs/acme/` → `/volume1/certs/acme/` (installed PEMs consumed by other stacks; **do not modify directly**)

## Required env (in `.env`, gitignored)
- CF_Token — Cloudflare API token with `Zone.DNS Edit` on `olutechsys.com` and `olutech.systems`
- DISCORD_WEBHOOK_URL — optional; receive renewal notifications

## Health
No probe (see compose comment). Verify health by:
- `docker logs AcmeSh --tail 50` — should show recent cron ticks
- `ls -la /volume1/certs/acme/<domain>/` — PEMs newer than 90 days

## Authoritative references
- [AGENTS.md](AGENTS.md) — lessons learned (rename pattern, dockerized issue flow, validation)
- [SETUP.md](SETUP.md) — issue/install procedure
- HIVE_OBJECTIVE.md — repo-wide guardrails (no edits to `/volume1/certs/acme/` content)

## Rollback
- `git checkout -- acme-sh/compose.yaml && docker compose -f acme-sh/compose.yaml up -d`
- Cert issuance state is on disk — survives container rebuild.
```

## Verification

```bash
cd /Volumes/docker/dockge/stacks/acme-sh
docker compose -f compose.yaml config
docker compose -f compose.yaml up -d
sleep 5
docker ps --filter name=AcmeSh --format '{{.Status}}'   # Up xs
docker logs AcmeSh --tail 30                             # cron banner

# Confirm digest pin took effect:
docker inspect AcmeSh --format '{{.Config.Image}}'       # should show ...@sha256:...

# Confirm renewals still work end-to-end (next renewal window — don't force unless needed):
docker exec AcmeSh acme.sh --list                        # show issued certs + dates
```

## Rollback

```bash
git checkout -- acme-sh/compose.yaml acme-sh/README.md
docker compose -f acme-sh/compose.yaml up -d
```

If a digest pin lands on an `acme.sh` build that breaks issuance, **immediately** revert and run a manual issue per AGENTS.md to confirm.

## Open questions (operator)

1. **Digest pin vs explicit semver?** `acme.sh` doesn't tag releases as semver on Docker Hub (mostly date-based or `latest`). Digest pin is the only practical "alternate" path. Confirm.
2. **Healthcheck attempt?** A weak proxy could be `[ -f /acme.sh/account.conf ]` checked via `docker exec`, but that's almost trivially-true and would give false confidence. Recommend keeping the documented exception over a fake check.
3. **Backup of `/volume1/docker/dockge/stacks/acme-sh/data/`?** Loss of `account.conf` + `Le_Link*` files means re-registering with Let's Encrypt and re-issuing all certs. Feed into `_backups/PROPOSAL.md`.

## Out of scope (deferred)

- Anything inside `/volume1/certs/acme/` — explicitly forbidden by HIVE_OBJECTIVE.md guardrails.
- Adding a healthcheck that actually tests issuance (would require a test domain + DNS automation; over-engineered).
