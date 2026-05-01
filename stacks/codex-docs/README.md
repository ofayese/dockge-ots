# codex-docs

Internal documentation hub powered by codex.team's [codex.docs](https://github.com/codex-team/codex.docs) CMS, backed by MongoDB.

## Services

- **mongodb** — data store, internal-only
- **codex-docs** (8896) — Node.js app; depends on `mongodb` healthcheck

## Required env (`.env`)

- `APP_SECRET` — random 64-char hex; rotate on compromise. Generate with `openssl rand -hex 32`.

See `.env.example` for the full set.

## Public hostname

`otsorundscore.olutechsys.com` (resolved via `extra_hosts` to `10.0.1.15`).

## Health

- mongodb: `mongosh` admin ping
- codex-docs: HTTP 200 on `/`

## Rollback

```bash
git checkout -- codex-docs/compose.yaml
docker compose -f codex-docs/compose.yaml up -d
```

Mongo data persists at `/volume1/docker/dockge/stacks/codex-docs/mongodb`. Never `rm -rf` without a snapshot.

## Status note

This stack historically shipped `APP_SECRET=REPLACE_WITH_RANDOM_SECRET` in compose.yaml. Verify the running container's `APP_SECRET` is a real random value before treating data as authoritative; see `docs/hive/proposals/codex-docs/PROPOSAL.md`.
