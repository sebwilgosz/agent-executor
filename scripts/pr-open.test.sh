#!/usr/bin/env bash
# Spec tests for scripts/pr-open.sh - one call from a finished branch to an open PR.
# No network: a local bare repo is the "origin" and a stub `gh` on PATH answers
# `gh pr list`, `gh stack ...` and `gh pr create|edit`, recording every call.
#
# Run: bash scripts/pr-open.test.sh   (exit 0 = all pass, non-zero = a failure)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
POPEN="$SELF_DIR/pr-open.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check(){ case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
BIN="$ROOT/bin"; mkdir -p "$BIN"
export GH_DIR="$ROOT/gh"; export GH_CALLS="$ROOT/calls.log"
export EOW_HOME="$ROOT/eow"

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
br=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
file(){ printf '%s/pr-%s.json' "$GH_DIR" "${1//\//_}"; }
newpr(){
  printf '[{"number":7,"url":"https://github.com/o/r/pull/7","state":"OPEN","baseRefName":"%s"}]\n' "$1" > "$(file "$br")"
}
case "$1 $2" in
  "pr list")
    h=""; while [ $# -gt 0 ]; do [ "$1" = "--head" ] && h=$2; shift; done
    if [ -f "$(file "$h")" ]; then cat "$(file "$h")"; else printf '[]\n'; fi ;;
  "stack view")
    grep -qx "$br" "$GH_DIR/stacked" 2>/dev/null && exit 0
    echo "not in a stack" >&2; exit 2 ;;
  "stack init") # like gh-stack: a branch already in a stack can't start another
    shift 2
    for b in "$@"; do grep -qx "$b" "$GH_DIR/stacked" 2>/dev/null && { echo "branch \"$b\" already exists in a stack" >&2; exit 5; }; done
    printf '%s\n' "$@" >> "$GH_DIR/stacked" ;;
  "stack add") # only from the top of a stack; adopts the branch, checkout unchanged
    [ "$(tail -1 "$GH_DIR/stacked" 2>/dev/null)" = "$br" ] || { echo "can only add branches to the top of the stack" >&2; exit 5; }
    echo "$3" >> "$GH_DIR/stacked"; echo "add-from $br" >> "$GH_CALLS" ;;
  "stack submit")
    [ -n "${GH_SUBMIT_EXIT:-}" ] && { echo "stacked PRs not enabled" >&2; exit "$GH_SUBMIT_EXIT"; }
    git push -q origin "$br" || exit 1
    newpr "${GH_NEW_BASE:-main}" ;;
  "pr create")
    b=""; while [ $# -gt 0 ]; do [ "$1" = "--base" ] && b=$2; shift; done
    newpr "$b"; echo "https://github.com/o/r/pull/7" ;;
  "pr edit")
    while [ $# -gt 0 ]; do
      case "$1" in --body-file) cp "$2" "$GH_DIR/edited-body" ;; --title) echo "$2" > "$GH_DIR/edited-title" ;; esac
      shift
    done ;;
  "repo view") printf '\n' ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

commit(){ printf '%s\n' "$2" > "$WORK/$1"; git -C "$WORK" add "$1"; git -C "$WORK" commit -qm "add $1"; }

fresh(){
  rm -rf "$ROOT/origin.git" "$ROOT/work" "$GH_DIR" "$ROOT/body.md"
  mkdir -p "$GH_DIR"; : > "$GH_CALLS"
  ORIGIN="$ROOT/origin.git"; WORK="$ROOT/work"
  git init -q --bare "$ORIGIN"
  git init -q -b main "$WORK"
  git -C "$WORK" config user.email t@t.t; git -C "$WORK" config user.name t
  git -C "$WORK" remote add origin "$ORIGIN"
  commit a.txt a
  git -C "$WORK" push -q -u origin main
  git -C "$WORK" remote set-head origin main
  printf '## What changes\n- a thing\n\n## Depends on\n#99\n' > "$ROOT/body.md"
}
feature(){ git -C "$WORK" checkout -q -b "$1" "$2"; commit "$3" "$3"; }
run(){ ( cd "$WORK" && bash "$POPEN" --branch "$1" --below "$2" --title "My feature" --body-file "${3:-$ROOT/body.md}" 2>&1 ); }
on_origin(){ git -C "$ORIGIN" rev-parse --verify -q "refs/heads/$1" >/dev/null; }
depends(){ sed -n '/## Depends on/,$p' "$GH_DIR/edited-body"; }

