<!--
SUPERSEDED — archived 2026-05-09
All phases verified complete. See AGENTS.md ## What Works for outcomes.
This file is retained for historical reference only.
-->

# Task: HAProxy Dockge Access + DNS Review + Macro Gaps Fix
# Version: 2026-05-08
# Plans incorporated:
#   haproxy_+_dockge_access_5e1531d0.plan.md
#   homelab_dns_review_4d799f13.plan.md
#   macro_gaps_review_7306a559.plan.md

/coder
/compound-learning
/continuous-learning

======================================================================
CONTEXT
======================================================================

Three previously-created plans are incorporated here as concrete tasks.
All items are cross-checked against the current repo state — some are
already partially or fully complete. The agent must verify current state
before applying any fix.

PLAN 1 (HAProxy + Dockge):
  - haproxy.cfg already has dockge-be backend (server dockge 10.0.1.15:5571)
  - HAProxy host.map is missing a dockge entry → needs adding
  - NAS operator steps documented for validation and reload

PLAN 2 (DNS Review):
  - SYNOLOGY_DNS_VIEWS.md and DNS_VIEWS_QUICK_REF.md are already well-corrected
    (terminology fix, hairpin-first, SPOF, acme-sh note — all present)
  - setup-dns-views.sh is already hardened (set -euo pipefail, DSM detection,
    mkdir -p, service restart fallback chain, loud failure)
  - Remaining gap: verify-dns-views.sh optional hairpin comparison mode
  - Optional: Mermaid diagram already in SYNOLOGY_DNS_VIEWS.md
  - Verdict: DNS docs are SUBSTANTIALLY COMPLETE — light touch only

PLAN 3 (Macro gaps):
  - restart policy: HIVE_OBJECTIVE.md already documents unless-stopped as default
    (adopted 2026-05-01). The macro gap plan referenced on-failure:5 which was
    the OLD default. No policy conflict exists — unless-stopped IS the baseline.
  - duckduckgo healthcheck: stacks/agents_gateway_data/duckduckgo/compose.yaml
    ALREADY HAS a healthcheck (added during OCI audit). No action needed.
  - docker.sock comment normalisation: multiple phrasings exist. Normalise all
    to a consistent template.
  - README volume tables: many stacks still use hardcoded paths instead of
    ${STACK_ROOT}/... — systematic doc sweep needed.

======================================================================
PHASE 0 — PRE-FLIGHT READS
======================================================================

Read before any changes:

  stacks/_haproxy/haproxy.cfg
  stacks/_haproxy/maps/host.map (if exists)
  docs/hive/SYNOLOGY_DNS_VIEWS.md
  docs/hive/DNS_VIEWS_QUICK_REF.md
  scripts/setup-dns-views.sh
  scripts/verify-dns-views.sh
  stacks/agents_gateway_data/duckduckgo/compose.yaml
  stacks/agents_gateway_data/compose.yaml
  HIVE_OBJECTIVE.md (restart policy section)

======================================================================
PHASE 1 — HAProxy: Add Dockge to host.map
======================================================================

CURRENT STATE:
  stacks/_haproxy/haproxy.cfg already contains:
    backend dockge-be
        option httpchk GET /
        server dockge 10.0.1.15:5571 check

  BUT: The frontend uses a map file for routing:
    use_backend %[req.hdr(host),lower,map(...host.map,homepage-be)]

  Without an entry in host.map, requests to dockge hostname will
  fall through to the homepage-be default.

STEP 1 — Check if host.map exists:
  Command: ls stacks/_haproxy/maps/host.map 2>/dev/null || echo "MISSING"

STEP 2 — If host.map exists, check current entries:
  Command: cat stacks/_haproxy/maps/host.map

