#!/bin/bash
#==============================================================================
# title           : image-ubuntu-pi.sh
# description     : CLI script to download, flash, and pre-configure Ubuntu Server 24.04
#                 : on Raspberry Pi using cloud-init for SSH, User, Hostname, and Wi-Fi.
# usage           : sudo ./image-ubuntu-pi.sh <dev> <hostname> <user> <pass> <wifi_ssid> <wifi_pass>
# example         : sudo ./image-ubuntu-pi.sh /dev/mmcblk0 p3-worker morne "MyPass" "HomeWiFi" "WiFiPassword123"
#==============================================================================

set -e

# --- Input Parameters ---
TARGET_DEV=$1
HOSTNAME_VAL=$2
USER_NAME=$3
USER_PASS=$4
WIFI_SSID=$5
WIFI_PASS=$6

if [ -z "$TARGET_DEV" ] || [ -z "$HOSTNAME_VAL" ] || [ -z "$USER_NAME" ] || [ -z "$USER_PASS" ] || [ -z "$WIFI_SSID" ] || [ -z "$WIFI_PASS" ]; then
    echo "Usage: sudo $0 <target_device> <hostname> <username> <password> <wifi_ssid> <wifi_pass>"
    echo "Example: sudo $0 /dev/mmcblk0 p3-worker morne MyPass 'MyHomeWiFi' 'SecretWiFiKey'"
    echo ""
    echo "⚠️  Run 'lsblk -e7' to verify your target device before running!"
    exit 1
fi

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)."
  exit 1
fi

# Check if target device exists
if [ ! -b "$TARGET_DEV" ]; then
    echo "❌ ERROR: Target device '$TARGET_DEV' does not exist."
    echo "Please insert your SD card and check 'lsblk -e7'."
    exit 1
fi

# --- SAFETY GUARD ---
# Verify the selected target is NOT hosting the root (/) or /boot filesystems
MOUNT_CHECK=$(lsblk -no MOUNTPOINTS "$TARGET_DEV" 2>/dev/null || true)
if echo "$MOUNT_CHECK" | grep -qE "^/$|^/boot"; then
    echo "-----------------------------------------------------------------"
    echo "❌ CRITICAL SAFETY ERROR:"
    echo "   $TARGET_DEV contains active system partitions (/ or /boot)!"
    echo "   Refusing to execute to prevent system destruction."
    echo "-----------------------------------------------------------------"
    exit 1
fi

# Confirm target device safety check
echo "================================================================="
echo " OS            : Ubuntu Server 24.04 LTS (ARM64)"
echo " TARGET DEVICE : $TARGET_DEV"
echo " HOSTNAME      : $HOSTNAME_VAL"
echo " USERNAME      : $USER_NAME"
echo " WI-FI SSID    : $WIFI_SSID"
echo "================================================================="
read -p "Are you ABSOLUTELY sure you want to overwrite $TARGET_DEV? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# URL for Ubuntu 24.04 LTS 64-bit Raspberry Pi Server image
IMG_URL="https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04-preinstalled-server-arm64+raspi.img.xz"
ZIP_FILE="ubuntu-24.04-preinstalled-server-arm64+raspi.img.xz"

# --- 1. Download OS Image ---
if [ ! -f "$ZIP_FILE" ]; then
    echo "--- Downloading Ubuntu Server 24.04 LTS (ARM64)... ---"
    curl -L -o "$ZIP_FILE" "$IMG_URL"
else
    echo "--- Using cached $ZIP_FILE ---"
fi

# --- 2. Flash Image to SD Card ---
echo "--- Flashing Ubuntu image to $TARGET_DEV (this may take a few minutes)... ---"
umount ${TARGET_DEV}* 2>/dev/null || true

xzcat "$ZIP_FILE" | dd of="$TARGET_DEV" bs=4M status=progress conv=fsync

sync
sleep 2

# --- 3. Mount Boot Partition (`system-boot`) ---
echo "--- Mounting system-boot partition for cloud-init pre-configuration... ---"
mkdir -p /mnt/piboot

if [[ "$TARGET_DEV" =~ "mmcblk" ]] || [[ "$TARGET_DEV" =~ "nvme" ]]; then
    BOOT_PART="${TARGET_DEV}p1"
else
    BOOT_PART="${TARGET_DEV}1"
fi

mount "$BOOT_PART" /mnt/piboot

# --- 4. Generate Cloud-Init Credentials & WiFi Config ---
echo "--- Writing cloud-init user-data config... ---"

# Generate SHA-512 encrypted password
PASS_HASH=$(openssl passwd -6 "$USER_PASS")

# Write native cloud-init user-data file
cat <<EOF > /mnt/piboot/user-data
#cloud-config

hostname: $HOSTNAME_VAL
manage_etc_hosts: true

users:
  - name: $USER_NAME
    gecos: Morné Kruger
    groups: [sudo, adm, dialout, cdrom, floppy, audio, dip, video, plugdev, netdev]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $PASS_HASH

ssh_pwauth: true
disable_root: true

# Configure Wi-Fi via Netplan inside cloud-init
write_files:
  - path: /etc/netplan/50-cloud-init.yaml
    permissions: '0600'
    content: |
      network:
        version: 2
        ethernets:
          eth0:
            dhcp4: true
            optional: true
        wifis:
          wifis-all:
            access-points:
              "$WIFI_SSID":
                password: "$WIFI_PASS"
            dhcp4: true
            optional: true

runcmd:
  - netplan apply
EOF

# Clean up & Unmount
sync
umount /mnt/piboot
rmdir /mnt/piboot

echo "================================================================="
echo " 🎉 Ubuntu Server Flashing & Provisioning Complete!"
echo " Insert the SD card into your Pi, power it on, and connect via SSH:"
echo " ssh $USER_NAME@$HOSTNAME_VAL.local"
echo "================================================================="