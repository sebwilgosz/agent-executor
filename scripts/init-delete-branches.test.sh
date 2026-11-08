#!/usr/bin/env bash
# Spec tests for scripts/init-delete-branches.sh — the engine behind
# /executor:init's "Automatically delete head branches" step. `gh` is stubbed
# and logs every call, so nothing touches GitHub:
#   setting off     → the check reports it off and patches nothing
#   --apply         → exactly one PATCH with delete_branch_on_merge=true
#   setting on      → nothing offered, nothing patched
#   gh failing      → one line, exit 0
#
# Run: bash scripts/init-delete-branches.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
SCRIPT="$SELF_DIR/init-delete-branches.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check(){ case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
export EOW_HOME="$ROOT/eow"

BIN="$ROOT/bin"; mkdir -p "$BIN"
CALLS="$ROOT/calls"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
case "$*" in
  *"-X PATCH"*) [ "${GH_MODE:-}" = fail ] && { echo "boom" >&2; exit 1; }; exit 0 ;;
  *) [ "${GH_MODE:-}" = fail ] && { echo "no network" >&2; exit 1; }
     printf '%s\n' "${GH_SETTING:-false}" ;;
esac
STUB
chmod +x "$BIN/gh"
export GH_CALLS="$CALLS"

REPO="$ROOT/repo"
git init -q "$REPO"
git -C "$REPO" remote add origin git@github.com:acme/widgets.git

run(){ : > "$CALLS"; ( cd "$REPO" && PATH="$BIN:$PATH" bash "$SCRIPT" "$@" 2>&1 ); }
patches(){ grep -c -- '-X PATCH' "$CALLS"; }

echo "init-delete-branches.sh spec tests"

export GH_SETTING=false GH_MODE=ok
out=$(run)
check "check: setting off → STATE: off" "STATE: off" "$out"
check "check: names the repository" "acme/widgets" "$out"
[ "$(patches)" = 0 ] && ok "check: patches nothing" || bad "check: patches nothing" "$(cat "$CALLS")"

out=$(run --apply)
check "apply: reports enabled" "STATE: enabled" "$out"
[ "$(patches)" = 1 ] && ok "apply: exactly one PATCH" || bad "apply: exactly one PATCH" "$(cat "$CALLS")"
check "apply: PATCH sets delete_branch_on_merge=true" "repos/acme/widgets -f delete_branch_on_merge=true" "$(grep PATCH "$CALLS")"

export GH_SETTING=true
out=$(run)
check "check: setting on → STATE: on" "STATE: on" "$out"
[ "$(patches)" = 0 ] && ok "on: nothing patched" || bad "on: nothing patched" "$(cat "$CALLS")"
out=$(run --apply)
[ "$(patches)" = 0 ] && ok "on: --apply patches nothing" || bad "on: --apply patches nothing" "$(cat "$CALLS")"

export GH_MODE=fail
out=$(run); rc=$?
check "gh failing: STOP line" "STOP:" "$out"
[ "$(printf '%s\n' "$out" | grep -c .)" = 2 ] && ok "gh failing: one line besides the target" || bad "gh failing: one line besides the target" "$out"
run >/dev/null; rc=$?
[ "$rc" = 0 ] && ok "gh failing: exit 0" || bad "gh failing: exit 0" "rc=$rc"
export GH_SETTING=false
out=$(run --apply)
check "apply failing: STOP line" "STOP:" "$out"

export GH_MODE=ok
git -C "$REPO" remote remove origin
out=$(run)
check "no remote: STOP line" "STOP:" "$out"
run >/dev/null; rc=$?
[ "$rc" = 0 ] && ok "no remote: exit 0" || bad "no remote: exit 0" "rc=$rc"

echo
printf 'init-delete-branches.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
