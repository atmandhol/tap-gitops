#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
#set -o xtrace

function usage() {
  cat << EOF
$0 :: configure Tanzu Sync for use with External Secrets Operator (ESO)

Required Environment Variables:
- VAULT_ADDR -- Vault server address
- CLUSTER_NAME -- name of cluster on which TAP is being installed

Optional:
- VAULT_TOKEN -- Vault token to access server
- VAULT_NAMESPACE -- Vault enterprise namespace where secrets are stored
- VAULT_ROLE_NAME_FOR_TANZU_SYNC -- name of Vault Role (to be created) which will be used to access Tanzu Sync secrets
- VAULT_ROLE_NAME_FOR_TAP -- name of Vault Role (to be created) which will be used to access TAP sensitive values

EOF
}

error_msg="Expected env var to be set, but was not."
: "${VAULT_ADDR?$error_msg}"
: "${CLUSTER_NAME?$error_msg}"

VAULT_ROLE_NAME_FOR_TANZU_SYNC=${VAULT_ROLE_NAME_FOR_TANZU_SYNC:-${CLUSTER_NAME}--tanzu-sync-secrets}
VAULT_ROLE_NAME_FOR_TAP=${VAULT_ROLE_NAME_FOR_TAP:-${CLUSTER_NAME}--tap-install-secrets}
VAULT_NAMESPACE=${VAULT_NAMESPACE:-""}

# Check if Git URL is configured and determine auth type
GIT_URL=""
if [ -f tanzu-sync/app/values/tanzu-sync.yaml ]; then
  GIT_URL=$(grep "^  url:" tanzu-sync/app/values/tanzu-sync.yaml | awk '{print $2}' | tr -d '"' || echo "")
fi

# Determine sync_git configuration based on Git URL and available credentials
SYNC_GIT_CONFIG=""
if [ -n "${GIT_URL}" ]; then
  if [[ "${GIT_URL}" =~ ^https:// ]]; then
    # HTTPS URL - use basic_auth
    SYNC_GIT_CONFIG="      sync_git:
        basic_auth:
          username:
            key: secret/dev/${CLUSTER_NAME}/tanzu-sync/git-credentials
            property: username
          password:
            key: secret/dev/${CLUSTER_NAME}/tanzu-sync/git-credentials
            property: password"
  else
    # SSH URL - use ssh
    SYNC_GIT_CONFIG="      sync_git:
        ssh:
          private_key:
            key: secret/dev/${CLUSTER_NAME}/tanzu-sync/git-ssh
            property: privatekey
          known_hosts:
            key: secret/dev/${CLUSTER_NAME}/tanzu-sync/git-ssh
            property: knownhosts"
  fi
else
  echo "Warning: Git URL not found in tanzu-sync.yaml. Skipping sync_git configuration."
  SYNC_GIT_CONFIG="      # TODO: Configure either basic_auth (for HTTPS) or ssh (for SSH) based on your Git URL"
fi

# configure
# (see: tanzu-sync/app/config/.tanzu-managed/schema.yaml)
ts_values_path=tanzu-sync/app/values/tanzu-sync-vault-values.yaml
cat > ${ts_values_path} << EOF
---
secrets:
  eso:
    vault:
      server: ${VAULT_ADDR}
      namespace: "${VAULT_NAMESPACE}"
      auth:
        kubernetes:
          mountPath: ${CLUSTER_NAME}
          role: ${VAULT_ROLE_NAME_FOR_TANZU_SYNC}
    remote_refs:
${SYNC_GIT_CONFIG}
      install_registry_dockerconfig:
        dockerconfigjson:
          key: secret/dev/${CLUSTER_NAME}/tanzu-sync/install-registry-dockerconfig
EOF

echo "wrote ESO configuration for Tanzu Sync to: ${ts_values_path}"

tap_install_values_path=cluster-config/values/tap-install-vault-values.yaml
cat > ${tap_install_values_path} << EOF
---
tap_install:
  secrets:
    eso:
      vault:
        server: ${VAULT_ADDR}
        namespace: "${VAULT_NAMESPACE}"
        auth:
          kubernetes:
            mountPath: ${CLUSTER_NAME}
            role: ${VAULT_ROLE_NAME_FOR_TAP}
      remote_refs:
        tap_sensitive_values:
          sensitive_tap_values_yaml:
            key: secret/dev/${CLUSTER_NAME}/tap/sensitive-values.yaml
EOF

echo "wrote Vault configuration for TAP install to: ${tap_install_values_path}"
echo ""
echo "Please edit '${ts_values_path}' filling in values for each 'TODO' comment"