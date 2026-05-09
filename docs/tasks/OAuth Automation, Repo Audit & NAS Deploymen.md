---
title: "HAProxy DSM Config, Traefik/OAuth Automation, Repo Audit & NAS Deployment"
version: "2026-05-10"
author: "Laolu (HIVE Agent Orchestration)"
status: "Stable"
description: |
  End-to-end macro for generating DSM-native HAProxy configuration, Traefik OAuth automation,
  repository audit, and NAS-side validation workflow. Designed for execution via the Queen Agent
  (Cursor/Coder) with NAS Operator follow-through.
tags:
  - haproxy
  - traefik
  - oauth
  - synology
  - hive
  - automation
  - macro
---

# HAProxy DSM Config Generation, Traefik/OAuth Automation, Repo Audit & NAS Deployment

## EXECUTION MODEL

| Phase | Executor | Duration | Rollback |
|-------|----------|----------|----------|
| 0–10  | Queen Agent (Cursor/Coder) | ~30m | `git reset --hard` + revert commits |
| 11    | NAS Operator (Human) | ~10m | Manual rollback of HAProxy config in DSM UI |

---

## PREREQUISITES

**Queen Agent must verify:**
- Repository is clean (`git status` is empty)
- All compose files are syntactically valid (`docker compose config` succeeds)
- `stacks/_haproxy/`, `stacks/traefik-ots/`, `docs/hive/` exist

**NAS Operator must have:**
- SSH access to NAS
- HAProxy package installed (`synopkg status haproxy`)
- Docker/container runtime running
- Valid SSL certs in `stacks/_haproxy/certs/` as `.pem` files

---

## PHASE 0 — PRE-FLIGHT VALIDATION

**Objective:** Verify repository state and read critical docs.

**Actions:**
```bash
# Verify git is clean
git status
[ $? -eq 0 ] || exit 1

# Validate all compose files
find stacks -name "compose.yaml" -exec docker compose -f {} config > /dev/null \; || exit 1

# Read critical files
cat HIVE_OBJECTIVE.md
cat AGENTS.md
cat stacks/_haproxy/README.md (if exists)
cat stacks/traefik-ots/README.md (if exists)
cat docs/hive/NAS_DEPLOYMENT.md
```

**Success Criteria:**
- No git conflicts or uncommitted changes
- All compose files valid YAML + Docker Compose schema
- All referenced files exist

**Failure Action:** Abort macro. Fix issues. Restart Phase 0.

---

## PHASE 1 — SCAN REPOSITORY FOR SERVICE METADATA

**Objective:** Build canonical service-to-backend mapping from all compose files.

**Actions:**

1. Scan `stacks/*/compose.yaml` for:
   - Service names
   - Published ports (extract all `ports:` entries)
   - Service labels (esp. Traefik: `traefik.http.routers.*`, `traefik.http.services.*`)
   - OAuth requirements (custom label: `auth.oauth.enabled: true`)
   - Network assignments

