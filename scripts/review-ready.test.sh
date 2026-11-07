#!/usr/bin/env bash
# Spec tests for scripts/review-ready.sh — the review marks your own draft PR
# ready, and nobody else's. No network: a stub `gh` on PATH answers from
# $GH_VIEW and $GH_USER ("FAIL" makes a call fail), $GH_READY=FAIL fails the flip,
# and every `pr ready` it receives is written to $CALLS.
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
  "pr view") reply "${GH_VIEW:-}" ;;
  "api user") reply "${GH_USER-me}" ;;
  "pr ready")
    printf '%s\n' "$3" >> "$CALLS"
    [ "${GH_READY:-}" = FAIL ] && { echo "gh: no permission" >&2; exit 1; }
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

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

echo
printf 'review-ready.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
