#!/usr/bin/env bash
set -euo pipefail

# Update ONE instance without deleting runtime state.
#
# Default (safe) behavior:
# - Patch <state>/openclaw.json with per-instance values (Feishu keys, owner open_id, gateway port/token, proxy)
# - Update workspaces from templates/state/workspace-main and workspace-ask (rsync --delete)
# - Optionally update extensions/ from templates/state/extensions (rsync --delete) if --extensions is passed
# - Restart container (or recreate with --recreate)
#
# Usage:
#   ./scripts/update_instance.sh test2
#   ./scripts/update_instance.sh test2 --extensions
#   ./scripts/update_instance.sh test2 --recreate

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTANCES_JSON="$ROOT_DIR/instances/instances.json"

NAME="${1:-}"
shift || true

if [[ -z "$NAME" || "$NAME" == -* ]]; then
  echo "Usage: $0 <instance-name> [--extensions] [--recreate]" >&2
  exit 1
fi

UPDATE_EXTENSIONS=false
RECREATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extensions) UPDATE_EXTENSIONS=true; shift ;;
    --recreate) RECREATE=true; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need jq
need docker
need openssl
need rsync
need git

inst_json=$(jq -c --arg name "$NAME" '.instances[] | select(.name==$name)' "$INSTANCES_JSON")
if [[ -z "$inst_json" ]]; then
  echo "Instance '$NAME' not found in $INSTANCES_JSON" >&2
  exit 1
fi

def_json=$(jq -c '.defaults' "$INSTANCES_JSON")
merged=$(jq -c -n --argjson d "$def_json" --argjson i "$inst_json" '$d * $i')

root=$(echo "$merged" | jq -r '.storage.root')
root_expanded=$(eval echo "$root")
state_dir="$root_expanded/state"

CONF="$state_dir/openclaw.json"
if [[ ! -f "$CONF" ]]; then
  echo "Missing instance state/openclaw.json at: $CONF" >&2
  echo "Run provision first: ./scripts/create_instance.sh $NAME" >&2
  exit 1
fi

# Ensure git sync repo is initialized (capability-only)
GIT_REPO_URL="github.com-autolab-bots:tyqqj0/autolab-bots.git"
GIT_BRANCH="user/$NAME"
if [[ ! -d "$state_dir/.git" ]]; then
  (cd "$state_dir" && git init >/dev/null)
  (cd "$state_dir" && git remote add origin "$GIT_REPO_URL" 2>/dev/null || true)
  (cd "$state_dir" && git checkout -b "$GIT_BRANCH" >/dev/null)
else
  (cd "$state_dir" && git remote set-url origin "$GIT_REPO_URL" 2>/dev/null || true)
  (cd "$state_dir" && git checkout "$GIT_BRANCH" >/dev/null 2>&1 || git checkout -b "$GIT_BRANCH" >/dev/null)
fi

# Per-instance git identity
(cd "$state_dir" && git config user.name "$NAME")
(cd "$state_dir" && git config user.email "$NAME@autolab-bots")

# Update workspaces (safe-ish; v1 still uses template rsync --delete)
# NOTE: git-sync will NOT track memory/; consider excluding memory/ from rsync later.
TPL="$ROOT_DIR/templates/state"
if [[ ! -d "$TPL" ]]; then
  echo "Missing template dir: $TPL" >&2
  exit 1
fi

mkdir -p "$state_dir/workspace-main" "$state_dir/workspace-ask"
rsync -a --delete "$TPL/workspace-main/" "$state_dir/workspace-main/"
rsync -a --delete "$TPL/workspace-ask/"  "$state_dir/workspace-ask/"

if $UPDATE_EXTENSIONS; then
  if [[ -d "$TPL/extensions" ]]; then
    mkdir -p "$state_dir/extensions"
    rsync -a --delete "$TPL/extensions/" "$state_dir/extensions/"
  else
    echo "Template has no extensions/, skipping." >&2
  fi
fi

# Patch openclaw.json (same logic as provision)
HTTP_PROXY=$(echo "$merged" | jq -r '.proxy.HTTP_PROXY // empty')
HTTPS_PROXY=$(echo "$merged" | jq -r '.proxy.HTTPS_PROXY // empty')
NO_PROXY=$(echo "$merged" | jq -r '.proxy.NO_PROXY // empty')

FEISHU_ACCOUNT_ID=$(echo "$merged" | jq -r '.feishu.accountId // "main"')
FEISHU_APP_ID=$(echo "$merged" | jq -r '.feishu.appId')
FEISHU_APP_SECRET=$(echo "$merged" | jq -r '.feishu.appSecret')
FEISHU_BOT_NAME=$(echo "$merged" | jq -r '.feishu.botName // .name')
FEISHU_DOMAIN=$(echo "$merged" | jq -r '.feishu.domain // "feishu"')
FEISHU_DM_POLICY=$(echo "$merged" | jq -r '.feishu.dmPolicy // "pairing"')
FEISHU_GROUP_POLICY=$(echo "$merged" | jq -r '.feishu.groupPolicy // "disabled"')
FEISHU_STREAMING=$(echo "$merged" | jq -r '.feishu.streaming // true')
FEISHU_BLOCK_STREAMING=$(echo "$merged" | jq -r '.feishu.blockStreaming // true')

