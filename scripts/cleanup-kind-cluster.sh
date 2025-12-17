#!/usr/bin/env bash
#
# Cleanup kind cluster
#

set -o errexit -o nounset -o pipefail

CLUSTER_NAME="${CLUSTER_NAME:-tap-iterate}"

function usage() {
  cat << EOF
$0 :: Cleanup kind cluster

Environment Variables:
- CLUSTER_NAME -- Name of the kind cluster (default: tap-iterate)

EOF
}

# Parse arguments
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

# Check if kind is installed
if ! command -v kind &> /dev/null; then
  echo "Error: kind is not installed"
  exit 1
fi

# Check if cluster exists
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Kind cluster '${CLUSTER_NAME}' does not exist."
  exit 0
fi

echo "Deleting kind cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "${CLUSTER_NAME}"

if [ $? -eq 0 ]; then
  echo "✓ Kind cluster '${CLUSTER_NAME}' deleted successfully"
  
  # Check if kubectl context still references the cluster
  if kubectl config get-contexts | grep -q "kind-${CLUSTER_NAME}"; then
    echo ""
    echo "Note: kubectl context 'kind-${CLUSTER_NAME}' may still exist."
    echo "To remove it, run: kubectl config delete-context kind-${CLUSTER_NAME}"
  fi
else
  echo "✗ Failed to delete kind cluster"
  exit 1
fi

echo ""
echo "✓ Kind cluster cleanup complete!"

