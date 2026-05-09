# ollama

Local LLM runtime (`ollama`) + open-webui front-end. CPU-only on this NAS — no GPU.

## Services

- **otsai-server** (11434) — Ollama REST API; models persist at `${STACK_ROOT}/ollama/data`
- **otsai-webui** (8893) — open-webui chat UI; depends on `ollama` healthcheck; app data under `${STACK_ROOT}/ollama/data/open-webui`

## Volumes

| Host path                              | Container path      | Purpose                                |
| -------------------------------------- | ------------------- | -------------------------------------- |
| `${STACK_ROOT}/ollama/data/ollama`     | `/root/.ollama`     | Ollama model blobs and engine state    |
| `${STACK_ROOT}/ollama/data/open-webui` | `/app/backend/data` | Open WebUI DB, uploads, and auth state |

> `STACK_ROOT` is resolved by `scripts/init-nas.sh` after `git clone`. On Synology use **`/volume1/docker/dockge/stacks`** (see `.env.example` and repo `CLAUDE.md`).

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
git checkout -- compose.yaml
docker compose up -d
```

Models survive under `${STACK_ROOT}/ollama/data/ollama` when you do not delete the bind. Open Webui state survives under `${STACK_ROOT}/ollama/data/open-webui` when you do not delete the bind.
