# Task: Network Normalisation + HTTP/HTTPS Routing Fix + OAuth Guide + Stack Optimisation
# Version: 2026-05-08

/coder
/compound-learning
/continuous-learning

======================================================================
CONTEXT
======================================================================

This task addresses five distinct but interrelated problems identified
during the 2026-05-08 bring-up session:

  1. GitHub Desktop creates a double-name Docker network
     (github-desktop_github-desktop-net instead of github-desktop-net).
  2. Docker/Container Manager on DSM auto-assigns subnets from the
     192.168.0.0/20 range for stacks without explicit network blocks.
     All container networks must use the 172.17.0.0/8 space broken
     into /24 segments. 192.168.x.x must not appear in any stack.
  3. Traefik dashboard on 8080 returns 404; ports 6443/8880 drop the
     connection; several containers return
     "Client sent an HTTP request to an HTTPS server." These are
     caused by Traefik entrypoint misconfiguration and mismatch between
     the port Traefik actually listens on vs what Docker publishes.
  4. A Google Workspace OAuth NAS login guide and a stack
     optimisation/customisation guide must be authored under
     docs/hive/.
  5. The plan in docs/tasks/google_workspace_nas_oauth_guide_*.plan.md
     must be executed to completion.

======================================================================
PHASE 0 — PRE-FLIGHT READS
======================================================================

Read before any changes:

  stacks/traefik-ots/compose.yaml
  stacks/traefik-ots/.env.example
  stacks/traefik-ots/config/tls.yaml
  stacks/traefik-mft/compose.yaml
  stacks/github-desktop/compose.yaml
  stacks/holyclaude/compose.yaml
  stacks/portainer/compose.yaml
  stacks/it-tools/compose.yaml
  stacks/searxng/compose.yaml
  stacks/grafana-prom/compose.yaml
  stacks/databases/compose.yaml
  stacks/ollama/compose.yaml
  stacks/rag-stack/compose.yaml
  stacks/dozzle/compose.yaml
  stacks/homepage/compose.yaml
  stacks/watchtower/compose.yaml
  stacks/remotely/compose.yaml
  stacks/zabbix/compose.yaml
  stacks/warp-main/compose.yaml
  stacks/code-server/compose.yaml
  AGENTS.md
  docs/hive/NAS_DEPLOYMENT.md

======================================================================
PHASE 1 — FIX: GitHub Desktop double-name network
======================================================================

PROBLEM:
  Docker Compose generates a network name by prefixing the compose
  project name to the network key. When the project name (derived from
  the directory name) equals the network key, the result is:
    github-desktop_github-desktop-net
  This is a confusing double-name and makes subnet registry tracking
  harder.

CURRENT state in stacks/github-desktop/compose.yaml:
  networks:
    github-desktop-net:          ← network KEY
      name: (not set)            ← no explicit name override
      driver: bridge
      ipam:
        config:
          - subnet: 172.29.0.0/24

FIX: Add `name:` override to pin the exact Docker network name:

  networks:
    github-desktop-net:
      name: github-desktop-net   ← ADD THIS LINE
      driver: bridge
      ipam:
        config:
          - subnet: 172.29.0.0/24
            gateway: 172.29.0.1

Apply to: stacks/github-desktop/compose.yaml

RULE (add to AGENTS.md and NAS_DEPLOYMENT.md):
  Always set `name:` explicitly on every named network block.
  Without it Docker prepends the project name, creating double-name
  artefacts. The `name:` field overrides this behaviour.

======================================================================
PHASE 2 — FIX: Subnet normalisation — remove all 192.168.x.x
======================================================================

PROBLEM:
  Docker on DSM uses the 192.168.0.0/20 pool for auto-assigned default
  networks. Any stack without an explicit network block gets a subnet
  from this range, which may conflict with home LAN, VPN, or other
  subnets. All stacks must use the 172.17.0.0/8 space in /24 segments.

