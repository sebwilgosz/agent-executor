#!/usr/bin/env bash
# Spec tests for scripts/heavy.sh — heavy commands take turns machine-wide, and
# the queue always fails open. Every test has its own state folder through
# EXECUTOR_HEAVY_DIR, so the real one is never touched. Each "command" is its own
# bash, called the way the Bash tool calls it: heavy.sh $$ <label>; <command>.
#
# Timing is tolerant of a loaded machine: a limit that says how soon something
# must happen is measured from when it was caused, a test waits for the log rather
# than sleeping a fixed time, and a 5-second check that overruns gets two more
# tries, so it can only pass if the slot really came free in time.
#
# Run: bash scripts/heavy.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
HEAVY="$SELF_DIR/heavy.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }
within(){ [ "$3" -le "$2" ] && ok "$1" || bad "$1" "want at most $2 s | took $3 s"; }

ROOT=$(cd -P "$(mktemp -d)" && pwd)
SHELLS=()
cleanup() {
  local p
  for p in "${SHELLS[@]:-}"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done
  chmod -R u+w "$ROOT" 2>/dev/null
  rm -rf "$ROOT"
}
trap cleanup EXIT

# Longest a test waits for something that should happen, on any machine load.
PATIENCE=60
N=0
state() {
  N=$((N+1))
  export EXECUTOR_HEAVY_DIR="$ROOT/state$N"
  LOG="$EXECUTOR_HEAVY_DIR/heavy.log"
  mkdir -p "$EXECUTOR_HEAVY_DIR"
  [ $# -eq 0 ] || printf '%s\n' "$1" > "$EXECUTOR_HEAVY_DIR/heavy.json"
}

outcomes() { [ -f "$LOG" ] || { echo 0; return; }; grep -cE "  $1(  |\$)" "$LOG"; }
until_logged() {
  local deadline=$((SECONDS+PATIENCE))
  while [ "$(outcomes "$1")" -lt "$2" ]; do
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 0.1
  done
}
slot_files() { find "$EXECUTOR_HEAVY_DIR" -name '*.lock' | wc -l | tr -d ' '; }

# A shell that takes a slot, then stays until it is stopped. HELD is its pid.
hold() {
  local before; before=$(outcomes acquired)
  mkdir -p "$2"
  bash -c 'cd "$3" && bash "$1" $$ "$2"; while :; do sleep 0.2; done' _ "$HEAVY" "$1" "$2" >/dev/null 2>&1 &
  HELD=$!
  disown "$HELD"
  SHELLS+=("$HELD")
  until_logged acquired $((before+1)) || bad "hold $1" "the slot was never acquired"
}

# One call from a shell of its own that exits when the call returns.
call() { bash -c 'bash "$1" $$ "$2"' _ "$HEAVY" "$1" 2>&1; }

nice_of() { ps -o nice= -p "$1" | tr -d ' '; }

echo "heavy.sh spec tests"

# 1. Six commands started at once with two slots.
state '{"slots":2,"wait_minutes":3}'
M="$ROOT/markers"; mkdir -p "$M"
SIX='bash "$1" $$ six; d=$2
touch "$d/in.$$"
ls "$d" | grep -c "^in\." >> "$d/../counts"
sleep 2
rm -f "$d/in.$$"
touch "$d/done.$$"'
PIDS=()
for i in 1 2 3 4 5 6; do
  bash -c "$SIX" _ "$HEAVY" "$M" >/dev/null 2>&1 &
  PIDS+=($!)
done
wait "${PIDS[@]}"
is "six at once: never more than 2 running" "2" "$(sort -n "$ROOT/counts" | tail -1)"
is "six at once: all ran" "6" "$(wc -l < "$ROOT/counts" | tr -d ' ')"
is "six at once: all finished" "6" "$(find "$M" -name 'done.*' | wc -l | tr -d ' ')"
is "six at once: all took a slot" "6" "$(outcomes acquired)"
is "six at once: none gave up" "0" "$(outcomes wait-expired)"

# 2. A slot is free within 5 seconds of its shell being killed with SIGKILL.
#    A second command is already waiting, so taking the slot proves it free.
free_after_kill() {
  state '{"slots":1,"wait_minutes":3}'
  hold first "$ROOT/first"
  local holder=$HELD err="$ROOT/waiting.$N" deadline
  bash -c 'bash "$1" $$ second; sleep 0.2' _ "$HEAVY" 2>"$err" >/dev/null &
  local waiter=$!
  deadline=$((SECONDS+PATIENCE))
  while [ ! -s "$err" ] && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.1; done
  SECONDS=0
  kill -9 "$holder"
  until_logged acquired 2
  ELAPSED=$SECONDS
  wait "$waiter"
}
for try in 1 2 3; do
  free_after_kill
  [ "$ELAPSED" -le 5 ] && break
done
within "SIGKILL: the slot is free within 5 s" 5 "$ELAPSED"
is "SIGKILL: the next command took it" "2" "$(outcomes acquired)"
until_logged released 1
check "SIGKILL: the release is logged" "released" "$(grep '  first  ' "$LOG")"

# A shell that has exited but that its parent hasn't reaped still has its pid.
unreaped_after_exit() {
  state '{"slots":1}'
  HEAVY="$HEAVY" perl -e 'my $c = fork; unless ($c) { exec "bash", "-c", q{bash "$HEAVY" $$ ghost} } sleep 120' >/dev/null 2>&1 &
  local parent=$!
  disown "$parent"
  SHELLS+=("$parent")
  until_logged acquired 1
  SECONDS=0
  until_logged released 1
  ELAPSED=$SECONDS
  kill -9 "$parent"
}
for try in 1 2 3; do
  unreaped_after_exit
  [ "$ELAPSED" -le 5 ] && break
done
within "unreaped shell: the slot is free within 5 s" 5 "$ELAPSED"

# A shell stopped while it waits ends the wait, and takes no slot later.
state '{"slots":1,"wait_minutes":3}'
hold first "$ROOT/first"
bash -c 'bash "$1" $$ stopped; sleep 0.2' _ "$HEAVY" >/dev/null 2>"$ROOT/stopped" &
STOPPED=$!
disown "$STOPPED"
deadline=$((SECONDS+PATIENCE))
while [ ! -s "$ROOT/stopped" ] && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.1; done
kill -9 "$STOPPED"
until_logged failed 1 && ok "stopped while waiting: logs failed" || bad "stopped while waiting: logs failed" "it kept waiting"
is "stopped while waiting: no slot" "1" "$(outcomes acquired)"
kill -9 "$HELD"

# 3. The wait limit, with all slots held.
state '{"slots":1,"wait_minutes":0.05}'
hold busy "$ROOT/busy dir"
SECONDS=0
out=$(call late)
took=$SECONDS
[ "$took" -ge 2 ] && ok "wait limit: it did wait" || bad "wait limit: it did wait" "returned after $took s"
within "wait limit: returns once it passes" 30 "$took"
is "wait limit: logged" "1" "$(outcomes wait-expired)"
check "wait limit: the log names the label" "  late  " "$(grep wait-expired "$LOG")"
is "waiting: one line on stderr" "1" "$(printf '%s\n' "$out" | grep -c '')"
check "waiting: names the label of what holds the slots" "busy" "$out"
check "waiting: names the cwd of what holds the slots" "$ROOT/busy dir" "$out"
is "wait limit: the slot stays with its holder" "1" "$(outcomes acquired)"

# 4. The hold limit: the slot goes, the shell stays.
state '{"slots":1,"hold_minutes":0.05}'
hold long "$ROOT/long"
until_logged hold-expired 1 && ok "hold limit: logged" || bad "hold limit: logged" "no hold-expired line"
kill -0 "$HELD" 2>/dev/null && ok "hold limit: the shell is still alive" || bad "hold limit: the shell is still alive" "it was killed"
SECONDS=0
is "hold limit: no output for the next command" "" "$(call next)"
within "hold limit: the next command does not wait" 20 "$SECONDS"
is "hold limit: the next command took the slot" "2" "$(outcomes acquired)"
kill -9 "$HELD"

# 5. A held slot keeps none of the caller's pipes open. The shell here outlives
#    the call, so the pipes can only close if the holder let go of them. If it
#    didn't, the watchdog ends the shell, and the check after it fails.
state '{"slots":1}'
bash -c 'while :; do sleep 0.2; done' >/dev/null 2>&1 &
LONG=$!
disown "$LONG"
SHELLS+=("$LONG")
( sleep "$PATIENCE"; kill -9 "$LONG" 2>/dev/null ) >/dev/null 2>&1 &
DOG=$!
disown "$DOG"
out=$(exec 4>&1; bash "$HEAVY" "$LONG" piped 2>&1 </dev/null | cat)
kill -0 "$LONG" 2>/dev/null && ok "pipes: the call returned while its slot was held" || bad "pipes: the call returned while its slot was held" "it only returned when the shell died"
is "pipes: nothing printed" "" "$out"
is "pipes: acquired" "1" "$(outcomes acquired)"
is "pipes: not yet released" "0" "$(outcomes released)"
kill -9 "$LONG" 2>/dev/null
kill -9 "$DOG" 2>/dev/null

state '{"slots":1}'
out=$(bash -c 'bash "$1" $$ piped; echo done' _ "$HEAVY" | cat)
is "pipes: a piped call returns once its shell finishes" "done" "$out"

# 6. The log: its fields, and never the command text.
state '{}'
WHERE="$ROOT/logged"; mkdir -p "$WHERE"
bash -c 'cd "$2" && bash "$1" $$ npm-test; API_TOKEN=hunter2-xyz sleep 1' _ "$HEAVY" "$WHERE" >/dev/null 2>&1
until_logged released 1
line=$(grep '  acquired' "$LOG")
check "log: acquired line has the label and cwd" "  npm-test  $WHERE  " "$line"
printf '%s\n' "$line" | grep -qE '  waited=[0-9]+  acquired$' && ok "log: acquired line has the seconds waited" || bad "log: acquired line has the seconds waited" "$line"
printf '%s\n' "$line" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}  ' && ok "log: starts with the time" || bad "log: starts with the time" "$line"
printf '%s\n' "$(grep '  released' "$LOG")" | grep -qE 'released  held=[0-9]+$' && ok "log: released line has seconds held" || bad "log: released line has seconds held" "$(cat "$LOG")"
refute "log: never the command text" "hunter2" "$(cat "$LOG")"
refute "log: never the command's words" "API_TOKEN" "$(cat "$LOG")"

