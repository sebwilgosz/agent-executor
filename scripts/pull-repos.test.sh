#!/usr/bin/env bash
# Spec tests for scripts/pull-repos.sh — updates the default branch of local repos,
# one at a time, and only ever by fast-forward. One case per rule: finding repos,
# groups, each layout, what is left alone, the final list and pull.log.
# No network: local bare repos under $ROOT/gh stand in for github.com. Origins
# keep their github.com URLs and a temp GIT_CONFIG_GLOBAL redirects them with
# url.<path>.insteadOf. Runs under /bin/bash where it exists, the 3.2 macOS ships.
#
# Run: bash scripts/pull-repos.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
PULL="$SELF_DIR/pull-repos.sh"
SHELL_BIN=bash
[ -x /bin/bash ] && SHELL_BIN=/bin/bash

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

ROOT=$(cd -P "$(mktemp -d)" && pwd)
SLEEPER=""
trap '[ -z "$SLEEPER" ] || kill "$SLEEPER" 2>/dev/null; rm -rf "$ROOT"' EXIT
export EOW_HOME="$ROOT/eow"
export HOME="$ROOT/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$ROOT/gitconfig"
GH="$ROOT/gh"
ELSEWHERE="$ROOT/elsewhere"; mkdir -p "$ELSEWHERE"
RCS="$ROOT/exit-codes"
PLOG="$EOW_HOME/executor/pull.log"

git config --global user.email t@example.com
git config --global user.name T
git config --global init.defaultBranch main
git config --global advice.detachedHead false
for pre in "git@github.com:" "https://github.com/" "ssh://git@github.com/"; do
  git config --global --add "url.$GH/.insteadOf" "$pre"
done

# The stand-in GitHub. A remote has file.txt and other.txt on its default branch,
# and a seed clone to push new commits from; advance always changes file.txt.
new_remote() {
  local slug=$1 def=${2:-main} seed="$ROOT/seed/$1"
  git init -q --bare --initial-branch="$def" "$GH/$slug.git"
  mkdir -p "$ROOT/seed"
  git clone -q "https://github.com/$slug.git" "$seed" 2>/dev/null
  printf 'one\n' > "$seed/file.txt"; printf 'other\n' > "$seed/other.txt"
  git -C "$seed" add file.txt other.txt
  git -C "$seed" commit -q -m "init $slug"
  git -C "$seed" push -q origin "$def"
}
advance() {
  local seed="$ROOT/seed/$1" b
  b=$(git -C "$seed" branch --show-current)
  printf 'next\n' >> "$seed/file.txt"
  git -C "$seed" add file.txt
  git -C "$seed" commit -q -m "next $1"
  git -C "$seed" push -q origin "$b"
}
remote_sha() { git --git-dir="$GH/$1.git" rev-parse "${2:-main}"; }
new_remote acme/api
new_remote acme/web
new_remote Kaligo/billing
new_remote other/tools
new_remote acme/modern v2

N=0
fresh() {
  N=$((N+1)); CASE="$ROOT/case$N"; P="$CASE/p"; mkdir -p "$P"
  mkdir -p "$EOW_HOME/executor"
  { echo "# Executor"; echo; echo "## Roots"; echo "- $P"; } > "$EOW_HOME/executor/config.md"
}
group_cfg() {
  local name=$1 e; shift
  { echo; echo "## Group $name"; for e in "$@"; do echo "- $e"; done; } >> "$EOW_HOME/executor/config.md"
}
clone_to() { mkdir -p "$(dirname "$2")"; git clone -q "https://github.com/$1.git" "$2"; }
bare_to() {
  mkdir -p "$(dirname "$2")"
  git clone -q --bare "https://github.com/$1.git" "$2"
  git -C "$2" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C "$2" fetch -q origin
}
branch_of() { git -C "$1" branch --show-current; }
sha_of() { git -C "$1" rev-parse "${2:-HEAD}"; }
behind_commit() { git -C "$1" commit -q --allow-empty -m "$2"; }

# The script runs as another identity, so a commit it made would show.
run() {
  local out rc
  out=$( cd "$ELSEWHERE" && GIT_AUTHOR_NAME=PullScript GIT_COMMITTER_NAME=PullScript \
    "$SHELL_BIN" "$PULL" "$@" 2>&1 ); rc=$?
  printf '%s\n' "$rc" >> "$RCS"
  printf '%s\n' "$out"
}

