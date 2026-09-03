cat << 'EOF' > enable-sharing.sh
#!/usr/bin/env bash
set -e

# 1. Detect active network interfaces
WIFI_IF=$(ip route show default | awk '{print $5}' | head -n 1)
ETH_IF="enp0s31f6"

if [ -z "$WIFI_IF" ]; then
    echo "[-] Error: No active Wi-Fi interface with a default route found."
    exit 1
fi

echo "[+] Outbound Wi-Fi Interface : $WIFI_IF"
echo "[+] Inbound Ethernet Interface: $ETH_IF"

# 2. Enable kernel IPv4 forwarding
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null

# 3. Flush & apply NAT masquerading
sudo iptables -t nat -F POSTROUTING
sudo iptables -t nat -A POSTROUTING -o "$WIFI_IF" -j MASQUERADE

# 4. Configure forward rules
sudo iptables -F FORWARD
sudo iptables -A FORWARD -j ACCEPT

# 5. Get current laptop IP on the shared link
LAPTOP_IP=$(ip -4 addr show "$ETH_IF" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)

echo "======================================================"
echo "[SUCCESS] Internet sharing active."
echo "Use Gateway IP for Pis: $LAPTOP_IP"
echo "======================================================"
EOF

chmod +x enable-sharing.sh