2. Extract subdomain routing from Traefik config:
   ```bash
   grep -r "traefik.http.routers" stacks/ | grep "rule=" | sed 's/.*Host(`\([^`]*\)`).*/\1/'
   ```

3. Build memory map (CSV format):
   ```
   subdomain,service-name,backend-ip,backend-port,oauth-required
   dockge.ots.olutechsys.com,dockge,10.0.1.15,5571,false
   traefik.ots.olutechsys.com,traefik,10.0.1.15,8880,false
   remotely.ots.olutechsys.com,remotely,10.0.1.15,5371,false
   grafana.ots.olutechsys.com,grafana,10.0.1.15,3000,true
   ```

4. Store in: `stacks/_haproxy/.metadata/service-map.csv`

**Success Criteria:**
- CSV file created with ≥3 entries
- All backend IPs are valid (10.x.x.x or 192.168.x.x range)
- All ports are integers 1–65535

**Failure Action:** Manual review required. Abort macro.

---

## PHASE 2 — GENERATE HAPROXY HOST.MAP

**Objective:** Create HAProxy host-to-backend mapping file.

**Actions:**

1. Read `stacks/_haproxy/.metadata/service-map.csv`
2. Generate `stacks/_haproxy/maps/host.map` (HAProxy map format):
   ```
   dockge.ots.olutechsys.com      dockge-be
   traefik.ots.olutechsys.com     traefik-be
   remotely.ots.olutechsys.com    remotely-be
   grafana.ots.olutechsys.com     grafana-be
   ```

3. Validate map file:
   ```bash
   grep -E "^[a-zA-Z0-9\.\-]+ [a-zA-Z0-9\-]+$" stacks/_haproxy/maps/host.map
   ```

**Success Criteria:**
- File created with correct format
- No duplicate hostnames

**Failure Action:** Regenerate. Verify service-map.csv.

---

## PHASE 3 — GENERATE HAPROXY CFG

**Objective:** Create production-ready `haproxy.cfg` with SSL/TLS, health checks, and logging.

**Actions:**

1. Create `stacks/_haproxy/haproxy.cfg`:

```haproxy
global
  log stdout local0
  log stdout local1 notice
  chroot /var/lib/haproxy
  stats socket /run/haproxy/admin.sock mode 660 level admin
  stats timeout 30s
  user haproxy
  group haproxy
  daemon
  ca-base /etc/ssl/certs
  crt-base /etc/ssl/private

defaults
  log     global
  mode    http
  option  httplog
  option  dontlognull
  option  forwardfor if-none
  option  http-server-close
  timeout connect 5000ms
  timeout client  30000ms
  timeout server  30000ms

# Read service map and backends from Phase 2
map $host $backend {
  default backend-not-found
  include /volume1/docker/dockge/stacks/_haproxy/maps/host.map
}

frontend http-in
  bind :80
  # Redirect HTTP to HTTPS
  redirect scheme https code 301 if !{ ssl_fc }

frontend https-in
  bind :443 ssl crt /volume1/docker/dockge/stacks/_haproxy/certs/cert.pem
  http-request set-header X-Forwarded-Proto https
  http-request set-header X-Forwarded-For %[src]
  
  # Use dynamic backend routing
  use_backend %[var(req.backend)]

backend backend-not-found
  http-request deny status 503

# Backends (generated from service-map.csv)
backend dockge-be
  mode http
  option httpchk GET / HTTP/1.1
  balance roundrobin
  server dockge 10.0.1.15:5571 check inter 10s fall 3

backend traefik-be
  mode http
  option httpchk GET /ping HTTP/1.1
  balance roundrobin
  server traefik 10.0.1.15:8880 check inter 10s fall 3

backend traefik-secure-be
  mode http
  option httpchk GET /ping HTTP/1.1
  balance roundrobin
  server traefik-secure 10.0.1.15:6443 check inter 10s fall 3

backend remotely-be
  mode http
  option httpchk GET / HTTP/1.1
  balance roundrobin
  server remotely 10.0.1.15:5371 check inter 10s fall 3

backend grafana-be
  mode http
  option httpchk GET /api/health HTTP/1.1
  balance roundrobin
  server grafana 10.0.1.15:3000 check inter 10s fall 3

# Monitoring/stats (optional, restrict access)
listen stats
  bind :8080
  stats enable
  stats uri /admin?stats
  stats refresh 30s
  stats show-legends
  # Restrict to internal network (adjust as needed)
  # stats admin if LOCALHOST
```

2. Validate syntax:
   ```bash
   haproxy -c -f stacks/_haproxy/haproxy.cfg
   ```

**Success Criteria:**
- Config validates without errors
- All backends from service-map.csv are included
- SSL cert path is correct

**Failure Action:** Check certificate path. Verify backends exist. Regenerate from Phase 1.

---

## PHASE 4 — CERTIFICATE HYGIENE

**Objective:** Ensure `stacks/_haproxy/certs/` contains only valid PEM bundles.

**Actions:**

1. List all files in certs directory:
   ```bash
   find stacks/_haproxy/certs/ -type f
   ```

2. Identify non-PEM files (`.txt`, `.md`, `.key` without matching `.pem`):
   ```bash
   find stacks/_haproxy/certs/ -type f ! -name "*.pem" ! -name "cert.pem" -print
   ```

3. Move to documentation:
   ```bash
   mkdir -p stacks/_haproxy/docs
   mv stacks/_haproxy/certs/*.{txt,md,key} stacks/_haproxy/docs/ 2>/dev/null || true
   ```

4. Verify PEM files are readable:
   ```bash
   for file in stacks/_haproxy/certs/*.pem; do
     openssl x509 -in "$file" -noout -dates || echo "Invalid PEM: $file"
   done
   ```

5. Ensure `cert.pem` exists (combined fullchain + privkey):
   ```bash
   [ -f stacks/_haproxy/certs/cert.pem ] || echo "WARNING: cert.pem not found. NAS Operator must create it."
   ```

**Success Criteria:**
- Only `.pem` files in certs directory
- All PEM files are valid X.509
- No orphaned `.key` or `.txt` files

**Failure Action:** Manual cleanup required. Document missing cert.pem for Phase 11.

---

## PHASE 5 — CREATE NAS OPERATOR RUNBOOK

**Objective:** Generate comprehensive deployment instructions for NAS Operator.

**Actions:**

1. Create/update `stacks/_haproxy/README_NAS_DEPLOYMENT.md`:

```markdown
# HAProxy NAS Deployment Runbook

## Prerequisites

- SSH access to NAS
- HAProxy package installed: `synopkg status haproxy`
- Docker/container runtime active
- Valid SSL certificate bundle: `stacks/_haproxy/certs/cert.pem`

## Steps

### 1. Pull repository changes
\`\`\`bash
cd /volume1/docker/dockge
git pull --no-rebase
git log -1 --oneline
\`\`\`

### 2. Create combined PEM certificate (if needed)
\`\`\`bash
cd stacks/_haproxy/certs/
cat fullchain.pem privkey.pem > cert.pem
chmod 600 cert.pem
\`\`\`

### 3. Copy HAProxy config to DSM location
\`\`\`bash
sudo cp stacks/_haproxy/haproxy.cfg /volume1/@appdata/haproxy/haproxy.cfg
sudo cp stacks/_haproxy/maps/host.map /volume1/@appdata/haproxy/maps/host.map
sudo cp stacks/_haproxy/certs/cert.pem /volume1/@appdata/haproxy/certs/cert.pem
sudo chown haproxy:haproxy /volume1/@appdata/haproxy -R
sudo chmod 755 /volume1/@appdata/haproxy
\`\`\`

### 4. Validate HAProxy configuration
\`\`\`bash
sudo /volume1/@appstore/haproxy/sbin/haproxy -c -f /volume1/@appdata/haproxy/haproxy.cfg
\`\`\`
Expected output: `[OK]`

### 5. Restart HAProxy service
\`\`\`bash
# Method A (preferred):
sudo synopkg restart haproxy

# Method B (fallback):
sudo synosystemctl restart pkgctl-haproxy

# Check status:
sudo synopkg status haproxy
\`\`\`

### 6. Run validation script
\`\`\`bash
bash stacks/_haproxy/nas_audit.sh
\`\`\`

### 7. Test connectivity
\`\`\`bash
curl -k -H "Host: dockge.ots.olutechsys.com" https://localhost
curl -k -H "Host: traefik.ots.olutechsys.com" https://localhost
\`\`\`

## Rollback (if needed)

\`\`\`bash
# Revert to previous config
sudo cp /volume1/@appdata/haproxy/haproxy.cfg.bak /volume1/@appdata/haproxy/haproxy.cfg
sudo synopkg restart haproxy
\`\`\`

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Permission denied" on restart | Run with `sudo` |
| "cert.pem not found" | Create in Phase 4 (see step 2 above) |
| "Port 443 already in use" | Check `netstat -tulpn \| grep 443` |
| "HAProxy won't start" | Review `/var/log/haproxy/error.log` |
```

2. Update `docs/hive/NAS_DEPLOYMENT.md` with link to this runbook.

**Success Criteria:**
- Runbook file created with 7+ procedural steps
- All commands are verified to work on DSM
- Rollback instructions included

**Failure Action:** Document issues for manual review.

---

## PHASE 6 — VALIDATION & COMMIT

**Objective:** Validate all generated files and commit to repository.

**Actions:**

1. Validate generated files:
   ```bash
   # Host map syntax
   grep -E "^[a-zA-Z0-9\.\-]+ [a-zA-Z0-9\-]+$" stacks/_haproxy/maps/host.map

   # HAProxy config
   haproxy -c -f stacks/_haproxy/haproxy.cfg

   # Service map CSV
   head -1 stacks/_haproxy/.metadata/service-map.csv | grep -q "subdomain"

   # Documentation exists
   [ -f stacks/_haproxy/README_NAS_DEPLOYMENT.md ]
   ```

2. Git diff review:
   ```bash
   git diff stacks/_haproxy/
   ```

3. Commit:
   ```bash
   git add stacks/_haproxy/
   git commit -m "feat(haproxy): generate DSM-native haproxy.cfg, host.map, and service metadata

   - Generated host-to-backend mapping from service-map.csv
   - Created production HAProxy config with SSL/TLS and health checks
   - Added NAS Operator deployment runbook
   - Implemented certificate hygiene checks" -m "" -m "Assisted-By: docker-agent"
   ```

**Success Criteria:**
- All validations pass
- Commit created successfully
- Git log shows new commit

**Failure Action:** Fix validation errors. Redo commit.

---

## PHASE 7 — FULL REPOSITORY AUDIT & AUTO-FIX

**Objective:** Scan entire repository for issues and auto-correct where possible.

**Audit Checklist:**

| Category | Check | Auto-Fix |
|----------|-------|----------|
| **Docker Compose** | Valid YAML syntax | Run `docker compose config` |
| | Missing `.env` files | List missing; document |
| | Invalid networks (IPAM conflicts) | Regenerate network IDs |
| | Broken service links | Add missing services or fix references |
| **Documentation** | Missing `README.md` in key dirs | Generate template |
| | Broken internal links | Grep `[](` and validate |
| | Outdated service configs | Cross-check against Phase 1 metadata |
| **Security** | Exposed secrets in compose | Scan for hardcoded credentials |
| | Invalid label syntax | Validate Traefik/HAProxy labels |
| **CI/CD** | Bash shell escaping issues | Run shellcheck on all `.sh` files |
| | Dollar-sign interpolation ($VAR) | Escape for CI pipeline if needed |
| **File System** | Broken symlinks | Identify and log |
| | Missing `.dockerignore` | Generate default |

**Actions:**

```bash
#!/bin/bash
set -e

AUDIT_REPORT="docs/hive/REPO_AUDIT_REPORT.md"

# Start report
cat > "$AUDIT_REPORT" << 'EOF'
# Repository Audit Report

**Generated:** $(date)
**Auditor:** Queen Agent
**Status:** IN PROGRESS

## Summary

| Category | Issues | Fixed |
|----------|--------|-------|
EOF

# 1. Docker Compose validation
echo "Scanning Docker Compose files..."
COMPOSE_ERRORS=0
for f in $(find stacks -name "compose.yaml"); do
  if ! docker compose -f "$f" config > /dev/null 2>&1; then
    echo "❌ $f: INVALID" >> "$AUDIT_REPORT"
    ((COMPOSE_ERRORS++))
  fi
done
echo "Compose | $COMPOSE_ERRORS | 0" >> "$AUDIT_REPORT"

# 2. Missing .env files
echo "Scanning for missing .env files..."
MISSING_ENV=0
for dir in stacks/*/; do
  if grep -q "env_file:" "$dir/compose.yaml" 2>/dev/null; then
    if [ ! -f "$dir/.env" ]; then
      echo "⚠️  $dir: Missing .env" >> "$AUDIT_REPORT"
      ((MISSING_ENV++))
    fi
  fi
done
echo "Environment | $MISSING_ENV | 0" >> "$AUDIT_REPORT"

# 3. Shellcheck all scripts
echo "Running shellcheck..."
SHELL_ERRORS=0
for f in $(find . -name "*.sh"); do
  if ! shellcheck "$f" 2>/dev/null; then
    ((SHELL_ERRORS++))
  fi
done
echo "Shell | $SHELL_ERRORS | 0" >> "$AUDIT_REPORT"

# 4. Document broken symlinks
echo "Checking symlinks..."
BROKEN_LINKS=0
for link in $(find . -type l); do
  if [ ! -e "$link" ]; then
    echo "🔗 Broken link: $link" >> "$AUDIT_REPORT"
    ((BROKEN_LINKS++))
  fi
done
echo "Symlinks | $BROKEN_LINKS | 0" >> "$AUDIT_REPORT"

# Finalize report
cat >> "$AUDIT_REPORT" << EOF

## Actions

- Fix $COMPOSE_ERRORS Compose syntax errors
- Create $MISSING_ENV missing .env files
- Fix $SHELL_ERRORS shell script issues
- Remove $BROKEN_LINKS broken symlinks

## Status

**AUDIT COMPLETE**
EOF

echo "✅ Report: $AUDIT_REPORT"
```

4. Commit audit:
   ```bash
   git add docs/hive/REPO_AUDIT_REPORT.md
   git commit -m "chore(repo): audit and document repository state

   - Scanned all compose files for validity
   - Identified missing .env files
   - Ran shellcheck on all scripts
   - Documented broken symlinks" -m "" -m "Assisted-By: docker-agent"
   ```

**Success Criteria:**
- Audit report created
- ≥80% of fixable issues corrected
- Commit created

**Failure Action:** Document issues. NAS Operator reviews before Phase 11.

---

## PHASE 8 — STATUS SUMMARY

**Objective:** Print human-readable summary of all phases.

**Output:**

```
╔════════════════════════════════════════════════════════════════╗
║   HAProxy + Traefik + OAuth + Repo Audit + NAS Audit Complete   ║
╚════════════════════════════════════════════════════════════════╝

PHASE 0: PRE-FLIGHT ✅
  ├─ Repository clean
  ├─ All compose files valid
  └─ Documentation verified

PHASE 1: SERVICE SCAN ✅
  ├─ Services found: 5
  ├─ Subdomains mapped: 5
  └─ CSV: stacks/_haproxy/.metadata/service-map.csv

PHASE 2: HOST.MAP ✅
  ├─ Entries: 5
  └─ File: stacks/_haproxy/maps/host.map

PHASE 3: HAPROXY.CFG ✅
  ├─ Backends: 5
  ├─ SSL: Enabled (cert.pem)
  ├─ Validation: PASSED
  └─ File: stacks/_haproxy/haproxy.cfg

PHASE 4: CERTIFICATE HYGIENE ✅
  ├─ PEM files: 2
  ├─ Non-PEM removed: 3
  └─ Status: CLEAN

PHASE 5: NAS RUNBOOK ✅
  ├─ Steps: 7
  └─ File: stacks/_haproxy/README_NAS_DEPLOYMENT.md

PHASE 6: GIT COMMIT ✅
  ├─ Files staged: 4
  ├─ Commit: 1a2b3c4 feat(haproxy): generate DSM-native config
  └─ Status: COMMITTED

PHASE 7: REPO AUDIT ✅
  ├─ Issues found: 3
  ├─ Issues fixed: 2
  ├─ Report: docs/hive/REPO_AUDIT_REPORT.md
  └─ Status: DOCUMENTED

═══════════════════════════════════════════════════════════════════

NEXT: Phase 9 (OAuth) or Phase 11 (NAS Operator)

NAS Operator Actions:
  1. Review docs/hive/REPO_AUDIT_REPORT.md for any blockers
  2. Follow stacks/_haproxy/README_NAS_DEPLOYMENT.md steps 1–7
  3. Verify: curl -k https://dockge.ots.olutechsys.com
  4. Report results in repo issue
```

**Success Criteria:**
- All 7 phase statuses shown
- No BLOCKED phases
- NAS Operator action items listed

---

## PHASE 9 — TRAEFIK + OAUTH AUTOMATION (OPTIONAL)

**Objective:** Set up OAuth2-Proxy middleware for Traefik-protected services.

**Prerequisites:**
- Traefik OTS is running
- OAuth2-Proxy image available

**Actions:**

1. **Create OAuth2-Proxy stack** `stacks/oauth2-proxy/compose.yaml`:

```yaml
version: '3.8'

services:
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.7.1
    container_name: oauth2-proxy
    restart: unless-stopped
    networks:
      - traefik-network
    ports:
      - "4180:4180"
    environment:
      OAUTH2_PROXY_PROVIDER: "oidc"
      OAUTH2_PROXY_OIDC_ISSUER_URL: "${OIDC_ISSUER_URL}"
      OAUTH2_PROXY_CLIENT_ID: "${OAUTH_CLIENT_ID}"
      OAUTH2_PROXY_CLIENT_SECRET: "${OAUTH_CLIENT_SECRET}"
      OAUTH2_PROXY_REDIRECT_URL: "${OAUTH_REDIRECT_URL:-https://auth.ots.olutechsys.com/oauth2/callback}"
      OAUTH2_PROXY_COOKIE_SECRET: "${OAUTH_COOKIE_SECRET}"
      OAUTH2_PROXY_COOKIE_SECURE: "true"
      OAUTH2_PROXY_COOKIE_HTTPONLY: "true"
      OAUTH2_PROXY_COOKIE_SAMESITE: "Lax"
      OAUTH2_PROXY_SKIP_PROVIDER_BUTTON: "true"
      OAUTH2_PROXY_EMAIL_DOMAINS: "${OAUTH_EMAIL_DOMAINS:-*}"
      OAUTH2_PROXY_WHITELIST_DOMAINS: "${OAUTH_WHITELIST_DOMAINS:-.ots.olutechsys.com}"
    labels:
      traefik.enable: "true"
      traefik.http.routers.oauth2-proxy.rule: "Host(`auth.ots.olutechsys.com`)"
      traefik.http.routers.oauth2-proxy.entrypoints: "websecure"
      traefik.http.routers.oauth2-proxy.tls: "true"
      traefik.http.services.oauth2-proxy.loadbalancer.server.port: "4180"

networks:
  traefik-network:
    external: true
```

2. **Create `.env` file** `stacks/oauth2-proxy/.env`:
   ```env
   OIDC_ISSUER_URL=https://auth.example.com
   OAUTH_CLIENT_ID=xxxxx
   OAUTH_CLIENT_SECRET=xxxxx
   OAUTH_REDIRECT_URL=https://auth.ots.olutechsys.com/oauth2/callback
   OAUTH_COOKIE_SECRET=xxxxx-min-32-chars-xxxxx
   OAUTH_EMAIL_DOMAINS=@example.com
   OAUTH_WHITELIST_DOMAINS=.ots.olutechsys.com
   ```

3. **Update Traefik dynamic config** `stacks/traefik-ots/dynamic/oauth.yml`:

```yaml
http:
  middlewares:
    oauth-forwardauth:
      forwardAuth:
        address: "http://oauth2-proxy:4180"
        trustForwardHeader: true
        authResponseHeaders:
          - X-Auth-Request-User
          - X-Auth-Request-Email

  # Apply OAuth to protected services
  routers:
    grafana-oauth:
      rule: "Host(`grafana.ots.olutechsys.com`)"
      middlewares:
        - oauth-forwardauth@file
      service: grafana
      entryPoints: websecure
      tls: {}

services:
  grafana:
    loadBalancer:
      servers:
        - url: "http://grafana:3000"
```

4. **Validate & test:**
   ```bash
   docker compose -f stacks/oauth2-proxy/compose.yaml config
   docker compose -f stacks/traefik-ots/docker-compose.yaml config
   ```

5. **Commit:**
   ```bash
   git add stacks/oauth2-proxy/ stacks/traefik-ots/dynamic/oauth.yml
   git commit -m "feat(oauth): add OAuth2-Proxy with Traefik middleware chain

   - OAuth2-Proxy stack with OIDC support
   - Traefik forwardAuth middleware configuration
   - Protected services: grafana" -m "" -m "Assisted-By: docker-agent"
   ```

**Success Criteria:**
- Compose files validate
- OAuth2-Proxy container starts
- Traefik recognizes middleware
- Auth.example.com credentials valid

**Failure Action:** Manual OAuth provider configuration. Document for NAS Operator.

---

## PHASE 10 — GENERATE NAS-SIDE AUDIT SCRIPT

**Objective:** Create comprehensive validation script for NAS Operator.

**Actions:**

1. **Create** `stacks/_haproxy/nas_audit.sh`:

```bash
#!/bin/bash

set +e  # Continue on errors; we want to report all issues

REPORT="/tmp/nas_audit_$(date +%s).txt"
PASSED=0
FAILED=0

log_pass() {
  echo "✅ $1" | tee -a "$REPORT"
  ((PASSED++))
}

log_fail() {
  echo "❌ $1" | tee -a "$REPORT"
  ((FAILED++))
}

echo "╔════════════════════════════════════════════╗" | tee "$REPORT"
echo "║   NAS HAProxy + Traefik + Cert Audit   ║" | tee -a "$REPORT"
echo "║   $(date)   ║" | tee -a "$REPORT"
echo "╚════════════════════════════════════════════╝" | tee -a "$REPORT"

echo "" | tee -a "$REPORT"
echo "[1/10] HAProxy Package Status" | tee -a "$REPORT"
if synopkg status haproxy > /dev/null 2>&1; then
  log_pass "HAProxy package is running"
else
  log_fail "HAProxy package is NOT running"
fi

echo "" | tee -a "$REPORT"
echo "[2/10] HAProxy Configuration Syntax" | tee -a "$REPORT"
if sudo /volume1/@appstore/haproxy/sbin/haproxy -c -f /volume1/@appdata/haproxy/haproxy.cfg > /dev/null 2>&1; then
  log_pass "HAProxy config is valid"
else
  log_fail "HAProxy config has syntax errors"
fi

echo "" | tee -a "$REPORT"
echo "[3/10] Traefik OTS Container" | tee -a "$REPORT"
if docker ps | grep -q traefik; then
  log_pass "Traefik OTS container is running"
else
  log_fail "Traefik OTS container is NOT running"
fi

echo "" | tee -a "$REPORT"
echo "[4/10] Certificate Files" | tee -a "$REPORT"
CERTS_DIR="/volume1/@appdata/haproxy/certs"
CERT_COUNT=$(find "$CERTS_DIR" -name "*.pem" 2>/dev/null | wc -l)
if [ "$CERT_COUNT" -gt 0 ]; then
  log_pass "Found $CERT_COUNT certificate files"
  find "$CERTS_DIR" -name "*.pem" -exec openssl x509 -in {} -noout -dates 2>/dev/null \; | tee -a "$REPORT"
else
  log_fail "No certificate files found in $CERTS_DIR"
fi

echo "" | tee -a "$REPORT"
echo "[5/10] Port Bindings" | tee -a "$REPORT"
for PORT in 80 443 8880 6443; do
  if netstat -tulpn 2>/dev/null | grep -q ":$PORT "; then
    log_pass "Port $PORT is bound"
  else
    log_fail "Port $PORT is NOT bound"
  fi
done

echo "" | tee -a "$REPORT"
echo "[6/10] Firewall Rules" | tee -a "$REPORT"
if iptables -L -n 2>/dev/null | grep -q "Chain"; then
  log_pass "Firewall is active"
  iptables -L -n -v 2>/dev/null | head -20 | tee -a "$REPORT"
else
  log_fail "Firewall check failed or not available"
fi

echo "" | tee -a "$REPORT"
echo "[7/10] Config Drift Check" | tee -a "$REPORT"
if diff -q /volume1/@appdata/haproxy/haproxy.cfg /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg > /dev/null 2>&1; then
  log_pass "No config drift detected"
else
  log_fail "Config drift detected (NAS vs. repo)"
  diff /volume1/@appdata/haproxy/haproxy.cfg /volume1/docker/dockge/stacks/_haproxy/haproxy.cfg | tee -a "$REPORT"
fi

echo "" | tee -a "$REPORT"
echo "[8/10] DNS Resolution" | tee -a "$REPORT"
for DOMAIN in dockge.ots.olutechsys.com traefik.ots.olutechsys.com; do
  if nslookup "$DOMAIN" > /dev/null 2>&1; then
    log_pass "$DOMAIN resolves"
  else
    log_fail "$DOMAIN does NOT resolve"
  fi
done

echo "" | tee -a "$REPORT"
echo "[9/10] HTTPS Connectivity" | tee -a "$REPORT"
for DOMAIN in dockge.ots.olutechsys.com traefik.ots.olutechsys.com; do
  if timeout 5 curl -sk -H "Host: $DOMAIN" https://127.0.0.1 > /dev/null 2>&1; then
    log_pass "$DOMAIN responds over HTTPS"
  else
    log_fail "$DOMAIN does NOT respond over HTTPS"
  fi
done

echo "" | tee -a "$REPORT"
echo "[10/10] Disk Space (HAProxy)" | tee -a "$REPORT"
DISK_USAGE=$(df /volume1/@appdata/haproxy 2>/dev/null | awk 'NR==2 {print $5}')
if [ "$DISK_USAGE" != "" ] && [ "$DISK_USAGE" -lt 80 ]; then
  log_pass "Disk usage: $DISK_USAGE%"
else
  log_fail "Disk usage: $DISK_USAGE% (warning: approaching limit)"
fi

echo "" | tee -a "$REPORT"
echo "╔════════════════════════════════════════════╗" | tee -a "$REPORT"
echo "║   AUDIT COMPLETE                           ║" | tee -a "$REPORT"
echo "║   Passed: $PASSED | Failed: $FAILED             ║" | tee -a "$REPORT"
echo "╚════════════════════════════════════════════╝" | tee -a "$REPORT"

cat "$REPORT"

exit $FAILED  # Exit with number of failures
```

2. **Make executable:**
   ```bash
   chmod +x stacks/_haproxy/nas_audit.sh
   ```

3. **Commit:**
   ```bash
   git add stacks/_haproxy/nas_audit.sh
   git commit -m "feat(nas-audit): add comprehensive DSM validation script

   - HAProxy package + config validation
   - Traefik container health check
   - SSL certificate inventory
   - Port binding verification
   - DNS/HTTPS connectivity tests
   - Config drift detection
   - Disk space monitoring" -m "" -m "Assisted-By: docker-agent"
   ```

**Success Criteria:**
- Script is executable
- All checks run without crashing
- Output is readable and actionable

---

## PHASE 11 — NAS DEPLOYMENT (NAS OPERATOR)

**Objective:** Deploy HAProxy, OAuth, and Traefik to DSM.

**Prerequisites:**
- Repository is clean (all Phases 0–10 complete)
- SSL certificates ready
- SSH access to NAS
- Backup of existing HAProxy config (optional but recommended)

**Execution:**

1. **Pull changes:**
   ```bash
   cd /volume1/docker/dockge
   git pull --no-rebase
   git log -1 --oneline
   ```

2. **Verify Phase 1 metadata:**
   ```bash
   cat stacks/_haproxy/.metadata/service-map.csv
   ```

3. **Build certificate bundle:**
   ```bash
   cd stacks/_haproxy/certs/
   cat fullchain.pem privkey.pem > cert.pem
   chmod 600 cert.pem
   ls -lh cert.pem
   ```

4. **Copy config to DSM HAProxy locations:**
   ```bash
   sudo cp stacks/_haproxy/haproxy.cfg /volume1/@appdata/haproxy/haproxy.cfg
   sudo cp stacks/_haproxy/maps/host.map /volume1/@appdata/haproxy/maps/host.map
   sudo cp stacks/_haproxy/certs/cert.pem /volume1/@appdata/haproxy/certs/cert.pem
   sudo chown haproxy:haproxy /volume1/@appdata/haproxy -R
   ```

5. **Validate:**
   ```bash
   sudo /volume1/@appstore/haproxy/sbin/haproxy -c -f /volume1/@appdata/haproxy/haproxy.cfg
   ```
   Expected: `[OK]`

6. **Restart HAProxy:**
   ```bash
   sudo synopkg restart haproxy
   sudo synopkg status haproxy
   ```

7. **Run audit script:**
   ```bash
   bash stacks/_haproxy/nas_audit.sh
   ```

8. **Test connectivity (from workstation):**
   ```bash
   curl -k https://dockge.ots.olutechsys.com
   curl -k https://traefik.ots.olutechsys.com
   ```

9. **Document results:**
   ```bash
   # Create deployment record
   cat > docs/hive/NAS_DEPLOYMENT_LOG.md << EOF
   # NAS Deployment Log

   **Date:** $(date)
   **NAS Operator:** [Your Name]
   **HAProxy Status:** [Running/Failed]
   **Audit Result:** [Pass/Fail]
   **Issues:** [None/List]
   EOF

   git add docs/hive/NAS_DEPLOYMENT_LOG.md
   git commit -m "log(nas): deployment completed"
   ```

**Rollback (if needed):**
```bash
# Revert config
sudo cp /volume1/@appdata/haproxy/haproxy.cfg.bak /volume1/@appdata/haproxy/haproxy.cfg
sudo synopkg restart haproxy

# Revert repo
git reset --hard HEAD~5  # Adjust commit count as needed
```

**Success Criteria:**
- HAProxy package running
- Config validates
- All audit checks pass
- External HTTPS connectivity works

---

# FINAL CHECKLIST

| Phase | Task | Status | Owner |
|-------|------|--------|-------|
| 0 | Pre-flight validation | ◻️ | Queen |
| 1 | Service scan + metadata | ◻️ | Queen |
| 2 | Generate host.map | ◻️ | Queen |
| 3 | Generate haproxy.cfg | ◻️ | Queen |
| 4 | Certificate hygiene | ◻️ | Queen |
| 5 | NAS runbook | ◻️ | Queen |
| 6 | Git commit | ◻️ | Queen |
| 7 | Repo audit + fix | ◻️ | Queen |
| 8 | Status summary | ◻️ | Queen |
| 9 | OAuth automation (optional) | ◻️ | Queen |
| 10 | NAS audit script | ◻️ | Queen |
| 11 | NAS deployment | ◻️ | Operator |

---

**END OF MACRO**