# Everything that must stay byte for byte: every file outside .git, the branch,
# every local ref, the status and the stash.
snapshot() {
  ( cd "$1" && find . -path ./.git -prune -o -type f -exec cksum {} + | sort
    git rev-parse HEAD; git branch --show-current
    git for-each-ref refs/heads; git status --porcelain; git stash list )
}

echo "pull-repos.sh spec tests"

# THE LAYOUTS
# Plain, on the default branch: fast-forward.
fresh; clone_to acme/api "$P/api"; advance acme/api
out=$(run)
is "plain on default: one line" "Pulled all 1 repo." "$out"
is "plain on default: fast-forwarded" "$(remote_sha acme/api)" "$(sha_of "$P/api")"
is "plain on default: origin/HEAD set" refs/remotes/origin/main "$(git -C "$P/api" symbolic-ref refs/remotes/origin/HEAD)"

# Already up to date counts as pulled.
is "up to date: counts as pulled" "Pulled all 1 repo." "$(run)"

# Plain, on another branch, clean and unused: switch and fast-forward.
fresh; clone_to acme/api "$P/api"; git -C "$P/api" checkout -q -b feature; advance acme/api
is "clean on another branch: one line" "Pulled all 1 repo." "$(run)"
is "clean on another branch: ends on the default" main "$(branch_of "$P/api")"
is "clean on another branch: fast-forwarded" "$(remote_sha acme/api)" "$(sha_of "$P/api")"
git -C "$P/api" show-ref --verify --quiet refs/heads/feature && ok "clean on another branch: the branch stays" || bad "clean on another branch: the branch stays" "gone"

# With no local default branch at all, it is created to switch to.
fresh; clone_to acme/api "$P/api"; git -C "$P/api" checkout -q -b feature; git -C "$P/api" branch -q -D main; advance acme/api
is "no local default: one line" "Pulled all 1 repo." "$(run)"
is "no local default: on it now" main "$(branch_of "$P/api")"
is "no local default: at origin" "$(remote_sha acme/api)" "$(sha_of "$P/api")"
is "no local default: it tracks origin" origin/main "$(git -C "$P/api" rev-parse --abbrev-ref 'main@{upstream}')"

# Plain, on another branch, with local changes: stay, update the ref, name it.
fresh; clone_to acme/api "$P/api"; git -C "$P/api" checkout -q -b feature
printf 'mine\n' > "$P/api/other.txt"; advance acme/api
out=$(run)
is "changes on another branch: stays" feature "$(branch_of "$P/api")"
is "changes on another branch: default ref updated" "$(remote_sha acme/api)" "$(sha_of "$P/api" main)"
is "changes on another branch: the change stays" mine "$(cat "$P/api/other.txt")"
is "changes on another branch: the list" "Pulled all 1 repo.
Left on another branch:
- api: on feature, local changes, main updated" "$out"

# Untracked files count as local changes for the switch decision.
fresh; clone_to acme/api "$P/api"; git -C "$P/api" checkout -q -b feature
printf 'mine\n' > "$P/api/scratch.txt"; advance acme/api
out=$(run)
is "untracked on another branch: stays" feature "$(branch_of "$P/api")"
check "untracked on another branch: named" "- api: on feature, local changes, main updated" "$out"
is "untracked on another branch: default ref updated" "$(remote_sha acme/api)" "$(sha_of "$P/api" main)"

# Plain, on another branch, clean, with a process using the folder.
fresh; clone_to acme/api "$P/api"; git -C "$P/api" checkout -q -b feature; mkdir -p "$P/api/sub"
advance acme/api
( cd "$P/api/sub" && exec sleep 300 ) & SLEEPER=$!
sleep 1
out=$(run)
kill "$SLEEPER" 2>/dev/null; wait "$SLEEPER" 2>/dev/null; SLEEPER=""
is "in use: stays" feature "$(branch_of "$P/api")"
is "in use: default ref updated" "$(remote_sha acme/api)" "$(sha_of "$P/api" main)"
is "in use: the list" "Pulled all 1 repo.
Left on another branch:
- api: on feature, in use, main updated" "$out"

# A process in a folder that merely starts with the same name does not count.
fresh; clone_to acme/api "$P/api"; git -C "$P/api" checkout -q -b feature; mkdir -p "$P/api-notes"
( cd "$P/api-notes" && exec sleep 300 ) & SLEEPER=$!
sleep 1
out=$(run)
kill "$SLEEPER" 2>/dev/null; wait "$SLEEPER" 2>/dev/null; SLEEPER=""
is "next-door folder in use: still switches" main "$(branch_of "$P/api")"

