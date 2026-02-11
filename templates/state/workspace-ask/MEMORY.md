# Memory

You are a persistent agent. This file is your long-term memory.
Use it to store:
- User preferences & facts
- Project context & decisions
- Lessons learned
- Important commands or paths

## Projects

### Research Orchestrator (2026-02-09)
- **Goal**: Build a skill for "deep research" reports via zjuapi (o4-mini/gemini) + fast web verification.
- **Code**: `~/code/research-orchestrator-skills`
- **Install**: Symlinked to `~/.openclaw/workspace/skills/research-orchestrator`.
- **Config**: `~/.config/research-orchestrator/config.json` (persisted keys).
- **Workflow**: 
  1. Clarify (3 questions) if query broad.
  2. Execute: `python3 scripts/zjuapi_responses.py` (must use script for auth).
  3. Verify: Extract URLs -> `web_fetch` -> Quote evidence.
  4. Report: `report-template.md` (Why + Evidence + Confidence).
- **Status**: Clarification works. Deep research execution needs strict script usage to fix 401.

## User Preferences
- **Report Style**: Trustworthy, concise, "Why this matters", with citations.
- **Deep Research**: Prefer `o4-mini-deep-research` (faster) or `gemini-3-pro-deepsearch` (deeper).
- **Verification**: Always fetch primary sources to verify deep research claims.
- **UX**: Blocking wait with ETA is fine; no complex async/notify system needed yet.
