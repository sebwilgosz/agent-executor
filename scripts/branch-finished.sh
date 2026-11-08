#!/usr/bin/env bash
# The one test for "is this branch finished", shared by repo-tidy.sh and any caller
# that needs it. A branch is finished when its PR is merged or closed, or when it
# has no PR and everything on it is already in origin/<default>. A branch with an
# open PR never is. No AI, no writes.
#
# Sourced, it defines:
#   branch_prs <repo> <branch>              - prints one "STATE headSha" line per PR
#                                             (gh pr list --head <branch> --state all);
#                                             returns 2 when gh fails
#   branch_finished <repo> <branch> <def>   - returns 0 finished, 1 not finished,
#                                             2 when GitHub could not be asked
# A failed gh call is reported through tidy_log <text> when the caller defines it.
#
# Run, it prints finished, unfinished or unknown for the branch, and always exits 0:
#   branch-finished.sh <repo> <branch> [default]

branch_prs() {
  local out
  if ! out=$(cd "$1" && gh pr list --head "$2" --state all --json state,headRefOid \
      --jq '.[] | "\(.state) \(.headRefOid)"' 2>&1); then
    ! type tidy_log >/dev/null 2>&1 || tidy_log "gh pr list --head $2 failed: $(printf '%s' "$out" | head -n 1)"
    return 2
  fi
  printf '%s\n' "$out" | sed '/^$/d'
  return 0
}

branch_finished() {
  local repo=$1 b=$2 def=$3 prs rc=0
  prs=$(branch_prs "$repo" "$b") || rc=$?
  [ "$rc" -eq 0 ] || return 2
  case "$prs" in
    OPEN" "*|*$'\n'OPEN" "*) return 1 ;;
    MERGED" "*|CLOSED" "*|*$'\n'MERGED" "*|*$'\n'CLOSED" "*) return 0 ;;
  esac
  git -C "$repo" merge-base --is-ancestor "refs/heads/$b" "refs/remotes/origin/$def" 2>/dev/null
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  unset CDPATH
  repo=${1:-.}; b=${2:-}; def=${3:-}
  if [ -z "$def" ]; then
    def=$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
    def=${def#refs/remotes/origin/}
    [ -n "$def" ] || def=main
  fi
  branch_finished "$repo" "$b" "$def"
  case $? in 0) echo finished ;; 1) echo unfinished ;; *) echo unknown ;; esac
  exit 0
fi
