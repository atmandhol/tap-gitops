#!/usr/bin/env bash
#
# Update TAP version in configuration files
#

set -o errexit -o nounset -o pipefail

CLUSTER_NAME="${CLUSTER_NAME:-tap-iterate}"
TAP_VERSION="${TAP_VERSION:-1.12.6-build.13}"

function usage() {
  cat << EOF
$0 :: Update TAP version in configuration

Environment Variables:
- CLUSTER_NAME -- Cluster name (default: tap-iterate)
- TAP_VERSION -- TAP version to set (default: 1.12.6-build.13)

EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLUSTER_DIR="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}"

if [ ! -d "${CLUSTER_DIR}" ]; then
  echo "Error: Cluster directory not found: ${CLUSTER_DIR}"
  exit 1
fi

cd "${CLUSTER_DIR}"

echo "Updating TAP version to ${TAP_VERSION} for cluster ${CLUSTER_NAME}..."

# Update tanzu-sync values if the file exists
if [ -f tanzu-sync/app/values/tanzu-sync.yaml ]; then
  echo "Updating tanzu-sync/app/values/tanzu-sync.yaml..."
  
  # Check if tap_install section exists
  if grep -q "tap_install:" tanzu-sync/app/values/tanzu-sync.yaml; then
    # Update existing version
    if command -v yq &> /dev/null; then
      yq eval ".tap_install.version.package_repo_bundle_tag = \"${TAP_VERSION}\"" -i tanzu-sync/app/values/tanzu-sync.yaml
      yq eval ".tap_install.version.package_version = \"${TAP_VERSION}\"" -i tanzu-sync/app/values/tanzu-sync.yaml
    else
      # Manual update using sed
      sed -i.bak "s/package_repo_bundle_tag:.*/package_repo_bundle_tag: \"${TAP_VERSION}\"/" tanzu-sync/app/values/tanzu-sync.yaml
      sed -i.bak "s/package_version:.*/package_version: \"${TAP_VERSION}\"/" tanzu-sync/app/values/tanzu-sync.yaml
      rm -f tanzu-sync/app/values/tanzu-sync.yaml.bak
    fi
  else
    # Add tap_install section
    cat >> tanzu-sync/app/values/tanzu-sync.yaml << EOF
tap_install:
  version:
    package_repo_bundle_tag: "${TAP_VERSION}"
    package_version: "${TAP_VERSION}"
EOF
  fi
  echo "✓ Updated tanzu-sync/app/values/tanzu-sync.yaml"
else
  echo "Note: tanzu-sync/app/values/tanzu-sync.yaml not found. Run configure.sh first."
fi

# Update tap-install values if the file exists
if [ -f cluster-config/values/tap-install-values.yaml ]; then
  echo "Updating cluster-config/values/tap-install-values.yaml..."
  
  if command -v yq &> /dev/null; then
    yq eval ".tap_install.version.package_repo_bundle_tag = \"${TAP_VERSION}\"" -i cluster-config/values/tap-install-values.yaml 2>/dev/null || true
    yq eval ".tap_install.version.package_version = \"${TAP_VERSION}\"" -i cluster-config/values/tap-install-values.yaml 2>/dev/null || true
  else
    # Manual update
    if grep -q "tap_install:" cluster-config/values/tap-install-values.yaml; then
      if ! grep -q "version:" cluster-config/values/tap-install-values.yaml; then
        # Add version section
        sed -i.bak "/tap_install:/a\\
  version:\\
    package_repo_bundle_tag: \"${TAP_VERSION}\"\\
    package_version: \"${TAP_VERSION}\"
" cluster-config/values/tap-install-values.yaml
        rm -f cluster-config/values/tap-install-values.yaml.bak
      else
        sed -i.bak "s/package_repo_bundle_tag:.*/package_repo_bundle_tag: \"${TAP_VERSION}\"/" cluster-config/values/tap-install-values.yaml
        sed -i.bak "s/package_version:.*/package_version: \"${TAP_VERSION}\"/" cluster-config/values/tap-install-values.yaml
        rm -f cluster-config/values/tap-install-values.yaml.bak
      fi
    fi
  fi
  echo "✓ Updated cluster-config/values/tap-install-values.yaml"
fi

echo ""
echo "✓ TAP version updated to ${TAP_VERSION}"
echo ""
echo "Note: The version.yaml file in cluster-config/config/tap-install/.tanzu-managed/"
echo "      should not be modified directly. Version is controlled via values files."

