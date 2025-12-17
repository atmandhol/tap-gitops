#!/usr/bin/env bash
#
# Setup Vault container in Colima for TAP GitOps installation
# This script starts a Vault container that can be accessed from kind cluster
#

set -o errexit -o nounset -o pipefail

VAULT_CONTAINER_NAME="${VAULT_CONTAINER_NAME:-vault-tap}"
VAULT_PORT="${VAULT_PORT:-8200}"
VAULT_DEV_MODE="${VAULT_DEV_MODE:-true}"
VAULT_DATA_DIR="${VAULT_DATA_DIR:-./vault-data}"
VAULT_IMAGE="${VAULT_IMAGE:-hashicorp/vault:1.15.2}"
VAULT_USE_HOST_NETWORK="${VAULT_USE_HOST_NETWORK:-false}"

function usage() {
  cat << EOF
$0 :: Setup Vault container in Colima

Environment Variables:
- VAULT_CONTAINER_NAME -- Name for Vault container (default: vault-tap)
- VAULT_PORT -- Port to expose Vault on (default: 8200)
- VAULT_DEV_MODE -- Run Vault in dev mode (default: true)
- VAULT_DATA_DIR -- Directory to store Vault data (default: ./vault-data)
- VAULT_IMAGE -- Vault Docker image (default: hashicorp/vault:1.15.2)
- VAULT_USE_HOST_NETWORK -- Use host network mode for better kind access (default: false)

EOF
}

# Check if Vault container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${VAULT_CONTAINER_NAME}$"; then
  echo "Vault container '${VAULT_CONTAINER_NAME}' already exists."
  if docker ps --format '{{.Names}}' | grep -q "^${VAULT_CONTAINER_NAME}$"; then
    echo "Container is already running."
    docker ps --filter "name=${VAULT_CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    exit 0
  else
    echo "Starting existing container..."
    docker start "${VAULT_CONTAINER_NAME}"
    exit 0
  fi
fi

# Create data directory if it doesn't exist
mkdir -p "${VAULT_DATA_DIR}"

echo "Starting Vault container '${VAULT_CONTAINER_NAME}'..."

# Check if Vault image exists, pull if not
echo "Checking for Vault image: ${VAULT_IMAGE}..."
if ! docker image inspect "${VAULT_IMAGE}" &> /dev/null; then
  echo "Pulling Vault image: ${VAULT_IMAGE}..."
  if ! docker pull "${VAULT_IMAGE}"; then
    echo "Error: Failed to pull Vault image: ${VAULT_IMAGE}"
    echo "You can specify a different image with: export VAULT_IMAGE=hashicorp/vault:<version>"
    exit 1
  fi
fi

# Determine network configuration
if [ "${VAULT_USE_HOST_NETWORK}" = "true" ]; then
  NETWORK_OPT="--network host"
  VAULT_ADDR_FOR_KIND="http://localhost:8200"
  echo "Using host network mode for better kind cluster access"
else
  NETWORK_OPT="--network bridge"
  # Try to get host IP that kind can access
  # On macOS with Colima, kind can access host.docker.internal
  if [[ "$(uname)" == "Darwin" ]]; then
    VAULT_ADDR_FOR_KIND="http://host.docker.internal:8200"
    echo "Using bridge network. Kind cluster should access via host.docker.internal"
  else
    # On Linux, get the host IP from Docker network
    HOST_IP=$(docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "172.17.0.1")
    VAULT_ADDR_FOR_KIND="http://${HOST_IP}:8200"
    echo "Using bridge network. Kind cluster should access via host IP: ${HOST_IP}"
  fi
fi

if [ "${VAULT_DEV_MODE}" = "true" ]; then
  # Dev mode: auto-unsealed, in-memory storage, root token in logs
  echo "Running Vault in DEV mode (not suitable for production)"
  if [ "${VAULT_USE_HOST_NETWORK}" = "true" ]; then
    docker run -d \
      --name "${VAULT_CONTAINER_NAME}" \
      --cap-add=IPC_LOCK \
      ${NETWORK_OPT} \
      -e 'VAULT_DEV_ROOT_TOKEN_ID=root-token' \
      -e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200' \
      -e 'VAULT_ADDR=http://0.0.0.0:8200' \
      "${VAULT_IMAGE}" server -dev
  else
    docker run -d \
      --name "${VAULT_CONTAINER_NAME}" \
      --cap-add=IPC_LOCK \
      -p "${VAULT_PORT}:8200" \
      ${NETWORK_OPT} \
      -e 'VAULT_DEV_ROOT_TOKEN_ID=root-token' \
      -e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200' \
      -e 'VAULT_ADDR=http://0.0.0.0:8200' \
      "${VAULT_IMAGE}" server -dev
  fi