SUBNET REGISTRY (current + additions needed):
  172.17.0.0/16  — Docker host bridge (docker0) — DO NOT USE
  172.20.0.0/24  — github-desktop-net (already assigned)
  172.22.0.0/24  — grafana-net
  172.22.1.0/24  — prometheus-net
  172.29.0.0/24  — github-desktop-net (CONFLICT with 172.20 — see below)

  NOTE: github-desktop has TWO subnet entries in the repo history:
    172.20.0.0/24 (earlier assignment) and 172.29.0.0/24 (later).
  Normalise to 172.20.0.0/24 (first assigned, already in AGENTS.md).

  New /24 allocations for stacks that currently have `networks: {}`
  or no networks block:

  172.23.0.0/24  — traefik-ots (external: false, internal bridge)
  172.23.1.0/24  — traefik-mft
  172.24.0.0/24  — portainer
  172.24.1.0/24  — dozzle
  172.24.2.0/24  — homepage
  172.24.3.0/24  — watchtower
  172.24.4.0/24  — it-tools
  172.25.0.0/24  — databases (mariadb + postgres + adminer)
  172.25.1.0/24  — zabbix
  172.26.0.0/24  — searxng (redis + searxng)
  172.27.0.0/24  — ollama (otsai-server + otsai-webui)
  172.27.1.0/24  — rag-stack (qdrant + anythingllm + pipelines)
  172.28.0.0/24  — holyclaude
  172.28.1.0/24  — remotely
  172.28.2.0/24  — code-server
  172.28.3.0/24  — warp-main
  172.28.4.0/24  — agents_gateway_data
  172.29.0.0/24  — RESERVED (was used for github-desktop — reassign if needed)

CHANGES REQUIRED:
  For each stack listed above that currently has `networks: {}` or no
  explicit network block, add:

  networks:
    <stack-name>-net:
      name: <stack-name>-net
      driver: bridge
      ipam:
        config:
          - subnet: <allocated /24 above>
            gateway: <first host in subnet, e.g. 172.23.0.1>

  And add a `networks:` reference to each service in that stack:

  services:
    <service-name>:
      ...
      networks:
        - <stack-name>-net

  MULTI-SERVICE STACKS: All services in the same stack share ONE
  network (not one per service). Example for databases:
    mariadb, postgres, adminer all join `databases-net` (172.25.0.0/24).

  TRAEFIK EXTERNAL NETWORKS: Services that route through Traefik join
  the traefik-ots network as `external: true`. They should NOT also
  be on a separate subnet unless they have internal service-to-service
  communication needs. The Traefik network is for ingress routing only.

  github-desktop: Change subnet from 172.29.0.0/24 to 172.20.0.0/24
  (original allocation — 172.29 was an error).

  Add `name:` override to grafana-net and prometheus-net in
  stacks/grafana-prom/compose.yaml (they already have subnets,
  just missing the name: override).

