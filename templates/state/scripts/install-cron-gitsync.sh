#!/usr/bin/env bash
set -euo pipefail

# Install or update OpenClaw cron job for daily git-sync push.
# Must be run inside the container (where `openclaw` CLI is available).

NAME="${1:-gitsync-daily}"
CRON_EXPR="${CRON_EXPR:-30 3 * * *}"

# Find existing job id by name
job_id=$(openclaw cron list --json | jq -r --arg name "$NAME" '.jobs[]? | select(.name==$name) | .jobId' | head -n 1)

payload=$(jq -nc --arg msg "[autolab] git-sync push" '{kind:"agentTurn", message:$msg, timeoutSeconds:600}')

if [[ -n "${job_id:-}" && "$job_id" != "null" ]]; then
  openclaw cron update --job-id "$job_id" \
    --name "$NAME" \
    --session isolated \
    --cron "$CRON_EXPR" \
    --message "[autolab] git-sync push (daily backup)" \
    --no-deliver >/dev/null
  echo "Updated cron job: $NAME ($job_id)"
else
  openclaw cron add \
    --name "$NAME" \
    --session isolated \
    --cron "$CRON_EXPR" \
    --message "[autolab] git-sync push (daily backup)" \
    --no-deliver >/dev/null
  echo "Added cron job: $NAME"
fi

# NOTE: This script only installs the schedule+agentTurn. The isolated agent must be configured
# to run `/root/.openclaw/scripts/git-sync.sh push` when it receives the message.
