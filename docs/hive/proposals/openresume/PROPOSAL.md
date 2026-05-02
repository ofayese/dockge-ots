# PROPOSAL — openresume

**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md)

## Summary

Stateless single-service stack, mostly compliant. Three changes:

1. Pin `xitanggg/open-resume:latest`.
2. Add `TZ` env.
3. Add `logging` block.
4. Add `.env.example` and `README.md`.

## Changes (ordered)

### Change 1 — `.env.example` and `README.md`

`openresume/.env.example`:
```
# Stack: openresume
# All keys are tunables.
TZ=America/New_York

# Override if HAProxy frontend hostname changes.
NEXT_PUBLIC_BASE_URL=https://resume.otsorundscore.olutechsys.com
```

`openresume/README.md`:
```markdown
# openresume
Self-hosted resume builder (Next.js). Stateless — all resume data lives in the user's browser localStorage.

## Service
- openresume (8889) — Next.js production build

## Public hostname
- resume.otsorundscore.olutechsys.com (via HAProxy stretch when ready; resolved via extra_hosts today)

## Health
HTTP 200 on `/`.

## Rollback
`git checkout -- openresume/compose.yaml && docker compose -f openresume/compose.yaml up -d`

## Note
No persistent state on the server side. Container restarts are zero-data-loss.
```

### Change 2 — Compose changes

```yaml
services:
  openresume:
    container_name: OpenResume
    image: xitanggg/open-resume:latest@sha256:<resolved>      # see Change 3
    mem_limit: 512m
    cpu_shares: 512
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped
    ports:
      - 10.0.1.15:8889:3000
    environment:
      - NODE_ENV=production
      - NEXT_PUBLIC_BASE_URL=${NEXT_PUBLIC_BASE_URL:-https://resume.otsorundscore.olutechsys.com}
      - TZ=${TZ:-America/New_York}
    extra_hosts:
      - "otsorundscore.olutechsys.com:10.0.1.15"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:3000/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    labels:
      - com.centurylinklabs.watchtower.enable=true
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
docker pull xitanggg/open-resume:latest
docker image inspect --format '{{index .RepoDigests 0}}' xitanggg/open-resume:latest
```

## Verification

```bash
cd /Volumes/docker/dockge/stacks/openresume
docker compose -f compose.yaml config
docker compose -f compose.yaml up -d
sleep 30
docker inspect --format '{{.State.Health.Status}}' OpenResume    # expect: healthy
curl -fs http://10.0.1.15:8889/                                  # 200, Next.js HTML
```

## Rollback

```bash
git checkout -- openresume/compose.yaml openresume/README.md
docker compose -f openresume/compose.yaml up -d
```

## Open questions

None — clean apply.
