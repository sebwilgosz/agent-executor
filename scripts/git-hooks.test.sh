#!/usr/bin/env bash
# Spec tests for scripts/git-hooks.sh — new worktrees start with clones of node_modules
# and .next/cache, and a commit runs its package's checks with no model involved. Every
# test uses throwaway repos and its own state folder.
#
# Run: bash scripts/git-hooks.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
HOOKS="$SELF_DIR/git-hooks.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }
exists(){ [ -e "$2" ] && ok "$1" || bad "$1" "missing: $2"; }
absent(){ [ ! -e "$2" ] && ok "$1" || bad "$1" "should not exist: $2"; }

ROOT=$(cd -P "$(mktemp -d)" && pwd)
trap 'rm -rf "$ROOT"' EXIT

export EXECUTOR_HEAVY_DIR="$ROOT/state"
export GIT_CONFIG_GLOBAL="$ROOT/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email test@example.com
git config --global user.name test
git config --global init.defaultBranch main
LOG="$EXECUTOR_HEAVY_DIR/git-hooks.log"

N=0
# A repo with a root package and a dashboard/ package, with installed folders in both.
repo() {
  N=$((N+1))
  R="$ROOT/r$N/main"
  mkdir -p "$R/dashboard"
  (
    cd "$R" || exit
    git init -q
    printf 'node_modules\n.next\n' > .gitignore
    printf '{"name":"root"}\n' > package.json
    printf 'one\n' > package-lock.json
    printf '{"name":"dash"}\n' > dashboard/package.json
    git add -A
    git commit -qm init
    mkdir -p node_modules/x .next/cache dashboard/node_modules/y dashboard/.next/cache
    printf 'a\n' > node_modules/x/f
    printf 'b\n' > .next/cache/c
    printf 'd\n' > dashboard/node_modules/y/f
    printf 'e\n' > dashboard/.next/cache/c
  )
}
# The package's scripts, given as JSON, with an installed folder so that checks run.
scripts() {
  printf '{"name":"root","scripts":%s}\n' "$1" > "$R/package.json"
  git -C "$R" add -A
  git -C "$R" commit -qm scripts >/dev/null 2>&1
}
commit_file() { # <repo> <path>; OUT is the commit's whole output and RC its exit code
  mkdir -p "$1/$(dirname "$2")"
  printf '%s\n' "$RANDOM" >> "$1/$2"
  git -C "$1" add -A
  OUT=$(git -C "$1" commit -m change 2>&1); RC=$?
}

echo "git-hooks.sh spec tests"

# 1. Install and uninstall.
repo
out=$(bash "$HOOKS" install "$R" 2>&1)
H="$R/.git/hooks"
[ -x "$H/post-checkout" ] && [ -x "$H/post-commit" ] && ok "install: writes both hooks" || bad "install: writes both hooks" "$out"
check "install: says what it did" "post-commit" "$out"
bash "$HOOKS" uninstall "$R" >/dev/null 2>&1
absent "uninstall: removes post-checkout" "$H/post-checkout"
absent "uninstall: removes post-commit" "$H/post-commit"

printf '#!/bin/sh\necho theirs\n' > "$H/post-commit"
out=$(bash "$HOOKS" install "$R" 2>&1)
is "install: a foreign hook survives" "echo theirs" "$(tail -1 "$H/post-commit")"
check "install: says it left a foreign hook alone" "left alone" "$out"
exists "install: the other hook is still written" "$H/post-checkout"
bash "$HOOKS" uninstall "$R" >/dev/null 2>&1
is "uninstall: a foreign hook survives" "echo theirs" "$(tail -1 "$H/post-commit")"
rm -f "$H/post-commit"

git -C "$R" config core.hooksPath "$ROOT/elsewhere"
out=$(bash "$HOOKS" install "$R" 2>&1)
check "install: core.hooksPath is reported" "core.hooksPath" "$out"
absent "install: nothing written with core.hooksPath" "$H/post-commit"
git -C "$R" config --unset core.hooksPath

