#!/usr/bin/env bash
# Spec tests for moving legacy .executor/ folders: scripts/plans-migrate.sh.
#   A. plans: the name from the modification time and the plan's title;
#   B. done/: the name kept, marked with its date;
#   C. anything else: legacy/ inside the repo's folder;
#   D. the .executor/ exclude line and the empty folder;
#   E. a clash stays, nothing is overwritten;
#   F. --dry-run changes nothing and says what a real run would do;
#   G. which folders are found;
#   H. a plan on another host gets a Host line;
#   I. the plans folder and repo folder come from plan-path.sh;
#   J. what is left alone: STOP, symlinks, tracked files, wrong input;
#   K. build, help and the docs.
# No network: HOME, EOW_HOME and EXECUTOR_PLANS point at a temp dir and origins are
# never contacted. It runs the script with /bin/bash where there is one: macOS's
# is bash 3.2.
#
# Run: bash scripts/plans-migrate.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd -P "$SELF_DIR/.." && pwd)
SCRIPT="$SELF_DIR/plans-migrate.sh"
SHELL_BIN=bash
[ -x /bin/bash ] && SHELL_BIN=/bin/bash

PASS=0; FAIL=0
ok()     { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()    { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()     { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute() { case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }
there()  { if [ -e "$2" ]; then ok "$1"; else bad "$1" "missing: $2 | in the folder: $(ls -A "$(dirname "$2")" 2>&1)"; fi; }
gone()   { if [ -e "$2" ] || [ -L "$2" ]; then bad "$1" "still there: $2"; else ok "$1"; fi; }

TMP=$(mktemp -d)
TMP=$(cd -P "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export EOW_HOME="$TMP/eow"
export EXECUTOR_PLANS="$TMP/plans"
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
mkdir -p "$HOME"
PLANS="$EXECUTOR_PLANS"
SRC="$TMP/src"
NL=$'\n'

migrate() { "$SHELL_BIN" "$SCRIPT" "$@" 2>&1; }
new_repo() { git init -q "$1" 2>/dev/null; [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"; }
write() { mkdir -p "$(dirname "$1")"; printf '%b\n' "$2" > "$1"; }
dated() { touch -t "${2//-/}1200" "$1"; }
# Everything under a folder, with contents and modes, so a change anywhere shows.
snapshot() { (cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r f; do
  printf '%s %s\n' "$(ls -ld "$f" | awk '{print $1}')" "$f"
  [ -f "$f" ] && cat "$f"
done); }
reset() { rm -rf "$SRC" "$PLANS"; mkdir -p "$SRC"; }

PLAN_BODY='# Build: Invite emails\nSpec: [Invite emails](/specs/invites.md)\n\n## Stack A: invites\n- [ ] send - [part](/specs/invites.md)'

echo "plans-migrate.sh spec tests"

# A. plan.md and plan-*.md.
reset
WEB="$SRC/web"
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/plan.md" "$PLAN_BODY"
dated "$WEB/.executor/plan.md" 2026-10-15
write "$WEB/.executor/plan-v2.md" '# Build: Spec: billing: part 2/3\nSpec: [other](/specs/other.md)\n'
dated "$WEB/.executor/plan-v2.md" 2026-09-01
out=$(migrate "$SRC"); rc=$?
DEST="$PLANS/acme/web/2026-10-15 - Invite emails.md"
is "exit 0" 0 "$rc"
there "plan.md: dated from its modification time, titled from its heading" "$DEST"
is "plan.md: content kept" "$(printf '%b\n' "$PLAN_BODY")" "$(cat "$DEST" 2>/dev/null)"
gone "plan.md: left the repo" "$WEB/.executor/plan.md"
there "plan-*.md: a file name can't hold / or :" "$PLANS/acme/web/2026-09-01 - billing- part 2-3.md"
gone "plan-*.md: left the repo" "$WEB/.executor/plan-v2.md"
is "one line per file" 2 "$(printf '%s\n' "$out" | grep -c '^moved: ')"
check "the line says where it went" "moved: $WEB/.executor/plan.md -> $DEST" "$out"

title_of() {
  reset; new_repo "$WEB" "git@github.com:acme/web.git"
  write "$WEB/.executor/$1" "$2"; dated "$WEB/.executor/$1" 2026-10-15
  migrate "$SRC" >/dev/null
  (cd "$PLANS/acme/web" 2>/dev/null && ls -1 | sed 's/^2026-10-15 - //')
}
is "title: a heading with no Build prefix" "Invites.md" "$(title_of plan.md '# Invites\n')"
is "title: the heading's spec suffix goes" "Invites.md" "$(title_of plan.md '# Build: Invites - spec\n')"
is "title: the heading's spec prefix goes" "Invites.md" "$(title_of plan.md '# Build: spec - Invites\n')"
is "title: no heading, the Spec line's link text" "Invites.md" "$(title_of plan.md 'Spec: [Invites - spec](</specs/a b.md>)\n')"
is "title: no heading, a Specs line's first link" "Invites.md" "$(title_of plan.md 'Specs: [Invites](/a.md), [Other](/b.md)\n')"
is "title: no heading, a bare Spec path's file name" "Invites.md" "$(title_of plan.md 'Spec: /specs/spec - Invites.md\n')"
is "title: nothing to read, plan.md" "plan.md" "$(title_of plan.md '- [ ] an item\n')"
is "title: nothing to read, plan-*.md" "v2.md" "$(title_of plan-v2.md '- [ ] an item\n')"
is "title: a heading below the header doesn't count" "plan.md" "$(title_of plan.md '## Stack\n# Not this\n')"

# B. done/*.
reset
new_repo "$WEB" "git@github.com:acme/web.git"
NAME="2026-10-30 - invite-emails.md"
write "$WEB/.executor/done/$NAME" '# Build: Invite emails\nSpec: [x](/x.md)\n\n## Stack A\n- [x] send - PR #1'
dated "$WEB/.executor/done/$NAME" 2026-11-02
out=$(migrate "$SRC")
DEST="$PLANS/acme/web/$NAME"
there "done: the name kept" "$DEST"
is "done: Status from the name, under the header's text" \
  "$(printf '# Build: Invite emails\nSpec: [x](/x.md)\nStatus: done 2026-10-30\n\n## Stack A\n- [x] send - PR #1')" \
  "$(cat "$DEST" 2>/dev/null)"
is "done: no longer live" "" "$(EXECUTOR_PLANS="$PLANS" "$SHELL_BIN" "$SELF_DIR/plan-path.sh" --live "$WEB")"
gone "done: left the repo" "$WEB/.executor/done/$NAME"
check "done: the line names the mark" "(Status: done 2026-10-30)" "$out"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/done/2026-10-30 - a.md" '# Build: A\nStatus: done 2026-10-29\n'
write "$WEB/.executor/done/undated.md" '# Build: B\n'
dated "$WEB/.executor/done/undated.md" 2026-08-08
write "$WEB/.executor/done/notes.txt" 'loose'
migrate "$SRC" >/dev/null
is "done: already marked keeps its own date, once" 'Status: done 2026-10-29' "$(grep '^Status:' "$PLANS/acme/web/2026-10-30 - a.md")"
check "done: no date in the name, its modification time" 'Status: done 2026-08-08' "$(cat "$PLANS/acme/web/undated.md" 2>/dev/null)"
there "done: what isn't a plan goes to legacy/" "$PLANS/acme/web/legacy/done/notes.txt"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/done/2026-10-30 - b.md" '# Build: B\n\n- [x] send - PR #1'
migrate "$SRC" >/dev/null
is "done: no heading below, the line still goes above the first item" \
  "$(printf '# Build: B\nStatus: done 2026-10-30\n\n- [x] send - PR #1')" \
  "$(cat "$PLANS/acme/web/2026-10-30 - b.md" 2>/dev/null)"

# C. Anything else.
reset
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/spec.md" 'the spec'
write "$WEB/.executor/pr/a-review.md" 'review a'
write "$WEB/.executor/pr/deep/b.md" 'review b'
write "$WEB/.executor/plan-notes/c.md" 'not a plan'
out=$(migrate "$SRC")
is "legacy: spec.md, content kept" "the spec" "$(cat "$PLANS/acme/web/legacy/spec.md" 2>/dev/null)"
there "legacy: pr/ keeps its shape" "$PLANS/acme/web/legacy/pr/a-review.md"
there "legacy: nested too" "$PLANS/acme/web/legacy/pr/deep/b.md"
there "legacy: a file in a plan-* folder isn't a plan" "$PLANS/acme/web/legacy/plan-notes/c.md"
is "legacy: one line per file" 4 "$(printf '%s\n' "$out" | grep -c '^moved: ')"
is "legacy: nothing in it counts as live" "" "$("$SHELL_BIN" "$SELF_DIR/plan-path.sh" --live "$WEB")"

# D. The exclude line and the folder.
reset
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/plan.md" "$PLAN_BODY"
EX="$WEB/.git/info/exclude"
printf '# keep me\n.executor/\nsub/.executor/\n.executor/keep\n.executors/\n' > "$EX"
out=$(migrate "$SRC")
is "exclude: only the .executor/ line goes" "$(printf '# keep me\nsub/.executor/\n.executor/keep\n.executors/')" "$(cat "$EX")"
gone "the empty .executor/ goes" "$WEB/.executor"
check "exclude: says so" "$EX" "$out"
check "folder: says so" "removed: $WEB/.executor" "$out"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
mkdir -p "$WEB/.executor/done" "$WEB/.executor/pr"
printf '.executor/\n' > "$WEB/.git/info/exclude"
out=$(migrate "$SRC")
gone "an empty .executor/ goes too" "$WEB/.executor"
gone "no plans folder made for nothing" "$PLANS/acme"
refute "exclude: last line removed" ".executor/" "$(cat "$WEB/.git/info/exclude")"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
mkdir -p "$WEB/.executor"
rm -f "$WEB/.git/info/exclude"
out=$(migrate "$SRC"); rc=$?
is "exclude: a missing file is fine" 0 "$rc"
gone "exclude: not created" "$WEB/.git/info/exclude"

# One repo, two worktrees: the exclude file is shared, in the common dir.
worktrees() {
  reset
  new_repo "$WEB" "git@github.com:acme/web.git"
  git -C "$WEB" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  git -C "$WEB" worktree add -q -b wt "$SRC/wt-web" 2>/dev/null
  EX="$WEB/.git/info/exclude"
  printf '# keep me\n.executor/\n' > "$EX"
}
worktrees
write "$SRC/wt-web/.executor/plan.md" "$PLAN_BODY"
migrate "$SRC/wt-web" >/dev/null
is "worktree: the line goes from the common dir" "# keep me" "$(cat "$EX")"
gone "worktree: no folder left" "$SRC/wt-web/.executor"

worktrees
write "$WEB/.executor/spec.md" 'a'
write "$SRC/wt-web/.executor/pr/x.md" 'b'
migrate "$WEB" >/dev/null 2>&1
migrate "$SRC/wt-web" >/dev/null 2>&1
is "worktree: both emptied, the line goes" "# keep me" "$(cat "$EX")"

worktrees
write "$SRC/wt-web/.executor/spec.md" 'in the other worktree'
mkdir -p "$WEB/.executor"
migrate "$WEB" >/dev/null
check "worktree: the line stays while another worktree holds a .executor/" ".executor/" "$(cat "$EX")"
there "worktree: the other one is untouched" "$SRC/wt-web/.executor/spec.md"
migrate "$SRC" >/dev/null
is "worktree: the run that empties the last one removes it" "# keep me" "$(cat "$EX")"

# E. A clash stays.
reset
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/plan.md" "$PLAN_BODY"
dated "$WEB/.executor/plan.md" 2026-10-15
write "$WEB/.executor/spec.md" 'moves fine'
DEST="$PLANS/acme/web/2026-10-15 - Invite emails.md"
write "$DEST" 'already here'
printf '.executor/\n' > "$WEB/.git/info/exclude"
out=$(migrate "$SRC"); rc=$?
is "clash: exit 0" 0 "$rc"
check "clash: reported" "clash: $WEB/.executor/plan.md" "$out"
is "clash: the file there isn't overwritten" "already here" "$(cat "$DEST")"
is "clash: the file stays, unchanged" "$(printf '%b\n' "$PLAN_BODY")" "$(cat "$WEB/.executor/plan.md" 2>/dev/null)"
there "clash: the others still move" "$PLANS/acme/web/legacy/spec.md"
there "clash: the folder stays" "$WEB/.executor"
is "clash: its exclude line stays, so what's left stays ignored" ".executor/" "$(cat "$WEB/.git/info/exclude")"
out=$(migrate "$SRC")
check "clash: a second run reports it again" "clash: $WEB/.executor/plan.md" "$out"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
NAME="2026-10-30 - a.md"
write "$WEB/.executor/done/$NAME" '# Build: A'
write "$PLANS/acme/web/$NAME" 'already here'
out=$(migrate "$SRC")
check "clash: a done plan too" "clash: $WEB/.executor/done/$NAME" "$out"
is "clash: a done plan isn't marked where it stays" '# Build: A' "$(cat "$WEB/.executor/done/$NAME")"
is "clash: leaves no temp file behind" "$NAME" "$(ls -A "$PLANS/acme/web")"

worktrees
write "$WEB/.executor/spec.md" 'from the checkout'
write "$SRC/wt-web/.executor/spec.md" 'from the worktree'
out=$(migrate "$SRC")
is "worktrees: the first file wins" "from the checkout" "$(cat "$PLANS/acme/web/legacy/spec.md")"
check "worktrees: same-named files clash" "clash: $SRC/wt-web/.executor/spec.md" "$out"
is "worktrees: the second stays" "from the worktree" "$(cat "$SRC/wt-web/.executor/spec.md")"
check "worktrees: the exclude line stays" ".executor/" "$(cat "$EX")"

# F. --dry-run.
worktrees
write "$WEB/.executor/plan.md" "$PLAN_BODY"
dated "$WEB/.executor/plan.md" 2026-10-15
write "$WEB/.executor/done/2026-10-30 - a.md" '# Build: A'
write "$WEB/.executor/spec.md" 'first'
write "$SRC/wt-web/.executor/spec.md" 'second'
before=$(snapshot "$TMP")
out=$(migrate --dry-run "$SRC"); rc=$?
after=$(snapshot "$TMP")
is "dry run: exit 0" 0 "$rc"
is "dry run: changes nothing, plans folder included" "$before" "$after"
gone "dry run: makes no plans folder" "$PLANS"
check "dry run: prints the plan's move" "would move: $WEB/.executor/plan.md -> $PLANS/acme/web/2026-10-15 - Invite emails.md" "$out"
check "dry run: prints the done mark" "(Status: done 2026-10-30)" "$out"
check "dry run: prints the legacy move" "would move: $WEB/.executor/spec.md -> $PLANS/acme/web/legacy/spec.md" "$out"
check "dry run: sees the clash a real run would hit" "clash: $SRC/wt-web/.executor/spec.md" "$out"
check "dry run: the folder that would empty" "would remove: $WEB/.executor" "$out"
refute "dry run: not the one that wouldn't" "would remove: $SRC/wt-web/.executor" "$out"
refute "dry run: the exclude line wouldn't go" "would remove .executor/" "$out"
refute "dry run: claims no real move" "moved: " "$out"
same=$(migrate "$SRC" --dry-run)
is "dry run: the flag may follow the root" "$out" "$same"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/plan.md" "$PLAN_BODY"
printf '.executor/\n' > "$WEB/.git/info/exclude"
out=$(migrate --dry-run "$SRC")
check "dry run: the exclude line that would go" "would remove .executor/ from $WEB/.git/info/exclude" "$out"
is "dry run: it is still there" ".executor/" "$(cat "$WEB/.git/info/exclude")"

# G. What is found.
reset
mkdir -p "$HOME/Projects/shallow"
new_repo "$HOME/Projects/shallow" "git@github.com:acme/shallow.git"
write "$HOME/Projects/shallow/.executor/spec.md" 's'
migrate >/dev/null
there "default root: ~/Projects" "$PLANS/acme/shallow/legacy/spec.md"
rm -rf "$HOME/Projects"
is "default root missing: one line" "STOP: no such folder: $HOME/Projects" "$(migrate)"

reset
for d in a/b/in a/b/c/out x/node_modules/y; do
  new_repo "$SRC/$d" "git@github.com:acme/${d##*/}.git"
  write "$SRC/$d/.executor/spec.md" 's'
done
mkdir -p "$SRC/dotgit/.git/.executor"
out=$(migrate "$SRC" --dry-run)
check "depth 4 is found" "$SRC/a/b/in/.executor/spec.md" "$out"
refute "depth 5 isn't" "/out/" "$out"
refute "node_modules is skipped" "node_modules" "$out"
refute ".git is skipped" "dotgit" "$out"
is "several repos, each to its own folder" 1 "$(printf '%s\n' "$out" | grep -c 'acme/in/legacy/spec.md')"

reset
out=$(migrate "$SRC"); rc=$?
is "nothing to move: one line" "No legacy .executor/ under $SRC" "$out"
is "nothing to move: exit 0" 0 "$rc"
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/spec.md" 's'
(cd "$WEB" && "$SHELL_BIN" "$SCRIPT" . >/dev/null 2>&1)
there "a relative root works" "$PLANS/acme/web/legacy/spec.md"

# H. A plan on another host gets a Host line.
host_plan() {
  reset; new_repo "$WEB" "$1"
  write "$WEB/.executor/plan.md" "$2"; dated "$WEB/.executor/plan.md" 2026-10-15
  [ -z "${3:-}" ] || write "$WEB/.executor/done/2026-10-30 - d.md" '# Build: D\nSpec: [d](/d.md)'
}
host_plan "https://git.acme.test/acme/web.git" "$PLAN_BODY" done
out=$(migrate "$SRC")
is "host: the line sits under Spec" "$(printf '# Build: Invite emails\nSpec: [Invite emails](/specs/invites.md)\nHost: git.acme.test\n\n## Stack A: invites\n- [ ] send - [part](/specs/invites.md)')" \
  "$(cat "$PLANS/acme/web/2026-10-15 - Invite emails.md" 2>/dev/null)"
check "host: the line says so" "(Host: git.acme.test)" "$out"
is "host: a done plan doesn't get it" "" "$(grep '^Host:' "$PLANS/acme/web/2026-10-30 - d.md")"
host_plan "https://github.com/acme/web.git" "$PLAN_BODY"
migrate "$SRC" >/dev/null
is "host: github.com gets none" "" "$(grep -h '^Host:' "$PLANS/acme/web/"*.md)"
host_plan "" "$PLAN_BODY"
migrate "$SRC" >/dev/null
is "host: no origin gets none" "" "$(grep -h '^Host:' "$PLANS/local/web/"*.md)"
host_plan "https://git.acme.test/acme/web.git" '# Build: A\nSpec: [a](/a.md)\nHost: git.acme.test\n'
migrate "$SRC" >/dev/null
is "host: already there, once" 1 "$(grep -c '^Host:' "$PLANS/acme/web/2026-10-15 - A.md")"
host_plan "https://git.acme.test/acme/web.git" '# Build: A\n\n## Stack\n- [ ] x'
migrate "$SRC" >/dev/null
is "host: no Spec line, under the header's text" "$(printf '# Build: A\nHost: git.acme.test\n\n## Stack\n- [ ] x')" "$(cat "$PLANS/acme/web/2026-10-15 - A.md")"
host_plan "https://git.acme.test/acme/web.git" '# Build: A\nSpecs: [a](/a.md), [b](/b.md)\nNote\n\n## Stack'
migrate "$SRC" >/dev/null
is "host: under a Specs line too" "$(printf '# Build: A\nSpecs: [a](/a.md), [b](/b.md)\nHost: git.acme.test\nNote\n\n## Stack')" "$(cat "$PLANS/acme/web/2026-10-15 - A.md")"
host_plan "https://git.acme.test/acme/web.git" "$PLAN_BODY"
migrate --dry-run "$SRC" > "$TMP/dry.out"
check "host: dry run says so" "(Host: git.acme.test)" "$(cat "$TMP/dry.out")"
is "host: dry run leaves the plan alone" "$(printf '%b\n' "$PLAN_BODY")" "$(cat "$WEB/.executor/plan.md")"

# I. The folders come from plan-path.sh.
reset
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/spec.md" 's'
mkdir -p "$EOW_HOME/executor"
printf '## Plans\n- ~/from-config\n' > "$EOW_HOME/executor/config.md"
env -u EXECUTOR_PLANS "$SHELL_BIN" "$SCRIPT" --dry-run "$SRC" > "$TMP/cfg.out" 2>&1
check "config's Plans section" "$HOME/from-config/acme/web/legacy/spec.md" "$(cat "$TMP/cfg.out")"
rm -f "$EOW_HOME/executor/config.md"
env -u EXECUTOR_PLANS "$SHELL_BIN" "$SCRIPT" --dry-run "$SRC" > "$TMP/def.out" 2>&1
check "the default under EOW_HOME" "$EOW_HOME/executor/plans/acme/web/legacy/spec.md" "$(cat "$TMP/def.out")"

reset
new_repo "$WEB"
write "$WEB/.executor/spec.md" 's'
migrate "$SRC" >/dev/null
there "no origin: local/<name>" "$PLANS/local/web/legacy/spec.md"

reset
git init -q --bare "$SRC/metrics/.bare" 2>/dev/null
printf 'gitdir: ./.bare\n' > "$SRC/metrics/.git"
git -C "$SRC/metrics" -c user.name=t -c user.email=t@example.com worktree add -q -b main "$SRC/metrics/main" 2>/dev/null
write "$SRC/metrics/main/.executor/spec.md" 's'
printf '.executor/\n' > "$SRC/metrics/.bare/info/exclude"
migrate "$SRC" >/dev/null
there "a bare repo's worktree: local/<name>" "$PLANS/local/metrics/legacy/spec.md"
gone "a bare repo's worktree: folder gone" "$SRC/metrics/main/.executor"
refute "a bare repo's worktree: exclude in its common dir" ".executor/" "$(cat "$SRC/metrics/.bare/info/exclude")"

# J. What is left alone.
reset
mkdir -p "$SRC/plain/.executor"; printf 's\n' > "$SRC/plain/.executor/spec.md"
new_repo "$WEB" "git@github.com:acme/web.git"; write "$WEB/.executor/spec.md" 's'
out=$(migrate "$SRC"); rc=$?
check "not a repo: reported" "STOP: $SRC/plain/.executor: not a git repository" "$out"
there "not a repo: nothing moves" "$SRC/plain/.executor/spec.md"
there "not a repo: the others still go" "$PLANS/acme/web/legacy/spec.md"
is "not a repo: exit 0" 0 "$rc"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/spec.md" 's'
printf '.executor/\n' > "$WEB/.git/info/exclude"
out=$(EXECUTOR_PLANS=relative/plans "$SHELL_BIN" "$SCRIPT" "$SRC" 2>&1)
check "a plan-path STOP: reported for that repo" "STOP: $WEB/.executor: the plans folder must be absolute" "$out"
there "a plan-path STOP: nothing moves" "$WEB/.executor/spec.md"
is "a plan-path STOP: the exclude line stays" ".executor/" "$(cat "$WEB/.git/info/exclude")"

reset
mkdir -p "$TMP/real/sub"
new_repo "$TMP/real/sub" "git@github.com:acme/linked.git"
write "$TMP/real/sub/.executor/spec.md" 's'
ln -s "$TMP/real" "$SRC/rootlink"
out=$(migrate "$SRC/rootlink"); rc=$?
is "symlinked root: reported" "STOP: $SRC/rootlink is a symbolic link: name the real folder" "$out"
is "symlinked root: exit 0" 0 "$rc"
there "symlinked root: nothing moves" "$TMP/real/sub/.executor/spec.md"
out=$(migrate "$SRC/rootlink/")
check "symlinked root: a trailing slash doesn't get past it" "is a symbolic link" "$out"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
mkdir -p "$TMP/elsewhere"; printf 's\n' > "$TMP/elsewhere/spec.md"
ln -s "$TMP/elsewhere" "$WEB/.executor"
printf '.executor/\n' > "$WEB/.git/info/exclude"
out=$(migrate "$SRC")
check "symlinked .executor: reported" "left: $WEB/.executor: a symbolic link" "$out"
there "symlinked .executor: the link stays" "$WEB/.executor/spec.md"
there "symlinked .executor: its target stays" "$TMP/elsewhere/spec.md"
is "symlinked .executor: the exclude line stays" ".executor/" "$(cat "$WEB/.git/info/exclude")"
gone "symlinked .executor: nothing arrives" "$PLANS/acme/web"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
mkdir -p "$WEB/.executor"
ln -s "$TMP/elsewhere/spec.md" "$WEB/.executor/plan.md"
ln -s "$TMP/elsewhere" "$WEB/.executor/pr"
printf '.executor/\n' > "$WEB/.git/info/exclude"
out=$(migrate "$SRC")
check "a link inside: a plan is reported" "left: $WEB/.executor/plan.md: a symbolic link" "$out"
check "a link inside: a folder is reported" "left: $WEB/.executor/pr: a symbolic link" "$out"
if [ -L "$WEB/.executor/plan.md" ]; then ok "a link inside: stays"; else bad "a link inside: stays" "gone"; fi
is "a link inside: its target stays" "s" "$(cat "$TMP/elsewhere/spec.md")"
is "a link inside: the exclude line stays" ".executor/" "$(cat "$WEB/.git/info/exclude")"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
printf 'not a folder\n' > "$WEB/.executor"
out=$(migrate "$SRC")
check "a file called .executor: reported" "left: $WEB/.executor: not a folder" "$out"
there "a file called .executor: stays" "$WEB/.executor"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/plan.md" "$PLAN_BODY"
git -C "$WEB" add .executor/plan.md
out=$(migrate "$SRC")
check "a tracked .executor/: reported" "left: $WEB/.executor: tracked by git" "$out"
there "a tracked .executor/: stays" "$WEB/.executor/plan.md"

out=$(migrate --nope); rc=$?
check "an unknown flag: usage" "STOP: usage: plans-migrate.sh" "$out"
is "an unknown flag: exit 0" 0 "$rc"
check "two roots: usage" "STOP: usage: plans-migrate.sh" "$(migrate "$SRC" "$WEB")"
is "a missing root: one line" "STOP: no such folder: $TMP/none" "$(migrate "$TMP/none")"

reset
new_repo "$WEB" "git@github.com:acme/web.git"
write "$WEB/.executor/spec.md" 's'
touch "$TMP/plans-is-a-file"
out=$(EXECUTOR_PLANS="$TMP/plans-is-a-file" "$SHELL_BIN" "$SCRIPT" "$SRC" 2>&1); rc=$?
check "a plans folder it can't write: reported" "failed: $WEB/.executor/spec.md" "$out"
there "a plans folder it can't write: stays" "$WEB/.executor/spec.md"
is "a plans folder it can't write: exit 0" 0 "$rc"

# K. Build, help and the docs.
cd "$REPO_ROOT" || exit 1
BUILD=$(cat skills/build/SKILL.md)
HELP=$(cat skills/help/SKILL.md)
check "build: step 0 runs it for this repo" 'scripts/plans-migrate.sh .`' "$BUILD"
check "build: may run it" 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/plans-migrate.sh:*)' "$BUILD"
check "build: says so in one line" 'legacy `.executor/`' "$BUILD"
step0=$(awk '/^## 0\./{f=1} /^## 1\./{f=0} f' skills/build/SKILL.md)
first_step=$(printf '%s\n' "$step0" | grep -n 'plans-migrate.sh' | head -1 | cut -d: -f1)
first_live=$(printf '%s\n' "$step0" | grep -n 'plan-path.sh --live' | head -1 | cut -d: -f1)
[ "${first_step:-99}" -lt "${first_live:-0}" ] && ok "build: migrates before it looks for live plans" \
  || bad "build: migrates before it looks for live plans" "$first_step vs $first_live"
check "help: lists it" 'scripts/plans-migrate.sh [--dry-run] [<root>]' "$HELP"
check "plan doc: says it" 'scripts/plans-migrate.sh' "$(cat references/plan.md)"
check "README: says it" 'scripts/plans-migrate.sh' "$(cat README.md)"

echo
printf 'plans-migrate.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