state '{}'
call $'two\nlines' >/dev/null
until_logged released 1
is "log: a label cannot split a line" "2" "$(wc -l < "$LOG" | tr -d ' ')"

# 7. Turned off, and every way it fails open.
state
SECONDS=0
out=$(bash -c 'a=$(ps -o nice= -p $$); bash "$1" $$ off; rc=$?; b=$(ps -o nice= -p $$); echo "$rc:$((b-a))"' _ "$HEAVY" 2>&1)
is "no heavy.json: nothing printed, exit 0, no renice" "0:0" "$out"
within "no heavy.json: returns at once" 20 "$SECONDS"
[ ! -e "$LOG" ] && ok "no heavy.json: no log line" || bad "no heavy.json: no log line" "$(cat "$LOG")"
is "no heavy.json: no slot" "0" "$(slot_files)"

state '{}'
SECONDS=0
out=$(call quiet)
is "no wait: prints nothing" "" "$out"
within "no wait: returns at once" 20 "$SECONDS"

fails_open() {
  state "$2"
  SECONDS=0
  local out rc
  out=$(call broken); rc=$?
  is "$1: nothing printed" "" "$out"
  is "$1: exit 0" "0" "$rc"
  within "$1: returns promptly" 20 "$SECONDS"
  is "$1: logs failed" "1" "$(outcomes failed)"
  is "$1: no slot" "0" "$(slot_files)"
}
fails_open "bad JSON" '{nope'
fails_open "empty file" ''
fails_open "not an object" '[2]'
fails_open "slots is a string" '{"slots":"2"}'
fails_open "slots is not whole" '{"slots":1.5}'
fails_open "slots is zero" '{"slots":0}'
fails_open "wait_minutes is a boolean" '{"wait_minutes":true}'
fails_open "wait_minutes is null" '{"wait_minutes":null}'
fails_open "hold_minutes is a list" '{"hold_minutes":[1]}'
fails_open "hold_minutes is negative" '{"hold_minutes":-1}'