# Bare, with a worktree on the default branch: fast-forward there; counted once.
fresh; bare_to acme/api "$P/api"
git -C "$P/api" worktree add -q "$P/api/main" main
git -C "$P/api" worktree add -q "$P/api/feature" -b feature main
feature_before=$(sha_of "$P/api/feature")
advance acme/api
out=$(run)
is "bare with worktrees: counted once" "Pulled all 1 repo." "$out"
is "bare with default worktree: fast-forwarded there" "$(remote_sha acme/api)" "$(sha_of "$P/api/main")"
is "bare with default worktree: its files moved" "$(cat "$ROOT/seed/acme/api/file.txt")" "$(cat "$P/api/main/file.txt")"
is "bare with default worktree: feature worktree untouched" "$feature_before" "$(sha_of "$P/api/feature")"
is "bare with default worktree: feature still on feature" feature "$(branch_of "$P/api/feature")"

# A worktree found first still stands for its repo.
fresh; bare_to acme/api "$CASE/outside/api.git"
git -C "$CASE/outside/api.git" worktree add -q "$P/api-main" main
advance acme/api
is "worktree of a bare repo outside the roots: pulled" "Pulled all 1 repo." "$(run)"
is "worktree of a bare repo outside the roots: fast-forwarded" "$(remote_sha acme/api)" "$(sha_of "$P/api-main")"

# Bare, with no worktree on the default branch: the ref moves, no checkout.
fresh; bare_to acme/api "$P/api"
git -C "$P/api" worktree add -q "$P/api/feature" -b feature main
feature_before=$(sha_of "$P/api/feature")
advance acme/api
is "bare, no default worktree: one line" "Pulled all 1 repo." "$(run)"
is "bare, no default worktree: ref updated" "$(remote_sha acme/api)" "$(git -C "$P/api" rev-parse refs/heads/main)"
is "bare, no default worktree: feature untouched" "$feature_before" "$(sha_of "$P/api/feature")"
is "bare, no default worktree: no worktree added" 2 "$(git -C "$P/api" worktree list | wc -l | tr -d ' ')"

# And the ref is created when it is absent.
fresh; bare_to acme/api "$P/api"
git -C "$P/api" worktree add -q "$P/api/feature" -b feature main
git -C "$P/api" symbolic-ref HEAD refs/heads/feature
git -C "$P/api" branch -q -D main
is "bare, no default branch: one line" "Pulled all 1 repo." "$(run)"
is "bare, no default branch: created" "$(remote_sha acme/api)" "$(git -C "$P/api" rev-parse refs/heads/main)"

# A plain `git clone --bare` has no fetch refspec.
fresh; mkdir -p "$P"; git clone -q --bare "https://github.com/acme/api.git" "$P/api"
git -C "$P/api" worktree add -q "$P/api/main" main; advance acme/api
is "plain bare clone: one line" "Pulled all 1 repo." "$(run)"
is "plain bare clone: fast-forwarded" "$(remote_sha acme/api)" "$(sha_of "$P/api/main")"

# THE DEFAULT BRANCH IS WHAT THE REMOTE SAYS
fresh; clone_to acme/modern "$P/modern"; old_main_absent=$(git -C "$P/modern" branch --list main); advance acme/modern
is "v2: one line" "Pulled all 1 repo." "$(run)"
is "v2: updates v2" "$(remote_sha acme/modern v2)" "$(sha_of "$P/modern" v2)"
is "v2: stays on v2" v2 "$(branch_of "$P/modern")"
is "v2: no main appears" "$old_main_absent" "$(git -C "$P/modern" branch --list main)"

# The default moved on the remote: origin/HEAD follows, and a clean checkout too.
new_remote acme/moved
fresh; clone_to acme/moved "$P/moved"
git -C "$ROOT/seed/acme/moved" checkout -q -b next
git -C "$ROOT/seed/acme/moved" commit -q --allow-empty -m "on next"
git -C "$ROOT/seed/acme/moved" push -q origin next
git --git-dir="$GH/acme/moved.git" symbolic-ref HEAD refs/heads/next
is "moved default: one line" "Pulled all 1 repo." "$(run)"
is "moved default: origin/HEAD refreshed" refs/remotes/origin/next "$(git -C "$P/moved" symbolic-ref refs/remotes/origin/HEAD)"
is "moved default: on it now" next "$(branch_of "$P/moved")"
is "moved default: at origin" "$(remote_sha acme/moved next)" "$(sha_of "$P/moved")"

