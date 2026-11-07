#!/usr/bin/env bash
# Spec tests for scripts/spec-home.sh — where a spec is read from and written
# to. It reads the nearest AGENTS.md or CLAUDE.md from a folder upwards, then
# the target repo's own, for a "## Specs" section, and names the kind of home,
# its location, the ticket tracker and the tool that reaches it. It also writes
# the section on a yes, and prepares the local fallback.
# No network: HOME points at a temp dir; the repos are real, with no remote.
#
# Run: bash scripts/spec-home.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
SH="$SELF_DIR/spec-home.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

TMP=$(cd -P "$(mktemp -d)" && pwd)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

n=0
fresh(){ n=$((n+1)); D="$TMP/t$n"; mkdir -p "$D"; }
field(){ printf '%s\n' "$2" | sed -n "s/^$1=//p"; }
put(){ mkdir -p "$(dirname "$1")"; shift_file=$1; shift; printf '%s\n' "$@" > "$shift_file"; }

echo "spec-home.sh spec tests"

# 1. Each way the instructions name a home resolves to the right kind.
fresh
put "$D/AGENTS.md" "# Rules" "" "## Specs" 'Specs: Notion, the "RFCs" database. Tickets: Jira project TRAV.' "" "## Other" "text"
out=$(bash "$SH" "$D")
is "notion: kind" "notion" "$(field kind "$out")"
is "notion: location" 'the "RFCs" database.' "$(field location "$out")"
is "notion: tracker" "jira" "$(field tracker "$out")"
is "notion: file" "$D/AGENTS.md" "$(field file "$out")"
check "notion: names a tool" "Notion" "$(field tool "$out")"

fresh
put "$D/AGENTS.md" "## Specs" 'Specs: in this vault, 623. Projects/<project>/<Name> - spec.md; next to the product note when the work belongs to no project.'
out=$(bash "$SH" "$D")
is "vault: kind" "folder" "$(field kind "$out")"
check "vault: location keeps the path" "623. Projects/<project>/<Name> - spec.md" "$(field location "$out")"
is "vault: no tracker" "none" "$(field tracker "$out")"

fresh
put "$D/AGENTS.md" "## Specs" "Specs: GitHub, a parent issue in this repo, one sub-issue per feature."
out=$(bash "$SH" "$D")
is "github: kind" "github" "$(field kind "$out")"
check "github: tool is gh" "gh" "$(field tool "$out")"

fresh
put "$D/CLAUDE.md" "## Specs" "Specs: docs/specs/ in this repo."
out=$(bash "$SH" "$D")
is "repo folder: kind" "repo" "$(field kind "$out")"
is "repo folder: location" "docs/specs/ in this repo." "$(field location "$out")"
is "repo folder: file" "$D/CLAUDE.md" "$(field file "$out")"

fresh
put "$D/AGENTS.md" "## Specs" "Specs: Linear, the Product project." "Tickets: Linear."
out=$(bash "$SH" "$D")
is "linear on two lines: kind" "linear" "$(field kind "$out")"
is "linear on two lines: tracker" "linear" "$(field tracker "$out")"

fresh
put "$D/AGENTS.md" "## Specs" "Specs: GitHub, a parent issue. Tickets: none."
is "tickets: none" "none" "$(field tracker "$(bash "$SH" "$D")")"

# 2. The nearest file that names a home wins, walking upwards.
fresh
put "$D/AGENTS.md" "## Specs" "Specs: Notion."
put "$D/sub/deeper/AGENTS.md" "## Specs" "Specs: GitHub, a parent issue."
mkdir -p "$D/sub/deeper/work" "$D/sub/other"
is "nearest wins" "github" "$(field kind "$(bash "$SH" "$D/sub/deeper/work")")"
is "a sibling falls back to the parent" "notion" "$(field kind "$(bash "$SH" "$D/sub/other")")"

# 3. A file with no Specs section is skipped.
fresh
put "$D/AGENTS.md" "## Specs" "Specs: Notion."
put "$D/sub/CLAUDE.md" "# Only rules" "## Style" "tabs"
is "no section: the parent's home" "notion" "$(field kind "$(bash "$SH" "$D/sub")")"

# 4. The section ends at the next heading, and only "## Specs" counts.
fresh
put "$D/AGENTS.md" "# Rules" "## Specs and more" "Specs: Notion." "## Specs" "Specs: GitHub." "## Next" "Specs: Notion."
is "exact heading, ends at the next heading" "github" "$(field kind "$(bash "$SH" "$D")")"

# 5. The target repo's own instructions, after the working folder's.
fresh
mkdir -p "$D/cwd" "$D/repo"
put "$D/repo/AGENTS.md" "## Specs" "Specs: GitHub, a parent issue."
out=$(bash "$SH" --repo "$D/repo" "$D/cwd")
is "repo's file when the cwd names nothing" "github" "$(field kind "$out")"
is "repo's file is reported" "$D/repo/AGENTS.md" "$(field file "$out")"
put "$D/cwd/AGENTS.md" "## Specs" "Specs: Notion."
is "the cwd's file wins over the repo's" "notion" "$(field kind "$(bash "$SH" --repo "$D/repo" "$D/cwd")")"

# 6. Nothing names a home.
fresh
mkdir -p "$D/x"
out=$(bash "$SH" "$D/x")
check "nothing: NONE line" "NONE:" "$out"
check "nothing: says run init" "/executor:init" "$out"
check "missing folder: NONE" "NONE:" "$(bash "$SH" "$D/does-not-exist")"

