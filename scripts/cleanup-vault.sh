#!/usr/bin/env bash
#
# Cleanup Vault container and data
#

set -o errexit -o nounset -o pipefail

VAULT_CONTAINER_NAME="${VAULT_CONTAINER_NAME:-vault-tap}"
VAULT_DATA_DIR="${VAULT_DATA_DIR:-./vault-data}"
REMOVE_DATA="${REMOVE_DATA:-false}"

function usage() {
  cat << EOF
$0 :: Cleanup Vault container and optionally data

Environment Variables:
- VAULT_CONTAINER_NAME -- Name of Vault container (default: vault-tap)
- VAULT_DATA_DIR -- Directory containing Vault data (default: ./vault-data)
- REMOVE_DATA -- Set to 'true' to remove Vault data directory (default: false)

EOF
}

# Parse arguments
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--remove-data" ]]; then
  REMOVE_DATA=true
fi

echo "Cleaning up Vault container..."

# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${VAULT_CONTAINER_NAME}$"; then
  echo "Vault container '${VAULT_CONTAINER_NAME}' does not exist."
  exit 0
fi

# Stop container if running
if docker ps --format '{{.Names}}' | grep -q "^${VAULT_CONTAINER_NAME}$"; then
  echo "Stopping Vault container '${VAULT_CONTAINER_NAME}'..."
  docker stop "${VAULT_CONTAINER_NAME}"
fi

# Remove container
echo "Removing Vault container '${VAULT_CONTAINER_NAME}'..."
docker rm "${VAULT_CONTAINER_NAME}"

if [ $? -eq 0 ]; then
  echo "✓ Vault container removed successfully"
else
  echo "✗ Failed to remove Vault container"
  exit 1
fi

# Optionally remove data directory
if [ "${REMOVE_DATA}" = "true" ]; then
  if [ -d "${VAULT_DATA_DIR}" ]; then
    echo ""
    echo "Removing Vault data directory: ${VAULT_DATA_DIR}"
    read -p "This will delete all Vault data. Are you sure? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
      rm -rf "${VAULT_DATA_DIR}"
      echo "✓ Vault data directory removed"
    else
      echo "Skipping data directory removal"
    fi
  else
    echo "Vault data directory not found: ${VAULT_DATA_DIR}"
  fi
else
  echo ""
  echo "Note: Vault data directory preserved: ${VAULT_DATA_DIR}"
  echo "To remove it, run: $0 --remove-data"
fi

echo ""
echo "✓ Vault cleanup complete!"