AFTER all changes, update the subnet registry table in:
  - AGENTS.md (## Stack Operations Memory → Docker Networks)
  - docs/hive/NAS_DEPLOYMENT.md (## Docker network subnet registry)

======================================================================
PHASE 3 — FIX: Traefik routing — 404, connection drop, HTTP/HTTPS mismatch
======================================================================

PROBLEM ANALYSIS:

  Symptom A: http://10.0.1.15:8080 → "404 page not found"
  Symptom B: https://10.0.1.15:6443 → "server unexpectedly dropped the connection"
             http://10.0.1.15:8880 → same
  Symptom C: Other containers → "Client sent an HTTP request to an HTTPS server"

ROOT CAUSES:

  A) Dashboard 404:
     The compose command block has:
       --api.dashboard=false
       --api.insecure=false
     When api.insecure=false, the dashboard is NOT served on the
     traefik entrypoint port (8080). It returns 404 because no
     route matches. The ping endpoint at /ping IS available on 8080
     (that is why healthcheck passes), but the dashboard root / is not.
     FIX: For dev/testing, enable dashboard. For production, disable
     port 8080 exposure entirely or change to --api.insecure=true
     with --api.dashboard=true.

  B) Port 6443/8880 connection drop:
     The Traefik command configures entrypoints as:
       --entrypoints.web.address=:80       (HTTP, inside container)
       --entrypoints.websecure.address=:443 (HTTPS, inside container)
     But the compose PORTS block maps:
       ${TRAEFIK_HTTP_PUBLISH:-8880}:8880   ← maps 8880 host to 8880 container
       ${TRAEFIK_HTTPS_PUBLISH:-6443}:6443  ← maps 6443 host to 6443 container
     The container does NOT listen on 8880 or 6443 — it listens on
     80 and 443. The published ports have NO matching listener inside
     the container, so the connection drops immediately.
     FIX: Either map the host ports to the correct internal ports:
       - ${TRAEFIK_HTTP_PUBLISH:-8880}:80
       - ${TRAEFIK_HTTPS_PUBLISH:-6443}:443
     OR change the entrypoints to listen on those high ports:
       --entrypoints.web.address=:8880
       --entrypoints.websecure.address=:6443
     The second option is cleaner for this setup where HAProxy owns
     443/80 externally.

  C) "Client sent HTTP request to HTTPS server":
     Containers like Portainer (9443), Traefik TLS, and any service
     using HTTPS internally return this when the browser sends plain
     HTTP to a port serving TLS. This is correct behaviour — the
     container is serving HTTPS and the client sent HTTP.
     FIX: Access these services with https:// in the URL.
     Document in README and Homepage config.

REQUIRED FIXES — stacks/traefik-ots/compose.yaml:

  FIX 1 — Correct port-to-entrypoint mapping:
    Change ports from:
      - ${TRAEFIK_HTTP_PUBLISH:-8880}:8880
      - ${TRAEFIK_HTTPS_PUBLISH:-6443}:6443
      - ${TRAEFIK_DASHBOARD_PORT:-8080}:8080
    To:
      - ${TRAEFIK_HTTP_PUBLISH:-8880}:80
      - ${TRAEFIK_HTTPS_PUBLISH:-6443}:443
      - ${TRAEFIK_DASHBOARD_PORT:-8080}:8080

    The entrypoints keep listening on 80/443 inside the container.
    The host maps 8880→80 and 6443→443 so HAProxy can keep host 443.

  FIX 2 — Dashboard access:
    Change in command block:
      - --api.dashboard=false   →  --api.dashboard=${TRAEFIK_DASHBOARD:-false}
      - --api.insecure=false    →  --api.insecure=${TRAEFIK_DASHBOARD:-false}

    When TRAEFIK_DASHBOARD=true in .env, the dashboard is served on
    http://10.0.1.15:8080/dashboard/ (note trailing slash required).
    When false (production default), 8080 serves only /ping.

  FIX 3 — Update .env.example to document the port mapping:
    Add a comment block explaining:
      # TRAEFIK_HTTP_PUBLISH maps host port -> container port :80
      # TRAEFIK_HTTPS_PUBLISH maps host port -> container port :443
      # Default: HAProxy owns 443/80; Traefik uses 8880/6443 on host.
      # To run Traefik directly on 80/443 (no HAProxy):
      #   TRAEFIK_HTTP_PUBLISH=80
      #   TRAEFIK_HTTPS_PUBLISH=443

  Apply same port fix to: stacks/traefik-mft/compose.yaml

