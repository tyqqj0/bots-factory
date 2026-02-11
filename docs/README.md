# OpenClaw Factory (MVP)

This folder is a **template + scripts** workspace to spin up multiple isolated OpenClaw instances (OrbStack/Docker) on one Mac.

## Goal (Phase-1: 1 day)

- 5 Feishu apps/bots
- 5 isolated runtime instances (Docker containers) on one Mac
- Each instance runs one OpenClaw Gateway and connects to exactly one Feishu bot
- Inside each instance:
  - `main` agent: owner-only (high privilege)
  - `ask` agent: everyone else (low privilege)
- DM routing is deterministic by Feishu `open_id`:
  - owner open_id -> `main`
  - everyone else -> `ask`
- Groups: require @mention (and ideally allowlist). MVP can start with groups disabled.

## Mental model

- Each instance has a host directory:
  - `~/code/openclaw-instances/<name>/state`
- That directory is **bind-mounted** into the container:
  - host `.../state` -> container `/root/.openclaw`
- Therefore:
  - container writes to `/root/.openclaw` are persisted on the host
  - restarting/recreating the container does not lose memory/state

## Templates

Factory keeps one primary template snapshot:

- `templates/state/` = a trimmed snapshot of a normal `~/.openclaw/` root.
  - MUST include `openclaw.json`
  - Includes two embedded workspaces:
    - `templates/state/workspace-main/`
    - `templates/state/workspace-ask/`
  - Excludes runtime/volatile by design (do not template these):
    - `credentials/`, `logs/`, `agents/*/sessions`, etc.

Notes:
- We disable Telegram by default in the template to avoid getUpdates conflicts.

## Provision / Update / Delete

### Provision (create/recreate)
Creates (or recreates) an instance from templates, patches `openclaw.json`, then runs the container.

```bash
cd ~/code/openclaw-factory
./scripts/create_instance.sh test2
```

Batch provision:
```bash
./scripts/create_all.sh
./scripts/create_all.sh --only test2,test3
```

### Update (safe, keeps runtime state)
Updates only what we control (workspaces + config patch). Does NOT wipe the whole state.

```bash
./scripts/update_instance.sh test2
```

Optionally update extensions too:
```bash
./scripts/update_instance.sh test2 --extensions
```

Batch update:
```bash
./scripts/update_all.sh
./scripts/update_all.sh --extensions
./scripts/update_all.sh --only test2,test3
```

### Delete
Default is container-only (keeps host data, memory preserved):

```bash
./scripts/delete_instance.sh test2
```

Dangerous full purge (deletes host directory too):

```bash
./scripts/delete_instance.sh test2 --purge
```

## Proxy (Clash)

Containers cannot reach host 127.0.0.1 directly.
Use `host.docker.internal:<port>` for HTTP(S)_PROXY.
Example: host Clash HTTP proxy at 7897:

- HTTP_PROXY=http://host.docker.internal:7897
- HTTPS_PROXY=http://host.docker.internal:7897

## Testing checklist (single instance)

1) Confirm container is running:
```bash
docker ps --filter name=openclaw-test2
```

2) Watch logs:
```bash
docker logs -f openclaw-test2
```

3) DM routing:
- owner DM -> `main`
- non-owner DM -> `ask`

