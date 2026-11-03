#!/usr/bin/env bash
# Spec tests for scripts/find-checkout.sh — finds your local checkout of a PR's
# repository, brings its default branch up to date without touching your work,
# or offers a clone. One case per rule: the ref forms, HERE, the search (depth,
# origin forms, bare repos with worktrees, several roots, missing roots), the
# update (fast-forward, ref only, dirty, diverged, never switch, fetch fails),
# the clone, and the self-audit.
# No network: local bare repos under $ROOT/gh stand in for github.com. Origins
# keep their github.com URLs and a temp GIT_CONFIG_GLOBAL redirects fetches with
# url.<path>.insteadOf. A stub `gh` on PATH clones the same way and logs every
# call, so the test can tell nothing was posted.
#
# Run: bash scripts/find-checkout.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
FIND="$SELF_DIR/find-checkout.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }
line()  { printf '%s\n' "$2" | grep "^$1: " | head -1; }
count() { printf '%s\n' "$2" | grep -c "^$1: "; }

ROOT=$(cd -P "$(mktemp -d)" && pwd)
trap 'rm -rf "$ROOT"' EXIT
BIN="$ROOT/bin"; mkdir -p "$BIN"
export EOW_HOME="$ROOT/eow"
export HOME="$ROOT/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$ROOT/gitconfig"
export GH_CALLS="$ROOT/gh-calls"
GH="$ROOT/gh"

git config --global user.email t@example.com
git config --global user.name T
git config --global init.defaultBranch main
git config --global advice.detachedHead false
for pre in "git@github.com:" "https://github.com/" "ssh://git@github.com/" "https://GitHub.com/"; do
  git config --global --add "url.$GH/.insteadOf" "$pre"
done

# Stub gh: `repo clone` clones from the stand-in GitHub, `auth status` answers
# from $GH_AUTH, everything else fails. Every call is logged.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
case "$1 $2" in
  "repo clone")
    [ "${GH_AUTH:-ok}" = ok ] || { echo "gh: authentication required" >&2; exit 1; }
    git clone -q "https://github.com/$3.git" "$4" ;;
  "auth status") [ "${GH_AUTH:-ok}" = ok ] ;;
  *) echo "gh: not stubbed: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# The stand-in GitHub: acme/api and acme/web, each with a main branch, and a
# seed clone of each to push new commits from.
for r in api web; do
  git init -q --bare "$GH/acme/$r.git"
  git clone -q "https://github.com/acme/$r.git" "$ROOT/seed-$r" 2>/dev/null
  git -C "$ROOT/seed-$r" commit -q --allow-empty -m "init $r"
  git -C "$ROOT/seed-$r" push -q origin main
done
advance(){ git -C "$ROOT/seed-$1" commit -q --allow-empty -m "next $1"; git -C "$ROOT/seed-$1" push -q origin main; }
remote_main(){ git --git-dir="$GH/acme/$1.git" rev-parse main; }

# Each case gets fresh roots. roots_cfg writes the setting in order.
N=0
fresh(){ N=$((N+1)); CASE="$ROOT/case$N"; mkdir -p "$CASE/elsewhere"; }
roots_cfg(){
  mkdir -p "$EOW_HOME/executor"
  { echo "# Executor"; echo; echo "## Roots"; for r in "$@"; do echo "- $r"; done; } > "$EOW_HOME/executor/config.md"
}
clone_to(){ mkdir -p "$(dirname "$2")"; git clone -q "https://github.com/acme/$1.git" "$2"; }
run(){ ( cd "$CASE/elsewhere" && bash "$FIND" "$@" 2>&1 ); }
URL=https://github.com/acme/api/pull/7

echo "find-checkout.sh spec tests"

# The ref: owner/repo#N or a github.com pull URL; anything else stops.
fresh; roots_cfg "$CASE/p"
out=$(run 'acme/api#7')
is "short ref is read" "PR: acme/api#7 · $URL" "$(line PR "$out")"
is "pull URL is read" "PR: acme/api#7 · $URL" "$(line PR "$(run "$URL")")"
is "pull URL with a trailing path is read" "PR: acme/api#7 · $URL" "$(line PR "$(run "$URL/files")")"
for junk in 7 '#7' feature-x 'acme/api' 'https://gitlab.com/acme/api/pull/7' 'https://github.com/acme/api/issues/7' ''; do
  out=$(run "$junk"); rc=$?
  check "junk ref '$junk' stops" "STOP: " "$out"
  check "junk ref '$junk' asks for owner/repo#N or a PR URL" "owner/repo#N" "$out"
  is "junk ref '$junk' is one line" 1 "$(printf '%s\n' "$out" | grep -c .)"
  [ "$rc" -eq 0 ] && ok "junk ref '$junk' exits 0" || bad "junk ref '$junk' exits 0" "exit $rc"
