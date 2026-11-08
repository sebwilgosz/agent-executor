#!/usr/bin/env bash
# Spec tests for scripts/review-mode.sh — whether /executor:review may fix what
# it finds. One case per rule: your PR fixes, a teammate's or a fork's reports,
# --fix and --no-fix override (never onto a fork), a branch without a PR is
# judged by its commit authors, and any lookup that fails reports.
# No network: a stub `gh` on PATH answers from $GH_VIEW / $GH_USER / $GH_REPO,
# and runs `pr list`'s own --jq over the JSON in $GH_LIST ("FAIL" makes a call
# fail). A local repo, origin owned by `me`, stands in for the branch.
#
# Run: bash scripts/review-mode.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
MODE="$SELF_DIR/review-mode.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()   { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check(){ case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
BIN="$ROOT/bin"; mkdir -p "$BIN"
export EOW_HOME="$ROOT/eow"

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
reply(){ [ "$1" = FAIL ] && { echo "gh: HTTP 502" >&2; exit 1; }; echo "A new release of gh is available" >&2; [ -n "$1" ] && printf '%s\n' "$1"; exit 0; }
case "$1 $2" in
  "pr view") reply "${GH_VIEW:-}" ;;
  "pr list")
    [ "${GH_LIST:-}" = FAIL ] && reply FAIL
    q=; while [ $# -gt 0 ]; do [ "$1" = --jq ] && q=$2; shift; done
    printf '%s' "${GH_LIST:-[]}" | jq -r "$q"; exit ;;
  "api user") reply "${GH_USER:-me}" ;;
  "repo view") reply "${GH_REPO:-}" ;;
esac
exit 0
STUB
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# A repo whose origin/main is the base; `mine` holds only my commits, `theirs`
# also a teammate's, `shouty` mine under my email in capitals.
REPO="$ROOT/repo"
git init -q -b main "$REPO"
cd "$REPO" || exit 1
git config user.email me@example.com; git config user.name Me
git remote add origin git@github.com:Me/repo.git
git commit -q --allow-empty -m base
git update-ref refs/remotes/origin/main HEAD
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git checkout -q -b mine;   git commit -q --allow-empty -m one
git checkout -q -b theirs; git -c user.email=Mate@Example.com commit -q --allow-empty -m two
git checkout -q -b shouty main; git -c user.email=ME@Example.COM commit -q --allow-empty -m three
git checkout -q -b fresh main

run(){ bash "$MODE" "$@" 2>&1; }

echo "review-mode.sh spec tests"

# 1. A PR is fixed by default only when you wrote it and it isn't a fork.
is "your PR fixes"           "MODE: fix · your PR"                   "$(GH_VIEW='7 me false' run pr 7)"
is "a teammate's PR reports" "MODE: report-only · PR by @mate"       "$(GH_VIEW='7 mate false' run pr 7)"
is "a fork PR reports"       "MODE: report-only · fork PR by @mate"  "$(GH_VIEW='7 mate true' run pr 7)"
is "your own fork PR reports" "MODE: report-only · fork PR by @me"   "$(GH_VIEW='7 me true' run pr 7)"
is "a PR URL works too"      "MODE: fix · your PR" \
  "$(GH_VIEW='7 me false' run pr https://github.com/o/r/pull/7)"

# 2. --fix forces fixing, never onto a fork; --no-fix always reports.
is "--fix on a teammate's PR fixes" "MODE: fix · --fix, PR by @mate" "$(GH_VIEW='7 mate false' run pr 7 --fix)"
is "--fix on a fork still reports"  "MODE: report-only · fork PR by @mate, --fix can't push to it" \
  "$(GH_VIEW='7 mate true' run pr 7 --fix)"
is "--no-fix on your PR reports"    "MODE: report-only · --no-fix" "$(GH_VIEW='7 me false' run pr 7 --no-fix)"
is "a flag before the target"       "MODE: fix · --fix, PR by @mate" "$(GH_VIEW='7 mate false' run pr --fix 7)"