REQUIRED DOCUMENTATION — HTTP vs HTTPS access guide:

  Add to docs/hive/NAS_DEPLOYMENT.md under new section
  "## Container access — HTTP vs HTTPS reference":

  | Container | Port | Protocol | Access URL | Notes |
  |---|---|---|---|---|
  | Traefik dashboard | 8080 | HTTP | http://10.0.1.15:8080/dashboard/ | Trailing slash required; only when TRAEFIK_DASHBOARD=true |
  | Traefik HTTP | 8880 | HTTP | http://10.0.1.15:8880 | Redirects to HTTPS |
  | Traefik HTTPS | 6443 | HTTPS | https://10.0.1.15:6443 | TLS — use https:// |
  | Portainer | 9000 | HTTP | http://10.0.1.15:9000 | Portainer CE HTTP |
  | Portainer | 9443 | HTTPS | https://10.0.1.15:9443 | TLS — use https:// |
  | Portainer Agent | 9001 | HTTPS (mTLS) | Internal only | Not browser-accessible |
  | Dockge | 5571 | HTTP | http://10.0.1.15:5571 | Plain HTTP |
  | Dozzle | 8892 | HTTP | http://10.0.1.15:8892 | Plain HTTP |
  | Homepage | 7575 | HTTP | http://10.0.1.15:7575 | Plain HTTP |
  | IT-Tools | 8894 | HTTP | http://10.0.1.15:8894 | Plain HTTP |
  | SearXNG | 8888 | HTTP | http://10.0.1.15:8888 | Plain HTTP |
  | Grafana | 3340 | HTTP | http://10.0.1.15:3340 | Plain HTTP |
  | holyclaude | 3001 | HTTP | http://10.0.1.15:3001 | Plain HTTP |
  | otsai-webui | 8893 | HTTP | http://10.0.1.15:8893 | Plain HTTP |
  | remotely | 5371 | HTTP | http://10.0.1.15:5371 | Plain HTTP; TLS at reverse proxy |
  | Adminer | 8895 | HTTP | http://10.0.1.15:8895 | Plain HTTP |
  | rag-qdrant | 6333 | HTTP | http://10.0.1.15:6333 | REST API; requires QDRANT_API_KEY if set |
  | rag-anythingllm | 3002 | HTTP | http://10.0.1.15:3002 | NOT 3001 (holyclaude conflict) |
  | rag-pipelines | 9099 | HTTP | http://10.0.1.15:9099 | Plain HTTP |
  | github-desktop | 3405 | HTTP | http://10.0.1.15:3405 | KasmVNC web UI |

  "Client sent an HTTP request to an HTTPS server" error:
    This means you accessed a TLS port using http:// instead of https://.
    Affected ports: 9443 (Portainer), 6443 (Traefik), 9001 (agent).
    Fix: change http:// to https:// in your browser URL.

  "server unexpectedly dropped the connection" error:
    This means the host port is published but the container has no
    listener on the mapped internal port. Check port-to-entrypoint
    alignment in the compose. The most common cause is the Traefik
    high-port issue described above.

======================================================================
PHASE 4 — AUTHOR: Google Workspace OAuth NAS Login Guide
======================================================================

Create docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md

This guide must be complete enough for an operator to follow without
additional research. Read the plan in:
  docs/tasks/google_workspace_nas_oauth_guide_*.plan.md

