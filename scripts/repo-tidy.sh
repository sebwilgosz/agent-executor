#!/usr/bin/env bash
# repo-tidy.sh - tidies one repo after merges, touching only Executor's own
# worktrees and branches (scripts/executor-owned.sh: a branch a plan names by PR,
# or worktree-agent-*; a worktree on such a branch or under
# .claude/worktrees/agent-). No AI. Anything else is neither touched nor listed.
# In this order:
#   1. Remove finished worktrees: a linked worktree of Executor's on a finished
#      branch (scripts/branch-finished.sh), clean and unused, goes with
#      `git worktree remove`; a dirty one is listed and stays. Then
#      `git worktree prune`.
#   2. Delete Executor's finished local branches checked out nowhere: with -D only
#      when GitHub reports the PR MERGED and the local tip is the PR's head commit
#      (a squash merge leaves the branch unmerged in git's eyes), otherwise with
#      -d, only when the tip is in origin/<default>, which git itself must accept.
#      A branch with commits after the PR's head stays.
# Never switches the checkout, fast-forwards the default branch, deletes a remote
# branch or the default branch, stashes, resets, forces, rebases or touches
# anything with changes.
#
# Usage: repo-tidy.sh [--dry-run] <repo>
# --dry-run prints what it would do and changes nothing (it still fetches).
# Prints one short list at the end: removed, deleted, kept and why.
# Every gh and git failure goes to tidy.log in $EOW_HOME/executor (EOW_HOME defaults
# to ~/.engineer-of-wealth). When GitHub can't be asked, it stops, so nothing is
# deleted on a guess. The exit code is always 0.
set -u
unset CDPATH

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
cd / || exit 0
export GIT_OPTIONAL_LOCKS=0

STATE="${EOW_HOME:-$HOME/.engineer-of-wealth}/executor"
LOG="$STATE/tidy.log"
NL=$'\n'
mkdir -p "$STATE" 2>/dev/null
exec 2>>"$LOG"

tidy_log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }

. "$SELF_DIR/folder-state.sh"
. "$SELF_DIR/branch-finished.sh"
. "$SELF_DIR/executor-owned.sh"

dry=0
if [ "${1:-}" = "--dry-run" ]; then dry=1; shift; fi
repo=${1:-}
if [ -z "$repo" ]; then
  printf 'Usage: repo-tidy.sh [--dry-run] <repo>\n'
  exit 0
fi

# Runs a command, logs one line when it fails. The output is left in $OUT.
OUT=""
run() {
  OUT=$("$@" 2>&1) && return 0
  local rc=$?
  tidy_log "$* failed: $(printf '%s' "$OUT" | head -n 1)"
  return $rc
}

if ! run git -C "$repo" rev-parse --git-dir; then
  printf 'Not a git repo: %s\n' "$repo"
  exit 0
fi

wt_path=(); wt_branch=(); is_bare=0
read_worktrees() {
  local l p="" b=""
  wt_path=(); wt_branch=(); is_bare=0
  run git -C "$repo" worktree list --porcelain || return 1
  while IFS= read -r l; do
    case "$l" in
      "worktree "*) [ -z "$p" ] || { wt_path+=("$p"); wt_branch+=("$b"); }
                    p=${l#worktree }; b="" ;;
      bare) [ "${#wt_path[@]}" -ne 0 ] || is_bare=1 ;;
      "branch refs/heads/"*) b=${l#branch refs/heads/} ;;
    esac
  done <<< "$OUT"
  [ -z "$p" ] || { wt_path+=("$p"); wt_branch+=("$b"); }
  return 0
}

