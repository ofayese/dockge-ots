# PROPOSAL — dozzle

**Owner:** worker `dozzle` (also cross-cutting log-visibility owner) · **Generated:** 2026-04-30
**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md)

## Summary

Three changes:
1. **HIGH** — mount `docker.sock` as `:ro` (Dozzle only reads).
2. **HIGH** — mount the existing `users.yml` so `DOZZLE_AUTH_PROVIDER=simple` actually has users.
3. Apply baseline: pin image, add healthcheck, add TZ, add logging block, right-size `mem_limit`.

## Changes (ordered)

### Change 1 — `docker.sock :ro`

**Before (line 13):**
```yaml
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /volume1/docker/dockge/stacks/dozzle:/data:rw
```

**After:**
```yaml
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /volume1/docker/dockge/stacks/dozzle:/data:rw
```

**Rationale:** Dozzle needs the daemon socket to enumerate containers and stream logs. It does not exec into containers, start/stop them, or modify state. Read-only is sufficient and removes a privilege-escalation surface.

**Risk:** if a future Dozzle feature needs write access (unlikely), this restricts it. Trivial to revert.

### Change 2 — Mount `users.yml` for `simple` auth

**Before (lines 11–18):**
```yaml
    ports:
      - 8892:8080
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /volume1/docker/dockge/stacks/dozzle:/data:rw
    environment:
      DOZZLE_AUTH_PROVIDER: simple
    labels:
      - com.centurylinklabs.watchtower.enable=true
```

**After (volumes section):**
```yaml
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /volume1/docker/dockge/stacks/dozzle:/data:rw
      - /volume1/docker/dockge/stacks/dozzle/users.yml:/data/users.yml:ro
```

**Rationale:** `users.yml` is already in the stack folder but never reaches the container. Without it, `DOZZLE_AUTH_PROVIDER=simple` resolves to "no users defined" and either denies all logins or runs in fall-back mode (depends on Dozzle version). Either state is broken — auth was clearly intended.

**Verification:** after apply, `https://10.0.1.15:8892/login` should accept the credentials defined in `users.yml`.

**Operator action before apply:** review `users.yml` contents and confirm it has at least one user with hashed password (Dozzle uses bcrypt). If not, generate one with:
```bash
docker run --rm amir20/dozzle:latest generate <username> --password <pass>
```
and append the output to `users.yml`.

### Change 3 — Baseline (logging, healthcheck, TZ, image pin, mem right-size)

```yaml
    image: amir20/dozzle:8.x.y      # pin to current minor; choose specific version
    mem_limit: 512m                  # rationale: was 3g; observed RSS for log viewer is <100MB
    cpu_shares: 256                  # rationale: low — passive log streaming
    environment:
      DOZZLE_AUTH_PROVIDER: simple
      TZ: America/New_York
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/healthz >/dev/null || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging:
      driver: json-file
      options:
        max-size: "5m"               # smaller cap — Dozzle's own logs are noisy
        max-file: "3"
```

**Notes:**
- `mem_limit: 3g` → `512m` is a major drop. Confirm with `docker stats Dozzle --no-stream` first. 512m is generous; 256m would also work.
- `cpu_shares: 768` → `256`: same reasoning — Dozzle is I/O-bound, not CPU-bound.
- Healthcheck endpoint `/healthz` is documented for Dozzle ≥ v6; verify against the pinned version.
- Image pin: pick a specific minor (e.g. `8.10.0`) once you've decided which to deploy. `:latest` tag must not stay.

## Verification

```bash
cd /Volumes/docker/dockge/stacks/dozzle
docker compose -f compose.yaml config
docker compose -f compose.yaml up -d
sleep 30
docker inspect --format '{{.State.Health.Status}}' Dozzle    # expect: healthy
docker stats Dozzle --no-stream                              # confirm RSS << 512m
curl -fs http://10.0.1.15:8892/healthz                       # expect: 200
# Then log in via browser at http://10.0.1.15:8892/ with users.yml credentials
```

## Rollback

```bash
git checkout -- dozzle/compose.yaml
docker compose -f dozzle/compose.yaml up -d
```

If `mem_limit: 512m` causes OOM (unexpected — Dozzle is small), bump to `1g` first before fully reverting.

## Open questions

1. **Healthcheck endpoint** — confirm `/healthz` exists in your chosen Dozzle version (v8 spec). If not, fall back to `wget -qO- http://localhost:8080/`.
2. **Which Dozzle minor to pin?** — current `:latest` resolves to whatever; pick a known-good version after a quick changelog scan.

## RACI follow-up

This stack's worker is also responsible for the cross-cutting `_logging/PROPOSAL.md` (log policy across all 12 stacks). That's a separate document; it will reuse the §1 logging block defined in [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md).