# A HEAD with no symref: the fallback in default-branch.sh decides.
new_remote acme/detached
fresh; clone_to acme/detached "$P/detached"
git --git-dir="$GH/acme/detached.git" update-ref --no-deref HEAD "$(remote_sha acme/detached)"
advance acme/detached
is "no symref: one line" "Pulled all 1 repo." "$(run)"
is "no symref: fast-forwarded" "$(remote_sha acme/detached main)" "$(sha_of "$P/detached")"

# A remote that answers with no HEAD at all.
new_remote acme/headless
fresh; clone_to acme/headless "$P/headless"
git --git-dir="$GH/acme/headless.git" symbolic-ref HEAD refs/heads/gone
is "no HEAD on the remote: could not update" "Pulled 0 of 1 repo.
Could not pull:
- headless: could not update" "$(run)"

# An empty remote.
git init -q --bare "$GH/acme/empty.git"
fresh; clone_to acme/empty "$P/empty" 2>/dev/null
is "empty remote: could not update" "Pulled 0 of 1 repo.
Could not pull:
- empty: could not update" "$(run)"

# WHAT IS LEFT ALONE
# Diverged: local and remote each have a commit.
fresh; clone_to acme/api "$P/api"; behind_commit "$P/api" local; advance acme/api
before=$(snapshot "$P/api")
is "diverged: the list" "Pulled 0 of 1 repo.
Could not pull:
- api: diverged from origin" "$(run)"
is "diverged: byte for byte" "$before" "$(snapshot "$P/api")"

# Ahead only, with nothing to pull, is diverged too.
fresh; clone_to acme/api "$P/api"; behind_commit "$P/api" local
before=$(snapshot "$P/api")
check "ahead only: diverged" "- api: diverged from origin" "$(run)"
is "ahead only: byte for byte" "$before" "$(snapshot "$P/api")"

# A diverged default on another branch, clean: never switches.
fresh; clone_to acme/api "$P/api"; behind_commit "$P/api" local; git -C "$P/api" checkout -q -b feature
before=$(snapshot "$P/api")
check "diverged, on another branch: diverged" "- api: diverged from origin" "$(run)"
is "diverged, on another branch: byte for byte" "$before" "$(snapshot "$P/api")"

# A conflicting local change on the default branch.
fresh; clone_to acme/api "$P/api"; printf 'mine\n' >> "$P/api/file.txt"; advance acme/api
before=$(snapshot "$P/api")
is "conflicting change: the list" "Pulled 0 of 1 repo.
Could not pull:
- api: local changes in the way" "$(run)"
is "conflicting change: byte for byte" "$before" "$(snapshot "$P/api")"

# An untracked file the remote also adds is in the way as well.
new_remote acme/adds
fresh; clone_to acme/adds "$P/adds"; printf 'mine\n' > "$P/adds/new.txt"
printf 'theirs\n' > "$ROOT/seed/acme/adds/new.txt"
git -C "$ROOT/seed/acme/adds" add new.txt
git -C "$ROOT/seed/acme/adds" commit -q -m "adds new"
git -C "$ROOT/seed/acme/adds" push -q origin main
before=$(snapshot "$P/adds")
check "untracked in the way: named" "- adds: local changes in the way" "$(run)"
is "untracked in the way: byte for byte" "$before" "$(snapshot "$P/adds")"

# A local change git can carry along is no obstacle.
fresh; clone_to acme/api "$P/api"; printf 'mine\n' > "$P/api/other.txt"; advance acme/api
is "harmless change on default: one line" "Pulled all 1 repo." "$(run)"
is "harmless change on default: fast-forwarded" "$(remote_sha acme/api)" "$(sha_of "$P/api")"
is "harmless change on default: the change stays" mine "$(cat "$P/api/other.txt")"

# A worktree on the default branch: fast-forward when git allows, else a failure.
fresh; bare_to acme/api "$P/api"; git -C "$P/api" worktree add -q "$P/api/main" main
printf 'mine\n' > "$P/api/main/other.txt"; advance acme/api
is "default worktree, harmless change: one line" "Pulled all 1 repo." "$(run)"
is "default worktree, harmless change: fast-forwarded" "$(remote_sha acme/api)" "$(sha_of "$P/api/main")"
fresh; bare_to acme/api "$P/api"; git -C "$P/api" worktree add -q "$P/api/main" main
printf 'mine\n' >> "$P/api/main/file.txt"; advance acme/api
before=$(snapshot "$P/api/main")
check "default worktree, conflicting change: reported" "- api: local changes in the way" "$(run)"
is "default worktree, conflicting change: byte for byte" "$before" "$(snapshot "$P/api/main")"

