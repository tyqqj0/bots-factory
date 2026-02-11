#!/usr/bin/env bash
set -euo pipefail

# Update ALL instances.
#
# Usage:
#   ./scripts/update_all.sh
#   ./scripts/update_all.sh --extensions
#   ./scripts/update_all.sh --only test2,test3
#
# This calls update_instance.sh for each instance.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTANCES_JSON="$ROOT_DIR/instances/instances.json"

ONLY=""
WITH_EXTENSIONS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --extensions) WITH_EXTENSIONS=true; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

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
  echo "No instances to update." >&2
  exit 1
fi

for name in $names; do
  echo "==> Updating instance: $name"
  if $WITH_EXTENSIONS; then
    "$ROOT_DIR/scripts/update_instance.sh" "$name" --extensions
  else
    "$ROOT_DIR/scripts/update_instance.sh" "$name"
  fi
  echo
done

echo "Done."