# 3. A branch with an open PR is judged as that PR: one whose head lives with
#    origin's owner, not a stranger's fork branch that only shares the name.
pr(){ printf '{"number":%s,"author":{"login":"%s"},"isCrossRepository":%s,"headRepositoryOwner":{"login":"%s"}}' "$@"; }
is "branch with your PR fixes"           "MODE: fix · your PR"             "$(GH_LIST="[$(pr 9 me false me)]" run branch theirs)"
is "branch with a teammate's PR reports" "MODE: report-only · PR by @mate" "$(GH_LIST="[$(pr 9 mate false me)]" run branch mine)"
is "a stranger's same-named fork PR is not yours" "MODE: fix · your branch" \
  "$(GH_LIST="[$(pr 8 stranger true stranger)]" run branch mine)"
is "--fix ignores a stranger's fork PR"  "MODE: fix · --fix, branch mine" \
  "$(GH_LIST="[$(pr 8 stranger true stranger)]" run branch mine --fix)"
is "origin's PR wins over a stranger's"  "MODE: report-only · PR by @mate" \
  "$(GH_LIST="[$(pr 8 stranger true stranger),$(pr 9 mate false me)]" run branch mine)"
is "your fork clone's PR is a fork PR"   "MODE: report-only · fork PR by @me" \
  "$(GH_LIST="[$(pr 9 me true Me)]" run branch mine)"
git remote set-url origin repo.git
is "no owner in origin: same-repo PRs only" "MODE: report-only · PR by @mate" \
  "$(GH_LIST="[$(pr 8 stranger true stranger),$(pr 9 mate false x)]" run branch mine)"
git remote set-url origin git@github.com:Me/repo.git

# 4. A branch with no PR: yours only when every commit past the base is yours.
is "your branch fixes"               "MODE: fix · your branch"                                "$(run branch mine)"
is "a teammate's commit reports" "MODE: report-only · branch has commits by Mate@Example.com" "$(run branch theirs)"
is "your email in other case is yours" "MODE: fix · your branch"                              "$(run branch shouty)"
is "no commits past the base: yours" "MODE: fix · your branch"                                "$(run branch fresh)"
is "no name: the current branch"     "MODE: fix · your branch"                                "$(run branch)"
is "--fix on someone's branch fixes" "MODE: fix · --fix, branch theirs"                       "$(run branch theirs --fix)"
is "a missing branch reports"        "MODE: report-only · branch nope not found"              "$(run branch nope)"

# With origin/HEAD unset the base is what gh reports, as ship.sh sees it: on a
# `trunk` that already holds the teammate's commit, `theirs` adds nothing past it.
git symbolic-ref --delete refs/remotes/origin/HEAD
git update-ref refs/remotes/origin/trunk theirs
is "no origin/HEAD: gh names the base" "MODE: fix · your branch" "$(GH_REPO=trunk run branch theirs)"
git update-ref -d refs/remotes/origin/trunk
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# 5. A lookup that fails reports, logs, and never crashes.
out=$(GH_VIEW=FAIL run pr 7); rc=$?
check "PR lookup fails: report-only" "MODE: report-only · could not read the PR's author" "$out"
[ "$rc" -eq 0 ] && ok "PR lookup fails: exits 0" || bad "PR lookup fails: exits 0" "exit $rc"
check "PR lookup fails: logged" "gh pr view 7: gh: HTTP 502" "$(cat "$EOW_HOME/executor/review.log" 2>/dev/null)"
check "gh user fails: report-only" "MODE: report-only · could not read the gh user" "$(GH_VIEW='7 me false' GH_USER=FAIL run pr 7)"
is "PR list fails: falls back to the commits" "MODE: fix · your branch" "$(GH_LIST=FAIL run branch mine)"
check "no arguments: report-only" "MODE: report-only" "$(run)"
check "pr without a number: report-only" "MODE: report-only · no PR given" "$(run pr --fix)"

# 6. One line, whatever happened.
lines=$(GH_VIEW='7 mate false' run pr 7 | grep -c .)
[ "$lines" -eq 1 ] && ok "output is a single line" || bad "output is a single line" "got $lines lines"

echo
printf 'review-mode.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