# A merge or a rebase in progress.
conflict_branches() {
  git -C "$1" checkout -q -b theirs
  printf 'theirs\n' > "$1/other.txt"; git -C "$1" add other.txt; git -C "$1" commit -q -m theirs
  git -C "$1" checkout -q -b ours HEAD~1
  printf 'ours\n' > "$1/other.txt"; git -C "$1" add other.txt; git -C "$1" commit -q -m ours
}
fresh; clone_to acme/api "$P/api"; conflict_branches "$P/api"
git -C "$P/api" merge -q theirs >/dev/null 2>&1; advance acme/api
before=$(snapshot "$P/api")
check "merge in progress: could not update" "- api: could not update" "$(run)"
is "merge in progress: byte for byte" "$before" "$(snapshot "$P/api")"
[ -f "$P/api/.git/MERGE_HEAD" ] && ok "merge in progress: still running" || bad "merge in progress: still running" "gone"

fresh; clone_to acme/api "$P/api"; conflict_branches "$P/api"
git -C "$P/api" rebase -q theirs >/dev/null 2>&1; advance acme/api
before=$(snapshot "$P/api")
check "rebase in progress: could not update" "- api: could not update" "$(run)"
is "rebase in progress: byte for byte" "$before" "$(snapshot "$P/api")"
[ -d "$P/api/.git/rebase-merge" ] && ok "rebase in progress: still running" || bad "rebase in progress: still running" "gone"
rm -rf "$CASE"

# The default branch in a linked worktree of a plain checkout on another branch.
fresh; clone_to acme/api "$P/api"; git -C "$P/api" checkout -q -b release/0.3.0
git -C "$P/api" worktree add -q "$CASE/wt-main" main; advance acme/api
out=$(run)
is "default in a linked worktree: the list" "Pulled all 1 repo.
Left on another branch:
- api: on release/0.3.0, main in a worktree, main updated" "$out"
is "default in a linked worktree: fast-forwarded there" "$(remote_sha acme/api)" "$(sha_of "$CASE/wt-main")"
is "default in a linked worktree: its files moved" "$(cat "$ROOT/seed/acme/api/file.txt")" "$(cat "$CASE/wt-main/file.txt")"
is "default in a linked worktree: the checkout stays" release/0.3.0 "$(branch_of "$P/api")"

# Detached HEAD, nothing running: never switches.
fresh; clone_to acme/api "$P/api"; head=$(sha_of "$P/api"); git -C "$P/api" checkout -q --detach; advance acme/api
out=$(run)
is "detached: the list" "Pulled all 1 repo.
Left on another branch:
- api: on detached HEAD, main updated" "$out"
is "detached: stays" "$head" "$(sha_of "$P/api")"
is "detached: still detached" "" "$(branch_of "$P/api")"
is "detached: default ref updated" "$(remote_sha acme/api)" "$(sha_of "$P/api" main)"

# A worktree entry whose folder is gone is ignored and not pruned.
fresh; bare_to acme/api "$P/api"
git -C "$P/api" worktree add -q "$CASE/gone" main; rm -rf "$CASE/gone"; advance acme/api
is "stale default worktree, bare: one line" "Pulled all 1 repo." "$(run)"
is "stale default worktree, bare: ref updated" "$(remote_sha acme/api)" "$(git -C "$P/api" rev-parse refs/heads/main)"
check "stale default worktree, bare: not pruned" "$CASE/gone" "$(git -C "$P/api" worktree list)"

fresh; clone_to acme/api "$P/api"; git -C "$P/api" checkout -q -b feature
git -C "$P/api" worktree add -q "$CASE/gone" main; rm -rf "$CASE/gone"; advance acme/api
is "stale default worktree, plain: one line" "Pulled all 1 repo." "$(run)"
is "stale default worktree, plain: switched" main "$(branch_of "$P/api")"
is "stale default worktree, plain: at origin" "$(remote_sha acme/api)" "$(sha_of "$P/api")"
check "stale default worktree, plain: not pruned" "$CASE/gone" "$(git -C "$P/api" worktree list)"

