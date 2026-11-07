#!/usr/bin/env bash
# Spec tests for scripts/heavy-hook.sh — the PreToolUse hook that puts a heavy
# command in the queue by prefixing it, and otherwise stays out of the way. Every
# test has its own state folder through EXECUTOR_HEAVY_DIR, so the real one is never
# touched. Events are built by the real jq; a stub jq on PATH records what the hook
# itself starts.
#
# Run: bash scripts/heavy-hook.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
PLUGIN=$(cd -P "$SELF_DIR/.." && pwd)
HOOK="$SELF_DIR/heavy-hook.sh"
HOOKS_JSON="$PLUGIN/hooks/hooks.json"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

ROOT=$(cd -P "$(mktemp -d)" && pwd)
cleanup() {
  chmod -R u+w "$ROOT" 2>/dev/null
  rm -rf "$ROOT"
}
trap cleanup EXIT
cd "$ROOT" || exit 1

BASH_BIN=$BASH
REAL_JQ=$(command -v jq)
PATIENCE=60

STUB="$ROOT/stub"; mkdir -p "$STUB"
export JQ_CALLS="$ROOT/jq-calls" REAL_JQ
cat > "$STUB/jq" <<'EOF'
#!/usr/bin/env bash
echo called >> "$JQ_CALLS"
exec "$REAL_JQ" "$@"
EOF
chmod +x "$STUB/jq"

NO_JQ="$ROOT/no-jq"; mkdir -p "$NO_JQ"
ln -s "$(command -v date)" "$NO_JQ/date"

N=0
state() {
  N=$((N+1))
  export EXECUTOR_HEAVY_DIR="$ROOT/state$N"
  LOG="$EXECUTOR_HEAVY_DIR/heavy.log"
  mkdir -p "$EXECUTOR_HEAVY_DIR"
  [ $# -eq 0 ] || printf '%s\n' "$1" > "$EXECUTOR_HEAVY_DIR/heavy.json"
}

event() {
  "$REAL_JQ" -cn --arg c "$1" --arg d "$PWD" \
    '{session_id:"s",transcript_path:"/t/t.jsonl",cwd:$d,permission_mode:"default",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c,description:"Run it",timeout:600000},tool_use_id:"u"}'
}

# The hook's whole output, stderr included, for a command.
run() { OUT=$(event "$1" | "$BASH_BIN" "${2:-$HOOK}" 2>&1); }

# The rewritten command as bytes: the x guards trailing newlines from $(...).
new_command() {
  local got
  got=$(printf '%s' "$OUT" | "$REAL_JQ" -j '.hookSpecificOutput.updatedInput.command, "x"')
  printf '%s' "${got%x}"
}

prefix() { printf "bash '%s/scripts/heavy.sh' \$\$ %s; " "$PLUGIN" "$1"; }

matches() {
  run "$1"
  local got want
  got=$(new_command; printf x)
  want="$(prefix "$2")$1"
  is "$3: $2" "${want}x" "$got"
}

unmatched() { run "$1"; is "not matched: $1" "" "$OUT"; }

failed_logged() {
  [ -f "$LOG" ] || { bad "$1: failed logged" "no heavy.log"; return; }
  local lines
  lines=$(grep -cE "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}  [A-Za-z0-9._-]+  $ROOT  waited=0  failed\$" "$LOG")
  is "$1: one failed line, with heavy.sh's fields" "1" "$lines"
}

until_logged() {
  local deadline=$((SECONDS+PATIENCE))
  until grep -qE "  $1(  |\$)" "$LOG" 2>/dev/null; do
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 0.1
  done
}

echo "heavy-hook.sh spec tests"

# 1. No heavy.json: off, whatever the command.
state
for c in 'npm test' 'ls' 'npx next build' 'chrome --headless=new x'; do
  run "$c"; is "off: nothing for: $c" "" "$OUT"
done
is "off: no log" "no" "$([ -e "$LOG" ] && echo yes || echo no)"
: > "$JQ_CALLS"
event 'npm test' | PATH="$STUB:$PATH" "$BASH_BIN" "$HOOK" >/dev/null 2>&1
is "off: no jq" "0" "$(wc -l < "$JQ_CALLS" | tr -d ' ')"

# 2. Default patterns, from a {} file.
state '{}'
while IFS='|' read -r label c; do
  matches "$c" "$label" "$c"
done <<'EOF'
next-build|next build
next-build|npx next build
npm-build|npm run build
npm-build|npm build
npm-build|pnpm build
npm-build|yarn run build
npm-build|npm --prefix dashboard run build
npm-build|npm run build:prod
npm-test|npm test
npm-test|yarn test
npm-test|pnpm run test
npm-test|npm --prefix dashboard test
npm-test|npm run test:unit
npm-test|npm test -- --watch=false
npm-test|FOO=1 BAR="a b" npm test
npm-test|FOO=1 BAR='a b' BAZ= npm test
js-test|npx vitest run
js-test|vitest
js-test|jest --ci
js-test|npx jest
js-test|playwright test
js-test|npx playwright test e2e
pytest|pytest
pytest|pytest tests/x.py -q
pytest|python3 -m pytest
pytest|python -m pytest -x
py-test|python3 tools/tests/test_comic_page.py
py-test|python test_a.py
py-test|python3 run_tests.py --fast
sh-test|bash scripts/status.test.sh
sh-test|sh scripts/status.test.sh
sh-test|scripts/status.test.sh
sh-test|./status.test.sh arg
chrome|chrome --headless=new http://x
chrome|/Applications/Chrome --disable-gpu --headless x
EOF

# Segments: any of them can match, whatever separates them.
matches 'cd x && npm test' npm-test 'after &&'
matches 'false || npm test' npm-test 'after ||'
matches 'ls; npm test' npm-test 'after ;'
matches 'ls | npm test' npm-test 'after |'
matches $'ls\nnpm test\nls' npm-test 'on its own line'
matches $'cd x &&\t FOO=1  npm  test' npm-test 'odd spacing'
matches 'npm test && echo done' npm-test 'before &&'
matches 'npm test&' npm-test 'sent to the background'
matches 'npm test>out' npm-test 'redirected'

while IFS= read -r c; do
  unmatched "$c"
done <<'EOF'
git commit -m "fix next build"
grep -r "npm test" .
next dev
npm install
cat scripts/status.test.sh
timeout 600 npm test
./node_modules/.bin/vitest
npm run tests
npm run test-unit
npm run lint
python3 tools/x.py
python3 tools/test_helpers.txt
ls
EOF

# 3. The rewrite: byte for byte, every other field kept, nothing about permissions.
state '{}'
while IFS= read -r name; do
  case "$name" in
    newline)     c=$'npm test\n' ;;
    newlines)    c=$'npm test\n\n\n' ;;
    heredoc)     c=$'npm test <<\'EOF\'\n  a "b" $c\nEOF\n' ;;
    quotes)      c='npm test -- "a b" '\''c d'\'' "e\"f"' ;;
    backslashes) c='npm test -- a\b\\c\\\\ \n \t' ;;
    non-ascii)   c='npm test -- "zażółć 日本語 🚀"' ;;
    control)     c=$'npm test -- \001\t\033[0m\177' ;;
    expansions)  c='npm test -- $HOME $(date) `date` * ?' ;;
    deny)        c='npm test && rm -rf /tmp/x' ;;
  esac
  matches "$c" npm-test "byte for byte, $name"
