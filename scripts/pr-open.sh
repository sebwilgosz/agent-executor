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

# Put the branch in its stack, then open the PR.
stacked=1
if ! gh stack view --json >/dev/null 2>&1; then
  if [ -n "$below_pr" ]; then try gh stack init "$below" "$branch" || stacked=0
  else try gh stack init "$branch" || stacked=0; fi
fi

write_body "$(depends_for "$base")"
opened=0
if [ "$stacked" = 1 ]; then
  out=$(gh stack submit --auto 2>&1); rc=$?
  if [ "$rc" = 0 ]; then opened=1
  elif [ "$rc" != 9 ]; then
    log_fail "gh stack submit: $(printf '%s' "$out" | tail -1)"
    stop "could not open the PR: $(printf '%s' "$out" | tail -1) - see $LOG"
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
printf 'PR: #%s %s base=%s opened\n' "$n" "$url" "$used"
exit 0
