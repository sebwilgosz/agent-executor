#!/usr/bin/env bash
# Spec tests for scripts/ship.sh — the deterministic engine behind /executor:ship.
# One case per requirement of Feature A's guard / idempotence / base-branch math.
# No network: a local bare repo is the "origin" and a stub `gh` on PATH answers
# `gh pr list` and `gh stack view`, so the test exercises ship.sh's branching
# honestly without shaping the script to it.
#
# Run: bash scripts/ship.test.sh   (exit 0 = all pass, non-zero = a failure)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
SHIP="$SELF_DIR/ship.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check(){ # name  expected-substring  actual
  case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac
}
refute(){ # name  forbidden-substring  actual
  case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac
}

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
BIN="$ROOT/bin"; mkdir -p "$BIN"

# Stub gh: reads $GH_PR_LIST / $GH_STACK files for each subcommand's reply.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "pr list")
    [ -n "${GH_PR_LIST:-}" ] && [ -f "$GH_PR_LIST" ] && cat "$GH_PR_LIST" || printf '[]\n' ;;
  "stack view")
    if [ -n "${GH_STACK:-}" ] && [ -f "$GH_STACK" ]; then cat "$GH_STACK"; exit 0
    else echo "not part of a stack" >&2; exit 2; fi ;;
  "repo view") printf '\n' ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"
export EOW_HOME="$ROOT/eow"
export GH_PR_LIST=""
export GH_STACK=""

# A bare "origin" plus a work repo with a default branch (main) and origin/HEAD.
ORIGIN="$ROOT/origin.git"
git init -q --bare "$ORIGIN"
WORK="$ROOT/work"
git init -q -b main "$WORK"
cd "$WORK"
git config user.email t@t.t; git config user.name t
git remote add origin "$ORIGIN"
printf 'a\n' > a.txt; git add a.txt; git commit -qm init
git push -q -u origin main
git remote set-head origin main

run(){ ( cd "$WORK" && bash "$SHIP" 2>&1 ); }

echo "ship.sh spec tests"

# 1. Guard: on the default branch → stop.
git -C "$WORK" checkout -q main
check "guard: stops on the default branch" "STOP" "$(run)"

# 2. Guard: a feature branch with no commits beyond default → stop.
git -C "$WORK" checkout -q -b feat/empty main
check "guard: stops with no commits beyond default" "STOP" "$(run)"

# 3. Open path: feature branch with a commit, no existing PR → OPEN_PR base=main.
git -C "$WORK" checkout -q -b feat/one main
printf 'b\n' > "$WORK/b.txt"; git -C "$WORK" add b.txt; git -C "$WORK" commit -qm feat
export GH_PR_LIST=""   # stub returns []
out=$(run)
check "open: pushes the branch"            "PUSHED" "$out"
check "open: asks to open a draft PR"       "OPEN_PR" "$out"
check "open: base is the default branch"    "base=main" "$out"

# 4. Idempotence: a PR already exists → push only, never a second PR.
printf '[{"number":42,"url":"https://github.com/o/r/pull/42"}]\n' > "$ROOT/prlist.json"
export GH_PR_LIST="$ROOT/prlist.json"
out=$(run)
check  "idempotent: still pushes"            "PUSHED" "$out"
check  "idempotent: reports the existing PR" "#42" "$out"
refute "idempotent: never asks to open another PR" "OPEN_PR" "$out"

# 5. Base math: in a multi-branch stack → base is the branch below. gh stack's
#    real JSON gives each branch's base as a commit SHA (not a name), so the
#    stub mirrors that: the current branch's base is the SHA that is the branch
#    below's head, and ship.sh must resolve it back to that branch's name.
export GH_PR_LIST=""
cat > "$ROOT/stack.json" <<'JSON'
{"trunk":"main","currentBranch":"feat/one","branches":[
  {"name":"feat/lower","head":"2222222222222222222222222222222222222222","base":"1111111111111111111111111111111111111111","isCurrent":false},
  {"name":"feat/one","head":"3333333333333333333333333333333333333333","base":"2222222222222222222222222222222222222222","isCurrent":true}]}
JSON
export GH_STACK="$ROOT/stack.json"
out=$(run)
check  "stack: base is the branch below, resolved from its SHA" "base=feat/lower" "$out"
refute "stack: base is never a raw commit SHA" "222222222222" "$out"

# 5b. Bottom of a stack: the current branch's base is the trunk commit, which no
#     stack branch has as its head → base falls back to the default branch, never
#     a bare SHA (the bug the name-shaped stub used to hide).
cat > "$ROOT/stack-bottom.json" <<'JSON'
{"trunk":"main","currentBranch":"feat/one","branches":[
  {"name":"feat/one","head":"3333333333333333333333333333333333333333","base":"1111111111111111111111111111111111111111","isCurrent":true}]}
JSON
export GH_STACK="$ROOT/stack-bottom.json"
out=$(run)
check  "stack bottom: base is the default branch" "base=main" "$out"
refute "stack bottom: base is never a raw commit SHA" "111111111111" "$out"
export GH_STACK=""

# 6. Failure is logged and returned as a note, never a raw failed call.
git -C "$WORK" remote set-url origin "$ROOT/does-not-exist.git"
out=$(run)
check "failure: returns a STOP note"         "STOP" "$out"
[ -s "$EOW_HOME/executor/ship.log" ] && ok "failure: logged to ship.log" \
  || bad "failure: logged to ship.log" "ship.log is empty or missing"
git -C "$WORK" remote set-url origin "$ORIGIN"

echo
printf 'ship.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
