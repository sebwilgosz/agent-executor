#!/usr/bin/env bash
# PostToolUse hook: assign every PR Claude just created to its author.
# Plain shell, no AI: it prints nothing, so Claude never hears of it.
# The gh calls run detached, so the hook returns at once and the session never
# waits on GitHub; they also outlive a headless `claude -p` session ending.
# gh has no setting for a default assignee, so this is where it happens.
set -u

. "$(dirname "$0")/new-prs.sh"
[ -n "$kind" ] || exit 0
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd"

log="$HOME/.engineer-of-wealth/executor/assign.log"

nohup bash -c '
  log=$1; shift
  for pr in "$@"; do
    # "@me" is whoever gh is signed in as: the account that just opened the PR.
    if ! out=$(gh pr edit "$pr" --add-assignee "@me" 2>&1); then
      mkdir -p "$(dirname "$log")"
      printf "%s  %s  %s  %s\n" "$(date "+%F %T")" "$PWD" "$pr" "$(printf "%s" "$out" | head -1)" >> "$log"
    fi
  done
' assign-author "$log" $prs </dev/null >/dev/null 2>&1 &
exit 0
