#!/usr/bin/env bash
# Spec tests for scripts/status.sh: what is yours to merge, what waits on you and
# what is still moving, across every repo.
#   A. the output's shape;
#   B. each bucket;
#   C. GitHub's state against a stale plan line;
#   D. the order: repos, plans, stacks;
#   E. the edges: no plans, STOP, gh missing or failing, local and malformed plans;
#   F. the repo and host of a lookup, and a branch-only item;
#   G. lookups run in parallel, at most 8 at once;
#   H. read-only, always exit 0, one parser.
# No network: a stub `gh` on PATH answers from a table, in the JSON gh prints, and
# applies status.sh's --jq with a real jq. HOME and EOW_HOME point at a temp dir. It
# runs the script with /bin/bash where there is one: macOS's is bash 3.2.
#
# Run: bash scripts/status.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
STATUS="$SELF_DIR/status.sh"
SHELL_BIN=bash
[ -x /bin/bash ] && SHELL_BIN=/bin/bash

PASS=0; FAIL=0
ok()     { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()    { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()     { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute() { case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "status.test.sh needs jq: its stub gh applies --jq with it"; exit 1; }

TMP=$(mktemp -d)
TMP=$(cd -P "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export EOW_HOME="$TMP/eow"
unset EXECUTOR_PLANS GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
mkdir -p "$HOME"
PLANS="$EOW_HOME/executor/plans"
LOG="$EOW_HOME/executor/status.log"
EM=$'\xe2\x80\x94'

# The stub answers `gh pr view <n> --repo <repo> --json ... --jq <expr>`. A table line
# is: <repo> <n> <state> <isDraft> <checks>, the checks comma-separated, each one
#   run:<conclusion>  a finished check run
#   now:<status>      a check run still going
#   ctx:<state>       a commit status
# or - for none. GH_STUB_FAIL fails every call; GH_STUB_FAIL_REPO fails one repo's.
STUB="$TMP/stub"; mkdir -p "$STUB"
export GH_TABLE="$TMP/gh-table"; : > "$GH_TABLE"
export GH_CALLS="$TMP/gh-calls"; : > "$GH_CALLS"
export GH_RUNNING="$TMP/gh-running"; mkdir -p "$GH_RUNNING"
export GH_PEAKS="$TMP/gh-peaks"; : > "$GH_PEAKS"
cat > "$STUB/gh" <<'STUB_EOF'
#!/bin/sh
echo "$*" >> "$GH_CALLS"
if [ -n "${GH_STUB_SLEEP:-}" ]; then
  : > "$GH_RUNNING/$$"
  ls "$GH_RUNNING" | wc -l | tr -d ' ' >> "$GH_PEAKS"
  sleep "$GH_STUB_SLEEP"
  rm -f "$GH_RUNNING/$$"
fi
if [ -n "${GH_STUB_FAIL:-}" ]; then echo "$GH_STUB_FAIL" >&2; echo "second line of noise" >&2; exit 1; fi
[ "$1 $2" = "pr view" ] || { echo "stub: not stubbed: $*" >&2; exit 1; }
n=$3; shift 3; repo=""; fields=""; expr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=$2 ;;
    --json) fields=$2 ;;
    --jq) expr=$2 ;;
  esac
  shift
done
if [ -n "${GH_STUB_FAIL_REPO:-}" ] && [ "$repo" = "$GH_STUB_FAIL_REPO" ]; then echo "cannot reach $repo" >&2; exit 1; fi
[ "$fields" = "state,isDraft,statusCheckRollup" ] || { echo "stub: wrong fields: $fields" >&2; exit 1; }
line=$(awk -v r="$repo" -v n="$n" '$1==r && $2==n' "$GH_TABLE")
[ -n "$line" ] || { echo "no pull requests found for #$n in $repo" >&2; exit 1; }
set -- $line
state=$3; draft=$4; checks=$5
rollup=""
if [ "$checks" != "-" ]; then
  old_ifs=$IFS; IFS=,
  for c in $checks; do
    v=${c#*:}
    case "$c" in
      run:*) o="{\"__typename\":\"CheckRun\",\"name\":\"state: FAILURE\",\"status\":\"COMPLETED\",\"conclusion\":\"$v\"}" ;;
      now:*) o="{\"__typename\":\"CheckRun\",\"name\":\"ci\",\"status\":\"$v\",\"conclusion\":\"\"}" ;;
      ctx:*) o="{\"__typename\":\"StatusContext\",\"context\":\"ci\",\"state\":\"$v\"}" ;;
    esac
    rollup="${rollup:+$rollup,}$o"
  done
  IFS=$old_ifs
fi
json="{\"state\":\"$state\",\"isDraft\":$draft,\"statusCheckRollup\":[$rollup]}"
if [ -n "$expr" ]; then printf '%s' "$json" | jq -r "$expr"; else printf '%s\n' "$json"; fi
STUB_EOF
chmod +x "$STUB/gh"
cat > "$STUB/ssh" <<'STUB_EOF'
#!/bin/sh
[ "$1" = "-G" ] || exit 1
case "$2" in work-alias) h=ghe.example.com ;; *) h=$2 ;; esac
printf 'user git\nhostname %s\n' "$h"
STUB_EOF
chmod +x "$STUB/ssh"
export PATH="$STUB:$PATH"

