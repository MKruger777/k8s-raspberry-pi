#!/bin/bash
#==============================================================================
#
# title           : master-node-install.sh
# description     : This script aims to provision a k8s master node on a raspberry pi (v1.36 + Calico v3.29).
#                 : Included:
#                 : kubeadm, kubectl and kubelet  (Kubernetes v1.31.)
#                 : containerD
#                 : Calico for Container Network Interface (CNI)  (pod-network-cidr used "10.244.0.0/16")
# author          : Morné Kruger
# date            : 10.08.2026
# version         : 0.2
# usage           : ./master-node-install.sh
#                 : you need to deploy the script to the raspberry pi that you want as the master node. This can be automated via a clone of a repo or just a simple scp command.
#                 : sudo scp master-node-install.sh morne@<master_node_name>.local:~/
#                 : example: sudo scp master-node-install.sh morne@p1-master.local:~/
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

echo ""
echo "--- Enable IPv4 packet forwarding ---"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

echo ""
echo "--- Apply sysctl params without reboot ---"
sudo sysctl --system

echo ""
echo "--- Installing Prerequisites ---"
echo "--- Verifing that net.ipv4.ip_forward is set to 1. Current value =  "
sysctl net.ipv4.ip_forward
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

echo ""
echo "--- Set up the official Kubernetes v1.36 repository ---"
# If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
# In releases older than Debian 12 and Ubuntu 22.04, directory /etc/apt/keyrings does not exist by default, and it should be created before the curl command.
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

echo ""
echo "--- Installing Container Runtime (containerd) ---"
sudo apt-get update
sudo apt-get install -y containerd

echo ""
echo "--- Configure containerd to use Systemd Cgroup driver ---"
sudo mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml

echo ""
echo "check that the set cgroup drive to use systemd was done correctly ..."
cat /etc/containerd/config.toml  | grep -i SystemdCgroup -B 50

echo ""
echo "--- Restarting containerd service ---"
sudo systemctl restart containerd

echo ""
echo "--- Installing Kubernetes core binaries (Kubelet, Kubeadm, Kubectl) v1.36 ---"
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo ""
echo "--- Start initializing Master Node ---"
echo "--- Enable the kubelet service ---"
sudo systemctl enable --now kubelet

echo ""
echo "--- Isolate primary node IP address safely ---"
MASTER_NODE_IP=$(hostname -I | awk '{print $1}')
echo "Master node IP bound to: $MASTER_NODE_IP"

echo ""
echo "--- Define Pod Network CIDR for Calico ---"
POD_CIDR="10.244.0.0/16"
echo "--- Pod Network CIDR for Calico is set to = $POD_CIDR ---"
echo "--- Initialize Kubernetes Control Plane ---"
sudo kubeadm init --apiserver-advertise-address="$MASTER_NODE_IP" --pod-network-cidr="$POD_CIDR" --upload-certs

echo ""
echo "--- Waiting on kubeconfig file creation @ /etc/kubernetes/admin.conf ---"
until [ -f /etc/kubernetes/admin.conf ]
do
     sleep 5
     echo " --- Rechecking existance of /etc/kubernetes/admin.conf ---"
done
echo "--- Found! kubeconfig file ready to be copied! ---"

echo ""
echo "--- Setup kubeconfig file in correct location ---"
echo "---$HOME variable is = $HOME ---" 
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo ""
echo "--- Pause 15s to allow API server to settle ---"
sleep 15

echo ""
echo "--- Testing kubectl with new kubeconfig file ---"
kubectl get nodes

echo ""
echo "--- Deploying  Tigera Operator for Calico CNI Operator (v3.29.1 ARM64 Fix) ---"
echo "--- # 1. Installing the Tigera operator ---"
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/tigera-operator.yaml

echo ""
echo "---  2. Download the default Calico custom resources manifest ---"
curl -fsSL -O https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/custom-resources.yaml

echo ""
echo "---  3. Dynamically update Calico's default IP pool string to match your cluster POD_CIDR ---"
sed -i "s|cidr: 192.168.0.0/16|cidr: $POD_CIDR|g" custom-resources.yaml

echo ""
echo "---  4. Apply the modified configuration to instantiate the Calico pods ---"
kubectl create -f custom-resources.yaml

echo ""
echo "--- Master node provisioning completed. Check output for errors. ---"
echo "--- As soon as a minion node(s) are ready to join, it can be done by running the kubeadm join command on each minion node that wishes to join the cluster. ---"
echo "--- Use command : ---"
echo "--- ATTENTION - EXAMPLE ONLY!! ---"
echo "--- Kubeadm join <master node ip>:6443  --token <token> --discovery-token-ca-cert-hash sha256:<token> ---"
echo "--- Kubeadm join 192.168.1.101:6443 --token ctig06.yubi6iamfakefviq --discovery-token-ca-cert-hash sha256:1891f0fdd09e3d73094ca12345678910eabec4290f1a7iamfakefb77dfedf412 ---"
echo "--- USE THE EXACT STATEMENT THAT WAS GENEREATED DURING YOUR MASTER NODE PROVISIONING! ---"