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

# 8. INTEGRITY: and the migration of legacy plans.
cp "$REPO/scripts/plans-migrate.sh" "$PLUG/scripts/"
refute "plans-migrate present: no integrity error" "scripts/plans-migrate.sh" "$(ROOT="$PLUG" audit)"
rm -f "$PLUG/scripts/plans-migrate.sh"
out=$(ROOT="$PLUG" audit); rc=$?
check "plans-migrate missing: integrity error" "✗ integrity: scripts/plans-migrate.sh missing" "$out"
check "plans-migrate missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F "scripts/plans-migrate.sh")"
[ "$rc" -eq 0 ] && ok "plans-migrate missing: exit 0" || bad "plans-migrate missing: exit 0" "exit $rc"

# 9. INTEGRITY: and the one reader of a plan's items.
cp "$REPO/scripts/plan-items.sh" "$PLUG/scripts/"
refute "plan-items present: no integrity error" "scripts/plan-items.sh" "$(ROOT="$PLUG" audit)"
rm -f "$PLUG/scripts/plan-items.sh"
out=$(ROOT="$PLUG" audit); rc=$?
check "plan-items missing: integrity error" "✗ integrity: scripts/plan-items.sh missing" "$out"
check "plan-items missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F "scripts/plan-items.sh")"
[ "$rc" -eq 0 ] && ok "plan-items missing: exit 0" || bad "plan-items missing: exit 0" "exit $rc"

# 10. INTEGRITY: and the review's docs check.
refute "docs-mentions present: no integrity error" "scripts/docs-mentions.sh" "$(ROOT="$PLUG" audit)"
rm -f "$PLUG/scripts/docs-mentions.sh"
out=$(ROOT="$PLUG" audit); rc=$?
check "docs-mentions missing: integrity error" "✗ integrity: scripts/docs-mentions.sh missing" "$out"
check "docs-mentions missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F "scripts/docs-mentions.sh")"
[ "$rc" -eq 0 ] && ok "docs-mentions missing: exit 0" || bad "docs-mentions missing: exit 0" "exit $rc"

# 11. INTEGRITY: and the script behind /executor:status.
cp "$REPO/scripts/status.sh" "$PLUG/scripts/"
refute "status present: no integrity error" "scripts/status.sh" "$(ROOT="$PLUG" audit)"
rm -f "$PLUG/scripts/status.sh"
out=$(ROOT="$PLUG" audit); rc=$?
check "status missing: integrity error" "✗ integrity: scripts/status.sh missing" "$out"
check "status missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F "scripts/status.sh")"
[ "$rc" -eq 0 ] && ok "status missing: exit 0" || bad "status missing: exit 0" "exit $rc"

# 12. /executor:status is a user-only skill the help lists, and the audit says so.
PLUG="$TMP/plugin3"; mkdir -p "$PLUG"
for d in .claude-plugin agents hooks references scripts skills; do cp -R "$REPO/$d" "$PLUG/"; done
out=$(ROOT="$PLUG" audit -v)
check  "status skill: named among the user-only skills" "✓ integrity: help, init and status run only when you type them" "$out"
refute "status skill: no integrity warning" "⚠ integrity" "$out"
sed '/^disable-model-invocation:/d' "$REPO/skills/status/SKILL.md" > "$PLUG/skills/status/SKILL.md"
out=$(ROOT="$PLUG" audit -v)
check  "status skill model-invocable: integrity error" "✗ integrity: status lost disable-model-invocation" "$out"
refute "status skill model-invocable: the ok line is gone" "run only when you type them" "$out"

# 13. The skill and the help may run the script, and the help routes to it.
HELP="$REPO/skills/help/SKILL.md"
for f in "$REPO/skills/status/SKILL.md" "$HELP"; do
  check "${f#"$REPO"/}: allowed-tools runs status.sh" 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh)' "$(grep '^allowed-tools:' "$f")"
done
check "help block lists the command" "/executor:status" "$(awk '/^## HELP$/{h=1} h' "$HELP" | awk '/^```$/{f++; next} f==1')"
row=$(grep -F '"where are my builds"' "$HELP")
check "help routing: what's in flight too" "\"what's in flight\"" "$row"
check "help routing: runs the script" 'run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh`' "$row"
check "README lists the command" '`/executor:status`' "$(cat "$REPO/README.md")"

# 14. INTEGRITY: and the review's ready step.
refute "review-ready present: no integrity error" "scripts/review-ready.sh" "$(ROOT="$PLUG" audit)"
rm -f "$PLUG/scripts/review-ready.sh"
out=$(ROOT="$PLUG" audit); rc=$?
check "review-ready missing: integrity error" "✗ integrity: scripts/review-ready.sh missing" "$out"
check "review-ready missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F "scripts/review-ready.sh")"
[ "$rc" -eq 0 ] && ok "review-ready missing: exit 0" || bad "review-ready missing: exit 0" "exit $rc"

# 15. INTEGRITY: and the heavy command queue's slot script.
refute "heavy present: no integrity error" "scripts/heavy.sh" "$(ROOT="$PLUG" audit)"
rm -f "$PLUG/scripts/heavy.sh"
out=$(ROOT="$PLUG" audit); rc=$?
check "heavy missing: integrity error" "✗ integrity: scripts/heavy.sh missing" "$out"
check "heavy missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F "scripts/heavy.sh")"
[ "$rc" -eq 0 ] && ok "heavy missing: exit 0" || bad "heavy missing: exit 0" "exit $rc"

