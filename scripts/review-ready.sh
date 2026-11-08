#!/usr/bin/env bash
# review-ready.sh — marks your own draft PR ready once the review passes it. No AI.
# Draft means Executor is still reviewing, so a PR left a draft after a passing
# review looks unfinished. Only an open draft you wrote is flipped: --fix can put
# the review on a teammate's PR, and that draft stays theirs to flip. A failure is
# logged to ~/.engineer-of-wealth/executor/review.log (EOW_HOME overrides the root)
# and flips nothing.
#
# Usage:   review-ready.sh <number|url>
#          review-ready.sh --branch [<name>]   (no name: HEAD)
# Output is one line; the exit code is always 0:
#   READY: marked ready
#   SKIP: <why>       left as it is
#   UNKNOWN: <why>    could not tell, or could not flip it
set -u

EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/review.log"

ERR=$(mktemp)
trap 'rm -f "$ERR"' EXIT

say() { printf '%s: %s\n' "$1" "$2"; exit 0; }
# stderr is kept apart from the reply, so a gh notice can't end up in a field.
log_fail() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s  %s  %s: %s\n' "$(date "+%F %T")" "$PWD" "$1" "$(head -1 "$ERR")" >> "$LOG"
}

pr="${1:-}"
[ -n "$pr" ] || say UNKNOWN "no PR given to review-ready.sh"

author=""; fork=""; draft=""; state=""
if [ "$pr" = --branch ]; then
  # A branch review covers the local commits and uncommitted changes, so its
  # verdict only speaks for a PR whose head is that same state. Matching on the
  # commit also rules out unpushed work and a fork's same-named branch.
  branch="${2:-}"
  [ -n "$branch" ] || branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  sha=$(git rev-parse --verify --quiet "$branch^{commit}" 2>/dev/null) || say UNKNOWN "branch $branch not found"
  if [ "$sha" = "$(git rev-parse HEAD 2>/dev/null)" ] && ! git diff --quiet HEAD 2>/dev/null; then
    say SKIP "uncommitted changes, so the review was not of the PR's head"
  fi
  if ! out=$(gh pr list --head "$branch" --state open --limit 50 --json number,author,isCrossRepository,isDraft,state,headRefOid \
             --jq "[.[] | select(.headRefOid == \"$sha\" and (.isCrossRepository | not))][0] // empty | \"\\(.number) \\(.author.login) \\(.isCrossRepository) \\(.isDraft) \\(.state)\"" 2>"$ERR"); then
    log_fail "gh pr list --head $branch"
    say UNKNOWN "could not read the PR, see $LOG"
  fi
  [ -n "$out" ] || say SKIP "no open PR at this commit"
  read -r pr author fork draft state <<<"$out"
else
  if ! out=$(gh pr view "$pr" --json author,isCrossRepository,isDraft,state --jq '"\(.author.login) \(.isCrossRepository) \(.isDraft) \(.state)"' 2>"$ERR"); then
    log_fail "gh pr view $pr"
    say UNKNOWN "could not read the PR, see $LOG"
  fi
  read -r author fork draft state <<<"$out"
  [ -n "$state" ] || say UNKNOWN "could not read the PR, gh returned nothing"
fi

[ "$state" = OPEN ] || say SKIP "PR is $(printf '%s' "$state" | tr '[:upper:]' '[:lower:]')"
[ "$draft" = true ] || say SKIP "already ready"
[ "$fork" = true ] && say SKIP "fork PR by @$author"

if ! me=$(gh api user --jq .login 2>"$ERR") || [ -z "$me" ]; then
  log_fail "gh api user"
  say UNKNOWN "could not read the gh user, see $LOG"
fi
[ "$author" = "$me" ] || say SKIP "PR by @$author"

if ! gh pr ready "$pr" >/dev/null 2>"$ERR"; then
  log_fail "gh pr ready $pr"
  say UNKNOWN "could not mark it ready, see $LOG"
fi
say READY "marked ready"
