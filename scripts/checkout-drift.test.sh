#!/usr/bin/env bash
# Spec tests for the main checkout drift check (scripts/drift.sh's checkout_drift,
# and its `--checkout <repo>` CLI). The main worktree of a repo has drifted when it
# is off its default branch, dirty, diverged from origin/<default> (a fast-forward
# would fail), or behind it (a nudge). No AI, no writes, no fetch: everything here
# reads the refs as a prior `git fetch` left them. A linked worktree (a build's own)
# is never judged, only the main one. No gh call, no stub needed: checkout_drift
# never asks GitHub anything.
#
# Run: bash scripts/checkout-drift.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
DRIFT="$SELF_DIR/drift.sh"
STATUS="$SELF_DIR/status.sh"
AUDIT="$SELF_DIR/self-audit.sh"
REPO_ROOT=$(cd -P "$SELF_DIR/.." && pwd)
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
export HOME="$ROOT/home"; mkdir -p "$HOME"
export EOW_HOME="$ROOT/eow"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$ROOT/gitconfig"
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR

git config --global user.email t@example.com
git config --global user.name T
git config --global init.defaultBranch main
git config --global advice.detachedHead false
for pre in "git@github.com:" "https://github.com/" "ssh://git@github.com/"; do
  git config --global --add "url.$ROOT/gh/.insteadOf" "$pre"
done

ORIGIN="$ROOT/origin.git"
git init -q --bare --initial-branch=main "$ORIGIN"
mkdir -p "$ROOT/gh/acme"
ln -s "$ORIGIN" "$ROOT/gh/acme/api.git"

SEED="$ROOT/seed"
git clone -q "$ORIGIN" "$SEED" 2>/dev/null
printf 'one\n' > "$SEED/file.txt"
git -C "$SEED" add file.txt
git -C "$SEED" commit -q -m init
git -C "$SEED" push -q origin main

REPO="$ROOT/projects/api"
OTHER="$ROOT/other-clone"

fresh() {
  rm -rf "$REPO" "$OTHER" "$ORIGIN" "$ROOT"/wt-*
  git init -q --bare --initial-branch=main "$ORIGIN"
  git -C "$SEED" push -q origin main
  git clone -q "$ORIGIN" "$REPO"
  git -C "$REPO" remote set-head origin main >/dev/null 2>&1
}

# A line of the CHECKOUT output: strips the leading two spaces status.sh and
# self-audit.sh add, when present.
checkout_of() { ( . "$DRIFT"; if checkout_drift "$1"; then printf '%s' "$CHECKOUT"; fi ); }

echo "checkout drift spec tests"

# A clean checkout on the default branch, equal to origin: no line.
fresh
out=$(checkout_of "$REPO")
is "clean: no CHECKOUT line" "" "$out"

# On another branch: off default, with git switch.
fresh
git -C "$REPO" switch -q -c docs/x
out=$(checkout_of "$REPO")
is "off default: the line" "CHECKOUT: on docs/x - fix: git switch main" "$out"

# An untracked file plus a modified file: 2 dirty files, with the stash fix. Nothing
# in the repo is changed by the check itself.
fresh
printf 'two\n' >> "$REPO/file.txt"
printf 'new\n' > "$REPO/untracked.txt"
before=$(git -C "$REPO" rev-parse HEAD; git -C "$REPO" branch --show-current; git -C "$REPO" status --porcelain; git -C "$REPO" for-each-ref)
out=$(checkout_of "$REPO")
after=$(git -C "$REPO" rev-parse HEAD; git -C "$REPO" branch --show-current; git -C "$REPO" status --porcelain; git -C "$REPO" for-each-ref)
is "dirty: the line" "CHECKOUT: 2 dirty files - fix: git stash push -u" "$out"
is "dirty: nothing changed in the repo" "$before" "$after"

# Local default with a commit origin lacks: diverged, with the backup-then-switch fix.
fresh
printf 'local only\n' > "$REPO/local.txt"
git -C "$REPO" add local.txt
git -C "$REPO" commit -q -m "local only"
out=$(checkout_of "$REPO")
today=$(date +%Y%m%d)
is "diverged: the line" "CHECKOUT: main diverged from origin (1 local-only) - fix: git branch backup/main-$today main && git switch -C main origin/main" "$out"

