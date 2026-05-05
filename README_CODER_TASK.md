# Coder Task — Create repo root README.md

/coder

Read AGENTS.md, docs/hive/NAS_DEPLOYMENT.md, scripts/init-nas.sh,
scripts/dockge-start.sh, and stacks/acme-sh/SETUP.md before starting.
Do not modify any of those files. Create only README.md at the repo root.

Run pre-commit run --files README.md at the end.
Run git add README.md && git commit -m "docs: add README.md — NAS bring-up runbook"

Print: README-TASK: COMPLETE

======================================================================
TASK — Create README.md at the repo root
======================================================================

CONTEXT:
There is currently no README.md in the repo root. After a NAS reset
(which just happened) the operator had to reconstruct the bring-up
sequence from scattered docs, AGENTS.md, Cursor chat history, and
Claude conversations over multiple days.

The README must be a single, self-contained operator runbook for:
  "I just reset or re-provisioned the NAS. What do I do first?"

It is not a developer guide. It is not a full reference. It is the
minimum ordered steps to get from a blank Synology DSM to a working
Dockge + acme-sh + Traefik + HAProxy stack. Every section must link
to the canonical detailed doc rather than duplicate it.

======================================================================
CONTENT SPEC — README.md
======================================================================

## Title and intro

# Olutech Homelab — Dockge Stack Repo

One-paragraph description: what this repo is (Dockge stack definitions
for the OTS and MFT NAS devices), what it does NOT include (Dockge
itself is started by scripts/dockge-start.sh, not a compose stack),
and the two NAS hostnames:
  OTS NAS: otsorundscore.synology.me (10.0.1.15)
  MFT NAS: misfitsds.synology.me    (10.0.1.24)

---

## Section 1 — After a NAS reset: bring-up order

This is the most important section. It must be a numbered ordered list
covering the exact sequence that must be followed. Steps must be concise
— one or two lines each — with the actual command where it is short
enough, and a link to the canonical doc for anything longer.

Order:
  1. Install Container Manager from DSM Package Center
  2. Clone the repo (exact command)
  3. Run init-nas.sh (exact command, note it writes STACK_ROOT to .env)
  4. Install and start Dockge (exact commands — cp dockge-start.sh,
     chmod, run it, verify with docker ps and curl)
  5. Bring up acme-sh stack (cd stacks/acme-sh, cp .env.example .env,
     set CF_Token, docker compose up -d) — link to
     stacks/acme-sh/SETUP.md for full issue/install-cert commands
  6. Issue and install all certs — note the 7 certs needed, link to
     SETUP.md ## Issue all certs and ## Configure output paths
  7. Deploy traefik-ots (cert must exist first — note the hard dependency)
     Link to docs/hive/NAS_DEPLOYMENT.md ## Traefik deployment
  8. Deploy remaining stacks via Dockge UI
  9. Build HAProxy cert bundle and validate — link to
     stacks/_haproxy/haproxy.cfg and docs/hive/NAS_DEPLOYMENT.md
     ## Dockge UI and HAProxy

---

## Section 2 — Dockge

Short section. Key facts only:
  - NOT a compose stack — started by scripts/dockge-start.sh
  - Install script: sudo cp scripts/dockge-start.sh
    /usr/local/etc/rc.d/dockge.sh && chmod +x ...
  - Image: louislam/dockge:1 (NOT :base)
  - Port: host 5571 → container 5001 (NOT 5571:5571 — script auto-fixes
    wrong mapping on recreate)
  - App state: repo root mounted at /app/data — no separate data/ dir
  - Verify: curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5571/

---

## Section 3 — Certs (acme-sh)

Short section. Key facts:
  - Container name: AcmeSh
  - Certs go to /volume1/certs/acme/<dir>/
  - 7 certs managed: wildcard, otsorundscore-sub, misfitsds-sub,
    otsmbpro16, hpdevcore, ots-sub, mft-sub
  - Issue order: --issue first, wait for DNS (~2 min), then --install-cert
  - Full commands: see stacks/acme-sh/SETUP.md
  - acme-sh auto-renews in daemon mode — no cron needed

---

## Section 4 — Traefik

