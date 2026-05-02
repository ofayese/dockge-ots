# Synology DNS Server — Split-Horizon DNS Configuration

## Overview

This guide configures Synology DNS Server with Views to resolve internal service hostnames to their internal LAN IPs from within your home network, while external resolvers see the public IP. This solves the hairpin NAT problem where internal clients cannot reach services using their external DDNS hostnames.

**Problem solved:**
```
Before: nslookup otsdrv.ots.olutechsys.com → 73.212.176.x (public IP)
        curl https://otsdrv.ots.olutechsys.com → TIMEOUT (hairpin NAT failure)

After:  nslookup otsdrv.ots.olutechsys.com → 10.0.1.15 (internal IP)
        curl https://otsdrv.ots.olutechsys.com → ✓ Works (local Traefik)
```

---

## Prerequisites

- **Synology DNS Server package installed** on OTS NAS (via Package Center)
- **OTS NAS IP:** 10.0.1.15
- **Router DHCP configured** to hand out NAS as primary DNS (done later)
- **Cloudflare managing `olutechsys.com`** (for root domain and existing certs)

---

## Step 1: Enable Synology DNS Server

1. SSH into OTS NAS (10.0.1.15):
   ```bash
   ssh admin@10.0.1.15 -p 28
   ```

2. Verify the DNS Server package is installed:
   ```bash
   sudo synoservice --status dnsmasq
   # Should return: dnsmasq is running
   ```

3. If not installed, use **Synology Package Center** (DSM UI):
   - Go to **Package Center** → search **DNS Server**
   - Click **Install**
   - Wait for completion

---

## Step 2: Configure Synology DNS Server Views

Synology DNS Server stores configuration in `/etc/dnsmasq.d/` and the DSM UI. For Views, we'll configure zones directly and via the UI.

### Option A: Web UI (Recommended for first-time setup)

1. Open **DSM** → **Control Panel** → **DNS Server**
2. Go to the **Zone** tab
3. Click **Create** → **Master Zone**

   **For OTS internal zone:**
   - **Zone name:** `ots.olutechsys.com`
   - **Type:** Master
   - **Nameserver:** `otsorundscore.synology.me` (or your NAS FQDN)
   - Click **Create**

4. In the new zone, click **Create Record** and add:
   ```
   Name:  *                    (wildcard)
   Type:  A
   Value: 10.0.1.15           (OTS NAS internal IP)
   TTL:   300
   ```

5. Repeat for MFT (if needed):
   - **Zone name:** `mft.olutechsys.com`
   - **Wildcard A record:** `10.0.1.24` (Misfits NAS internal IP)

### Option B: CLI (Advanced / Scriptable)

Create `/etc/dnsmasq.d/views.conf` with:

```bash
sudo tee /etc/dnsmasq.d/views.conf > /dev/null <<'EOF'
# OTS internal zone — wildcard resolves to internal IP
address=/ots.olutechsys.com/10.0.1.15
address=/.ots.olutechsys.com/10.0.1.15

# MFT internal zone — wildcard resolves to internal IP
address=/mft.olutechsys.com/10.0.1.24
address=/.mft.olutechsys.com/10.0.1.24
EOF
```

Then reload dnsmasq:

```bash
sudo synoservice --restart dnsmasq
```

Verify:

```bash
nslookup otsdrv.ots.olutechsys.com 127.0.0.1
# Should return: 10.0.1.15
```

---

## Step 3: Update Router DHCP to Use NAS as DNS

**Goal:** Clients on your LAN get 10.0.1.15 as their DNS server instead of the router's default.

### ASUS Web UI

1. SSH into your ASUS router (or access via web UI):
   ```bash
   ssh admin@192.168.1.1
   ```

2. In the ASUS web UI, go to:
   - **Advanced Settings** → **LAN** → **DHCP Server**

