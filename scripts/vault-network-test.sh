#!/usr/bin/env bash
#
# Test network connectivity between kind cluster and Vault container
#

set -o nounset -o pipefail
# Note: errexit is disabled to allow fallback attempts

VAULT_CONTAINER_NAME="${VAULT_CONTAINER_NAME:-vault-tap}"
CLUSTER_NAME="${CLUSTER_NAME:-tap-iterate}"

function usage() {
  cat << EOF
$0 :: Test network connectivity between kind cluster and Vault

Environment Variables:
- VAULT_CONTAINER_NAME -- Name of Vault container (default: vault-tap)
- CLUSTER_NAME -- Name of kind cluster (default: tap-iterate)

EOF
}

# Check if Vault container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${VAULT_CONTAINER_NAME}$"; then
  echo "Error: Vault container '${VAULT_CONTAINER_NAME}' is not running"
  echo "Start it with: ./scripts/setup-vault.sh"
  exit 1
fi

# Check if kind cluster exists
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Error: Kind cluster '${CLUSTER_NAME}' does not exist"
  echo "Create it with: ./scripts/create-kind-cluster.sh"
  exit 1
fi

# Determine Vault address - try host.docker.internal first (works on macOS/Windows with Colima)
# Then fall back to container IP
if [[ "$(uname)" == "Darwin" ]]; then
  # On macOS with Colima, kind can access via host.docker.internal
  VAULT_ADDR="http://host.docker.internal:8200"
  echo "Using host.docker.internal for Vault access (macOS/Colima)"
else
  # On Linux, try to get host IP or container IP
  HOST_IP=$(docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "")
  if [ -n "${HOST_IP}" ]; then
    VAULT_ADDR="http://${HOST_IP}:8200"
    echo "Using Docker bridge gateway IP: ${HOST_IP}"
  else
    VAULT_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${VAULT_CONTAINER_NAME}")
    VAULT_ADDR="http://${VAULT_IP}:8200"
    echo "Using Vault container IP: ${VAULT_IP}"
  fi
fi

# Also get container IP for display
VAULT_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${VAULT_CONTAINER_NAME}" 2>/dev/null || echo "N/A")

echo "Testing connectivity from kind cluster to Vault..."
echo "Vault Container: ${VAULT_CONTAINER_NAME}"
echo "Vault IP: ${VAULT_IP}"
echo "Vault Address: ${VAULT_ADDR}"
echo ""

# Ensure default namespace and service account exist (kind clusters sometimes don't have them)
echo "Ensuring default namespace and service account exist..."
kubectl create namespace default 2>/dev/null || true
kubectl apply -f - <<EOF 2>/dev/null || true
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: default
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: kube-system
EOF

# Test connectivity from kind cluster using a temporary pod
echo "Creating test pod in kind cluster..."
TEST_RESULT=1

# Try with default namespace first
if kubectl run vault-connectivity-test \
  --image=curlimages/curl:latest \
  --namespace=default \
  --rm -i --restart=Never \
  --command -- sh -c "
    echo 'Testing connection to Vault at ${VAULT_ADDR}...'
    if curl -s --max-time 10 ${VAULT_ADDR}/v1/sys/health > /dev/null; then
      echo '✓ Successfully connected to Vault!'
      curl -s ${VAULT_ADDR}/v1/sys/health | head -20
      exit 0
    else
      echo '✗ Failed to connect to Vault'
      echo 'Trying to ping Vault IP...'
      ping -c 2 ${VAULT_IP} 2>/dev/null || echo 'Ping also failed'
      exit 1
    fi
  " 2>&1; then
  TEST_RESULT=0
else
  # If that failed, try in kube-system namespace
  echo "Retrying in kube-system namespace..."
  if kubectl run vault-connectivity-test \
    --image=curlimages/curl:latest \
    --namespace=kube-system \
    --rm -i --restart=Never \
    --command -- sh -c "
      echo 'Testing connection to Vault at ${VAULT_ADDR}...'
      if curl -s --max-time 10 ${VAULT_ADDR}/v1/sys/health > /dev/null; then
        echo '✓ Successfully connected to Vault!'
        curl -s ${VAULT_ADDR}/v1/sys/health | head -20
        exit 0
      else
        echo '✗ Failed to connect to Vault'
        echo 'Trying to ping Vault IP...'
        ping -c 2 ${VAULT_IP} 2>/dev/null || echo 'Ping also failed'
        exit 1
      fi
    " 2>&1; then
    TEST_RESULT=0
  fi
fi

if [ $TEST_RESULT -eq 0 ]; then
  echo ""
  echo "✓ Network connectivity test passed!"
  echo ""
  echo "Vault is accessible from kind cluster at: ${VAULT_ADDR}"
  echo ""
  echo "Set these environment variables:"
  echo "  export VAULT_ADDR=\"${VAULT_ADDR}\""
  echo "  export CLUSTER_NAME=\"${CLUSTER_NAME}\""
else
  echo ""
  echo "✗ Network connectivity test failed!"
  echo ""
  echo "The kind cluster cannot reach Vault at ${VAULT_ADDR}"
  echo ""
  echo "Troubleshooting:"
  echo "1. Ensure Vault container is running: docker ps | grep ${VAULT_CONTAINER_NAME}"
  echo "2. Check Vault container IP: docker inspect ${VAULT_CONTAINER_NAME} | grep IPAddress"
  echo "3. Try accessing Vault from host: curl http://localhost:8200/v1/sys/health"
  echo ""
  echo "Solution: Use host network mode for Vault or use host.docker.internal"
  echo "  Restart Vault with: VAULT_USE_HOST_NETWORK=true ./scripts/setup-vault.sh"
  exit 1
fi

