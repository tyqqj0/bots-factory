#!/usr/bin/env bash
set -euo pipefail

# Apply instance profile (from instances.json) into workspace USER.md files.
# Usage: apply-profile.sh <instances.json> <instanceName> <stateDir>

INSTANCES_JSON="${1:?instances.json}"
NAME="${2:?instanceName}"
STATE_DIR="${3:?stateDir}"

profile_json=$(jq -c --arg name "$NAME" '(.instances[] | select(.name==$name) | .profile // {})' "$INSTANCES_JSON")

ownerName=$(echo "$profile_json" | jq -r '.ownerName // ""')
assistantName=$(echo "$profile_json" | jq -r '.assistantName // ""')
purpose=$(echo "$profile_json" | jq -r '.purpose // ""')
quickstart=$(echo "$profile_json" | jq -r '.quickstart // [] | map("- " + .) | join("\\n")')

block=$(cat <<EOF
## Bot Profile

- **Owner**: ${ownerName}
- **Assistant**: ${assistantName}

**Purpose**
${purpose}

**Quickstart**
${quickstart}
EOF
)

for ws in "$STATE_DIR/workspace-main" "$STATE_DIR/workspace-ask"; do
  [[ -d "$ws" ]] || continue
  f="$ws/USER.md"
  if [[ ! -f "$f" ]]; then
    printf "%s\n" "$block" > "$f"
    continue
  fi
  # Remove previous injected block (from "## Bot Profile" until next "## " header or EOF)
  awk 'BEGIN{skip=0}
       /^## Bot Profile/{skip=1; next}
       skip && /^## /{skip=0}
       !skip{print}' "$f" > "$f.tmp" || true
  mv "$f.tmp" "$f"
  printf "\n%s\n" "$block" >> "$f"
done
