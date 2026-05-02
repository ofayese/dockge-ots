#!/bin/bash
# Verify Synology DNS Server Views configuration and internal DNS resolution
# Run from: any device on your LAN, or SSH into OTS NAS
# Usage: bash verify-dns-views.sh

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

OTS_NAS_IP="10.0.1.15"
MFT_NAS_IP="10.0.1.24"
OTS_DNS_SERVER="127.0.0.1"  # Use local if running on NAS, or change to $OTS_NAS_IP if remote
MFT_DNS_SERVER="$MFT_NAS_IP"

echo -e "${BOLD}━━ Synology DNS Views Verification ━━${NC}"
echo ""

# Test 1: DNS Server is reachable
echo -e "${BOLD}[Test 1] DNS Server reachability${NC}"
if ping -c 1 -W 2 "$OTS_NAS_IP" &>/dev/null; then
    echo -e "${GREEN}✓${NC} OTS NAS ($OTS_NAS_IP) is reachable"
else
    echo -e "${RED}✗${NC} OTS NAS ($OTS_NAS_IP) is NOT reachable"
    exit 1
fi

# Test 2: Internal zone resolution (OTS)
echo ""
echo -e "${BOLD}[Test 2] Internal zone resolution — OTS${NC}"
echo "Query: otsdrv.ots.olutechsys.com → should return $OTS_NAS_IP"
if result=$(nslookup otsdrv.ots.olutechsys.com "$OTS_DNS_SERVER" 2>&1); then
    if echo "$result" | grep -q "$OTS_NAS_IP"; then
        echo -e "${GREEN}✓${NC} Resolved correctly: $OTS_NAS_IP"
    else
        echo -e "${RED}✗${NC} Resolution failed or returned wrong IP:"
        echo "$result" | tail -5
    fi
else
    echo -e "${RED}✗${NC} nslookup failed:"
    echo "$result" | tail -5
fi

# Test 3: Wildcard resolution (OTS)
echo ""
echo -e "${BOLD}[Test 3] Wildcard resolution — OTS (*. ots.olutechsys.com)${NC}"
test_subdomain="testhost.ots.olutechsys.com"
echo "Query: $test_subdomain → should return $OTS_NAS_IP"
if result=$(nslookup "$test_subdomain" "$OTS_DNS_SERVER" 2>&1); then
    if echo "$result" | grep -q "$OTS_NAS_IP"; then
        echo -e "${GREEN}✓${NC} Wildcard works: $OTS_NAS_IP"
    else
        echo -e "${RED}✗${NC} Wildcard not working:"
        echo "$result" | tail -5
    fi
else
    echo -e "${RED}✗${NC} nslookup failed"
fi

# Test 4: MFT zone (if Misfits NAS is up)
echo ""
echo -e "${BOLD}[Test 4] Internal zone resolution — MFT (optional)${NC}"
echo "Query: mftdrv.mft.olutechsys.com → should return $MFT_NAS_IP"
if ping -c 1 -W 2 "$MFT_NAS_IP" &>/dev/null 2>&1; then
    if result=$(nslookup mftdrv.mft.olutechsys.com "$OTS_DNS_SERVER" 2>&1); then
        if echo "$result" | grep -q "$MFT_NAS_IP"; then
            echo -e "${GREEN}✓${NC} MFT resolved correctly: $MFT_NAS_IP"
        else
            echo -e "${YELLOW}⚠${NC} MFT zone not configured or returned different IP:"
            echo "$result" | tail -5
        fi
    fi
else
    echo -e "${YELLOW}⚠${NC} MFT NAS ($MFT_NAS_IP) not reachable — skipping"
fi

# Test 5: External domain fallback (should use upstream)
echo ""
echo -e "${BOLD}[Test 5] External domain fallback${NC}"
echo "Query: google.com (should resolve via upstream DNS)"
if result=$(nslookup google.com "$OTS_DNS_SERVER" 2>&1); then
    if echo "$result" | grep -qE "^Address: [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"; then
        echo -e "${GREEN}✓${NC} External resolution works"
    else
        echo -e "${RED}✗${NC} External resolution failed"
        echo "$result" | tail -5
    fi
fi

# Test 6: TLS connectivity to Traefik (curl)
echo ""
echo -e "${BOLD}[Test 6] TLS connectivity to Traefik on OTS${NC}"
echo "Testing: curl -kI https://otsdrv.ots.olutechsys.com"
if timeout 10 curl -kI https://otsdrv.ots.olutechsys.com 2>&1 | head -1; then
    echo -e "${GREEN}✓${NC} Traefik is responding"
else
    echo -e "${YELLOW}⚠${NC} Traefik may not be accessible or service not responding"
fi

# Test 7: Check client's DNS configuration (if not on NAS)
echo ""
echo -e "${BOLD}[Test 7] This machine's DNS configuration${NC}"
if [ -f /etc/resolv.conf ]; then
    primary_dns=$(grep -m1 "nameserver" /etc/resolv.conf | awk '{print $2}')
    echo "Primary DNS: $primary_dns"
    if [ "$primary_dns" = "$OTS_NAS_IP" ]; then
        echo -e "${GREEN}✓${NC} Using OTS NAS as primary DNS"
    else
        echo -e "${YELLOW}⚠${NC} Not using OTS NAS as primary DNS"
        echo "Expected: $OTS_NAS_IP, Got: $primary_dns"
    fi
elif command -v scutil &>/dev/null; then
    # macOS
    echo -e "${YELLOW}ℹ${NC} macOS detected. DNS configuration:"
    scutil --dns | grep -A1 "nameserver\[0\]" || echo "Could not read DNS config"
elif command -v ipconfig &>/dev/null; then
    # Windows
    echo -e "${YELLOW}ℹ${NC} Windows detected. Run 'ipconfig /all' to check DNS"
else
    echo -e "${YELLOW}ℹ${NC} Could not determine DNS configuration"
fi

# Summary
echo ""
echo -e "${BOLD}━━ Summary ━━${NC}"
echo -e "${GREEN}If all tests show ✓, internal DNS Views are working correctly.${NC}"
echo ""
echo "Next steps:"
echo "  1. Update router DHCP to use $OTS_NAS_IP as DNS Server 1"
echo "  2. Renew DHCP leases on all clients"
echo "  3. Re-run this script from a client to verify router integration"
echo ""
echo "Reference: docs/hive/SYNOLOGY_DNS_VIEWS.md"
