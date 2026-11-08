#!/usr/bin/env bash
# Spec tests for scripts/repo-discovery.sh — the search for local repos under
# the roots. find-checkout.test.sh covers it through one caller, whose predicate
# keeps a single origin. These cover what the helper promises any caller: a
# predicate of its own decides what counts, a clone or a bare repo counts once
# with all its worktrees, a missing root is skipped, and the self-audit misses
# the file when it is gone.
# No network: every repo is local, HOME and EOW_HOME point at a temp dir, and a
# stub `gh` on PATH answers for the self-audit.
#
# Run: bash scripts/repo-discovery.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
HELPER="$SELF_DIR/repo-discovery.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

ROOT=$(cd -P "$(mktemp -d)" && pwd)
trap 'rm -rf "$ROOT"' EXIT
BIN="$ROOT/bin"; mkdir -p "$BIN"
export HOME="$ROOT/home"; mkdir -p "$HOME"
export EOW_HOME="$ROOT/eow"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$ROOT/gitconfig"
git config --global user.email t@example.com
git config --global user.name T
git config --global init.defaultBranch main

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

N=0
fresh(){ N=$((N+1)); CASE="$ROOT/case$N"; mkdir -p "$CASE"; }
repo(){ mkdir -p "$(dirname "$1")"; git init -q "$1"; git -C "$1" commit -q --allow-empty -m init; }
bare(){
  repo "$CASE/seed"
  mkdir -p "$(dirname "$1")"
  git clone -q --bare "$CASE/seed" "$1"
  rm -rf "$CASE/seed"
}

# Runs the search in a shell of its own under the caller's strictest settings
# and prints what it found, one per line. "$1" is the predicate's body, the rest
# are the roots.
search(){
  local body=$1; shift
  "$BASH" -c '
    set -eu
    . "$1"; body=$2; shift 2
    keep() { eval "$body"; }
    discover_repos keep "$@"
    [ "${#repos[@]}" -eq 0 ] || printf "%s\n" "${repos[@]}"
  ' _ "$HELPER" "$body" "$@" 2>&1
}
all='return 0'

echo "repo-discovery.sh spec tests"

# Sourcing does nothing on its own.
is "sourcing prints nothing" "" "$("$BASH" -c 'set -eu; . "$1"' _ "$HELPER" 2>&1)"

# One and two levels deep, not three, in path order, root after root.
fresh
repo "$CASE/r2/b"; repo "$CASE/r2/a/deep"; repo "$CASE/r2/a/x/too-deep"; repo "$CASE/r1/c"
is "depth 1 and 2, not 3: path order, then the next root" "$CASE/r2/a/deep
$CASE/r2/b
$CASE/r1/c" "$(search "$all" "$CASE/r2" "$CASE/r1")"

# A plain clone and its worktrees are one repo, the first seen standing for all.
fresh
repo "$CASE/r/api"
git -C "$CASE/r/api" worktree add -q "$CASE/r/api/inside" -b inside
git -C "$CASE/r/api" worktree add -q "$CASE/r/other" -b other
is "clone and worktrees: one repo, the first seen" "$CASE/r/api" "$(search "$all" "$CASE/r")"

# A bare repo and its worktrees are one repo too.
fresh
bare "$CASE/r/api"
git -C "$CASE/r/api" worktree add -q "$CASE/r/api/one" -b one
git -C "$CASE/r/api" worktree add -q "$CASE/r/two" -b two
is "bare and worktrees: one repo, the first seen" "$CASE/r/api" "$(search "$all" "$CASE/r")"

# A worktree whose repo sits outside the roots still counts, once.
fresh
repo "$CASE/outside/api"
git -C "$CASE/outside/api" worktree add -q "$CASE/r/one" -b one
git -C "$CASE/outside/api" worktree add -q "$CASE/r/two" -b two
is "worktrees of a repo outside the roots: the first seen" "$CASE/r/one" "$(search "$all" "$CASE/r")"

