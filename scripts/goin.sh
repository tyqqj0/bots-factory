#!/usr/bin/env bash
set -euo pipefail

# Quick shell into an instance container for debugging.
#
# Usage:
#   ./scripts/goin.sh test2
#   ./scripts/goin.sh test2 bash
#   ./scripts/goin.sh test2 sh
#
# Notes:
# - Containers run without SSH; use docker exec.

NAME="${1:-}"
SHELL_BIN="${2:-sh}"

if [[ -z "$NAME" ]]; then
  echo "Usage: $0 <instance-name> [shell]" >&2
  exit 1
fi

CNAME="openclaw-$NAME"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CNAME"; then
  echo "Container not running: $CNAME" >&2
  echo "Try: docker ps -a --filter name=$CNAME" >&2
  exit 1
fi

echo "Entering $CNAME ..."
exec docker exec -it "$CNAME" "$SHELL_BIN"
