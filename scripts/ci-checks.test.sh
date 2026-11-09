#!/usr/bin/env bash
# Spec tests for scripts/ci-checks.sh: whether a repo has CI, and the checks on a PR's
# head commit, waiting for them if asked.
#   A. --detect, from the repo's files alone;
#   B. none, running, green, red;
#   C. only the given commit counts; checks not registered yet;
#   D. --wait, and its timeout;
#   E. failures: gh down, bad input;
#   F. the check-state parsing is shared with status.sh.
# No network: a stub `gh` on PATH answers from files in a table folder. HOME and
# EOW_HOME point at a temp dir. The poll interval and the length of a "minute" are
# set through the environment so the waits run in about a second.
#
# Run: bash scripts/ci-checks.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
CHECKS="$SELF_DIR/ci-checks.sh"

PASS=0; FAIL=0
ok()     { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()    { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()     { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute() { case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "ci-checks.test.sh needs jq"; exit 1; }

TMP=$(mktemp -d)
TMP=$(cd -P "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export EOW_HOME="$TMP/eow"
mkdir -p "$HOME"
export CI_CHECKS_POLL=0.2
export CI_CHECKS_MINUTE=1

# The stub answers, from $GH_TABLE:
#   gh pr view <n> --json headRefOid --jq ...   the head in pr-<n>
#   gh api --paginate repos/{owner}/{repo}/commits/<sha>/check-runs?...   runs-<sha>.json
#   gh api --paginate repos/{owner}/{repo}/commits/<sha>/status?...       statuses-<sha>.json
#   gh run view <id> --log-failed   logs-<id>
# A runs-<sha>.<k>.json answers the k-th call for that commit, so a wait can see a
# check finish. GH_STUB_FAIL fails every call; GH_STUB_FAIL_RUN fails the log call.
STUB="$TMP/stub"; mkdir -p "$STUB"
export GH_TABLE="$TMP/table"; mkdir -p "$GH_TABLE"
export GH_CALLS="$TMP/gh-calls"; : > "$GH_CALLS"
cat > "$STUB/gh" <<'STUB_EOF'
#!/bin/sh
echo "$*" >> "$GH_CALLS"
if [ -n "${GH_STUB_FAIL:-}" ]; then echo "$GH_STUB_FAIL" >&2; exit 1; fi
case "$1 $2" in
  "pr view")
    [ -f "$GH_TABLE/pr-$3" ] || { echo "no pull requests found for #$3" >&2; exit 1; }
    cat "$GH_TABLE/pr-$3"
    ;;
  "api --paginate")
    case "$3" in
      */commits/*/check-runs*) kind=runs; empty='{"check_runs":[]}' ;;
      */commits/*/status*) kind=statuses; empty='{"statuses":[]}' ;;
      *) echo "stub: not stubbed: $*" >&2; exit 1 ;;
    esac
    sha=${3#*/commits/}; sha=${sha%%/*}
    counter="$GH_TABLE/count-$kind-$sha"
    n=$(cat "$counter" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$counter"
    for f in "$GH_TABLE/$kind-$sha.$n.json" "$GH_TABLE/$kind-$sha.json"; do
      if [ -f "$f" ]; then cat "$f"; exit 0; fi
    done
    echo "$empty"
    ;;
  "run view")
    [ -z "${GH_STUB_FAIL_RUN:-}" ] || { echo "log not available" >&2; exit 1; }
    [ "$4" = "--log-failed" ] || { echo "stub: wrong flags: $*" >&2; exit 1; }
    cat "$GH_TABLE/logs-$3" 2>/dev/null || exit 1
    ;;
  *) echo "stub: not stubbed: $*" >&2; exit 1 ;;
esac
STUB_EOF
chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

reset() { rm -rf "$GH_TABLE"; mkdir -p "$GH_TABLE"; : > "$GH_CALLS"; rm -rf "$EOW_HOME"; }
head_of() { printf '%s\n' "$2" > "$GH_TABLE/pr-$1"; }
# run <sha> <name> <status> <conclusion> <url> [k]: a check run on a commit
run() {
  local f="$GH_TABLE/runs-$1${6:+.$6}.json"
  [ -f "$f" ] || printf '{"check_runs":[]}' > "$f"
  jq --arg n "$2" --arg s "$3" --arg c "$4" --arg u "$5" \
    '.check_runs += [{name:$n,status:$s,conclusion:(if $c == "" then null else $c end),details_url:$u,html_url:$u}]' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
# ctx <sha> <context> <state> <url>: a commit status, such as a Vercel preview
ctx() {
  local f="$GH_TABLE/statuses-$1.json"
  [ -f "$f" ] || printf '{"statuses":[]}' > "$f"
  jq --arg n "$2" --arg s "$3" --arg u "$4" '.statuses += [{context:$n,state:$s,target_url:$u}]' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
URL_RUN=https://github.com/o/r/actions/runs/777/job/1

# A repo folder with the given workflow, as a workflow file's `on:` text.
N=0
repo_with() { # <on text...>: sets R
  N=$((N+1)); R="$TMP/repo$N"
  mkdir -p "$R/.github/workflows"
  printf 'name: t\n%s\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n' "$1" > "$R/.github/workflows/ci.yml"
}
in_repo() { (cd "$R" && bash "$CHECKS" "$@" 2>&1); }

echo "ci-checks.sh spec tests"

# A. --detect.
repo_with 'on: push'
is "detect: a workflow on push" "CI: configured .github/workflows/ci.yml" "$(in_repo --detect)"
repo_with 'on:
  pull_request:
    branches: [main]'
is "detect: a workflow on pull_request" "CI: configured .github/workflows/ci.yml" "$(in_repo --detect)"
repo_with 'on: [workflow_dispatch, push]'
is "detect: push in a flow list" "CI: configured .github/workflows/ci.yml" "$(in_repo --detect)"
repo_with 'on:
  workflow_dispatch:
  schedule:
    - cron: "0 3 * * *"'
is "detect: only schedule and workflow_dispatch is none" "CI: none" "$(in_repo --detect)"
repo_with 'on:
  workflow_dispatch:
  # push:
  schedule:
    - cron: "0 3 * * *"'
is "detect: a commented-out push is none" "CI: none" "$(in_repo --detect)"
repo_with 'on:
  - release
  - push'
is "detect: push in a block list" "CI: configured .github/workflows/ci.yml" "$(in_repo --detect)"
repo_with 'on: workflow_dispatch'
is "detect: a lone workflow_dispatch is none" "CI: none" "$(in_repo --detect)"
repo_with 'on: push'
mv "$R/.github/workflows/ci.yml" "$R/.github/workflows/ci.yaml"
is "detect: the .yaml extension counts" "CI: configured .github/workflows/ci.yaml" "$(in_repo --detect)"
repo_with 'on: workflow_dispatch'
printf 'on: pull_request\njobs: {}\n' > "$R/.github/workflows/lint.yml"
is "detect: any one workflow is enough" "CI: configured .github/workflows/lint.yml" "$(in_repo --detect)"
mkdir -p "$TMP/bare"
is "detect: no workflows folder is none" "CI: none" "$(bash "$CHECKS" --detect "$TMP/bare" 2>&1)"
repo_with 'on: push'
is "detect: takes a folder argument" "CI: configured .github/workflows/ci.yml" "$(cd "$TMP" && bash "$CHECKS" --detect "$R" 2>&1)"
is "detect: needs no gh calls" "" "$(cat "$GH_CALLS")"
is "detect: sourced, ci_detect is a function other scripts call" "CI: configured .github/workflows/ci.yml" \
  "$(bash -c '. "$1"; ci_detect "$2"' _ "$CHECKS" "$R")"

# B. none, running, green, red.
reset; head_of 5 $A
repo_with 'on: workflow_dispatch'
is "none: no checks and no workflow that would run" "CI: none" "$(in_repo 5)"

reset; head_of 5 $A
repo_with 'on: pull_request'
run $A build in_progress "" $URL_RUN
run $A lint queued "" $URL_RUN
run $A docs completed success $URL_RUN
is "running: some checks still going" "CI: running 2 checks" "$(in_repo 5)"

reset; head_of 5 $A
run $A build completed success $URL_RUN
run $A lint completed skipped $URL_RUN
ctx $A vercel success https://vercel.com/x
is "green: every check passed, skipped or neutral" "CI: green" "$(in_repo 5)"

reset; head_of 5 $A
run $A build completed failure $URL_RUN
run $A lint completed success $URL_RUN
i=1; : > "$GH_TABLE/logs-777"
while [ "$i" -le 45 ]; do echo "log line $i" >> "$GH_TABLE/logs-777"; i=$((i+1)); done
out=$(in_repo 5)
is "red: names the failing check and its url" "CI: red build $URL_RUN" "$(printf '%s\n' "$out" | head -1)"
is "red: at most 30 log lines, the last ones" "30" "$(printf '%s\n' "$out" | grep -c '^LOG: ')"
is "red: the last log line is the failing log's last" "LOG: log line 45" "$(printf '%s\n' "$out" | tail -1)"
is "red: the first log line shown is the 16th" "LOG: log line 16" "$(printf '%s\n' "$out" | sed -n 2p)"
check "red: the log came from the run in the url" "run view 777 --log-failed" "$(cat "$GH_CALLS")"

reset; head_of 5 $A
run $A build completed failure $URL_RUN
printf 'one\ntwo\n' > "$GH_TABLE/logs-777"
is "red: a short log is shown whole" "CI: red build $URL_RUN
LOG: one
LOG: two" "$(in_repo 5)"

reset; head_of 5 $A
ctx $A vercel failure https://vercel.com/o/r/deploy/9
is "red from a check that is not an Actions run: name and url, no log" "CI: red vercel https://vercel.com/o/r/deploy/9" "$(in_repo 5)"
refute "red from a non-Actions check: no run view" "run view" "$(cat "$GH_CALLS")"

reset; head_of 5 $A
run $A build completed timed_out $URL_RUN
run $A deploy completed failure https://example.com/not-actions
out=$(in_repo 5)
is "red: a timed-out check is red too" "CI: red build $URL_RUN" "$(printf '%s\n' "$out" | head -1)"

reset; head_of 5 $A
run $A build completed failure $URL_RUN
run $A lint in_progress "" $URL_RUN
check "red wins over running" "CI: red build" "$(in_repo 5)"

reset; head_of 5 $A
run $A build completed failure $URL_RUN
out=$(GH_STUB_FAIL_RUN=1 in_repo 5)
is "red: a log that cannot be fetched leaves no log lines" "CI: red build $URL_RUN" "$out"

# C. Only the given commit counts.
reset; head_of 5 $B
run $A build completed success $URL_RUN
repo_with 'on: pull_request'
out=$(in_repo 5)
is "stale green: a green run on an older head is not green" "CI: running 0 checks" "$out"
repo_with 'on: workflow_dispatch'
is "stale green: and with no workflow that would run, none" "CI: none" "$(in_repo 5)"

reset; head_of 5 $B
run $A build completed failure $URL_RUN
run $B build completed success $URL_RUN
is "the head's own checks are what count, not an older red" "CI: green" "$(in_repo 5)"

reset; head_of 5 $B
run $A build completed success $URL_RUN
is "--sha picks the commit: its green" "CI: green" "$(in_repo 5 --sha $A)"
is "--sha picks the commit: the head has none" "CI: none" "$(cd "$TMP/bare" && bash "$CHECKS" 5 2>&1)"
check "--sha asks for that commit" "commits/$A/" "$(cat "$GH_CALLS")"

reset; head_of 5 $A
repo_with 'on: push'
is "not registered yet: a workflow that runs on push reads running" "CI: running 0 checks" "$(in_repo 5)"
repo_with 'on: pull_request'
is "not registered yet: a workflow that runs on pull_request reads running" "CI: running 0 checks" "$(in_repo 5)"

# D. --wait.
reset; head_of 5 $A
repo_with 'on: pull_request'
run $A build in_progress "" $URL_RUN 1
run $A build in_progress "" $URL_RUN 2
run $A build completed success $URL_RUN 3
SECONDS=0
out=$(in_repo 5 --wait 5)
is "wait: returns green as soon as the checks finish" "CI: green" "$out"
[ "$SECONDS" -lt 5 ] && ok "wait: it did not wait out the whole time" || bad "wait: it did not wait out the whole time" "took $SECONDS s"

reset; head_of 5 $A
repo_with 'on: pull_request'
run $A build in_progress "" $URL_RUN 1
run $A build completed failure $URL_RUN 2
printf 'boom\n' > "$GH_TABLE/logs-777"
is "wait: returns red when a check fails" "CI: red build $URL_RUN
LOG: boom" "$(in_repo 5 --wait 5)"

reset; head_of 5 $A
repo_with 'on: pull_request'
run $A build in_progress "" $URL_RUN
SECONDS=0
out=$(in_repo 5 --wait 2)
is "wait: runs out and reports running" "CI: running 1 checks" "$out"
[ "$SECONDS" -ge 2 ] && [ "$SECONDS" -lt 10 ] && ok "wait: it waited its minutes" || bad "wait: it waited its minutes" "took $SECONDS s"

reset; head_of 5 $A
repo_with 'on: pull_request'
out=$(in_repo 5)
is "no --wait: running is answered at once" "CI: running 0 checks" "$out"
is "no --wait: one lookup of the runs" "1" "$(grep -c 'check-runs' "$GH_CALLS")"

reset; head_of 5 $A
repo_with 'on: pull_request'
run $A build in_progress "" $URL_RUN 1
run $A build completed success $URL_RUN 2
is "wait: checks not registered yet are waited for too" "CI: green" "$(in_repo 5 --wait 3)"

# E. Failures.
reset; head_of 5 $A
repo_with 'on: push'
out=$(GH_STUB_FAIL="HTTP 502 bad gateway" in_repo 5)
check "gh failing: UNKNOWN with the reason" "UNKNOWN: " "$out"
check "gh failing: the reason is gh's" "502" "$out"
is "gh failing: one line" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
out=$(cd "$R" && GH_STUB_FAIL=x bash "$CHECKS" 5 >/dev/null 2>&1; echo "rc=$?")
is "gh failing: exit 0" "rc=0" "$out"
check "gh failing: logged" "ci-checks" "$(cat "$EOW_HOME/executor/ci-checks.log" 2>/dev/null)"

reset
out=$(in_repo 99)
check "an unknown PR: UNKNOWN" "UNKNOWN: " "$out"

reset; head_of 5 $A
EMPTY="$TMP/nogh"; mkdir -p "$EMPTY"
ln -s "$(command -v jq)" "$EMPTY/jq"
for t in bash env dirname cat date mkdir printf sleep tr head tail sed awk grep sort wc rm mktemp; do
  p=$(command -v "$t") && ln -sf "$p" "$EMPTY/$t"
done
out=$(cd "$R" && PATH="$EMPTY" bash "$CHECKS" 5 2>&1)
check "gh missing: UNKNOWN" "UNKNOWN: gh" "$out"

out=$(in_repo)
check "no arguments: usage in an UNKNOWN line" "UNKNOWN: usage" "$out"
out=$(in_repo abc)
check "a PR that is not a number: UNKNOWN" "UNKNOWN: " "$out"
out=$(in_repo 5 --wait soon)
check "a wait that is not a number: UNKNOWN" "UNKNOWN: " "$out"
out=$(in_repo 5 --what)
check "an unknown flag: UNKNOWN" "UNKNOWN: " "$out"

# F. One parser for check states, shared with status.sh.
STATUS_SRC=$(cat "$SELF_DIR/status.sh")
CHECKS_SRC=$(cat "$CHECKS")
STATE_SRC=$(cat "$SELF_DIR/ci-state.sh" 2>/dev/null)
check "shared: status.sh sources ci-state.sh" 'ci-state.sh' "$STATUS_SRC"
check "shared: ci-checks.sh sources ci-state.sh" 'ci-state.sh' "$CHECKS_SRC"
refute "shared: status.sh no longer holds ci_of" 'ci_of() {' "$STATUS_SRC"
refute "shared: ci-checks.sh does not hold its own ci_of" 'ci_of() {' "$CHECKS_SRC"
check "shared: ci-state.sh holds it" 'ci_of() {' "$STATE_SRC"

echo
printf 'ci-checks.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