# Origin ahead: behind, with pull --ff-only.
fresh
git clone -q "$ORIGIN" "$OTHER"
printf 'remote only\n' > "$OTHER/remote.txt"
git -C "$OTHER" add remote.txt
git -C "$OTHER" commit -q -m "remote only"
git -C "$OTHER" push -q origin main
git -C "$REPO" fetch -q origin
out=$(checkout_of "$REPO")
is "behind: the line" "CHECKOUT: origin ahead of main (1 commit) - fix: git pull --ff-only" "$out"

# Every case at once: one line, parts in the order above (off default, dirty,
# diverged, behind).
fresh
printf 'local only\n' > "$REPO/local.txt"
git -C "$REPO" add local.txt
git -C "$REPO" commit -q -m "local only"
git clone -q "$ORIGIN" "$OTHER"
printf 'remote only\n' > "$OTHER/remote.txt"
git -C "$OTHER" add remote.txt
git -C "$OTHER" commit -q -m "remote only"
git -C "$OTHER" push -q origin main
git -C "$REPO" fetch -q origin
git -C "$REPO" switch -q -c docs/x
printf 'dirty\n' > "$REPO/dirty.txt"
out=$(checkout_of "$REPO")
today=$(date +%Y%m%d)
want="CHECKOUT: on docs/x, 1 dirty file, main diverged from origin (1 local-only), origin ahead of main (1 commit) - fix: git stash push -u && git branch backup/main-$today main && git switch -C main origin/main"
is "every case: one line, in order, one combined fix" "$want" "$out"

# A linked worktree (a build's own) is never judged, only the main one.
fresh
git -C "$REPO" worktree add -q -b scratch "$ROOT/wt-a" main
printf 'dirty\n' > "$ROOT/wt-a/dirty.txt"
out=$(checkout_of "$ROOT/wt-a")
is "linked worktree: never judged" "" "$out"
out=$(checkout_of "$REPO")
is "linked worktree: the main checkout is still judged on its own state" "" "$out"

# No origin/HEAD at all (git init -b master, remote add origin, push -u origin
# master): the local fallback names master, so a healthy checkout on master is not
# called off default.
NOHEAD_ORIGIN="$ROOT/noheadorigin.git"
NOHEAD_REPO="$ROOT/noheadrepo"
rm -rf "$NOHEAD_ORIGIN" "$NOHEAD_REPO"
git init -q --bare --initial-branch=master "$NOHEAD_ORIGIN"
git init -q -b master "$NOHEAD_REPO"
git -C "$NOHEAD_REPO" remote add origin "$NOHEAD_ORIGIN"
printf 'one\n' > "$NOHEAD_REPO/file.txt"
git -C "$NOHEAD_REPO" add file.txt
git -C "$NOHEAD_REPO" commit -q -m init
git -C "$NOHEAD_REPO" push -q -u origin master
out=$(checkout_of "$NOHEAD_REPO")
is "no origin/HEAD, local master only: not off default" "" "$out"

# Neither origin/HEAD nor a local main/master: no default can be named, so off
# default is skipped instead of guessed.
NODEF_ORIGIN="$ROOT/nodeforigin.git"
NODEF_REPO="$ROOT/nodefrepo"
rm -rf "$NODEF_ORIGIN" "$NODEF_REPO"
git init -q --bare --initial-branch=trunk "$NODEF_ORIGIN"
git init -q -b trunk "$NODEF_REPO"
git -C "$NODEF_REPO" remote add origin "$NODEF_ORIGIN"
printf 'one\n' > "$NODEF_REPO/file.txt"
git -C "$NODEF_REPO" add file.txt
git -C "$NODEF_REPO" commit -q -m init
git -C "$NODEF_REPO" push -q -u origin trunk
out=$(checkout_of "$NODEF_REPO")
is "no default can be named: off default skipped, not guessed" "" "$out"

# A subfolder of the main checkout (a build session started below the repo root,
# passing "."): git prints --git-dir absolute and --git-common-dir relative, which
# must not be taken for a linked worktree and skipped.
fresh
git -C "$REPO" switch -q -c docs/x
mkdir -p "$REPO/sub"
out=$(checkout_of "$REPO/sub")
is "subfolder of the main checkout: still judged, not skipped" "CHECKOUT: on docs/x - fix: git switch main" "$out"

echo
echo "drift.sh --checkout <repo> (the build pre-check)"

# Clean: exit 0, nothing printed.
fresh
out=$("$SHELL_BIN" "$DRIFT" --checkout "$REPO"); rc=$?
is "CLI clean: exit 0" "0" "$rc"
is "CLI clean: no output" "" "$out"

