#!/usr/bin/env bash
# Spec tests for tickets from the plan (build offers one ticket per plan item
# when the spec home names a tracker). The GitHub side is a script, since each
# gh call is wrapped (CONTRIBUTING #4): scripts/ticket-github.sh creates the
# issue and links it as a sub-issue of the spec's parent issue. Jira and Linear
# go through the connectors the model has; their rules are held to the text.
# No network: a stub gh on PATH records its calls.
#
# Run: bash scripts/tickets.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)
cd "$REPO" || exit 1
T="$SELF_DIR/ticket-github.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2" ;; *) ok "$1" ;; esac; }

TMP=$(cd -P "$(mktemp -d)" && pwd); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export EOW_HOME="$TMP/eow"
BIN="$TMP/bin"; mkdir -p "$BIN"; CALLS="$TMP/calls"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
[ -n "${GH_FAIL:-}" ] && case "$*" in *"$GH_FAIL"*) echo "boom" >&2; exit 1 ;; esac
case "$1 $2" in
  "issue create") echo "https://github.com/acme/api/issues/${NEXT:-12}" ;;
  "api repos/acme/api/issues/${NEXT:-12}") echo 987654 ;;
esac
exit 0
STUB
chmod +x "$BIN/gh"; export PATH="$BIN:$PATH" CALLS
BODY="$TMP/body.md"; printf 'Feature X\n\nrequirements\n' > "$BODY"
LOG="$EOW_HOME/executor/tickets.log"

echo "tickets spec tests"

# 1. A ticket: the issue is created from the body file and linked under the parent.
out=$(bash "$T" acme/api 7 "Feature X" "$BODY"); rc=$?
is "ticket: exit 0" "0" "$rc"
is "ticket: reports it" "TICKET: #12 https://github.com/acme/api/issues/12" "$out"
check "ticket: created in the repo with the title and the body file" "issue create --repo acme/api --title Feature X --body-file $BODY" "$(cat "$CALLS")"
check "ticket: linked as a sub-issue of the parent" "api -X POST repos/acme/api/issues/7/sub_issues" "$(cat "$CALLS")"
check "ticket: by the new issue's id" "sub_issue_id=987654" "$(cat "$CALLS")"

# 2. An unreachable tracker is a note and a log line, never a failed call.
: > "$CALLS"
out=$(GH_FAIL="issue create" bash "$T" acme/api 7 "Feature X" "$BODY"); rc=$?
is "unreachable: exit 0" "0" "$rc"
check "unreachable: a NOTE line" "NOTE: " "$out"
refute "unreachable: no TICKET line" "TICKET:" "$out"
check "unreachable: logged" "acme/api" "$(cat "$LOG")"
is "unreachable: nothing else was called" "1" "$(wc -l < "$CALLS" | tr -d ' ')"

# 3. The issue exists but linking failed: still a ticket, with a note.
rm -f "$LOG"; : > "$CALLS"
out=$(GH_FAIL="sub_issues" bash "$T" acme/api 7 "Feature X" "$BODY")
check "link failed: the ticket is reported" "TICKET: #12" "$out"
check "link failed: and says it is not linked" "NOTE: #12 is not linked under #7" "$out"
check "link failed: logged" "sub_issues" "$(cat "$LOG")"

# 4. Bad input is a note, not a crash.
out=$(bash "$T" acme/api 7 "Feature X" "$TMP/missing.md"); check "missing body file: a NOTE" "NOTE: " "$out"
out=$(bash "$T" acme/api); check "too few arguments: a usage NOTE" "NOTE: usage" "$out"
out=$(bash "$T" acme/api seven "T" "$BODY"); check "parent not a number: a NOTE" "NOTE: " "$out"
: > "$CALLS"; bash "$T" acme/api seven "T" "$BODY" >/dev/null
is "bad parent: gh is never called" "0" "$(wc -l < "$CALLS" | tr -d ' ')"

# 5. The plan keeps a ticket beside its item, and the readers of the plan ignore it.
. "$SELF_DIR/plan-items.sh"
parse_item '- [ ] Send email — [Feature B](/x/spec.md) — ticket #12 — PR #50 ⏳ in review'
is "plan: the PR is the PR, not the ticket" "50" "$ITEM_PR"
parse_item '- [ ] Send email — [Feature B](/x/spec.md) — ticket TRAV-88'
is "plan: a ticket alone is no PR" "" "$ITEM_PR"
is "plan: a ticket alone is not started" "none" "$ITEM_REVIEW"
check "plan reference: records the ticket next to its item" "ticket" "$(cat references/plan.md)"

# 6. Build: offered after the plan approval, once per run, never twice.
BUILD=$(cat skills/build/SKILL.md)
TK=$(printf '%s\n' "$BUILD" | awk '/^## 2b\./{f=1} /^## 3\./{f=0} f')
check "build: a tickets step exists" "Tickets" "$TK"
check "build: only when the spec home names a tracker" "tracker" "$TK"
check "build: after the plan is approved" "plan is approved" "$TK"
check "build: asks, once per run, never on its own" "once per run" "$TK"
check "build: one ticket per plan item" "one ticket per" "$TK"
check "build: the body is the builder's brief" "builder" "$TK"
check "build: and a link to the spec" "link to the spec" "$TK"
check "build: GitHub uses the script" "scripts/ticket-github.sh" "$TK"
check "build: Linear and Jira go through their connectors" "connector" "$TK"
check "build: a rerun never creates one twice" "never creates a ticket twice" "$TK"
check "build: unreachable tracker: carry on and say so" "carry on without tickets" "$TK"
check "build: records the ticket in the plan" "plan" "$TK"
check "build: may run the script" 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-github.sh:*)' "$BUILD"
check "build: tells the builder its ticket" "ticket" "$(printf '%s\n' "$BUILD" | awk '/^## 3\./{f=1} /^## 4\./{f=0} f')"
check "builder: its PR links the ticket" "Closes #" "$(cat agents/builder.md)"
check "builder: Jira and Linear by key" "key" "$(cat agents/builder.md)"
check "PR template: a ticket line" "Closes #" "$(cat references/pull-request.md)"
check "stack map: the ticket is out of scope to update" "status" "$(printf '%s\n' "$TK")"

echo
printf 'tickets: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