Key sections required:

  ## Overview and architecture choice
    Path A: DSM SSO Client (recommended for NAS system login)
    Path B: Synology SSO Server app profiles (for app-level SSO)
    Recommendation: Path A for NAS login, Path B for app delegation.

  ## Prerequisites
    - Google Workspace admin access
    - Custom domain with active TLS cert (must match OAuth origins)
    - DSM 7.x with HTTPS enabled on Login Portal
    - User accounts pre-created in DSM with matching email addresses

  ## DNS and TLS alignment rules (critical)
    RULE: OAuth hostname must be covered by the TLS cert SANs.
    RULE: OAuth origins use scheme + host + optional port ONLY
          (no paths, no wildcards in origins).
    RULE: Redirect URIs use exact full paths (no wildcards).
    RULE: All of these must agree:
      - Google Authorized Domains
      - OAuth client JavaScript Origins
      - OAuth client Redirect URIs
      - DSM Login Portal HTTPS hostname
      - TLS certificate SANs
    This repo's cert SANs for OTS NAS:
      *.ots.olutechsys.com, olutechsys.com, *.olutech.systems
    Use a hostname covered by one of these for the OAuth client.
    Recommended: nas.ots.olutechsys.com → 10.0.1.15 (NAS LAN IP)

  ## Google Auth Platform setup (Path A)
    1. console.cloud.google.com → APIs & Services → OAuth consent screen
       - App type: Internal (Google Workspace only)
       - App name: Olutech NAS
       - Authorized domains: olutechsys.com
    2. Create OAuth 2.0 Client ID (Web application type)
       - Name: OTS NAS DSM SSO
       - Authorized JavaScript Origins:
           https://nas.ots.olutechsys.com
           https://nas.ots.olutechsys.com:5001  (DSM HTTPS alt port if used)
       - Authorized Redirect URIs:
           https://nas.ots.olutechsys.com/__ssolib/oauth/callback
           https://nas.ots.olutechsys.com:5001/__ssolib/oauth/callback
       NOTE: Copy client_id and client_secret immediately.
    3. Download the JSON credentials file (keep offline, never commit).

  ## DSM SSO Client configuration (Path A)
    DSM → Control Panel → Domain/LDAP → SSO Client
    → Enable OpenID Connect SSO
    → Profile: Google Workspace
    → Client ID: <from step 2>
    → Client Secret: <from step 2>
    → Redirect URI: must match exactly what was registered
    → Save → Test

  ## Synology SSO Server app profiles (Path B)
    For app-level OAuth (not NAS login):
    Package Center → install SSO Server
    SSO Server → Application → Add
    → Protocol: OIDC
    → Redirect URI: <app callback URL>
    → Copy App ID and App Secret to the consuming app's config.
    NOTE: This does NOT replace NAS system login — it enables
    app-to-app OAuth flows using the NAS as identity provider.

  ## Configuration templates (copy-paste ready)
    Origins example for olutechsys.com setup:
      https://nas.ots.olutechsys.com

    Redirect URIs example:
      https://nas.ots.olutechsys.com/__ssolib/oauth/callback

    Mapping table:
      Public URL                          → Reverse Proxy    → DSM service
      https://nas.ots.olutechsys.com      → Traefik 6443     → DSM :5001
      https://nas.ots.olutechsys.com/dsm → Traefik 6443     → DSM HTTPS

  ## Validation checklist
    □ Certificate SANs cover the OAuth hostname
    □ Origins exactly match scheme + host (no trailing slash, no path)
    □ Redirect URIs exactly match (including path and port)
    □ DSM Login Portal HTTPS is configured and accessible
    □ Test user exists in DSM with matching Google Workspace email
    □ Test SSO login in an incognito window
    □ Verify rollback: DSM local admin account still works after SSO

  ## Common errors and fixes
    origin_mismatch:
      OAuth client origin does not match the browser's current origin.
      Fix: Add the exact scheme+host the browser is using to Origins.
    redirect_uri_mismatch:
      Redirect URI registered != URI sent by DSM.
      Fix: Copy the exact URI from DSM's SSO Client config page.
    cert mismatch / NET::ERR_CERT_AUTHORITY_INVALID:
      DSM is serving a self-signed cert. The OAuth hostname must use
      a valid cert. Use acme-sh to issue a cert for this hostname.
    HTTP/HTTPS mismatch in reverse proxy:
      DSM serves HTTPS internally. If Traefik or nginx proxy sends
      HTTP to DSM, DSM returns "Client sent HTTP to HTTPS server".
      Fix: Set proxy destination to https:// with appropriate TLS
      verification settings.

  ## Rotation and ops runbook
    Client secret rotation:
      1. Google Cloud Console → OAuth client → Edit → Regenerate secret
      2. DSM → SSO Client → update Client Secret → Save
      3. Test immediately; if broken, revert to old secret while debugging
    Rollback:
      DSM → SSO Client → Disable → save → log in with local admin account.

======================================================================
PHASE 5 — AUTHOR: Stack Optimisation and Customisation Guide
======================================================================

Create docs/hive/STACK_OPTIMIZATION_CUSTOMIZATION.md

Use the uploaded reference docs as primary source:
  - About_SearXNG_-_SearXNG.html
  - Search_syntax_-_SearXNG.html
  - Claude_Code_UI_-_API_Documentation.html
  - IT_TOOLS_README.md
  - open_webui_README.md
  - package.json (it-tools version: 2024.10.22-7ca5933)

