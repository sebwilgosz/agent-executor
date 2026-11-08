#!/usr/bin/env bash
# PostToolUse hook: assign every PR Claude just created to its author.
# Plain shell, no AI: it prints nothing, so Claude never hears of it.
# The gh calls run detached, so the hook returns at once and the session never
# waits on GitHub; they also outlive a headless `claude -p` session ending.
# gh has no setting for a default assignee, so this is where it happens.
# A stack PR is assigned only by URL, once its head branch is the one gh stack
# reported: a PR that isn't surely the new one is left alone, and logged.
set -u

. "$(dirname "$0")/new-prs.sh"
[ -n "$kind" ] || exit 0
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd"

log="$HOME/.engineer-of-wealth/executor/assign.log"

set --
while IFS= read -r pr <&3; do
  IFS= read -r branch <&4
  set -- "$@" "$pr" "$branch"
done 3<<< "$prs" 4<<< "$branches"

nohup bash -c '
  log=$1; kind=$2; shift 2
  note() {
    mkdir -p "$(dirname "$log")"
    printf "%s  %s  %s  %s\n" "$(date "+%F %T")" "$PWD" "$1" "$2" >> "$log"
  }
  errors=$(mktemp) || errors=/dev/null
  while [ "$#" -gt 0 ]; do
    pr=$1; branch=$2; shift 2
    if [ "$kind" = stack ]; then
      case "$pr" in
        https://*) ;;
        *) note "$pr" "repo unknown, not assigned (head branch $branch)"; continue ;;
      esac
      if ! actual=$(gh pr view "$pr" --json headRefName --jq .headRefName 2>"$errors"); then
        note "$pr" "lookup failed, not assigned: $(tail -1 "$errors")"
        continue
      fi
      if [ "$actual" != "$branch" ]; then
        note "$pr" "head branch is $actual, not $branch: not assigned"
        continue
      fi
    fi
    # "@me" is whoever gh is signed in as: the account that just opened the PR.
    if ! out=$(gh pr edit "$pr" --add-assignee "@me" 2>&1); then
      note "$pr" "$(printf "%s" "$out" | head -1)"
    fi
  done
  [ "$errors" = /dev/null ] || rm -f "$errors"
' assign-author "$log" "$kind" "$@" </dev/null >/dev/null 2>&1 &
exit 0
