
#==============================================================================
#
# title           : master-node-install.sh
# description     : This script aims to provision a k8s master node on a raspberry pi.
#                 : Included:
#                 : kubeadm, kubectl and kubelet  (Kubernetes v1.31.)
#                 : containerD
#                 : Flannel (pod-network-cidr used "10.244.0.0/16")
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

echo "   !!!   master node configuration ONLY!"
echo ""
echo "init master node..."

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
MASTER_NODE_IP=$(hostname -I)
echo "master node ip set to $MASTER_NODE_IP"
echo "running kubeadm init ... "
sudo kubeadm init --apiserver-advertise-address $MASTER_NODE_IP --pod-network-cidr "10.244.0.0/16" --upload-certs

echo "waiting on kubeconfig file creation @ /etc/kubernetes/admin.conf ..."
until [ -f /etc/kubernetes/admin.conf ]
do
     sleep 5
done
echo "kubeconfig file ready to be copied !"

echo ""
echo "setup kubeconfig file in correct location to make kubectl work out of the box ... "
echo '$HOME variable is =  ' $HOME 
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo ""
echo "testing kubectl with new kubeconfig file ... "
kubectl get nodes

echo ""
echo "Installing a Pod network (flannel) add-on ..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml


echo ""
echo "master node provisioning complete. Check output for errors."
echo "as soon as a minion node(s) are ready to join, it can be done by running the kubeadm join command on each minion node that wishes to join the cluster."
echo "use command :"
echo "kubeadm join <master node ip>:6443  --token <token> --discovery-token-ca-cert-hash sha256:<token>"
echo "ATTENTION - EXAMPLE ONLY!!"
echo "kubeadm join 192.168.1.101:6443 --token ctig06.yubi6iamfakefviq --discovery-token-ca-cert-hash sha256:1891f0fdd09e3d73094ca12345678910eabec4290f1a7iamfakefb77dfedf412"
echo "USE THE EXACT STATEMENT THAT WAS GENEREATED DURING YOUR MASTER NODE PROVISIONING!"