Sections required:

  ## holyclaude (CloudCLI web UI)
    Safe baseline:
      - Port 3001 (internal); never expose 3059 externally (dev HMR)
      - Set SELKIES_MASTER_TOKEN env var to require auth for the
        web terminal; without it the container runs in Legacy Mode
        (see startup logs: "Legacy Mode ENABLED")
      - Reverse proxy requires WebSocket headers (SignalR/WebSocket)
      - mem_limit 4g; cpu_shares 768 are good defaults
    Optional customisation:
      - Mount /workspace to a persistent STACK_ROOT volume for project
        files to survive container restarts (already in compose)
      - Set DISCORD_WEBHOOK_URL for task notifications from Claude agents
      - Use the /api/agent endpoint for programmatic task dispatch
        (see Claude_Code_UI_-_API_Documentation.html)
      - Update to v2.0.0 when upstream publishes it (fixes @/shared bug)
    Hardening:
      - The web terminal is unauthenticated in Legacy Mode — place
        behind Traefik with auth middleware or restrict to LAN IP only
      - Do not expose port 3001 to WAN without authentication

  ## searxng
    Safe baseline:
      - settings.yml is auto-generated on first boot if not present
      - config dir must be writable by root (chmod 755 minimum)
      - Set SEARXNG_BASE_URL to your public HTTPS URL
      - SEARXNG_REDIS_URL: redis://redis:6379/0 (same compose network)
      - UWSGI_WORKERS=4, UWSGI_THREADS=4: good for NAS homelab
    Useful customisation from settings.yml:
      - Disable noisy engines: set enabled: false for Wikidata, Bing,
        Yahoo (reduces 403 errors at startup)
      - Enable: DuckDuckGo, Google, Brave, Startpage, Qwant
      - Set default language and locale
      - Enable calculator, hash_plugin, unit_converter plugins
      - Set safe_search: 0 (off) for homelab use
      - Set autocomplete: "duckduckgo" for best bang coverage
    Search syntax cheatsheet (from uploaded HTML):
      !wp <query>     → Wikipedia
      !map <query>    → Maps
      !images <query> → Image search
      !!              → Lucky redirect (first result)
      :fr !wp <query> → Wikipedia in French
      !! <bang> <q>   → DuckDuckGo external bang redirect
    vm.overcommit_memory:
      Cannot be set via compose sysctls on DSM (not namespaced).
      Set at host level via Task Scheduler (see NAS_DEPLOYMENT.md).

  ## it-tools
    Safe baseline:
      - Stateless nginx image — no persistent volumes needed
      - Image pinned to 2024.10.22-7ca5933 (package.json confirms this)
      - Runs on port 80 internally → host port 8894
    Optional customisation:
      - No auth by default — add Traefik BasicAuth middleware if
        it-tools should not be publicly accessible
      - Disable unused tools via DISABLE_HOME=true if needed
      - Current version includes: JWT decoder, bcrypt, UUID gen,
        TOML↔YAML, SQL formatter, QR code, network tools, and 100+
        other developer utilities
    Hardening:
      - Stateless, no secrets — low risk as-is
      - If exposed externally, add Traefik auth middleware:
          labels:
            - traefik.http.middlewares.it-tools-auth.basicauth.users=...

  ## rag-stack (anythingllm + qdrant + pipelines) for Open WebUI
    Safe baseline:
      - anythingllm: mount at /app/storage (NOT /app/server/storage)
        Prisma schema resolves ../storage from /app/server working dir
      - anythingllm: host port 3002 (NOT 3001 — conflicts holyclaude)
      - JWT_SECRET: generate with openssl rand -hex 32 before deploy
      - VECTOR_DB=qdrant + QDRANT_ENDPOINT=http://qdrant:6333
      - LLM_PROVIDER=ollama + OLLAMA_BASE_PATH=http://10.0.1.15:11434
      - Pull embedding model first: docker exec otsai-server ollama pull nomic-embed-text
    qdrant:
      - /readyz endpoint is unauthenticated even when QDRANT_API_KEY set
      - Healthcheck uses nc probe (no wget/curl in Rust image)
      - Web UI at http://10.0.1.15:6333/dashboard — requires API key if set
    Open WebUI integration:
      - Connect Open WebUI to pipelines: Settings → Connections → Pipelines
        URL: http://10.0.1.15:9099, Key: ${PIPELINES_API_KEY}
      - Connect Open WebUI to SearXNG: Settings → Web Search
        URL: http://10.0.1.15:8888 (same LAN, no auth needed)
      - Connect to anythingllm: use REST API at http://10.0.1.15:3002/api/v1/
    Optional customisation:
      - anythingllm multi-user mode: set DISABLE_TELEMETRY=true,
        configure teams and workspaces via the UI
      - pipelines: add custom LangChain pipeline scripts to
        STACK_ROOT/rag-stack/config/pipelines/ — hot-reloaded
      - qdrant collections: auto-created by anythingllm on first embed

  ## Validation matrix
    For each recommendation above, document:
      - How to test it works
      - What the failure looks like and how to roll back

    holyclaude:
      Test: open http://10.0.1.15:3001 → no auth prompt in Legacy Mode
      Rollback: remove SELKIES_MASTER_TOKEN from .env and restart

    searxng:
      Test: search query returns results; /healthz returns 200
      Rollback: rm /volume1/docker/dockge/stacks/searxng/config/settings.yml
               restart — will regenerate from template

    it-tools:
      Test: open http://10.0.1.15:8894 → all tools load
      Rollback: docker compose restart (stateless)

    rag-stack:
      Test: anythingllm http://10.0.1.15:3002 → login screen appears
            qdrant http://10.0.1.15:6333/dashboard → collections list
      Rollback: docker compose down → fix env → docker compose up -d
               Data persists in STACK_ROOT/rag-stack/data/