# FINDING REPOS
# Two levels deep, not three; Archive skipped; a missing root skipped.
fresh
clone_to acme/api "$P/api"; clone_to acme/web "$P/deep/web"
clone_to other/tools "$P/a/b/tools"
clone_to Kaligo/billing "$P/Archive/billing"; clone_to Kaligo/billing "$P/old/Archive"
{ echo "## Roots"; echo "- $CASE/missing"; echo "- $P"; } > "$EOW_HOME/executor/config.md"
tools_before=$(sha_of "$P/a/b/tools"); archived_before=$(sha_of "$P/Archive/billing"); advance Kaligo/billing; advance other/tools
is "search: two levels, no Archive, missing root skipped" "Pulled all 2 repos." "$(run)"
is "search: depth 3 not touched" "$tools_before" "$(sha_of "$P/a/b/tools")"
is "search: Archive not touched" "$archived_before" "$(sha_of "$P/Archive/billing")"

# A root that is itself named Archive is still searched.
fresh; R="$CASE/Archive"; clone_to acme/api "$R/api"
{ echo "## Roots"; echo "- $R"; } > "$EOW_HOME/executor/config.md"
is "a root named Archive: searched" "Pulled all 1 repo." "$(run)"

# The default root.
fresh; rm -f "$EOW_HOME/executor/config.md"
is "no repos, default root: says where it looked" "No repos found (looked in ~/Projects)." "$(run)"
clone_to acme/api "$HOME/Projects/api"
is "default root: searched" "Pulled all 1 repo." "$(run)"
rm -rf "$HOME/Projects"

# No origin: skipped and counted, never a failure.
fresh; clone_to acme/api "$P/api"; git init -q "$P/local-only"; behind_commit "$P/local-only" one
is "skipped: the one-liner" "Pulled all 1 repo. 1 skipped, no remote." "$(run)"
fresh; git init -q "$P/a"; git init -q "$P/b"; git init -q "$P/c"
is "only skipped: no repos to pull" "No repos to pull. 3 skipped, no remote." "$(run)"

# Two clones of one remote: each updated, each shown by its folder.
fresh; clone_to acme/api "$P/one"; clone_to acme/api "$P/two"; advance acme/api
is "two clones: both counted" "Pulled all 2 repos." "$(run)"
is "two clones: first updated" "$(remote_sha acme/api)" "$(sha_of "$P/one")"
is "two clones: second updated" "$(remote_sha acme/api)" "$(sha_of "$P/two")"
fresh; clone_to acme/api "$P/one"; clone_to acme/api "$P/two"
behind_commit "$P/one" local; behind_commit "$P/two" local
is "two clones: shown by folder" "Pulled 0 of 2 repos.
Could not pull:
- $P/one: diverged from origin
- $P/two: diverged from origin" "$(run)"

# GROUPS
groups_repos() {
  clone_to acme/api "$P/api"; clone_to acme/web "$P/web"
  clone_to Kaligo/billing "$P/billing"; clone_to other/tools "$P/tools"
  git init -q "$P/local-only"
  behind_commit "$P/api" mark; behind_commit "$P/web" mark; behind_commit "$P/billing" mark; behind_commit "$P/tools" mark
}
names_in() { printf '%s\n' "$1" | sed -n 's/^- \([^:]*\):.*/\1/p' | sort | tr '\n' ' '; }

# Every repo is diverged here, so the list names exactly what the run selected.
fresh; groups_repos
out=$(run)
is "no argument: every repo" "api billing tools web " "$(names_in "$out")"
check "no argument: the no-remote repo is counted" "Pulled 0 of 4 repos. 1 skipped, no remote." "$out"

fresh; groups_repos; group_cfg eow ACME other/TOOLS
out=$(run eow)
is "group: owners and owner/repo, ignoring case" "api tools web " "$(names_in "$out")"
check "group: a no-origin repo is not counted" "Pulled 0 of 3 repos.
" "$out"

fresh; groups_repos; group_cfg eow billing
is "group: a bare line is an owner, not a repo" "No repos match eow (looked in $P)." "$(run eow)"

fresh; groups_repos; group_cfg eow acme
out=$(run EOW)
refute "group: the section name must match exactly" "- api" "$out"
is "group: a wrong-case name matches nothing here" "No repos match EOW (looked in $P)." "$out"

fresh; groups_repos; group_cfg acme other
is "group: a section wins over an owner of that name" "tools " "$(names_in "$(run acme)")"