# The same repo under two roots counts once, separate clones count apart.
fresh
repo "$CASE/r1/api"
git -C "$CASE/r1/api" worktree add -q "$CASE/r2/wt" -b wt
git clone -q "$CASE/r1/api" "$CASE/r2/clone"
is "across roots: a worktree is the same repo, a clone is not" "$CASE/r1/api
$CASE/r2/clone" "$(search "$all" "$CASE/r1" "$CASE/r2")"

# The caller's predicate decides what counts.
fresh
repo "$CASE/r/keep"; repo "$CASE/r/skip"
is "predicate: a refused folder is left out" "$CASE/r/keep" \
  "$(search 'case "$1" in */skip) return 1 ;; esac' "$CASE/r")"
is "predicate: refusing all finds nothing" "" "$(search 'return 1' "$CASE/r")"

# A refused folder doesn't use up its repo: the next worktree can stand for it.
fresh
repo "$CASE/r/a-skip"
git -C "$CASE/r/a-skip" worktree add -q "$CASE/r/b-wt" -b wt
is "predicate: a refused first folder leaves the repo to the next" "$CASE/r/b-wt" \
  "$(search 'case "$1" in */a-skip) return 1 ;; esac' "$CASE/r")"

# The predicate is asked about repos only, each with its folder.
fresh
repo "$CASE/r/api"; mkdir -p "$CASE/r/notes/sub"; : > "$CASE/r/file"
mkdir -p "$CASE/r/almost"; : > "$CASE/r/almost/HEAD"
ASKED="$CASE/asked"
search "echo \"\$1\" >> \"$ASKED\"" "$CASE/r" >/dev/null
is "predicate: asked about repos, never other folders or files" "$CASE/r/api" "$(cat "$ASKED")"

# Missing roots are skipped; nothing found is an empty list, not an error.
fresh
repo "$CASE/r/api"
out=$(search "$all" "$CASE/missing" "$CASE/r"); rc=$?
is "missing root: skipped, found in the next" "$CASE/r/api" "$out"
is "missing root: no failure" 0 "$rc"
out=$(search "$all" "$CASE/missing"); rc=$?
is "only a missing root: nothing found" "" "$out"
is "only a missing root: no failure" 0 "$rc"
mkdir -p "$CASE/empty"
out=$(search "$all" "$CASE/empty"); rc=$?
is "an empty root: nothing found" "" "$out"
is "an empty root: no failure" 0 "$rc"

# A second search starts over, and the caller's own variables survive.
fresh
repo "$CASE/r/api"; repo "$CASE/s/web"
out=$("$BASH" -c '
  set -eu
  . "$1"
  keep() { return 0; }
  root=mine; d=mine; e=mine; seen=mine
  discover_repos keep "$2"
  discover_repos keep "$3"
  printf "%s\n" "${repos[@]}" "$root$d$e$seen"
' _ "$HELPER" "$CASE/r" "$CASE/s" 2>&1)
is "a second search starts over, the caller's variables survive" "$CASE/s/web
minemineminemine" "$out"

# The self-audit misses the helper when it is gone.
fresh
PLUG="$CASE/plugin"; mkdir -p "$PLUG"
cp -R "$SELF_DIR/../scripts" "$SELF_DIR/../skills" "$SELF_DIR/../references" "$SELF_DIR/../agents" \
  "$SELF_DIR/../hooks" "$SELF_DIR/../.claude-plugin" "$PLUG/"
refute "self-audit: present, no finding" "repo-discovery.sh" "$(ROOT="$PLUG" "$BASH" "$PLUG/scripts/self-audit.sh")"
rm -f "$PLUG/scripts/repo-discovery.sh"
check "self-audit: flags it missing" "✗ integrity: scripts/repo-discovery.sh missing" \
  "$(ROOT="$PLUG" "$BASH" "$PLUG/scripts/self-audit.sh")"

echo
printf 'repo-discovery.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