done <<'EOF'
newline
newlines
heredoc
quotes
backslashes
non-ascii
control
expansions
deny
EOF

# A long heredoc fits within the hook's 5 seconds. An overrun gets two more tries,
# so a loaded machine can't fail it and only a truly slow hook can.
LONG=$(perl -e 'print "npm test <<EOF\n"; print "const x$_ = \"a value; here\";\n" for 1..3000; print "EOF\n"')
for try in 1 2 3; do
  started=$SECONDS
  run "$LONG"
  took=$((SECONDS-started))
  [ "$took" -le 5 ] && break
done
[ "$took" -le 5 ] && ok "long heredoc: within the timeout" || bad "long heredoc: within the timeout" "took $took s"
is "long heredoc: byte for byte" "$(prefix npm-test)$LONG" "$(new_command)"

INPUT='{"command":"npm test","description":"D","timeout":12345,"run_in_background":true,"extra":{"a":[1,"b"]}}'
OUT=$(printf '{"tool_name":"Bash","tool_input":%s}' "$INPUT" | "$BASH_BIN" "$HOOK" 2>&1)
is "fields: all others kept" "$(printf '%s' "$INPUT" | "$REAL_JQ" -cS 'del(.command)')" \
  "$(printf '%s' "$OUT" | "$REAL_JQ" -cS '.hookSpecificOutput.updatedInput | del(.command)')"
is "fields: run_in_background gets the same prefix" "$(prefix npm-test)npm test" "$(new_command)"
is "output: only hookEventName and updatedInput, no permissionDecision" \
  '[["hookSpecificOutput"],["hookEventName","updatedInput"],"PreToolUse"]' \
  "$(printf '%s' "$OUT" | "$REAL_JQ" -c '[keys, (.hookSpecificOutput|keys), .hookSpecificOutput.hookEventName]')"

