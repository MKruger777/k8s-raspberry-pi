#!/bin/bash
#==============================================================================
#
# title           : minion-node-install.sh
# description     : This script aims to provision a k8s minion node on a raspberry pi (v1.36 + Calico v3.29).
#                 : Included:
#                 : kubeadm, kubectl and kubelet (Kubernetes v1.36)
#                 : containerd
# author          : Morné Kruger
# date            : 10.08.2026
# version         : 0.2
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
set -e

echo "--- Turning off swap (Required by K8s) ---"
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "--- Configuring Kernel Modules ---"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
overlay
EOF

echo "--- Loading kernel modules (br_netfilter & overlay) into current session ---"
sudo modprobe br_netfilter
sudo modprobe overlay

echo "--- Enable IPv4 packet forwarding ---"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

echo ""
echo "--- Apply sysctl params without reboot ---"
sudo sysctl --system

echo "--- Installing Prerequisites ---"
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

echo "--- Set up the official Kubernetes v1.36 repository ---"
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# In releases older than Debian 12 and Ubuntu 22.04, directory /etc/apt/keyrings does not exist by default, and it should be created before the curl command.
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

echo "--- Installing Container Runtime (containerd) ---"
sudo apt-get update
sudo apt-get install -y containerd

echo "--- Configure containerd to use Systemd Cgroup driver ---"
sudo mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml

echo ""
echo "--- Restarting containerd service ---"
sudo systemctl restart containerd

echo "--- Installing Kubernetes core binaries (Kubelet, Kubeadm, Kubectl) v1.36 ---"
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "--- Start initializing Minion Node ---"
echo "--- Enable the kubelet service ---"

sudo systemctl enable --now kubelet

echo ""
echo "--- Getting minion node IP ---"
MINION_NODE_IP=$(hostname -I | awk '{print $1}')
echo "--- Minion node IP bound to: $MINION_NODE_IP ---"

echo "--- Minion node provisioning completed ---"
echo "--- When ready, the minion node can join the cluster by running the 'kubeadm join' command. The exact command can be found in the master node's output. --- "
echo "--- Command structure should look like: ---"
echo "--- ATTENTION - EXAMPLE ONLY!! ---"
echo "--- kubeadm join <master node ip>:6443  --token <token> --discovery-token-ca-cert-hash sha256:<discovery-token-ca-cert-hash> ---"
echo "--- kubeadm join 192.168.1.101:6443 --token ctig06.yubi6iamfakefviq --discovery-token-ca-cert-hash sha256:1891f0fdd09e3d73094ca12345678910eabec4290f1a7iamfakefb77dfedf412 ---"
echo "--- USE THE EXACT STATEMENT THAT WAS GENEREATED DURING YOUR MASTER NODE PROVISIONING ---"
echo "--- IT SHOULD BE RUN ON THE MINION NODE THAT WISH TO JOIN THE CLUSTER! ---"