#!/usr/bin/env bash
set -euo pipefail

# Create ONE OpenClaw container instance from instances/instances.json
#
# Usage:
#   ./scripts/create_instance.sh test2
#
# Factory layout (after this change):
# - templates/state/ is a *trimmed snapshot* of a normal ~/.openclaw state root,
#   and it now INCLUDES two prebuilt workspaces:
#     templates/state/workspace-main/
#     templates/state/workspace-ask/
#
# Instance layout:
# - <root>/state/ is mounted to /root/.openclaw
# - Workspaces live inside state:
#     /root/.openclaw/workspace-main
#     /root/.openclaw/workspace-ask
# - openclaw.json workspaces are pointed at those paths

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTANCES_JSON="$ROOT_DIR/instances/instances.json"

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  echo "Usage: $0 <instance-name>" >&2
  exit 1
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need jq
need docker
need openssl
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

mkdir -p "$state_dir"

# 1) Copy state template (includes workspaces)
STATE_TPL="$ROOT_DIR/templates/state"
if [[ ! -d "$STATE_TPL" ]]; then
  echo "Missing template dir: $STATE_TPL" >&2
  exit 1
fi

rsync -a --delete "$STATE_TPL/" "$state_dir/"

# 1.5) Init git sync repo (capability-only) in state root
# Repo URL (shared) + per-instance branch user/<name>
# Remote uses SSH host alias; requires ~/.ssh/config + key inside container
GIT_REPO_URL="github.com-autolab-bots:tyqqj0/autolab-bots.git"
GIT_BRANCH="user/$NAME"

if [[ ! -d "$state_dir/.git" ]]; then
  (cd "$state_dir" && git init >/dev/null)
  (cd "$state_dir" && git remote add origin "$GIT_REPO_URL" 2>/dev/null || true)
  (cd "$state_dir" && git checkout -b "$GIT_BRANCH" >/dev/null)
else
  # Ensure branch name matches convention
  (cd "$state_dir" && git remote set-url origin "$GIT_REPO_URL" 2>/dev/null || true)
  (cd "$state_dir" && git checkout "$GIT_BRANCH" >/dev/null 2>&1 || git checkout -b "$GIT_BRANCH" >/dev/null)
fi

# Per-instance git identity (helpful for audit)
(cd "$state_dir" && git config user.name "$NAME")
(cd "$state_dir" && git config user.email "$NAME@autolab-bots")

# Ensure required paths exist
ws_main="$state_dir/workspace-main"
ws_ask="$state_dir/workspace-ask"
mkdir -p "$ws_main" "$ws_ask"

# 2) Patch state/openclaw.json
CONF="$state_dir/openclaw.json"
if [[ ! -f "$CONF" ]]; then
  echo "Template state is missing openclaw.json at: $CONF" >&2
  exit 1
fi

# Proxy env vars
HTTP_PROXY=$(echo "$merged" | jq -r '.proxy.HTTP_PROXY // empty')
HTTPS_PROXY=$(echo "$merged" | jq -r '.proxy.HTTPS_PROXY // empty')
NO_PROXY=$(echo "$merged" | jq -r '.proxy.NO_PROXY // empty')

# Feishu account
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

# Gateway
GW_PORT=$(echo "$merged" | jq -r '.gateway.port')
GW_BIND=$(echo "$merged" | jq -r '.gateway.bind // "loopback"')
GW_AUTH_MODE=$(echo "$merged" | jq -r '.gateway.auth.mode // "token"')
GW_TOKEN_FILE="$state_dir/gateway-token.txt"
if [[ ! -f "$GW_TOKEN_FILE" ]]; then
  openssl rand -hex 20 > "$GW_TOKEN_FILE"
fi
GW_TOKEN=$(cat "$GW_TOKEN_FILE")

# Workspace paths (inside container)
WORKSPACE_MAIN_IN="/root/.openclaw/workspace-main"
WORKSPACE_ASK_IN="/root/.openclaw/workspace-ask"

# Patch JSON using jq
tmp="$CONF.tmp"
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
' "$CONF" > "$tmp"

mv "$tmp" "$CONF"
## --- public/secrets split (factory-managed) ---
CONF_DIR="$state_dir"
RUNTIME_JSON="$CONF_DIR/openclaw.json"
PUBLIC_JSON="$CONF_DIR/openclaw.public.json"
SECRETS_JSON="$CONF_DIR/openclaw.secrets.local.json"
EXTRACT_JQ="$CONF_DIR/scripts/extract_openclaw_secrets.jq"
REDACT_JQ="$CONF_DIR/scripts/redact_openclaw.jq"
MERGE_JQ="$CONF_DIR/scripts/merge_openclaw.jq"

ensure_public_and_secrets() {
  # create secrets.local if missing (from runtime)
  if [[ ! -f "$SECRETS_JSON" ]]; then
    jq -f "$EXTRACT_JQ" "$RUNTIME_JSON" > "$SECRETS_JSON.tmp"
    mv "$SECRETS_JSON.tmp" "$SECRETS_JSON"
  fi

  # always enforce instance Feishu appSecret into secrets.local
  jq --arg acct "$FEISHU_ACCOUNT_ID" --arg appSecret "$FEISHU_APP_SECRET" \
    ".channels.feishu.accounts[\$acct].appSecret=\$appSecret" \
    "$SECRETS_JSON" > "$SECRETS_JSON.tmp"
  mv "$SECRETS_JSON.tmp" "$SECRETS_JSON"
  chmod 600 "$SECRETS_JSON" 2>/dev/null || true

  # generate public.json from runtime
  jq -f "$REDACT_JQ" "$RUNTIME_JSON" > "$PUBLIC_JSON"

  # regenerate runtime from public+secrets (validate merge path)
  jq --slurpfile secrets "$SECRETS_JSON" -f "$MERGE_JQ" "$PUBLIC_JSON" > "$RUNTIME_JSON.tmp"
  mv "$RUNTIME_JSON.tmp" "$RUNTIME_JSON"
}

ensure_public_and_secrets
## --- end public/secrets split ---


echo "Prepared instance '$NAME' state at: $state_dir"

# 3) Run container
IMAGE=$(echo "$merged" | jq -r '.image')
CNAME="openclaw-$NAME"

# Proxy env for container

docker rm -f "$CNAME" >/dev/null 2>&1 || true

SSH_DIR="$state_dir/ssh"
mkdir -p "$SSH_DIR"
# The deploy key + config should be provisioned into $SSH_DIR (not in git).

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

echo "Started $CNAME"
echo "Gateway UI: http://127.0.0.1:$GW_PORT/ (token: $GW_TOKEN)"