OUT=$(printf '%s' '{"tool_input":{"command":"npm test \ud83d"}}' | "$BASH_BIN" "$HOOK" 2>&1)
is "a command jq can't carry unchanged is left alone" "" "$OUT"
OUT=$(printf '%s' '{"tool_input":{"command":"npm test \u0000 x"}}' | "$BASH_BIN" "$HOOK" 2>&1)
is "a command with a NUL is left alone" "" "$OUT"
OUT=$(printf '%s' '{"tool_input":{"command":["npm test"]}}' | "$BASH_BIN" "$HOOK" 2>&1)
is "a command that isn't a string is left alone" "" "$OUT"

# Already prefixed: never doubled, whatever the root, label or quoting.
state '{}'
while IFS= read -r c; do
  run "$c"; is "already prefixed: $c" "" "$OUT"
done <<'EOF'
bash '/some/other root/scripts/heavy.sh' $$ npm-test; npm test
bash '/a;b&c/scripts/heavy.sh' $$ by-hand.1; npm test
bash "/x/scripts/heavy.sh" $$ my_label; npx vitest
bash /x/scripts/heavy.sh $$ z; npm test
EOF
matches 'npm test' npm-test 'first pass'
FIRST=$(new_command)
run "$FIRST"; is "already prefixed: the hook's own output" "" "$OUT"
c="ls; bash '/x/scripts/heavy.sh' \$\$ y; npm test"
matches "$c" npm-test "prefix further on is not a prefix"

# 4. An ordinary command never starts jq. The stub is known to work: npm test does.
state '{}'
QUIET="$ROOT/npm-test next-build vitest"; mkdir -p "$QUIET"
jq_count() {
  : > "$JQ_CALLS"
  (cd "$1" && event "$2" | PATH="$STUB:$PATH" "$BASH_BIN" "$HOOK" >/dev/null 2>&1)
  wc -l < "$JQ_CALLS" | tr -d ' '
}
is "ordinary: no jq" "0" "$(jq_count "$ROOT" 'ls -la')"
is "ordinary: no jq, npm without test or build" "0" "$(jq_count "$ROOT" 'npm install')"
is "ordinary: no jq, whatever the folder is called" "0" "$(jq_count "$QUIET" 'git status')"
is "stub works: a match starts jq" "yes" "$([ "$(jq_count "$ROOT" 'npm test')" -gt 0 ] && echo yes || echo no)"
state '{"match":{"x":"^make"}}'
is "custom match: jq runs on an ordinary command" "yes" "$([ "$(jq_count "$ROOT" 'ls -la')" -gt 0 ] && echo yes || echo no)"
state '{"match":{"x":"^make"}}'
run 'make all'; is "custom match: found when the key is escaped" "$(prefix x)make all" "$(new_command)"

# 5. Every failure: no output, no rewrite, one failed line.
while IFS='|' read -r name json; do
  state "$json"
  run 'npm test'
  is "$name: no output" "" "$OUT"
  failed_logged "$name"