status() { (cd "$TMP" && "$SHELL_BIN" "$STATUS" "$@" 2>&1); }
prs()    { printf '%s\n' "$@" > "$GH_TABLE"; }
reset()  { rm -rf "$PLANS" "$LOG"; : > "$GH_TABLE"; : > "$GH_CALLS"; }

# plan <org/repo> <file title> <line>...: a plan, its lines as given.
plan() {
  local f="$PLANS/$1/$2.md"; shift 2
  mkdir -p "$(dirname "$f")"
  { printf '# Build: Sample\nSpec: [Sample](https://example.com/spec)\n\n'
    printf '%s\n' "$@"; } > "$f"
  printf '%s' "$f"
}
item() { printf -- '- [%s] %s %s [part](https://example.com/p) %s %s' "$1" "$2" "$EM" "$EM" "$3"; }

# bucket <heading> <output>: the lines under one bucket, up to the next heading.
bucket() {
  printf '%s\n' "$2" | awk -v h="    $1" '
    $0 == h { on = 1; next }
    /^    [A-Z]/ || /^  [^ ]/ || /^[^ ]/ { on = 0 }
    on { print }'
}

echo "status.sh spec tests"

# A. The shape.
reset
prs "sebwilgosz/agent-executor 31 OPEN false run:SUCCESS" "sebwilgosz/agent-executor 32 OPEN false run:FAILURE"
plan sebwilgosz/agent-executor "2026-11-07 - review depth and status" \
  '## Stack A: docs' "$(item x 'Docs drift' 'PR #31 ✅ ready')" "$(item ' ' Later '')" \
  '## Stack B: status' "$(item ' ' Status 'PR #32')" >/dev/null
is "the table, as a whole" "EXECUTOR STATUS

sebwilgosz/agent-executor
  2026-11-07 - review depth and status
    MERGE NOW
      #31  Docs drift                 Stack A 1/2   CI green   review ready
    WAITING ON YOU
      #32  Status                     Stack B 1/1   CI red
    MOVING
      Stack A: 1 not started" "$(status)"
"$SHELL_BIN" "$STATUS" >/dev/null 2>&1; is "the table: exit 0" "0" "$?"
is "the table: the exact lookup, one per PR" "2" "$(grep -c -- '^pr view 3[12] --repo sebwilgosz/agent-executor --json state,isDraft,statusCheckRollup' "$GH_CALLS")"

reset
prs "acme/web 1 OPEN false run:SUCCESS"
plan acme/web "2026-01-01 - em" '## Stack A: a' "$(item x "A${EM}B and a name that runs well past forty characters here" 'PR #1 ✅ ready')" >/dev/null
OUT=$(status)
check "a long name: cut at 40, em dash as -" "#1   A-B and a name that runs well past forty  Stack A 1/1" "$OUT"
refute "no em dash anywhere" "$EM" "$OUT"

reset
prs "acme/web 1 OPEN false run:SUCCESS"
LONG=$(printf 'é%.0s' 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5)
CUT=$(printf 'é%.0s' 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0)
plan acme/web "2026-01-01 - utf" '## Stack A: a' "$(item x "$LONG" 'PR #1 ✅ ready')" >/dev/null
OUT=$(status)
check "a long name: 40 characters, not bytes" "#1   $CUT  Stack A" "$OUT"
printf '%s' "$OUT" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 && ok "a long name: cut between characters" || bad "a long name: cut between characters" "$OUT"

reset
prs "acme/web 1 OPEN false run:SUCCESS" "acme/web 2 OPEN false run:SUCCESS"
plan acme/web "2026-01-01 - align" '## Stack A: a' "$(item x 'Aé' 'PR #1 ✅ merged')" '## Stack B: b' "$(item x 'Ae' 'PR #2 ✅ ready')" >/dev/null
OUT=$(bucket "MERGE NOW" "$(status)")
is "columns line up on characters" "      #1   Aé                         Stack A 1/1   CI green   review ready
      #2   Ae                         Stack B 1/1   CI green   review ready" "$OUT"

# B. Each bucket.
reset
prs "acme/web 1 MERGED false -" "acme/web 2 CLOSED false -" "acme/web 3 OPEN false run:SUCCESS" "acme/web 4 OPEN false now:IN_PROGRESS" \
    "acme/web 5 OPEN false -"
plan acme/web "2026-01-01 - merge" \
  '## Stack A: a' "$(item x One 'PR #1 ✅ merged')" "$(item ' ' Two 'PR #2 ❌ dropped')" "$(item x Three 'PR #3 ✅ ready')" \
  '## Stack B: b' "$(item x Four 'PR #4 ✅ ready')" \
  '## Stack C: c' "$(item x Five 'PR #5 ✅ ready')" >/dev/null