fresh; groups_repos; group_cfg empty
is "group: an empty section selects nothing" "No repos match empty (looked in $P)." "$(run empty)"

fresh; groups_repos
is "no section: owner in another case" "billing " "$(names_in "$(run kaligo)")"
is "no section: repo name in another case" "tools " "$(names_in "$(run TOOLS)")"
is "no match: one line" "No repos match nobody (looked in $P)." "$(run nobody)"

# A repo out of the group is not touched.
fresh; clone_to acme/api "$P/api"; clone_to other/tools "$P/tools"; api_before=$(sha_of "$P/api"); tools_before=$(sha_of "$P/tools")
advance acme/api; advance other/tools
is "group run: one line" "Pulled all 1 repo." "$(run other)"
is "group run: selected repo updated" "$(remote_sha other/tools)" "$(sha_of "$P/tools")"
is "group run: the rest untouched" "$api_before" "$(sha_of "$P/api")"
is "group run: the rest not even fetched" "$api_before" "$(sha_of "$P/api" origin/main)"

# Owner and repo come from the origin URL in any form.
for u in git@github.com:ACME/api.git https://github.com/acme/api ssh://git@github.com/acme/api.git; do
  fresh; clone_to acme/api "$P/x"; git -C "$P/x" remote set-url origin "$u"
  is "origin $u: matched by owner" "Pulled all 1 repo." "$(run acme)"
  is "origin $u: matched by repo" "Pulled all 1 repo." "$(run API)"
done

# THE FINAL LIST
fresh
clone_to acme/api "$P/api"; behind_commit "$P/api" local
clone_to acme/web "$P/web"; printf 'mine\n' >> "$P/web/file.txt"
clone_to other/tools "$P/tools"; git -C "$P/tools" checkout -q -b release/0.3.0; printf 'mine\n' > "$P/tools/scratch"
clone_to Kaligo/billing "$P/billing"
git init -q "$P/local-only"
advance acme/web; advance other/tools; advance Kaligo/billing
out=$(run)
is "failures: exactly the lines of the list" "Pulled 2 of 4 repos. 1 skipped, no remote.
Could not pull:
- api: diverged from origin
- web: local changes in the way
Left on another branch:
- tools: on release/0.3.0, local changes, main updated" "$out"

# Offline.
fresh; clone_to acme/api "$P/api"; clone_to acme/web "$P/web"; git init -q "$P/local-only"
api_before=$(sha_of "$P/api")
git config --file "$ROOT/offline" "url.$ROOT/nowhere/.insteadOf" "https://github.com/"
git config --file "$ROOT/offline" user.name T
git config --file "$ROOT/offline" user.email t@example.com
out=$(GIT_CONFIG_GLOBAL="$ROOT/offline" run)
is "offline: one line" "Could not reach any origin. Are you online?" "$out"
is "offline: nothing moved" "$api_before" "$(sha_of "$P/api")"

# One unreachable origin among reachable ones is named.
fresh; clone_to acme/api "$P/api"; clone_to acme/web "$P/web"
git -C "$P/web" remote set-url origin "https://github.com/acme/no-such-repo.git"
is "one unreachable: named" "Pulled 1 of 2 repos.
Could not pull:
- no-such-repo: could not reach origin" "$(run)"

# gh is not installed: works anyway, also through the fallback.
NOGH="$ROOT/nogh"; mkdir -p "$NOGH"
for c in git mktemp mkdir rm cat dirname lsof sed; do
  p=$(command -v "$c") && ln -sf "$p" "$NOGH/$c"
done
fresh; clone_to acme/api "$P/api"; advance acme/api
out=$( cd "$ELSEWHERE" && PATH="$NOGH" "$SHELL_BIN" "$PULL" 2>&1 ); printf '%s\n' "$?" >> "$RCS"
is "no gh: one line" "Pulled all 1 repo." "$out"
is "no gh: fast-forwarded" "$(remote_sha acme/api)" "$(sha_of "$P/api")"

# Depending on nothing else: a broken lsof means nobody can say it is free.
fresh; clone_to acme/api "$P/api"; git -C "$P/api" checkout -q -b feature
BROKEN="$ROOT/broken"; mkdir -p "$BROKEN"
for c in git mktemp mkdir rm cat dirname sed; do
  p=$(command -v "$c") && ln -sf "$p" "$BROKEN/$c"