# 16. INTEGRITY: and the queue's hook, present and wired.
refute "heavy hook present: no integrity error" "heavy-hook.sh" "$(ROOT="$PLUG" audit)"
rm -f "$PLUG/scripts/heavy-hook.sh"
out=$(ROOT="$PLUG" audit); rc=$?
check "heavy hook missing: integrity error" "✗ integrity: scripts/heavy-hook.sh missing" "$out"
check "heavy hook missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F "scripts/heavy-hook.sh")"
[ "$rc" -eq 0 ] && ok "heavy hook missing: exit 0" || bad "heavy hook missing: exit 0" "exit $rc"
cp "$REPO/scripts/heavy-hook.sh" "$PLUG/scripts/"
sed '/heavy-hook/d' "$REPO/hooks/hooks.json" > "$PLUG/hooks/hooks.json"
out=$(ROOT="$PLUG" audit)
check "heavy hook unwired: integrity error" "✗ integrity: hooks/hooks.json no longer runs heavy-hook.sh" "$out"
check "heavy hook unwired: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F "no longer runs heavy-hook.sh")"

# 17. INTEGRITY: and the spec home resolver. It reports the file that names the
#     home for the current folder, or says none is named; it never warns.
mkdir -p "$TMP/named/sub" "$TMP/unnamed"
printf '## Specs\nSpecs: Notion.\n' > "$TMP/named/AGENTS.md"
out=$(cd "$TMP/named/sub" && ROOT="$PLUG" audit -v)
check  "spec home present: ok line" "✓ integrity: the spec home resolver is present" "$out"
check  "spec home named: prints the file" "spec home: named in " "$out"
check  "spec home named: it is the AGENTS.md" "/named/AGENTS.md" "$out"
out=$(cd "$TMP/unnamed" && ROOT="$PLUG" audit -v)
check  "spec home unnamed: says to run init" "no spec home named; run /executor:init" "$out"
refute "spec home unnamed: no warning for it" "⚠ spec home" "$out"
rm -f "$PLUG/scripts/spec-home.sh"
out=$(ROOT="$PLUG" audit); rc=$?
check "spec home missing: integrity error" "✗ integrity: scripts/spec-home.sh missing" "$out"
check "spec home missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F "scripts/spec-home.sh")"
[ "$rc" -eq 0 ] && ok "spec home missing: exit 0" || bad "spec home missing: exit 0" "exit $rc"

# 18. INTEGRITY: and the ticket script.
refute "ticket script present: no integrity error" "ticket-github.sh" "$(ROOT="$PLUG" audit)"
rm -f "$PLUG/scripts/ticket-github.sh"
out=$(ROOT="$PLUG" audit)
check "ticket script missing: integrity error" "✗ integrity: scripts/ticket-github.sh missing" "$out"
check "ticket script missing: says what to do" "→ reinstall" "$(printf '%s\n' "$out" | grep -F "scripts/ticket-github.sh")"

# 19. INTEGRITY: the copy lists what Executor does. A README that still says
#     "What it does today: review", or a description that omits build, warns.
copy_ok(){ rm -rf "$PLUG"; mkdir -p "$PLUG"; for d in .claude-plugin agents hooks references scripts skills; do cp -R "$REPO/$d" "$PLUG/"; done; cp "$REPO/README.md" "$PLUG/"; }
copy_ok
out=$(ROOT="$PLUG" audit -v)
refute "product copy current: no copy warning" "⚠ integrity: the copy" "$out"
check  "product copy current: ok line" "✓ integrity: the copy names what Executor does" "$out"
printf '## What it does today: review\n' >> "$PLUG/README.md"
out=$(ROOT="$PLUG" audit)
check "stale README: warned" "⚠ integrity: the copy in README.md" "$out"
check "stale README: says what to do" "→ " "$(printf '%s\n' "$out" | grep -F 'the copy in README.md')"
copy_ok
sed -i.bak 's/Today that is code review of a pull request/Today that is code review/; s/^description: ".*"/description: "Executor front door: code review of a pull request."/' "$PLUG/skills/help/SKILL.md"
check "help description omits build: warned" "⚠ integrity: the copy in skills/help/SKILL.md" "$(ROOT="$PLUG" audit)"
copy_ok
sed -i.bak 's/"description": ".*"/"description": "Executor reviews every pull request. Free."/' "$PLUG/.claude-plugin/plugin.json"
check "plugin.json description omits build: warned" "⚠ integrity: the copy in .claude-plugin/plugin.json" "$(ROOT="$PLUG" audit)"
copy_ok
printf 'Today that is code review of a PR\n' >> "$PLUG/README.md"
check "old help phrase in README: warned" "⚠ integrity: the copy in README.md" "$(ROOT="$PLUG" audit)"
audit_rc=$(ROOT="$PLUG" audit >/dev/null; echo $?)
[ "$audit_rc" -eq 0 ] && ok "stale copy: exit 0" || bad "stale copy: exit 0" "exit $audit_rc"

echo
printf 'self-audit.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
