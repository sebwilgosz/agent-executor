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

stop()     { printf 'STOP: %s\n' "$1"; exit 0; }
log_fail() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s  %s  %s\n' "$(date "+%F %T")" "$PWD" "$1" >> "$LOG"
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || stop "not a git repository"

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -n "$branch" ] && [ "$branch" != HEAD ] || stop "detached HEAD — check out a branch first"

. "$(dirname "$0")/default-branch.sh"

# Guard 1: never ship the default branch itself.
[ "$branch" = "$def" ] && stop "on the default branch ($def) — switch to a feature branch"

# A dirty tree means the commit step was skipped; the skill commits first.
[ -z "$(git status --porcelain 2>/dev/null)" ] || \
  stop "uncommitted changes — commit (or set aside) them, then ship again"

# Guard 2: the branch must carry commits the default branch lacks.
ahead=$(git rev-list --count "$cmp..HEAD" 2>/dev/null || echo 0)
[ "${ahead:-0}" -gt 0 ] || stop "$branch has no commits beyond $def — nothing to ship"

# Push the branch to origin.
if ! out=$(git push -u origin "$branch" 2>&1); then
  log_fail "git push $branch: $(printf '%s' "$out" | head -1)"
  stop "could not push $branch to origin — see $LOG"
fi
printf 'PUSHED: %s\n' "$branch"

# Already have a PR for this branch? Then push only — never a second PR.
if ! existing=$(gh pr list --head "$branch" --json number,url 2>&1); then
  log_fail "gh pr list $branch: $(printf '%s' "$existing" | head -1)"
  stop "pushed $branch, but could not check for an existing PR — not opening one to avoid a duplicate; see $LOG"
fi
if command -v jq >/dev/null 2>&1; then
  n=$(printf '%s' "$existing" | jq -r '.[0].number // empty' 2>/dev/null)
  url=$(printf '%s' "$existing" | jq -r '.[0].url // empty' 2>/dev/null)
else
  n=$(printf '%s' "$existing" | grep -oE '"number":[0-9]+' | head -1 | grep -oE '[0-9]+')
  url=$(printf '%s' "$existing" | grep -oE 'https://[^"]+/pull/[0-9]+' | head -1)
fi
if [ -n "$n" ]; then
  printf 'PR_EXISTS: #%s %s\n' "$n" "$url"
  exit 0
fi

# No PR yet. Base = the default branch, unless this branch sits in a gh stack,
# where it is the branch below. gh stack reports each branch's base as a commit
# SHA, not a name, so map that SHA to the stack branch whose head it is — that
# branch's name is a valid PR base. A base that is the trunk commit (the bottom
# of the stack) matches no branch, so the default branch stands.
base="$def"
if command -v jq >/dev/null 2>&1 && command -v gh >/dev/null 2>&1; then
  if sv=$(gh stack view --json 2>/dev/null) && [ -n "$sv" ]; then
    below=$(printf '%s' "$sv" | jq -r '
      (.branches[]? | select(.isCurrent==true) | .base) as $pb
      | ([.branches[]? | select(.head==$pb) | .name] | first) // empty' 2>/dev/null)
    [ -n "$below" ] && [ "$below" != null ] && base="$below"
  fi
fi
printf 'OPEN_PR: base=%s head=%s\n' "$base" "$branch"
exit 0
