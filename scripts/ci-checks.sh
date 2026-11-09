#!/usr/bin/env bash
# ci-checks.sh - the CI state of one commit, and whether a repo has CI at all. No AI.
#
#   ci-checks.sh --detect [<repo dir>]
#   ci-checks.sh <pr> [--sha <commit>] [--wait <minutes>]
#
# --detect reads the repo's files alone, with no PR and no network: "CI: configured
# <workflow file>" when a workflow under .github/workflows runs on push or on
# pull_request, whatever it runs, else "CI: none". Sourced, this file gives its callers
# ci_detect <repo dir> with the same line, and returns 0 when CI is configured.
#
# The PR form reports the checks on one commit, the PR's current head unless --sha says
# otherwise, so a green run on an older commit is never green. --wait polls until they
# finish or the minutes run out. Tagged lines, and the exit code is always 0:
#   CI: none                          no checks, and no workflow that would run here
#   CI: running <n> checks            still going: no --wait, or the wait ran out. Right
#                                     after a push nothing is registered yet, and a repo
#                                     with a push or pull_request workflow reads "running 0"
#   CI: green
#   CI: red <check name> <url>        then up to 30 of the failing log's last lines, each
#                                     as "LOG: <line>". A check that is not a GitHub
#                                     Actions run (a Vercel preview) has no log lines
#   UNKNOWN: <why>                    gh failed, or the input was wrong
#
# CI_CHECKS_POLL (seconds between polls, 30) and CI_CHECKS_MINUTE (seconds in a minute of
# --wait, 60) exist so tests run fast. Failures are logged to
# ~/.engineer-of-wealth/executor/ci-checks.log (EOW_HOME overrides the root).

CI_SELF=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$CI_SELF/ci-state.sh"

# Exit 0 when the workflow file runs on push or pull_request: the `on:` key at the top
# of the file, as a value ("on: push", "on: [push]"), a list, or a mapping of events.
ci_workflow_runs() {
  awk -v q="'" '
    BEGIN { onre = "^[\"" q "]?on[\"" q "]?[[:space:]]*:" }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    function hit(t,   n, a, i) {
      gsub(/[^A-Za-z_]+/, " ", t)
      n = split(t, a, " ")
      for (i = 1; i <= n; i++) if (a[i] == "push" || a[i] == "pull_request") return 1
      return 0
    }
    !inblock && $0 ~ onre {
      v = $0
      sub(onre, "", v)
      sub(/[[:space:]]+#.*$/, "", v)
      if (v ~ /[^[:space:]]/) { found = hit(v); exit }
      inblock = 1; base = -1
      next
    }
    inblock {
      if ($0 !~ /^[[:space:]]/ && $0 !~ /^- /) { inblock = 0; next }
      match($0, /^[[:space:]]*/)
      ind = RLENGTH
      if (base < 0) base = ind
      if (ind != base) next
      t = substr($0, ind + 1)
      sub(/^-[[:space:]]*/, "", t)
      sub(/[^A-Za-z_].*$/, "", t)
      if (t == "push" || t == "pull_request") { found = 1; exit }
    }
    END { exit found ? 0 : 1 }
  ' "$1" 2>/dev/null
}

ci_detect() {
  local dir=${1:-.} f
  for f in "$dir"/.github/workflows/*.yml "$dir"/.github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    if ci_workflow_runs "$f"; then
      printf 'CI: configured .github/workflows/%s\n' "${f##*/}"
      return 0
    fi
  done
  printf 'CI: none\n'
  return 1
}

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

set -u
unset CDPATH
LC_ALL=C

EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/ci-checks.log"
POLL="${CI_CHECKS_POLL:-30}"
MINUTE="${CI_CHECKS_MINUTE:-60}"
USAGE="usage: ci-checks.sh --detect [<repo dir>] | ci-checks.sh <pr> [--sha <commit>] [--wait <minutes>]"
LOG_LINES=30
ROWS_JQ='(.check_runs[]? | [(('"$CHECK_VALUE_JQ"') | ascii_upcase), .name, (.details_url // .html_url // "")]),
  (.statuses[]? | [(('"$CHECK_VALUE_JQ"') | ascii_upcase), .context, (.target_url // "")]) | @tsv'

ERRF=""
trap 'rm -f "$ERRF"; exit 0' EXIT

log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s  %s  ci-checks: %s\n' "$(date "+%F %T")" "$PWD" "$1" >> "$LOG" 2>/dev/null
  return 0
}

say() { printf '%s\n' "$1"; exit 0; }

unknown() { log "$1"; say "UNKNOWN: $1"; }

# Runs gh; the answer is in GH_OUT, and on failure GH_WHY holds its first error line.
gh_try() {
  GH_WHY=""
  if GH_OUT=$(gh "$@" 2>"$ERRF" </dev/null); then return 0; fi
  GH_WHY=$(head -n 1 "$ERRF" | tr -d '\r')
  GH_WHY=${GH_WHY:-no reason given}
  return 1
}

[ "$#" -gt 0 ] || say "UNKNOWN: $USAGE"

if [ "$1" = "--detect" ]; then
  [ "$#" -le 2 ] || say "UNKNOWN: $USAGE"
  ci_detect "${2:-.}"
  exit 0
fi

PR=$1; shift
SHA=""; WAIT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sha) [ "$#" -ge 2 ] || say "UNKNOWN: $USAGE"; SHA=$2; shift ;;
    --wait) [ "$#" -ge 2 ] || say "UNKNOWN: $USAGE"; WAIT=$2; shift ;;
    *) say "UNKNOWN: $USAGE" ;;
  esac
  shift