out=$(bash "$HOOKS" install "$ROOT/not-a-repo" 2>&1); rc=$?
is "install: not a repo exits 0" "0" "$rc"
check "install: not a repo says so" "not a git repo" "$out"

# 2. Cloning on a new worktree.
repo
bash "$HOOKS" install "$R" >/dev/null 2>&1
W="$ROOT/r$N/wt"
out=$(git -C "$R" worktree add -q "$W" -b wt 2>&1); rc=$?
is "clone: the worktree is created" "0" "$rc"
is "clone: node_modules" "a" "$(cat "$W/node_modules/x/f" 2>/dev/null)"
is "clone: .next/cache" "b" "$(cat "$W/.next/cache/c" 2>/dev/null)"
is "clone: node_modules in a subfolder package" "d" "$(cat "$W/dashboard/node_modules/y/f" 2>/dev/null)"
is "clone: .next/cache in a subfolder package" "e" "$(cat "$W/dashboard/.next/cache/c" 2>/dev/null)"
is "clone: it prints nothing when all is well" "" "$out"
[ ! -L "$W/node_modules" ] && ok "clone: a real folder, not a link" || bad "clone: a real folder, not a link" "symlink"
printf 'changed\n' > "$W/node_modules/x/f"
is "clone: a change in the worktree stays there" "a" "$(cat "$R/node_modules/x/f")"
is "clone: the worktree stays clean" "" "$(git -C "$W" status --short)"

rm -rf "$W/node_modules"
git -C "$W" checkout -q -b switched 2>/dev/null
absent "branch switch: clones nothing" "$W/node_modules"

mkdir -p "$W/keep"
repo
bash "$HOOKS" install "$R" >/dev/null 2>&1
git -C "$R" checkout -q -b busy
rm -rf "$R/node_modules"
REAL="$ROOT/r$N/real_modules"; mkdir -p "$REAL/z"; printf 'z\n' > "$REAL/z/f"
ln -s "$REAL" "$R/node_modules"
W="$ROOT/r$N/wt2"
git -C "$R" worktree add -q "$W" -b wt2 2>/dev/null
is "symlinked source: followed" "z" "$(cat "$W/node_modules/z/f" 2>/dev/null)"
[ ! -L "$W/node_modules" ] && ok "symlinked source: a real folder" || bad "symlinked source: a real folder" "symlink"

# 3. Nothing to clone: one line, still a worktree.
repo
bash "$HOOKS" install "$R" >/dev/null 2>&1
rm -rf "$R/node_modules" "$R/dashboard/node_modules" "$R/.next" "$R/dashboard/.next"
W="$ROOT/r$N/wt"
out=$(git -C "$R" worktree add -q "$W" -b wt 2>&1); rc=$?
is "no source: exit 0" "0" "$rc"
exists "no source: the worktree exists" "$W/package.json"
check "no source: names what is missing" "node_modules" "$out"
is "no source: one line per package" "2" "$(printf '%s\n' "$out" | grep -c node_modules)"

# A lockfile that differs is cloned, and said.
repo
bash "$HOOKS" install "$R" >/dev/null 2>&1
git -C "$R" branch older
printf 'two\n' > "$R/package-lock.json"
git -C "$R" commit -qam "new lock"
W="$ROOT/r$N/wt"
out=$(git -C "$R" worktree add -q "$W" older 2>&1)
is "lockfile differs: still cloned" "a" "$(cat "$W/node_modules/x/f" 2>/dev/null)"
check "lockfile differs: says so" "out of date" "$out"

