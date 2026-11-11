#!/usr/bin/env bash
# Spec tests for finished plans: scripts/plan-state.sh says whether a plan is
# finished and marks it, scripts/plan-sweep.sh does so for the whole plans folder.
#   A. NONE, DONE, a closed-unmerged item, OPEN, UNKNOWN;
#   B. an item with only a branch: merged, not merged, gone, no checkout here;
#   C. marking: where the line goes, twice is once, only on DONE;
#   D. the sweep: only DONE plans, --dry-run changes nothing;
#   E. the skills and docs say when it happens.
# No network: a stub `gh` on PATH answers from a table, HOME and EOW_HOME point at
# a temp dir. It runs the scripts with /bin/bash where there is one: macOS's is
# bash 3.2.
#
# Run: bash scripts/plan-state.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd -P "$SELF_DIR/.." && pwd)
STATE="$SELF_DIR/plan-state.sh"
SWEEP="$SELF_DIR/plan-sweep.sh"
SHELL_BIN=bash
[ -x /bin/bash ] && SHELL_BIN=/bin/bash

PASS=0; FAIL=0
ok()     { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()    { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()     { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute() { case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

TMP=$(mktemp -d)
TMP=$(cd -P "$TMP" && pwd)
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export EOW_HOME="$TMP/eow"
unset EXECUTOR_PLANS GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
mkdir -p "$HOME"
PLANS="$EOW_HOME/executor/plans"
TODAY=$(date +%F)
EM=$'\xe2\x80\x94'

# The stub answers `gh pr view <n> --repo <org>/<repo> ...` from the table.
STUB="$TMP/stub"; mkdir -p "$STUB"
export GH_TABLE="$TMP/gh-table"; : > "$GH_TABLE"
export GH_CALLS="$TMP/gh-calls"; : > "$GH_CALLS"
cat > "$STUB/gh" <<'STUB_EOF'
#!/bin/sh
echo "$*" >> "$GH_CALLS"
if [ -n "${GH_STUB_FAIL:-}" ]; then echo "$GH_STUB_FAIL" >&2; exit 1; fi
[ "$1 $2" = "pr view" ] || { echo "stub: not stubbed: $*" >&2; exit 1; }
n=$3; shift 3; repo=""
while [ $# -gt 0 ]; do
  [ "$1" = "--repo" ] && repo=$2
  shift
done
s=$(awk -v r="$repo" -v n="$n" '$1==r && $2==n {print $3}' "$GH_TABLE")
[ -n "$s" ] || { echo "no pull requests found for #$n in $repo" >&2; exit 1; }
echo "$s"
STUB_EOF
chmod +x "$STUB/gh"
# The stub reads an SSH alias the way `ssh -G` prints it.
cat > "$STUB/ssh" <<'STUB_EOF'
#!/bin/sh
[ "$1" = "-G" ] || exit 1
case "$2" in work-alias) h=ghe.example.com ;; *) h=$2 ;; esac
printf 'user git\nhostname %s\n' "$h"
STUB_EOF
chmod +x "$STUB/ssh"
export PATH="$STUB:$PATH"

state()  { "$SHELL_BIN" "$STATE" "$@" 2>&1; }
sweep()  { "$SHELL_BIN" "$SWEEP" "$@" 2>&1; }
prs()    { printf '%s\n' "$@" > "$GH_TABLE"; }
marks()  { grep -c '^Status: done ' "$1"; }

# plan <org/repo> <title> <item line>...: a plan in the shape of references/plan.md.
plan() {
  local f="$PLANS/$1/2026-01-01 - $2.md"; shift 2
  mkdir -p "$(dirname "$f")"
  { printf '# Build: Sample\nSpec: [Sample](https://example.com/spec)\n- an answer to a question\n\n## Stack A: sample\n'
    printf '%s\n' "$@"; } > "$f"
  printf '%s' "$f"
}
item() { printf -- '- [%s] %s %s [part](https://example.com/p) %s %s' "$1" "$2" "$EM" "$EM" "$3"; }

# rc_ok <name> <args...>: exit 0 whatever the outcome.
rc_ok() { local n=$1; shift; "$SHELL_BIN" "$STATE" "$@" >/dev/null 2>&1; is "$n: exit 0" "0" "$?"; }

echo "plan-state.sh spec tests"

# A. The outcomes.
is "no such plan: NONE" "NONE" "$(state "$PLANS/acme/web/nope.md")"
rc_ok "no such plan" "$PLANS/acme/web/nope.md"
is "no argument: NONE"  "NONE" "$(state)"

prs "acme/web 1 MERGED" "acme/web 2 MERGED" "acme/web 3 CLOSED" "acme/web 4 OPEN"
P=$(plan acme/web merged "$(item x Login 'PR #1 ✅ merged')" "$(item ' ' Invites 'PR #2 ⏳ in review')")
is "all merged: DONE <n> items" "DONE 2 items" "$(state "$P")"
rc_ok "all merged" "$P"
check "the lookup goes to the plan's own repo" "--repo acme/web" "$(cat "$GH_CALLS")"
is "reading alone changes nothing" "0" "$(marks "$P")"

P=$(plan acme/web closed "$(item x Login 'PR #1 ✅ merged')" "$(item ' ' Billing 'PR #3 ❌ dropped')")
OUT=$(state "$P")
check "closed unmerged counts as finished" "DONE 2 items" "$OUT"
check "closed unmerged is named by PR" "PR #3" "$OUT"
check "closed unmerged is named by item" "Billing" "$OUT"
check "closed unmerged says what it is" "closed unmerged" "$OUT"
refute "a merged PR is not named" "PR #1" "$OUT"

P=$(plan acme/web open "$(item x Login 'PR #1 ✅ merged')" "$(item ' ' 'Send email' 'PR #4 ⏳ in review')" "$(item ' ' Export '')")
is "unfinished items: OPEN <k> of <n>: <first>" "OPEN 2 of 3: Send email" "$(state "$P")"
rc_ok "open" "$P"

P=$(plan acme/web open-closed "$(item ' ' Billing 'PR #3 ❌ dropped')" "$(item ' ' Export 'PR #4 ⏳ in review')")
OUT=$(state "$P")
check "open: counts only what is unfinished" "OPEN 1 of 2: Export" "$OUT"
check "open: still names a closed-unmerged item" "PR #3" "$OUT"

P=$(plan acme/web ticked "$(item x Login 'PR #4 ✅ ready')")
is "a ticked box is not merged" "OPEN 1 of 1: Login" "$(state "$P")"

P=$(plan acme/web named "$(item ' ' 'Follow up on PR #1' 'PR #4 ⏳ in review')")
is "a PR number in the feature's name is not its PR" "OPEN 1 of 1: Follow up on PR #1" "$(state "$P")"

P=$(plan acme/web blocked "$(item ' ' Export '⛔ waits for PR #1 upstream')")
is "a blocked item is unfinished, whatever PR its question names" "OPEN 1 of 1: Export" "$(state "$P")"

P=$(plan acme/web long "$(item ' ' "$(printf 'é%.0s' 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0)" '')")
OUT=$(state "$P")
is "a long name is cut short: one line" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
[ "${#OUT}" -lt 110 ] && ok "a long name is cut short" || bad "a long name is cut short" "$OUT"
printf '%s' "$OUT" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 && ok "a long name is cut between characters" || bad "a long name is cut between characters" "$OUT"

P=$(plan acme/web failing "$(item x Login 'PR #1 ✅ merged')")
OUT=$(GH_STUB_FAIL="error connecting to api.github.com" state "$P")
check "gh failing: UNKNOWN" "UNKNOWN: " "$OUT"
check "gh failing: the reason" "error connecting to api.github.com" "$OUT"
is "gh failing: one line" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
GH_STUB_FAIL="not logged in" "$SHELL_BIN" "$STATE" "$P" >/dev/null 2>&1; is "gh failing: exit 0" "0" "$?"
OUT=$(GH_STUB_FAIL="not logged in" state --mark "$P")
check "gh failing, marking: UNKNOWN" "UNKNOWN: " "$OUT"
is "gh failing: UNKNOWN never marks" "0" "$(marks "$P")"

P=$(plan acme/web gone "$(item x Login 'PR #1 ✅ merged')" "$(item ' ' Export 'PR #99 ⏳ in review')")
OUT=$(state "$P")
check "one PR gh can't read: UNKNOWN" "UNKNOWN: " "$OUT"
check "one PR gh can't read: names it" "99" "$OUT"

P=$(plan acme/web garbled "$(item x Login 'PR #5 ✅ merged')")
prs "acme/web 5 WAT"
check "a state gh shouldn't report: UNKNOWN" "UNKNOWN: " "$(state "$P")"

F="$PLANS/acme/web/empty.md"; printf '# Build: Sample\n\nNothing yet.\n' > "$F"
OUT=$(state --mark "$F")
check "no items: UNKNOWN" "UNKNOWN: " "$OUT"
is "no items: never marked" "0" "$(marks "$F")"

F="$TMP/elsewhere/2026-01-01 - x.md"; mkdir -p "$(dirname "$F")"
printf '# Build\n\n## A\n- [x] Login - PR #1 merged\n' > "$F"
prs "acme/web 1 MERGED"
check "a plan outside the plans folder: its repo is unknown" "UNKNOWN: " "$(state "$F")"
P=$(plan local/scratch pr-without-remote "$(item x Login 'PR #1 ✅ merged')")
check "a PR on a plan with no remote: UNKNOWN" "UNKNOWN: " "$(state "$P")"

: > "$GH_CALLS"
P=$(plan acme/web untouched "$(item ' ' Export '')" "$(item ' ' Import '🔨 building')")
is "nothing to look up: no network" "OPEN 2 of 2: Export" "$(state "$P")"
is "nothing to look up: gh not called" "" "$(cat "$GH_CALLS")"

is "a relative plans folder: its STOP is passed on" \
  "STOP: the plans folder must be absolute: rel/plans" \
  "$(EXECUTOR_PLANS=rel/plans state "$P")"

# The host of a PR: the plans folder drops it, so it comes from elsewhere.
origin_repo() {
  git init -q -b main "$1"
  git -C "$1" remote add origin "$2"
}
in_dir() { local d=$1; shift; (cd "$d" && "$SHELL_BIN" "$STATE" "$@" 2>&1); }
add_host() { local c; c=$(cat "$2"); printf 'Host: %s\n%s\n' "$1" "$c" > "$2"; }
GHE="$TMP/src/ghe"; origin_repo "$GHE" git@ghe.example.com:acme/web.git
GHE_HTTPS="$TMP/src/ghe-https"; origin_repo "$GHE_HTTPS" https://user:secret@ghe.example.com:8443/acme/web.git
ALIAS="$TMP/src/alias"; origin_repo "$ALIAS" git@work-alias:acme/web.git
DOTCOM="$TMP/src/dotcom"; origin_repo "$DOTCOM" git@github.com:acme/web.git

prs "acme/web 12 MERGED" "ghe.example.com/acme/web 12 OPEN"
P=$(plan acme/web host-checkout "$(item x Login 'PR #12 ✅ ready')")
is "from its checkout on another host: that host's PR" "OPEN 1 of 1: Login" "$(in_dir "$GHE" --mark "$P")"
is "the same number on the default host marks nothing" "0" "$(marks "$P")"
is "an HTTPS origin with a port and credentials" "OPEN 1 of 1: Login" "$(in_dir "$GHE_HTTPS" "$P")"
is "an SSH alias is read as its real host" "OPEN 1 of 1: Login" "$(in_dir "$ALIAS" "$P")"
prs "acme/web 12 OPEN" "github.com/acme/web 12 MERGED"
is "from a github.com checkout: asks github.com" "DONE 1 items" "$(in_dir "$DOTCOM" "$P")"

prs "acme/web 12 MERGED" "ghe.example.com/acme/web 12 OPEN"
add_host ghe.example.com "$P"
is "elsewhere: the plan's Host line" "OPEN 1 of 1: Login" "$(in_dir "$TMP" --mark "$P")"
is "elsewhere: the same number on the default host marks nothing" "0" "$(marks "$P")"
P=$(plan acme/web host-wins "$(item x Login 'PR #12 ✅ ready')")
add_host other.example.com "$P"
is "in a checkout its origin wins over the Host line" "OPEN 1 of 1: Login" "$(in_dir "$GHE" "$P")"
P=$(plan acme/web host-bad "$(item x Login 'PR #12 ✅ ready')")
add_host 'not a host' "$P"
check "a Host line that is no host: UNKNOWN" "UNKNOWN: " "$(in_dir "$TMP" "$P")"
P=$(plan acme/web host-below "$(item x Login 'PR #12 ✅ ready')")
printf 'Host: ghe.example.com\n' >> "$P"
is "a Host line under a heading doesn't count" "DONE 1 items" "$(in_dir "$TMP" "$P")"

# B. An item with only a branch: an ancestor of the default branch, or not.
LOCAL="$TMP/src/scratch"
git init -q -b main "$LOCAL"
gitl() { git -C "$LOCAL" -c user.name=t -c user.email=t@example.com "$@" >/dev/null 2>&1; }
gitl commit -q --allow-empty -m one
gitl checkout -q -b plans/merged; gitl commit -q --allow-empty -m two
gitl checkout -q main; gitl merge -q --ff-only plans/merged
gitl checkout -q -b plans/unmerged; gitl commit -q --allow-empty -m three
gitl checkout -q main
in_local() { (cd "$LOCAL" && "$SHELL_BIN" "$STATE" "$@" 2>&1); }
LOCALF=$("$SHELL_BIN" "$SELF_DIR/plan-path.sh" "$LOCAL")

: > "$GH_CALLS"
P=$(plan "local/scratch" branch-merged "$(item x Login 'branch plans/merged ✅ ready')")
is "branch merged: DONE" "DONE 1 items" "$(in_local "$P")"
is "the plan's folder is the one plan-path prints" "$LOCALF" "$(dirname "$P")"
is "branch only: gh is not asked about a PR" "" "$(grep -F 'pr view' "$GH_CALLS")"
P=$(plan "local/scratch" branch-open "$(item x Login 'branch plans/merged ✅ ready')" "$(item ' ' Export 'branch plans/unmerged ⏳')")
is "branch not merged: OPEN" "OPEN 1 of 2: Export" "$(in_local "$P")"
gitl branch plans/building
P=$(plan "local/scratch" branch-building "$(item ' ' Login 'branch plans/building 🔨 building')")
is "a branch still at the default branch's tip, being built: OPEN" "OPEN 1 of 1: Login" "$(in_local "$P")"
is "being built: not marked" "0" "$(in_local --mark "$P" >/dev/null; marks "$P")"
P=$(plan "local/scratch" branch-gone "$(item x Login 'branch plans/deleted ✅ ready')")
OUT=$(in_local "$P")
check "branch gone: can't tell, UNKNOWN" "UNKNOWN: " "$OUT"
check "branch gone: names it" "plans/deleted" "$OUT"
P=$(plan "local/scratch" branch-not-yet "$(item x Login 'branch plans/merged ✅ ready')" "$(item ' ' Export 'branch plans/next off plans/merged')")
is "a branch not made yet, on an unticked item: OPEN" "OPEN 1 of 2: Export" "$(in_local "$P")"
OUT=$(cd "$TMP" && "$SHELL_BIN" "$STATE" "$P" 2>&1)
check "a branch not made yet, outside a repo: still UNKNOWN" "UNKNOWN: " "$OUT"
P=$(plan "local/scratch" branch-dash "$(item x Login 'branch --help ✅ ready')")
check "a branch name that reads as an option: UNKNOWN" "UNKNOWN: " "$(in_local "$P")"
P=$(plan "local/scratch" branch-away "$(item x Login 'branch plans/merged ✅ ready')")
OUT=$(cd "$TMP" && "$SHELL_BIN" "$STATE" "$P" 2>&1)
check "outside a repo: UNKNOWN" "UNKNOWN: " "$OUT"
OTHER="$TMP/src/other"
git init -q -b main "$OTHER"
git -C "$OTHER" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m one
git -C "$OTHER" branch plans/merged
OUT=$(cd "$OTHER" && "$SHELL_BIN" "$STATE" "$P" 2>&1)
check "in another repo with a branch of that name: UNKNOWN" "UNKNOWN: " "$OUT"
P=$(plan "local/scratch" both "$(item ' ' Login 'PR #4 ⏳ branch plans/merged')")
prs "local/scratch 4 OPEN"
check "a PR number wins over a branch" "UNKNOWN: " "$(in_local "$P")"

# C. Marking on DONE.
prs "acme/web 1 MERGED" "acme/web 4 OPEN"
P=$(plan acme/web mark "$(item x Login 'PR #1 ✅ merged')")
BEFORE=$(cat "$P")
is "marking prints the state" "DONE 1 items" "$(state --mark "$P")"
is "DONE marks the plan" "1" "$(marks "$P")"
LINE=$(grep -n "^Status: done $TODAY\$" "$P" | cut -d: -f1)
HEAD=$(grep -n '^## ' "$P" | head -1 | cut -d: -f1)
[ -n "$LINE" ] && [ "$LINE" -lt "$HEAD" ] && ok "the line is before the first ## heading" || bad "the line is before the first ## heading" "line ${LINE:-none}, heading $HEAD"
is "only that line changed" "$BEFORE" "$(grep -v '^Status: done ' "$P")"
is "the blank line above the heading stays" "" "$(sed -n "$((HEAD-1))p" "$P")"
refute "a marked plan is no longer live" "$P" "$("$SHELL_BIN" "$SELF_DIR/plan-path.sh" --all-live 2>&1)"
is "marking twice: DONE still" "DONE 1 items" "$(state --mark "$P")"
is "marking twice: one line" "1" "$(marks "$P")"

P=$(plan acme/web mark-open "$(item ' ' Login 'PR #4 ⏳ in review')")
BEFORE=$(cat "$P")
state --mark "$P" >/dev/null
is "OPEN marks nothing" "$BEFORE" "$(cat "$P")"

F="$PLANS/acme/web/2026-01-02 - no heading.md"
printf '# Build: Sample\n\n- [x] Login - PR #1 merged\n' > "$F"
state --mark "$F" >/dev/null
is "no heading: the line goes under the title" "# Build: Sample|Status: done $TODAY||- [x] Login - PR #1 merged|" "$(tr '\n' '|' < "$F")"

F="$PLANS/acme/web/2026-01-03 - late status.md"
printf '# Build: Sample\n\n## A\n- [x] Login - PR #1 merged\nStatus: done 2020-01-01\n' > "$F"
state --mark "$F" >/dev/null
is "a Status line below the header doesn't count" "1" "$(sed -n '/^## /q;p' "$F" | grep -c '^Status: done ')"

F="$PLANS/acme/web/2026-01-04 - read only.md"
printf '# Build: Sample\n\n## A\n- [x] Login - PR #1 merged\n' > "$F"
chmod 444 "$F"
OUT=$(state --mark "$F")
check "a plan it can't write: UNKNOWN" "UNKNOWN: " "$OUT"
"$SHELL_BIN" "$STATE" --mark "$F" >/dev/null 2>&1; is "a plan it can't write: exit 0" "0" "$?"
chmod 644 "$F"; rm -f "$F"

REAL="$TMP/notes/linked"; mkdir -p "$REAL" "$PLANS/acme"
printf '# Build: Sample\n\n## A\n- [x] Login - PR #1 merged\n' > "$REAL/2026-01-01 - linked.md"
ln -s "$REAL" "$PLANS/acme/linked"
prs "acme/linked 1 MERGED"
state --mark "$PLANS/acme/linked/2026-01-01 - linked.md" >/dev/null
is "a linked-in folder: the plan is marked in place" "1" "$(marks "$REAL/2026-01-01 - linked.md")"
[ -L "$PLANS/acme/linked" ] && ok "a linked-in folder stays a link" || bad "a linked-in folder stays a link" "replaced"
rm -rf "$PLANS/acme/linked" "$REAL"
mkdir -p "$REAL"
printf '# Build: Sample\n\n## A\n- [x] Login - PR #1 merged\n' > "$REAL/target.md"
mkdir -p "$PLANS/acme/linkfile"
ln -s "$REAL/target.md" "$PLANS/acme/linkfile/2026-01-01 - x.md"
prs "acme/linkfile 1 MERGED"
state --mark "$PLANS/acme/linkfile/2026-01-01 - x.md" >/dev/null
is "a linked plan: the target is marked" "1" "$(marks "$REAL/target.md")"
[ -L "$PLANS/acme/linkfile/2026-01-01 - x.md" ] && ok "a linked plan stays a link" || bad "a linked plan stays a link" "replaced"

# C2. Marking tidies the repo, detached: --mark returns without waiting for it.
TIDY_STUB="$TMP/repo-tidy-stub.sh"
cat > "$TIDY_STUB" <<'STUB_EOF'
#!/bin/sh
sleep 2
printf '%s\n' "$*" > "$TIDY_MARK"
STUB_EOF
chmod +x "$TIDY_STUB"
export TIDY_MARK="$TMP/tidy-mark"
export EXECUTOR_REPO_TIDY="$TIDY_STUB"
now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }

prs "local/scratch 1 MERGED"
rm -f "$TIDY_MARK"
P=$(plan "local/scratch" tidy-done "$(item x Login 'branch plans/merged ✅ ready')")
T0=$(now)
OUT=$(in_local --mark "$P")
T1=$(now)
is "tidy: --mark on a finished plan prints DONE" "DONE 1 items" "$OUT"
FAST=$(perl -e 'print(($ARGV[1]-$ARGV[0]) < 1.5 ? "fast" : "slow")' "$T0" "$T1")
is "tidy: --mark returns without waiting for it" "fast" "$FAST"
[ ! -e "$TIDY_MARK" ] && ok "tidy: not finished when --mark returned" || bad "tidy: not finished when --mark returned" "marker already there"
i=0; while [ ! -e "$TIDY_MARK" ] && [ "$i" -lt 50 ]; do sleep 0.2; i=$((i+1)); done
is "tidy: it ran later, on this repo" "$(cd -P "$LOCAL" && pwd)" "$(cat "$TIDY_MARK" 2>/dev/null)"

rm -f "$TIDY_MARK"
P=$(plan "local/scratch" tidy-open "$(item x Login 'branch plans/merged ✅ ready')" "$(item ' ' Export 'branch plans/unmerged ⏳')")
OUT=$(in_local --mark "$P")
check "tidy: an unfinished plan is OPEN" "OPEN 1 of 2" "$OUT"
sleep 3
[ ! -e "$TIDY_MARK" ] && ok "tidy: an unfinished plan starts no tidy" || bad "tidy: an unfinished plan starts no tidy" "tidy ran"

rm -f "$TIDY_MARK"
P=$(plan "local/scratch" tidy-readonly "$(item x Login 'branch plans/merged ✅ ready')")
in_local "$P" >/dev/null
sleep 3
[ ! -e "$TIDY_MARK" ] && ok "tidy: read-only (no --mark) starts no tidy" || bad "tidy: read-only (no --mark) starts no tidy" "tidy ran"

rm -f "$TIDY_MARK"
P=$(plan "local/scratch" tidy-elsewhere "$(item x Login 'branch plans/merged ✅ ready')")
(cd "$TMP" && "$SHELL_BIN" "$STATE" --mark "$P" >/dev/null 2>&1)
sleep 3
[ ! -e "$TIDY_MARK" ] && ok "tidy: outside the plan's checkout, no repo to tidy" || bad "tidy: outside the plan's checkout" "tidy ran"
unset EXECUTOR_REPO_TIDY

# D. The sweep.
rm -rf "$PLANS"
is "sweep: no plans folder, nothing to do" "No live plans in $PLANS" "$(sweep)"
[ -e "$PLANS" ] && bad "sweep: creates no folder" "$PLANS exists" || ok "sweep: creates no folder"

prs "acme/web 1 MERGED" "acme/web 2 OPEN" "acme/api 1 OPEN" "acme/api 2 MERGED" "acme/old 1 MERGED"
D1=$(plan acme/web finished "$(item x Login 'PR #1 ✅ merged')")
O1=$(plan acme/web going "$(item ' ' Export 'PR #2 ⏳ in review')")
O2=$(plan acme/api same-number "$(item ' ' Search 'PR #1 ⏳ in review')")
D2=$(plan acme/api finished "$(item x Search 'PR #2 ✅ merged')")
U1=$(plan acme/api cant-tell "$(item x Search 'PR #77 ✅ ready')")
M1=$(plan acme/old marked "$(item x Login 'PR #1 ✅ merged')")
{ printf '# Build: Old\nStatus: done 2020-02-02\n\n## A\n'; item x Login 'PR #1 ✅ merged'; printf '\n'; } > "$M1"
L1="$PLANS/acme/web/legacy/old.md"; mkdir -p "$(dirname "$L1")"
printf '# Old\n\n## A\n- [x] Login - PR #1 merged\n' > "$L1"

sums() { find "$PLANS" -type f -print0 | sort -z | xargs -0 cksum; }
BEFORE=$(sums)
: > "$GH_CALLS"
OUT=$(sweep --dry-run)
is "dry run: changes nothing" "$BEFORE" "$(sums)"
check "dry run: says what it would mark" "would mark" "$(printf '%s\n' "$OUT" | grep -F "$D1")"
check "dry run: both done plans listed" "would mark" "$(printf '%s\n' "$OUT" | grep -F "$D2")"
check "dry run: open plans say so" "OPEN 1 of 1: Export" "$(printf '%s\n' "$OUT" | grep -F "$O1")"
check "dry run: unknown plans say so" "UNKNOWN: " "$(printf '%s\n' "$OUT" | grep -F "$U1")"
refute "the sweep skips plans already marked" "$M1" "$OUT"
refute "the sweep skips subfolders" "legacy" "$OUT"

OUT=$(sweep); RC=$?
is "sweep: exit 0" "0" "$RC"
is "sweep marks a DONE plan" "1" "$(marks "$D1")"
is "sweep marks a DONE plan in another repo" "1" "$(marks "$D2")"
is "sweep leaves an OPEN plan" "0" "$(marks "$O1")"
is "sweep: the same PR number in another repo is its own PR" "0" "$(marks "$O2")"
is "sweep leaves an UNKNOWN plan" "0" "$(marks "$U1")"
check "sweep says what it marked" "marked" "$(printf '%s\n' "$OUT" | grep -F "$D1")"
is "sweep leaves a marked plan's date" "Status: done 2020-02-02" "$(grep '^Status: done ' "$M1")"
is "sweep leaves a subfolder alone" "0" "$(marks "$L1")"

BEFORE=$(sums)
: > "$GH_CALLS"
OUT=$(sweep)
is "sweep twice: nothing more changes" "$BEFORE" "$(sums)"
refute "sweep twice: a marked plan isn't read again" "$D1" "$OUT"
refute "sweep twice: no lookup for a marked plan" "acme/old" "$(cat "$GH_CALLS")"

BEFORE=$(sums)
OUT=$(GH_STUB_FAIL="no network" sweep)
is "sweep with gh failing: marks nothing" "$BEFORE" "$(sums)"
check "sweep with gh failing: says why" "no network" "$OUT"

is "sweep: a relative plans folder's STOP is passed on" \
  "STOP: the plans folder must be absolute: rel/plans" \
  "$(EXECUTOR_PLANS=rel/plans sweep)"
EXECUTOR_PLANS=rel/plans "$SHELL_BIN" "$SWEEP" >/dev/null 2>&1; is "sweep: STOP exit 0" "0" "$?"
check "sweep: a wrong argument is a plain note" "STOP: " "$(sweep --nope)"

ENVP="$TMP/env-plans"
plan_env() { mkdir -p "$ENVP/acme/web"; printf '# Build\n\n## A\n- [x] Login - PR #1 merged\n' > "$ENVP/acme/web/2026-01-01 - env.md"; }
plan_env
prs "acme/web 1 MERGED"
EXECUTOR_PLANS="$ENVP" "$SHELL_BIN" "$SWEEP" >/dev/null 2>&1
is "sweep: walks the folder plan-path.sh resolves" "1" "$(marks "$ENVP/acme/web/2026-01-01 - env.md")"

# E. When it happens: the skills and references.
cd "$REPO_ROOT" || exit 1
BUILD=$(cat skills/build/SKILL.md)
check "build: may run plan-state" 'scripts/plan-state.sh:*' "$(sed -n 1,5p skills/build/SKILL.md)"
STEP0=$(sed -n '/^## 0\./,/^## 1\./p' skills/build/SKILL.md)
check "build step 0: runs plan-state" 'plan-state.sh --mark' "$STEP0"
check "build step 0: DONE starts at step 1" '`DONE`' "$STEP0"
check "build step 0: UNKNOWN names the reason" '`UNKNOWN`' "$STEP0"
check "build step 0: OPEN as before" '`OPEN`' "$STEP0"
check "build step 5: runs plan-state" 'plan-state.sh --mark' "$(sed -n '/^## 5\./,$p' skills/build/SKILL.md)"
STACKS=$(sed -n '/^## Keeping a stack healthy/,/^## Titles/p' references/stacks.md)
check "stacks: after the sync" 'plan-state.sh --mark' "$STACKS"
check "stacks: tidies the repo, detached, after the sync" 'repo-tidy.sh' "$STACKS"
check "plan.md: how a plan is marked" 'plan-state.sh --mark' "$(cat references/plan.md)"
check "plan.md: names the sweep" 'plan-sweep.sh' "$(cat references/plan.md)"
check "plan.md: the Host line" 'Host: <host>' "$(cat references/plan.md)"
check "build step 2: records a host other than github.com" 'plan-path.sh --host' "$(sed -n '/^## 2\./,/^## 3\./p' skills/build/SKILL.md)"
check "plan.md: an item with only a branch" 'branch <name>' "$(cat references/plan.md)"
HELPBLOCK=$(awk '/^## HELP$/{h=1} h' skills/help/SKILL.md | awk '/^```$/{f++; next} f==1')
is "help: lists the sweep in one line" "1" "$(printf '%s\n' "$HELPBLOCK" | grep -c 'plan-sweep.sh')"
check "help: may run the sweep" 'scripts/plan-sweep.sh:*' "$(sed -n 1,6p skills/help/SKILL.md)"
# Width in characters, not bytes: drop the UTF-8 continuation bytes (0x80-0xBF),
# so it holds in any locale. The help is printed as it stands: 80 columns at most.
WIDE=$(printf '%s\n' "$HELPBLOCK" | while IFS= read -r row; do
  n=$(printf '%s' "$row" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' ')
  [ "$n" -gt 80 ] && printf '%s\n' "$row"
done)
is "help: no row wider than 80 columns" "" "$WIDE"
is "help: the width check reads the block" "1" "$([ "$(printf '%s\n' "$HELPBLOCK" | wc -l)" -gt 20 ] && echo 1)"

local_refs=$(grep -nE '/Users/|\[\[[A-Za-z]' scripts/plan-state.sh scripts/plan-sweep.sh)
is "nothing local in what ships" "" "$local_refs"

echo
printf 'plan-state.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