done

# Already inside the PR's repo: HERE, and nothing else happens.
fresh; roots_cfg "$CASE/p"
clone_to api "$CASE/here/api"; mkdir -p "$CASE/here/api/sub"
advance api
before=$(git -C "$CASE/here/api" rev-parse origin/main)
out=$( cd "$CASE/here/api/sub" && bash "$FIND" 'acme/api#7' 2>&1 )
is "inside the repo: HERE names its top" "HERE: $CASE/here/api" "$(line HERE "$out")"
is "inside the repo: no checkout line" 0 "$(count CHECKOUT "$out")"
is "inside the repo: no fetch" "$before" "$(git -C "$CASE/here/api" rev-parse origin/main)"
out=$( cd "$CASE/here/api" && bash "$FIND" 'acme/web#3' 2>&1 )
is "inside another repo: not HERE" 0 "$(count HERE "$out")"

# Found one and two levels deep, with the hand-off command.
fresh; roots_cfg "$CASE/p"
clone_to api "$CASE/p/api"
out=$(run 'acme/api#7')
is "depth 1: found" "CHECKOUT: $CASE/p/api" "$(line CHECKOUT "$out")"
is "depth 1: the command to run" "RUN: cd \"$CASE/p/api\" && claude \"/executor:review $URL\"" "$(line RUN "$out")"
is "depth 1: no others" 0 "$(count ALSO "$out")"
fresh; roots_cfg "$CASE/p"
clone_to api "$CASE/p/acme/api"
is "depth 2: found" "CHECKOUT: $CASE/p/acme/api" "$(line CHECKOUT "$(run 'acme/api#7')")"
fresh; roots_cfg "$CASE/p"
clone_to api "$CASE/p/a/b/api"
is "depth 3: not searched" 0 "$(count CHECKOUT "$(run 'acme/api#7')")"

# origin matches in every github.com form, whatever the case.
for u in git@github.com:acme/api.git https://github.com/acme/api https://github.com/acme/api.git \
         ssh://git@github.com/acme/api.git https://GitHub.com/ACME/Api.git; do
  fresh; roots_cfg "$CASE/p"
  clone_to api "$CASE/p/api"; git -C "$CASE/p/api" remote set-url origin "$u"
  is "origin $u matches" "CHECKOUT: $CASE/p/api" "$(line CHECKOUT "$(run 'acme/api#7')")"
done
for u in git@github.com:acme/api-v2.git git@gitlab.com:acme/api.git https://github.com/other/api.git; do
  fresh; roots_cfg "$CASE/p"
  clone_to api "$CASE/p/api"; git -C "$CASE/p/api" remote set-url origin "$u"
  is "origin $u does not match" 0 "$(count CHECKOUT "$(run 'acme/api#7')")"
done

