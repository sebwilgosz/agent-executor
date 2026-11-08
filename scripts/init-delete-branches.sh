#!/usr/bin/env bash
# init-delete-branches.sh — the engine behind /executor:init's "Automatically
# delete head branches" step. No AI. Reads the repository's
# delete_branch_on_merge setting; with --apply, turns it on. Only --apply
# changes anything on GitHub, and the skill runs it only after a yes.
# The exit code is always 0; a problem is one STOP line.
#   TARGET: <owner>/<repo>
#   STATE: on        — already on; nothing to offer
#   STATE: off       — off; the skill offers to turn it on
#   STATE: enabled   — (--apply) turned on
#   STOP: <reason>   — could not check or change it
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
. "$SELF_DIR/remote-slug.sh"

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/init.log"

stop() { printf 'STOP: %s\n' "$1"; exit 0; }
log_fail() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s  %s  %s\n' "$(date "+%F %T")" "$PWD" "$1" >> "$LOG" 2>/dev/null
}

url=$(git remote get-url origin 2>/dev/null) || stop "no origin remote, so the delete-head-branches setting was not checked"
slug=$(slug_from_url "$url")
[ -n "$slug" ] || stop "could not read the repository from the origin remote, so the delete-head-branches setting was not checked"
printf 'TARGET: %s\n' "$slug"

command -v gh >/dev/null 2>&1 || stop "gh is not installed, so the delete-head-branches setting was not checked"

if ! cur=$(gh api "repos/$slug" --jq .delete_branch_on_merge 2>&1); then
  log_fail "check $slug: $cur"
  stop "could not read the delete-head-branches setting of $slug (no network or no permission) — see $LOG"
fi

case "$cur" in
  true) printf 'STATE: on\n'; exit 0 ;;
  false) ;;
  *) log_fail "check $slug: unexpected '$cur'"; stop "could not read the delete-head-branches setting of $slug — see $LOG" ;;
esac

if [ "$APPLY" -eq 0 ]; then
  printf 'STATE: off\n'; exit 0
fi

if ! err=$(gh api -X PATCH "repos/$slug" -f delete_branch_on_merge=true 2>&1 >/dev/null); then
  log_fail "enable $slug: $err"
  stop "could not turn on automatic deletion of head branches for $slug (you may lack admin rights) — see $LOG"
fi
printf 'STATE: enabled\n'
