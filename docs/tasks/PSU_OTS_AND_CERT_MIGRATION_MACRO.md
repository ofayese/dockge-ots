# PSU OTS + host-named TLS — operator macro

Paste blocks into Cursor **Agent** (or `/coder`) in order. **Plan source:** `.cursor/plans/psu_ots_+_cert_migration_aa360025.plan.md` (repo-relative path may differ).

**Repo status (May 2026):** Phase **1** deliverables for **`stacks/psu-ots/`** are **landed on `main`** (`compose.yaml`, digest-pinned image, host-published PSU port for HAProxy, `/data`, `/nas-repo` ro, `/certs/acme` ro, public host **`psu.otsorundscore.olutechsys.com`**, `.env.example`, `README.md`, **`STACK_MANIFEST`** entry **`psu-ots:data`** in `scripts/init-nas.sh`). Git-tracked PSU templates live under **`stacks/psu-ots/universal/`** (not under `data/` — root `.gitignore` ignores `stacks/**/data/`). **NAS:** copy `universal/` → `data/Repository/.universal/` after deploy; add **`Scripts/*.ps1`** and **`Apps/NOC-Dashboard.ps1`** only under **`data/Repository/`** on the appliance (optional; version there if you want them durable).

---

## 1) /coder — implementation directive (historical + gap-fill)

**If you are reviving this macro on an older branch**, implement or verify:

- **`stacks/psu-ots/compose.yaml`** — digest-pinned `ironmansoftware/universal`, explicit host publish for HAProxy backend, **`${STACK_ROOT}/psu-ots/data:/data`**, **`${DOCKGE_REPO_ROOT}:/nas-repo:ro`**, **`${ACME_CERT_ROOT}:/certs/acme:ro`**, no Traefik labels/network.
- **`.env.example`**, **`README.md`**, **`universal/{scripts,endpoints,dashboards}/*.ps1`** (templates).
- **`scripts/init-nas.sh`** includes **`psu-ots:data`** in **`STACK_MANIFEST`**.

**TLS migration (already applied in tree):** HAProxy serves host-named cert bundles built from **`otsorundscore/`** and **`misfitsds/`** PEM dirs; update **live NAS** `acme.sh` orders and rebuild staged HAProxy PEM bundles.

**Verification (repo):**

```bash
bash scripts/compose-validate.sh
bash scripts/verify-repo-layout.sh
# Expect no matches (rg exits 1 when empty):
rg '\.ots\.olutechsys\.com|\.mft\.olutechsys\.com' stacks/
```

---

## 2) Continual-learning — session notes to promote

**Canonical in-repo:** **`AGENTS.md`** → **What Works** already carries PSU URL, Dockge API env vars, **`git pull --no-rebase`**, PEM dir names, phased gates, and **`docs/tasks/PSU_OTS_AND_CERT_MIGRATION_MACRO.md`** pointer. **After NAS-only changes**, add or refresh a **dated** bullet there if behavior or paths change.

**Do not** commit PSU DB or runtime churn under **`stacks/psu-ots/data/`** — only operator content under **`data/Repository/`** where you intentionally version it (see **`stacks/psu-ots/.gitignore`**).

---

## 3) Compound-project-memory — phased memory

**Canonical in-repo index:** **`AGENTS.md`** → **What Works** — search for **PSU + host-named cert migration — phased gates**.

**Phase 1** — compose + docs landed → `compose-validate` + `verify-repo-layout`.  
**Phase 2** — PSU scripts/endpoints validated on NAS.  
**Phase 3** — NOC dashboard smoke in browser.  
**Phase 4** — ACME issued for **`otsorundscore/`** + **`misfitsds/`**, HAProxy cert bundles refreshed and validated, `verify-dns-views.sh --hairpin` (interpret per **`docs/hive/DNS_VIEWS_QUICK_REF.md`**).

---

## 4) Cert cutover checklist (operator on NAS)

1. Issue / install PEMs to **`/volume1/certs/acme/otsorundscore/`** and **`…/misfitsds/`** (see `stacks/acme-sh/SETUP.md`).
2. Rebuild and validate **`stacks/_haproxy/certs/*.pem`** bundles; reload HAProxy.
3. Cloudflare: CNAMEs **`*.otsorundscore`** / **`*.misfitsds`** per `docs/hive/dns/olutechsys.com.zone`.
4. DSM split-horizon: forward zones **`otsorundscore.olutechsys.com`** / **`misfitsds.olutechsys.com`** (see **`docs/hive/SYNOLOGY_DNS_VIEWS.md`** and **`docs/hive/DNS_VIEWS_QUICK_REF.md`**).
5. HAProxy: rebuild **`stacks/_haproxy/certs/*.pem`** from new fullchain+privkey paths (`stacks/_haproxy/README.txt`).
