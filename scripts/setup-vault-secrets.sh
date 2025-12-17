#!/usr/bin/env bash
#
# Populate Vault with required secrets for TAP installation
# This script stores registry credentials and TAP sensitive values in Vault
#

set -o errexit -o nounset -o pipefail

CLUSTER_NAME="${CLUSTER_NAME:-tap-iterate}"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root-token}"

function usage() {
  cat << EOF
$0 :: Populate Vault with TAP secrets

Required Environment Variables:
- INSTALL_REGISTRY_USERNAME -- Username for VMware Tanzu Network registry
- INSTALL_REGISTRY_PASSWORD -- Password for VMware Tanzu Network registry
- INSTALL_REGISTRY_HOSTNAME -- Registry hostname (default: registry.tanzu.vmware.com)

Optional Environment Variables:
- CLUSTER_NAME -- Cluster name (default: tap-iterate)
- VAULT_ADDR -- Vault server address (default: http://localhost:8200)
- VAULT_TOKEN -- Vault token (default: root-token)
- TAP_SENSITIVE_VALUES_FILE -- Path to TAP sensitive values YAML file (optional)

EOF
}

error_msg="Expected env var to be set, but was not."
: "${INSTALL_REGISTRY_USERNAME?$error_msg}"
: "${INSTALL_REGISTRY_PASSWORD?$error_msg}"

INSTALL_REGISTRY_HOSTNAME="${INSTALL_REGISTRY_HOSTNAME:-registry.tanzu.vmware.com}"

# Check if vault CLI is available
if ! command -v vault &> /dev/null; then
  echo "Warning: vault CLI not found. Using curl to interact with Vault API."
  USE_CURL=true
else
  USE_CURL=false
  export VAULT_ADDR
  export VAULT_TOKEN
fi

echo "Populating Vault secrets for cluster: ${CLUSTER_NAME}"
echo "Vault Address: ${VAULT_ADDR}"
echo ""

# Create Docker config JSON for registry credentials
# Check if jq is available, otherwise create JSON manually
if command -v jq &> /dev/null; then
  DOCKER_CONFIG_JSON=$(cat <<EOF | jq -c .
{
  "auths": {
    "${INSTALL_REGISTRY_HOSTNAME}": {
      "username": "${INSTALL_REGISTRY_USERNAME}",
      "password": "${INSTALL_REGISTRY_PASSWORD}",
      "auth": "$(echo -n "${INSTALL_REGISTRY_USERNAME}:${INSTALL_REGISTRY_PASSWORD}" | base64)"
    }
  }
}
EOF
)
else
  # Create JSON manually if jq is not available
  AUTH_STRING=$(echo -n "${INSTALL_REGISTRY_USERNAME}:${INSTALL_REGISTRY_PASSWORD}" | base64)
  DOCKER_CONFIG_JSON="{\"auths\":{\"${INSTALL_REGISTRY_HOSTNAME}\":{\"username\":\"${INSTALL_REGISTRY_USERNAME}\",\"password\":\"${INSTALL_REGISTRY_PASSWORD}\",\"auth\":\"${AUTH_STRING}\"}}}"
fi

# Store registry credentials
TANZU_SYNC_SECRET_PATH="secret/data/dev/${CLUSTER_NAME}/tanzu-sync/install-registry-dockerconfig"
echo "Storing registry credentials at: ${TANZU_SYNC_SECRET_PATH}"

if [ "$USE_CURL" = true ]; then
  curl -s \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --header "Content-Type: application/json" \
    --request POST \
    --data "{\"data\":{\"dockerconfigjson\":${DOCKER_CONFIG_JSON}}}" \
    "${VAULT_ADDR}/v1/${TANZU_SYNC_SECRET_PATH}" > /dev/null
else
  vault kv put "${TANZU_SYNC_SECRET_PATH}" \
    dockerconfigjson="${DOCKER_CONFIG_JSON}"
fi

if [ $? -eq 0 ]; then
  echo "✓ Registry credentials stored successfully"
else
  echo "✗ Failed to store registry credentials"
  exit 1
fi

# Store TAP sensitive values
# Per official TAP docs: Create an empty secret initially if not provided
TAP_SECRET_PATH="secret/data/dev/${CLUSTER_NAME}/tap/sensitive-values.yaml"
echo ""

if [ -n "${TAP_SENSITIVE_VALUES_FILE:-}" ] && [ -f "${TAP_SENSITIVE_VALUES_FILE}" ]; then
  echo "Storing TAP sensitive values at: ${TAP_SECRET_PATH}"
  
  SENSITIVE_VALUES_CONTENT=$(cat "${TAP_SENSITIVE_VALUES_FILE}")
  
  if [ "$USE_CURL" = true ]; then
    # Escape JSON properly
    if command -v jq &> /dev/null; then
      ESCAPED_CONTENT=$(echo "${SENSITIVE_VALUES_CONTENT}" | jq -Rs .)
    else
      # Manual JSON escaping (basic)
      ESCAPED_CONTENT=$(echo "${SENSITIVE_VALUES_CONTENT}" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
      ESCAPED_CONTENT="\"${ESCAPED_CONTENT}\""
    fi
    curl -s \
      --header "X-Vault-Token: ${VAULT_TOKEN}" \
      --header "Content-Type: application/json" \
      --request POST \
      --data "{\"data\":{\"sensitive_tap_values_yaml\":${ESCAPED_CONTENT}}}" \
      "${VAULT_ADDR}/v1/${TAP_SECRET_PATH}" > /dev/null
  else
    vault kv put "${TAP_SECRET_PATH}" \
      sensitive_tap_values_yaml="${SENSITIVE_VALUES_CONTENT}"
  fi
  
  if [ $? -eq 0 ]; then
    echo "✓ TAP sensitive values stored successfully"
  else
    echo "✗ Failed to store TAP sensitive values"
    exit 1
  fi
else
  # Create empty secret per official TAP documentation
  # Vault does not support storing YAML files directly - must be key-value format
  echo "Creating initial empty TAP sensitive values secret at: ${TAP_SECRET_PATH}"
  echo "  (You can edit this later with your sensitive values)"
  
  EMPTY_YAML="---\n# this document is intentionally initially blank.\n"
  
  if [ "$USE_CURL" = true ]; then
    if command -v jq &> /dev/null; then
      ESCAPED_CONTENT=$(echo -e "${EMPTY_YAML}" | jq -Rs .)
    else
      ESCAPED_CONTENT=$(echo -e "${EMPTY_YAML}" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
      ESCAPED_CONTENT="\"${ESCAPED_CONTENT}\""
    fi
    curl -s \
      --header "X-Vault-Token: ${VAULT_TOKEN}" \
      --header "Content-Type: application/json" \
      --request POST \
      --data "{\"data\":{\"sensitive_tap_values_yaml\":${ESCAPED_CONTENT}}}" \
      "${VAULT_ADDR}/v1/${TAP_SECRET_PATH}" > /dev/null
  else
    # Use printf to match official TAP docs format exactly
    # Per: https://techdocs.broadcom.com/us/en/vmware-tanzu/standalone-components/tanzu-application-platform/1-12/tap/install-gitops-eso-hashicorp-vault.html
    printf '%s\n' "$(cat <<EOF
---
# this document is intentionally initially blank.
EOF
)" | vault kv put "${TAP_SECRET_PATH}" sensitive_tap_values_yaml=-
  fi
  
  if [ $? -eq 0 ]; then
    echo "✓ Empty TAP sensitive values secret created"
    echo "  You can update it later with:"
    echo "    vault kv put ${TAP_SECRET_PATH} sensitive_tap_values_yaml=\"\$(cat tap-sensitive-values.yaml)\""
  else
    echo "✗ Failed to create empty TAP sensitive values secret"
    exit 1
  fi
fi

# Store Git credentials if provided (for Tanzu Sync)
if [ -n "${GIT_USERNAME:-}" ] && [ -n "${GIT_PASSWORD:-}" ]; then
  GIT_SECRET_PATH="secret/data/dev/${CLUSTER_NAME}/tanzu-sync/git-credentials"
  echo ""
  echo "Storing Git credentials at: ${GIT_SECRET_PATH}"
  
  if [ "$USE_CURL" = true ]; then
    curl -s \
      --header "X-Vault-Token: ${VAULT_TOKEN}" \
      --header "Content-Type: application/json" \
      --request POST \
      --data "{\"data\":{\"username\":\"${GIT_USERNAME}\",\"password\":\"${GIT_PASSWORD}\"}}" \
      "${VAULT_ADDR}/v1/${GIT_SECRET_PATH}" > /dev/null
  else
    vault kv put "${GIT_SECRET_PATH}" \
      username="${GIT_USERNAME}" \
      password="${GIT_PASSWORD}"
  fi
  
  if [ $? -eq 0 ]; then
    echo "✓ Git credentials stored successfully"
  else
    echo "✗ Failed to store Git credentials"
    exit 1
  fi
fi

echo ""
echo "✓ All secrets stored in Vault successfully!"
echo ""
echo "Secret paths:"
echo "  - Registry: secret/data/dev/${CLUSTER_NAME}/tanzu-sync/install-registry-dockerconfig"
echo "  - TAP Values: secret/data/dev/${CLUSTER_NAME}/tap/sensitive-values.yaml"
if [ -n "${GIT_USERNAME:-}" ] && [ -n "${GIT_PASSWORD:-}" ]; then
  echo "  - Git Credentials: secret/data/dev/${CLUSTER_NAME}/tanzu-sync/git-credentials"
fi
echo ""
echo "Note: Per official TAP documentation, Vault does not support storing YAML files directly."
echo "      Sensitive values are stored as key-value pairs where the key is 'sensitive_tap_values_yaml'"
echo "      and the value is the YAML content as a string."

