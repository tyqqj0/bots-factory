#!/usr/bin/env bash
set -euo pipefail

# Create ALL instances defined in instances/instances.json
#
# Usage:
#   ./scripts/create_all.sh
#   ./scripts/create_all.sh --only test2,test3
#
# Notes:
# - This will recreate (rsync --delete) each instance's state/workspaces from templates,
#   then patch openclaw.json and restart the container.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTANCES_JSON="$ROOT_DIR/instances/instances.json"

ONLY=""
if [[ "${1:-}" == "--only" ]]; then
  ONLY="${2:-}"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

names=$(jq -r '.instances[].name' "$INSTANCES_JSON")

if [[ -n "$ONLY" ]]; then
  IFS=',' read -r -a want <<< "$ONLY"
  filtered=""
  for n in $names; do
    for w in "${want[@]}"; do
      if [[ "$n" == "$w" ]]; then
        filtered+="$n\n"
      fi
    done
  done
  names=$(echo -e "$filtered" | sed '/^$/d')
fi

if [[ -z "$names" ]]; then
  echo "No instances to create." >&2
  exit 1
fi

for name in $names; do
  echo "==> Creating instance: $name"
  "$ROOT_DIR/scripts/create_instance.sh" "$name"
  echo
done

echo "Done."
