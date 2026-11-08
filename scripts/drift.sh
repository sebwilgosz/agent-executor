#!/usr/bin/env bash
# Sourced by status.sh and self-audit.sh, so both judge a repo's drift the same way.
# No AI, no writes, no fetch: it reads the refs as the last fetch left them. Defines:
#   repo_drift <repo>   - sets DRIFT to one line naming what drifted, empty when
#                         nothing did. Returns 0 when the repo has drifted, else 1.
# A repo has drifted for one reason: Executor's own leftovers from finished builds,
# the ones scripts/repo-tidy.sh removes (scripts/executor-owned.sh says what is
# Executor's own). Any count above zero is drift:
#   - linked worktrees of Executor's on a finished branch (scripts/branch-finished.sh's
#     rule, from one `gh pr list` for the repo);
#   - Executor's local branches checked out nowhere that repo-tidy.sh would delete:
#     the PR is merged and the tip is the PR's head, or no PR is open and the tip
#     is in origin/<default>.
# The line reads "DRIFT: <n> worktrees and <m> branches left from finished builds -
# fix: repo-tidy.sh <repo>", a zero part left out. When GitHub or the plans folder
# can't be read, there is no line: no guess. At most two gh calls per repo.

NL=$'\n'
DRIFT_SELF_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$DRIFT_SELF_DIR/executor-owned.sh"

drift_count() {
  if [ "$1" -eq 1 ]; then printf '1 %s' "$2"; else printf '%s %s' "$1" "$3"; fi
}

# branch_finished's rule, judged from the one PR listing in DRIFT_PRS
# ("<branch> <state> <head sha>" per line): 0 finished, 1 not.
drift_finished() {
  local states
  states=$(printf '%s\n' "$DRIFT_PRS" | awk -v b="$2" '$1 == b { print $2 }')
  case "$NL$states$NL" in
    *"${NL}OPEN$NL"*) return 1 ;;
    *"${NL}MERGED$NL"*|*"${NL}CLOSED$NL"*) return 0 ;;
  esac
  git -C "$1" merge-base --is-ancestor "refs/heads/$2" "refs/remotes/origin/$3" 2>/dev/null
}

# repo-tidy.sh's rule for deleting a branch, from the same listing.
drift_branch_deletable() {
  local tip states
  tip=$(git -C "$1" rev-parse "refs/heads/$2" 2>/dev/null) || return 1
  states=$(printf '%s\n' "$DRIFT_PRS" | awk -v b="$2" '$1 == b { print $2 }')
  case "$NL$states$NL" in *"${NL}OPEN$NL"*) return 1 ;; esac
  if printf '%s\n' "$DRIFT_PRS" | awk -v b="$2" -v t="$tip" \
      '$1 == b && $2 == "MERGED" && $3 == t { f = 1 } END { exit !f }'; then
    return 0
  fi
  git -C "$1" merge-base --is-ancestor "$tip" "refs/remotes/origin/$3" 2>/dev/null
}

repo_drift() {
  local repo=$1 def l p="" b="" i main wt=0 br=0 held="$NL" line
  local wt_path=() wt_branch=() cand=()
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
  main=${wt_path[0]:-$repo}

  executor_owned_load "$repo" || return 1

  for b in ${wt_branch[@]+"${wt_branch[@]}"}; do held="$held$b$NL"; done
  i=1
  while [ "$i" -lt "${#wt_path[@]}" ]; do
    p=${wt_path[$i]}; b=${wt_branch[$i]}; i=$((i+1))
    [ -n "$b" ] && [ "$b" != "$def" ] || continue
    ! executor_worktree_owned "$main" "$p" "$b" || cand+=("w $b")
  done
  while IFS= read -r b; do
    [ -n "$b" ] && [ "$b" != "$def" ] || continue
    case "$held" in *"$NL$b$NL"*) continue ;; esac
    ! executor_branch_owned "$b" || cand+=("b $b")
  done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
  [ "${#cand[@]}" -gt 0 ] || return 1

  DRIFT_PRS=$(cd "$repo" && gh pr list --state all --limit 200 \
      --json headRefName,state,headRefOid \
      --jq '.[] | "\(.headRefName) \(.state) \(.headRefOid)"' 2>/dev/null) || return 1

  for line in "${cand[@]}"; do
    b=${line#? }
    case "$line" in
      "w "*) ! drift_finished "$repo" "$b" "$def" || wt=$((wt+1)) ;;
      *) ! drift_branch_deletable "$repo" "$b" "$def" || br=$((br+1)) ;;
    esac
  done
  [ $((wt + br)) -gt 0 ] || return 1

  l=""
  [ "$wt" -eq 0 ] || l=$(drift_count "$wt" worktree worktrees)
  [ "$br" -eq 0 ] || l="${l:+$l and }$(drift_count "$br" branch branches)"
  DRIFT="DRIFT: $l left from finished builds - fix: repo-tidy.sh $main"
  return 0
}
