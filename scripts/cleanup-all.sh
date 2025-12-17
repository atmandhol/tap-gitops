#!/usr/bin/env bash
#
# Aggressive cleanup - removes everything including data and configs
# Use with caution!
#

set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "WARNING: This will remove ALL TAP GitOps setup including:"
echo "  - Kind cluster"
echo "  - Vault container and ALL data"
echo "  - Generated configuration files"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Cleanup cancelled."
  exit 0
fi

"${SCRIPT_DIR}/cleanup-tap-gitops.sh" --all

echo ""
echo "✓ Complete cleanup finished!"

