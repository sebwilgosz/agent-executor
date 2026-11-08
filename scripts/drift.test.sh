#!/usr/bin/env bash
# Spec tests for the drift check (scripts/drift.sh) as status.sh and self-audit.sh -v
# use it: a repo has drifted when its checkout sits on a branch whose PR is finished,
# when its local default is behind origin, or when more than 3 linked worktrees sit
# on finished branches. A clean repo says nothing, and so does a repo when GitHub
# can't be asked. No network: a local bare repo under $ROOT/gh stands in for
# github.com and a stub gh answers `gh pr list --head <branch>` from files under
# $ROOT/prs and `gh pr view` for status.sh's plan lookups.
#
# Run: bash scripts/drift.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
STATUS="$SELF_DIR/status.sh"
AUDIT="$SELF_DIR/self-audit.sh"
SHELL_BIN=bash
[ -x /bin/bash ] && SHELL_BIN=/bin/bash

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

ROOT=$(cd -P "$(mktemp -d)" && pwd)
trap 'rm -rf "$ROOT"' EXIT
export EOW_HOME="$ROOT/eow"
export HOME="$ROOT/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$ROOT/gitconfig"
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
GH="$ROOT/gh"
PRS="$ROOT/prs"; mkdir -p "$PRS"
BIN="$ROOT/bin"; mkdir -p "$BIN"
PROJECTS="$ROOT/projects"; mkdir -p "$PROJECTS"
ELSEWHERE="$ROOT/elsewhere"; mkdir -p "$ELSEWHERE"

git config --global user.email t@example.com
git config --global user.name T
git config --global init.defaultBranch main
git config --global advice.detachedHead false
for pre in "git@github.com:" "https://github.com/" "ssh://git@github.com/"; do
  git config --global --add "url.$GH/.insteadOf" "$pre"
done

cat > "$BIN/gh" <<'STUB'
#!/bin/sh
[ ! -e "$PRS/down" ] || { echo "error connecting to api.github.com" >&2; exit 1; }
if [ "$1 $2" = "pr view" ]; then
  echo "OPEN false SUCCESS"
  exit 0
fi
if [ "$1 $2" = "--version " ]; then echo "gh version 2.99.0 (2026-01-01)"; exit 0; fi
head=""
while [ $# -gt 0 ]; do
  [ "$1" != "--head" ] || head=$2
  shift
done
if [ -n "$head" ]; then
  [ ! -f "$PRS/$head" ] || cat "$PRS/$head"
else
  for f in "$PRS"/*; do
    [ -f "$f" ] && [ "${f##*/}" != down ] || continue
    sed "s|^|${f##*/} |" "$f"
  done
fi
exit 0
STUB
chmod +x "$BIN/gh"
export PRS
export PATH="$BIN:$PATH"

mkdir -p "$EOW_HOME/executor"
printf '## Roots\n- %s\n' "$PROJECTS" > "$EOW_HOME/executor/config.md"

SEED="$ROOT/seed"
git init -q --bare --initial-branch=main "$GH/acme/api.git"
git clone -q "https://github.com/acme/api.git" "$SEED" 2>/dev/null
printf 'one\n' > "$SEED/file.txt"
git -C "$SEED" add file.txt
git -C "$SEED" commit -q -m init
git -C "$SEED" push -q origin main