OUT=$(status)
M=$(bucket "MERGE NOW" "$OUT")
check "merge now: everything below merged or closed" "#3   Three" "$M"
check "merge now: merged and closed count in the position" "Stack A 3/3   CI green     review ready" "$M"
check "merge now: CI running is not red" "#4   Four" "$M"
check "CI running" "Stack B 1/1   CI running" "$M"
check "CI none" "Stack C 1/1   CI none" "$M"
refute "merged is not printed" "One" "$OUT"
refute "closed is not printed" "Two" "$OUT"
refute "an empty bucket isn't printed" "WAITING ON YOU" "$OUT"
refute "an empty bucket isn't printed, unknown" "UNKNOWN" "$OUT"

reset
prs "acme/web 3 OPEN true run:SUCCESS" "acme/web 4 OPEN false run:SUCCESS" "acme/web 5 OPEN false run:FAILURE" "acme/web 9 OPEN false -"
plan acme/web "2026-01-01 - wait" \
  '## Stack A: a' "$(item ' ' Asks "⛔ is PR #9 the${EM}right one?")" \
  '## Stack B: b' "$(item ' ' Finding "PR #3 ❌ 2 Critical: the login${EM}leak")" \
  '## Stack C: c' "$(item x ReadyFinding "PR #4 ❌ still open")" \
  '## Stack D: d' "$(item x Red 'PR #5 ✅ ready')" >/dev/null
OUT=$(status)
W=$(bucket "WAITING ON YOU" "$OUT")
check "a blocked item waits, with its question after the row" "Asks" "$W"
is "the question sits on its own line, under the row" "        is PR #9 the-right one?" "$(printf '%s\n' "$W" | sed -n 2p)"
check "a blocked item: no number" "      -    Asks" "$W"
check "a draft at ❌: open findings" "#3   Finding                    Stack B 1/1   CI green   review open findings" "$W"
check "a draft at ❌: what is open" "        2 Critical: the login-leak" "$W"
check "a ready PR at ❌: GitHub can't overrule the verdict" "#4   ReadyFinding" "$W"
check "a ready PR at ❌: what is open" "still open" "$W"
check "a ready PR with red CI" "#5   Red                        Stack D 1/1   CI red     review ready" "$W"
refute "a question's PR is not looked up" "pr view 9" "$(cat "$GH_CALLS")"

reset
prs "acme/web 1 OPEN true run:SUCCESS" "acme/web 2 OPEN false run:SUCCESS" "acme/web 3 OPEN true -" "acme/web 4 OPEN false run:SUCCESS" "acme/web 5 OPEN false run:SUCCESS" "acme/web 6 OPEN false run:SUCCESS"
plan acme/web "2026-01-01 - moving" \
  '## Stack A: a' "$(item ' ' Reviewing 'PR #1 ⏳ in review')" "$(item x Above 'PR #2 ✅ ready')" \
  '## Stack B: b' "$(item ' ' Builds '🔨 building')" "$(item ' ' Rest '')" "$(item ' ' More '')" \
  '## Stack C: c' "$(item x StaleDraft 'PR #3 ✅ ready')" \
  '## Stack D: d' "$(item ' ' Asks '⛔ why?')" "$(item x OverBlocked 'PR #4 ✅ ready')" \
  '## Stack E: e' "$(item ' ' NotYet '')" "$(item x OverNotStarted 'PR #5 ✅ ready')" >/dev/null
OUT=$(status)
V=$(bucket "MOVING" "$OUT")
check "a draft at ⏳" "#1   Reviewing                  Stack A 1/2   CI green   review in review" "$V"
check "a ready PR waiting on the one below" "#2   Above                      Stack A 2/2   CI green   review ready" "$V"
check "a hammer, no PR" "      -    Builds                     Stack B 1/3   CI none    review none" "$V"
check "not started: a count per stack" "      Stack B: 2 not started" "$V"
check "a draft saying ✅ ready is moving" "#3   StaleDraft" "$V"
check "a ready PR over a blocked item waits" "#4   OverBlocked" "$V"
check "a ready PR over a not-started item waits" "#5   OverNotStarted" "$V"
check "not started below: counted too" "      Stack E: 1 not started" "$V"
refute "a stack with none not started says nothing" "Stack A: " "$V"
refute "moving: no merge now" "MERGE NOW" "$OUT"

reset
prs "acme/web 1 OPEN false now:IN_PROGRESS" "acme/web 2 OPEN true run:SUCCESS" "acme/web 3 OPEN false run:FAILURE" "acme/web 4 OPEN true run:FAILURE"
plan acme/web "2026-01-01 - answers" \
  '## Stack A: a' "$(item ' ' Follows 'PR #1 ⏳ in review')" \
  '## Stack B: b' "$(item ' ' Below 'PR #2 ⏳ in review')" "$(item x RedAndBlocked 'PR #3 ✅ ready')" \
  '## Stack C: c' "$(item ' ' RedDraft 'PR #4 ⏳ in review')" >/dev/null