run git -C "$repo" fetch -q origin
def=$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
def=${def#refs/remotes/origin/}
[ -n "$def" ] || def=$(cd "$repo" && . "$SELF_DIR/default-branch.sh" && printf '%s' "$def")
[ -n "$def" ] || def=main

removed=""; deleted=""; kept=""
gh_down=0
say_kept() { kept="$kept- $1$NL"; }

# Finished, not finished, or GitHub down (sets gh_down).
finished() {
  local rc=0
  branch_finished "$repo" "$1" "$def" || rc=$?
  [ "$rc" -ne 2 ] || gh_down=1
  return $rc
}

read_worktrees || { printf 'Could not read the worktrees of %s, see tidy.log.\n' "$repo"; exit 0; }
main_wt=${wt_path[0]}
executor_owned_load "$repo" || gh_down=1

# 1. The worktrees
if [ "$gh_down" -eq 0 ]; then
  read_worktrees
  i=1
  while [ "$i" -lt "${#wt_path[@]}" ] && [ "$gh_down" -eq 0 ]; do
    p=${wt_path[$i]}; b=${wt_branch[$i]}
    i=$((i+1))
    [ -n "$b" ] && [ "$b" != "$def" ] || continue
    executor_worktree_owned "$main_wt" "$p" "$b" || continue
    finished "$b" || continue
    if has_changes "$p" || in_progress "$p"; then
      say_kept "worktree $p ($b): changes, not removed"
    elif folder_in_use "$p"; then
      say_kept "worktree $p ($b): in use, not removed"
    elif [ "$dry" -eq 1 ]; then
      removed="$removed- worktree $p ($b)$NL"
    elif run git -C "$repo" worktree remove "$p"; then
      removed="$removed- worktree $p ($b)$NL"
    else
      say_kept "worktree $p ($b): git would not remove it"
    fi
  done
  [ "$dry" -eq 1 ] || run git -C "$repo" worktree prune
fi

# 2. The branches
if [ "$gh_down" -eq 0 ]; then
  read_worktrees
  held=$NL
  for b in "${wt_branch[@]}"; do held="$held$b$NL"; done
  branches=$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads)
  while IFS= read -r b; do
    [ -n "$b" ] && [ "$b" != "$def" ] || continue
    case "$held" in *"$NL$b$NL"*) continue ;; esac
    executor_branch_owned "$b" || continue
    prs=$(branch_prs "$repo" "$b") || { gh_down=1; break; }
    case "$prs" in OPEN" "*|*"${NL}OPEN "*) continue ;; esac
    tip=$(git -C "$repo" rev-parse "refs/heads/$b")
    merged_tip=0; merged=0
    case "$prs" in *"MERGED $tip"*) merged_tip=1 ;; esac
    case "$prs" in MERGED" "*|*"${NL}MERGED "*) merged=1 ;; esac
    if [ "$merged_tip" -eq 1 ]; then
      if [ "$dry" -eq 1 ] || run git -C "$repo" branch -D "$b"; then
        deleted="$deleted- $b$NL"
      else
        say_kept "$b: git would not delete it"
      fi
    elif git -C "$repo" merge-base --is-ancestor "$tip" "refs/remotes/origin/$def" 2>/dev/null; then
      if [ "$dry" -eq 1 ] || git -C "$repo" branch -d "$b" >/dev/null 2>&1; then
        deleted="$deleted- $b$NL"
      else
        say_kept "$b: git does not call it merged"
      fi
    elif [ "$merged" -eq 1 ]; then
      say_kept "$b: has local commits after the merged PR"
    fi
  done <<< "$branches"
fi

# The final list
verb_r=Removed; verb_d=Deleted
if [ "$dry" -eq 1 ]; then verb_r="Would remove"; verb_d="Would delete"; fi
list=""
[ -z "$removed" ] || list="$list$verb_r:$NL$removed"
[ -z "$deleted" ] || list="$list$verb_d branches:$NL$deleted"
[ -z "$kept" ] || list="$list""Kept:$NL$kept"
if [ "$gh_down" -eq 1 ]; then
  list="${list}Could not ask GitHub, stopped there. See tidy.log.$NL"
fi
[ -n "$list" ] || list="Nothing to tidy.$NL"
[ "$dry" -eq 0 ] || list="Dry run, nothing changed.$NL$list"
printf '%s' "$list"
exit 0
