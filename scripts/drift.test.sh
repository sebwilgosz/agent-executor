#!/usr/bin/env bash
# Spec tests for the drift check (scripts/drift.sh) as status.sh and self-audit.sh -v
# use it: a repo has drifted only when Executor's own worktrees or branches are left
# from finished builds (the ones scripts/repo-tidy.sh removes). A checkout on a
# finished branch, a default behind origin and a user's own branches are not drift.
# A clean repo says nothing, and so does a repo when GitHub can't be asked. No
# network: a local bare repo under $ROOT/gh stands in for github.com and a stub gh
# answers `gh pr list` from files under $ROOT/prs and `gh pr view` for status.sh's
# plan lookups.
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
echo "$*" >> "$PRS/../ghcalls"
case "$*" in
  *number*)
    [ ! -f "$PRS/named" ] || sed 's/^/77 /' "$PRS/named"
    exit 0 ;;
esac
head=""
while [ $# -gt 0 ]; do
  [ "$1" != "--head" ] || head=$2
  shift
done
if [ -n "$head" ]; then
  [ ! -f "$PRS/$head" ] || cat "$PRS/$head"
else
  for f in "$PRS"/*; do
    [ -f "$f" ] && [ "${f##*/}" != down ] && [ "${f##*/}" != named ] || continue
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
builder_wt() {
  branch_with_pr "$1" "$2"
  git -C "$REPO" worktree add -q "$ROOT/wt-$3" "$1"
}
plan() {
  mkdir -p "$EOW_HOME/executor/plans/acme/api"
  printf '# B\n\n## S\n- [ ] One - PR #77 hammer\n' > "$EOW_HOME/executor/plans/acme/api/2026-01-01 - x.md"
}
status() { ( cd "$ELSEWHERE" && "$SHELL_BIN" "$STATUS" 2>&1 ); }
audit_v() { ( cd "$REPO" && ROOT="$SELF_DIR/.." "$SHELL_BIN" "$AUDIT" -v 2>&1 ); }
drift_line() { printf '%s\n' "$1" | grep DRIFT; }

plan
echo "drift spec tests"

# A clean repo: nothing.
fresh
out=$(status)
check "clean: the repo is still listed" "acme/api" "$out"
refute "clean: status prints no DRIFT" "DRIFT" "$out"
refute "clean: self-audit -v prints no DRIFT" "DRIFT" "$(audit_v)"
check "clean: self-audit -v says none" "drift: none" "$(audit_v)"

# The old reasons are gone: default behind origin and the checkout on a merged
# branch, with nothing of Executor's left over.
fresh; branch_with_pr feat-a MERGED; git -C "$REPO" switch -q feat-a
printf 'two\n' > "$SEED/two.txt"
git -C "$SEED" add two.txt; git -C "$SEED" commit -q -m two; git -C "$SEED" push -q origin main
git -C "$REPO" fetch -q origin
refute "behind origin, on a merged branch, no leftovers: no DRIFT" "DRIFT" "$(status)"
check "behind origin, on a merged branch: self-audit -v says none" "drift: none" "$(audit_v)"
git -C "$SEED" reset -q --hard HEAD~1; git -C "$SEED" push -q -f origin main

# One finished builder worktree.
for state in MERGED CLOSED; do
  fresh; builder_wt worktree-agent-a "$state" 1
  out=$(status)
  is "$state builder worktree: the DRIFT line" "  DRIFT: 1 worktree left from finished builds - fix: repo-tidy.sh $REPO" "$(drift_line "$out")"
  check "$state builder worktree: DRIFT sits under the repo" "acme/api"$'\n'"  DRIFT" "$out"
  check "$state builder worktree: self-audit -v reports it" "DRIFT: 1 worktree left" "$(audit_v)"
done

# A worktree under .claude/worktrees/agent-, its branch already in main.
fresh; mkdir -p "$REPO/.claude/worktrees"
git -C "$REPO" worktree add -q -b scratch "$REPO/.claude/worktrees/agent-q" main
check "agent- folder, branch in main: DRIFT" "1 worktree left" "$(status)"

# Not finished: an open PR.
fresh; builder_wt worktree-agent-a OPEN 1
refute "open PR builder worktree: no DRIFT" "DRIFT" "$(status)"

# A user's own merged branch, in a worktree or not, is not counted.
fresh; builder_wt feat-a MERGED 1; branch_with_pr feat-b MERGED
refute "user's own merged branch and worktree: no DRIFT" "DRIFT" "$(status)"

# Leftover branches, checked out nowhere, and the wording of the counts.
fresh; branch_with_pr worktree-agent-b MERGED
is "one builder branch" "  DRIFT: 1 branch left from finished builds - fix: repo-tidy.sh $REPO" "$(drift_line "$(status)")"
branch_with_pr worktree-agent-c MERGED
is "two builder branches" "  DRIFT: 2 branches left from finished builds - fix: repo-tidy.sh $REPO" "$(drift_line "$(status)")"
builder_wt worktree-agent-a MERGED 1
is "one worktree, two branches" "  DRIFT: 1 worktree and 2 branches left from finished builds - fix: repo-tidy.sh $REPO" "$(drift_line "$(status)")"
builder_wt worktree-agent-d MERGED 2
is "two worktrees, two branches" "  DRIFT: 2 worktrees and 2 branches left from finished builds - fix: repo-tidy.sh $REPO" "$(drift_line "$(status)")"
check "self-audit -v gives the same line" "DRIFT: 2 worktrees and 2 branches left" "$(audit_v)"

# A branch the plan names by PR is Executor's own.
fresh; branch_with_pr feat-named MERGED; echo feat-named > "$PRS/named"
check "plan-named merged branch: DRIFT" "1 branch left" "$(status)"
rm -f "$PRS/named"

# A builder branch checked out in the main checkout is not left over.
fresh; branch_with_pr worktree-agent-b MERGED; git -C "$REPO" switch -q worktree-agent-b
refute "builder branch is the checkout: no DRIFT" "DRIFT" "$(status)"

# A builder branch with commits after the merged PR stays, so it is not drift.
fresh; branch_with_pr worktree-agent-b MERGED
git -C "$REPO" switch -q worktree-agent-b; printf 'x\n' > "$REPO/more.txt"
git -C "$REPO" add more.txt; git -C "$REPO" commit -q -m more; git -C "$REPO" switch -q main
refute "commits after the merged PR: no DRIFT" "DRIFT" "$(status)"

# No PR, tip already in origin/main: finished.
fresh; git -C "$REPO" branch worktree-agent-e
check "no PR, tip in origin/main: DRIFT" "1 branch left" "$(status)"

# GitHub can't be asked: no guess.
fresh; builder_wt worktree-agent-a MERGED 1
: > "$PRS/down"
refute "gh down: no DRIFT" "DRIFT" "$(status)"
refute "gh down: self-audit -v no DRIFT" "DRIFT" "$(audit_v)"
check "gh down: self-audit -v says none" "drift: none" "$(audit_v)"
rm -f "$PRS/down"

# At most two PR listings per repo: status runs this for every repo under a hook timeout.
fresh; builder_wt worktree-agent-a MERGED 1; branch_with_pr worktree-agent-b MERGED
rm -f "$ROOT/ghcalls"
( . "$SELF_DIR/drift.sh"; repo_drift "$REPO" )
is "at most two gh calls per repo" "ok" "$([ "$(grep -c 'pr list' "$ROOT/ghcalls")" -le 2 ] && echo ok || echo many)"

# Read-only, and one definition.
fresh; builder_wt worktree-agent-a MERGED 1
before=$(cd "$REPO" && git rev-parse HEAD; git branch --show-current; git status --porcelain; git for-each-ref)
status >/dev/null
after=$(cd "$REPO" && git rev-parse HEAD; git branch --show-current; git status --porcelain; git for-each-ref)
is "status leaves the repo untouched" "$before" "$after"
is "self-audit reuses drift.sh, no second copy" "" "$(grep -n 'branch_finished\|worktree list' "$AUDIT" "$STATUS")"

echo
printf 'drift: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
