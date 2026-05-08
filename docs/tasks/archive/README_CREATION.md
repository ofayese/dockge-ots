> Superseded by `docs/tasks/MASTER_AUDIT_AND_DEPLOY.md` on 2026-05-08. Kept for history.

# Task: Create README.md at repo root

/coder

Read the following files before starting — they are the source of truth:
  - AGENTS.md
  - HIVE_OBJECTIVE.md
  - CLAUDE.md
  - docs/hive/NAS_DEPLOYMENT.md
  - scripts/README.txt
  - scripts/dockge-start.sh
  - stacks/acme-sh/SETUP.md
  - stacks/_haproxy/README.txt
  - stacks/portainer/README.md
  - stacks/watchtower/README.md


Do NOT modify any of those files. Create only README.md at the repo root.

======================================================================
TASK — Create README.md at repo root
======================================================================

CONTEXT:
There is no operator-facing README at the repo root. After a NAS reset
this has caused days of recovery work because the bring-up sequence,
port references, and troubleshooting steps exist only in scattered
docs/hive/ files and AGENTS.md (agent-facing, not operator-facing).

The README must be the single document a human reaches for after any
of these events:
  - NAS reset / DSM reinstall
  - New NAS onboarded to this repo
  - First-time contributor setup
  - "Where is X?" reference during an incident

======================================================================
CONTENT REQUIREMENTS
======================================================================

## Section 1 — What this repo is (3-5 sentences)
  - Dockge stack definitions for two Synology NAS devices
    (OTS NAS: 10.0.1.15, MFT NAS: 10.0.1.24)
  - 23 stacks under stacks/ plus _haproxy infrastructure
  - Cert automation via acme-sh -> Traefik/HAProxy
  - Point to HIVE_OBJECTIVE.md for full architecture brief

## Section 2 — Repository layout
  Quick tree showing:
    stacks/           Dockge compose stack folders (23 stacks + _haproxy)
    docs/hive/        Operator docs (NAS_DEPLOYMENT.md, SERVICE_MAP.md, etc.)
    scripts/          NAS bootstrap and utility scripts
    AGENTS.md         Agent/AI operational memory
    HIVE_OBJECTIVE.md Architecture brief and milestones

## Section 3 — Post-reset NAS bring-up (THE most important section)

  Sub-section 3a: Prerequisites
    - Synology Container Manager installed from Package Center
    - SSH enabled (Admin or operator user)
    - GitHub SSH key configured for the git user:
        ssh-keygen -t ed25519 -C "nas-deploy"
        # Add pubkey to GitHub Settings -> SSH keys
    - Test SSH auth: ssh -T git@github.com

  Sub-section 3b: Clone and bootstrap
    git clone git@github.com:ofayese/dockge-ots.git /volume1/docker/dockge
    cd /volume1/docker/dockge
    # If dubious ownership error after clone:
    git config --file .git/config \
      --add safe.directory /volume1/docker/dockge
    sudo bash scripts/init-nas.sh
    # Creates all STACK_ROOT dirs and writes repo-root .env

  Sub-section 3c: Start Dockge
    sudo cp scripts/dockge-start.sh /usr/local/etc/rc.d/dockge.sh
    sudo chmod +x /usr/local/etc/rc.d/dockge.sh
    sudo sh /usr/local/etc/rc.d/dockge.sh
    # Wait ~30s then verify:
    docker inspect Dockge --format '{{json .HostConfig.PortBindings}}'
    # Must show: {"5001/tcp":[{"HostIp":"0.0.0.0","HostPort":"5571"}]}
    curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5571/
    # Must return 200 or 302
    # Browser: http://10.0.1.15:5571

  Sub-section 3d: Issue TLS certificates (REQUIRED before Traefik/HAProxy)
    cd /volume1/docker/dockge/stacks/acme-sh
    cp .env.example .env
    # Edit .env: set CF_Token (Cloudflare Zone.DNS:Edit for olutechsys.com)
    docker compose up -d
    sudo mkdir -p \
      /volume1/certs/acme/wildcard \
      /volume1/certs/acme/otsorundscore-sub \
      /volume1/certs/acme/misfitsds-sub \
      /volume1/certs/acme/otsmbpro16 \
      /volume1/certs/acme/hpdevcore \
      /volume1/certs/acme/ots-sub \
      /volume1/certs/acme/mft-sub
    # Full --issue and --install-cert commands: stacks/acme-sh/SETUP.md
    # Each cert takes ~2 min (DNS-01 propagation)
    # Verify: sudo docker exec AcmeSh acme.sh --list

  Sub-section 3e: Deploy Traefik (after certs exist)
    cd /volume1/docker/dockge/stacks/traefik-ots
    cp .env.example .env   # set STACK_ROOT, ACME_CERT_ROOT, CF_Token
    docker compose up -d
    # Verify: docker exec traefik-ots wget -qO- http://127.0.0.1:8080/ping

  Sub-section 3f: Deploy remaining stacks via Dockge UI
    Open http://10.0.1.15:5571
    Each stack: cp .env.example .env, fill secrets, deploy via UI
    Recommended order: portainer -> acme-sh -> traefik-ots -> others

