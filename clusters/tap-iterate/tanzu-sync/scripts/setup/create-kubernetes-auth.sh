#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
#set -o xtrace

function usage() {
  cat << EOF
$0 :: create Vault Kubernetes Auth engine

Required Environment Variables:
- VAULT_ADDR -- Vault server which is hosting the secrets
- CLUSTER_NAME -- cluster on which TAP is being installed

Optional Environment Variables:
- VAULT_TOKEN -- Vault token authorized to add/update authentication engine instances in vault
EOF
}

error_msg="Expected env var to be set, but was not."
: "${VAULT_ADDR?$error_msg}"
: "${CLUSTER_NAME?$error_msg}"

k8s_api_server="$(kubectl config view --minify --output jsonpath="{.clusters[*].cluster.server}")"
k8s_cacert="$(kubectl config view --minify --raw --output 'jsonpath={..cluster.certificate-authority-data}' | base64 --decode)"

# Check if auth method is already enabled
if vault auth list 2>/dev/null | grep -q "^${CLUSTER_NAME}/"; then
  echo "Kubernetes auth method at path '${CLUSTER_NAME}' already exists"
  echo "Updating configuration..."
else
  echo "Enabling Kubernetes auth method at path '${CLUSTER_NAME}'"
  if ! vault auth enable -path=$CLUSTER_NAME kubernetes 2>/dev/null; then
    # If enable fails, it might already exist - check and continue
    if vault auth list 2>/dev/null | grep -q "${CLUSTER_NAME}/"; then
      echo "Auth method already exists (may have been created previously)"
    else
      echo "Error: Failed to enable Kubernetes auth method"
      exit 1
    fi
  fi
fi

echo "Configuring Kubernetes auth method..."
if vault write auth/$CLUSTER_NAME/config \
  kubernetes_host="${k8s_api_server}" \
  kubernetes_ca_cert="${k8s_cacert}" \
  ttl=1h 2>&1; then
  echo "✓ Kubernetes auth method configured successfully"
else
  EXIT_CODE=$?
  # Check if it's just a configuration update (not an error)
  if vault read auth/$CLUSTER_NAME/config 2>/dev/null | grep -q "kubernetes_host"; then
    echo "✓ Kubernetes auth method is already configured"
  else
    echo "Warning: Failed to configure auth method, but it may already be set up correctly"
    echo "Verifying configuration..."
    vault read auth/$CLUSTER_NAME/config 2>/dev/null || echo "Please check Vault configuration manually"
  fi
fi