Short section. Key facts:
  - One stack per NAS: stacks/traefik-ots/ and stacks/traefik-mft/
  - MUST deploy acme-sh and issue certs BEFORE deploying Traefik
    (missing cert = self-signed fallback = browser warning)
  - Verify: docker exec traefik-ots wget -qO- http://127.0.0.1:8080/ping
  - Services join Traefik by adding labels + traefik-ots network
  - Full reference: docs/hive/NAS_DEPLOYMENT.md ## Traefik deployment

---

## Section 5 — HAProxy

Short section. Key facts:
  - Synology HAProxy package (not a Docker container)
  - Config: stacks/_haproxy/haproxy.cfg
  - Cert dir: stacks/_haproxy/certs/ — HAProxy reads every .pem here
    (do NOT put non-PEM files in this directory)
  - Build PEM bundle after certs are issued:
      sudo sh -c 'cat /volume1/certs/acme/ots-sub/fullchain.pem \
        /volume1/certs/acme/ots-sub/privkey.pem \
        > /volume1/docker/dockge/stacks/_haproxy/certs/ots.olutechsys.com.pem'
  - Validate before reload:
      sudo /volume1/@appstore/haproxy/sbin/haproxy -c \
        -f /volume1/@appdata/haproxy/haproxy.cfg
  - Full reference: docs/hive/NAS_DEPLOYMENT.md ## Dockge UI and HAProxy

---

## Section 6 — Namespace and DNS

Two-paragraph summary only. Do not duplicate the zone file.
  - *.ots.olutechsys.com → OTS NAS via traefik-ots
  - *.mft.olutechsys.com → MFT NAS via traefik-mft
  - Both are DNS-only CNAMEs (grey cloud in Cloudflare)
  - Add a service: Traefik labels + network join, no DNS change needed
  - Full reference: docs/hive/SERVICE_MAP.md and
    docs/hive/dns/olutechsys.com.zone

---

## Section 7 — Day-to-day operations

Short bulleted list:
  - Keeping NAS in sync: git pull on NAS, then init-nas.sh --if-changed
    if stacks were added (link to NAS_DEPLOYMENT.md ## Keeping the NAS
    in sync)
  - Adding a new stack: add compose.yaml under stacks/<name>/,
    add entry to STACK_MANIFEST in scripts/init-nas.sh,
    run init-nas.sh to create dirs, deploy in Dockge
  - Cert renewal: automatic via acme-sh daemon; check with
    docker exec AcmeSh acme.sh --list
  - Permissions: sudo bash scripts/fix-permissions.sh

---

## Section 8 — Key files reference

A small table of the most important files:

| File | Purpose |
|---|---|
| scripts/dockge-start.sh | Dockge host container startup (install to rc.d) |
| scripts/init-nas.sh | Post-clone bootstrap — creates dirs, writes STACK_ROOT |
| scripts/fix-permissions.sh | Normalize stack bind-mount ownership |
| stacks/acme-sh/SETUP.md | Full cert issue/install/renew runbook |
| stacks/_haproxy/haproxy.cfg | HAProxy config (TLS, backends, host map) |
| docs/hive/NAS_DEPLOYMENT.md | Full deployment reference |
| docs/hive/SERVICE_MAP.md | Service inventory for both NASes |
| docs/hive/dns/olutechsys.com.zone | DNS zone reference |
| AGENTS.md | Repo memory and conventions for AI agents |

---

## Section 9 — Security notes

Very short. Just the items from the syslog audit that should stay off:
  - NFS/NFSD: keep disabled on the router (USB Application → NFS)
  - rpcbind port 111: blocked via iptables on router WAN interface
  - FTP WAN access: disabled
  - Router admin: HTTPS only (already enforced on port 8443)
  - Router SSL cert: check expiry — the Let's Encrypt cert for
    batcavegtaxe16k.asuscomm.com expired 2025/6/6 and needs renewal

======================================================================
STYLE RULES
======================================================================

- Use prose and short lists. No excessive headers.
- Keep the whole file under 250 lines.
- Every section must have at least one link to a canonical doc.
- Do not duplicate command sequences that already exist in SETUP.md
  or NAS_DEPLOYMENT.md — link to them instead.
- Code blocks only where the command is short enough to be the
  definitive version (not a summary of a longer sequence).
- Tone: operator runbook, not tutorial. Assume the reader has done
  this before and needs the sequence and key facts, not explanations.
