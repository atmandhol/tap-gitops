#!/usr/bin/env bash
#
# Master setup script for TAP GitOps installation with Vault and Kind
# This script orchestrates the complete setup process
#

set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-tap-iterate}"
VAULT_CONTAINER_NAME="${VAULT_CONTAINER_NAME:-vault-tap}"

function usage() {
  cat << EOF
$0 :: Complete TAP GitOps setup with Vault and Kind

This script performs the following steps:
1. Start Vault container
2. Create kind cluster
3. Install cluster essentials (kapp-controller, secretgen-controller)
4. Test network connectivity
5. Configure Vault (K8s auth, policies, roles)
6. Populate Vault with secrets
7. Apply Kubernetes RBAC
8. Configure Tanzu Sync
9. Bootstrap and deploy Tanzu Sync

Required Environment Variables:
- INSTALL_REGISTRY_USERNAME -- Username for VMware Tanzu Network registry
- INSTALL_REGISTRY_PASSWORD -- Password for VMware Tanzu Network registry

Optional Environment Variables:
- CLUSTER_NAME -- Cluster name (default: tap-iterate)
- VAULT_CONTAINER_NAME -- Vault container name (default: vault-tap)
- VAULT_TOKEN -- Vault root token (default: root-token for dev mode)
- TAP_VERSION -- TAP version (default: 1.12.6-build.13)
- TAP_PKGR_REPO -- TAP package repository OCI URL (default: registry.tanzu.vmware.com/tanzu-application-platform/tap-packages)
- INSTALL_REGISTRY_HOSTNAME -- Registry hostname for bootstrap and Vault secrets (default: registry.tanzu.vmware.com)
- TAP_VALUES_FILE -- Path to TAP non-sensitive values YAML file (optional)
- TAP_SENSITIVE_VALUES_FILE -- Path to TAP sensitive values file (optional)
- GIT_USERNAME -- Git username for Tanzu Sync (optional)
- GIT_PASSWORD -- Git password for Tanzu Sync (optional)
- SKIP_VAULT_SETUP -- Skip Vault container setup if already running
- SKIP_KIND_SETUP -- Skip kind cluster creation if already exists

EOF
}

# Parse arguments
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

TAP_VERSION="${TAP_VERSION:-1.12.6-build.13}"
TAP_PKGR_REPO="${TAP_PKGR_REPO:-registry.tanzu.vmware.com/tanzu-application-platform/tap-packages}"

echo "=========================================="
echo "TAP GitOps Setup with Vault and Kind"
echo "=========================================="
echo "Cluster Name: ${CLUSTER_NAME}"
echo "TAP Version: ${TAP_VERSION}"
echo "TAP Package Repository: ${TAP_PKGR_REPO}"
echo ""

cd "${PROJECT_ROOT}/clusters/${CLUSTER_NAME}"

# Step 1: Start Vault container
if [[ "${SKIP_VAULT_SETUP:-false}" != "true" ]]; then
  echo "Step 1: Starting Vault container..."
  "${SCRIPT_DIR}/setup-vault.sh"
  echo ""
else
  echo "Step 1: Skipping Vault setup (SKIP_VAULT_SETUP=true)"
  echo ""
fi

# Determine Vault address for access from host (for Vault CLI)
# On macOS with Colima, kind can access via host.docker.internal
if [[ "$(uname)" == "Darwin" ]]; then
  VAULT_ADDR="http://localhost:8200"
  VAULT_ADDR_FOR_KIND="http://host.docker.internal:8200"
else
  # On Linux, try container IP or host IP
  VAULT_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${VAULT_CONTAINER_NAME}" 2>/dev/null || echo "")
  if [ -n "${VAULT_IP}" ]; then
    VAULT_ADDR="http://${VAULT_IP}:8200"
  else
    VAULT_ADDR="http://localhost:8200"
  fi
  HOST_IP=$(docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "172.17.0.1")
  VAULT_ADDR_FOR_KIND="http://${HOST_IP}:8200"
fi

VAULT_TOKEN="${VAULT_TOKEN:-root-token}"

export VAULT_ADDR
export VAULT_TOKEN
export CLUSTER_NAME
export TAP_PKGR_REPO
export INSTALL_REGISTRY_HOSTNAME

echo "Vault address for host: ${VAULT_ADDR}"
echo "Vault address for kind: ${VAULT_ADDR_FOR_KIND}"

# Step 2: Create kind cluster
if [[ "${SKIP_KIND_SETUP:-false}" != "true" ]]; then
  echo "Step 2: Creating kind cluster..."
  "${SCRIPT_DIR}/create-kind-cluster.sh"
  echo ""
  
  # Set kubectl context
  kubectl config use-context "kind-${CLUSTER_NAME}" || true
  
  # Step 2.1: Install cluster essentials
  echo "Step 2.1: Installing TAP cluster essentials..."
  if command -v tappr &> /dev/null; then
    echo "Running: tappr tap install-cluster-essentials"
    tappr tap install-cluster-essentials
    if [ $? -eq 0 ]; then
      echo "✓ Cluster essentials installed successfully"
    else
      echo "Warning: Cluster essentials installation failed or may have already been installed"
    fi
  else
    echo "Warning: tappr command not found. Skipping cluster essentials installation."
    echo "Install tappr or run manually: tappr tap install-cluster-essentials"
  fi
  echo ""
else
  echo "Step 2: Skipping kind cluster setup (SKIP_KIND_SETUP=true)"
  echo ""
  # Set kubectl context even if skipping setup
  kubectl config use-context "kind-${CLUSTER_NAME}" || true
