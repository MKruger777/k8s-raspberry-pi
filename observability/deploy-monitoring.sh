#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# 1. SYSTEM HEALTH & HOST CONFIGURATION (t460)
# ------------------------------------------------------------------------------
echo "[*] Checking host system configuration..."

# A. Inotify Limits Check
CURRENT_WATCHES=$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 0)
REQUIRED_WATCHES=524288

if [ "$CURRENT_WATCHES" -lt "$REQUIRED_WATCHES" ]; then
    echo "[!] Inotify max_user_watches is low ($CURRENT_WATCHES). Adjusting to $REQUIRED_WATCHES..."
    sudo sysctl -w fs.inotify.max_user_watches=$REQUIRED_WATCHES > /dev/null
    sudo sysctl -w fs.inotify.max_user_instances=512 > /dev/null
    
    # Persist across reboots
    if [ ! -f /etc/sysctl.d/99-kubernetes.conf ]; then
        echo "fs.inotify.max_user_watches=$REQUIRED_WATCHES" | sudo tee /etc/sysctl.d/99-kubernetes.conf > /dev/null
        echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.d/99-kubernetes.conf > /dev/null
    fi
fi

echo "[+] Host system checks passed."

# ------------------------------------------------------------------------------
# 2. HELM INSTALLATION & UPGRADE CHECK
# ------------------------------------------------------------------------------
MIN_HELM_VERSION="3.14.0"

install_or_upgrade_helm() {
    echo "[*] Fetching and running official Helm installer script..."
    curl -fsSL -k https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

if command -v helm &> /dev/null; then
    CURRENT_VERSION=$(helm version --template='{{.Version}}' | sed 's/^v//')
    echo "[+] Found Helm version: v$CURRENT_VERSION"
    
    if [ "$(printf '%s\n' "$MIN_HELM_VERSION" "$CURRENT_VERSION" | sort -V | head -n1)" != "$MIN_HELM_VERSION" ]; then
        echo "[*] Helm version is older than v$MIN_HELM_VERSION. Upgrading..."
        install_or_upgrade_helm
        echo "[+] Helm upgraded to: $(helm version --short)"
    fi
else
    echo "[*] Helm not found. Installing latest stable Helm..."
    install_or_upgrade_helm
    echo "[+] Helm installed: $(helm version --short)"
fi

# ------------------------------------------------------------------------------
# 3. KUBERNETES CONTEXT VERIFICATION & CONFIRMATION
# ------------------------------------------------------------------------------
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "NONE")

if [ "$CURRENT_CONTEXT" = "NONE" ]; then
    echo "[ERROR] No active kubectl context found. Please configure kubeconfig and try again."
    exit 1
fi

CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' 2>/dev/null || echo "Unknown")

echo ""
echo "======================================================"
echo " ATTENTION: KUBERNETES CONTEXT CONFIRMATION"
echo "======================================================"
echo " Active Context : $CURRENT_CONTEXT"
echo " Target Cluster : $CLUSTER_NAME"
echo "======================================================"
echo ""

read -p "Do you want to deploy the monitoring stack to this cluster? (Y/y to proceed, any other key to abort): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "[ABORTED] Deployment cancelled by user."
    exit 0
fi

echo "[+] Context confirmed. Proceeding with deployment..."

# ------------------------------------------------------------------------------
# 4. KUBERNETES NAMESPACE CHECK
# ------------------------------------------------------------------------------
NAMESPACE="monitoring"

if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "[+] Namespace '$NAMESPACE' already exists."
else
    echo "[*] Creating namespace '$NAMESPACE'..."
    kubectl create namespace "$NAMESPACE"
fi

# ------------------------------------------------------------------------------
# 5. HELM REPOSITORY & CHART INSTALLATION
# ------------------------------------------------------------------------------
RELEASE_NAME="kube-prometheus-stack"
REPO_NAME="prometheus-community"
REPO_URL="https://prometheus-community.github.io/helm-charts"

echo "[*] Adding and updating Helm repository..."
helm repo add "$REPO_NAME" "$REPO_URL" --force-update > /dev/null
helm repo update "$REPO_NAME" > /dev/null

echo "[*] Deploying $RELEASE_NAME into '$NAMESPACE' namespace..."
helm upgrade --install "$RELEASE_NAME" "$REPO_NAME/$RELEASE_NAME" \
  --namespace "$NAMESPACE"

echo "======================================================"
echo "[SUCCESS] Monitoring stack deployment complete!"
echo "======================================================"