#!/usr/bin/env bash
# Spec tests for scripts/self-audit.sh's search-roots checks: SETUP warns once
# per configured root (or the default ~/Projects) that is not a directory,
# saying what to do, and says ok once when all are there; INTEGRITY errors
# when the roots reader is missing. The audit's contract holds throughout:
# exit 0, summary line last.
# No network: a stub `gh` on PATH answers as a signed-in gh with gh stack;
# HOME and EOW_HOME point at a temp dir.
#
# Run: bash scripts/self-audit.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)
AUDIT="$SELF_DIR/self-audit.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }
count() { printf '%s\n' "$2" | grep -cF -- "$1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
export HOME="$TMP/home"; mkdir -p "$HOME"
export EOW_HOME="$TMP/eow"
CFG="$EOW_HOME/executor/config.md"

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "--version ") echo "gh version 2.99.0 (2026-01-01)" ;;
  "auth status") exit 0 ;;
  "extension list") echo "gh stack  github/gh-stack  v0.3.0" ;;
esac
exit 0
STUB
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

config(){ mkdir -p "$(dirname "$CFG")"; printf '%s\n' "$@" > "$CFG"; }
audit(){ bash "$AUDIT" "$@"; }
summary_last(){ printf '%s\n' "$2" | tail -1 | grep -q '^  executor: ' && ok "$1" || bad "$1" "last line: $(printf '%s\n' "$2" | tail -1)"; }

echo "self-audit.sh search-roots spec tests"

# 1. Every configured root is a directory: one ok line, no warning.
mkdir -p "$HOME/code" "$TMP/srv"
config "# Executor settings" "" "## Roots" "- ~/code" "- $TMP/srv"
out=$(audit -v); rc=$?
check  "all roots present: one ok line" "✓ setup: search roots" "$out"
[ "$(count '✓ setup: search roots' "$out")" -eq 1 ] && ok "all roots present: exactly one ok line" \
  || bad "all roots present: exactly one ok line" "$out"
refute "all roots present: no root warning" "⚠ setup: search root" "$out"
check  "all roots present: PASS" "executor: PASS" "$out"
[ "$rc" -eq 0 ] && ok "all roots present: exit 0" || bad "all roots present: exit 0" "exit $rc"
summary_last "all roots present: summary line last" "$out"

# 2. A configured root that is missing: a warning naming it, ending with what to do.
config "## Roots" "- ~/code" "- ~/gone" "- $TMP/also-gone"
out=$(audit); rc=$?
line=$(printf '%s\n' "$out" | grep -F '⚠ setup: search root' | grep -F 'gone' | head -1)
check  "missing root: warned"             "gone" "$line"
check  "missing root: says what to do"    "→ create the folder, or change the roots with /executor:init" "$line"
[ "$(count '⚠ setup: search root' "$out")" -eq 2 ] && ok "missing roots: one warning per missing root" \
  || bad "missing roots: one warning per missing root" "$out"
check  "missing root: the other missing root is named too" "also-gone" "$out"
refute "missing root: the present root is not warned" "search root ~/code " "$(printf '%s\n' "$out" | grep -F '⚠ setup: search root')"
refute "missing root: no ok line for roots" "✓ setup: search roots" "$(audit -v)"
check  "missing root: WARN" "executor: WARN" "$out"
[ "$rc" -eq 0 ] && ok "missing root: exit 0" || bad "missing root: exit 0" "exit $rc"
summary_last "missing root: summary line last" "$out"
audit --strict >/dev/null; rc=$?
[ "$rc" -eq 1 ] && ok "missing root: --strict exits 1" || bad "missing root: --strict exits 1" "exit $rc"

# 3. Nothing configured: the default ~/Projects is checked.
rm -rf "$EOW_HOME"
out=$(audit)
check "no config, no ~/Projects: warned" "Projects" "$(printf '%s\n' "$out" | grep -F '⚠ setup: search root')"
mkdir -p "$HOME/Projects"
out=$(audit -v)
check  "no config, ~/Projects there: ok" "✓ setup: search roots" "$out"
refute "no config, ~/Projects there: no warning" "⚠ setup: search root" "$out"

# 4. A root that is a file, not a folder, is missing too.
: > "$HOME/afile"
config "## Roots" "- ~/afile"
check "a file is not a root" "afile" "$(audit | grep -F '⚠ setup: search root')"

# 5. INTEGRITY: the roots reader is checked like the other scripts.
PLUG="$TMP/plugin"; mkdir -p "$PLUG"
for d in .claude-plugin agents hooks references scripts skills; do cp -R "$REPO/$d" "$PLUG/"; done
out=$(ROOT="$PLUG" audit)
refute "reader present: no integrity error" "scripts/roots.sh" "$out"
rm -f "$PLUG/scripts/roots.sh"
out=$(ROOT="$PLUG" audit); rc=$?
check "reader missing: integrity error" "✗ integrity: scripts/roots.sh missing" "$out"
check "reader missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F 'scripts/roots.sh')"
[ "$rc" -eq 0 ] && ok "reader missing: exit 0" || bad "reader missing: exit 0" "exit $rc"
summary_last "reader missing: summary line last" "$out"

# 6. INTEGRITY: the plans resolver is checked like the other scripts.
PLUG="$TMP/plugin2"; mkdir -p "$PLUG"
for d in .claude-plugin agents hooks references scripts skills; do cp -R "$REPO/$d" "$PLUG/"; done
out=$(ROOT="$PLUG" audit)
refute "resolver present: no integrity error" "scripts/plan-path.sh" "$out"
rm -f "$PLUG/scripts/plan-path.sh"
out=$(ROOT="$PLUG" audit); rc=$?
check "resolver missing: integrity error" "✗ integrity: scripts/plan-path.sh missing" "$out"
check "resolver missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F 'scripts/plan-path.sh')"
[ "$rc" -eq 0 ] && ok "resolver missing: exit 0" || bad "resolver missing: exit 0" "exit $rc"

# 7. INTEGRITY: so are the scripts that tell and mark a finished plan.
for s in plan-state plan-sweep; do
  cp "$REPO/scripts/plan-path.sh" "$PLUG/scripts/"
  cp "$REPO/scripts/plan-state.sh" "$REPO/scripts/plan-sweep.sh" "$PLUG/scripts/"
  out=$(ROOT="$PLUG" audit)
  refute "$s present: no integrity error" "scripts/$s.sh" "$out"
  rm -f "$PLUG/scripts/$s.sh"
  out=$(ROOT="$PLUG" audit); rc=$?
  check "$s missing: integrity error" "✗ integrity: scripts/$s.sh missing" "$out"
  check "$s missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F "scripts/$s.sh")"
  [ "$rc" -eq 0 ] && ok "$s missing: exit 0" || bad "$s missing: exit 0" "exit $rc"
done

echo
printf 'self-audit.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
