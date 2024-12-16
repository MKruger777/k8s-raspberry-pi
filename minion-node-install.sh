
#==============================================================================
#
# title           : minion-node-install.sh
# description     : This script aims to provision a k8s minion node on a raspberry pi.
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

echo ""
echo "enable IPv4 packet forwarding..."
# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

echo ""
echo "Apply sysctl params without reboot..."
sudo sysctl --system

echo ""
echo "Verifing that net.ipv4.ip_forward is set to 1. Current value = "
sysctl net.ipv4.ip_forward

sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# In releases older than Debian 12 and Ubuntu 22.04, directory /etc/apt/keyrings does not exist by default, and it should be created before the curl command.
# sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo ""
echo "checking the version of kubeadm ..."
kubeadm version

echo ""
echo "starting container runtime install ..."

sudo apt update
sudo apt install -y containerd

echo ""
echo "set cgroup drive to use systemd..."
sudo mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml

echo ""
echo "check that the set cgroup drive to use systemd was done correctly ..."
cat /etc/containerd/config.toml  | grep -i SystemdCgroup -B 50

echo ""
echo "restarting systemd..."
sudo systemd restart containerd

echo ""
echo "Configure the Kernel Module ‘br_netfilter’ in the containerd configuration file..."
sudo tee /etc/modules-load.d/containerd.conf <<EOF
br_netfilter
EOF

echo ""
echo "Load the br_netfilter modules into the running Linux kernel."
sudo modprobe br_netfilter

echo "Enable the kubelet service before running kubeadm ..."
sudo systemctl enable --now kubelet
echo "done"

echo ""
echo "getting master node ip ..."
MINION_NODE_IP=$(hostname -I)
echo "minion node ip set to $MINION_NODE_IP"

echo ""
echo "minion node provisioning completed"
echo "when ready, the minion node can join the cluster by running the 'kubeadm join' command. The exact command can be found in the master node's output."
echo "command structure should look like: "
echo "kubeadm join <master node ip>:6443  --token <token> --discovery-token-ca-cert-hash sha256:<discovery-token-ca-cert-hash>"
echo "ATTENTION - EXAMPLE ONLY!!"
echo "kubeadm join 192.168.1.101:6443 --token ctig06.yubi6iamfakefviq --discovery-token-ca-cert-hash sha256:1891f0fdd09e3d73094ca12345678910eabec4290f1a7iamfakefb77dfedf412"
echo "USE THE EXACT STATEMENT THAT WAS GENEREATED DURING YOUR MASTER NODE PROVISIONING"
echo "IT SHOULD BE RUN ON THE MINION NODE THAT WISH TO JOIN THE CLUSTER!"
