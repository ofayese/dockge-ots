# DNS Views Quick Reference

## Problem
```
Internal client: nslookup otsdrv.ots.olutechsys.com
Returns: 73.212.176.x (public IP)
Result: curl times out (hairpin NAT failure)
```

## Solution: Split-Horizon DNS

Internal clients get internal IP (10.0.1.15), external clients get public IP.

---

## Setup Checklist

### ✓ Step 1: Enable Synology DNS Server
```bash
ssh admin@10.0.1.15 -p 28
sudo synoservice --status dnsmasq
# → dnsmasq is running
```

### ✓ Step 2: Create DNS Zones (Web UI or CLI)

**Web UI:** DSM → Control Panel → DNS Server → Zone tab → Create Master Zone
- Zone: `ots.olutechsys.com`
- Record: `*` → A → `10.0.1.15`

**CLI:**
```bash
sudo tee /etc/dnsmasq.d/views.conf > /dev/null <<'EOF'
address=/ots.olutechsys.com/10.0.1.15
address=/.ots.olutechsys.com/10.0.1.15
address=/mft.olutechsys.com/10.0.1.24
address=/.mft.olutechsys.com/10.0.1.24
EOF

sudo synoservice --restart dnsmasq
```

### ✓ Step 3: Test on NAS
```bash
nslookup otsdrv.ots.olutechsys.com 127.0.0.1
# → 10.0.1.15 ✓

curl -kI https://otsdrv.ots.olutechsys.com
# → 200/301 ✓
```

### ✓ Step 4: Update Router DHCP

ASUS Web UI: Advanced Settings → LAN → DHCP Server
- DNS Server 1: `10.0.1.15`
- DNS Server 2: `8.8.8.8` (optional fallback)
- **Apply**

### ✓ Step 5: Verify on Client

From any LAN device (not NAS):
```bash
nslookup otsdrv.ots.olutechsys.com
# → 10.0.1.15 ✓

curl -kI https://otsdrv.ots.olutechsys.com
# → 200/301 ✓
```

---

## How to Know It Works

| Test | Command | Expected | Status |
|------|---------|----------|--------|
| Internal DNS | `nslookup otsdrv.ots.olutechsys.com` | `10.0.1.15` | ? |
| Traefik TLS | `curl -kI https://otsdrv.ots.olutechsys.com` | `200` or `301` | ? |
| External DNS | `nslookup otsdrv.ots.olutechsys.com` (from non-LAN) | `73.212.176.x` | ? |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| nslookup returns NXDOMAIN | Verify `/etc/dnsmasq.d/views.conf` exists; restart dnsmasq |
| Client not using NAS DNS | Verify router DHCP points to 10.0.1.15; renew DHCP lease on client |
| curl still times out | Check Traefik is running: `docker ps \| grep traefik` |
| Test after DNS changes | Clear client DNS cache: `sudo dscacheutil -flushcache` (macOS) |

---

## Files Added

- **`docs/hive/SYNOLOGY_DNS_VIEWS.md`** — Full setup guide
- **`scripts/verify-dns-views.sh`** — Automated verification script

---

## Key Facts

- **acme-sh unaffected** — uses Cloudflare API directly, not internal DNS
- **Traefik unaffected** — still terminates TLS on 10.0.1.15:443
- **No double TLS** — internal clients bypass DDNS hop, hit Traefik locally
- **External clients unaffected** — Cloudflare serves public IP