state '{}'
bash -c ':' &
DEAD=$!
wait "$DEAD"
SECONDS=0
out=$(bash "$HEAVY" "$DEAD" gone 2>&1); rc=$?
is "pid already gone: nothing printed" "" "$out"
is "pid already gone: exit 0" "0" "$rc"
within "pid already gone: returns at once" 20 "$SECONDS"
is "pid already gone: logs failed" "1" "$(outcomes failed)"
is "pid already gone: no slot" "0" "$(slot_files)"

state '{}'
out=$(bash "$HEAVY" nonsense bad 2>&1); rc=$?
is "pid not a number: nothing printed, exit 0" ":0" "$out:$rc"
is "pid not a number: logs failed" "1" "$(outcomes failed)"
is "pid not a number: no slot" "0" "$(slot_files)"

state '{}'
BARE="$ROOT/bare"; mkdir -p "$BARE"; ln -s "$(command -v date)" "$BARE/date"
out=$(PATH="$BARE" "$BASH" -c '"$1" "$2" $$ noperl' _ "$BASH" "$HEAVY" 2>&1); rc=$?
is "perl missing: nothing printed, exit 0" ":0" "$out:$rc"
is "perl missing: logs failed" "1" "$(outcomes failed)"
is "perl missing: no slot" "0" "$(slot_files)"

