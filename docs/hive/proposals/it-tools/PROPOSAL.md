# PROPOSAL — it-tools

**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md)

## Summary

Smallest stack in the fleet — one stateless service, no env, no volumes, no secrets. Three small changes:

1. Pin `corentinth/it-tools:latest`.
2. Add `TZ` env (low impact for a stateless web app, but consistency with fleet baseline).
3. Add `logging` block + `start_period` to existing healthcheck.
4. Add `.env.example` and `README.md`.

## Changes (ordered)

### Change 1 — `.env.example` and `README.md`

`it-tools/.env.example`:
```
# Stack: it-tools
# Stateless web utility — no real tunables.
TZ=America/New_York
```

`it-tools/README.md`:
```markdown
# it-tools
Web utility belt — JSON formatters, base64, regex tester, etc. Stateless, no DB, no auth.

## Service
- it-tools (8894) — Vue.js single-container app

## Health
HTTP 200 on `/`.

## Rollback
`git checkout -- it-tools/compose.yaml && docker compose -f it-tools/compose.yaml up -d`

## Note
Lowest-risk stack in the fleet. Safe to use as a smoke-test target for compose-tooling changes.
```

### Change 2 — Compose changes

```yaml
services:
  it-tools:
    container_name: IT-Tools
    image: corentinth/it-tools:latest@sha256:<resolved>     # see Change 3
    mem_limit: 256m
    cpu_shares: 256
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped
    ports:
      - 10.0.1.15:8894:80
    environment:
      - TZ=${TZ:-America/New_York}
    labels:
      - com.centurylinklabs.watchtower.enable=true
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:80/ || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s              # added — stateless app boots fast
    networks:
      - bridge
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

networks:
  bridge:
    external: true
```

### Change 3 — Pin image

```bash
docker pull corentinth/it-tools:latest
docker image inspect --format '{{index .RepoDigests 0}}' corentinth/it-tools:latest
```

Use the resolved digest. it-tools releases roughly weekly; expect to bump the digest when you want new tools.

## Verification

```bash
cd /Volumes/docker/dockge/stacks/it-tools
docker compose -f compose.yaml config
docker compose -f compose.yaml up -d
sleep 15
docker inspect --format '{{.State.Health.Status}}' IT-Tools    # expect: healthy
curl -fs http://10.0.1.15:8894/                                # 200
```

## Rollback

```bash
git checkout -- it-tools/compose.yaml it-tools/README.md
docker compose -f it-tools/compose.yaml up -d
```

## Open questions

None — this is a clean apply with no scope ambiguity.
