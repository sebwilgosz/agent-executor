#!/usr/bin/env bash
# Spec tests for scripts/docs-mentions.sh, the review's docs-drift check: what
# it takes from the diff (removed flags and names, deleted and renamed files,
# extra identifiers), where it searches (tracked docs at HEAD, never a
# changelog), what it prints, and that it never fails into the conversation.
# No network: every case is a local repo in a temp folder, with no global git
# config, so a setting on this machine can't change the result.
#
# Run: bash scripts/docs-mentions.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
MENTIONS="$SELF_DIR/docs-mentions.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }
lines() { printf '%s\n' "$@"; }

ROOT=$(cd -P "$(mktemp -d)" && pwd)
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"; mkdir -p "$HOME"
export EOW_HOME="$ROOT/eow"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
LOG="$EOW_HOME/executor/docs-mentions.log"

run()  { bash "$MENTIONS" "$@" 2>&1; }
put()  { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
save() { git add -A; git commit -qm "$1"; }

# A new repo: main holds the files `put` wrote since, `work` is checked out on
# top of it. Each case starts with `fresh`, writes its base, then calls `branch`.
N=0
fresh() {
  N=$((N+1)); cd "$ROOT" || exit 1
  git init -q -b main "r$N"; cd "r$N" || exit 1
  git config user.email me@example.com; git config user.name Me
  git config commit.gpgsign false
}
branch() { save base; git checkout -q -b work; }

echo "docs-mentions.sh spec tests"

# 1. A removed flag still in the README.
fresh
put cli.sh 'run --foo-bar now'
put README.md "$(lines '# Tool' '' 'Pass `--foo-bar` to go faster.')"
branch
put cli.sh 'run now'; save 'drop the flag'
is "removed flag still in the README" 'MENTION: --foo-bar README.md:3' "$(run main)"
run main >/dev/null; is "a mention: exit 0" 0 "$?"

# 2. A removed UPPER_SNAKE name, and every kind of doc searched.
fresh
put app.py 'token = env("API_TOKEN")'
put README.rst 'Set API_TOKEN first.'
put docs/setup.txt 'export API_TOKEN=x'
put pkg/NOTES.md 'API_TOKEN is required.'
put pkg/README 'API_TOKEN again.'
put src/other.py '# API_TOKEN stays out of the search: not a doc, and not added'
branch
put app.py 'token = None'; save 'drop the name'
is "removed name: README*, docs/**, other *.md" \
  "$(lines 'MENTION: API_TOKEN README.rst:1' 'MENTION: API_TOKEN docs/setup.txt:1' 'MENTION: API_TOKEN pkg/NOTES.md:1' 'MENTION: API_TOKEN pkg/README:1')" \
  "$(run main)"

# 3. Still on an added line, anywhere in the code: nothing removed, no mention.
fresh
put a.sh 'run --moved'
put b.sh 'run'
put README.md 'Use --moved.'
branch
put a.sh 'run'; put b.sh 'run --moved'; save 'move the flag'
is "a flag only moved between files is no mention" NONE "$(run main)"

# 4. Whole token: a longer flag or name is another identifier.
fresh
put cli.sh "$(lines 'run --foo' 'env API_KEY')"
put README.md "$(lines 'Use --foo-bar.' 'Or ---foo.' 'Or x--foo.' 'Set MY_API_KEY.' 'Set API_KEY_2.' 'Set API_KEYS.')"
branch
put cli.sh 'run'; save 'drop them'
is "longer tokens are not hits" NONE "$(run main)"

fresh
put cli.sh "$(lines 'run --foo' 'env API_KEY')"
put README.md "$(lines 'Use --foo-bar or --foo here.' 'Use --foo=1.' 'The API_KEY-specific part.' 'Set `API_KEY`.')"
branch
put cli.sh 'run'; save 'drop them'
is "a real token after a longer one, and punctuation around it" \
  "$(lines 'MENTION: --foo README.md:1' 'MENTION: --foo README.md:2' 'MENTION: API_KEY README.md:3' 'MENTION: API_KEY README.md:4')" \
  "$(run main)"

# 5. A line that starts with the flag shows as `---flag` in the patch.
fresh
put cli.sh "$(lines 'run \' '--verbose \' '--quiet' 'NOT_SNAKE' 'PATH')"
put README.md "$(lines 'Use --verbose.' 'Use --quiet.' 'Use PATH.')"
branch
put cli.sh 'run'; save 'drop the lines'
is "a removed line starting with the flag counts; no underscore, no name" \
  "$(lines 'MENTION: --quiet README.md:2' 'MENTION: --verbose README.md:1')" "$(run main)"

fresh
put a.sh '--keep'
put b.sh 'x'
put README.md 'Use --keep.'
branch
put a.sh 'x'; put b.sh '--keep'; save 'move a line that starts with the flag'
is "an added line starting with the flag counts too" NONE "$(run main)"

# 6. Extra identifiers: fixed strings, whole token, no duplicates.
fresh
put src/app.py 'x = 1'
put README.md "$(lines 'Call parse_user first.' 'Not parse_user2.' 'abc is unrelated.' 'GET /api/users/42' 'a\b here' 'path a.c')"
branch
put src/app.py 'x = 2'; save 'change the code'
is "extra identifier, whole token" 'MENTION: parse_user README.md:1' "$(run main parse_user)"
is "an extra identifier is not a regex" 'MENTION: a.c README.md:6' "$(run main a.c)"
is "a route is a fixed string" 'MENTION: /api/users README.md:4' "$(run main /api/users)"
is "a backslash stays a backslash" 'MENTION: a\b README.md:5' "$(run main 'a\b')"
is "an empty argument matches nothing" NONE "$(run main '')"
is "no hit for an identifier: NONE" NONE "$(run main not_there)"
is "the same identifier twice is one search" 'MENTION: parse_user README.md:1' "$(run main parse_user parse_user)"

fresh
put cli.sh 'run --gone'
put README.md 'Use --gone.'
branch
put cli.sh 'run'; save 'drop it'
is "an argument the script also found is one search" 'MENTION: --gone README.md:1' "$(run main --gone)"

# 7. A renamed file still linked in docs/.
fresh
put scripts/old.sh 'echo a long enough body for rename detection to see it'
put docs/guide.md "$(lines '# Guide' 'See [the script](../scripts/old.sh).')"
branch
git mv scripts/old.sh scripts/new.sh; save 'rename'
is "renamed file still linked in docs/" 'MENTION: scripts/old.sh docs/guide.md:2' "$(run main)"

# The bare name counts only in docs in that same folder.
fresh
put src/old.py 'print("a long enough body for rename detection to see it")'
put src/NOTES.md "$(lines 'See old.py.' 'See ./old.py.' 'See src/old.py.' 'See sub/old.py.' 'See ../old.py.' 'See bold.py.')"
put src/sub/NOTES.md 'See old.py.'
put other/NOTES.md 'See old.py.'
put README.md 'See src/old.py and old.py.'
branch
git mv src/old.py src/new.py; save 'rename'
is "full path everywhere, bare name beside it" \
  "$(lines 'MENTION: src/old.py README.md:1' 'MENTION: src/old.py src/NOTES.md:3' 'MENTION: old.py src/NOTES.md:1' 'MENTION: old.py src/NOTES.md:2')" \
  "$(run main)"

# Deleted files too; at the top of the repo the path is the bare name: one hit.
fresh
put tool.sh 'body'
put lib/gone.sh 'body'
put README.md 'Run tool.sh, or lib/gone.sh.'
put keep.sh 'x'
branch
git rm -q tool.sh lib/gone.sh; save 'delete'
is "deleted files, one hit each" \
  "$(lines 'MENTION: lib/gone.sh README.md:1' 'MENTION: tool.sh README.md:1')" "$(run main | LC_ALL=C sort)"

# A path git would quote, and one with a space.
fresh
put 'my tools/caf€.sh' 'body'
put 'my tools/two words.sh' 'body'
put README.md "$(lines 'Run my tools/caf€.sh.' 'Run my tools/two words.sh.')"
branch
git rm -q 'my tools/caf€.sh' 'my tools/two words.sh'; save 'delete'
is "unusual paths are read whole" \
  "$(lines 'MENTION: my tools/caf€.sh README.md:1' 'MENTION: my tools/two words.sh README.md:2')" "$(run main)"

# 8. A changelog is ignored completely.
fresh
put cli.sh 'run --old'
put CHANGELOG.md 'Added --old.'
put docs/CHANGELOG.md 'Added --old.'
put changelog.md 'Added --old.'
branch
put cli.sh 'run'; save 'drop it'
is "a mention only in a changelog: no hit" NONE "$(run main)"

fresh
put cli.sh 'run'
put CHANGELOG.md 'Removed --ancient.'
put README.md 'Use --ancient.'
branch
put cli.sh 'run 2'; put CHANGELOG.md 'Rewrote history.'; save 'edit the changelog'
is "a changelog's lines are no identifiers, its edit no touched doc" NONE "$(run main)"

fresh
put cli.sh 'run'
put CHANGELOG.md 'Old.'
put README.md 'See CHANGELOG.md.'
branch
put cli.sh 'run 2'; git rm -q CHANGELOG.md; save 'delete the changelog'
is "a deleted changelog is no identifier" NONE "$(run main)"

# A code file with changelog in its name is code.
fresh
put changelog.py 'run --from-changelog-tool'
put README.md 'Use --from-changelog-tool.'
branch
put changelog.py 'run'; save 'drop it'
is "changelog.py is code" 'MENTION: --from-changelog-tool README.md:1' "$(run main)"

# 9. A docs-only diff: one NONE, whatever else was given.
fresh
put cli.sh 'x'
put README.md "$(lines 'Use --doc-flag and API_TOKEN.' 'Keep parse_user.')"
put docs/a.md 'Use --doc-flag and API_TOKEN.'
put docs/old.md 'text'
branch
put README.md 'Short now.'; git rm -q docs/old.md; save 'docs only'
is "docs-only diff: exactly NONE" NONE "$(run main)"
is "docs-only diff: extra identifiers ignored" NONE "$(run main 'text' parse_user)"

fresh
put cli.sh 'x'
put README.md 'a'
put CHANGELOG.md 'a'
branch
put README.md 'b'; put CHANGELOG.md 'b'; save 'docs and changelog'
is "docs and a changelog: still docs-only" NONE "$(run main)"

fresh
put README.md 'a'
branch
is "no diff at all: NONE" NONE "$(run main)"

# 10. DOCS TOUCHED, and doc lines never decide an identifier.
fresh
put cli.sh 'run --gone'
put README.md 'Use --gone.'
put docs/a.md 'Use --gone.'
branch
put cli.sh 'run'; put README.md "$(lines 'Do not use it.' 'New.')"; save 'drop and document'
is "mention plus touched doc" \
  "$(lines 'MENTION: --gone docs/a.md:1' 'DOCS TOUCHED: README.md')" "$(run main)"

fresh
put cli.sh 'run'
put README.md 'Use --doc-only.'
put docs/a.md 'Use --doc-only.'
branch
put cli.sh 'run 2'; put README.md 'Gone.'; save 'edit both'
is "a flag removed from a doc only is no identifier" 'DOCS TOUCHED: README.md' "$(run main)"

fresh
put cli.sh 'run --gone'
put README.md 'x'
branch
put cli.sh 'run'; put README.md 'Use --gone.'; save 'add it to a doc'
is "a flag added to a doc only is still gone" \
  "$(lines 'MENTION: --gone README.md:1' 'DOCS TOUCHED: README.md')" "$(run main)"

fresh
put cli.sh 'run'
put docs/old.md 'x'
put docs/moved.md 'a long enough body for rename detection to see it'
branch
put cli.sh 'run 2'; git rm -q docs/old.md; git mv docs/moved.md docs/here.md; save 'mixed'
is "a deleted doc and a renamed one are touched" \
  "$(lines 'DOCS TOUCHED: docs/here.md' 'DOCS TOUCHED: docs/old.md')" "$(run main)"

fresh
put cli.sh 'run'
put docs/old.md 'a long enough body for rename detection to see it'
put docs/index.md 'See old.md and docs/old.md.'
branch
put cli.sh 'run 2'; git mv docs/old.md docs/new.md; save 'mixed'
is "a renamed doc is searched in a mixed diff" \
  "$(lines 'MENTION: docs/old.md docs/index.md:1' 'MENTION: old.md docs/index.md:1' 'DOCS TOUCHED: docs/new.md')" "$(run main)"

fresh
put cli.sh 'run'
put README.md 'x'
branch
put cli.sh 'run 2'; save 'code only'
is "nothing to say: NONE" NONE "$(run main)"

# 11. The docs at HEAD, not the working tree; tracked, not untracked.
fresh
put cli.sh 'run --gone'
put README.md "$(lines 'x' 'Use --gone.')"
put docs/a.md 'y'
branch
put cli.sh 'run'; save 'drop it'
put README.md 'edited away, uncommitted'
put docs/a.md 'Use --gone, uncommitted.'
put docs/new.md 'Use --gone, untracked.'
is "searches HEAD only" 'MENTION: --gone README.md:2' "$(run main)"

# 12. The diff is base...HEAD: what the base did after the fork isn't ours.
fresh
put cli.sh 'run --base-flag'
put other.sh 'run --mine'
put README.md 'Use --base-flag and --mine.'
branch
put other.sh 'run'; save 'drop mine'
git checkout -q main; put cli.sh 'run'; save 'drop on the base'; git checkout -q work
is "three-dot diff" 'MENTION: --mine README.md:1' "$(run main)"

# 13. Cut at 50 lines; DOCS TOUCHED survives the cut.
fresh
put cli.sh 'run --many'
put touched.md 'a'
i=0; : > README.md; while [ $i -lt 60 ]; do echo 'Use --many.' >> README.md; i=$((i+1)); done
branch
put cli.sh 'run'; put touched.md 'b'; save 'drop it'
out=$(run main)
is "cut: 50 mentions" 50 "$(printf '%s\n' "$out" | grep -c '^MENTION: ')"
check "cut: says how many more" '...and 10 more' "$out"
is "cut: the touched doc still prints, last" 'DOCS TOUCHED: touched.md' "$(printf '%s\n' "$out" | tail -1)"

fresh
put cli.sh 'run --many'
i=0; : > README.md; while [ $i -lt 50 ]; do echo 'Use --many.' >> README.md; i=$((i+1)); done
branch
put cli.sh 'run'; save 'drop it'
out=$(run main)
is "exactly 50: all printed" 50 "$(printf '%s\n' "$out" | grep -c '^MENTION: ')"
refute "exactly 50: no cut line" '...and' "$out"

# 14. Binary docs are skipped.
fresh
put cli.sh 'run --gone'
printf 'Use --gone\000 binary\n' > docs.bin; mkdir -p docs; mv docs.bin docs/logo.png
put README.md 'x'
branch
put cli.sh 'run'; save 'drop it'
is "a binary file in docs/ is no hit" NONE "$(run main)"

# 15. From a subfolder: the whole repo, paths from its root.
fresh
put src/cli.sh 'run --gone'
put README.md 'Use --gone.'
branch
put src/cli.sh 'run'; save 'drop it'
is "run from a subfolder" 'MENTION: --gone README.md:1' "$(cd src && run main)"

# 16. A machine's git settings don't change the answer.
fresh
put cli.sh 'run --gone'
put scripts/old.sh 'echo a long enough body for rename detection to see it'
put README.md "$(lines 'Use --gone.' 'Run scripts/old.sh.')"
branch
put cli.sh 'run'; git mv scripts/old.sh scripts/new.sh; save 'drop and rename'
want=$(run main)
git config color.ui always; git config diff.noprefix true; git config diff.renames false
git config grep.lineNumber false; git config grep.patternType perl; git config core.quotePath true
is "git settings change nothing" "$want" "$(run main)"
is "git settings: the answer was right" \
  "$(lines 'MENTION: --gone README.md:1' 'MENTION: scripts/old.sh README.md:2')" "$want"

# 17. UNKNOWN: logged, exit 0, one line, and nothing partial.
fresh
put cli.sh 'x'
branch
out=$(run nope); rc=$?
check "bad base: UNKNOWN" 'UNKNOWN: ' "$out"
check "bad base: says which" nope "$out"
is "bad base: one line" 1 "$(printf '%s\n' "$out" | grep -c .)"
is "bad base: exit 0" 0 "$rc"
check "bad base: logged" nope "$(cat "$LOG" 2>/dev/null)"

check "an option as the base is a bad base" 'UNKNOWN: ' "$(run --output=written)"
[ ! -e written ] && ok "an option as the base writes nothing" || bad "an option as the base writes nothing" "file written"

out=$(run); rc=$?
check "no base: UNKNOWN" 'UNKNOWN: ' "$out"
is "no base: exit 0" 0 "$rc"

mkdir -p "$ROOT/plain"
out=$(cd "$ROOT/plain" && GIT_CEILING_DIRECTORIES="$ROOT" run main); rc=$?
check "not a repo: UNKNOWN" 'UNKNOWN: ' "$out"
is "not a repo: exit 0" 0 "$rc"

rm -f "$LOG"
: > "$ROOT/afile"
out=$(EOW_HOME="$ROOT/afile" run nope); rc=$?
check "the log can't be written: still UNKNOWN" 'UNKNOWN: ' "$out"
is "the log can't be written: one line" 1 "$(printf '%s\n' "$out" | grep -c .)"
is "the log can't be written: exit 0" 0 "$rc"

(unset EOW_HOME; run nope >/dev/null)
check "the log's default root" nope "$(cat "$HOME/.engineer-of-wealth/executor/docs-mentions.log" 2>/dev/null)"

fresh
put a.sh 'x'
branch
git checkout -q --orphan lonely; save 'no common history'
check "no merge base: UNKNOWN" 'UNKNOWN: ' "$(run main)"
run main >/dev/null; is "no merge base: exit 0" 0 "$?"

fresh
out=$(run main); rc=$?
check "no commits yet: UNKNOWN" 'UNKNOWN: ' "$out"
is "no commits yet: exit 0" 0 "$rc"

echo
printf 'docs-mentions.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
