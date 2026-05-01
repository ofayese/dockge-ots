# ollama

Local LLM runtime (`ollama`) + open-webui front-end. CPU-only on this NAS — no GPU.

## Services

- **otsai-server** (11434) — Ollama REST API; models persist at `/volume1/​docker/dockge​/stacks/ollama/data`
- **otsai-webui** (8893) — open-webui chat UI; depends on `ollama` healthcheck; auth state in `/volume1/​docker/dockge​/stacks/ollama/webui`

## Public hostname

`ai.otsorundscore.olutechsys.com` (referenced in `WEBUI_URL`; resolved via `extra_hosts`).

## Health

- ollama: `curl http://localhost:11434/api/tags` returns JSON
- open-webui: HTTP 200 on `/health` (or `/` as fallback in older versions)

## Models

`DEFAULT_MODELS=phi4:mini` — small enough to run CPU-only at usable latency.

Pull additional models:

```bash
docker exec otsai-server ollama pull <model>
```

## Resource ceiling

Without `mem_limit`, model loading can eat all NAS RAM. The compose enforces:

- ollama: 8g (room for phi4-mini + KV cache + headroom)
- open-webui: 512m (just a Node UI)

If you regularly run larger models (e.g. `llama3.1:70b`), bump `ollama` mem_limit significantly.

## Rollback

```bash
git checkout -- ollama/compose.yaml
docker compose -f ollama/compose.yaml up -d
```

Models survive: `/volume1/​docker/dockge​/stacks/ollama/data` not touched.
User accounts (open-webui) survive: `/volume1/​docker/dockge​/stacks/ollama/webui` not touched.
