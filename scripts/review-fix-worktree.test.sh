#!/usr/bin/env bash
# Spec tests for the review's fix on a stacked PR leaving the user's checkout alone:
#   A. the skill fixes a stacked PR in a worktree on its branch, rebases and
#      pushes from there, removes it, and asserts the checkout's branch at the end.
#   B. against the real gh-stack extension and a local bare remote: a fix on the
#      lower PR, made from a linked worktree, leaves the checkout on its branch
#      with the same HEAD, and the upper branch carries the fix, locally and
#      on the remote. Skipped when the extension is not installed.
#   C. the stacks reference and the review format agree with the flow.
#
# Run: bash scripts/review-fix-worktree.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "must not hold: $2" ;; *) ok "$1" ;; esac; }

REVIEW=$(cat "$REPO/skills/review/SKILL.md")
STACKS=$(cat "$REPO/references/stacks.md")
FORMAT=$(cat "$REPO/references/review-format.md")
fixstep=$(printf '%s\n' "$REVIEW" | awk '/^## 6\./{f=1;next} /^## 7\./{f=0} f')
report=$(printf '%s\n' "$REVIEW" | awk '/^## 7\./{f=1} f')

echo "review fix-in-worktree spec tests"

# A. The skill.
check "stacked fix uses a worktree on the PR's branch" 'git worktree add "$TMPDIR/executor-fix-<n>" <headRefName>' "$fixstep"
refute "stacked fix never checks the branch out in the checkout" 'gh stack checkout <headRefName>' "$fixstep"
check "rebases the branches above from the worktree" 'gh stack rebase --upstack' "$fixstep"
check "pushes from the worktree" 'gh stack push' "$fixstep"
check "removes the worktree" 'git worktree remove' "$REVIEW"
check "checkout already on the PR's branch and clean: fix in place" "already on the PR's own branch" "$fixstep"
check "in place: no worktree, no switch" "fix in place there instead" "$fixstep"
check "checkout on the PR's branch and dirty: findings left open" "When it is on that branch and the tree has uncommitted changes, touch nothing: leave the findings open" "$fixstep"
check "last step asserts the checkout's branch" 'branch --show-current' "$report"

# B. The behaviour, against gh-stack.
if command -v gh >/dev/null 2>&1 && gh stack --help >/dev/null 2>&1; then
  T=$(mktemp -d); T=$(cd -P "$T" && pwd)
  trap 'rm -rf "$T"' EXIT
  export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

  fixture() {
    rm -rf "$T/o.git" "$T/w" "$T/fix"
    git init -q --bare -b main "$T/o.git"
    git clone -q "$T/o.git" "$T/w" 2>/dev/null
    git -C "$T/w" commit -q --allow-empty -m init
    git -C "$T/w" push -q origin main
    git -C "$T/w" checkout -q -b low
    echo a > "$T/w/a"; git -C "$T/w" add a; git -C "$T/w" commit -qm low
    (cd "$T/w" && gh stack init --adopt low >/dev/null 2>&1; gh stack add up >/dev/null 2>&1)
    echo b > "$T/w/b"; git -C "$T/w" add b; git -C "$T/w" commit -qm up
    git -C "$T/w" push -q origin low up
  }
  fix_in_worktree() {
    git -C "$T/w" worktree add -q "$T/fix" low
    echo f > "$T/fix/f"; git -C "$T/fix" add f; git -C "$T/fix" commit -qm "fix the defect"
    (cd "$T/fix" && gh stack rebase --upstack >/dev/null 2>&1 && gh stack push >/dev/null 2>&1)
    echo $?
  }

  fixture
  git -C "$T/w" checkout -q -b scratch main
  start=$(git -C "$T/w" branch --show-current); head0=$(git -C "$T/w" rev-parse HEAD)
  rc=$(fix_in_worktree)
  git -C "$T/w" worktree remove --force "$T/fix"
  is "rebase and push from the worktree succeed" 0 "$rc"
  is "the checkout is on the branch it started on" "$start" "$(git -C "$T/w" branch --show-current)"
  is "the checkout's HEAD is unchanged" "$head0" "$(git -C "$T/w" rev-parse HEAD)"
  is "the checkout is clean" "" "$(git -C "$T/w" status --short)"
  is "the upper branch carries the fix" "f" "$(git -C "$T/w" ls-tree --name-only up | grep -x f)"
  is "the upper branch sits on the fixed lower one" "$(git -C "$T/w" rev-parse low)" "$(git -C "$T/w" rev-parse up~1)"
  is "the remote's upper branch carries the fix" "$(git -C "$T/w" rev-parse up)" "$(git -C "$T/o.git" rev-parse up)"
  is "no worktree is left" 1 "$(git -C "$T/w" worktree list | wc -l | tr -d ' ')"

  fixture
  git -C "$T/w" checkout -q up
  rc=$(fix_in_worktree)
  git -C "$T/w" worktree remove --force "$T/fix"
  is "rebase and push succeed with the checkout on the upper branch" 0 "$rc"
  is "the checkout stays on the upper branch" up "$(git -C "$T/w" branch --show-current)"
  is "and carries the fix" "f" "$(cat "$T/w/f" 2>/dev/null | tr -d '\n')"

  # The checkout is on the PR's own branch: git refuses the worktree, so the fix
  # runs in place, and the checkout ends on that branch with the fix.
  fixture
  git -C "$T/w" checkout -q low
  if git -C "$T/w" worktree add -q "$T/fix" low 2>/dev/null; then wt=added; else wt=refused; fi
  is "on the PR's branch: git refuses a second worktree on it" refused "$wt"
  echo f > "$T/w/f"; git -C "$T/w" add f; git -C "$T/w" commit -qm "fix the defect"
  rc=$( (cd "$T/w" && gh stack rebase --upstack >/dev/null 2>&1 && gh stack push >/dev/null 2>&1); echo $?)
  is "in place: rebase and push succeed" 0 "$rc"
  is "in place: the checkout stays on the PR's branch" low "$(git -C "$T/w" branch --show-current)"
  is "in place: the checkout is clean" "" "$(git -C "$T/w" status --short)"
  is "in place: the upper branch carries the fix" "f" "$(git -C "$T/w" ls-tree --name-only up | grep -x f)"
  is "in place: the remote's upper branch carries the fix" "$(git -C "$T/w" rev-parse up)" "$(git -C "$T/o.git" rev-parse up)"

  # The same but dirty: the review touches nothing, so the change and branch stay.
  fixture
  git -C "$T/w" checkout -q low
  echo wip > "$T/w/a"
  is "dirty, on the PR's branch: the change is untouched" "wip" "$(cat "$T/w/a")"
  is "dirty, on the PR's branch: still on it" low "$(git -C "$T/w" branch --show-current)"
else
  ok "skipped: the gh-stack extension is not installed"
fi

# C. The references.
check "stacks reference describes the fix worktree" 'git worktree add' "$STACKS"
check "review format has the branch-moved line" 'Checkout' "$FORMAT"

echo
printf 'review-fix-worktree: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
