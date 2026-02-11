#!/usr/bin/env bash
set -euo pipefail

# Git sync for OpenClaw state directory (repo root).
# - Tracks capability files only (workspaces, scripts, openclaw.public.json)
# - Never commits secrets (openclaw.json, openclaw.secrets.local.json)
# - Stops on conflicts; prints guidance for owner.

cmd="${1:-}"
shift || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PUBLIC_JSON="$ROOT/openclaw.public.json"
RUNTIME_JSON="$ROOT/openclaw.json"
SECRETS_JSON="$ROOT/openclaw.secrets.local.json"

REDact_JQ="$ROOT/scripts/redact_openclaw.jq"
MERGE_JQ="$ROOT/scripts/merge_openclaw.jq"
EXTRACT_SECRETS_JQ="$ROOT/scripts/extract_openclaw_secrets.jq"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need git
need jq
need ssh

branch_name() {
  git symbolic-ref -q --short HEAD 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(no-branch)"
}

ensure_repo() {
  if [[ ! -d .git ]]; then
    echo "Not a git repo: $ROOT" >&2
    exit 2
  fi
}

generate_public() {
  if [[ ! -f "$RUNTIME_JSON" ]]; then
    echo "Missing runtime config: $RUNTIME_JSON" >&2
    exit 2
  fi
  jq -f "$REDact_JQ" "$RUNTIME_JSON" > "$PUBLIC_JSON"
}

extract_secrets_from_runtime_if_missing() {
  if [[ -f "$SECRETS_JSON" ]]; then
    return 0
  fi
  if [[ ! -f "$RUNTIME_JSON" ]]; then
    return 0
  fi
  if [[ ! -f "$EXTRACT_SECRETS_JQ" ]]; then
    return 0
  fi
  jq -f "$EXTRACT_SECRETS_JQ" "$RUNTIME_JSON" > "$SECRETS_JSON.tmp" || return 0
  mv "$SECRETS_JSON.tmp" "$SECRETS_JSON"
  echo "Generated $SECRETS_JSON from existing runtime openclaw.json (local-only)." >&2
}

merge_runtime() {
  if [[ ! -f "$PUBLIC_JSON" ]]; then
    echo "Missing $PUBLIC_JSON; run pull or push first." >&2
    exit 2
  fi

  extract_secrets_from_runtime_if_missing

  if [[ ! -f "$SECRETS_JSON" ]]; then
    echo "Missing $SECRETS_JSON (local-only secrets)." >&2
    echo "Create it from factory/instances.json (preferred) or let extract_secrets run from a known-good openclaw.json." >&2
    exit 2
  fi

  jq --slurpfile secrets "$SECRETS_JSON" -f "$MERGE_JQ" "$PUBLIC_JSON" > "$RUNTIME_JSON.tmp"
  # --slurpfile produces an array; merge script expects $secrets as object
  jq '.[0]' "$RUNTIME_JSON.tmp" > "$RUNTIME_JSON.tmp2"
  mv "$RUNTIME_JSON.tmp2" "$RUNTIME_JSON"
  rm -f "$RUNTIME_JSON.tmp"
}

# White-list add: include all workspace-* except memory; include scripts + public json
stage_whitelist() {
  # scripts + public
  git add -A -- "scripts" "$PUBLIC_JSON" ".gitignore" 2>/dev/null || true

  # workspaces: add everything, then unstage memory
  shopt -s nullglob
  local ws
  for ws in workspace-*; do
    [[ -d "$ws" ]] || continue
    git add -A -- "$ws" 2>/dev/null || true
    if [[ -d "$ws/memory" ]]; then
      git reset -q -- "$ws/memory" || true
    fi
  done
  shopt -u nullglob

  # state capability dirs/files (safe-ish)
  git add -A -- "agents" "cron" "openclaw.json.patch.jq" "package.json" "package-lock.json" 2>/dev/null || true
}

print_conflict_help() {
  echo "Git conflict detected. Please resolve manually:" >&2
  echo "  - cd $ROOT" >&2
  echo "  - git status" >&2
  echo "  - git diff --name-only --diff-filter=U" >&2
  echo "  - resolve files, then: git add <files>" >&2
  echo "  - continue: git rebase --continue" >&2
  echo "  - or abort:  git rebase --abort" >&2
}

case "$cmd" in
  status)
    ensure_repo
    echo "repo: $ROOT"
    echo "branch: $(branch_name)"
    git status -sb || true
    ;;

  push)
    ensure_repo
    generate_public
    git fetch origin || true
    # If no commits yet: commit once first, then set upstream on push.
    if [[ "$(git rev-list --count HEAD 2>/dev/null || echo 0)" == "0" ]]; then
      stage_whitelist
      if ! git diff --cached --quiet; then
        msg="sync: $(date '+%F %T')"
        git commit -m "$msg" >/dev/null
      fi

      # If remote branch exists already, set upstream + rebase first.
      if git show-ref --verify --quiet "refs/remotes/origin/$(branch_name)"; then
        git branch --set-upstream-to="origin/$(branch_name)" "$(branch_name)" >/dev/null 2>&1 || true
        if ! git pull --rebase origin "$(branch_name)"; then
          print_conflict_help
          exit 10
        fi
      fi

      if git push --set-upstream origin "$(branch_name)"; then
        echo "Pushed $(git rev-parse --short HEAD) on $(branch_name)"
        exit 0
      fi
      echo "Initial push failed; check remote auth." >&2
      exit 11
    fi

    # Ensure upstream exists; if not, set it to origin/<current-branch>
    if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
      git branch --set-upstream-to="origin/$(branch_name)" "$(branch_name)" >/dev/null 2>&1 || true
    fi

    # v1: no auto-pull/rebase. Owner updates instances manually; this job only snapshots capabilities.
    # If push is rejected (non-fast-forward), resolve manually.

    stage_whitelist

    if git diff --cached --quiet; then
      echo "No changes to push."
      exit 0
    fi

    msg="sync: $(date '+%F %T')"
    git commit -m "$msg" >/dev/null
    # Push; if upstream not set (first push), set it automatically
    if ! git push; then
      if git push --set-upstream origin "$(branch_name)"; then
        :
      else
        echo "Push failed (likely non-fast-forward). Resolve manually then push." >&2
        exit 11
      fi
    fi
    echo "Pushed $(git rev-parse --short HEAD) on $(branch_name)"
    ;;

  pull)
    ensure_repo
    git fetch origin || true
    if ! git pull --rebase; then
      print_conflict_help
      exit 10
    fi
    merge_runtime
    echo "Pulled and regenerated openclaw.json (secrets merged locally)."
    ;;

  *)
    echo "Usage: $0 <status|push|pull>" >&2
    exit 1
    ;;
esac
