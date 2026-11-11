#!/usr/bin/env bash
# pr-open.sh — from a finished branch to an open draft PR in one call. No AI.
#   bash pr-open.sh --branch <b> --below <branch|default> --title "<t>" --body-file <f>
# It puts the branch in its stack, pushes, opens the draft PR on the right base
# (or updates the one that exists), sets title and body, and fills the body's
# "Depends on" section itself from the base it used. Every gh/git call lives
# here: a failure is logged to $EOW_HOME/executor/pr-open.log and returned as
# a STOP line, never raised. EOW_HOME overrides ~/.engineer-of-wealth.
#
# Output is tagged lines, and the exit code is always 0:
#   PR: #<n> <url> base=<base> opened|updated
#   RETARGETED: <old-base> merged, based on <default> instead   (before PR:)
#   UNSTACKED: gh stack exited <n> (<last line>) - opened as a plain PR   (before PR:)
#   STOP: <one-line reason>                  - nothing opened; tell the user why
set -u

EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/pr-open.log"
. "$(dirname "$0")/branch-guard.sh"

want_branch=""; below=""; title=""; body_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --branch)    want_branch=${2:-}; shift ;;
    --below)     below=${2:-}; shift ;;
    --title)     title=${2:-}; shift ;;
    --body-file) body_file=${2:-}; shift ;;
    *) stop "unknown argument $1 - usage: pr-open.sh --branch <b> --below <branch|default> --title <t> --body-file <f>" ;;
  esac
  shift
done
[ -n "$want_branch" ] && [ -n "$below" ] && [ -n "$title" ] && [ -n "$body_file" ] || \
  stop "usage: pr-open.sh --branch <b> --below <branch|default> --title <t> --body-file <f>"
[ -f "$body_file" ] || stop "body file $body_file not found"
command -v jq >/dev/null 2>&1 || stop "jq is required"

TMP=$(mktemp -d 2>/dev/null) || stop "could not create a temp folder"
trap 'rm -rf "$TMP"' EXIT
export GIT_EDITOR=true

try() { # run a command; on failure log it and keep its last error line
  local out
  out=$("$@" 2>&1) && return 0
  fail_msg=$(printf '%s' "$out" | tail -1)
  log_fail "$*: $fail_msg"
  return 1
}

# Like try, for a gh stack call, but it acts on the exit code: 8 (locked) is
# retried after $EXECUTOR_STACK_WAIT seconds (default 2), up to 3 times. It
# returns the command's exit code and sets fail_msg, gs_rc and $TMP/gs_msg (the
# last survives a subshell). stack_fatal turns 6, 7 and 8 into a STOP.
gstack() {
  local out rc tries=0
  while :; do
    out=$("$@" 2>&1) && return 0
    rc=$?
    [ "$rc" = 8 ] && [ "$tries" -lt 3 ] || break
    tries=$((tries+1)); sleep "${EXECUTOR_STACK_WAIT:-2}"
  done
  fail_msg=$(printf '%s' "$out" | tail -1); gs_rc=$rc
  printf '%s' "$fail_msg" > "$TMP/gs_msg"
  log_fail "$*: exit $rc: $fail_msg"
  return "$rc"
}

stack_fatal() { # <exit code> - stop on 6, 7, 8; main shell only
  local repo; repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
  case "$1" in
    8) stop "gh stack is locked by another process in $repo - retry the ship" ;;
    7) stop "a gh stack rebase is in progress in $repo - finish it with gh stack rebase --continue or --abort, then retry" ;;
    6) stop "$branch belongs to more than one stack - check out a branch in only one stack, then retry" ;;
  esac
}