STEP 3 — Add dockge entry to host.map:
  The format is: <hostname>\t<backend-name>  (tab-separated, lowercase host)
  Add this line:
    dockge.ots.olutechsys.com      dockge-be

  Also add these variants consistent with other entries (check existing
  format for olutech.systems dual-hostname pattern):
    dockge.otsorundscore.olutechsys.com    dockge-be

  If host.map does not exist, create it at stacks/_haproxy/maps/host.map
  with ALL current backends documented (homepage, portainer, dozzle,
  ittools, searxng, openwebui, codexdocs, adminer, codeserver,
  phpmyadmin, openresume, hcld, dockge).

STEP 4 — Verify haproxy.cfg is valid by checking syntax only
  (cannot run haproxy binary here — mark for NAS validation):
  NOTE FOR OPERATOR: Run on NAS after pull:
    sudo /volume1/@appstore/haproxy/sbin/haproxy -c \
      -f /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg

  If binary path differs: find /volume1/@appstore -name "haproxy" -type f

STEP 5 — Add NAS operator runbook to stacks/_haproxy/README.txt
  (or update existing) with:
    ## Dockge access via HAProxy

    Prerequisite: Dockge container must be mapped 5571:5001 (NOT 5571:5571).
    Verify: docker inspect Dockge --format '{{json .HostConfig.PortBindings}}'
    Expected: {"5001/tcp":[{"HostIp":"0.0.0.0","HostPort":"5571"}]}

    Direct LAN access: http://10.0.1.15:5571/
    Via HAProxy: https://dockge.ots.olutechsys.com/
    (or https://dockge.ots.olutechsys.com:8443/ if HAProxy binds to 8443)

    DNS: Add A record dockge.ots.olutechsys.com → 10.0.1.15 (or CNAME to
    otsorundscore.synology.me.). Covered by *.ots.olutechsys.com wildcard cert.

    HAProxy reload (after haproxy -c passes):
      sudo synopkg restart haproxy
      # or: sudo synosystemctl restart pkgctl-haproxy
      # or: DSM → Package Center → HAProxy → Stop → Start

  Traffic flow diagram:
    Client → HTTPS dockge.ots.olutechsys.com:443
      → HAProxy (TLS termination, PEM from /volume1/docker/dockge/stacks/_haproxy/certs/)
      → host.map lookup → dockge-be
      → http://10.0.1.15:5571/ (Dockge container)
      → container internal port 5001

======================================================================
PHASE 2 — DNS Review: verify-dns-views.sh hairpin mode
======================================================================

CURRENT STATE:
  SYNOLOGY_DNS_VIEWS.md — COMPLETE (all four corrections applied).
  DNS_VIEWS_QUICK_REF.md — COMPLETE.
  setup-dns-views.sh — COMPLETE (hardened).

REMAINING GAP (from plan):
  verify-dns-views.sh needs an explicit --hairpin comparison mode that
  resolves a hostname via both the NAS resolver and the default resolver,
  then compares the results to answer "is split-DNS needed?".

STEP 1 — Read current verify-dns-views.sh:
  Command: cat scripts/verify-dns-views.sh

STEP 2 — If --hairpin mode is already implemented, PASS. Skip to Phase 3.

STEP 3 — If --hairpin mode is missing or incomplete, add it:

  The enhanced --hairpin mode should:
    1. Accept an optional hostname argument (default: otsdrv.ots.olutechsys.com)
    2. Resolve via default resolver (public DNS path)
    3. Resolve via NAS resolver @10.0.1.15 if DNS Server package is running
    4. Compare the two results:
       - If both return the same public IP → hairpin is working or split-DNS
         not yet configured → split-DNS is OPTIONAL
       - If public resolves to public IP but NAS resolves to 10.0.1.x → split-DNS
         IS configured and working → test curl too
       - If public resolves public IP and NAS returns NXDOMAIN or same public IP
         → split-DNS NOT configured → test if curl works anyway (hairpin NAT)
    5. Run curl -kI against the hostname to test reachability regardless

  Template to add to verify-dns-views.sh:
    --hairpin [hostname]
      Compares resolution via default resolver vs @10.0.1.15.
      Then tests curl -kI --max-time 15 https://<hostname>
      Reports:
        [HAIRPIN OK] if curl succeeds via public IP path
        [SPLIT-DNS WORKING] if NAS returns LAN IP
        [SPLIT-DNS NEEDED] if curl fails via public IP path

======================================================================
PHASE 3 — Macro gaps: docker.sock comment normalisation
======================================================================

CURRENT STATE:
  Every docker.sock mount has a comment but phrasings vary:
    "Docker socket (ro): …" (dozzle, watchtower, grafana-prom)
    "Required for the docker.yaml …" (homepage)
    "SECURITY: docker.sock grants …" (code-server, portainer, agents_gateway_data)
    "SECURITY: docker.sock grants Docker API access (host-level)." (agents_gateway_data/duckduckgo)

TARGET TEMPLATE (normalise all mounts to this — single line, consistent):
  Read-only mounts (:ro):
    # docker.sock :ro — Traefik/Dozzle/Homepage/Watchtower reads container labels/stats only.
  Read-write mounts (full Docker API access):
    # SECURITY: docker.sock :rw — grants full Docker API (host-level control). Required for <reason>.

STACKS TO UPDATE (verify each before editing):
  dozzle:
    Change: "Docker socket (ro): …"
    To:     "# docker.sock :ro — Dozzle reads container logs and stats only."

  homepage:
    Change: "Required for the docker.yaml …"
    To:     "# docker.sock :ro — Homepage reads container labels for widget status."

  watchtower:
    Change: "Docker socket (ro): …"
    To:     "# docker.sock :ro — Watchtower reads container images for update checks."

  grafana-prom (cAdvisor):
    Change: existing comment
    To:     "# docker.sock :ro — cAdvisor reads container runtime stats for Prometheus metrics."

  traefik-ots / traefik-mft:
    Keep existing two-line comment (already documented with proper explanation).
    Only normalise if the comment is missing or inconsistent.

  portainer:
    Keep "SECURITY:" prefix — portainer uses :rw which is genuinely higher risk.
    Normalise to:
    "# SECURITY: docker.sock :rw — Portainer requires full Docker API for management UI."

  code-server:
    Keep "SECURITY:" prefix.
    Normalise to:
    "# SECURITY: docker.sock :rw — code-server terminal requires Docker API access."

  agents_gateway_data / duckduckgo:
    Normalise to:
    "# SECURITY: docker.sock :rw — MCP gateway requires Docker API for container tool dispatch."

RULE: Never change the actual volume mount line — only the comment above it.
      Never add comments inside arrays (YAML does not permit inline comments in
      flow sequences).

======================================================================
PHASE 4 — Macro gaps: README volume tables — ${STACK_ROOT} sweep
======================================================================

CURRENT STATE (from plan):
  stacks/zabbix/README.md is the GOLD STANDARD — uses dedicated ## Volumes
  table with ${STACK_ROOT}/... and init-nas.sh callout.

  The following READMEs still use hardcoded paths or missing volume docs:
    stacks/acme-sh/README.md
    stacks/grafana-prom/README.md
    stacks/github-desktop/README.md
    stacks/databases/README.md
    stacks/ollama/README.md
    stacks/homepage/README.md
    stacks/codex-docs/README.md
    stacks/warp-main/README.md
    stacks/agents_gateway_data/README.md
    stacks/docker-model-runner/README.md

  stacks/it-tools/README.md is stateless — no volumes to document.

WHAT TO DO:
  For each README listed above:

  1. Read the current README
  2. Read the corresponding compose.yaml to identify bind mounts
  3. Replace any hardcoded /volume1/docker/dockge/stacks/<stack>/...
     with ${STACK_ROOT}/<stack>/...
  4. Add or update a ## Volumes section using the Zabbix README format:

     ## Volumes

     | Host path | Container path | Mode | Created by |
     |---|---|---|---|
     | `${STACK_ROOT}/<stack>/data` | `/app/data` | rw | `init-nas.sh` |
     | `${STACK_ROOT}/<stack>/config` | `/etc/<app>` | rw | `init-nas.sh` |

     > Run `sudo bash scripts/init-nas.sh` after cloning to create these
     > directories. Without them, the container will fail to bind-mount.

  5. Portainer and code-server are OPERATOR EXCEPTIONS — they use paths
     outside STACK_ROOT. Keep their existing operator-exception wording
     but normalise the variable name format.

IMPORTANT: Do NOT add volume documentation for bind mounts that use
Docker-managed volumes (volumes: claude-home: {} etc.) — only document
host bind mounts.

======================================================================
PHASE 5 — HIVE_OBJECTIVE.md restart policy clarification
======================================================================

CURRENT STATE:
  HIVE_OBJECTIVE.md already has:
    "Default: restart: unless-stopped for long-running services."
    "Adopted: 2026-05-01 — replaces restart: on-failure:5 and restart: always repo-wide."

  The plan referenced a conflict between on-failure:5 and unless-stopped.
  This conflict NO LONGER EXISTS — unless-stopped is the documented baseline.

ACTION:
  Verify the following stacks still use the correct policy:
  Command: grep -rn "restart:" stacks/*/compose.yaml \
    | grep -v "unless-stopped\|# intentional\|\"no\""

  Expected: zero results (all services use unless-stopped or documented exception).

  If any stacks still use on-failure:5 without a documented exception:
    Change restart: on-failure:5 → restart: unless-stopped
    Add inline comment if a specific restart count was intentional:
      restart: unless-stopped  # was on-failure:5; unless-stopped per 2026-05-01 baseline

======================================================================
PHASE 6 — VALIDATION
======================================================================

  scripts/compose-validate.sh
  Expected: All compose files validated OK.

  pre-commit run --all-files
  Expected: all hooks pass.

  # No hardcoded /volume1/docker/dockge/stacks paths in README files
  grep -rn "volume1/docker/dockge/stacks" stacks/*/README.md \
    | grep -v "# EXEMPT\|operator.*exception\|portainer\|code-server"
  Expected: zero results.

  # docker.sock comments are normalised
  grep -rn "docker.sock" stacks/*/compose.yaml | grep -v "# docker.sock\|# SECURITY:"
  Expected: zero results.

  # host.map has dockge entry
  grep "dockge" stacks/_haproxy/maps/host.map
  Expected: at least one line with dockge-be.

  # restart policy consistent
  grep -rn "restart:" stacks/*/compose.yaml \
    | grep -v "unless-stopped\|# intentional\|\"no\""
  Expected: zero results.

  Commit:
    git add \
      stacks/_haproxy/maps/host.map \
      stacks/*/README.md \
      stacks/*/compose.yaml \
      scripts/verify-dns-views.sh
    git commit -m \
      "fix: HAProxy host.map dockge entry; docker.sock comment normalisation; \
README STACK_ROOT volume tables; verify-dns-views hairpin mode; \
restart policy cleanup"
    git push

======================================================================
PHASE 7 — NAS OPERATOR STEPS (human, not agent)
======================================================================

Run these on the NAS AFTER the git push lands.

  Step 1 — Pull:
    cd /volume1/docker/dockge
    find .git/refs -name "*eaDir*" | xargs rm -f 2>/dev/null; true
    git pull --no-rebase

  Step 2 — Validate HAProxy config:
    sudo /volume1/@appstore/haproxy/sbin/haproxy -c \
      -f /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg
    # Expected: Configuration file is valid

  Step 3 — Reload HAProxy:
    sudo synopkg restart haproxy 2>/dev/null \
      || sudo synosystemctl restart pkgctl-haproxy 2>/dev/null \
      || echo "Restart via DSM Package Center → HAProxy → Stop/Start"

  Step 4 — Test Dockge via HAProxy:
    # Direct LAN (should already work)
    curl -sS -o /dev/null -w '%{http_code}\n' http://10.0.1.15:5571/

    # Via HAProxy (requires DNS or /etc/hosts entry for dockge.ots.olutechsys.com)
    curl -k -sS -o /dev/null -w '%{http_code}\n' \
      https://dockge.ots.olutechsys.com/
    # Expected: 200 or 302

  Step 5 — Optional: run hairpin preflight
    bash scripts/verify-dns-views.sh --hairpin otsdrv.ots.olutechsys.com
    # Expected: reports hairpin OK or split-DNS needed

======================================================================
PHASE 8 — COMPOUND MEMORY UPDATE
======================================================================

/compound-learning

Add dated bullet under AGENTS.md -> ## What Works:

  [2026-05-08] HAProxy + Dockge + DNS + macro gaps:
  - HAProxy host.map is the routing table for the https-in frontend.
    Without an entry, requests fall through to the default (homepage-be).
    Format: <lowercase-hostname>\t<backend-name> (tab-separated).
  - haproxy.cfg already has dockge-be backend at 10.0.1.15:5571.
    Dockge must map 5571:5001 (not 5571:5571) for this to work.
  - DNS docs (SYNOLOGY_DNS_VIEWS.md, DNS_VIEWS_QUICK_REF.md) are complete.
    Terminology: "internal forward zones" not "BIND Views".
    Hairpin preflight: run nslookup + curl before adding NAS DNS.
    SPOF: always set DNS2 fallback (router or 1.1.1.1).
    acme-sh: unaffected by split-horizon (uses Cloudflare DNS-01 API only).
  - restart policy: unless-stopped is the confirmed baseline since 2026-05-01.
    No conflict with on-failure:5 — unless-stopped replaced it repo-wide.
  - duckduckgo healthcheck: already present from OCI audit. Not a gap.
  - docker.sock comment template: "# docker.sock :ro — <reason>" for :ro mounts;
    "# SECURITY: docker.sock :rw — <reason>" for :rw mounts.
  - README volume tables: use ${STACK_ROOT}/<stack>/... not hardcoded paths.
    Reference stacks/zabbix/README.md as the gold standard template.

======================================================================
PHASE 9 — CONTINUOUS LEARNING
======================================================================

/continuous-learning

Extract to ~/.cursor/skills/learned/:

  haproxy-host-map-routing.md:
    Title: HAProxy host.map Routing Pattern
    The https-in frontend uses a map file for backend selection.
    Without an entry in host.map, all requests fall to the default backend.
    Format: lowercase-host<TAB>backend-name
    File path: stacks/_haproxy/maps/host.map
    Validate with: haproxy -c -f stacks/_haproxy/haproxy.cfg
    After editing: reload haproxy (synopkg restart / synosystemctl)

  synology-dns-split-horizon-status.md (update if exists):
    Title: Synology Split-horizon DNS — Repo Status 2026-05-08
    Status: COMPLETE — all four corrections applied to SYNOLOGY_DNS_VIEWS.md
    setup-dns-views.sh: hardened (set -euo pipefail, DSM detection, loud failure)
    verify-dns-views.sh: hairpin comparison mode added
    Action needed before enabling: run hairpin preflight; only implement if
    hairpin fails (many ASUS routers handle it transparently).

  docker-sock-comment-template.md:
    Title: docker.sock Mount Comment Template
    Read-only: # docker.sock :ro — <service> reads <what> only.
    Read-write: # SECURITY: docker.sock :rw — <reason for full API access>.
    Never leave docker.sock mounts without a comment.
    Never use inline comments inside YAML flow sequences.

======================================================================
FINAL PRINT
======================================================================

HAPROXY-DNS-MACRO-GAPS: COMPLETE