OWNER_OPEN_ID=$(echo "$merged" | jq -r '.routing.ownerOpenId')

GW_PORT=$(echo "$merged" | jq -r '.gateway.port')
GW_BIND=$(echo "$merged" | jq -r '.gateway.bind // "loopback"')
GW_AUTH_MODE=$(echo "$merged" | jq -r '.gateway.auth.mode // "token"')
GW_TOKEN_FILE="$state_dir/gateway-token.txt"
if [[ ! -f "$GW_TOKEN_FILE" ]]; then
  openssl rand -hex 20 > "$GW_TOKEN_FILE"
fi
GW_TOKEN=$(cat "$GW_TOKEN_FILE")

WORKSPACE_MAIN_IN="/root/.openclaw/workspace-main"
WORKSPACE_ASK_IN="/root/.openclaw/workspace-ask"

TMP="$CONF.tmp"
jq \
  --arg http "$HTTP_PROXY" \
  --arg https "$HTTPS_PROXY" \
  --arg no "$NO_PROXY" \
  --arg acct "$FEISHU_ACCOUNT_ID" \
  --arg appId "$FEISHU_APP_ID" \
  --arg appSecret "$FEISHU_APP_SECRET" \
  --arg botName "$FEISHU_BOT_NAME" \
  --arg domain "$FEISHU_DOMAIN" \
  --arg dmPolicy "$FEISHU_DM_POLICY" \
  --arg groupPolicy "$FEISHU_GROUP_POLICY" \
  --argjson streaming "$FEISHU_STREAMING" \
  --argjson blockStreaming "$FEISHU_BLOCK_STREAMING" \
  --arg owner "$OWNER_OPEN_ID" \
  --arg bind "$GW_BIND" \
  --arg authMode "$GW_AUTH_MODE" \
  --arg token "$GW_TOKEN" \
  --arg wsMain "$WORKSPACE_MAIN_IN" \
  --arg wsAsk "$WORKSPACE_ASK_IN" \
  --argjson port "$GW_PORT" \
'
  .env.vars.HTTP_PROXY = $http
| .env.vars.HTTPS_PROXY = $https
| .env.vars.NO_PROXY = $no
| .channels.feishu.dmPolicy = $dmPolicy
| .channels.feishu.groupPolicy = $groupPolicy
| .channels.feishu.streaming = $streaming
| .channels.feishu.blockStreaming = $blockStreaming
| .channels.feishu.accounts[$acct].appId = $appId
| .channels.feishu.accounts[$acct].appSecret = $appSecret
| .channels.feishu.accounts[$acct].botName = $botName
| .channels.feishu.accounts[$acct].domain = $domain
| .gateway.port = ($port|tonumber)
| .gateway.bind = $bind
| .gateway.auth.mode = $authMode
| .gateway.auth.token = $token
| (.agents.defaults.workspace) = $wsMain
| (.agents.list[]? | select(.id=="main") | .workspace) = $wsMain
| (.agents.list[]? | select(.id=="ask")  | .workspace) = $wsAsk
| .bindings = [
    {"agentId":"main","match":{"channel":"feishu","peer":{"kind":"direct","id":$owner}}},
    {"agentId":"ask","match":{"channel":"feishu","peer":{"kind":"direct","id":"*"}}}
  ]
' "$CONF" > "$TMP"

mv "$TMP" "$CONF"

CNAME="openclaw-$NAME"
if docker ps -a --format '{{.Names}}' | grep -qx "$CNAME"; then
  if $RECREATE; then
    echo "Recreating container $CNAME"
    docker rm -f "$CNAME" >/dev/null 2>&1 || true
    IMAGE=$(echo "$merged" | jq -r '.image')
    SSH_DIR="$state_dir/ssh"
    mkdir -p "$SSH_DIR"

    docker run -d --name "$CNAME" \
      -p "$GW_PORT:18789" \
      -e "OPENCLAW_STATE_DIR=/root/.openclaw" \
      -e "OPENCLAW_CONFIG_PATH=/root/.openclaw/openclaw.json" \
      -e "HTTP_PROXY=$HTTP_PROXY" \
      -e "HTTPS_PROXY=$HTTPS_PROXY" \
      -e "NO_PROXY=$NO_PROXY" \
      -v "$state_dir:/root/.openclaw" \
      -v "$SSH_DIR:/root/.ssh:ro" \
      "$IMAGE"
  else
    echo "Restarting container $CNAME"
    docker restart "$CNAME" >/dev/null
  fi
else
  echo "Container $CNAME does not exist; run provision to create it." >&2
  exit 1
fi

echo "Updated $NAME. Gateway: http://127.0.0.1:$GW_PORT/"