echo "pr-open.sh spec tests"

# new stack on the default branch
fresh; feature feat/one main b.txt
out=$(run feat/one default)
check "new stack: PR line, opened, base is the default branch" "PR: #7 https://github.com/o/r/pull/7 base=main opened" "$out"
check "new stack: starts the stack" "stack init feat/one" "$(cat "$GH_CALLS")"
check "new stack: submits non-interactively" "stack submit --auto" "$(cat "$GH_CALLS")"
on_origin feat/one && ok "new stack: branch is pushed" || bad "new stack: branch is pushed" "not on origin"
check "new stack: title set" "My feature" "$(cat "$GH_DIR/edited-title")"
check "new stack: Depends on is nothing" "nothing" "$(depends)"
refute "new stack: stale Depends on replaced" "#99" "$(cat "$GH_DIR/edited-body")"
check "new stack: the rest of the body is kept" "- a thing" "$(cat "$GH_DIR/edited-body")"
[ "$(grep -c '## Depends on' "$GH_DIR/edited-body")" = 1 ] && ok "new stack: one Depends on section" || bad "new stack: one Depends on section" "$(cat "$GH_DIR/edited-body")"

# added on top of a branch that has an open PR
fresh; feature feat/lower main l.txt; git -C "$WORK" push -q origin feat/lower
printf '[{"number":5,"url":"https://github.com/o/r/pull/5","state":"OPEN","baseRefName":"main"}]\n' > "$GH_DIR/pr-feat_lower.json"
feature feat/top feat/lower t.txt
out=$(GH_NEW_BASE=feat/lower run feat/top feat/lower)
check "on top: base is the branch below" "base=feat/lower opened" "$out"
check "on top: adopts both branches into a stack" "stack init feat/lower feat/top" "$(cat "$GH_CALLS")"
check "on top: Depends on is the PR below" "#5" "$(depends)"

# added on top of a branch already in a stack (the build case: the builder below stacked it)
fresh; feature feat/lower main l.txt; git -C "$WORK" push -q origin feat/lower
printf '[{"number":5,"url":"https://github.com/o/r/pull/5","state":"OPEN","baseRefName":"main"}]\n' > "$GH_DIR/pr-feat_lower.json"
echo feat/lower > "$GH_DIR/stacked"
feature feat/top feat/lower t.txt
out=$(GH_NEW_BASE=feat/lower run feat/top feat/lower)
check "stacked below: base is the branch below" "base=feat/lower opened" "$out"
check "stacked below: adopted on top of that stack, from the branch below" "stack add feat/top
add-from feat/lower" "$(cat "$GH_CALLS")"
check "stacked below: now in the stack" "feat/top" "$(cat "$GH_DIR/stacked")"
check "stacked below: opened through the stack" "stack submit --auto" "$(cat "$GH_CALLS")"
refute "stacked below: no plain PR outside the stack" "pr create" "$(cat "$GH_CALLS")"
[ "$(git -C "$WORK" branch --show-current)" = feat/top ] && ok "stacked below: checkout stays on the branch" || bad "stacked below: checkout stays on the branch" "$(git -C "$WORK" branch --show-current)"
[ "$(git -C "$WORK" worktree list | wc -l | tr -d ' ')" = 1 ] && ok "stacked below: no worktree left behind" || bad "stacked below: no worktree left behind" "$(git -C "$WORK" worktree list)"

# base merged: retarget onto the default branch
fresh; feature feat/lower main l.txt; git -C "$WORK" push -q origin feat/lower
printf '[{"number":5,"url":"u","state":"MERGED","baseRefName":"main"}]\n' > "$GH_DIR/pr-feat_lower.json"
feature feat/top feat/lower t.txt; git -C "$WORK" push -q origin feat/top
git -C "$WORK" checkout -q main; commit m.txt m; git -C "$WORK" merge -q --no-ff -m merge feat/lower; git -C "$WORK" push -q origin main
git -C "$WORK" push -q origin --delete feat/lower; git -C "$WORK" checkout -q feat/top
out=$(run feat/top feat/lower)
check "merged base: RETARGETED line" "RETARGETED: feat/lower merged, based on main instead" "$out"
check "merged base: PR on the default branch" "base=main opened" "$out"
git -C "$WORK" merge-base --is-ancestor origin/main feat/top && ok "merged base: branch rebased onto the default branch" || bad "merged base: branch rebased onto the default branch" "origin/main is not an ancestor"
[ "$(git -C "$WORK" rev-parse feat/top)" = "$(git -C "$ORIGIN" rev-parse feat/top)" ] && ok "merged base: rebased branch is pushed" || bad "merged base: rebased branch is pushed" "origin differs"
check "merged base: Depends on is nothing" "nothing" "$(depends)"

