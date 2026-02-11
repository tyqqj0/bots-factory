#!/usr/bin/env bash
set -euo pipefail

# Delete ONE instance.
#
# By default: delete container ONLY (keeps host state dir so memory is preserved)
#
# Usage:
#   ./scripts/delete_instance.sh test2
#   ./scripts/delete_instance.sh test2 --purge   # also deletes ~/code/openclaw-instances/test2

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTANCES_JSON="$ROOT_DIR/instances/instances.json"

NAME="${1:-}"
shift || true

if [[ -z "$NAME" || "$NAME" == -* ]]; then
  echo "Usage: $0 <instance-name> [--purge]" >&2
  exit 1
fi

PURGE=false
if [[ "${1:-}" == "--purge" || "${1:-}" == "-p" ]]; then
  PURGE=true
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

inst_json=$(jq -c --arg name "$NAME" '.instances[] | select(.name==$name)' "$INSTANCES_JSON")
if [[ -z "$inst_json" ]]; then
  echo "Instance '$NAME' not found in $INSTANCES_JSON" >&2
  exit 1
fi

root=$(echo "$inst_json" | jq -r '.storage.root')
root_expanded=$(eval echo "$root")

CNAME="openclaw-$NAME"

docker rm -f "$CNAME" >/dev/null 2>&1 || true

echo "Removed container (if existed): $CNAME"

echo "Instance data directory: $root_expanded"

if $PURGE; then
  echo
  echo "DANGER: This will delete ALL instance data (memory/state/workspaces) at:"
  echo "  $root_expanded"
  echo -n "Type the instance name to confirm purge: "
  read -r confirm
  if [[ "$confirm" != "$NAME" ]]; then
    echo "Purge aborted." >&2
    exit 1
  fi
  
  echo "Purging..."
  rm -rf "$root_expanded"
  echo "Purged: $root_expanded"
else
  echo "Kept data directory (memory preserved)."
fi
