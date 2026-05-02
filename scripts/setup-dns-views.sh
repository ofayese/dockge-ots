#!/bin/bash
# One-line DNS Views setup for OTS + MFT
# Run on OTS NAS: ssh admin@10.0.1.15 -p 28, then paste this

# Verify Synology DNS Server is installed
sudo synoservice --status dnsmasq || (echo "ERROR: dnsmasq not running. Install DNS Server package first." && exit 1)

# Create the views configuration
sudo tee /etc/dnsmasq.d/views.conf > /dev/null <<'EOF'
# Synology DNS Server Views — Internal split-horizon DNS
# OTS internal zone
address=/ots.olutechsys.com/10.0.1.15
address=/.ots.olutechsys.com/10.0.1.15

# MFT internal zone
address=/mft.olutechsys.com/10.0.1.24
address=/.mft.olutechsys.com/10.0.1.24
EOF

echo "✓ DNS Views configuration created"

# Restart dnsmasq to apply changes
sudo synoservice --restart dnsmasq
echo "✓ dnsmasq restarted"

# Verify it worked
echo ""
echo "Testing OTS zone..."
nslookup otsdrv.ots.olutechsys.com 127.0.0.1 | grep "Address:"

echo ""
echo "Testing MFT zone..."
nslookup mftdrv.mft.olutechsys.com 127.0.0.1 | grep "Address:"

echo ""
echo "✓ DNS Views enabled!"
echo ""
echo "Next: Update router DHCP to use 10.0.1.15 as DNS Server 1"
echo "Then: Run verify-dns-views.sh from a client to confirm"
