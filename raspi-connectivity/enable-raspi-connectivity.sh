#!/bin/bash

# Get laptop gateway IP (run on Pi, replacing 10.42.0.219 with t460's current IP if it changes)
GATEWAY_IP="10.42.0.219"
echo "ATTENTION! The host (laptop's) IPv4 address that will be used = $GATEWAY_IP"
echo "If this not correct or you want to re-check the current value by running the scrip get-laptop-ethernet-ip.sh"
read -p "Do you want to continue? (Press Y/y to continue, any other key to exit): " -n 1 -r
echo    # Move to a new line after keypress

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Exiting..."
    exit 1
fi

echo "Continuing script..."

# 1. Immediate Runtime Route Update
sudo ip route del default 2>/dev/null || true
sudo ip route add default via "$GATEWAY_IP" dev eth0

# 2. Persist Default Route via Netplan
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
CURRENT_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+')

if [ -z "$CURRENT_IP" ]; then
    echo "[!] Warning: Could not detect static IP on eth0. Skipping Netplan auto-write."
else
    echo "[*] Writing persistent route via $GATEWAY_IP for $CURRENT_IP to $NETPLAN_FILE..."
    sudo bash -c "cat <<EOF > $NETPLAN_FILE
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - $CURRENT_IP
      routes:
        - to: default
          via: $GATEWAY_IP
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
EOF"
    sudo chmod 600 "$NETPLAN_FILE"
    sudo netplan apply
fi

# 3. Bypass systemd-resolved and set static public DNS
# Remove immutable attribute if present to allow editing
sudo chattr -i /etc/resolv.conf 2>/dev/null || true

# Remove old symlink/file and write static nameservers
sudo rm -f /etc/resolv.conf
sudo bash -c 'cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF'

# Re-apply immutable attribute (read-only even for root)
sudo chattr +i /etc/resolv.conf

# 4. Prevent systemd-resolved from recreating the symlink on reboot
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# 5. Verify connectivity
ping -c 2 ports.ubuntu.com && sudo apt update