done <<'EOF'
not JSON|{
not an object|[]
two documents|{} {}
slots a string|{"slots":"2"}
slots zero|{"slots":0}
slots a fraction|{"slots":1.5}
slots null|{"slots":null}
wait_minutes a bool|{"wait_minutes":true}
hold_minutes negative|{"hold_minutes":-1}
hold_minutes an array|{"hold_minutes":[30]}
match an array|{"match":["npm"]}
match a string|{"match":"npm"}
match null|{"match":null}
regex not a string|{"match":{"a":1}}
bad regex|{"match":{"a":"("}}
bad regex after a match|{"match":{"a":"npm","b":"("}}
label with a space|{"match":{"a b":"npm"}}
label with a semicolon|{"match":{"a;rm":"npm"}}
label with a newline|{"match":{"a\nb":"npm"}}
label with a quote|{"match":{"a'b":"npm"}}
label with a dollar|{"match":{"$(x)":"npm"}}
label empty|{"match":{"":"npm"}}
EOF

state
: > "$EXECUTOR_HEAVY_DIR/heavy.json"
run 'npm test'
is "empty file: no output" "" "$OUT"
failed_logged "empty file"

state '{}'
OUT=$(event 'npm test' | PATH="$NO_JQ" "$BASH_BIN" "$HOOK" 2>&1)
is "jq missing: no output" "" "$OUT"
failed_logged "jq missing"

state '{}'
chmod 555 "$EXECUTOR_HEAVY_DIR"
run 'npm test'
is "unwritable folder: no output" "" "$OUT"
is "unwritable folder: no log" "no" "$([ -e "$LOG" ] && echo yes || echo no)"
chmod 755 "$EXECUTOR_HEAVY_DIR"

state '{"slots":"2"}'
run 'ls -la'
is "bad settings, ordinary command: no output" "" "$OUT"
is "bad settings, ordinary command: nothing logged" "no" "$([ -e "$LOG" ] && echo yes || echo no)"

# The plugin root: one that single quotes can't carry fails open, others work.
copy_plugin() {
  mkdir -p "$1/scripts"
  cp "$HOOK" "$SELF_DIR/heavy.sh" "$1/scripts/"
}
state '{}'
Q="$ROOT/it's"; copy_plugin "$Q"
run 'npm test' "$Q/scripts/heavy-hook.sh"
is "root with a quote: no output" "" "$OUT"
failed_logged "root with a quote"

state '{}'
S="$ROOT/a b;c&d"; copy_plugin "$S"
run 'npm test' "$S/scripts/heavy-hook.sh"
is "root with spaces and separators: quoted" "bash '$S/scripts/heavy.sh' \$\$ npm-test; npm test" "$(new_command)"

state '{}'
M="$ROOT/no-script/scripts"; mkdir -p "$M"; cp "$HOOK" "$M/"
run 'npm test' "$M/heavy-hook.sh"
is "no heavy.sh beside the hook: no output" "" "$OUT"
failed_logged "no heavy.sh beside the hook"

# 6. A custom match replaces the defaults, and file order picks the label.
state '{"match":{"zeta":"make","alpha":"make all","anchored":"^deploy","sp.a_c-e":"[[:digit:]]{3}x"}}'
matches 'make all' zeta 'first key in file order'
matches 'FOO=1 BAR="a b" deploy now' anchored 'anchored after assignments'
unmatched 'npm test'
unmatched 'foo deploy'
matches 'echo 123x' sp.a_c-e 'unanchored, extended regex, full label alphabet'
state '{"match":{}}'
unmatched 'npm test'
is "empty match: nothing logged" "no" "$([ -e "$LOG" ] && echo yes || echo no)"
state '{"slots":3,"wait_minutes":1.5,"hold_minutes":2,"other":"ignored"}'
matches 'npm test' npm-test 'all keys valid, unknown key ignored'

# 7. The log never holds the command text, on any path.
SECRET='TOKEN=hunter2-secret'
state '{'; run "$SECRET npm test"; LOGS=$(cat "$LOG" 2>/dev/null)
state '{"match":{"a":"("}}'; run "$SECRET npm test"; LOGS=$LOGS$(cat "$LOG" 2>/dev/null)
state '{"match":{"a b":"npm"}}'; run "$SECRET npm test"; LOGS=$LOGS$(cat "$LOG" 2>/dev/null)
state '{}'; OUT=$(event "$SECRET npm test" | PATH="$NO_JQ" "$BASH_BIN" "$HOOK" 2>&1); LOGS=$LOGS$(cat "$LOG" 2>/dev/null)
state '{"slots":1}'; run "$SECRET npm test"
"$BASH_BIN" -c "$(new_command | sed "s/$SECRET npm test/true/")" >/dev/null 2>&1
until_logged released; LOGS=$LOGS$(cat "$LOG" 2>/dev/null)
is "log: lines were written" "yes" "$([ -n "$LOGS" ] && echo yes || echo no)"
refute "log: no command text" "hunter2" "$LOGS"

# 8. End to end: through bash -c as the Bash tool would, against the real slot script.
E2E="$ROOT/e2e"; mkdir -p "$E2E"
cat > "$E2E/npm" <<'EOF'
#!/usr/bin/env bash
echo "out $*"
echo "err $*" >&2
cat
exit 7
EOF
chmod +x "$E2E/npm"
end_to_end() {
  local name=$1 c=$2 want got want_rc got_rc
  state '{"slots":1}'
  run "$c"
  want=$(PATH="$E2E:$PATH" "$BASH_BIN" -c "$c" 2>&1 </dev/null); want_rc=$?
  got=$(PATH="$E2E:$PATH" "$BASH_BIN" -c "$(new_command)" 2>&1 </dev/null); got_rc=$?
  is "$name: same output" "$want" "$got"
  is "$name: same exit code" "$want_rc" "$got_rc"
  grep -qE '  npm-test  .*  acquired$' "$LOG" && ok "$name: took a slot" || bad "$name: took a slot" "$(cat "$LOG" 2>/dev/null)"
  until_logged released && ok "$name: gave it back" || bad "$name: gave it back" "$(cat "$LOG" 2>/dev/null)"
}
end_to_end 'plain' 'npm test'
end_to_end 'heredoc' $'npm test <<\'EOF\'\nfrom "heredoc" \\ $HOME\nEOF'
end_to_end 'pipe' 'npm test | tr a-z A-Z'
end_to_end 'function' 'f() { echo "in f"; return 4; }; npm test; f'

# The wiring.
is "hooks.json: PreToolUse on Bash runs the hook with a 5 second timeout" \
  '["Bash","bash \"${CLAUDE_PLUGIN_ROOT}/scripts/heavy-hook.sh\"",5]' \
  "$("$REAL_JQ" -c '.hooks.PreToolUse[0] | [.matcher, .hooks[0].command, .hooks[0].timeout]' "$HOOKS_JSON")"

echo
printf 'heavy-hook.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