======================================================================
PHASE 6 — DOCS: Cross-link new guides and update existing docs
======================================================================

  1. docs/hive/NAS_DEPLOYMENT.md:
     Add under "## Authentication and Identity":
       → See docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md
     Add under "## Stack tuning and customisation":
       → See docs/hive/STACK_OPTIMIZATION_CUSTOMIZATION.md
     Add the full HTTP/HTTPS access reference table from Phase 3.

  2. README.md:
     Add under "## Architecture overview":
       → See docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md for SSO setup
       → See docs/hive/STACK_OPTIMIZATION_CUSTOMIZATION.md for tuning

  3. stacks/holyclaude/README.md:
     Add pointer: "See docs/hive/STACK_OPTIMIZATION_CUSTOMIZATION.md
     for WebSocket hardening, API auth, and resource tuning."

  4. stacks/searxng/README.md (create if missing):
     Document settings.yml location, engine hygiene, search syntax
     cheatsheet, and vm.overcommit_memory host-level fix.
     Add pointer to STACK_OPTIMIZATION_CUSTOMIZATION.md.

  5. stacks/it-tools/README.md (create if missing):
     Document port, stateless nature, image version, and optional
     Traefik auth middleware pattern.

  6. stacks/rag-stack/README.md:
     Add anythingllm storage mount path note (critical — wrong path
     causes Prisma crash loop).
     Add Open WebUI connection instructions.
     Add pointer to STACK_OPTIMIZATION_CUSTOMIZATION.md.