else
  # Production mode: requires initialization and unsealing
  echo "Running Vault in PRODUCTION mode"
  if [ ! -f "$(pwd)/vault-config.hcl" ]; then
    echo "Error: vault-config.hcl not found. Required for production mode."
    exit 1
  fi
  if [ "${VAULT_USE_HOST_NETWORK}" = "true" ]; then
    docker run -d \
      --name "${VAULT_CONTAINER_NAME}" \
      --cap-add=IPC_LOCK \
      ${NETWORK_OPT} \
      -v "$(pwd)/${VAULT_DATA_DIR}:/vault/data" \
      -v "$(pwd)/vault-config.hcl:/vault/config/vault.hcl" \
      -e 'VAULT_ADDR=http://0.0.0.0:8200' \
      "${VAULT_IMAGE}" server -config=/vault/config/vault.hcl
  else
    docker run -d \
      --name "${VAULT_CONTAINER_NAME}" \
      --cap-add=IPC_LOCK \
      -p "${VAULT_PORT}:8200" \
      ${NETWORK_OPT} \
      -v "$(pwd)/${VAULT_DATA_DIR}:/vault/data" \
      -v "$(pwd)/vault-config.hcl:/vault/config/vault.hcl" \
      -e 'VAULT_ADDR=http://0.0.0.0:8200' \
      "${VAULT_IMAGE}" server -config=/vault/config/vault.hcl
  fi
fi

# Wait for Vault to be ready
echo "Waiting for Vault to be ready..."
sleep 5

# Determine Vault address based on network mode
if [ "${VAULT_USE_HOST_NETWORK}" = "true" ]; then
  VAULT_ADDR="http://localhost:8200"
  VAULT_ADDR_FOR_KIND="http://localhost:8200"
  echo ""
  echo "Vault container started successfully!"
  echo "Container Name: ${VAULT_CONTAINER_NAME}"
  echo "Network Mode: host"
  echo "Vault Address (host): ${VAULT_ADDR}"
  echo "Vault Address (for kind): ${VAULT_ADDR_FOR_KIND}"
else
  # Get container IP for bridge network
  VAULT_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${VAULT_CONTAINER_NAME}" 2>/dev/null || echo "")
  if [ -n "${VAULT_IP}" ]; then
    VAULT_ADDR="http://${VAULT_IP}:8200"
  else
    VAULT_ADDR="http://localhost:${VAULT_PORT}"
  fi
  echo ""
  echo "Vault container started successfully!"
  echo "Container Name: ${VAULT_CONTAINER_NAME}"
  echo "Container IP: ${VAULT_IP:-N/A}"
  echo "Vault Address (host): http://localhost:${VAULT_PORT}"
  echo "Vault Address (container IP): ${VAULT_ADDR}"
  echo "Vault Address (for kind): ${VAULT_ADDR_FOR_KIND}"
fi
echo "Exposed Port: ${VAULT_PORT}"
echo ""
if [ "${VAULT_DEV_MODE}" = "true" ]; then
  echo "Dev Mode Root Token: root-token"
  echo ""
  echo "To use from kind cluster, set:"
  echo "  export VAULT_ADDR=\"${VAULT_ADDR_FOR_KIND}\""
  echo "  export VAULT_TOKEN=\"root-token\""
  echo ""
  echo "Note: If kind cannot reach Vault, restart with:"
  echo "  VAULT_USE_HOST_NETWORK=true ./scripts/setup-vault.sh"
else
  echo "Production mode: Vault needs to be initialized and unsealed"
  echo "Run: vault operator init"
fi
echo ""
echo "Container status:"
docker ps --filter "name=${VAULT_CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