done
case "$PR" in ""|*[!0-9]*) say "UNKNOWN: $USAGE" ;; esac
case "$WAIT" in ""|*[!0-9]*) say "UNKNOWN: --wait takes whole minutes, got '$WAIT'" ;; esac
case "$SHA" in *[!0-9a-fA-F]*) say "UNKNOWN: --sha takes a commit hash, got '$SHA'" ;; esac

command -v gh >/dev/null 2>&1 || unknown "gh is not installed"
command -v jq >/dev/null 2>&1 || unknown "jq is not installed"
ERRF=$(mktemp) || unknown "cannot make a temp file"
export GH_PROMPT_DISABLED=1

if [ -z "$SHA" ]; then
  gh_try pr view "$PR" --json headRefOid --jq .headRefOid || unknown "gh pr view $PR failed: $GH_WHY"
  SHA=$GH_OUT
  case "$SHA" in ""|*[!0-9a-fA-F]*) unknown "gh pr view $PR gave no head commit" ;; esac
fi

# Sets ROWS: one "<VALUE>\t<name>\t<url>" line per check on the commit.
fetch_rows() {
  local runs statuses
  gh_try api --paginate "repos/{owner}/{repo}/commits/$SHA/check-runs?per_page=100" \
    || unknown "gh api check-runs of $SHA failed: $GH_WHY"
  runs=$GH_OUT
  gh_try api --paginate "repos/{owner}/{repo}/commits/$SHA/status?per_page=100" \
    || unknown "gh api status of $SHA failed: $GH_WHY"
  statuses=$GH_OUT
  ROWS=$(printf '%s\n%s\n' "$runs" "$statuses" | jq -r "$ROWS_JQ" 2>/dev/null) \
    || unknown "gh gave checks for $SHA that cannot be read"
}

# Sets CI (as ci_of does, running when nothing is registered yet but a workflow would run),
# PENDING (how many checks are still going) and RED_NAME and RED_URL (the first failure).
classify() {
  local values="" v name url
  PENDING=0; RED_NAME=""; RED_URL=""
  while IFS=$'\t' read -r v name url; do
    [ -n "$v" ] || continue
    values="${values:+$values,}$v"
    check_kind "$v"
    case "$KIND" in
      pending) PENDING=$((PENDING+1)) ;;
      red) [ -n "$RED_NAME" ] || { RED_NAME=$name; RED_URL=$url; } ;;
    esac
  done <<< "$ROWS"
  ci_of "$values"
  if [ "$CI" = none ] && ci_detect "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" >/dev/null; then
    CI=running
  fi
}

DEADLINE=$((WAIT * MINUTE))
START=$SECONDS
while :; do
  fetch_rows
  classify
  [ "$CI" = running ] && [ "$WAIT" -gt 0 ] && [ $((SECONDS - START)) -lt "$DEADLINE" ] || break
  sleep "$POLL"
done

case "$CI" in
  none) say "CI: none" ;;
  running) say "CI: running $PENDING checks" ;;
  green) say "CI: green" ;;
esac

printf 'CI: red %s%s\n' "$RED_NAME" "${RED_URL:+ $RED_URL}"
case "$RED_URL" in
  */actions/runs/[0-9]*)
    RUN_ID=${RED_URL#*/actions/runs/}
    RUN_ID=${RUN_ID%%[!0-9]*}
    if gh_try run view "$RUN_ID" --log-failed; then
      ESC=$(printf '\033')
      printf '%s\n' "$GH_OUT" | tr -d '\r' | sed "s/$ESC\\[[0-9;]*[A-Za-z]//g" | tail -n "$LOG_LINES" | sed 's/^/LOG: /'
    else
      log "gh run view $RUN_ID failed: $GH_WHY"
    fi
    ;;
esac
exit 0