# Dirty: exit 2 (blocking), the line printed - what the build pre-check stops on.
fresh
printf 'new\n' > "$REPO/untracked.txt"
out=$("$SHELL_BIN" "$DRIFT" --checkout "$REPO"); rc=$?
is "CLI dirty: exit 2 (blocking)" "2" "$rc"
check "CLI dirty: prints the line the build pre-check shows" "1 dirty file" "$out"
check "CLI dirty: names the fix" "git stash push -u" "$out"

# Off default: exit 2 (blocking).
fresh
git -C "$REPO" switch -q -c docs/x
out=$("$SHELL_BIN" "$DRIFT" --checkout "$REPO"); rc=$?
is "CLI off default: exit 2 (blocking)" "2" "$rc"

# Diverged: exit 2 (blocking).
fresh
printf 'local only\n' > "$REPO/local.txt"
git -C "$REPO" add local.txt
git -C "$REPO" commit -q -m "local only"
out=$("$SHELL_BIN" "$DRIFT" --checkout "$REPO"); rc=$?
is "CLI diverged: exit 2 (blocking)" "2" "$rc"

# Behind only: exit 1 (a nudge, safe to carry on), the line still printed.
fresh
git clone -q "$ORIGIN" "$OTHER"
printf 'remote only\n' > "$OTHER/remote.txt"
git -C "$OTHER" add remote.txt
git -C "$OTHER" commit -q -m "remote only"
git -C "$OTHER" push -q origin main
git -C "$REPO" fetch -q origin
out=$("$SHELL_BIN" "$DRIFT" --checkout "$REPO"); rc=$?
is "CLI behind: exit 1 (a nudge)" "1" "$rc"
check "CLI behind: still prints the line" "origin ahead of main" "$out"

echo
echo "status.sh and self-audit.sh"

export PROJECTS="$ROOT/projects"
mkdir -p "$EOW_HOME/executor"
printf '## Roots\n- %s\n' "$PROJECTS" > "$EOW_HOME/executor/config.md"
mkdir -p "$EOW_HOME/executor/plans/acme/api"

# status.sh needs the repo's origin to resolve to a slug, and a live plan to look at
# (an item not yet started needs no GitHub lookup at all).
rm -rf "$REPO"
git clone -q "https://github.com/acme/api.git" "$REPO"
git -C "$REPO" remote set-head origin main >/dev/null 2>&1
printf '# B\n\n## S\n- [ ] One\n' > "$EOW_HOME/executor/plans/acme/api/2026-01-01 - x.md"
git -C "$REPO" switch -q -c docs/x
printf 'dirty\n' > "$REPO/dirty.txt"

out=$( ( cd "$ROOT" && "$SHELL_BIN" "$STATUS" 2>&1 ) )
check "status.sh: shows the CHECKOUT line under the repo" "CHECKOUT: on docs/x" "$out"

# A gh stub so self-audit's SETUP checks pass cleanly, isolating the checkout
# warning from unrelated findings.
BIN="$ROOT/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "--version ") echo "gh version 2.99.0 (2026-01-01)"; exit 0 ;;
  "auth status") exit 0 ;;
  "extension list") echo "gh stack  github/gh-stack  v0.3.0"; exit 0 ;;
esac
exit 0
STUB
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"
mkdir -p "$HOME/Projects"

audit_drifted() { ( cd "$REPO" && ROOT="$REPO_ROOT" "$SHELL_BIN" "$AUDIT" 2>&1 ); }
out=$(audit_drifted); rc=$?
check "self-audit on a drifted repo: shown without -v" "⚠ CHECKOUT: on docs/x" "$out"
case "$out" in
  *"executor: FAIL"*) bad "self-audit on a drifted repo: never FAIL" "$out" ;;
  *"executor: PASS"*|*"executor: WARN"*) ok "self-audit on a drifted repo: PASS or WARN" ;;
  *) bad "self-audit on a drifted repo: PASS or WARN" "$out" ;;
esac
refute "self-audit on a drifted repo: no ✗ for the checkout" "✗ CHECKOUT" "$out"

fresh
out=$( ( cd "$REPO" && ROOT="$REPO_ROOT" "$SHELL_BIN" "$AUDIT" 2>&1 ) )
refute "self-audit on a clean repo: no CHECKOUT line" "CHECKOUT" "$out"

echo
printf 'checkout-drift: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
