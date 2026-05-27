#!/usr/bin/env bash
# scripts/rename.sh <mfe-name>
#
# Replaces MFE_NAME placeholder tokens in all YAML, TypeScript, and config files
# with the actual microfrontend name.
#
# Used when using apps/_templates/vue-mfe/ as a starting point instead of
# the Backstage scaffolder. The Backstage scaffolder handles this automatically
# via its fetch:template step.
#
# Usage:
#   ./scripts/rename.sh claims-mfe
#
# Exit 0 = success
# Exit 1 = usage error
#
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <mfe-name>"
  echo "  mfe-name: kebab-case name, e.g. claims-mfe"
  exit 1
fi

MFE_NAME="$1"

if ! [[ "$MFE_NAME" =~ ^[a-z][a-z0-9-]{2,40}$ ]]; then
  echo "ERROR: mfe-name must be lowercase kebab-case (e.g. claims-mfe)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Renaming MFE_NAME → $MFE_NAME in $REPO_ROOT"

find "$REPO_ROOT" \
  -type f \
  \( -name "*.yaml" -o -name "*.yml" -o -name "*.ts" -o -name "*.tsx" -o -name "*.json" -o -name "*.conf" -o -name "Dockerfile" \) \
  ! -path "*/node_modules/*" \
  ! -path "*/.git/*" \
  | while read -r file; do
      if grep -qF "MFE_NAME" "$file"; then
        # BSD sed (macOS) and GNU sed compatible
        sed -i.bak "s/MFE_NAME/$MFE_NAME/g" "$file"
        rm -f "${file}.bak"
        echo "  patched: $file"
      fi
    done

echo ""
echo "✓ Done. All MFE_NAME tokens replaced with '$MFE_NAME'."
echo "  Review git diff to confirm the changes."
