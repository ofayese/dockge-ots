# PSU OTS + host-named TLS — operator macro

Paste blocks into Cursor **Agent** (or `/coder`) in order. **Plan source:** `.cursor/plans/psu_ots_+_cert_migration_aa360025.plan.md` (repo-relative path may differ).

---

## 1) `/coder` — implementation directive

Implement **`stacks/psu-ots/`** (PowerShell Universal): `compose.yaml` (digest-pinned image, `traefik-ots` external network, `/data`, `/nas-repo` ro, `/certs/acme` ro, Traefik labels for `psu.otsorundscore.olutechsys.com`), `.env.example`, `README.md`, `data/Repository/.universal/*.ps1`, `Scripts/*.ps1`, `Apps/NOC-Dashboard.ps1`, `STACK_MANIFEST` entry **`psu-ots:data`**.

**TLS migration (already applied in tree):** Traefik mounts **`otsorundscore/`** and **`misfitsds/`** PEM dirs; update **live NAS** `acme.sh` orders and PEM paths before restarting Traefik.

**Verification:** `bash scripts/compose-validate.sh`, `bash scripts/verify-repo-layout.sh`, `rg '\\.ots\\.olutechsys\\.com|\\.mft\\.olutechsys\\.com' stacks/` → empty.

---

## 2) Continual-learning — session notes to promote

After changes: add dated bullets to **`AGENTS.md`** (PSU URL, Dockge API creds for jobs, `git pull --no-rebase` on webhooks, PEM dir names). **Do not** commit PSU DB files under `stacks/psu-ots/data/` (only `Repository/`).

---

## 3) Compound-project-memory — phased memory

**Canonical in-repo index:** the same phased gates (with explicit commands and cross-links) live under **`AGENTS.md`** → **What Works** — search for **PSU + host-named cert migration — phased gates**.

**Phase 1** — compose + docs landed → `compose-validate` + `verify-repo-layout`.  
**Phase 2** — PSU scripts/endpoints validated on NAS.  
**Phase 3** — NOC dashboard smoke in browser.  
**Phase 4** — ACME issued for **`otsorundscore/`** + **`misfitsds/`**, Traefik green, `verify-dns-views.sh --hairpin`.

---

## 4) Cert cutover checklist (operator on NAS)

1. Issue / install PEMs to **`/volume1/certs/acme/otsorundscore/`** and **`…/misfitsds/`** (see `stacks/acme-sh/SETUP.md`).
2. Recreate **traefik-ots** / **traefik-mft** if binds were stale.
3. Cloudflare: CNAMEs **`*.otsorundscore`** / **`*.misfitsds`** per `docs/hive/dns/olutechsys.com.zone`.
4. DSM split-horizon: forward zones **`otsorundscore.olutechsys.com`** / **`misfitsds.olutechsys.com`** (see `docs/hive/SYNOLOGY_DNS_VIEWS.md`).
5. HAProxy: rebuild **`stacks/_haproxy/certs/*.pem`** from new fullchain+privkey paths (`stacks/_haproxy/README.txt`).
