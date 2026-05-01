# PROPOSAL — ollama

**References:** [`../_baseline/PROPOSAL.md`](../_baseline/PROPOSAL.md), [`./INVENTORY.md`](./INVENTORY.md)

## Summary

The biggest baseline gap in the fleet — both services miss `mem_limit`, `cpu_shares`, `TZ`, healthchecks, logging, and use floating image tags. Five changes:

1. **HIGH** — Add `mem_limit` / `cpu_shares` to both services. Ollama in particular can pin large RAM during model load; without a cap a runaway model can starve the NAS.
2. **HIGH** — Pin both images. `ghcr.io/open-webui/open-webui:main` is especially risky (every commit on `main`).
3. Add healthchecks for both services.
4. Upgrade `depends_on: ollama` from started to `condition: service_healthy` once ollama has a healthcheck.
5. Add `TZ`, `logging`, `.env.example`, `README.md`.

## Changes (ordered by phase)

### Phase A — non-runtime: `.env.example` and `README.md`

`ollama/.env.example`:
```
# Stack: ollama (otsai-server + otsai-webui)
# Optional (tunables):
TZ=America/New_York
OLLAMA_NUM_PARALLEL=1
OLLAMA_MAX_LOADED_MODELS=1
DEFAULT_MODELS=phi4:mini

# (no secrets — open-webui auth state lives in the mounted volume, not env)
```

`ollama/README.md`:
```markdown
# ollama
Local LLM runtime (`ollama`) + open-webui front-end. CPU-only on this NAS — no GPU.

## Services
- otsai-server (11434) — Ollama REST API; models persist at /volume1/.../ollama/data
- otsai-webui (8893) — open-webui chat UI; depends on ollama; auth state in /volume1/.../ollama/webui

## Public hostname
- ai.otsorundscore.olutechsys.com (referenced in WEBUI_URL; resolved via extra_hosts)

## Health
- ollama: `curl http://localhost:11434/api/tags` returns JSON
- open-webui: HTTP 200 on `/health` (or `/` as fallback)

## Models
- DEFAULT_MODELS=phi4:mini — small enough to run CPU-only at usable latency
- Pull more with: `docker exec otsai-server ollama pull <model>`

## Rollback
- `git checkout -- ollama/compose.yaml && docker compose -f ollama/compose.yaml up -d`
- Models survive: `/volume1/docker/dockge/stacks/ollama/data` not touched.
- User accounts (open-webui) survive: `/volume1/docker/dockge/stacks/ollama/webui` not touched.

## Resource ceiling
Without `mem_limit`, model loading can eat all NAS RAM. The compose enforces:
- ollama: 8g (room for phi4-mini + headroom)
- open-webui: 512m (it's just a Node UI)
```

### Phase B — runtime: limits, TZ, logging

```yaml
  ollama:
    container_name: otsai-server
    image: ollama/ollama:0.x.y@sha256:<resolved>      # see Phase C
    mem_limit: 8g            # rationale: phi4:mini ~3GB resident + KV cache + headroom
    cpu_shares: 1024         # heavy compute; let it dominate when active
    security_opt:
      - no-new-privileges:true
    restart: on-failure:5
    ports:
      - 10.0.1.15:11434:11434
    volumes:
      - /volume1/docker/dockge/stacks/ollama/data:/root/.ollama:rw
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_NUM_PARALLEL=1
      - OLLAMA_MAX_LOADED_MODELS=1
      - TZ=America/New_York
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    labels:
      - com.centurylinklabs.watchtower.enable=true
    extra_hosts:
      - "otsorundscore.olutechsys.com:10.0.1.15"

  open-webui:
    container_name: otsai-webui
    image: ghcr.io/open-webui/open-webui:0.x.y@sha256:<resolved>     # see Phase C
    mem_limit: 512m          # rationale: Node + SQLite, no model in-process
    cpu_shares: 512
    security_opt:
      - no-new-privileges:true
    restart: on-failure:5
    ports:
      - 8893:8080
    volumes:
      - /volume1/docker/dockge/stacks/ollama/webui:/app/backend/data:rw
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_AUTH=true
      - WEBUI_NAME=olutechsys AI
      - WEBUI_URL=https://ai.otsorundscore.olutechsys.com
      - DEFAULT_MODELS=phi4:mini
      - TZ=America/New_York
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    labels:
      - com.centurylinklabs.watchtower.enable=true
    extra_hosts:
      - "otsorundscore.olutechsys.com:10.0.1.15"
```

### Phase C — pinning

**Before:** `ollama/ollama:latest`, `ghcr.io/open-webui/open-webui:main`
**After:**

```bash
# Resolve current digests:
docker pull ollama/ollama:latest
docker image inspect --format '{{index .RepoDigests 0}}' ollama/ollama:latest
# → e.g. ollama/ollama@sha256:abc123... — use as `image: ollama/ollama:latest@sha256:abc123...`

docker pull ghcr.io/open-webui/open-webui:main
docker image inspect --format '{{index .RepoDigests 0}}' ghcr.io/open-webui/open-webui:main
```

`open-webui:main` follows `main` branch — every push redeploys. Strongly prefer pinning to a release tag (e.g. `:0.5.5`) once you've confirmed it.

### Phase D — healthchecks (must follow Phase C)

Append to each service:

```yaml
  ollama:
    healthcheck:
      test: ["CMD-SHELL", "curl -fs http://localhost:11434/api/tags >/dev/null || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s        # cold start may load default model

  open-webui:
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/health >/dev/null || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      ollama:
        condition: service_healthy        # was: bare `- ollama`
```

**Confirm `/health` exists** in your pinned open-webui version. If not, fall back to `wget -qO- http://localhost:8080/`.

## Verification

```bash
cd /Volumes/docker/dockge/stacks/ollama
docker compose -f compose.yaml config
docker compose -f compose.yaml up -d
sleep 90    # cold start with model load is slow
docker inspect --format '{{.State.Health.Status}}' otsai-server otsai-webui
# Expect: healthy
curl -fs http://10.0.1.15:11434/api/tags          # JSON list of available models
curl -fs http://10.0.1.15:8893/                   # webui login page
docker stats --no-stream otsai-server otsai-webui # confirm RSS within mem_limit
```

## Rollback

```bash
git checkout -- ollama/compose.yaml ollama/README.md
docker compose -f ollama/compose.yaml up -d
```

If `mem_limit: 8g` causes OOM on a larger model, bump to `12g` before reverting wholesale.

## Open questions (operator)

1. **Right-sizing memory**: 8g for ollama assumes phi4:mini. If you regularly run larger models (`llama3.1:70b` etc.) bump significantly — single-precision 70b ≈ 70+ GB. Confirm intended workload.
2. **`open-webui:main` vs `:<release>`** — pin to a release tag, or accept main-branch churn for latest features?
3. **`/health` endpoint** in your open-webui version — confirm before applying healthcheck.