3. Find the **DNS Server** field:
   - **DNS Server 1:** `10.0.1.15` (OTS NAS)
   - **DNS Server 2:** `8.8.8.8` (fallback, optional)

4. **Apply** and wait for DHCP lease renewal (or restart clients manually)

5. Verify on a client:
   ```bash
   # On any device on your LAN
   nslookup otsdrv.ots.olutechsys.com
   # Should return: 10.0.1.15
   ```

---

## Step 4: Verify Internal Resolution

From any device on your LAN:

```bash
# Test internal resolution
nslookup otsdrv.ots.olutechsys.com
# Expected: 10.0.1.15

# Test that it works
curl -kI https://otsdrv.ots.olutechsys.com
# Expected: 200 / 301 (successful TLS + Traefik routing)
```

From the OTS NAS itself:

```bash
ssh admin@10.0.1.15 -p 28
nslookup otsdrv.ots.olutechsys.com
# Should return: 10.0.1.15 (from local DNS on 127.0.0.1:53)
```

---

## Step 5: Verify External Resolution (Optional)

External resolvers should still see your public IP:

```bash
# From a computer NOT on your LAN (e.g., phone on cellular or a friend's network)
nslookup otsdrv.ots.olutechsys.com
# Expected: 73.212.176.x (your public IP from Cloudflare)
```

This is handled by Cloudflare (external) and is unaffected by internal DNS changes.

---

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│ Internal Client (10.0.1.x)                              │
│ DHCP-configured to use 10.0.1.15 as DNS                 │
└──────────────────┬──────────────────────────────────────┘
                   │ DNS query: otsdrv.ots.olutechsys.com
                   ↓ (UDP port 53)
┌─────────────────────────────────────────────────────────┐
│ Synology DNS Server on OTS NAS (10.0.1.15:53)           │
│ Zone ots.olutechsys.com → *.ots → 10.0.1.15            │
│ Zone mft.olutechsys.com → *.mft → 10.0.1.24            │
│ Everything else → forward to router/8.8.8.8             │
└──────────────────┬──────────────────────────────────────┘
                   │ Response: 10.0.1.15
                   ↓
┌─────────────────────────────────────────────────────────┐
│ Internal Client                                          │
│ Connects to 10.0.1.15:443 → Traefik TLS termination     │
│ ✓ Success — no external routing, no hairpin NAT needed  │
└─────────────────────────────────────────────────────────┘

────────────────────────────────────────────────────────────

┌─────────────────────────────────────────────────────────┐
│ External Client (NOT on your LAN)                       │
│ Queries public resolver (8.8.8.8, 1.1.1.1, etc.)        │
│ No DHCP → uses configured/OS default resolver           │
└──────────────────┬──────────────────────────────────────┘
                   │ DNS query: otsdrv.ots.olutechsys.com
                   ↓
┌─────────────────────────────────────────────────────────┐
│ Cloudflare (authoritative for olutechsys.com)           │
│ *.ots → CNAME otsorundscore.synology.me                 │
│ otsorundscore.synology.me → 73.212.176.x (DDNS IP)      │
│ Response: 73.212.176.x (public IP)                      │
└──────────────────┬──────────────────────────────────────┘
                   │ Response: 73.212.176.x
                   ↓
┌─────────────────────────────────────────────────────────┐
│ External Client                                         │
│ Connects to 73.212.176.x:443 → ISP router → Traefik     │
│ ✓ Success — Traefik terminates TLS, routes service      │
└─────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

### DNS still returns NXDOMAIN

1. Verify Synology DNS Server is running:
   ```bash
   sudo synoservice --status dnsmasq
   ```

2. Verify the zone was created:
   ```bash
   sudo cat /etc/dnsmasq.d/views.conf
   # Should show address=/ots.olutechsys.com/10.0.1.15
   ```

3. Restart dnsmasq:
   ```bash
   sudo synoservice --restart dnsmasq
   ```

