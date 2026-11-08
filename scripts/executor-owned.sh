#!/usr/bin/env bash
# The one rule for "Executor's own", shared by repo-tidy.sh and drift.sh. Sourced.
# A branch is Executor's when it is the head branch of a PR a plan of this repo
# names (`PR #<n>`, live and done plans alike), or when its name starts with
# worktree-agent-. A linked worktree is Executor's when its branch is, or its path
# is under <main checkout>/.claude/worktrees/agent-. No AI, no writes.
#
#   executor_owned_load <repo>                     - reads the plans folder
#       (scripts/plan-path.sh) and, when a plan names a PR, asks GitHub once
#       (gh pr list --state all --limit 200) which branches those PRs head.
#       Returns 0 loaded, 2 when GitHub or the plans folder could not be read:
#       callers stop there rather than guess.
#   executor_branch_owned <branch>                 - 0 when Executor's, else 1
#   executor_worktree_owned <main> <path> <branch> - 0 when Executor's, else 1
# A failure is reported through tidy_log <text> when the caller defines it.

EXECUTOR_OWNED_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EO_NAMED=$'\n'

executor_owned_load() {
  local repo=$1 dir f nums="" map
  EO_NAMED=$'\n'
  dir=$(bash "$EXECUTOR_OWNED_DIR/plan-path.sh" "$repo" 2>/dev/null)
  case "$dir" in
    /*) ;;
    *) ! type tidy_log >/dev/null 2>&1 || tidy_log "plans folder unknown: $dir"; return 2 ;;
  esac
  if [ -d "$dir" ]; then
    for f in "$dir"/*.md; do
      [ -f "$f" ] || continue
      nums="$nums"$'\n'"$(grep -oE 'PR #[0-9]+' "$f" | sed 's/^PR #//')"
    done
  fi
  nums=$(printf '%s\n' "$nums" | sed '/^$/d' | sort -u)
  [ -n "$nums" ] || return 0
  if ! map=$(cd "$repo" && gh pr list --state all --limit 200 \
      --json number,headRefName,state,headRefOid \
      --jq '.[] | "\(.number) \(.headRefName)"' 2>&1); then
    ! type tidy_log >/dev/null 2>&1 || tidy_log "gh pr list --state all failed: $(printf '%s' "$map" | head -n 1)"
    return 2
  fi
  local n b
  while read -r n b; do
    [ -n "$b" ] || continue
    case $'\n'"$nums"$'\n' in *$'\n'"$n"$'\n'*) EO_NAMED="$EO_NAMED$b"$'\n' ;; esac
  done <<< "$map"
  return 0
}

executor_branch_owned() {
  case "$1" in worktree-agent-*) return 0 ;; esac
  case "$EO_NAMED" in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

executor_worktree_owned() {
  case "$2" in "$1"/.claude/worktrees/agent-*) return 0 ;; esac
  [ -z "$3" ] || executor_branch_owned "$3"
}
