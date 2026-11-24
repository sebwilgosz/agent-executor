#!/usr/bin/env bash
# Sourced by status.sh and self-audit.sh, so both judge a repo's drift the same way.
# No AI, no writes, no fetch: it reads the refs as the last fetch left them. Defines:
#   repo_drift <repo>     - sets DRIFT to one line naming what drifted, empty when
#                           nothing did. Returns 0 when the repo has drifted, else 1.
#   checkout_drift <repo> - sets CHECKOUT to one line naming how the main checkout has
#                           drifted from its default branch, empty when it hasn't.
#                           Returns 0 when it has drifted, else 1. A linked worktree
#                           (a build's own) is never judged: only the main one is.
#
# repo_drift's one reason: Executor's own leftovers from finished builds, the ones
# scripts/repo-tidy.sh removes (scripts/executor-owned.sh says what is Executor's
# own). Any count above zero is drift:
#   - linked worktrees of Executor's on a finished branch (scripts/branch-finished.sh's
#     rule, from one `gh pr list` for the repo);
#   - Executor's local branches checked out nowhere that repo-tidy.sh would delete:
#     the PR is merged and the tip is the PR's head, or no PR is open and the tip
#     is in origin/<default>.
# The line reads "DRIFT: <n> worktrees and <m> branches left from finished builds -
# fix: repo-tidy.sh <repo>", a zero part left out. When GitHub or the plans folder
# can't be read, there is no line: no guess. At most two gh calls per repo.
#
# checkout_drift's four reasons, read from the refs alone (no gh call at all):
#   - off default: HEAD is not the default branch (origin/HEAD, as below);
#   - dirty: tracked changes or untracked files that are not ignored;
#   - diverged: local <default> has commits origin/<default> lacks, so a
#     fast-forward is impossible;
#   - behind: origin/<default> has commits local <default> lacks. The mildest: a
#     nudge, not a block.
# The line reads "CHECKOUT: <part>, <part> - fix: <command>", in that order, a zero
# part left out. Every fix is spelled out, folded into one command when more than
# one part applies: stash first when dirty, then either the backup-and-switch (which
# also leaves the checkout on <default>, fresh from origin) when diverged, or switch
# (when off default) and pull --ff-only (when behind), in that order.
#
#   drift.sh --checkout <repo>   prints the CHECKOUT line (or nothing) and exits:
#     0  nothing drifted
#     1  behind only - a nudge, safe to carry on
#     2  off default, dirty or diverged - the build should stop

NL=$'\n'
DRIFT_SELF_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$DRIFT_SELF_DIR/executor-owned.sh"

# The default branch's name, as origin/HEAD left it (status.sh's and self-audit.sh's
# one way to find it; no gh call, no fetch).
drift_default() {
  local def
  def=$(git -C "$1" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
  def=${def#refs/remotes/origin/}
  [ -n "$def" ] || def=main
  printf '%s' "$def"
}

# Is <repo> its main worktree, not one linked from it (a build's own)? Read-only:
# the main worktree's git-dir and git-common-dir are the same path; a linked one's
# git-dir is its own, under the main's .git/worktrees/.
checkout_is_main() {
  local gd gcd
  gd=$(git -C "$1" rev-parse --git-dir 2>/dev/null) || return 1
  gcd=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 1
  [ "$gd" = "$gcd" ]
}

checkout_drift() {
  local repo=$1 def head dirty_n local_only behind_n parts="" cmds="" \
        off=0 dirty=0 diverged=0 behind=0
  CHECKOUT=""
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 1
  checkout_is_main "$repo" || return 1

  def=$(drift_default "$repo")
  head=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)
  if [ "$head" != "$def" ]; then
    off=1
    parts="on ${head:-detached HEAD}"
  fi

  dirty_n=$(git -C "$repo" status --porcelain 2>/dev/null | grep -c .)
  if [ "${dirty_n:-0}" -gt 0 ]; then
    dirty=1
    parts="${parts:+$parts, }$(drift_count "$dirty_n" "dirty file" "dirty files")"
  fi

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$def" \
      && git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$def"; then
    local_only=$(git -C "$repo" rev-list --count "refs/remotes/origin/$def..refs/heads/$def" 2>/dev/null)
    behind_n=$(git -C "$repo" rev-list --count "refs/heads/$def..refs/remotes/origin/$def" 2>/dev/null)
    if [ "${local_only:-0}" -gt 0 ]; then
      diverged=1
      parts="${parts:+$parts, }$def diverged from origin ($local_only local-only)"
    fi
    if [ "${behind_n:-0}" -gt 0 ]; then
      behind=1
      parts="${parts:+$parts, }origin ahead of $def ($(drift_count "$behind_n" commit commits))"
    fi
  fi

  [ -n "$parts" ] || return 1

  [ "$dirty" -eq 0 ] || cmds="git stash push -u"
  if [ "$diverged" -eq 1 ]; then
    cmds="${cmds:+$cmds && }git branch backup/$def-$(date +%Y%m%d) $def && git switch -C $def origin/$def"
  else
    [ "$off" -eq 0 ] || cmds="${cmds:+$cmds && }git switch $def"
    [ "$behind" -eq 0 ] || cmds="${cmds:+$cmds && }git pull --ff-only"
  fi

  CHECKOUT="CHECKOUT: $parts - fix: $cmds"
  CHECKOUT_BLOCKING=$((off || dirty || diverged))
  return 0
}

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

  def=$(drift_default "$repo")

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

# Run directly (not sourced): `drift.sh --checkout <repo>`, for /executor:build's
# pre-check. Prints the CHECKOUT line, or nothing when the checkout hasn't drifted.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  unset CDPATH
  case "${1:-}" in
    --checkout)
      repo=${2:-.}
      if checkout_drift "$repo"; then
        printf '%s\n' "$CHECKOUT"
        [ "$CHECKOUT_BLOCKING" -eq 0 ] && exit 1 || exit 2
      fi
      exit 0
      ;;
    *) printf 'usage: drift.sh --checkout <repo>\n' >&2; exit 64 ;;
  esac
fi
