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

## What is configuration vs workspace?

- `openclaw.json` (config):
  - Channels (Feishu appId/secret)
  - Models/providers registry
  - Agents list, bindings routing rules
  - Tool policies / sandbox policies
  - Gateway port/bind/auth token (if exposed)

- `workspace/` (per-agent brain files):
  - Skills (`skills/`)
  - Persona rules (`SOUL.md`, `AGENTS.md`)
  - User profile (`USER.md`)
  - Local notes (`TOOLS.md`)
  - Heartbeat instructions (`HEARTBEAT.md`)
  - Any files the agent should use

In this MVP we will keep config in the instance state dir and mount workspaces as volumes.

## Proxy (Clash)

Containers cannot reach host 127.0.0.1 directly.
Use `host.docker.internal:<port>` for HTTP(S)_PROXY.
Example: host Clash HTTP proxy at 7897:

- HTTP_PROXY=http://host.docker.internal:7897
- HTTPS_PROXY=http://host.docker.internal:7897

## Next steps

1) Finalize `instances/instances.json` schema (instances list, per-instance secrets, owner open_id)
2) Add template `templates/openclaw.json5.tpl` which embeds:
   - env proxy vars
   - model providers registry
   - agents.list + bindings
   - feishu channel config
3) Implement scripts:
   - create_instance.sh <name>
   - create_all.sh
   - update_all.sh
4) Build image `openclaw-factory/gateway:2026.2.9` (done)
5) Boot one instance (`test2`) and verify DM routing:
   - owner -> main
   - other user -> ask

