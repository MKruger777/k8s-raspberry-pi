# Kubernetes on Raspberry Pi (k8s-raspberry-pi)

Production-grade automation scripts for provisioning, networking, managing, and monitoring a bare-metal Kubernetes v1.36 cluster on Raspberry Pi 5 hardware running Ubuntu Server 24.04.

---

## Table of Contents
1. [Hardware & Architecture Overview](#hardware--architecture-overview)
2. [Network & Topology Diagram](#network--topology-diagram)
3. [How Network & DNS Traffic Flows](#how-network--dns-traffic-flows)
4. [Repository Structure & Script Reference](#repository-structure--script-reference)
5. [Step-by-Step Deployment Guide](#step-by-step-deployment-guide)
   - [Phase 1: Gateway & Network Sharing (Laptop `t800`)](#phase-1-gateway--network-sharing-laptop-t800)
   - [Phase 2: Persistent Connectivity & DNS Hardening (Pi Nodes)](#phase-2-persistent-connectivity--dns-hardening-pi-nodes)
   - [Phase 3: Control Plane Provisioning (`p1-master`)](#phase-3-control-plane-provisioning-p1-master)
   - [Phase 4: Worker Node Provisioning & Joining (`p2-minion`, `p3-minion`)](#phase-4-worker-node-provisioning--joining-p2-minion-p3-minion)
   - [Phase 5: Remote Cluster Management (`t800`)](#phase-5-remote-cluster-management-t800)
   - [Phase 6: Observability Stack Deployment](#phase-6-observability-stack-deployment)
6. [Key System Safeguards & Idempotency](#key-system-safeguards--idempotency)

---

## Hardware & Architecture Overview

* **Control Plane (`p1-master`)**: Raspberry Pi 5 running Ubuntu Server 24.04 (`10.42.0.100`).
* **Worker Nodes (`p2-minion`, `p3-minion`)**: Raspberry Pi 5 units running Ubuntu Server 24.04 (`10.42.0.x`).
* **Management Host / Gateway (`t800`)**: Laptop running Linux, serving as the network gateway/NAT bridge and central management workstation.
* **Switch / Router**: Unmanaged Gigabit Ethernet switch connecting all Pi nodes and the management laptop.
* **Container Network Interface (CNI)**: Calico v3.29.1 deployed via the Tigera Operator with a Pod CIDR of `10.244.0.0/16`.
* **Container Runtime**: `containerd` configured with systemd cgroups (`SystemdCgroup = true`).

---

## Network & Topology Diagram

```
                             +-----------------------+
                             |   Internet / Wi-Fi    |
                             +-----------+-----------+
                                         |
                                         | (wlan0 - DHCP/Public IP)
                                         v
                             +-----------------------+
                             |    Laptop Gateway     |
                             |        (t800)         |
                             |  IP: 10.42.0.219/24   |
                             +-----------+-----------+
                                         |
          (iptables NAT / MASQUERADE & net.ipv4.ip_forward=1)
                                         |
                                         | (enp0s31f6 - Static Link)
                                         v
                             +-----------------------+
                             |   Ethernet Switch /   |
                             |   Unmanaged Router    |
                             +---+-------+-------+---+
                                 |       |       |
           +---------------------+       |       +---------------------+
           |                             |                             |
           v                             v                             v
+---------------------+       +---------------------+       +---------------------+
|  Control Plane Node |       |    Worker Node 1    |       |    Worker Node 2    |
|     (p1-master)     |       |     (p2-minion)     |       |     (p3-minion)     |
|   10.42.0.100/24    |       |    10.42.0.x/24     |       |    10.42.0.x/24     |
+---------------------+       +---------------------+       +---------------------+
| • Default Gateway:  |       | • Default Gateway:  |       | • Default Gateway:  |
|   10.42.0.219       |       |   10.42.0.219       |       |   10.42.0.219       |
|   (via Netplan YAML)|       |   (via Netplan YAML)|       |   (via Netplan YAML)|
| • DNS Nameservers:  |       | • DNS Nameservers:  |       | • DNS Nameservers:  |
|   1.1.1.1, 8.8.8.8  |       |   1.1.1.1, 8.8.8.8  |       |   1.1.1.1, 8.8.8.8  |
| • /etc/resolv.conf  |       | • /etc/resolv.conf  |       | • /etc/resolv.conf  |
|   (chattr +i locked)|       |   (chattr +i locked)|       |   (chattr +i locked)|
+---------------------+       +---------------------+       +---------------------+
```

---

## How Network & DNS Traffic Flows

1. **Outbound Internet Path (NAT/Masquerade):**
   * All Raspberry Pi nodes set their default gateway route to the laptop's Ethernet IP (`10.42.0.219`) declaratively via Netplan (`/etc/netplan/01-netcfg.yaml`).
   * When a node or pod requests outbound internet traffic (e.g., pulling container images from `ghcr.io` or `docker.io`), the packet is routed over Ethernet to `t800`.
   * The `enable-laptop-sharing.sh` script enables kernel IPv4 forwarding (`net.ipv4.ip_forward=1`) and sets up an `iptables` NAT `MASQUERADE` rule. This rewrites the outgoing source IP to match the laptop's Wi-Fi address before sending it out to the internet.

2. **DNS Resolution Flow & System Hardening:**
   * To prevent system network resets or `systemd-resolved` from overwriting DNS settings, `systemd-resolved` is stopped and disabled across all Pi nodes.
   * Static public DNS servers (`1.1.1.1` and `8.8.8.8`) are explicitly written into `/etc/resolv.conf`.
   * The file is locked using the immutable attribute (`chattr +i /etc/resolv.conf`), preventing any process or DHCP client from overwriting DNS configuration.
   * DNS queries travel directly from the Pi over the `10.42.0.219` gateway out to public upstream resolvers (`1.1.1.1`/`8.8.8.8`), preventing `ErrImagePull` timeouts.

---

## Repository Structure & Script Reference

```
.
├── join-cluster.sh                   # Fetches a fresh join token from master and joins worker node
├── master-node-install.sh            # Provisions K8s v1.36, containerd, and Calico on master node
├── merge-p1-master-kubeconfig.sh     # Merges cluster kubeconfig into local laptop kubectl context
├── minion-node-install.sh            # Provisions K8s v1.36 and containerd runtime on worker nodes
├── README.md                         # Project documentation
├── observability/
│   └── deploy-monitoring.sh          # Deploys/upgrades Prometheus & Grafana stack via Helm
└── raspi-connectivity/
    ├── enable-laptop-sharing.sh      # Enables IP forwarding & NAT masquerading on management laptop
    ├── enable-raspi-connectivity.sh  # Sets persistent Netplan routes & immutable DNS on Pi nodes
    └── get-laptop-ethernet-ip.sh     # Inspects and outputs the management laptop's Ethernet IP
```

### Detailed Script Breakdown

#### Root Directory

1. **`master-node-install.sh`**
   * **Purpose**: Fully initializes a Kubernetes v1.36 control plane node.
   * **What it does**: Disables swap, loads `br_netfilter` and `overlay` kernel modules, configures `net.ipv4.ip_forward = 1`, installs `containerd` with `SystemdCgroup = true`, installs `kubelet`, `kubeadm`, and `kubectl` (v1.36), initializes the cluster with `kubeadm init`, configures local `kubeconfig`, and applies the Tigera Operator for Calico CNI (`10.244.0.0/16`).

2. **`minion-node-install.sh`**
   * **Purpose**: Prepares a worker (minion) node to join the cluster.
   * **What it does**: Applies identical kernel module, sysctl, swap, and runtime (`containerd` + K8s v1.36 binaries) configurations as the master node, enabling `kubelet` so it is ready to receive a `kubeadm join` command.

3. **`join-cluster.sh`**
   * **Purpose**: Automates adding a worker node to an existing cluster.
   * **What it does**: Takes the master node IP/hostname and username as arguments, SSHs into the master node to generate a fresh `kubeadm token create --print-join-command`, and executes the returned command locally on the worker node.

4. **`merge-p1-master-kubeconfig.sh`**
   * **Purpose**: Integrates the remote cluster config into your local laptop environment.
   * **What it does**: Securely copies `/etc/kubernetes/admin.conf` from `p1-master.local`, updates the API server endpoint from `127.0.0.1` to `p1-master.local:6443`, safely flattens and merges the configuration with existing contexts in `~/.kube/config`, and sets `kubernetes-admin@kubernetes` as the active context.

#### `observability/`

5. **`observability/deploy-monitoring.sh`**
   * **Purpose**: Automates the deployment of the Prometheus and Grafana monitoring stack.
   * **What it does**: Validates and increases host `fs.inotify.max_user_watches` (to `524288`) and `max_user_instances` (to `512`), verifies or upgrades the local Helm CLI binary (v3.14.0+), prompts the operator for interactive confirmation of the active `kubectl` context, creates the `monitoring` namespace, and deploys/upgrades `kube-prometheus-stack` via Helm.

#### `raspi-connectivity/`

6. **`raspi-connectivity/enable-laptop-sharing.sh`**
   * **Purpose**: Transforms the management laptop (`t800`) into an internet gateway for the Pi cluster.
   * **What it does**: Automatically detects active outbound Wi-Fi and inbound Ethernet interfaces, enables IPv4 forwarding (`net.ipv4.ip_forward=1`), and sets up `iptables` NAT masquerading rules.

7. **`raspi-connectivity/enable-raspi-connectivity.sh`**
   * **Purpose**: Ensures persistent outbound network routing and DNS stability on Raspberry Pi nodes.
   * **What it does**: Configures an immediate default route via the laptop gateway IP, dynamically generates a declarative Netplan configuration (`/etc/netplan/01-netcfg.yaml`) to persist routing across interface resets/reboots, disables `systemd-resolved`, and locks `/etc/resolv.conf` with `chattr +i` to prevent DNS resolution timeouts.

8. **`raspi-connectivity/get-laptop-ethernet-ip.sh`**
   * **Purpose**: Quick utility to inspect the gateway IP address.
   * **What it does**: Scans network interfaces starting with `eth` or `en` and prints the currently assigned IPv4 address.

---

## Step-by-Step Deployment Guide

### Phase 1: Gateway & Network Sharing (Laptop `t800`)

1. Connect your laptop to Wi-Fi (internet) and connect your Raspberry Pi cluster to the laptop via an Ethernet switch.
2. Run the internet sharing script on `t800`:
   ```bash
   ./raspi-connectivity/enable-laptop-sharing.sh
   ```
3. Note the Ethernet IP output by the script (e.g., `10.42.0.219`).

---

### Phase 2: Persistent Connectivity & DNS Hardening (Pi Nodes)

Run `enable-raspi-connectivity.sh` on each Pi node (`p1-master`, `p2-minion`, `p3-minion`). This ensures that image pulls from container registries (`ghcr.io`, `docker.io`) never fail due to DNS or routing drops.

```bash
# SSH into each node and execute:
./raspi-connectivity/enable-raspi-connectivity.sh
```

---

### Phase 3: Control Plane Provisioning (`p1-master`)

1. Copy `master-node-install.sh` to the master node:
   ```bash
   scp master-node-install.sh morne@p1-master.local:~/
   ```
2. SSH into `p1-master` and execute the installer:
   ```bash
   ssh morne@p1-master.local
   ./master-node-install.sh
   ```
3. Save the `kubeadm join` command output at the end of the script execution for manual reference if needed.

---

### Phase 4: Worker Node Provisioning & Joining (`p2-minion`, `p3-minion`)

1. Provision worker dependencies on each minion node:
   ```bash
   scp minion-node-install.sh morne@p2-minion.local:~/
   ssh morne@p2-minion.local "./minion-node-install.sh"
   ```
2. Join the worker node to the cluster using `join-cluster.sh`:
   ```bash
   # Run on the worker node:
   ./join-cluster.sh p1-master.local morne
   ```
3. Verify all nodes are in `Ready` state from `p1-master`:
   ```bash
   kubectl get nodes
   ```

---

### Phase 5: Remote Cluster Management (`t800`)

From your laptop (`t800`), merge the cluster configuration so you can control the cluster using `kubectl`:

```bash
./merge-p1-master-kubeconfig.sh
```

Verify connectivity from `t800`:
```bash
kubectl get nodes
```

---

### Phase 6: Observability Stack Deployment

Deploy the Prometheus, Grafana, and Alertmanager stack from `t800`:

```bash
./observability/deploy-monitoring.sh
```

During execution, the script will display:
```
======================================================
 ATTENTION: KUBERNETES CONTEXT CONFIRMATION
======================================================
 Active Context : kubernetes-admin@kubernetes
 Target Cluster : kubernetes
======================================================
```
Press `Y` to confirm and proceed with deployment.

---

## Key System Safeguards & Idempotency

* **Immutable DNS Protection**: Ubuntu's `systemd-resolved` frequently overwrites static nameservers during link updates. Using `chattr +i /etc/resolv.conf` guarantees that fallback DNS servers (`1.1.1.1`, `8.8.8.8`) remain locked and functional across all cluster nodes.
* **Declarative Netplan Persistence**: Instead of relying solely on transient runtime routes (`ip route add`), network configurations are written directly to `/etc/netplan/01-netcfg.yaml`, ensuring that default routes via the gateway survive interface flaps and system reboots.
* **Interactive Guardrails**: `deploy-monitoring.sh` validates the active `kubectl` context before applying Helm charts, preventing accidental deployments to local developer clusters (such as Kind or Minikube).
* **System Resource Tuning**: Automated adjustment of `fs.inotify.max_user_watches` prevents Prometheus exporter pods from running out of file watch descriptors.