guard_branch "$want_branch"
git show-ref --verify --quiet "refs/heads/$branch" || stop "branch $branch does not exist"
[ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$branch" ] || stop "$branch is not checked out - check it out first"
guard_ahead

try git fetch -q origin || stop "could not fetch origin: $fail_msg - see $LOG"

push_branch() { # [--force-with-lease]
  try git push -q "$@" -u origin "$branch" || stop "could not push $branch: $fail_msg - see $LOG"
}

write_body() { # <depends>
  awk '/^## /{skip = ($0 ~ /^## Depends on[[:space:]]*$/)} !skip{print}' "$body_file" | cat -s > "$TMP/body.md"
  [ -s "$TMP/body.md" ] && printf '\n' >> "$TMP/body.md"
  printf '## Depends on\n%s\n' "$1" >> "$TMP/body.md"
}

depends_for() { # <base> -> "#<n>" of the open PR on that branch, else nothing
  [ "$1" = "$def" ] && { printf 'nothing'; return; }
  pr_lookup "$1" open && [ -n "$pr_n" ] && { printf '#%s' "$pr_n"; return; }
  printf 'nothing'
}

edit_pr() { # <n> <base>
  write_body "$(depends_for "$2")"
  try gh pr edit "$1" --title "$title" --body-file "$TMP/body.md" || stop "could not set the title and body of #$1: $fail_msg - see $LOG"
}

# A PR already exists for the branch: push, update title and body, no second PR.
pr_lookup "$branch" open || stop "could not check for an existing PR: $(tail -1 "$LOG" | sed 's/.*: //') - see $LOG"
if [ -n "$pr_n" ]; then
  n=$pr_n; url=$pr_url; base=${pr_base:-$def}
  push_branch
  edit_pr "$n" "$base"
  printf 'PR: #%s %s base=%s updated\n' "$n" "$url" "$base"
  exit 0
fi

# Work out the base.
below_pr=""; retargeted=""
if [ "$below" = default ] || [ "$below" = "$def" ]; then
  base=$def
else
  base=$below
  pr_lookup "$below" all || stop "could not look up the PR of $below: $(tail -1 "$LOG" | sed 's/.*: //') - see $LOG"
  if [ -n "$pr_n" ]; then
    below_pr=$pr_n
  else
    merged=$(printf '%s' "$pr_json" | jq -r 'any(.[]?; .state=="MERGED")' 2>/dev/null)
    gone=1
    git show-ref --verify --quiet "refs/remotes/origin/$below" && gone=0
    git show-ref --verify --quiet "refs/heads/$below" && gone=0
    if [ "$merged" = true ] || [ "$gone" = 1 ]; then
      retargeted=$below; base=$def
    else
      stop "$below has no open PR - open it first"
    fi
  fi
fi

# The base merged or is gone: replay only the branch's own commits onto the default branch.
rebased=0
if [ -n "$retargeted" ]; then
  upstream=""
  git show-ref --verify --quiet "refs/remotes/origin/$retargeted" && upstream="origin/$retargeted"
  [ -z "$upstream" ] && git show-ref --verify --quiet "refs/heads/$retargeted" && upstream=$retargeted
  before=$(git rev-parse HEAD)
  if [ -n "$upstream" ]; then rebase=(git rebase --onto "$cmp" "$upstream" "$branch"); else rebase=(git rebase "$cmp" "$branch"); fi
  if ! try "${rebase[@]}"; then
    files=$(git diff --name-only --diff-filter=U 2>/dev/null | paste -sd, -)
    git rebase --abort >/dev/null 2>&1
    stop "rebasing $branch onto $def conflicts in: ${files:-unknown files} - rebase aborted, resolve it by hand"
  fi
  [ "$(git rev-parse HEAD)" = "$before" ] || rebased=1
fi

if [ "$rebased" = 1 ]; then push_branch --force-with-lease; else push_branch; fi

# Adopt $branch on top of the stack $below is already in. `gh stack add` runs
# from a checkout of $below; since $branch is checked out here, it leaves that
# checkout as it is. A worktree that already has $below is used, else a temporary one.
stack_add_on_below() {
  local wt rc
  wt=$(git worktree list --porcelain | awk -v b="branch refs/heads/$below" '/^worktree /{p=substr($0,10)} $0==b{print p; exit}')
  if [ -z "$wt" ]; then
    wt="$TMP/below"
    try git worktree add -q "$wt" "$below" || return 1
  fi
  (cd "$wt" && gstack gh stack add "$branch"); rc=$?
  [ "$wt" = "$TMP/below" ] && git worktree remove --force "$wt" >/dev/null 2>&1
  return $rc
}

# Put the branch in its stack, then open the PR. 6, 7 and 8 stop; 9 (stacked
# PRs not enabled) falls back to a plain PR; any other failure falls back too,
# and is reported as UNSTACKED.
stacked=1; unstacked=""
if ! gh stack view --json >/dev/null 2>&1; then
  if [ -n "$below_pr" ]; then
    gstack gh stack init "$below" "$branch"; rc=$?
    if [ "$rc" != 0 ]; then stack_fatal "$rc"; stack_add_on_below; rc=$?; fi
  else gstack gh stack init "$branch"; rc=$?; fi
  if [ "$rc" != 0 ]; then
    stack_fatal "$rc"
    stacked=0
    [ "$rc" = 9 ] || unstacked="gh stack exited $rc ($(cat "$TMP/gs_msg" 2>/dev/null)) - opened as a plain PR, not in a stack"
  fi
fi

write_body "$(depends_for "$base")"
opened=0
if [ "$stacked" = 1 ]; then
  gstack gh stack submit --auto; rc=$?
  if [ "$rc" = 0 ]; then opened=1
  elif [ "$rc" != 9 ]; then
    stack_fatal "$rc"
    stop "could not open the PR: $fail_msg - see $LOG"
  fi
fi
if [ "$opened" = 0 ]; then
  try gh pr create --draft --base "$base" --head "$branch" --title "$title" --body-file "$TMP/body.md" \
    || stop "could not open the PR: $fail_msg - see $LOG"
fi

pr_lookup "$branch" open && [ -n "$pr_n" ] || stop "the PR for $branch was not found after opening it - see $LOG"
n=$pr_n; url=$pr_url; used=${pr_base:-$base}
edit_pr "$n" "$used"

[ -n "$retargeted" ] && printf 'RETARGETED: %s merged, based on %s instead\n' "$retargeted" "$def"
[ -n "$unstacked" ] && printf 'UNSTACKED: %s\n' "$unstacked"
printf 'PR: #%s %s base=%s opened\n' "$n" "$url" "$used"
exit 0