done
out=$( cd "$ELSEWHERE" && PATH="$BROKEN" "$SHELL_BIN" "$PULL" 2>&1 ); printf '%s\n' "$?" >> "$RCS"
is "no lsof: stays on the branch" feature "$(branch_of "$P/api")"
check "no lsof: named as in use" "- api: on feature, in use, main updated" "$out"

# PULL.LOG
fresh; clone_to acme/api "$P/api"; behind_commit "$P/api" local; clone_to acme/web "$P/web"; advance acme/web
: > "$PLOG"; printf 'an old run\n' > "$PLOG"
out=$(run)
log=$(cat "$PLOG")
refute "pull.log: overwritten" "an old run" "$log"
check "pull.log: names each repo" "$P/web" "$log"
check "pull.log: holds git's output" "origin/main" "$log"
check "pull.log: ends with the final list" "$out" "$log"
is "pull.log: the list is its last lines" "$out" "$(tail -n "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "$PLOG")"

fresh
is "pull.log: an early line is logged too" "No repos found (looked in $P)." "$(run)"
is "pull.log: holds that line" "No repos found (looked in $P)." "$(cat "$PLOG")"

# The state folder defaults under ~/.engineer-of-wealth.
fresh; clone_to acme/api "$P/api"
cfg="$HOME/.engineer-of-wealth/executor"; mkdir -p "$cfg"; cp "$EOW_HOME/executor/config.md" "$cfg/config.md"
out=$( cd "$ELSEWHERE" && env -u EOW_HOME "$SHELL_BIN" "$PULL" 2>&1 ); printf '%s\n' "$?" >> "$RCS"
is "default state folder: runs" "Pulled all 1 repo." "$out"
check "default state folder: pull.log there" "Pulled all 1 repo." "$(cat "$cfg/pull.log" 2>/dev/null)"

# An unwritable state folder changes nothing about the list.
clone_to acme/api "$HOME/Projects/api"
mkdir -p "$ROOT/blocked"; : > "$ROOT/blocked/executor"
out=$( cd "$ELSEWHERE" && EOW_HOME="$ROOT/blocked" "$SHELL_BIN" "$PULL" 2>&1 ); printf '%s\n' "$?" >> "$RCS"
is "no state folder: still answers" "Pulled all 1 repo." "$out"
rm -rf "$HOME/Projects"

# NEVER: no stash, reset, rebase or new commit in any repo of any case, and exit 0.
sweep_stash=""; sweep_flog=""; sweep_commit=""
for g in "$ROOT"/case*/p/* "$ROOT"/case*/p/*/* ; do
  [ -e "$g/.git" ] || { [ -f "$g/HEAD" ] && [ -d "$g/objects" ]; } || continue
  [ -z "$(git -C "$g" stash list)" ] || sweep_stash="$sweep_stash $g"
  git -C "$g" log -g --all --format=%gs 2>/dev/null | grep -qE '^(reset|rebase|pull|stash)' && sweep_flog="$sweep_flog $g"
  [ -z "$(git -C "$g" log --all --format=%h --committer=PullScript 2>/dev/null)" ] || sweep_commit="$sweep_commit $g"
done
is "never: no stash entry anywhere" "" "$sweep_stash"
is "never: no reset or rebase in any reflog" "" "$sweep_flog"
is "never: no commit made by the script" "" "$sweep_commit"
is "never: the exit code is always 0" "" "$(grep -v '^0$' "$RCS")"
for slug in acme/api acme/web other/tools Kaligo/billing; do
  seed_head=$(sha_of "$ROOT/seed/$slug")
  is "never: nothing pushed to $slug" "$seed_head" "$(remote_sha "$slug")"
done

# THE SELF-AUDIT misses the scripts when they are gone.
PLUG="$ROOT/plugin"; mkdir -p "$PLUG"
for d in .claude-plugin agents hooks references scripts skills; do cp -R "$SELF_DIR/../$d" "$PLUG/" 2>/dev/null; done
for s in pull-repos remote-slug; do
  refute "self-audit: $s.sh present" "scripts/$s.sh" "$(ROOT="$PLUG" "$SHELL_BIN" "$PLUG/scripts/self-audit.sh")"
  rm -f "$PLUG/scripts/$s.sh"
  check "self-audit: $s.sh missing" "✗ integrity: scripts/$s.sh missing" "$(ROOT="$PLUG" "$SHELL_BIN" "$PLUG/scripts/self-audit.sh")"
done

echo
printf 'pull-repos.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