4. Clear client DNS cache and retry:
   ```bash
   # On macOS:
   sudo dscacheutil -flushcache
   
   # On Linux:
   sudo resolvectl flush-caches
   
   # On Windows:
   ipconfig /flushdns
   ```

### NAS is not being used as DNS by clients

1. Verify router DHCP is set to `10.0.1.15`:
   - ASUS UI: **Advanced Settings** → **LAN** → **DHCP Server** → **DNS Server 1**

2. Force DHCP lease renewal on a test client:
   ```bash
   # On macOS:
   sudo ipconfig set en0 BOOTP && sudo ipconfig set en0 DHCP
   
   # On Linux:
   sudo dhclient -r && sudo dhclient
   
   # On Windows:
   ipconfig /release && ipconfig /renew
   ```

3. Verify the client is using the NAS DNS:
   ```bash
   # On macOS:
   scutil --dns | grep "nameserver\[0\]"
   # Should show: 10.0.1.15
   ```

### Curl still times out after DNS works

1. Verify Traefik is running on OTS:
   ```bash
   docker ps | grep traefik
   ```

2. Check Traefik logs:
   ```bash
   docker logs traefik-ots 2>&1 | tail -20
   ```

3. Verify the service hostname is configured in Traefik labels:
   ```bash
   docker inspect <service-container> --format='{{.Config.Labels}}'
   ```

4. Test TLS on Traefik directly:
   ```bash
   curl -kI https://10.0.1.15:443 -H "Host: otsdrv.ots.olutechsys.com"
   # Should return 200 or 301
   ```

---

## Single Point of Failure (Optional: Secondary DNS)

Right now, if the OTS NAS reboots, DNS is down until it comes back. Options:

### Option 1: Accept NAS availability coupling (simplest)

Document that DNS follows NAS uptime. No secondary needed.

### Option 2: Add Pi-hole in a container (recommended)

Deploy Pi-hole on the Misfits NAS or another device:

```yaml
# Example: stacks/pihole/compose.yaml
version: '3'
services:
  pihole:
    image: pihole/pihole:latest
    container_name: pihole
    hostname: pihole
    environment:
      TZ: America/New_York
      WEBPASSWORD: <PASSWORD>
      DNSMASQ_LISTENING: all
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"
    volumes:
      - ${STACK_ROOT}/pihole/config:/etc/dnsmasq.d/
      - ${STACK_ROOT}/pihole/pihole:/etc/pihole/
    restart: unless-stopped
    networks:
      - default
```

Then update router DHCP to prefer OTS, secondary to Pi-hole:
- **DNS Server 1:** `10.0.1.15` (OTS)
- **DNS Server 2:** `10.0.1.24` (Misfits / Pi-hole)

### Option 3: Technitium DNS (lightweight, containerized)

Similar to Pi-hole but lighter. Use if Pi-hole is overkill:

```yaml
services:
  technitium:
    image: technitium/dns-server:latest
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    volumes:
      - ${STACK_ROOT}/technitium/config:/etc/technitium/
    restart: unless-stopped
```

**For now, skip the secondary.** Once internal DNS is working, add it as a follow-up.

---

## Next Steps

1. **Immediate:** Apply Views configuration (Step 1–2)
2. **Router DHCP:** Update to use NAS as DNS (Step 3)
3. **Verify:** Test `nslookup` and `curl` from a client (Step 4)
4. **Later:** Add secondary DNS (Pi-hole or Technitium) if desired

Once internal DNS works, document the secondary resolver setup in `docs/hive/NAS_DEPLOYMENT.md`.

---

## Key Points

- **acme-sh is unaffected:** DNS-01 via Cloudflare API (direct, not through internal DNS)
- **External clients unaffected:** Cloudflare serves public IP; split-horizon DNS is internal-only
- **Traefik unchanged:** Still terminates TLS on `10.0.1.15:443`; DNS just gets clients to that IP locally
- **No double TLS:** Internal clients hit Traefik directly (local path), no external routing