state '{}'
chmod 555 "$EXECUTOR_HEAVY_DIR"
if [ -w "$EXECUTOR_HEAVY_DIR" ]; then
  echo "  skip unwritable state folder: this user can write anywhere"
else
  SECONDS=0
  out=$(call sandboxed); rc=$?
  is "unwritable state folder: nothing printed" "" "$out"
  is "unwritable state folder: exit 0" "0" "$rc"
  within "unwritable state folder: returns promptly" 20 "$SECONDS"
  is "unwritable state folder: no slot" "0" "$(slot_files)"
fi
chmod 755 "$EXECUTOR_HEAVY_DIR"

# 8. Lower priority: the shell, so its children inherit it.
state '{}'
out=$(bash -c 'a=$(ps -o nice= -p $$); bash "$1" $$ low; b=$(ps -o nice= -p $$); sleep 1 & c=$(ps -o nice= -p $!); echo "$((b-a)):$((c-a))"' _ "$HEAVY" 2>&1)
is "renice: the shell and its children run 10 lower" "10:10" "$out"

# 9. Defaults: {} means two slots.
state '{"wait_minutes":0.03}'
hold a "$ROOT/a"; A=$HELD
hold b "$ROOT/b"; B=$HELD
is "default slots: two held" "2" "$(outcomes acquired)"
out=$(call third)
is "default slots: the third gave up" "1" "$(outcomes wait-expired)"
check "waiting: one line names every holder" "$ROOT/a" "$out"
check "waiting: one line names every holder" "$ROOT/b" "$out"

# 10. slots lowered while slots are held: A and B keep running, and new ones use
#     only the new count, even when the slot that came free is within it.
printf '%s\n' '{"slots":1,"wait_minutes":0.03}' > "$EXECUTOR_HEAVY_DIR/heavy.json"
kill -9 "$A"
until_logged released 1
kill -0 "$B" 2>/dev/null && ok "slots lowered: the running command keeps going" || bad "slots lowered: the running command keeps going" "it was stopped"
call fourth >/dev/null
is "slots lowered: a new one waits while one still runs" "2" "$(outcomes acquired)"
is "slots lowered: and gives up at the limit" "2" "$(outcomes wait-expired)"
kill -9 "$B"
until_logged released 2
call fifth >/dev/null
is "slots lowered: runs again once under the new count" "3" "$(outcomes acquired)"

echo
printf 'heavy.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
