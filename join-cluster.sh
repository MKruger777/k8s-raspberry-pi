#!/bin/bash
#==============================================================================
# title           : join-cluster.sh
# description     : Automatically fetches the kubeadm join command from the 
#                 : master node and joins the minion node to the cluster.
# usage           : ./join-cluster.sh <master_ip_or_hostname> <master_user>
# example         : ./join-cluster.sh 192.168.1.101 morne
#==============================================================================

set -e

MASTER_HOST=$1
MASTER_USER=$2

if [ -z "$MASTER_HOST" ] || [ -z "$MASTER_USER" ]; then
    echo "Usage: $0 <master_ip_or_hostname> <master_user>"
    echo "Example: $0 192.168.1.101 morne"
    exit 1
fi

echo "--- Fetching fresh kubeadm join command from master node ($MASTER_HOST)... ---"

# 1. SSH into the master node and create a new token with print-join-command
JOIN_CMD=$(ssh -t "${MASTER_USER}@${MASTER_HOST}" "sudo kubeadm token create --print-join-command" 2>/dev/null | tr -d '\r')

if [ -z "$JOIN_CMD" ]; then
    echo "Error: Failed to retrieve join command from master node."
    echo "Make sure SSH access is configured and the user has sudo privileges on $MASTER_HOST."
    exit 1
fi

echo "--- Joining cluster with command: ---"
echo "sudo $JOIN_CMD"
echo ""

# 2. Execute the join command on the local minion node
sudo $JOIN_CMD

echo ""
echo "--- Successfully joined the cluster! ---"
echo "Run 'kubectl get nodes' on your master node to verify this node is Ready."