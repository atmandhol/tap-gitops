#!/usr/bin/env bash
#
# Configure TAP non-sensitive values
# This script allows you to provide custom TAP values that will be merged
# into the tap-install-values.yaml file
#

set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-tap-iterate}"
TAP_VALUES_FILE="${TAP_VALUES_FILE:-}"

function usage() {
  cat << EOF
$0 :: Configure TAP non-sensitive values

This script merges your custom TAP values into the tap-install-values.yaml file.
The values should be provided under the tap_install.values path.

Usage:
  $0 [OPTIONS]

Options:
  -f, --file FILE    Path to TAP values YAML file
  -h, --help         Show this help message

Environment Variables:
- CLUSTER_NAME -- Cluster name (default: tap-iterate)
- TAP_VALUES_FILE -- Path to TAP values YAML file (alternative to -f option)

Example TAP values file structure:
  tap_install:
    values:
      shared:
        ingress_domain: "example.com"
      ceip_policy_disclosed: true
      # ... other TAP configuration

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--file)
      TAP_VALUES_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

CLUSTER_DIR="${PROJECT_ROOT}/clusters/${CLUSTER_NAME}"
TAP_INSTALL_VALUES="${CLUSTER_DIR}/cluster-config/values/tap-install-values.yaml"

if [ ! -d "${CLUSTER_DIR}" ]; then
  echo "Error: Cluster directory not found: ${CLUSTER_DIR}"
  exit 1
fi

# Ensure tap-install-values.yaml exists (create minimal if not)
if [ ! -f "${TAP_INSTALL_VALUES}" ]; then
  echo "Creating initial tap-install-values.yaml..."
  mkdir -p "$(dirname "${TAP_INSTALL_VALUES}")"
  # Try to get TAP_PKGR_REPO from environment or use default
  TAP_PKGR_REPO="${TAP_PKGR_REPO:-registry.tanzu.vmware.com/tanzu-application-platform/tap-packages}"
  cat > "${TAP_INSTALL_VALUES}" << EOF
tap_install:
  package_repository:
    oci_repository: "${TAP_PKGR_REPO}"
  values: {}
EOF
fi

# If TAP_VALUES_FILE is provided, merge it
if [ -n "${TAP_VALUES_FILE}" ] && [ -f "${TAP_VALUES_FILE}" ]; then
  echo "Merging TAP values from: ${TAP_VALUES_FILE}"
  
  # Check if yq is available for merging
  if command -v yq &> /dev/null; then
    # Use yq to merge values
    echo "Using yq to merge values..."
    
    # Extract tap_install.values from the input file
    if yq eval '.tap_install.values' "${TAP_VALUES_FILE}" > /dev/null 2>&1; then
      # Merge the values section
      yq eval-all '. as \$item ireduce ({}; . *+ \$item)' \
        "${TAP_INSTALL_VALUES}" \
        <(yq eval '.tap_install.values as $vals | {"tap_install": {"values": $vals}}' "${TAP_VALUES_FILE}") \
        > "${TAP_INSTALL_VALUES}.tmp" && mv "${TAP_INSTALL_VALUES}.tmp" "${TAP_INSTALL_VALUES}"
      
      echo "✓ TAP values merged successfully"
    else
      # If no tap_install.values, assume the file contains values directly
      yq eval-all '. as \$item ireduce ({}; . *+ \$item)' \
        "${TAP_INSTALL_VALUES}" \
        <(yq eval '{"tap_install": {"values": .}}' "${TAP_VALUES_FILE}") \
        > "${TAP_INSTALL_VALUES}.tmp" && mv "${TAP_INSTALL_VALUES}.tmp" "${TAP_INSTALL_VALUES}"
      
      echo "✓ TAP values merged successfully (assumed values are at root level)"
    fi
  else
    echo "Warning: yq not found. Attempting basic merge..."
    echo ""
    echo "Please manually merge the values from ${TAP_VALUES_FILE} into:"
    echo "  ${TAP_INSTALL_VALUES}"
    echo ""
    echo "The values should be placed under tap_install.values:"
    echo ""
    cat "${TAP_VALUES_FILE}" | head -20
    echo ""
    echo "..."
    exit 1
  fi
else
  if [ -n "${TAP_VALUES_FILE}" ]; then
    echo "Error: TAP values file not found: ${TAP_VALUES_FILE}"
    exit 1
  else
    echo "No TAP values file provided."
    echo "Current tap-install-values.yaml location: ${TAP_INSTALL_VALUES}"
    echo ""
    echo "To add custom values, either:"
    echo "1. Edit the file directly: ${TAP_INSTALL_VALUES}"
    echo "2. Use this script: $0 -f /path/to/your-tap-values.yaml"
    echo ""
    echo "Example values structure:"
    cat << 'EXAMPLE'
tap_install:
  values:
    shared:
      ingress_domain: "example.com"
    ceip_policy_disclosed: true
    # ... other TAP configuration
EXAMPLE
  fi
fi

echo ""
echo "TAP values file: ${TAP_INSTALL_VALUES}"
echo "Review the file to ensure values are correct before deploying."

