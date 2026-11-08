#!/usr/bin/env bash
# Spec tests for scripts/repo-tidy.sh - tidies one repo after merges: returns the
# checkout to the default branch, removes finished worktrees, deletes merged local
# branches, and never touches anything dirty or any remote branch. One case per
# rule. No network: a local bare repo under $ROOT/gh stands in for github.com and
# a stub gh answers `gh pr list --head <branch>` from files under $ROOT/prs.
#
# Run: bash scripts/repo-tidy.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
TIDY="$SELF_DIR/repo-tidy.sh"
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
GH="$ROOT/gh"
PRS="$ROOT/prs"; mkdir -p "$PRS"
BIN="$ROOT/bin"; mkdir -p "$BIN"
ELSEWHERE="$ROOT/elsewhere"; mkdir -p "$ELSEWHERE"
TLOG="$EOW_HOME/executor/tidy.log"

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
head=""
while [ $# -gt 0 ]; do
  [ "$1" != "--head" ] || head=$2
  shift
done
[ -z "$head" ] || [ ! -f "$PRS/$head" ] || cat "$PRS/$head"
exit 0
STUB
chmod +x "$BIN/gh"
export PRS
export PATH="$BIN:$PATH"

SEED="$ROOT/seed"
git init -q --bare --initial-branch=main "$GH/acme/api.git"
git clone -q "https://github.com/acme/api.git" "$SEED" 2>/dev/null
printf 'one\n' > "$SEED/file.txt"
git -C "$SEED" add file.txt
git -C "$SEED" commit -q -m init
git -C "$SEED" push -q origin main

N=0
fresh() {
  N=$((N+1)); CASE="$ROOT/case$N"; REPO="$CASE/api"; mkdir -p "$CASE"
  rm -f "$PRS"/*
  git clone -q "https://github.com/acme/api.git" "$REPO"
  mkdir -p "$EOW_HOME/executor"; : > "$TLOG"
}
# A feature branch with one commit, squash-merged on GitHub: main gains the same
# change as a new commit, so git sees the branch as unmerged. The stub PR is
# MERGED with the branch's tip as its head. Leaves the clone on that branch.
squash_merged() {
  local b=$1
  git -C "$REPO" switch -q -c "$b"
  printf '%s\n' "$b" > "$REPO/$b.txt"
  git -C "$REPO" add "$b.txt"
  git -C "$REPO" commit -q -m "add $b"
  printf 'MERGED %s\n' "$(git -C "$REPO" rev-parse HEAD)" > "$PRS/$b"
  printf '%s\n' "$b" > "$SEED/$b.txt"
  git -C "$SEED" add "$b.txt"
  git -C "$SEED" commit -q -m "add $b (#1)"
  git -C "$SEED" push -q origin main
}
tidy() {
  ( cd "$ELSEWHERE" && "$SHELL_BIN" "$TIDY" "$@" 2>&1 ); printf 'rc=%s\n' "$?"
}
branches() { git -C "$REPO" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' '; }
snapshot() {
  ( cd "$1" && find . -path ./.git -prune -o -type f -exec cksum {} + | sort
    git rev-parse HEAD; git branch --show-current
    git for-each-ref refs/heads; git worktree list; git status --porcelain )
}

echo "repo-tidy.sh spec tests"

# THE CHECKOUT
# On a branch whose PR is merged, clean: back on the default, fast-forwarded.
fresh; squash_merged feat-a
out=$(tidy "$REPO")
is "merged checkout: back on main" main "$(git -C "$REPO" branch --show-current)"
is "merged checkout: fast-forwarded" "$(git --git-dir="$GH/acme/api.git" rev-parse main)" "$(git -C "$REPO" rev-parse main)"
check "merged checkout: listed as switched" "feat-a" "$out"
check "merged checkout: exit 0" "rc=0" "$out"
refute "merged checkout: branch deleted, no longer kept" "kept" "$out"
is "merged checkout: merged branch deleted" "main " "$(branches)"

# The same but dirty: stays, listed.
fresh; squash_merged feat-a
printf 'wip\n' >> "$REPO/feat-a.txt"
out=$(tidy "$REPO")
is "dirty checkout: stays on the branch" feat-a "$(git -C "$REPO" branch --show-current)"
check "dirty checkout: listed as kept" "feat-a" "$out"
check "dirty checkout: says why" "changes" "$out"
is "dirty checkout: change untouched" "wip" "$(tail -1 "$REPO/feat-a.txt")"

# THE WORKTREES
# A merged worktree, clean: removed.
fresh; squash_merged feat-b
git -C "$REPO" switch -q main
git -C "$REPO" worktree add -q "$CASE/wt-b" feat-b
out=$(tidy "$REPO")
[ ! -d "$CASE/wt-b" ] && ok "merged worktree: removed" || bad "merged worktree: removed" "folder still there"
check "merged worktree: listed as removed" "wt-b" "$out"
is "merged worktree: its branch deleted after" "main " "$(branches)"

# A dirty worktree: kept, listed, never removed.
fresh; squash_merged feat-b
git -C "$REPO" switch -q main
git -C "$REPO" worktree add -q "$CASE/wt-b" feat-b
printf 'wip\n' > "$CASE/wt-b/new.txt"
out=$(tidy "$REPO")
[ -f "$CASE/wt-b/new.txt" ] && ok "dirty worktree: kept" || bad "dirty worktree: kept" "file gone"
check "dirty worktree: listed" "wt-b" "$out"
check "dirty worktree: its branch stays" "feat-b" "$(branches)"

# THE BRANCHES
# Squash-merged, local tip equals the PR's head: deleted, though git says unmerged.
fresh; squash_merged feat-c
git -C "$REPO" switch -q main
out=$(tidy "$REPO")
is "squash-merged, tip matches: deleted" "main " "$(branches)"
check "squash-merged, tip matches: listed as deleted" "feat-c" "$out"
is "remote branches never deleted" "main" "$(git --git-dir="$GH/acme/api.git" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ' | sed 's/ $//')"

# The same with one more local commit after the PR's head: kept, listed.
fresh; squash_merged feat-c
printf 'more\n' >> "$REPO/feat-c.txt"
git -C "$REPO" commit -q -am "after the PR"
git -C "$REPO" switch -q main
out=$(tidy "$REPO")
check "extra local commit: branch kept" "feat-c" "$(branches)"
check "extra local commit: listed" "feat-c" "$out"

# DRY RUN
fresh; squash_merged feat-a
git -C "$REPO" switch -q main
squash_merged feat-b
git -C "$REPO" switch -q main
git -C "$REPO" worktree add -q "$CASE/wt-a" feat-a
before=$(snapshot "$REPO")
out=$(tidy --dry-run "$REPO")
is "dry run: nothing changed" "$before" "$(snapshot "$REPO")"
check "dry run: says what it would do" "feat-a" "$out"
check "dry run: exit 0" "rc=0" "$out"

# GITHUB UNREACHABLE
fresh; squash_merged feat-a
git -C "$REPO" switch -q main
squash_merged feat-b
touch "$PRS/down"
before=$(snapshot "$REPO")
out=$(tidy "$REPO")
check "gh down: exit 0" "rc=0" "$out"
is "gh down: nothing changed" "$before" "$(snapshot "$REPO")"
is "gh down: one log line" 1 "$(wc -l < "$TLOG" | tr -d ' ')"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