======================================================================
PHASE 7 — UPDATE AGENTS.md and HIVE_OBJECTIVE.md
======================================================================

  AGENTS.md additions:

  [2026-05-08] Network normalisation:
    - ALL stacks must have explicit network block with name: override.
      Without name:, Docker prepends project name creating double names.
    - All subnets must use 172.17.0.0/8 in /24 segments.
    - 192.168.x.x subnets are FORBIDDEN in compose files.
    - See subnet registry in NAS_DEPLOYMENT.md for allocated ranges.
    - Next free /24: 172.28.5.0/24+

  [2026-05-08] Traefik port mapping rule:
    - Traefik entrypoints listen on :80 (web) and :443 (websecure) INSIDE
      the container. Host port mapping must target these internal ports:
        - ${HOST_HTTP_PORT}:80    (NOT :8880 which has no listener)
        - ${HOST_HTTPS_PORT}:443  (NOT :6443 which has no listener)
    - When api.insecure=false, /dashboard returns 404 (correct behaviour).
      Access dashboard ONLY at http://<host>:<dashboard_port>/dashboard/
      (trailing slash required) with api.insecure=true.
    - "Client sent HTTP to HTTPS server": access with https:// not http://

  [2026-05-08] Google Workspace OAuth:
    - OAuth origins: scheme + host only (no paths, no wildcards)
    - Redirect URIs: exact full path (no wildcards)
    - All must agree: Authorized Domains, Origins, Redirect URIs,
      DSM Login Portal hostname, TLS cert SANs
    - Guide: docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md

  Update HIVE_OBJECTIVE.md:
    - Add docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md to docs list
    - Add docs/hive/STACK_OPTIMIZATION_CUSTOMIZATION.md to docs list

======================================================================
PHASE 8 — VALIDATION
======================================================================

  scripts/compose-validate.sh
  Expected: All compose files validated OK.

  pre-commit run --all-files
  Expected: all hooks pass.

  # No 192.168.x subnets anywhere
  grep -rn "192\.168\." stacks/*/compose.yaml stacks/*/docker-compose.yml
  Expected: zero results.

  # All named networks have name: override
  # For each stack with a networks: block, verify name: is set
  grep -A3 "^networks:" stacks/*/compose.yaml | grep -B2 "driver: bridge" \
    | grep -v "name:"
  Expected: zero results without name: line.

  # Traefik ports map to correct internal ports
  grep -A5 "^    ports:" stacks/traefik-ots/compose.yaml
  Expected: :80 and :443 as container targets.

  # No double-name network artefacts
  grep -rn "github-desktop_github" stacks/
  Expected: zero results.

  Commit:
    git add -A
    git commit -m \
      "fix: subnet normalisation (no 192.168.x), network name overrides, \
traefik port mapping, github-desktop net name; \
feat: Google Workspace OAuth guide, stack optimisation guide, \
HTTP/HTTPS access reference"
    git push

======================================================================
PHASE 9 — CONTINUOUS LEARNING
======================================================================

/continuous-learning

Extract to ~/.cursor/skills/learned/:

  docker-network-naming.md:
    Title: Docker Compose Network Naming — Always Set name: Override
    Problem: Without name:, Docker prepends project name to network key.
      Result: github-desktop_github-desktop-net instead of github-desktop-net.
    Fix: Always add `name: <desired-name>` to every networks: block.
    Rule: network key + name: must both be set; name: wins at runtime.

  traefik-port-entrypoint-alignment.md:
    Title: Traefik Port Mapping Must Target Internal Entrypoint Ports
    Problem: Publishing host:8880 → container:8880 fails when
      Traefik's entrypoint listens on :80 (not :8880).
    Rule: host:${HTTP_PORT}:80, host:${HTTPS_PORT}:443
    Dashboard: requires api.insecure=true AND trailing slash in URL.
    "Connection dropped" = host port published but no container listener.
    "HTTP to HTTPS server" = accessed TLS port with http:// protocol.

  subnet-normalisation.md:
    Title: Docker Subnet Normalisation for Synology DSM
    Problem: DSM auto-assigns 192.168.0.0/20 for default bridge networks,
      which conflicts with home LAN, VPN, and other subnets.
    Fix: Always define explicit network blocks with subnets from
      172.17.0.0/8 in /24 segments. Never use 192.168.x.x in compose.
    Registry: See NAS_DEPLOYMENT.md for allocated /24 ranges.

======================================================================
FINAL PRINT
======================================================================

NETWORK-ROUTING-OAUTH-OPTIMIZATION: COMPLETE
