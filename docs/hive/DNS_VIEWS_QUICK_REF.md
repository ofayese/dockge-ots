# Split-horizon DNS — quick reference

**Terminology:** split-horizon DNS, **internal forward zones** (DSM Primary → Forward), optional **dnsmasq `address=` overrides** — not BIND “Views.” Full guide: [SYNOLOGY_DNS_VIEWS.md](SYNOLOGY_DNS_VIEWS.md).

---

## 0. Hairpin-first (do before split-DNS)

From a **LAN** machine:

```bash
nslookup otsdrv.ots.olutechsys.com
curl -kI --max-time 15 https://otsdrv.ots.olutechsys.com
```

| Result | Meaning |
|--------|---------|
| `curl` OK, `nslookup` shows **public** IP | Hairpin works → **split-DNS optional** |
| `curl` fails, `nslookup` public IP | Hairpin broken / blocked → **split-DNS required** (or router fix) |
| `nslookup` already shows **LAN** Traefik IP | Internal DNS already in path → **split-DNS not needed** for reachability |

Automated: `bash scripts/verify-dns-views.sh --hairpin` or `bash scripts/verify-dns-views.sh --hairpin mftdrv.mft.olutechsys.com`

---

## DNS SPOF

DHCP **DNS1 = NAS only** with no **DNS2** → NAS outage **breaks all DNS** for clients. Set **DNS2** to router or `1.1.1.1` (internal zones still only on NAS unless replicated).

---

## ACME (acme-sh / Traefik Cloudflare DNS-01)

**Cloudflare DNS-01** uses the **Cloudflare API** only — **not** internal Synology DNS. Wildcards like `*.ots.olutechsys.com` / `*.mft.olutechsys.com` stay on **public** Cloudflare; see `stacks/acme-sh/SETUP.md`. Traefik’s optional built-in resolver (if enabled in compose) also uses **`CF_DNS_API_TOKEN`** — still **no** dependency on split-horizon.

---

## Setup checklist

### Step 1 — Package

DSM → **Package Center** → **DNS Server** → Install.

```bash
sudo synopkg status DNSServer 2>/dev/null || sudo synoservice --status dnsmasq 2>/dev/null
```

### Step 2 — Internal forward zones (DSM UI)

**DNS Server** → **Zone** → **Create** → **Primary zone** → **Forward zone**

- `ots.olutechsys.com` → `*` **A** → `10.0.1.15`
- Optional: `mft.olutechsys.com` → `*` **A** → `10.0.1.24`

**SOA / public DNS:** Cloudflare stays authoritative for public `olutechsys.com`; internal zones are **LAN-only** unless you delegate at the registrar.

### Step 3 — Optional dnsmasq overrides (expert)

See [scripts/setup-dns-views.sh](../../scripts/setup-dns-views.sh) — DSM-version-specific.

### Step 4 — Router DHCP

DNS1 = `10.0.1.15`, **DNS2 = fallback** (router / `1.1.1.1`).

### Step 5 — Verify

```bash
bash scripts/verify-dns-views.sh
```

---

## Files

- [SYNOLOGY_DNS_VIEWS.md](SYNOLOGY_DNS_VIEWS.md)
- [scripts/verify-dns-views.sh](../../scripts/verify-dns-views.sh)
- [scripts/setup-dns-views.sh](../../scripts/setup-dns-views.sh)
