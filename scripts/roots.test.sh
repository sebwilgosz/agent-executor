#!/usr/bin/env bash
# Spec tests for scripts/roots.sh — the one reader of the search roots, the
# folders where Executor looks for a PR's local checkout. One case per rule:
# the default when the file, the section or the list is missing, the config's
# order kept, a leading ~ expanded, other sections and blank lines ignored.
# No network: EOW_HOME and HOME point at a temp dir.
#
# Run: bash scripts/roots.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
READER="$SELF_DIR/roots.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()   { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }

TMP=$(mktemp -d)
trap 'chmod -R u+rw "$TMP"; rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export EOW_HOME="$TMP/eow"
CFG="$EOW_HOME/executor/config.md"
mkdir -p "$HOME"

# Sources the reader as a caller would and prints the roots, one per line.
show='. "$1"; printf "%s\n" "${roots[@]}"'
roots(){ bash -c "$show" _ "$READER" 2>&1; }
config(){ mkdir -p "$(dirname "$CFG")"; printf '%s\n' "$@" > "$CFG"; }

echo "roots.sh spec tests"

# 1. Nothing configured means the default, ~/Projects.
rm -rf "$EOW_HOME"
is "no config file: the default"  "$HOME/Projects" "$(roots)"
config "# Executor settings" "" "## Other" "- ~/elsewhere"
is "no Roots section: the default" "$HOME/Projects" "$(roots)"
config "# Executor settings" "" "## Roots" "" "## Other" "- ~/elsewhere"
is "empty Roots list: the default" "$HOME/Projects" "$(roots)"
config "# Executor settings" "" "## Roots"
is "Roots heading only: the default" "$HOME/Projects" "$(roots)"

# 2. The configured roots, in the config's order, ~ expanded.
config "# Executor settings" "" "## Roots" "- ~/code" "- /srv/repos" "- ~"
is "order kept, ~ expanded" "$HOME/code
/srv/repos
$HOME" "$(roots)"
config "## Roots" "- /work/my repos"
is "a path with a space stays one root" "/work/my repos" "$(roots)"
config "## Roots" "- /srv/a~b"
is "only a leading ~ expands" "/srv/a~b" "$(roots)"

# 3. Blank lines and lines outside the section are ignored.
config "# Executor settings" "- /top" "" "## Notes" "- /notes" "" "## Roots" "" \
  "- ~/code" "" "some text" "- ~/Projects  " "" "## After" "- /after"
is "other sections and blank lines ignored" "$HOME/code
$HOME/Projects" "$(roots)"

# 4. EOW_HOME unset: the file under ~/.engineer-of-wealth is read.
mkdir -p "$HOME/.engineer-of-wealth/executor"
printf '## Roots\n- ~/code\n' > "$HOME/.engineer-of-wealth/executor/config.md"
is "EOW_HOME unset: ~/.engineer-of-wealth" "$HOME/code" \
  "$(env -u EOW_HOME bash -c "$show" _ "$READER" 2>&1)"

# 5. Sourcing prints nothing and never fails, even on an unreadable file.
config "## Roots" "- ~/code"
out=$(bash -c '. "$1"' _ "$READER" 2>&1); rc=$?
is "sourcing prints nothing" "" "$out"
is "sourcing succeeds" "0" "$rc"
is "safe under set -eu" "after" "$(bash -c 'set -eu; . "$1"; echo after' _ "$READER" 2>&1)"
chmod 000 "$CFG"
is "unreadable config: the default" "$HOME/Projects" "$(roots)"
chmod 644 "$CFG"

echo
printf 'roots.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
