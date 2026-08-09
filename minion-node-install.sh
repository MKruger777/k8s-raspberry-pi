
#==============================================================================
#
# title           : minion-node-install.sh
# description     : This script aims to provision a k8s minion node on a raspberry pi (v1.36 + Calico v3.29).
#                 : Included:
#                 : kubeadm, kubectl and kubelet (Kubernetes v1.31.)
#                 : containerD
# author          : Morné Kruger
# date            : 10.12.2024
# version         : 0.1
# usage           : ./minion-node-install.sh
#                 : you need to deploy the script to the raspberry pi that you want as the minion (aka worker) node. This can be automated via a clone of a repo or just a simple scp command.
#                 : sudo scp minion-node-install.sh morne@<minion_node_name>.local:~/
#                 : example:  sudo scp minion-node-install.sh morne@p2-minion.local:~/
#
# depends on      : - being able to run sudo commands.
#                   - working internet connection.
#                   - bash.
#                   - os tested on = ubuntu server 10.24.01
# bash_version    : tested on 5.0.11(1)-release
#
#==============================================================================

#!/bin/sh
set -e

echo "--- Turning off swap (Required by K8s) ---"
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "--- Configuring Kernel Modules ---"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
overlay
EOF

echo "---  Load kernel modules (modprobe br_netfilter and overlay) into the current session ---"
sudo modprobe br_netfilter
sudo modprobe overlay

echo "--- Enable IPv4 packet forwarding ---"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

echo "--- Installing Prerequisites ---"
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

echo "--- Set up the official Kubernetes v1.36 repository ---"
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

echo "--- Installing Container Runtime (containerd) ---"
sudo apt-get update
sudo apt-get install -y containerd

echo "--- Configure containerd to use Systemd Cgroup driver ---"
sudo mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd

echo "--- Installing Kubernetes core binaries (Kubelet, Kubeadm, Kubectl) v1.36 ---"
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "--- Start initializing Minion Node ---"
echo "--- Enable the kubelet service ---"
sudo systemctl enable --now kubelet

echo "Minion node provisioning completed successfully!"
echo "Run the 'kubeadm join' command outputted by your master node to attach this worker."