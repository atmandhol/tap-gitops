#!/usr/bin/env bash
#
# Master cleanup script for TAP GitOps installation
# This script cleans up Vault, kind cluster, and optionally configuration files
#

set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-tap-iterate}"
VAULT_CONTAINER_NAME="${VAULT_CONTAINER_NAME:-vault-tap}"
REMOVE_CONFIG="${REMOVE_CONFIG:-false}"
REMOVE_VAULT_DATA="${REMOVE_VAULT_DATA:-false}"

function usage() {
  cat << EOF
$0 :: Complete cleanup of TAP GitOps setup

This script performs the following cleanup steps:
1. Delete kind cluster
2. Stop and remove Vault container
3. Optionally remove Vault data
4. Optionally remove generated configuration files

Environment Variables:
- CLUSTER_NAME -- Cluster name (default: tap-iterate)
- VAULT_CONTAINER_NAME -- Vault container name (default: vault-tap)
- REMOVE_CONFIG -- Set to 'true' to remove generated config files (default: false)
- REMOVE_VAULT_DATA -- Set to 'true' to remove Vault data directory (default: false)

Options:
  --remove-config    Remove generated configuration files
  --remove-vault-data Remove Vault data directory
  --all              Remove everything including config and data
  --help             Show this help message

EOF
}

# Parse arguments
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--all" ]]; then
  REMOVE_CONFIG=true
  REMOVE_VAULT_DATA=true
elif [[ "${1:-}" == "--remove-config" ]]; then
  REMOVE_CONFIG=true
elif [[ "${1:-}" == "--remove-vault-data" ]]; then
  REMOVE_VAULT_DATA=true
fi

echo "=========================================="
echo "TAP GitOps Cleanup"
echo "=========================================="
echo "Cluster Name: ${CLUSTER_NAME}"
echo "Vault Container: ${VAULT_CONTAINER_NAME}"
echo "Remove Config: ${REMOVE_CONFIG}"
echo "Remove Vault Data: ${REMOVE_VAULT_DATA}"
echo ""

# Step 1: Delete kind cluster
echo "Step 1: Deleting kind cluster..."
"${SCRIPT_DIR}/cleanup-kind-cluster.sh"
echo ""

# Step 2: Cleanup Vault
echo "Step 2: Cleaning up Vault container..."
if [ "${REMOVE_VAULT_DATA}" = "true" ]; then
  REMOVE_DATA=true "${SCRIPT_DIR}/cleanup-vault.sh" --remove-data
else
  "${SCRIPT_DIR}/cleanup-vault.sh"
fi
echo ""

# Step 3: Optionally remove generated configuration files
if [ "${REMOVE_CONFIG}" = "true" ]; then
  echo "Step 3: Removing generated configuration files..."
  cd "${PROJECT_ROOT}/clusters/${CLUSTER_NAME}"
  
  CONFIG_FILES=(
    "tanzu-sync/app/values/tanzu-sync.yaml"
    "tanzu-sync/app/values/tanzu-sync-vault-values.yaml"
    "cluster-config/values/tap-install-values.yaml"
    "cluster-config/values/tap-install-vault-values.yaml"
  )
  
  REMOVED_COUNT=0
  for file in "${CONFIG_FILES[@]}"; do
    if [ -f "${file}" ]; then
      echo "  Removing: ${file}"
      rm -f "${file}"
      REMOVED_COUNT=$((REMOVED_COUNT + 1))
    fi
  done
  
  if [ $REMOVED_COUNT -gt 0 ]; then
    echo "✓ Removed ${REMOVED_COUNT} configuration file(s)"
  else
    echo "No configuration files found to remove"
  fi
  echo ""
else
  echo "Step 3: Skipping configuration file removal (use --remove-config to enable)"
  echo ""
fi

# Step 4: Cleanup kubectl context
echo "Step 4: Checking kubectl contexts..."
if kubectl config get-contexts 2>/dev/null | grep -q "kind-${CLUSTER_NAME}"; then
  echo "Found kubectl context 'kind-${CLUSTER_NAME}'"
  read -p "Remove this context? (y/n): " remove_context
  if [ "$remove_context" = "y" ] || [ "$remove_context" = "Y" ]; then
    kubectl config delete-context "kind-${CLUSTER_NAME}" 2>/dev/null || true
    echo "✓ Removed kubectl context"
  fi
else
  echo "No kubectl context found for 'kind-${CLUSTER_NAME}'"
fi
echo ""

echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Kind cluster deleted"
echo "  ✓ Vault container removed"
if [ "${REMOVE_VAULT_DATA}" = "true" ]; then
  echo "  ✓ Vault data removed"
fi
if [ "${REMOVE_CONFIG}" = "true" ]; then
  echo "  ✓ Configuration files removed"
fi
echo ""
echo "To start fresh, run:"
echo "  ./scripts/setup-tap-gitops.sh"
echo ""