REPO="$PROJECTS/api"
fresh() {
  rm -rf "$REPO" "$ROOT"/wt-*; rm -f "$PRS"/*
  git -C "$REPO" worktree prune 2>/dev/null
  git clone -q "https://github.com/acme/api.git" "$REPO"
  git -C "$REPO" remote set-head origin main >/dev/null 2>&1
}
# A branch with one commit whose PR is <state>. Leaves the checkout on main.
branch_with_pr() {
  local b=$1 state=$2
  git -C "$REPO" switch -q -c "$b"
  printf '%s\n' "$b" > "$REPO/$b.txt"
  git -C "$REPO" add "$b.txt"
  git -C "$REPO" commit -q -m "add $b"
  printf '%s %s\n' "$state" "$(git -C "$REPO" rev-parse HEAD)" > "$PRS/$b"
  git -C "$REPO" switch -q main
}
plan() {
  mkdir -p "$EOW_HOME/executor/plans/acme/api"
  printf '# B\n\n## S\n- [ ] One - PR #77 hammer\n' > "$EOW_HOME/executor/plans/acme/api/2026-01-01 - x.md"
}
status() { ( cd "$ELSEWHERE" && "$SHELL_BIN" "$STATUS" 2>&1 ); }
audit_v() { ( cd "$REPO" && ROOT="$SELF_DIR/.." "$SHELL_BIN" "$AUDIT" -v 2>&1 ); }

plan
echo "drift spec tests"

# A clean repo: nothing.
fresh
out=$(status)
check "clean: the repo is still listed" "acme/api" "$out"
refute "clean: status prints no DRIFT" "DRIFT" "$out"
refute "clean: self-audit -v prints no DRIFT" "DRIFT" "$(audit_v)"
check "clean: self-audit -v says none" "drift: none" "$(audit_v)"

# (a) The checkout on a branch whose PR is merged, or closed.
for state in MERGED CLOSED; do
  fresh; branch_with_pr feat-a "$state"; git -C "$REPO" switch -q feat-a
  out=$(status)
  check "$state branch: status prints DRIFT" "DRIFT" "$out"
  check "$state branch: names the branch" "feat-a" "$(printf '%s\n' "$out" | grep DRIFT)"
  check "$state branch: names the fix" "repo-tidy.sh $REPO" "$(printf '%s\n' "$out" | grep DRIFT)"
  is "$state branch: one DRIFT line" 1 "$(printf '%s\n' "$out" | grep -c DRIFT)"
  check "$state branch: DRIFT sits under the repo" "acme/api"$'\n'"  DRIFT" "$out"
  check "$state branch: self-audit -v reports it" "DRIFT" "$(audit_v)"
  check "$state branch: self-audit -v names the fix" "repo-tidy.sh $REPO" "$(audit_v)"
done

# An open PR is not drift.
fresh; branch_with_pr feat-a OPEN; git -C "$REPO" switch -q feat-a
refute "open PR: no DRIFT" "DRIFT" "$(status)"

# No PR, but everything is in origin/main: finished.
fresh; git -C "$REPO" switch -q -c feat-b
check "no PR, nothing new: DRIFT" "DRIFT" "$(status)"

# GitHub can't be asked: no guess.
fresh; branch_with_pr feat-a MERGED; git -C "$REPO" switch -q feat-a
: > "$PRS/down"
refute "gh down: no DRIFT" "DRIFT" "$(status)"
refute "gh down: self-audit -v no DRIFT" "DRIFT" "$(audit_v)"
rm -f "$PRS/down"

# (b) The local default behind origin.
fresh
printf 'two\n' > "$SEED/two.txt"
git -C "$SEED" add two.txt; git -C "$SEED" commit -q -m two; git -C "$SEED" push -q origin main
git -C "$REPO" fetch -q origin
out=$(status)
check "main behind: status prints DRIFT" "DRIFT" "$out"
check "main behind: says by how much" "1 behind origin/main" "$out"
check "main behind: names the fix" "repo-tidy.sh $REPO" "$out"
check "main behind: self-audit -v reports it" "1 behind origin/main" "$(audit_v)"
git -C "$REPO" merge -q --ff-only origin/main
refute "main caught up: no DRIFT" "DRIFT" "$(status)"

# (c) More than 3 linked worktrees on finished branches.
fresh
for i in 1 2 3; do
  branch_with_pr "w$i" MERGED
  git -C "$REPO" worktree add -q "$ROOT/wt-$i" "w$i"
done
refute "3 finished worktrees: no DRIFT" "DRIFT" "$(status)"
branch_with_pr w4 MERGED
git -C "$REPO" worktree add -q "$ROOT/wt-4" w4
out=$(status)
check "4 finished worktrees: DRIFT" "DRIFT" "$out"
check "4 finished worktrees: says how many" "4 worktrees" "$out"
check "4 finished worktrees: names the fix" "repo-tidy.sh $REPO" "$out"
check "4 finished worktrees: self-audit -v reports it" "4 worktrees" "$(audit_v)"
: > "$PRS/down"
refute "4 worktrees, gh down: no DRIFT" "DRIFT" "$(status)"
rm -f "$PRS/down"
printf '%s %s\n' OPEN "$(git -C "$REPO" rev-parse w4)" > "$PRS/w4"
refute "3 finished and 1 open: no DRIFT" "DRIFT" "$(status)"

# Read-only, and one definition.
fresh; branch_with_pr feat-a MERGED; git -C "$REPO" switch -q feat-a
before=$(cd "$REPO" && git rev-parse HEAD; git branch --show-current; git status --porcelain; git for-each-ref)
status >/dev/null
after=$(cd "$REPO" && git rev-parse HEAD; git branch --show-current; git status --porcelain; git for-each-ref)
is "status leaves the repo untouched" "$before" "$after"
is "self-audit reuses drift.sh, no second copy" "" "$(grep -n 'branch_finished\|worktree list' "$AUDIT" "$STATUS")"

echo
printf 'drift: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
