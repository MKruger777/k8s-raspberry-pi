#!/bin/bash
#==============================================================================
# title           : join-cluster.sh
# description     : Automatically fetches the kubeadm join command from the 
#                 : master node and joins the minion node to the cluster.
# usage           : ./join-cluster.sh <master_ip_or_hostname> <master_user>
# example         : ./join-cluster.sh 192.168.1.101 morne
#==============================================================================

set -e

echo "--- Starting theretrieval from the master pie ---"
#depends on ssh to p1-master and executing the following command:
#sudo cp /etc/kubernetes/admin.conf ~/config && sudo chown morne:morne ~/config
sudo scp morne@p1-master.local:~/config ~/.kube/config-pi

echo ""
echo "--- Updating the ip address joined the cluster! ---"
# Replace 10.42.0.100 with your p1-master IP address if different
sudo sed -i 's|server: https://127.0.0.1:6443|server: https://p1-master.local:6443|g' ~/.kube/config-pi

echo ""
echo "--- Backup existing config ---"
sudo cp ~/.kube/config ~/.kube/config.bak 2>/dev/null || true

echo "--- Merge configs into a single file ---"
sudo KUBECONFIG=~/.kube/config:~/.kube/config-pi kubectl config view --flatten > ~/.kube/config_merged
sudo mv ~/.kube/config_merged ~/.kube/config

echo "--- Switch context explicitly to your Pi cluster ---"
kubectl config use-context kubernetes-admin@kubernetes