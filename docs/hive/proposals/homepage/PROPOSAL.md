# PROPOSAL — homepage

**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md)

## Summary

Most-compliant stack in the fleet — already has `security_opt`, `restart`, watchtower label, mem/cpu, TZ, healthcheck, `README.md`, and correctly uses `:ro` on `docker.sock`. Three remaining gaps:

1. Pin `ghcr.io/gethomepage/homepage:latest` to a digest or explicit version tag.
2. Add `logging` block.
3. Add `.env.example`.

Also one **RACI** action: per HIVE_OBJECTIVE.md, this stack's worker owns cross-cutting widgets and `HOMEPAGE_ALLOWED_HOSTS`. As HAProxy stretch lands, the allowed-hosts list and per-stack widget specs flow back here.

## Changes (ordered)

### Change 1 — `.env.example`

`homepage/.env.example`:
```
# Stack: homepage
# All keys are tunables, not secrets.
TZ=America/New_York

# Comma-separated list of host:port allowed for direct access.
# Update when HAProxy frontend hostnames change (see _haproxy/PROPOSAL.md).
HOMEPAGE_ALLOWED_HOSTS=10.0.1.15:7575,otsorundscore.olutechsys.com:7575,otsorundscore.olutech.systems:7575,localhost:7575
```

Refactor compose to use `${HOMEPAGE_ALLOWED_HOSTS}` — pulls value from `.env` instead of hardcoded inline:

**Before (compose.yaml line 18–20):**
```yaml
    environment:
      - TZ=America/New_York
      # Allow access from the Synology LAN IP and your domain
      - HOMEPAGE_ALLOWED_HOSTS=10.0.1.15:7575,otsorundscore.olutechsys.com:7575,otsorundscore.olutech.systems:7575,localhost:7575
```

**After:**
```yaml
    environment:
      - TZ=${TZ:-America/New_York}
      - HOMEPAGE_ALLOWED_HOSTS=${HOMEPAGE_ALLOWED_HOSTS:-10.0.1.15:7575,otsorundscore.olutechsys.com:7575,otsorundscore.olutech.systems:7575,localhost:7575}
```

**Rationale:** Inline default keeps current behavior even without `.env`; `.env` lets the operator override allowed-hosts without editing compose.

### Change 2 — Pin image

```bash
docker pull ghcr.io/gethomepage/homepage:latest
docker image inspect --format '{{index .RepoDigests 0}}' ghcr.io/gethomepage/homepage:latest
```

**Before (line 4):**
```yaml
    image: ghcr.io/gethomepage/homepage:latest
```

**After (digest — recommended):**
```yaml
    image: ghcr.io/gethomepage/homepage:latest@sha256:<resolved>
```

**Or (semver tag — also acceptable):**
```yaml
    image: ghcr.io/gethomepage/homepage:v0.10.x
```

(Check Docker Hub or GHCR for current tag scheme — homepage releases on a roughly-monthly cadence.)

### Change 3 — `logging` block

```yaml
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

## RACI follow-ups (separate proposals — out of scope here)

This stack's worker is responsible for the cross-cutting **homepage widget catalog**. Each stack's PROPOSAL flags whether it should expose a widget; the homepage worker collects those and produces a consolidated widget config update against `homepage/config/services.yaml` (or whatever the active config name is — verify against `homepage/config/`).

Current `homepage/config/` and `homepage/CONTAINER_MAPPING.md` exist and presumably represent the current widget setup. Confirm they list all 12 stacks and align with the post-baseline ports — that's a separate audit, not part of this PROPOSAL.

The HAProxy stretch (`_haproxy/haproxy.cfg`) when it lands will introduce `https://homepage.otsorundscore...` — at that point `HOMEPAGE_ALLOWED_HOSTS` must include the new frontend hostname.

## Verification

```bash
cd /Volumes/docker/dockge/stacks/homepage
docker compose -f compose.yaml config
docker compose -f compose.yaml up -d
sleep 30
docker inspect --format '{{.State.Health.Status}}' Homepage    # expect: healthy
curl -fs http://10.0.1.15:7575/                                # dashboard renders
./verify-integration.sh                                         # if the script is still relevant
```

## Rollback

```bash
git checkout -- homepage/compose.yaml
docker compose -f homepage/compose.yaml up -d
```

`.env.example` and any new `.env` are file additions — `git rm` to remove if needed.

## Open questions (operator)

1. **Digest pin or version tag?** Both are acceptable per `_baseline §3`. Homepage's release cadence is moderate; digest pin is fine.
2. **`verify-integration.sh`** — what does it check, and is it still current? Worth a quick read to confirm we're not breaking an integration test by changing the env interpolation.
3. **Widget catalog audit** — separate task or roll into this PROPOSAL? Recommend separate (cross-cutting) since it touches `homepage/config/*.yaml`.