# The main checkout in a bare repo is the worktree on the default branch, not the first.
repo
D="$ROOT/bare"; B="$D/repo.git"; mkdir -p "$D"
git clone -q --bare "$R" "$B" 2>/dev/null
bash "$HOOKS" install "$B" >/dev/null 2>&1
git -C "$B" worktree add -q "$D/aaa" -b aaa 2>/dev/null
git -C "$B" worktree add -q "$D/main" main 2>/dev/null
mkdir -p "$D/main/node_modules/m"; printf 'main\n' > "$D/main/node_modules/m/f"
git -C "$B" worktree add -q "$D/new" -b new 2>/dev/null
is "bare repo: clones from the default branch's worktree" "main" "$(cat "$D/new/node_modules/m/f" 2>/dev/null)"
absent "bare repo: the default branch's own worktree got nothing" "$D/main/.next/cache"
exists "bare repo: the hooks live in the shared folder" "$B/hooks/post-commit"

# A plugin update is picked up with no reinstall.
repo
P="$ROOT/cache/executor"
mkdir -p "$P/0.9.0/scripts" "$P/0.10.0/scripts"
cp "$HOOKS" "$P/0.9.0/scripts/git-hooks.sh"
bash "$P/0.9.0/scripts/git-hooks.sh" install "$R" >/dev/null 2>&1
printf '#!/usr/bin/env bash\necho newest-version-ran\n' > "$P/0.10.0/scripts/git-hooks.sh"
commit_file "$R" notes.txt
check "plugin update: the newest version runs" "newest-version-ran" "$OUT"

# 4. Checks after a commit.
repo
scripts '{"typecheck":"echo TYPE-BAD; exit 1","lint":"echo LINT-BAD; exit 1"}'
bash "$HOOKS" install "$R" >/dev/null 2>&1
rm -f "$LOG"
commit_file "$R" src/a.js
is "failing check: the commit exits 0" "0" "$RC"
check "failing check: type check output" "TYPE-BAD" "$OUT"
check "failing check: lint output" "LINT-BAD" "$OUT"
is "failing check: the commit stands" "change" "$(git -C "$R" log -1 --format=%s)"
check "log: the outcome is there" "failed" "$(cat "$LOG" 2>/dev/null)"
refute "log: never the check's output" "BAD" "$(cat "$LOG" 2>/dev/null)"

scripts '{"typecheck":"echo all fine","lint":"echo all fine"}'
commit_file "$R" src/a.js
refute "passing check: prints nothing" "all fine" "$OUT"

scripts '{"lint":"i=0; while [ $i -lt 100 ]; do echo line-$i; i=$((i+1)); done; exit 1"}'
commit_file "$R" src/a.js
is "long output: capped at 40 lines" "40" "$(printf '%s\n' "$OUT" | grep -c '^line-')"

scripts '{"type-check":"echo HYPHEN-BAD; exit 1"}'
commit_file "$R" src/a.js
check "the type-check spelling also runs" "HYPHEN-BAD" "$OUT"

scripts '{"lint":"echo ROOT-LINT; exit 1"}'
commit_file "$R" dashboard/src/b.js
refute "a package the commit did not touch runs nothing" "ROOT-LINT" "$OUT"
commit_file "$R" src/a.js
check "the touched package runs" "ROOT-LINT" "$OUT"

commit_file "$R" docs/note.md
refute "Markdown-only commit: no check" "ROOT-LINT" "$OUT"
commit_file "$R" public/pic.png
refute "image-only commit: no check" "ROOT-LINT" "$OUT"

# No installed folder: nothing runs.
mv "$R/node_modules" "$R/nm-away"
commit_file "$R" src/a.js
refute "no node_modules: no check" "ROOT-LINT" "$OUT"
mv "$R/nm-away" "$R/node_modules"

# Rebase: no check for each replayed commit.
git -C "$R" checkout -q -b replay
commit_file "$R" src/replay.js
git -C "$R" checkout -q main
commit_file "$R" src/other.js
git -C "$R" checkout -q replay
OUT=$(git -C "$R" rebase main 2>&1); RC=$?
is "rebase: succeeds" "0" "$RC"
refute "rebase: no check" "ROOT-LINT" "$OUT"
git -C "$R" checkout -q main