## Section 4 — Port reference

  | Service        | Host port | Notes                                    |
  |----------------|-----------|------------------------------------------|
  | Dockge UI      | 5571      | Maps to container 5001 (NOT 5571:5571)   |
  | Portainer      | 9443      | HTTPS                                    |
  | DSM admin      | 5001/5000 | Synology system — do NOT use for Dockge  |
  | Traefik dash   | 8080      | Internal only; disabled in production    |
  | HAProxy HTTPS  | 443       | External TLS termination                 |
  | HAProxy HTTP   | 8080      | Redirects to 443                         |
  | Router admin   | 8443      | https://10.0.1.1:8443                    |
  | Router SSH     | 24        | ssh -p 24 admin@10.0.1.1                 |

## Section 5 — Key scripts

  | Script                         | Purpose                                     |
  |--------------------------------|---------------------------------------------|
  | scripts/init-nas.sh            | Bootstrap STACK_ROOT dirs after clone/pull  |
  | scripts/dockge-start.sh        | Start/recreate Dockge host container        |
  | scripts/fix-permissions.sh     | Normalize bind-mount ownership to root:root |
  | scripts/compose-validate.sh    | Validate all compose files (also runs in CI)|
  | scripts/check-dockge-http.sh   | HTTP probe Dockge on 5571                   |
  | scripts/verify-repo-layout.sh  | Guard against wrong hive/stacks paths       |
  | scripts/validate-haproxy-proposal.sh | Syntax-check HAProxy config off-box  |

## Section 6 — Keeping the NAS in sync

  Short version pointing to docs/hive/NAS_DEPLOYMENT.md for full detail:
    - Preferred: SSH -> cd /volume1/docker/dockge -> git pull
    - After adding stacks: sudo bash scripts/init-nas.sh
    - If dubious ownership error:
        git config --file .git/config \
          --add safe.directory /volume1/docker/dockge
    - If Permission denied (publickey): run git as the DSM user
        whose ~/.ssh contains the GitHub deploy key, not as root

## Section 7 — Architecture overview

  Two NAS devices:
    OTS NAS  10.0.1.15  otsorundscore.synology.me  *.ots.olutechsys.com
    MFT NAS  10.0.1.24  misfitsds.synology.me       *.mft.olutechsys.com

  Traffic flow:
    Internet -> DDNS -> HAProxy (443) or Traefik -> stack containers

  Certs (acme-sh, DNS-01 via Cloudflare, RSA 2048):
    Issued to /volume1/certs/acme/<dir>/
    Traefik reads PEMs read-only via bind mount (no Traefik ACME)
    acme-sh daemon auto-renews every 60 days

  See docs/hive/SERVICE_MAP.md for the full service inventory.
  See docs/hive/dns/olutechsys.com.zone for the DNS zone reference.

## Section 8 — Troubleshooting quick reference

  Dockge "connection dropped" on 5571
    Cause: port mapping is 5571:5571 instead of 5571:5001
    Fix:
      docker stop Dockge && docker rm Dockge
      sudo sh /usr/local/etc/rc.d/dockge.sh

  Traefik serving self-signed cert
    Cause: acme-sh certs not issued or ACME_CERT_ROOT path wrong
    Fix: run --issue then --install-cert per stacks/acme-sh/SETUP.md
         then docker compose restart in stacks/traefik-ots/

  HAProxy "no start line" on config check
    Cause: non-PEM file (e.g. README.txt) in stacks/_haproxy/certs/
    Fix: remove all non-.pem files from that directory

  HAProxy "no SSL certificate specified"
    Cause: stacks/_haproxy/certs/ is empty
    Fix:
      cat /volume1/certs/acme/ots-sub/fullchain.pem \
          /volume1/certs/acme/ots-sub/privkey.pem \
          > stacks/_haproxy/certs/ots.olutechsys.com.pem

  git pull "dubious ownership"
    Cause: repo owned by root, git running as laolufayese
    Fix:
      git config --file /volume1/docker/dockge/.git/config \
        --add safe.directory /volume1/docker/dockge

  git pull "Permission denied (publickey)"
    Cause: running git as root which has no GitHub SSH key
    Fix: switch to the DSM user that owns the deploy key

======================================================================
FORMATTING RULES
======================================================================

- Standard GitHub-flavoured Markdown only
- Fenced code blocks for all shell commands
- Tables where specified above
- Concise prose — operators read this under stress
- Link to docs/hive/NAS_DEPLOYMENT.md and stacks/acme-sh/SETUP.md
  for full command listings; do not duplicate everything here
- No emoji, no decorative elements

======================================================================
FINAL STEPS
======================================================================

STEP 1 — Write README.md at repo root.

STEP 2 — Run pre-commit on the new file only:
  Command: pre-commit run --files README.md
  Expected: all hooks pass.

STEP 3 — Verify no unintended changes:
  Command: git status
  Expected: only README.md as new untracked file.

STEP 4 — Commit:
  Command: git add README.md && git commit -m \
    "docs: add operator README with post-reset bring-up guide"

Print:
  README-CREATION: COMPLETE