fi

# Step 3: Test network connectivity
echo "Step 3: Testing network connectivity..."
"${SCRIPT_DIR}/vault-network-test.sh"
echo ""

# Step 4: Configure Vault Kubernetes authentication
echo "Step 4: Configuring Vault Kubernetes authentication..."
echo "Using Vault address: ${VAULT_ADDR} (for Vault CLI)"
export VAULT_ADDR="${VAULT_ADDR}"  # Use host-accessible address for Vault CLI
tanzu-sync/scripts/setup/create-kubernetes-auth.sh
echo ""

# Step 5: Create Vault policies
echo "Step 5: Creating Vault policies..."
tanzu-sync/scripts/setup/create-policies.sh
echo ""

# Step 6: Create Vault roles
echo "Step 6: Creating Vault roles..."
tanzu-sync/scripts/setup/create-roles.sh
echo ""

# Step 7: Populate Vault with secrets
echo "Step 7: Populating Vault with secrets..."
"${SCRIPT_DIR}/setup-vault-secrets.sh"
echo ""

# Step 8: Apply Kubernetes RBAC
echo "Step 8: Applying Kubernetes RBAC resources..."
# Ensure namespaces exist first (they're included in the YAML files, but apply in order)
kubectl apply -f tanzu-sync/bootstrap/vault-rbac-tanzu-sync.yaml
if [ $? -ne 0 ]; then
  echo "Warning: Failed to apply tanzu-sync RBAC. Creating namespace first..."
  kubectl create namespace tanzu-sync 2>/dev/null || true
  kubectl apply -f tanzu-sync/bootstrap/vault-rbac-tanzu-sync.yaml
fi
kubectl apply -f tanzu-sync/bootstrap/vault-rbac-tap-install.yaml
echo ""

# Step 9: Configure Tanzu Sync
echo "Step 9: Configuring Tanzu Sync..."
if [ ! -f tanzu-sync/app/values/tanzu-sync.yaml ]; then
  echo "Running configure.sh with TAP_PKGR_REPO=${TAP_PKGR_REPO}..."
  if ! tanzu-sync/scripts/configure.sh; then
    echo "Warning: configure.sh failed. This may be due to missing git remote configuration."
    echo "You may need to configure git remote or run configure.sh manually."
  fi
else
  echo "tanzu-sync.yaml already exists. To reconfigure, delete it first or set TAP_PKGR_REPO and run configure.sh manually."
fi

# Update TAP version
echo "Updating TAP version to ${TAP_VERSION}..."
"${SCRIPT_DIR}/update-tap-version.sh"
echo ""

# Configure TAP values if provided
if [ -n "${TAP_VALUES_FILE:-}" ] && [ -f "${TAP_VALUES_FILE}" ]; then
  echo "Configuring TAP values from: ${TAP_VALUES_FILE}..."
  "${SCRIPT_DIR}/configure-tap-values.sh" -f "${TAP_VALUES_FILE}"
  echo ""
fi

# Configure secrets
echo "Configuring Vault secrets..."
echo "Note: ESO will use ${VAULT_ADDR_FOR_KIND} to access Vault from kind cluster"
# Temporarily set VAULT_ADDR to the kind-accessible address for configure-secrets.sh
# This ensures the SecretStore is configured with the correct address
export VAULT_ADDR="${VAULT_ADDR_FOR_KIND}"
tanzu-sync/scripts/configure-secrets.sh
# Restore host-accessible address for subsequent Vault CLI operations
export VAULT_ADDR="http://localhost:8200"
echo ""

# Step 10: Bootstrap Tanzu Sync
echo "Step 10: Bootstrapping Tanzu Sync..."
if [ -z "${INSTALL_REGISTRY_USERNAME:-}" ] || [ -z "${INSTALL_REGISTRY_PASSWORD:-}" ]; then
  echo "Warning: INSTALL_REGISTRY_USERNAME and INSTALL_REGISTRY_PASSWORD not set"
  echo "Skipping bootstrap. You'll need to run it manually:"
  echo "  INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com \\"
  echo "  INSTALL_REGISTRY_USERNAME=<username> \\"
  echo "  INSTALL_REGISTRY_PASSWORD=<password> \\"
  echo "  tanzu-sync/scripts/bootstrap.sh"
else
  INSTALL_REGISTRY_HOSTNAME="${INSTALL_REGISTRY_HOSTNAME:-registry.tanzu.vmware.com}" \
    tanzu-sync/scripts/bootstrap.sh
fi
echo ""

# Step 11: Deploy Tanzu Sync
echo "Step 11: Deploying Tanzu Sync..."
echo "Note: This step requires kapp and ytt to be installed"
echo "Run manually: cd clusters/${CLUSTER_NAME} && tanzu-sync/scripts/deploy.sh"
echo ""

echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Verify Vault connectivity:"
echo "   export VAULT_ADDR=\"${VAULT_ADDR}\""
echo "   export VAULT_TOKEN=\"${VAULT_TOKEN}\""
echo "   vault status"
echo ""
echo "2. Deploy Tanzu Sync:"
echo "   cd clusters/${CLUSTER_NAME}"
echo "   tanzu-sync/scripts/deploy.sh"
echo ""
echo "3. Monitor TAP installation:"
echo "   kubectl get packageinstall -n tap-install"
echo "   kubectl get pods -n tanzu-sync"
echo ""
echo "4. Check External Secrets:"
echo "   kubectl get externalsecret -n tanzu-sync"
echo "   kubectl get externalsecret -n tap-install"
echo ""

