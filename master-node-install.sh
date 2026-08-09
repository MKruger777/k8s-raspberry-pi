
#==============================================================================
#
# title           : master-node-install.sh
# description     : This script aims to provision a k8s master node on a raspberry pi (v1.36 + Calico v3.29).
#                 : Included:
#                 : kubeadm, kubectl and kubelet  (Kubernetes v1.31.)
#                 : containerD
#                 : Calico for Container Network Interface (CNI)  (pod-network-cidr used "10.244.0.0/16")
# author          : Morné Kruger
# date            : 10.12.2024
# version         : 0.1
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

echo "--- Start initializing Master Node ---"
echo "--- Enable the kubelet service ---"
sudo systemctl enable --now kubelet

# Isolate primary node IP address safely
MASTER_NODE_IP=$(hostname -I | awk '{print $1}')
echo "Master node IP bound to: $MASTER_NODE_IP"

echo "Define Pod Network CIDR for Calico"
POD_CIDR="10.244.0.0/16"
echo "Pod Network CIDR for Calico is set to = $POD_CIDR"
echo "Initialize Kubernetes Control Plane"
sudo kubeadm init --apiserver-advertise-address="$MASTER_NODE_IP" --pod-network-cidr="$POD_CIDR" --upload-certs

echo "--- Set up local non-root user kubeconfig permissions---"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "Giving the API server a moment (15s) to settle down before making API calls ... "
sleep 15

echo "--- Deploying  Tigera Operator for Calico CNI Operator (v3.29.1 ARM64 Fix) ---"
echo "--- # 1. Installing the Tigera operator ---"
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/tigera-operator.yaml

echo "---  2. Download the default Calico custom resources manifest ---"
curl -fsSL -O https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/custom-resources.yaml

echo "---  3. Dynamically update Calico's default IP pool string to match your cluster POD_CIDR ---"
sed -i "s|cidr: 192.168.0.0/16|cidr: $POD_CIDR|g" custom-resources.yaml

echo "---  4. Apply the modified configuration to instantiate the Calico pods ---"
kubectl create -f custom-resources.yaml

echo "Master node setup complete!"
echo "Watch your Calico pods come up using: kubectl get pods -n calico-system -w"