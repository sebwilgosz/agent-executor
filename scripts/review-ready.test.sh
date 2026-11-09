#!/usr/bin/env bash
# Spec tests for scripts/review-ready.sh — the review marks your own draft PR
# ready, and nobody else's. No network: a stub `gh` on PATH answers from
# $GH_VIEW and $GH_USER ("FAIL" makes a call fail), $GH_READY=FAIL fails the flip,
# and every `pr ready` it receives is written to $CALLS. $GH_CI sets the checks on
# the PR's head: green, red, running, or unset for none.
#
# Run: bash scripts/review-ready.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
READY="$SELF_DIR/review-ready.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()   { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check(){ case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
BIN="$ROOT/bin"; mkdir -p "$BIN"
export EOW_HOME="$ROOT/eow"
export CALLS="$ROOT/calls"
LOG="$EOW_HOME/executor/review.log"

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
reply(){ [ "$1" = FAIL ] && { echo "gh: HTTP 502" >&2; exit 1; }; echo "A new release of gh is available" >&2; [ -n "$1" ] && printf '%s\n' "$1"; exit 0; }
case "$1 $2" in
  "pr view")
    case "$*" in *"--json headRefOid"*) echo abc123; exit 0 ;; esac
    reply "${GH_VIEW:-}" ;;
  "api --paginate")
    [ "${GH_CI:-}" = FAIL ] && { echo "gh: HTTP 502" >&2; exit 1; }
    case "$3" in
      */check-runs*)
        case "${GH_CI:-}" in
          green) echo '{"check_runs":[{"name":"test","conclusion":"success","status":"completed","details_url":"https://ci/1"}]}' ;;
          red) echo '{"check_runs":[{"name":"test","conclusion":"failure","status":"completed","details_url":"https://ci/2"}]}' ;;
          running) echo '{"check_runs":[{"name":"test","conclusion":null,"status":"in_progress","details_url":"https://ci/3"}]}' ;;
          *) echo '{"check_runs":[]}' ;;
        esac ;;
      *) echo '{"statuses":[]}' ;;
    esac
    exit 0 ;;
  "api user") reply "${GH_USER-me}" ;;
  "pr list")
    [ "${GH_LIST:-}" = FAIL ] && reply FAIL
    q=; while [ $# -gt 0 ]; do [ "$1" = --jq ] && q=$2; shift; done
    printf '%s' "${GH_LIST:-[]}" | jq -r "$q"; exit ;;
  "pr ready")
    printf '%s\n' "$3" >> "$CALLS"
    [ "${GH_READY:-}" = FAIL ] && { echo "gh: no permission" >&2; exit 1; }
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"
cd "$ROOT" || exit 1

run(){ : > "$CALLS"; bash "$READY" "$@" 2>&1; }
calls(){ paste -sd ' ' - < "$CALLS"; }

echo "review-ready.sh spec tests"

# Fields of the lookup: author, fork, draft, state.

# 1. Your own open draft is marked ready, by the name it was given.
is "your draft: marked ready"    "READY: marked ready"  "$(GH_VIEW='me false true OPEN' run 7)"
is "your draft: flipped once"    "7"                    "$(calls)"
URL=https://github.com/o/r/pull/7
is "a PR URL works too"          "READY: marked ready"  "$(GH_VIEW='me false true OPEN' run "$URL")"
is "a PR URL: flips that PR"     "$URL"                 "$(calls)"

# 2. Everything else is left as it is, and nothing is flipped.
is "already ready: skipped"      "SKIP: already ready"  "$(GH_VIEW='me false false OPEN' run 7)"
is "already ready: no flip"      ""                     "$(calls)"
is "a teammate's draft: skipped" "SKIP: PR by @mate"    "$(GH_VIEW='mate false true OPEN' run 7)"
is "a teammate's draft: no flip" ""                     "$(calls)"
is "a fork's draft: skipped"     "SKIP: fork PR by @me" "$(GH_VIEW='me true true OPEN' run 7)"
is "a fork's draft: no flip"     ""                     "$(calls)"
is "a merged PR: skipped"        "SKIP: PR is merged"   "$(GH_VIEW='me false false MERGED' run 7)"
is "a merged PR: no flip"        ""                     "$(calls)"
is "a closed draft: skipped"     "SKIP: PR is closed"   "$(GH_VIEW='me false true CLOSED' run 7)"
is "a closed draft: no flip"     ""                     "$(calls)"