# A bare repo with its worktrees inside is one checkout, opened at the
#    worktree that has the default branch.
bare_api(){
  git clone -q --bare "https://github.com/acme/api.git" "$1"
  git -C "$1" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C "$1" fetch -q origin
  git -C "$1" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
fresh; roots_cfg "$CASE/p"
bare_api "$CASE/p/api"
git -C "$CASE/p/api" worktree add -q "$CASE/p/api/feature-x" -b feature-x main
git -C "$CASE/p/api" worktree add -q "$CASE/p/api/main" main
out=$(run 'acme/api#7')
is "bare + worktrees: opened at the default branch's worktree" "CHECKOUT: $CASE/p/api/main" "$(line CHECKOUT "$out")"
is "bare + worktrees: counted once" 0 "$(count ALSO "$out")"
fresh; roots_cfg "$CASE/p"
bare_api "$CASE/p/api"
git -C "$CASE/p/api" worktree add -q "$CASE/p/api/feature-x" -b feature-x main
out=$(run 'acme/api#7')
is "bare, no default worktree: its first worktree" "CHECKOUT: $CASE/p/api/feature-x" "$(line CHECKOUT "$out")"
check "bare, no default worktree: works from origin/main" "BASE: origin/main · " "$out"

# The update: fast-forward only, never over your work, never switching.
fresh; roots_cfg "$CASE/p"
clone_to api "$CASE/p/api"; advance api
out=$(run 'acme/api#7')
is "clean and behind: fast-forwarded" "$(remote_main api)" "$(git -C "$CASE/p/api" rev-parse main)"
check "clean and behind: says so" "BASE: main · " "$out"
check "clean and behind: names the fast-forward" "fast-forwarded" "$(line BASE "$out")"
out=$(run 'acme/api#7')
check "level with origin: says up to date" "BASE: main · " "$out"
check "level with origin: names it" "up to date" "$(line BASE "$out")"

fresh; roots_cfg "$CASE/p"
clone_to api "$CASE/p/api"; git -C "$CASE/p/api" checkout -q -b feature; advance api
out=$(run 'acme/api#7')
is "main not checked out: ref fast-forwarded" "$(remote_main api)" "$(git -C "$CASE/p/api" rev-parse main)"
is "main not checked out: the branch you are on stays" feature "$(git -C "$CASE/p/api" branch --show-current)"
check "main not checked out: works from origin/main" "BASE: origin/main · " "$out"

fresh; roots_cfg "$CASE/p"
clone_to api "$CASE/p/api"
printf 'wip\n' > "$CASE/p/api/notes.txt"; git -C "$CASE/p/api" add notes.txt; git -C "$CASE/p/api" commit -qm notes
git -C "$CASE/p/api" push -q origin main; git -C "$ROOT/seed-api" pull -q --ff-only
printf 'my edit\n' > "$CASE/p/api/notes.txt"
before=$(git -C "$CASE/p/api" rev-parse main); advance api
out=$(run 'acme/api#7')
check "dirty main: left alone, works from origin/main" "BASE: origin/main · main has uncommitted changes, left alone" "$out"
is "dirty main: branch not moved" "$before" "$(git -C "$CASE/p/api" rev-parse main)"
is "dirty main: your edit untouched" "my edit" "$(cat "$CASE/p/api/notes.txt")"

fresh; roots_cfg "$CASE/p"
clone_to api "$CASE/p/api"; git -C "$CASE/p/api" commit -q --allow-empty -m local
before=$(git -C "$CASE/p/api" rev-parse main); advance api
out=$(run 'acme/api#7')
check "diverged main: left alone, works from origin/main" "BASE: origin/main · main has local commits not on origin, left alone" "$out"
is "diverged main: branch not moved" "$before" "$(git -C "$CASE/p/api" rev-parse main)"

fresh; roots_cfg "$CASE/p"
clone_to api "$CASE/p/api"; git -C "$CASE/p/api" checkout -q -b feature
git -C "$CASE/p/api" worktree add -q "$CASE/wt-main" main
printf 'x\n' > "$CASE/wt-main/scratch.txt"; git -C "$CASE/wt-main" add scratch.txt
before=$(git -C "$CASE/p/api" rev-parse main); advance api
out=$(run 'acme/api#7')
check "main in a worktree with work: left alone" "BASE: origin/main · " "$out"
is "main in a worktree with work: not moved" "$before" "$(git -C "$CASE/p/api" rev-parse main)"
is "main in a worktree with work: you stay on feature" feature "$(git -C "$CASE/p/api" branch --show-current)"
is "main in a worktree with work: still on main there" main "$(git -C "$CASE/wt-main" branch --show-current)"

# A failed fetch is one line, and the checkout is still found.
fresh; roots_cfg "$CASE/p"
clone_to api "$CASE/p/api"
git config --file "$ROOT/broken" "url.$ROOT/offline/.insteadOf" "https://github.com/"
out=$(GIT_CONFIG_GLOBAL="$ROOT/broken" run 'acme/api#7'); rc=$?
is "fetch fails: still found" "CHECKOUT: $CASE/p/api" "$(line CHECKOUT "$out")"
is "fetch fails: one note" 1 "$(count NOTE "$out")"
check "fetch fails: the note says so" "fetch" "$(line NOTE "$out")"
check "fetch fails: the note has the fix" "→" "$(line NOTE "$out")"
check "fetch fails: logged" "git fetch origin" "$(cat "$EOW_HOME/executor/checkout.log" 2>/dev/null)"
[ "$rc" -eq 0 ] && ok "fetch fails: exits 0" || bad "fetch fails: exits 0" "exit $rc"

# The same repo more than once: root order first, then path order.
fresh; roots_cfg "$CASE/r2" "$CASE/r1"
clone_to api "$CASE/r1/api"; clone_to api "$CASE/r2/x/api"; clone_to api "$CASE/r2/b-api"
out=$(run 'acme/api#7')
is "twice: the first root wins, path order within it" "CHECKOUT: $CASE/r2/b-api" "$(line CHECKOUT "$out")"
is "twice: the others in one line" 1 "$(count ALSO "$out")"
check "twice: names the other in the first root" "$CASE/r2/x/api" "$(line ALSO "$out")"
check "twice: names the one in the second root" "$CASE/r1/api" "$(line ALSO "$out")"

# A missing root is skipped.
fresh; roots_cfg "$CASE/missing" "$CASE/p"
clone_to api "$CASE/p/api"
out=$(run 'acme/api#7'); rc=$?
is "missing root: skipped, found in the next" "CHECKOUT: $CASE/p/api" "$(line CHECKOUT "$out")"
is "missing root: no stop" 0 "$(count STOP "$out")"
[ "$rc" -eq 0 ] && ok "missing root: exits 0" || bad "missing root: exits 0" "exit $rc"

# Nothing found: where it looked and the clone, which needs --clone.
fresh; roots_cfg "$CASE/p" "$CASE/missing"
mkdir -p "$CASE/p"; : > "$GH_CALLS"
out=$(run 'acme/web#3')
is "not found: looked in every root, in order" "LOOKED: $CASE/p
LOOKED: $CASE/missing" "$(printf '%s\n' "$out" | grep '^LOOKED: ' | sed 's/ (missing)$//')"
is "not found: the clone it would make" "CLONE: gh repo clone acme/web \"$CASE/p/web\"" "$(line CLONE "$out")"
is "not found: no checkout" 0 "$(count CHECKOUT "$out")"
[ -e "$CASE/p/web" ] && bad "not found: nothing cloned without --clone" "$CASE/p/web exists" || ok "not found: nothing cloned without --clone"
is "not found: gh not called" "" "$(cat "$GH_CALLS")"

out=$(run 'acme/web#3' --clone)
[ -d "$CASE/p/web/.git" ] && ok "--clone: cloned into the first root" || bad "--clone: cloned into the first root" "no $CASE/p/web"
is "--clone: origin is the PR's repo" "https://github.com/acme/web.git" "$(git -C "$CASE/p/web" config --get remote.origin.url)"
is "--clone: then found" "CHECKOUT: $CASE/p/web" "$(line CHECKOUT "$out")"
is "--clone: the command to run" "RUN: cd \"$CASE/p/web\" && claude \"/executor:review https://github.com/acme/web/pull/3\"" "$(line RUN "$out")"

fresh; roots_cfg "$CASE/p"
mkdir -p "$CASE/p/web"; printf 'mine\n' > "$CASE/p/web/keep.txt"
out=$(run 'acme/web#3' --clone)
check "--clone, target exists: says so" "already exists" "$out"
is "--clone, target exists: nothing added" "keep.txt" "$(ls -A "$CASE/p/web")"
is "--clone, target exists: its file untouched" "mine" "$(cat "$CASE/p/web/keep.txt")"
is "--clone, target exists: no checkout" 0 "$(count CHECKOUT "$out")"

# gh only matters for the clone: missing or signed out, one line with the fix.
fresh; roots_cfg "$CASE/p"
NOGH="$ROOT/nogh"; mkdir -p "$NOGH"
for c in bash env git date mkdir mktemp rm head tr sed cat dirname basename sort grep ls; do
  p=$(command -v "$c") && ln -sf "$p" "$NOGH/$c"
done
out=$( cd "$CASE/elsewhere" && PATH="$NOGH" bash "$FIND" 'acme/web#3' --clone 2>&1 ); rc=$?
check "no gh: says how to install it" "https://cli.github.com" "$out"
is "no gh: one stop line" 1 "$(count STOP "$out")"
[ -e "$CASE/p/web" ] && bad "no gh: nothing cloned" "exists" || ok "no gh: nothing cloned"
[ "$rc" -eq 0 ] && ok "no gh: exits 0" || bad "no gh: exits 0" "exit $rc"
out=$(GH_AUTH=no run 'acme/web#3' --clone); rc=$?
check "signed out: says gh auth login" "gh auth login" "$(line STOP "$out")"
check "signed out: logged" "gh repo clone acme/web" "$(cat "$EOW_HOME/executor/checkout.log")"
[ "$rc" -eq 0 ] && ok "signed out: exits 0" || bad "signed out: exits 0" "exit $rc"

# Read-only on GitHub: gh is only ever asked to clone or about its sign-in.
others=$(grep -vE '^(repo clone|auth status)( |$)' "$GH_CALLS" 2>/dev/null)
is "gh never posts, comments, approves or merges" "" "$others"

# The self-audit misses the script when it is gone.
fresh
PLUG="$CASE/plugin"; mkdir -p "$PLUG"
cp -R "$SELF_DIR/.." "$PLUG/x" 2>/dev/null; PLUG="$PLUG/x"
check "self-audit: present is fine" "executor:" "$(ROOT="$PLUG" bash "$PLUG/scripts/self-audit.sh" -v)"
refute "self-audit: present, no finding" "find-checkout.sh missing" "$(ROOT="$PLUG" bash "$PLUG/scripts/self-audit.sh")"
rm -f "$PLUG/scripts/find-checkout.sh"
check "self-audit: flags it missing" "scripts/find-checkout.sh missing" "$(ROOT="$PLUG" bash "$PLUG/scripts/self-audit.sh")"

echo
printf 'find-checkout.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
