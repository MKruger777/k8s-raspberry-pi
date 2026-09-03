#!/usr/bin/env bash

# 1. Dynamically find the first physical Ethernet interface (names starting with 'eth' or 'en')
ETH_IF=$(ip -br link show | awk '$1 ~ /^(eth|en)/ {print $1}' | head -n 1)

if [ -z "$ETH_IF" ]; then
    echo "Error: No Ethernet interface found."
    exit 1
fi

# 2. Extract the IPv4 address assigned to that interface
IP_ADDR=$(ip -4 -br addr show "$ETH_IF" | awk '{print $3}' | cut -d'/' -f1)

if [ -z "$IP_ADDR" ]; then
    echo "Interface $ETH_IF found, but no IPv4 address is assigned."
    exit 1
fi

# Output the results
echo "Ethernet Interface : $ETH_IF"
echo "IP Address         : $IP_ADDR"