# 2b. CI on the PR's head gates the flip: green or none flips, running and red don't.
is "CI green: marked ready"      "READY: marked ready"  "$(GH_CI=green GH_VIEW='me false true OPEN' run 7)"
is "CI green: flipped"           "7"                    "$(calls)"
is "CI none: marked ready"       "READY: marked ready"  "$(GH_VIEW='me false true OPEN' run 7)"
is "CI running: skipped"         "SKIP: CI still running" "$(GH_CI=running GH_VIEW='me false true OPEN' run 7)"
is "CI running: no flip"         ""                     "$(calls)"
is "CI red: skipped, named"      "SKIP: CI red: test"   "$(GH_CI=red GH_VIEW='me false true OPEN' run 7)"
is "CI red: no flip"             ""                     "$(calls)"
is "CI red, a PR URL: skipped"   "SKIP: CI red: test"   "$(GH_CI=red GH_VIEW='me false true OPEN' run "$URL")"
is "CI unreadable: not flipped"  "UNKNOWN: could not read CI on the PR's head" "$(GH_CI=FAIL GH_VIEW='me false true OPEN' run 7)"
is "CI unreadable: no flip"      ""                     "$(calls)"
is "a URL ending past the number: not flipped" "UNKNOWN: could not read CI on the PR's head" "$(GH_VIEW='me false true OPEN' run "$URL/files")"
is "a URL ending past the number: no flip" ""           "$(calls)"
is "a teammate's PR: not checked for CI" "SKIP: PR by @mate" "$(GH_CI=red GH_VIEW='mate false true OPEN' run 7)"
is "already ready: not checked for CI"   "SKIP: already ready" "$(GH_CI=red GH_VIEW='me false false OPEN' run 7)"

# 3. A failure is a plain line and a log entry, never a failed call, and it
#    never flips: not knowing whose PR it is means not touching it.
out=$(GH_VIEW=FAIL run 7); rc=$?
check "PR lookup fails: UNKNOWN"   "UNKNOWN: could not read the PR" "$out"
is    "PR lookup fails: exit 0"    "0" "$rc"
is    "PR lookup fails: no flip"   ""  "$(calls)"
check "PR lookup fails: logged"    "gh: HTTP 502" "$(cat "$LOG")"

out=$(GH_VIEW='' run 7)
check "an empty PR lookup: UNKNOWN" "UNKNOWN: could not read the PR" "$out"
is    "an empty PR lookup: no flip" "" "$(calls)"

rm -f "$LOG"
out=$(GH_VIEW='me false true OPEN' GH_USER=FAIL run 7); rc=$?
check "user lookup fails: UNKNOWN" "UNKNOWN: could not read the gh user" "$out"
is    "user lookup fails: exit 0"  "0" "$rc"
is    "user lookup fails: no flip" ""  "$(calls)"
check "user lookup fails: logged"  "gh: HTTP 502" "$(cat "$LOG")"

rm -f "$LOG"
out=$(GH_VIEW='me false true OPEN' GH_USER='' run 7); rc=$?
check "no gh user: UNKNOWN"        "UNKNOWN: could not read the gh user" "$out"
is    "no gh user: no flip"        ""  "$(calls)"

rm -f "$LOG"
out=$(GH_VIEW='me false true OPEN' GH_READY=FAIL run 7); rc=$?
check "the flip fails: UNKNOWN"    "UNKNOWN: could not mark it ready" "$out"
is    "the flip fails: exit 0"     "0" "$rc"
check "the flip fails: logged"     "gh: no permission" "$(cat "$LOG")"

out=$(run); rc=$?
check "no PR given: UNKNOWN"       "UNKNOWN: no PR given" "$out"
is    "no PR given: exit 0"        "0" "$rc"
is    "no PR given: no flip"       ""  "$(calls)"

# 4. A gh notice on stderr can't end up in a field: the stub prints one on every
#    reply, so the output above would differ. Output is exactly one line.
is "one line of output" "1" "$(GH_VIEW='me false true OPEN' run 7 | wc -l | tr -d ' ')"