OUT=$(status)
check "a ready PR at ⏳ follows GitHub" "#1   Follows                    Stack A 1/1   CI running   review in review" "$(bucket "MERGE NOW" "$OUT")"
check "red CI and blocked by the PR below waits on you" "#3   RedAndBlocked" "$(bucket "WAITING ON YOU" "$OUT")"
check "a draft with red CI still moves" "#4   RedDraft" "$(bucket "MOVING" "$OUT")"

reset
prs "acme/web 1 OPEN false -" "acme/web 3 OPEN false run:SUCCESS" "acme/web 4 OPEN false run:SUCCESS" "acme/web 5 OPEN false run:FAILURE" "acme/web 6 OPEN true run:SUCCESS" "acme/web 7 OPEN false run:SUCCESS"
plan acme/web "2026-01-01 - unknown" \
  '## Stack A: a' "$(item ' ' Gone 'PR #99 ⏳ in review')" "$(item x Above 'PR #3 ✅ ready')" "$(item x Top 'PR #4 ✅ ready')" \
  "$(item x RedTop 'PR #5 ✅ ready')" "$(item ' ' DraftTop 'PR #6 ⏳ in review')" \
  '## Stack B: b' "$(item x Fine 'PR #7 ✅ ready')" >/dev/null
OUT=$(status)
U=$(bucket "UNKNOWN" "$OUT")
check "one failed lookup: unknown, with its number" "#99  Gone                       Stack A 1/5" "$U"
check "one failed lookup: why, after the row" "        gh pr view 99 failed: no pull requests found for #99 in acme/web" "$U"
check "the item above an unreadable one: unknown" "#3   Above" "$U"
check "and every item above that" "#4   Top" "$U"
check "and it says why" "the item below can't be read" "$U"
check "the rest of the plan prints" "#7   Fine" "$(bucket "MERGE NOW" "$OUT")"
check "red CI above an unreadable one still waits on you" "#5   RedTop" "$(bucket "WAITING ON YOU" "$OUT")"
check "a draft above an unreadable one still moves" "#6   DraftTop" "$(bucket "MOVING" "$OUT")"
check "one failed lookup: logged" "gh pr view 99 failed" "$(cat "$LOG")"

reset
prs "acme/web 1 OPEN false run:SUCCESS" "acme/web 2 OPEN false ctx:SUCCESS" "acme/web 3 OPEN false ctx:FAILURE" "acme/web 4 OPEN false ctx:ERROR" \
    "acme/web 5 OPEN false ctx:PENDING" "acme/web 6 OPEN false run:SUCCESS,now:QUEUED" "acme/web 7 OPEN false now:IN_PROGRESS,run:FAILURE" \
    "acme/web 8 OPEN false run:NEUTRAL,run:SKIPPED" "acme/web 10 OPEN false run:TIMED_OUT" "acme/web 11 OPEN false run:CANCELLED" \
    "acme/web 12 OPEN false run:ACTION_REQUIRED" "acme/web 13 OPEN false run:STARTUP_FAILURE"