# rebase conflict: abort and STOP naming the file
fresh; feature feat/lower main l.txt; git -C "$WORK" push -q origin feat/lower
printf '[{"number":5,"url":"u","state":"MERGED","baseRefName":"main"}]\n' > "$GH_DIR/pr-feat_lower.json"
feature feat/top feat/lower c.txt
git -C "$WORK" checkout -q main; commit c.txt other; git -C "$WORK" push -q origin main
git -C "$WORK" checkout -q feat/top; before=$(git -C "$WORK" rev-parse HEAD)
out=$(run feat/top feat/lower)
check "conflict: STOP" "STOP:" "$out"
check "conflict: names the file" "c.txt" "$out"
refute "conflict: nothing opened" "PR:" "$out"
[ ! -d "$WORK/.git/rebase-merge" ] && [ ! -d "$WORK/.git/rebase-apply" ] && [ "$(git -C "$WORK" rev-parse HEAD)" = "$before" ] && ok "conflict: rebase aborted, branch untouched" || bad "conflict: rebase aborted, branch untouched" "rebase left behind"
on_origin feat/top && bad "conflict: nothing pushed" "on origin" || ok "conflict: nothing pushed"

# no stacked PRs (submit exits 9): plain draft PR, same result
fresh; feature feat/one main b.txt
out=$(GH_SUBMIT_EXIT=9 run feat/one default)
check "no stacks: PR line" "PR: #7 https://github.com/o/r/pull/7 base=main opened" "$out"
check "no stacks: plain draft PR on the same base" "pr create --draft --base main --head feat/one" "$(cat "$GH_CALLS")"
on_origin feat/one && ok "no stacks: branch is pushed" || bad "no stacks: branch is pushed" "not on origin"

# a PR already exists: updated, never a second one
fresh; feature feat/one main b.txt
printf '[{"number":42,"url":"https://github.com/o/r/pull/42","state":"OPEN","baseRefName":"main"}]\n' > "$GH_DIR/pr-feat_one.json"
out=$(run feat/one default)
check "existing: PR line is updated" "PR: #42 https://github.com/o/r/pull/42 base=main updated" "$out"
refute "existing: no second PR" "pr create" "$(cat "$GH_CALLS")"
refute "existing: no submit" "stack submit" "$(cat "$GH_CALLS")"
check "existing: edits title and body" "pr edit 42" "$(cat "$GH_CALLS")"
on_origin feat/one && ok "existing: branch is pushed" || bad "existing: branch is pushed" "not on origin"

# below exists but has no open PR: STOP, nothing pushed
fresh; feature feat/lower main l.txt; feature feat/top feat/lower t.txt
out=$(run feat/top feat/lower)
check "below without PR: STOP says to open it first" "STOP: feat/lower has no open PR - open it first" "$out"
on_origin feat/top && bad "below without PR: nothing pushed" "on origin" || ok "below without PR: nothing pushed"
refute "below without PR: no submit" "stack submit" "$(cat "$GH_CALLS")"

# guards
fresh; feature feat/one main b.txt; printf 'x\n' > "$WORK/dirty.txt"; git -C "$WORK" add dirty.txt
check "dirty tree: STOP" "STOP:" "$(run feat/one default)"
fresh; git -C "$WORK" checkout -q main
check "default branch as --branch: STOP" "STOP:" "$(run main default)"
fresh; feature feat/one main b.txt
check "missing body file: STOP" "STOP:" "$(run feat/one default "$ROOT/nope.md")"
refute "missing body file: nothing submitted" "stack submit" "$(cat "$GH_CALLS")"

# failures become a STOP and a log line
fresh; feature feat/one main b.txt; git -C "$WORK" remote set-url origin "$ROOT/does-not-exist.git"
out=$(run feat/one default)
check "failure: STOP, not a raw error" "STOP:" "$out"
[ -s "$EOW_HOME/executor/pr-open.log" ] && ok "failure: logged" || bad "failure: logged" "pr-open.log empty or missing"

echo
printf 'pr-open.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