# 7. Ambiguous: two files at one level disagree, or the words do.
fresh
put "$D/AGENTS.md" "## Specs" "Specs: Notion."
put "$D/CLAUDE.md" "## Specs" "Specs: GitHub, a parent issue."
out=$(bash "$SH" "$D")
check "two files disagree: AMBIGUOUS" "AMBIGUOUS:" "$out"
check "two files disagree: names both" "CLAUDE.md" "$out"
put "$D/CLAUDE.md" "## Specs" "Specs: Notion."
is "two files agree" "notion" "$(field kind "$(bash "$SH" "$D")")"
fresh
put "$D/AGENTS.md" "## Specs" "Specs: Notion or GitHub, whichever is handy."
check "two kinds in one line: AMBIGUOUS" "AMBIGUOUS:" "$(bash "$SH" "$D")"
fresh
put "$D/AGENTS.md" "## Specs" "Specs: wherever."
check "no recognizable home: AMBIGUOUS" "AMBIGUOUS:" "$(bash "$SH" "$D")"

# 8. The folder an answer would apply to: the nearest with an instructions file.
fresh
put "$D/space/CLAUDE.md" "# x"
mkdir -p "$D/space/proj/src"
is "folder: nearest with an instructions file" "$D/space" "$(bash "$SH" --folder "$D/space/proj/src")"
put "$D/space/proj/AGENTS.md" "# y"
is "folder: the nearest, not the highest" "$D/space/proj" "$(bash "$SH" --folder "$D/space/proj/src")"
fresh
mkdir -p "$D/bare"
check "folder: none" "NONE" "$(bash "$SH" --folder "$D/bare")"

# 9. Writing the section on a yes.
fresh
put "$D/AGENTS.md" "# Rules" "keep this" "## Specs" "Specs: old." "## Tail" "keep that"
put "$D/CLAUDE.md" "# Claude rules" "also keep"
out=$(bash "$SH" --write "$D" "Specs: GitHub, a parent issue." "Tickets: none.")
check "both files: AGENTS.md written" "$D/AGENTS.md" "$out"
check "both files: CLAUDE.md written" "$D/CLAUDE.md" "$out"
is "replaced, not duplicated" "1" "$(grep -c '^## Specs$' "$D/AGENTS.md")"
check "other content kept" "keep this" "$(cat "$D/AGENTS.md")"
check "the tail kept" "keep that" "$(cat "$D/AGENTS.md")"
refute "the old text gone" "Specs: old." "$(cat "$D/AGENTS.md")"
is "CLAUDE.md gets the section" "github" "$(field kind "$(bash "$SH" "$D")")"
bash "$SH" --write "$D" "Specs: GitHub, a parent issue." "Tickets: none." >/dev/null
is "writing twice stays one section" "1" "$(grep -c '^## Specs$' "$D/CLAUDE.md")"

fresh
put "$D/AGENTS.md" "# Rules"
put "$D/CLAUDE.md" "@AGENTS.md"
out=$(bash "$SH" --write "$D" "Specs: Notion.")
check "CLAUDE.md imports AGENTS.md: AGENTS.md written" "$D/AGENTS.md" "$out"
refute "CLAUDE.md imports AGENTS.md: CLAUDE.md untouched" "CLAUDE.md" "$out"
is "the import line is untouched" "@AGENTS.md" "$(cat "$D/CLAUDE.md")"

fresh
out=$(bash "$SH" --write "$D" "Specs: Notion.")
check "neither file: AGENTS.md created" "$D/AGENTS.md" "$out"
is "neither file: CLAUDE.md imports it" "@AGENTS.md" "$(cat "$D/CLAUDE.md")"
is "neither file: resolves" "notion" "$(field kind "$(bash "$SH" "$D")")"

fresh
put "$D/CLAUDE.md" "# Only claude"
bash "$SH" --write "$D" "Specs: Notion." >/dev/null
is "only CLAUDE.md: it is written" "notion" "$(field kind "$(bash "$SH" "$D")")"
[ ! -e "$D/AGENTS.md" ] && ok "only CLAUDE.md: no AGENTS.md invented" || bad "only CLAUDE.md: no AGENTS.md invented" "AGENTS.md exists"

fresh
check "write: a missing folder is refused" "STOP:" "$(bash "$SH" --write "$D/nope" "Specs: Notion.")"
check "write: an empty section is refused" "STOP:" "$(bash "$SH" --write "$D")"

# 10. The local fallback, kept out of git inside a repo.
fresh
git init -q "$D/repo"; mkdir -p "$D/repo/sub"
out=$(bash "$SH" --local "$D/repo/sub")
is "local: path" "$D/repo/.executor/specs" "$out"
[ -d "$D/repo/.executor/specs" ] && ok "local: folder created" || bad "local: folder created" "missing"
touch "$D/repo/.executor/specs/a - spec.md"
(cd "$D/repo" && git status --porcelain | grep -q executor) && bad "local: kept out of git" "shows in status" || ok "local: kept out of git"
bash "$SH" --local "$D/repo" >/dev/null
is "local: exclude written once" "1" "$(grep -c '^/.executor/specs/$' "$D/repo/.git/info/exclude")"
fresh
is "local, no repo: path" "$D/.executor/specs" "$(bash "$SH" --local "$D")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
