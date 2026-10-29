#!/usr/bin/env bash
# Spec tests for the version assertion the entry skills (build, ship, init) run
# at their start. Two parts, one case per requirement:
#   A. scripts/version-check.sh — the deterministic engine. A fake plugin root
#      (its own .claude-plugin/plugin.json) stands in for the installed plugin,
#      so the match / mismatch / unreadable branches are exercised honestly.
#   B. the three entry skills are wired to it, baking the installed version, so
#      a stale snapshot stops with a reload note instead of a generic failure.
#
# Run: bash scripts/version-check.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)
CHECK="$SELF_DIR/version-check.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check(){ case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

ROOTDIR=$(mktemp -d)
trap 'rm -rf "$ROOTDIR"' EXIT

# A fake installed plugin root: only the manifest the script reads.
FAKE="$ROOTDIR/plugin"
mkdir -p "$FAKE/.claude-plugin"
printf '{\n  "name": "executor",\n  "version": "0.3.0"\n}\n' > "$FAKE/.claude-plugin/plugin.json"

run(){ ROOT="$FAKE" bash "$CHECK" "$@" 2>&1; }

echo "version-check.sh spec tests"

# 1. The loaded snapshot matches the installed plugin → OK, carry on.
out=$(run 0.3.0)
check  "match: reports OK with the version" "OK: executor 0.3.0" "$out"
refute "match: no mismatch"                 "MISMATCH" "$out"

# 2. A stale snapshot (older loaded version) → one-line mismatch naming the fix.
out=$(run 0.1.4)
check "stale: reports a MISMATCH"              "MISMATCH" "$out"
check "stale: names the loaded version"        "0.1.4" "$out"
check "stale: names the installed version"     "0.3.0" "$out"
check "stale: the fix is to reload or restart" "reload the plugin or start a fresh session" "$out"
# The whole message is one line, not a wall of generic error text.
lines=$(printf '%s\n' "$out" | grep -c .)
[ "$lines" -eq 1 ] && ok "stale: the message is a single line" \
  || bad "stale: the message is a single line" "got $lines lines: $out"

# 3. Any difference is a mismatch, including a newer loaded version.
check "drift either way is a mismatch" "MISMATCH" "$(run 0.4.0)"

# 4. The exit code is always 0 — a stop is a note, never a raw failed call.
run 0.1.4 >/dev/null 2>&1; [ $? -eq 0 ] && ok "mismatch exits 0 (a note, not a crash)" \
  || bad "mismatch exits 0" "non-zero exit on a mismatch"

# 5. No argument → a STOP note, deterministically, never a crash.
out=$(ROOT="$FAKE" bash "$CHECK" 2>&1); rc=$?
check "no argument: STOP note" "STOP" "$out"
[ "$rc" -eq 0 ] && ok "no argument: still exits 0" || bad "no argument: still exits 0" "exit $rc"

# 6. Missing / unreadable manifest → a STOP note, not a mismatch and not a crash.
out=$(ROOT="$ROOTDIR/nope" bash "$CHECK" 0.3.0 2>&1); rc=$?
check  "no manifest: STOP note" "STOP" "$out"
refute "no manifest: not a false mismatch" "MISMATCH" "$out"
[ "$rc" -eq 0 ] && ok "no manifest: still exits 0" || bad "no manifest: still exits 0" "exit $rc"

# 7. Wiring: each entry skill asserts the version at its start, baking the
#    installed version, so the guard above actually runs when the skill does.
if command -v jq >/dev/null 2>&1; then
  pv=$(jq -r '.version // empty' "$REPO/.claude-plugin/plugin.json")
else
  pv=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$REPO/.claude-plugin/plugin.json" | head -1 | grep -oE '"[^"]+"$' | tr -d '"')
fi
for s in build ship init; do
  f="$REPO/skills/$s/SKILL.md"
  bv=$(grep -oE "version-check\.sh[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+" "$f" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ -z "$bv" ]; then
    bad "wiring: $s calls version-check.sh" "no version-check.sh invocation in $f"
  elif [ "$bv" = "$pv" ]; then
    ok "wiring: $s asserts the installed version ($pv)"
  else
    bad "wiring: $s asserts the installed version" "skill bakes $bv but the plugin is $pv"
  fi
done

echo
printf 'version-check.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