LINES=()
for n in 1 2 3 4 5 6 7 8 10 11 12 13; do
  LINES[${#LINES[@]}]="## Stack $n: s"
  LINES[${#LINES[@]}]=$(item x "Pr$n" "PR #$n ✅ ready")
done
plan acme/web "2026-01-01 - ci" "${LINES[@]}" >/dev/null
OUT=$(status)
ci() { printf '%s\n' "$OUT" | grep -F "Pr$1 " | sed 's/.*CI \([a-z]*\).*/\1/'; }
is "CI: a passed check run" "green" "$(ci 1)"
is "CI: a passed commit status" "green" "$(ci 2)"
is "CI: a failed commit status" "red" "$(ci 3)"
is "CI: a commit status in error" "red" "$(ci 4)"
is "CI: a pending commit status" "running" "$(ci 5)"
is "CI: one still queued" "running" "$(ci 6)"
is "CI: red wins over running" "red" "$(ci 7)"
is "CI: neutral and skipped are green" "green" "$(ci 8)"
is "CI: timed out" "red" "$(ci 10)"
is "CI: cancelled" "red" "$(ci 11)"
is "CI: action required" "red" "$(ci 12)"
is "CI: startup failure" "red" "$(ci 13)"

# C. A stale plan line.
reset
prs "acme/web 1 MERGED false -" "acme/web 2 CLOSED false -" "acme/web 3 OPEN false run:SUCCESS" "acme/web 4 MERGED false -" "acme/web 5 OPEN true -"
plan acme/web "2026-01-01 - stale" \
  '## Stack A: a' "$(item ' ' SaysReview 'PR #1 ⏳ in review')" "$(item x SaysReady 'PR #2 ✅ ready')" "$(item x SaysMerged 'PR #3 ✅ merged')" \
  '## Stack B: b' "$(item ' ' SaysFindings 'PR #4 ❌ open')" \
  '## Stack C: c' "$(item x SaysMergedDraft 'PR #5 ✅ merged')" >/dev/null
OUT=$(status)
refute "says in review, GitHub says merged: not printed" "SaysReview" "$OUT"
refute "says ready, GitHub says closed: not printed" "SaysReady" "$OUT"
refute "says ❌, GitHub says merged: not printed" "SaysFindings" "$OUT"
check "says merged, GitHub says open: merge now" "#3   SaysMerged" "$(bucket "MERGE NOW" "$OUT")"
check "says merged, GitHub says draft: moving" "#5   SaysMergedDraft" "$(bucket "MOVING" "$OUT")"

reset
prs "acme/web 1 MERGED false -" "acme/web 2 CLOSED false -"
P=$(plan acme/web "2026-01-01 - unmarked" '## Stack A: a' "$(item x One 'PR #1 ✅ ready')" "$(item ' ' Two 'PR #2 ⏳ in review')")
OUT=$(status)
is "all merged or closed, not marked: its last line" "    finished, not marked: run scripts/plan-sweep.sh" "$(printf '%s\n' "$OUT" | tail -1)"
refute "the finished line never marks" "Status: done" "$(cat "$P")"
prs "acme/web 1 MERGED false -"
refute "one unreadable item: not finished" "finished, not marked" "$(status)"

reset
prs "acme/web 1 MERGED false -"
P=$(plan acme/web "2026-01-01 - marked" '## Stack A: a' "$(item x One 'PR #1 ✅ merged')")
{ printf 'Status: done 2026-01-02\n'; cat "$P"; } > "$P.new"; mv "$P.new" "$P"
is "a marked plan isn't shown at all" "No live plans in $PLANS" "$(status)"

# D. The order.
reset
prs "zeta/app 1 OPEN false run:SUCCESS" "Beta/app 1 OPEN false run:SUCCESS" "acme/web 1 OPEN false run:SUCCESS" "acme/web 2 OPEN false run:SUCCESS" "acme/web 3 OPEN false run:SUCCESS"
plan zeta/app "2026-01-01 - z" '## S: s' "$(item x Z 'PR #1 ✅ ready')" >/dev/null
plan Beta/app "2026-01-01 - b" '## S: s' "$(item x B 'PR #1 ✅ ready')" >/dev/null
plan acme/web "2026-01-01 - older" '## S: s' "$(item x Old 'PR #1 ✅ ready')" >/dev/null
plan acme/web "2026-03-01 - newer" '## S: s' "$(item x New 'PR #2 ✅ ready')" >/dev/null
plan acme/web "2026-02-01 - middle" '## S: s' "$(item x Mid 'PR #3 ✅ ready')" >/dev/null
OUT=$(status)
is "repos alphabetical, whatever the case; plans newest first" "acme/web
2026-03-01 - newer
2026-02-01 - middle
2026-01-01 - older
Beta/app
2026-01-01 - b
zeta/app
2026-01-01 - z" "$(printf '%s\n' "$OUT" | grep -E '^[^ ]+/[^ ]+$|^  [0-9]' | sed 's/^ *//')"
is "one blank line between repos" "4" "$(printf '%s\n' "$OUT" | grep -c '^$' | awk '{print $1+1}')"

reset
prs "acme/web 1 OPEN true run:SUCCESS" "acme/web 2 OPEN true run:SUCCESS" "acme/web 3 OPEN true run:SUCCESS" "acme/web 4 OPEN true run:SUCCESS"
plan acme/web "2026-01-01 - stacks" \
  '## Stack B: b' "$(item ' ' First 'PR #4 ⏳')" "$(item ' ' Second 'PR #2 ⏳')" \
  '## Stack A: a' "$(item ' ' Third 'PR #3 ⏳')" "$(item ' ' Fourth 'PR #1 ⏳')" >/dev/null
is "each stack bottom-up, in the plan's order" "#4
#2
#3
#1" "$(bucket "MOVING" "$(status)" | awk '{print $1}')"

reset
prs "acme/web 1 OPEN false run:SUCCESS"
plan acme/web "2026-01-01 - flat" "$(item x NoHeading 'PR #1 ✅ ready')" >/dev/null
check "no heading above an item: still a row" "#1   NoHeading                  Plan 1/1" "$(status)"

# E. The edges.
reset
is "no live plans" "No live plans in $PLANS" "$(status)"
[ -e "$PLANS" ] && bad "no live plans: creates no folder" "$PLANS exists" || ok "no live plans: creates no folder"
is "a STOP: as it is" "STOP: the plans folder must be absolute: rel/plans" "$(EXECUTOR_PLANS=rel/plans status)"
EXECUTOR_PLANS=rel/plans "$SHELL_BIN" "$STATUS" >/dev/null 2>&1; is "a STOP: exit 0" "0" "$?"
check "an argument: a plain note" "STOP: " "$(status --nope)"
"$SHELL_BIN" "$STATUS" --nope >/dev/null 2>&1; is "an argument: exit 0" "0" "$?"

reset
prs "acme/web 1 OPEN false run:SUCCESS" "acme/web 2 OPEN false run:SUCCESS" "zeta/app 1 OPEN false run:SUCCESS"
plan acme/web "2026-01-01 - one" '## S: s' "$(item x One 'PR #1 ✅ ready')" >/dev/null
plan acme/web "2026-01-02 - two" '## S: s' "$(item x Two 'PR #2 ✅ ready')" >/dev/null
plan zeta/app "2026-01-01 - three" '## S: s' "$(item x Three 'PR #1 ✅ ready')" >/dev/null
OUT=$(GH_STUB_FAIL="error connecting to api.github.com" status)
is "offline: one line per repo, its plans still named" "EXECUTOR STATUS

acme/web
  UNKNOWN: gh pr view 2 failed: error connecting to api.github.com
  2026-01-02 - two
  2026-01-01 - one

zeta/app
  UNKNOWN: gh pr view 1 failed: error connecting to api.github.com
  2026-01-01 - three" "$OUT"
GH_STUB_FAIL="x" "$SHELL_BIN" "$STATUS" >/dev/null 2>&1; is "offline: exit 0" "0" "$?"
check "offline: logged" "error connecting to api.github.com" "$(cat "$LOG")"
OUT=$(GH_STUB_FAIL="To get started with GitHub CLI, please run:  gh auth login" status)
check "not signed in: says so" "UNKNOWN: gh pr view 2 failed: To get started with GitHub CLI" "$OUT"

OUT=$(GH_STUB_FAIL_REPO="acme/web" status)
check "one repo's lookups all failing: its line" "UNKNOWN: gh pr view" "$(printf '%s\n' "$OUT" | sed -n '/^acme/,/^$/p')"
check "one repo's lookups all failing: its plans named" "2026-01-02 - two" "$(printf '%s\n' "$OUT" | sed -n '/^acme/,/^$/p')"
check "one repo's lookups all failing: other repos carry on" "#1   Three" "$(printf '%s\n' "$OUT" | sed -n '/^zeta/,$p')"

NOGH="$TMP/nogh"; mkdir -p "$NOGH"
for t in bash sh git mkdir mktemp date dirname rm sort uniq xargs cat head tail awk sed tr wc ls ssh; do
  p=$(command -v "$t") && ln -sf "$p" "$NOGH/$t"
done
OUT=$(cd "$TMP" && PATH="$NOGH" "$SHELL_BIN" "$STATUS" 2>&1); RC=$?
check "gh missing: says so, per repo" "UNKNOWN: gh is not installed" "$OUT"
is "gh missing: one line per repo" "2" "$(printf '%s\n' "$OUT" | grep -c 'UNKNOWN:')"
check "gh missing: plans still named" "2026-01-01 - three" "$OUT"
is "gh missing: exit 0" "0" "$RC"
check "gh missing: logged" "gh is not installed" "$(cat "$LOG")"

reset
plan local/scratch "2026-01-01 - text" \
  '## Stack A: a' "$(item x Merged 'branch a ✅ merged')" "$(item x Ready 'branch b ✅ ready')" "$(item ' ' After 'branch c ⏳ in review')" \
  '## Stack B: b' "$(item ' ' Asks '⛔ which one?')" "$(item ' ' Rest '')" \
  '## Stack C: c' "$(item ' ' Finding 'branch d ❌ one open')" "$(item ' ' Build 'branch e 🔨 building')" \
  '## Stack D: d' "$(item x WithNumber 'PR #4 ✅ ready')" >/dev/null
OUT=$(GH_STUB_FAIL="must not be called" status)
is "a local plan: no lookups" "" "$(cat "$GH_CALLS")"
check "a local plan: shown under its name" "local/scratch" "$OUT"
M=$(bucket "MERGE NOW" "$OUT")
check "a local plan: ready, from the text" "-    Ready                      Stack A 2/3   CI none   review ready" "$M"
check "a local plan: a PR number is shown" "#4   WithNumber" "$M"
check "a local plan: waits from the text" "which one?" "$(bucket "WAITING ON YOU" "$OUT")"
check "a local plan: ❌ from the text" "one open" "$(bucket "WAITING ON YOU" "$OUT")"
check "a local plan: in review" "After" "$(bucket "MOVING" "$OUT")"
check "a local plan: hammer" "Build" "$(bucket "MOVING" "$OUT")"
check "a local plan: not started" "Stack B: 1 not started" "$(bucket "MOVING" "$OUT")"
refute "a local plan: merged isn't printed" "Merged" "$OUT"
refute "a local plan: never a repo-level UNKNOWN" "UNKNOWN" "$OUT"

reset
plan local/scratch "2026-01-01 - gone" '## Stack A: a' "$(item x Merged 'branch a ✅ merged')" >/dev/null
check "a local plan: finished from the text" "finished, not marked" "$(status)"

reset
prs "acme/web 1 OPEN false run:SUCCESS"
plan acme/web "2026-01-01 - malformed" 'Nothing here.' >/dev/null
plan acme/web "2026-01-02 - fine" '## S: s' "$(item x Fine 'PR #1 ✅ ready')" >/dev/null
OUT=$(status)
is "a malformed plan: one line naming it" "1" "$(printf '%s\n' "$OUT" | grep -c '2026-01-01 - malformed')"
is "a malformed plan: nothing more about it" "  2026-01-01 - malformed: no items" "$(printf '%s\n' "$OUT" | grep -F 'malformed')"
check "a malformed plan: carries on" "#1   Fine" "$OUT"
check "a malformed plan: logged" "no items" "$(cat "$LOG")"

reset
prs "acme/web 1 OPEN false run:SUCCESS"
plan acme/web "2026-01-01 - blocked only" '## S: s' "$(item ' ' Asks '⛔ what now?')" >/dev/null
OUT=$(cd "$TMP" && PATH="$NOGH" "$SHELL_BIN" "$STATUS" 2>&1)
check "gh missing, nothing to look up: the plan prints" "what now?" "$OUT"
refute "gh missing, nothing to look up: no UNKNOWN" "UNKNOWN" "$OUT"

reset
prs "acme/web 1 OPEN false run:SUCCESS"
plan acme/web "2026-01-01 - ticked" '## S: s' "$(item x NoRef 'nothing to go on')" >/dev/null
check "a ticked item with no PR, branch or state: unknown" "NoRef" "$(bucket "UNKNOWN" "$(status)")"

# F. The repo and host of a lookup, as plan-state.sh resolves them.
origin_repo() { git init -q -b main "$1"; git -C "$1" remote add origin "$2"; }
in_dir() { local d=$1; (cd "$d" && "$SHELL_BIN" "$STATUS" 2>&1); }
GHE="$TMP/src/ghe"; origin_repo "$GHE" git@ghe.example.com:acme/web.git
ALIAS="$TMP/src/alias"; origin_repo "$ALIAS" git@work-alias:acme/web.git
OTHER="$TMP/src/other"; origin_repo "$OTHER" git@ghe.example.com:acme/other.git

reset
prs "ghe.example.com/acme/web 12 OPEN false run:SUCCESS"
P=$(plan acme/web "2026-01-01 - host" '## S: s' "$(item x Login 'PR #12 ✅ ready')")
check "from its checkout: the origin's host" "#12  Login" "$(in_dir "$GHE")"
check "the lookup goes to that host" "--repo ghe.example.com/acme/web" "$(cat "$GH_CALLS")"
check "an SSH alias is read as its real host" "#12  Login" "$(in_dir "$ALIAS")"
: > "$GH_CALLS"
in_dir "$OTHER" >/dev/null
is "another repo's checkout: gh's default host" "--repo acme/web" "$(sed 's/.*\(--repo [^ ]*\).*/\1/' "$GH_CALLS")"

{ printf 'Host: ghe.example.com\n'; cat "$P"; } > "$P.new"; mv "$P.new" "$P"
check "elsewhere: the plan's Host line" "#12  Login" "$(status)"
prs "other.example.com/acme/web 12 OPEN false run:SUCCESS"
P2=$(plan acme/web "2026-01-02 - bad host" 'Host: not a host' '## S: s' "$(item x Two 'PR #13 ✅ ready')")
: > "$GH_CALLS"
check "a Host line that is no host: unknown, naming it" "not a host" "$(status)"
refute "a Host line that is no host: never looked up" "13" "$(cat "$GH_CALLS")"
rm -f "$P2"

LOCAL="$TMP/src/mine"
origin_repo "$LOCAL" git@github.com:acme/mine.git
gitl() { git -C "$LOCAL" -c user.name=t -c user.email=t@example.com "$@" >/dev/null 2>&1; }
gitl commit -q --allow-empty -m one
gitl checkout -q -b plans/merged; gitl commit -q --allow-empty -m two
gitl checkout -q main; gitl merge -q --ff-only plans/merged
gitl checkout -q -b plans/unmerged; gitl commit -q --allow-empty -m three
gitl checkout -q main

reset
plan acme/mine "2026-01-01 - branches" \
  '## S: s' "$(item x Merged 'branch plans/merged ✅ ready')" "$(item ' ' Open 'branch plans/unmerged ⏳ in review')" \
  '## T: t' "$(item x Gone 'branch plans/deleted ✅ ready')" \
  '## U: u' "$(item ' ' Hammer '🔨 branch plans/new')" "$(item ' ' Asks '⛔ branch plans/new, or?')" >/dev/null
OUT=$(status)
U=$(bucket "UNKNOWN" "$OUT")
check "a branch-only item outside its checkout: unknown" "Merged" "$U"
check "a branch-only item outside its checkout: why" "no checkout of this plan's repo here" "$U"
check "a hammer on a branch needs no checkout" "Hammer" "$(bucket "MOVING" "$OUT")"
check "a stop sign on a branch needs no checkout" "Asks" "$(bucket "WAITING ON YOU" "$OUT")"
OUT=$(in_dir "$LOCAL")
refute "in its checkout: a merged branch isn't printed" "Merged" "$OUT"
check "in its checkout: an unmerged branch follows its line" "Open" "$(bucket "MOVING" "$OUT")"
check "in its checkout: a ticked branch that's gone is unknown" "branch plans/deleted not found" "$(bucket "UNKNOWN" "$OUT")"

# G. In parallel, at most 8 at once.
reset
TABLE=(); LINES=()
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  TABLE[${#TABLE[@]}]="acme/web $n OPEN false run:SUCCESS"
  LINES[${#LINES[@]}]="## Stack $n: s"
  LINES[${#LINES[@]}]=$(item x "Pr$n" "PR #$n ✅ ready")
done
prs "${TABLE[@]}"
plan acme/web "2026-01-01 - many" "${LINES[@]}" >/dev/null
: > "$GH_PEAKS"; rm -f "$GH_RUNNING"/*
START=$(date +%s)
OUT=$(GH_STUB_SLEEP=0.5 status)
ELAPSED=$(( $(date +%s) - START ))
PEAK=$(sort -n "$GH_PEAKS" | tail -1)
[ "$PEAK" -ge 2 ] && ok "lookups overlap (peak $PEAK)" || bad "lookups overlap" "peak ${PEAK:-none}"
[ "$PEAK" -le 8 ] && ok "at most 8 at once (peak $PEAK)" || bad "at most 8 at once" "peak $PEAK"
[ "$ELAPSED" -lt 8 ] && ok "20 half-second lookups don't add up (${ELAPSED}s)" || bad "20 half-second lookups don't add up" "${ELAPSED}s"
is "every lookup is answered" "20" "$(bucket "MERGE NOW" "$OUT" | grep -c '#')"
is "the rows stay in plan order" "#1 #2 #3 #4 #5 #6 #7 #8 #9 #10 #11 #12 #13 #14 #15 #16 #17 #18 #19 #20" "$(bucket "MERGE NOW" "$OUT" | awk '{printf "%s%s", (NR>1?" ":""), $1}')"
: > "$GH_CALLS"
plan acme/web "2026-01-02 - same PR" '## S: s' "$(item x Again 'PR #1 ✅ ready')" >/dev/null
status >/dev/null
is "the same PR in two plans: one lookup" "1" "$(grep -c '^pr view 1 ' "$GH_CALLS")"

# H. Read-only, exit 0, one parser.
reset
prs "acme/web 1 MERGED false -" "acme/web 2 OPEN false run:SUCCESS"
plan acme/web "2026-01-01 - done" '## S: s' "$(item x Done 'PR #1 ✅ merged')" >/dev/null
plan acme/web "2026-01-02 - open" '## S: s' "$(item x Open 'PR #2 ✅ ready')" >/dev/null
sums() { find "$EOW_HOME" -type f -print0 | sort -z | xargs -0 cksum; }
BEFORE=$(sums)
status >/dev/null
is "it changes no file" "$BEFORE" "$(sums)"
is "gh is only asked to read" "" "$(grep -v '^pr view ' "$GH_CALLS")"
[ -e "$LOG" ] && bad "nothing failed: no log" "$LOG exists" || ok "nothing failed: no log"
LEFT=$(TMPDIR="$TMP/tmp-check"; mkdir -p "$TMPDIR"; export TMPDIR; status >/dev/null; ls "$TMPDIR")
is "it leaves no temp file behind" "" "$LEFT"

ERR=$( (cd "$TMP" && GH_STUB_FAIL="noise" "$SHELL_BIN" "$STATUS" 2>&1 >/dev/null) )
is "a failure never reaches stderr" "" "$ERR"

ALT="$TMP/alt-eow"; mkdir -p "$ALT/executor/plans/acme/web"
printf '# B\n\n## S\n- [x] One - PR #77 ✅ ready\n' > "$ALT/executor/plans/acme/web/2026-01-01 - x.md"
: > "$GH_TABLE"
(cd "$TMP" && EOW_HOME="$ALT" "$SHELL_BIN" "$STATUS" >/dev/null 2>&1)
check "EOW_HOME moves the log" "gh pr view 77" "$(cat "$ALT/executor/status.log")"

BROKEN="$TMP/broken"; mkdir -p "$BROKEN"
cp "$STATUS" "$SELF_DIR/plan-path.sh" "$BROKEN/"
OUT=$(cd "$TMP" && "$SHELL_BIN" "$BROKEN/status.sh" 2>&1); RC=$?
check "the reader gone: a plain note" "UNKNOWN: scripts/plan-items.sh is missing" "$OUT"
is "the reader gone: exit 0" "0" "$RC"

for def in 'plan_host()' 'in_plan_checkout()' 'HOST_RE=' 'ITEM_RE=' 'PR_RE='; do
  hits=$(grep -lF -- "$def" "$SELF_DIR"/*.sh | grep -v '\.test\.sh$' | grep -v '/plan-items\.sh$')
  is "only the reader defines $def" "" "$hits"
done
refute "no wait -n: bash 3.2" "wait -n" "$(cat "$STATUS")"
refute "no associative array: bash 3.2" "declare -A" "$(cat "$STATUS")"
is "nothing local in what ships" "" "$(grep -nE '/Users/|\[\[[A-Za-z]' "$STATUS")"

echo
printf 'status.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
