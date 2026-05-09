# Stack Optimisation and Customisation Guide

> Per-stack tuning for holyclaude, searxng, it-tools, and rag-stack (Open WebUI path).
> Each section separates **safe baseline** from **optional customisation**, with rollback steps.

---

## holyclaude

### Safe baseline
- Port `3001` — web UI. Port `3059` — HMR/dev only; do not expose externally.
- `mem_limit: 4g`, `cpu_shares: 768` — appropriate for an Electron-style web container.
- Workspace mounted at `${HOLYCLAUDE_WORKSPACE:-/volume1/homes/laolufayese}:/workspace`.  
  Files created inside `/workspace` persist on the NAS under the DSM user home.
- Without `SELKIES_MASTER_TOKEN` set, the container runs in **Legacy Mode** — the web terminal is unauthenticated. Restrict to LAN IP only or place behind Traefik auth middleware.

### Optional customisation
- **Persistent project files:** already handled by the `/workspace` mount. No named volumes needed for workspace content.
- **AnythingLLM integration:** set `ANYTHINGLLM_API_URL` and `ANYTHINGLLM_API_TOKEN` in `.env` to give Claude Code sessions access to your ingested document workspace.
- **Fully offline:** leave `ANTHROPIC_API_KEY` and `CURSOR_API_KEY` blank. All inference routes to Ollama at `OLLAMA_HOST`.
- **Discord notifications:** set `DISCORD_WEBHOOK_URL` and `NOTIFY_DISCORD=true` for task completion alerts from Claude agent sessions.

### Hardening
- Place behind Traefik with auth middleware if port `3001` is exposed beyond LAN.
- The `/api/agent` endpoint accepts programmatic task dispatch — restrict or require a token if exposing externally.

### Rollback
Remove `SELKIES_MASTER_TOKEN` from `.env` and restart. Named volumes (`claude-home`, `cloudcli-data`) preserve session state across restarts.

| Test | Expected |
|---|---|
| `curl -fs http://10.0.1.15:3001/` | HTTP 200 |
| Web terminal opens without auth | Legacy Mode active (expected without token) |

---

## searxng