# A local tsc is used when there is no script.
repo
mkdir -p "$R/node_modules/.bin"
printf '#!/bin/sh\necho "TSC-ARGS $*"; exit 2\n' > "$R/node_modules/.bin/tsc"; chmod +x "$R/node_modules/.bin/tsc"
printf '{}\n' > "$R/tsconfig.json"
git -C "$R" add -A; git -C "$R" commit -qm tsconfig
bash "$HOOKS" install "$R" >/dev/null 2>&1
commit_file "$R" src/a.ts
check "local tsc: runs with no script" "TSC-ARGS --noEmit --incremental false" "$OUT"
rm "$R/tsconfig.json"; git -C "$R" add -A; git -C "$R" commit -qm notsconfig >/dev/null 2>&1
commit_file "$R" src/a.ts
refute "no tsconfig.json: no type check" "TSC-ARGS" "$OUT"

# A check killed by a signal is a failure, not a pass.
printf '#!/bin/sh\nkill -9 $$\n' > "$R/node_modules/.bin/tsc"
printf '{}\n' > "$R/tsconfig.json"
git -C "$R" add -A; git -C "$R" commit -qm tsconfig-again >/dev/null 2>&1
rm -f "$LOG"
commit_file "$R" src/a.ts
check "killed check: reported as failed" "type-check failed" "$OUT"
refute "killed check: never logged as passed" "passed" "$(cat "$LOG" 2>/dev/null)"

# A check that cannot start is one line, not a failure.
repo
scripts '{"lint":"echo NOT-STARTED-OUT; exit 127"}'
bash "$HOOKS" install "$R" >/dev/null 2>&1
rm -f "$LOG"
commit_file "$R" src/a.js
is "cannot start: the commit exits 0" "0" "$RC"
check "cannot start: says so" "lint in . could not start" "$OUT"
refute "cannot start: not reported as a failure" "lint failed" "$OUT"
refute "cannot start: prints none of its output" "NOT-STARTED-OUT" "$OUT"
check "cannot start: logged as not started" "not-started" "$(cat "$LOG" 2>/dev/null)"

# A check over the limit is stopped, along with what it started.
repo
scripts '{"lint":"sleep 40 & echo $! > stray.pid; wait"}'
bash "$HOOKS" install "$R" >/dev/null 2>&1
SECONDS=0
OUT=$(printf x >> "$R/a.js"; git -C "$R" add -A; EXECUTOR_CHECK_SECONDS=1 git -C "$R" commit -m slow 2>&1); RC=$?
[ "$SECONDS" -lt 30 ] && ok "limit: the commit returns" || bad "limit: the commit returns" "took $SECONDS s"
is "limit: the commit exits 0" "0" "$RC"
check "limit: says it stopped the check" "stopped" "$OUT"
stray=$(cat "$R/stray.pid" 2>/dev/null)
sleep 0.5
if [ -n "$stray" ] && kill -0 "$stray" 2>/dev/null; then
  bad "limit: what the check started is stopped too" "pid $stray still running"
  kill -9 "$stray" 2>/dev/null
else
  ok "limit: what the check started is stopped too"
fi

# A worktree commit, where git sets its own variables for the hook, finds its package.
repo
scripts '{"lint":"pwd; echo WT-LINT; exit 1"}'
bash "$HOOKS" install "$R" >/dev/null 2>&1
W="$ROOT/r$N/wt"
git -C "$R" worktree add -q "$W" -b wt 2>/dev/null
commit_file "$W" src/a.js
check "worktree commit: the check runs" "WT-LINT" "$OUT"
check "worktree commit: in the worktree's own folder" "$W" "$OUT"

# 5. The builder's rule.
IMPL=$(cat "$SELF_DIR/../references/implementation.md")
check "builder rule: the full build runs once, before the PR" "The full build runs once" "$IMPL"
check "builder rule: names the commit check" "commit check" "$IMPL"
refute "builder rule: a commit no longer has to build" "complete: it builds" "$IMPL"

echo
printf 'git-hooks.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