# 5. A review by branch marks the branch's PR only when it saw what the PR holds:
#    its head commit, with no uncommitted change to a tracked file.
REPO="$ROOT/repo"
git init -q -b main "$REPO"
cd "$REPO" || exit 1
git config user.email me@example.com; git config user.name Me
echo one > tracked; git add tracked; git commit -q -m base
git checkout -q -b other; git commit -q --allow-empty -m other
git checkout -q -b mine main; git commit -q --allow-empty -m mine
SHA=$(git rev-parse mine); OTHER=$(git rev-parse other)
pr_at(){ # number author fork draft head
  printf '{"number":%s,"author":{"login":"%s"},"isCrossRepository":%s,"isDraft":%s,"state":"OPEN","headRefOid":"%s"}' "$1" "$2" "$3" "$4" "$5"
}
OWN="[$(pr_at 7 me false true "$SHA")]"

is "branch, no name: marked ready"    "READY: marked ready" "$(GH_LIST=$OWN run --branch)"
is "branch, no name: flips its PR"    "7"                   "$(calls)"
is "branch, named: marked ready"      "READY: marked ready" "$(GH_LIST="[$(pr_at 8 me false true "$OTHER")]" run --branch other)"
is "branch, named: flips its PR"      "8"                   "$(calls)"
is "already ready: skipped"           "SKIP: already ready" "$(GH_LIST="[$(pr_at 7 me false false "$SHA")]" run --branch)"
is "already ready: no flip"           ""                    "$(calls)"
is "a teammate's PR: skipped"         "SKIP: PR by @mate"   "$(GH_LIST="[$(pr_at 7 mate false true "$SHA")]" run --branch)"
is "a teammate's PR: no flip"         ""                    "$(calls)"

rm -f "$LOG"
is "no PR for the branch: skipped"    "SKIP: no open PR at this commit" "$(GH_LIST='[]' run --branch)"
is "no PR for the branch: no flip"    ""                    "$(calls)"
is "no PR for the branch: not logged" "no"                  "$([ -e "$LOG" ] && echo yes || echo no)"
is "unpushed commits: skipped"        "SKIP: no open PR at this commit" "$(GH_LIST="[$(pr_at 7 me false true "$OTHER")]" run --branch)"
is "unpushed commits: no flip"        ""                    "$(calls)"
is "a fork's same-named branch: skipped" "SKIP: no open PR at this commit" "$(GH_LIST="[$(pr_at 9 me true true "$SHA")]" run --branch)"
is "a fork's same-named branch: no flip" ""                 "$(calls)"
is "branch, CI red: skipped"          "SKIP: CI red: test"  "$(GH_CI=red GH_LIST=$OWN run --branch)"
is "branch, CI red: no flip"          ""                    "$(calls)"
is "branch, CI running: skipped"      "SKIP: CI still running" "$(GH_CI=running GH_LIST=$OWN run --branch)"
is "your PR after a fork's: still yours" "7"                "$(GH_LIST="[$(pr_at 9 stranger true true "$SHA"),$(pr_at 7 me false true "$SHA")]" run --branch >/dev/null; calls)"

echo two > tracked
check "uncommitted change: skipped"   "SKIP: uncommitted changes" "$(GH_LIST=$OWN run --branch)"
is    "uncommitted change: no flip"   ""                    "$(calls)"
is    "another branch ignores this tree" "READY: marked ready" "$(GH_LIST="[$(pr_at 8 me false true "$OTHER")]" run --branch other)"
git checkout -q -- tracked
echo new > untracked
is "an untracked file: still marked"  "READY: marked ready" "$(GH_LIST=$OWN run --branch)"
rm -f untracked

rm -f "$LOG"
out=$(GH_LIST=FAIL run --branch); rc=$?
check "PR list fails: UNKNOWN"        "UNKNOWN: could not read the PR" "$out"
is    "PR list fails: exit 0"         "0" "$rc"
is    "PR list fails: no flip"        ""  "$(calls)"
check "PR list fails: logged"         "gh: HTTP 502" "$(cat "$LOG")"

out=$(run --branch nosuch); rc=$?
check "no such branch: UNKNOWN"       "UNKNOWN: branch nosuch not found" "$out"
is    "no such branch: exit 0"        "0" "$rc"
is    "no such branch: no flip"       ""  "$(calls)"

echo
printf 'review-ready.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