### Safe baseline
- `settings.yml` is auto-generated on first boot if not present. The config dir must be writable by root (`chmod 755` minimum on `/STACK_ROOT/searxng/config`).
- `SEARXNG_BASE_URL` must match the public HTTPS URL served by the reverse proxy.
- `SEARXNG_REDIS_URL=redis://redis:6379/0` — both services on the same `searxng-net` bridge.
- `UWSGI_WORKERS=4, UWSGI_THREADS=4` — good for CPU-only NAS homelab.
- `vm.overcommit_memory` and `net.core.somaxconn` **cannot** be set via compose `sysctls` on DSM (kernel doesn't namespace them). Set at host level via DSM Task Scheduler at boot:
  ```bash
  sysctl vm.overcommit_memory=1 && sysctl net.core.somaxconn=512
  ```

### Useful settings.yml tuning
After first boot, edit `/STACK_ROOT/searxng/config/settings.yml`:

**Disable noisy engines** (reduce 403 errors at startup):
```yaml
engines:
  - name: wikidata
    disabled: true
  - name: bing
    disabled: true
```

**Enable reliable engines:**
- DuckDuckGo, Brave, Startpage, Qwant — good defaults for homelab

**Plugin configuration:**
```yaml
enabled_plugins:
  - 'Hash plugin'
  - 'Self Informations'
  - 'Tracker URL remover'
  - 'Unit converter plugin'
  - 'Calculator'
```

**Safe search:** set `safe_search: 0` for homelab use (no filtering).

**Autocomplete:** set `autocomplete: "duckduckgo"` for broad bang coverage.

### Search syntax cheatsheet (from SearXNG docs)
| Syntax | Effect |
|---|---|
| `!wp paris` | Search Wikipedia |
| `!map london` | Map search |
| `!images cat` | Image search |
| `:fr !wp Zola` | Wikipedia in French |
| `!! Wau Holland` | Redirect to first result |
| `!!wfr query` | DuckDuckGo external bang redirect |

### Rollback
Delete `/STACK_ROOT/searxng/config/settings.yml` and restart. SearXNG will regenerate from template.

| Test | Expected |
|---|---|
| `curl -fs http://10.0.1.15:8888/` | HTTP 200, search page loads |
| Query returns results | At least one engine responding |

---

## it-tools

### Safe baseline
- Stateless nginx image — no persistent volumes needed. Container restart is safe at any time.
- Image pinned to `2024.10.22-7ca5933` (from `package.json` version field).
- Serves on internal port `80` → host `8894`.
- No auth by default — suitable for LAN-only access.

### Optional customisation
- **Traefik auth middleware** (if exposed beyond LAN):
  ```yaml
  labels:
    - traefik.http.middlewares.it-tools-auth.basicauth.users=user:$$apr1$$...
    - traefik.http.routers.it-tools.middlewares=it-tools-auth
  ```
- **Pin Watchtower updates** for stability: set `WATCHTOWER_LABEL_ENABLE=true` and add `com.centurylinklabs.watchtower.enable=false` label if you want to freeze the version.

### Tools available (v2024.10.22)
JWT decoder, UUID generator, bcrypt hasher, QR code generator, TOML↔YAML converter, SQL formatter, regex tester, network subnet calculator, cron expression parser, base64 encoder, and 100+ more.

### Rollback
`docker compose restart it-tools` — stateless, instant rollback.

| Test | Expected |
|---|---|
| `curl -fs http://10.0.1.15:8894/` | HTTP 200 |
| All tools load | No JS errors in browser console |

---

## rag-stack (AnythingLLM + Qdrant + Pipelines) — Open WebUI path

### Safe baseline

**AnythingLLM:**
- Storage mount MUST target `/app/storage` (not `/app/server/storage`). Prisma resolves `../storage` from `/app/server` working directory. Wrong path → crash loop.
- Host port `3002:3001` (NOT `3001` — conflicts with holyclaude).
- `JWT_SECRET`: generate with `openssl rand -hex 32` before first deploy.
- `EMBEDDING_MODEL_PREF=nomic-embed-text:latest` — must be pulled on `otsai-server` before RAG stack starts.

**Qdrant:**
- `/readyz` endpoint is **unauthenticated** even when `QDRANT_API_KEY` is set — correct behaviour.
- Healthcheck uses `nc` TCP probe (no `wget`/`curl` in Rust image).
- Web UI at `http://10.0.1.15:6333/dashboard` — shows collections and vector counts.

**Pipelines:**
- Connect to Open WebUI: Settings → Connections → Pipelines → URL `http://10.0.1.15:9099`, Key `${PIPELINES_API_KEY}`.
- Drop custom LangChain scripts into `${STACK_ROOT}/rag-stack/config/pipelines/` — hot-reloaded.

### Open WebUI integration
- Web search via SearXNG: Settings → Web Search → URL `http://10.0.1.15:8888`
- AnythingLLM REST API: `http://10.0.1.15:3002/api/v1/` — usable from HolyClaude workspace scripts
- Direct Qdrant queries: `http://10.0.1.15:6333/collections`

### First-time AnythingLLM setup
1. Open `http://10.0.1.15:3002`
2. Setup wizard → **LLM Provider: Ollama** → Base URL `http://10.0.1.15:11434` → Model `qwen2.5-coder:7b`
3. Embeddings → **Ollama** → `nomic-embed-text:latest`
4. Vector DB → **Qdrant** → URL `http://10.0.1.15:6333`
5. Create workspaces: NAS Admin, Coding, Research, DevOps
6. Settings → API Keys → Generate → copy to `stacks/holyclaude/.env` as `ANYTHINGLLM_API_TOKEN`

### Rollback
`docker compose down && docker compose up -d`. Data persists in `${STACK_ROOT}/rag-stack/data/`. Qdrant collections survive restart. AnythingLLM workspace config survives restart.

| Test | Expected |
|---|---|
| `curl http://10.0.1.15:3002/api/ping` | `{"online":true}` |
| `curl http://10.0.1.15:6333/readyz` | `{}` (empty JSON, 200 OK) |
| `curl http://10.0.1.15:9099/` | HTTP 200 |

---

## HTTP vs HTTPS reference table

| Container | Host port | Protocol | Access URL | Notes |
|---|---|---|---|---|
| Traefik dashboard | 8080 | HTTP | `http://10.0.1.15:8080/dashboard/` | Trailing slash required; only when `TRAEFIK_DASHBOARD=true` |
| Traefik HTTP | 8880 | HTTP | `http://10.0.1.15:8880` | Redirects to HTTPS |
| Traefik HTTPS | 6443 | HTTPS | `https://10.0.1.15:6443` | TLS — use `https://` |
| Portainer | 9000 | HTTP | `http://10.0.1.15:9000` | |
| Portainer | 9443 | HTTPS | `https://10.0.1.15:9443` | TLS — use `https://` |
| Dockge | 5571 | HTTP | `http://10.0.1.15:5571` | |
| Dozzle | 8892 | HTTP | `http://10.0.1.15:8892` | |
| Homepage | 7575 | HTTP | `http://10.0.1.15:7575` | |
| IT-Tools | 8894 | HTTP | `http://10.0.1.15:8894` | |
| SearXNG | 8888 | HTTP | `http://10.0.1.15:8888` | |
| holyclaude | 3001 | HTTP | `http://10.0.1.15:3001` | |
| Open WebUI | 8893 | HTTP | `http://10.0.1.15:8893` | |
| AnythingLLM | 3002 | HTTP | `http://10.0.1.15:3002` | NOT 3001 |
| Qdrant | 6333 | HTTP | `http://10.0.1.15:6333` | |
| Pipelines | 9099 | HTTP | `http://10.0.1.15:9099` | |
| Ollama API | 11434 | HTTP | `http://10.0.1.15:11434` | |
| Grafana | 3340 | HTTP | `http://10.0.1.15:3340` | |
| Adminer | 8895 | HTTP | `http://10.0.1.15:8895` | |

**"Client sent an HTTP request to an HTTPS server"** → you used `http://` on a TLS port. Switch to `https://`.  
**"Server unexpectedly dropped the connection"** → host port published but no container listener on that internal port. Check port mapping.

---

*See also: [GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md](GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md) | [NAS_DEPLOYMENT.md](NAS_DEPLOYMENT.md)*
