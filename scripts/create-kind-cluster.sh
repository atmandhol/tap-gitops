#!/usr/bin/env bash
#
# Create kind cluster for TAP installation
# Configures cluster to access Vault container on Docker network
#

set -o errexit -o nounset -o pipefail

CLUSTER_NAME="${CLUSTER_NAME:-tap-iterate}"
KIND_CONFIG_FILE="${KIND_CONFIG_FILE:-kind-config.yaml}"

function usage() {
  cat << EOF
$0 :: Create kind cluster for TAP installation

Environment Variables:
- CLUSTER_NAME -- Name of the kind cluster (default: tap-iterate)
- KIND_CONFIG_FILE -- Path to kind config file (default: kind-config.yaml)

EOF
}

# Check if kind is installed
if ! command -v kind &> /dev/null; then
  echo "Error: kind is not installed"
  echo "Install with: brew install kind (on macOS) or see https://kind.sigs.k8s.io/docs/user/quick-start/"
  exit 1
fi

# Check if cluster already exists
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Kind cluster '${CLUSTER_NAME}' already exists."
  echo "To delete and recreate, run: kind delete cluster --name ${CLUSTER_NAME}"
  exit 0
fi

# Create kind config if it doesn't exist
if [ ! -f "${KIND_CONFIG_FILE}" ]; then
  echo "Creating kind configuration file: ${KIND_CONFIG_FILE}"
  cat > "${KIND_CONFIG_FILE}" << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: tap-iterate
networking:
  # Allow access to Docker network
  apiServerAddress: "127.0.0.1"
  apiServerPort: 6443
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
  echo "Created ${KIND_CONFIG_FILE}"
fi

echo "Creating kind cluster '${CLUSTER_NAME}'..."
kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG_FILE}"

echo ""
echo "Kind cluster created successfully!"
echo "Cluster name: ${CLUSTER_NAME}"
echo ""
echo "To use this cluster, run:"
echo "  kubectl cluster-info --context kind-${CLUSTER_NAME}"
echo ""
echo "To set as default context:"
echo "  kubectl config use-context kind-${CLUSTER_NAME}"

