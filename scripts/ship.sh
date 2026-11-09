#!/usr/bin/env bash
# ship.sh — the deterministic engine behind /executor:ship. No AI.
# It guards the branch, pushes it, checks whether a PR already exists and works
# out the PR's base. The model writes only the commit message and the PR body;
# every gh/git call lives here, so a failure is logged and returned as a note,
# never raised as a raw failed tool call. EOW_HOME overrides ~/.engineer-of-wealth.
#
# Output is one or more tagged lines the ship skill reads, and the exit code is
# always 0 (a stop is a note, not a crash):
#   STOP: <one-line reason>                 — do not open a PR; tell the user why
#   PUSHED: <branch>                         — the branch is on origin
#   PR_EXISTS: #<n> <url>                    — a PR is already open; push only
#   OPEN_PR: base=<base> head=<branch>       — open a DRAFT PR with this base
set -u

EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/ship.log"
. "$(dirname "$0")/branch-guard.sh"

guard_branch
guard_ahead

# Push the branch to origin.
if ! out=$(git push -u origin "$branch" 2>&1); then
  log_fail "git push $branch: $(printf '%s' "$out" | head -1)"
  stop "could not push $branch to origin — see $LOG"
fi
printf 'PUSHED: %s\n' "$branch"

# Already have a PR for this branch? Then push only — never a second PR.
if ! pr_lookup "$branch" open; then
  stop "pushed $branch, but could not check for an existing PR — not opening one to avoid a duplicate; see $LOG"
fi
if [ -n "$pr_n" ]; then
  printf 'PR_EXISTS: #%s %s\n' "$pr_n" "$pr_url"
  exit 0
fi

# No PR yet. Base = the default branch, unless this branch sits in a gh stack,
# where it is the branch below.
resolve_base
printf 'OPEN_PR: base=%s head=%s\n' "$base" "$branch"
exit 0
