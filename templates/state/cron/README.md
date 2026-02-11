# Cron jobs (OpenClaw Gateway scheduler)

These are *desired* cron jobs for each instance. OpenClaw cron jobs live in the Gateway state store,
so they should be installed into each running container (not committed as runtime state).

Recommended v1 job:
- Daily capability backup to GitHub
- Runs inside container with local state repo

Install (inside container):

```bash
openclaw cron add \
  --session isolated \
  --cron "30 3 * * *" \
  --message "[autolab] git-sync push (daily backup)" \
  --no-deliver
```

Then configure the isolated agent to execute:
- `/root/.openclaw/scripts/git-sync.sh push`

We keep the actual schedule in this template so factory updates stay consistent.
