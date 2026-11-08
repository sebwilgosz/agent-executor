#!/usr/bin/env bash
# review-mode.sh — decides whether /executor:review may fix what it finds. No AI.
# Fix mode commits on the target and, for a PR, pushes to its branch. That is
# right on your own work and wrong on a teammate's, and a fork PR can't take the
# push at all. So the review fixes by default only when the target is yours, and
# otherwise reports. Every gh/git call lives here; a failure is logged to
# ~/.engineer-of-wealth/executor/review.log (EOW_HOME overrides the root) and
# falls back to report-only, the mode that can't do harm.
#
# Usage:   review-mode.sh pr <number|url> [--fix|--no-fix]
#          review-mode.sh branch [<name>] [--fix|--no-fix]   (no name: HEAD)
# Output is one line; the exit code is always 0:
#   MODE: fix · <why>
#   MODE: report-only · <why>
# <why> goes into the summary's Rounds line as it is.
set -u

EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/review.log"

ERR=$(mktemp)
trap 'rm -f "$ERR"' EXIT

say()      { printf 'MODE: %s · %s\n' "$1" "$2"; exit 0; }
# stderr is kept apart from the reply, so a gh notice can't end up in a field.
log_fail() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s  %s  %s: %s\n' "$(date "+%F %T")" "$PWD" "$1" "$(head -1 "$ERR")" >> "$LOG"
}

kind="${1:-}"; [ $# -gt 0 ] && shift
target=""; flag=""
for a in "$@"; do
  case "$a" in
    --fix | --no-fix) flag=$a ;;
    *) target=$a ;;
  esac
done

case "$kind" in pr | branch) ;; *) say report-only "review-mode.sh needs pr or branch as its first argument" ;; esac
[ "$kind" = pr ] && [ -z "$target" ] && say report-only "no PR given to review-mode.sh"

# --no-fix needs no lookup: nothing will be committed whoever wrote it.
[ "$flag" = --no-fix ] && say report-only "--no-fix"

# The PR to judge: the one named, or the open PR of the branch.
author=""; fork=""; pr=""
if [ "$kind" = pr ]; then
  if ! out=$(gh pr view "$target" --json number,author,isCrossRepository --jq '"\(.number) \(.author.login) \(.isCrossRepository)"' 2>"$ERR"); then
    log_fail "gh pr view $target"
    say report-only "could not read the PR's author, see $LOG"
  fi
  read -r pr author fork <<<"$out"
else
  [ -n "$target" ] || target=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  # --head matches the branch name in every fork, so a stranger's patch-1 would
  # answer for yours: keep only a PR whose head lives with origin's owner. With
  # no owner to read, keep the same-repository PRs.
  owner=$(git remote get-url origin 2>/dev/null | sed -nE 's#^(.*[:/])?([A-Za-z0-9_.-]+)/[^/]+$#\2#p' | tr '[:upper:]' '[:lower:]')
  if [ -n "$owner" ]; then keep="(.headRepositoryOwner.login | ascii_downcase) == \"$owner\""; else keep=".isCrossRepository | not"; fi
  if out=$(gh pr list --head "$target" --state open --limit 50 --json number,author,isCrossRepository,headRepositoryOwner \
           --jq "[.[] | select($keep)][0] // empty | \"\\(.number) \\(.author.login) \\(.isCrossRepository)\"" 2>"$ERR"); then
    [ -n "$out" ] && read -r pr author fork <<<"$out"
  else
    log_fail "gh pr list --head $target"
  fi
fi

if [ -n "$pr" ]; then
  # A fork's branch lives in another repository: the push can't land, --fix or not.
  [ "$fork" = true ] && {
    [ "$flag" = --fix ] && say report-only "fork PR by @$author, --fix can't push to it"
    say report-only "fork PR by @$author"
  }
  [ "$flag" = --fix ] && say fix "--fix, PR by @$author"
  if ! me=$(gh api user --jq .login 2>"$ERR") || [ -z "$me" ]; then
    log_fail "gh api user"
    say report-only "could not read the gh user, see $LOG"
  fi
  [ "$author" = "$me" ] && say fix "your PR"
  say report-only "PR by @$author"
fi

# A branch with no open PR: nothing is pushed, but fixing still commits on it,
# so it has to be yours too. Yours = every commit past the default branch is
# authored with your git email. No commits past it yet (only uncommitted work)
# is yours.
git rev-parse --verify --quiet "$target^{commit}" >/dev/null || say report-only "branch $target not found"
[ "$flag" = --fix ] && say fix "--fix, branch $target"
. "$(dirname "$0")/default-branch.sh"
git rev-parse --verify --quiet "$cmp^{commit}" >/dev/null || say report-only "no default branch to compare $target with"
mine=$(git config user.email 2>/dev/null)
[ -n "$mine" ] || say report-only "git user.email is not set, can't tell whose commits these are"
others=$(git log --format=%ae "$cmp..$target" 2>/dev/null | grep -vixF -- "$mine" | sort -u | paste -sd ',' - | sed 's/,/, /g')
[ -z "$others" ] && say fix "your branch"
say report-only "branch has commits by $others"
