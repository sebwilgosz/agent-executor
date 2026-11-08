#!/usr/bin/env bash
# Sourced by status.sh and self-audit.sh, so both judge a repo's drift the same way.
# No AI, no writes, no fetch: it reads the refs as the last fetch left them. Defines:
#   repo_drift <repo>   - sets DRIFT to one line naming what drifted, empty when
#                         nothing did. Returns 0 when the repo has drifted, else 1.
# A repo has drifted when
#   (a) its main checkout is on a non-default branch whose PR is merged or closed
#       (scripts/branch-finished.sh's rule, from one `gh pr list` for the repo);
#   (b) its local default branch is behind origin/<default>;
#   (c) more than 3 linked worktrees sit on finished branches.
# When GitHub can't be asked, (a) and (c) say nothing: no guess. The line ends with
# the one command that fixes it, repo-tidy.sh <repo>.

DRIFT_WORKTREES_MAX=3
NL=$'\n'

# branch_finished's rule, judged from the one PR listing in DRIFT_PRS: 0 finished,
# 1 not, 2 when GitHub could not be asked.
drift_finished() {
  local states
  [ "$DRIFT_GH" -eq 0 ] || return 2
  states=$(printf '%s\n' "$DRIFT_PRS" | awk -v b="$2" '$1 == b { print $2 }')
  case "$NL$states$NL" in
    *"${NL}OPEN$NL"*) return 1 ;;
    *"${NL}MERGED$NL"*|*"${NL}CLOSED$NL"*) return 0 ;;
  esac
  git -C "$1" merge-base --is-ancestor "refs/heads/$2" "refs/remotes/origin/$3" 2>/dev/null
}

repo_drift() {
  local repo=$1 def l p="" b="" i n=0 why="" main_branch="" behind
  local wt_path=() wt_branch=()
  DRIFT=""
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 1

  def=$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
  def=${def#refs/remotes/origin/}
  [ -n "$def" ] || def=main

  while IFS= read -r l; do
    case "$l" in
      "worktree "*) [ -z "$p" ] || { wt_path+=("$p"); wt_branch+=("$b"); }
                    p=${l#worktree }; b="" ;;
      "branch refs/heads/"*) b=${l#branch refs/heads/} ;;
    esac
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null)
  [ -z "$p" ] || { wt_path+=("$p"); wt_branch+=("$b"); }
  main_branch=${wt_branch[0]:-}

  # One gh call for every branch: a call per branch costs most of a second each.
  DRIFT_PRS=""; DRIFT_GH=0
  for b in "${wt_branch[@]}"; do
    [ -n "$b" ] && [ "$b" != "$def" ] || continue
    DRIFT_PRS=$(cd "$repo" && gh pr list --state all --limit 200 \
        --json headRefName,state,headRefOid --jq '.[] | "\(.headRefName) \(.state)"' 2>/dev/null) || DRIFT_GH=2
    break
  done

  if [ -n "$main_branch" ] && [ "$main_branch" != "$def" ]; then
    drift_finished "$repo" "$main_branch" "$def"
    [ $? -ne 0 ] || why="the checkout is on $main_branch, whose PR is finished"
  fi

  if git -C "$repo" rev-parse --verify --quiet "refs/heads/$def" >/dev/null 2>&1 \
      && git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$def" >/dev/null 2>&1 \
      && git -C "$repo" merge-base --is-ancestor "refs/heads/$def" "refs/remotes/origin/$def" 2>/dev/null; then
    behind=$(git -C "$repo" rev-list --count "refs/heads/$def..refs/remotes/origin/$def" 2>/dev/null)
    [ -z "$behind" ] || [ "$behind" -eq 0 ] || why="${why:+$why; }$def is $behind behind origin/$def"
  fi

  i=1
  while [ "$i" -lt "${#wt_path[@]}" ]; do
    b=${wt_branch[$i]}; i=$((i+1))
    [ -n "$b" ] && [ "$b" != "$def" ] || continue
    drift_finished "$repo" "$b" "$def"
    case $? in 0) n=$((n+1)) ;; 2) n=0; break ;; esac
  done
  [ "$n" -le "$DRIFT_WORKTREES_MAX" ] || why="${why:+$why; }$n worktrees on finished branches"

  [ -n "$why" ] || return 1
  DRIFT="DRIFT: $why - fix: repo-tidy.sh ${wt_path[0]:-$repo}"
  return 0
}
