# acme-sh

Containerized acme.sh in daemon mode — issues and renews TLS certificates via Cloudflare DNS-01.

## Operating posture

- `network_mode: host` (required for ACME challenges; do not change)
- `command: daemon` — runs `acme.sh --cron` indefinitely; renewals every 60 days by default

## State on disk

- `/volume1/docker/dockge/stacks/acme-sh/data/` → `/acme.sh` (issuance state, account keys, order history)
- `/volume1/certs/acme/` → `/volume1/certs/acme/` (installed PEMs consumed by other stacks; **do not modify directly**)

## Required env (`.env`, gitignored)

- `CF_Token` — Cloudflare API token with `Zone.DNS Edit` on `olutechsys.com` and `olutech.systems`
- `DISCORD_WEBHOOK_URL` — optional; renewal notifications

See `.env.example` for the full set.

## Health

No probe (host networking + daemon mode → no meaningful liveness probe). Verify health by:

- `docker logs AcmeSh --tail 50` — recent cron ticks
- `ls -la /volume1/certs/acme/<domain>/` — PEMs newer than 90 days
- `docker exec AcmeSh acme.sh --list` — issued certs and expiry dates

## Authoritative references

- [AGENTS.md](AGENTS.md) — local lessons learned (rename pattern, dockerized issue flow, validation)
- [SETUP.md](SETUP.md) — issue/install procedure
- [HIVE_OBJECTIVE.md](../HIVE_OBJECTIVE.md) — repo-wide guardrails

## Rollback

```bash
git checkout -- acme-sh/compose.yaml
docker compose -f acme-sh/compose.yaml up -d
```

Cert issuance state is on disk — survives container rebuild.
