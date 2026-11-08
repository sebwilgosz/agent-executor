#!/usr/bin/env bash
# Spec tests for scripts/plan-items.sh, the one reader of a plan's items:
#   A. a second script can source it and read what an item, its name, its PR, its
#      branch, a stop sign and a hammer are;
#   B. nothing else in scripts/ keeps its own copy;
#   C. plan-state.sh keeps its contract when the reader is gone.
# No network: nothing here calls gh. HOME and EOW_HOME point at a temp dir. It runs
# the scripts with /bin/bash where there is one: macOS's is bash 3.2.
#
# Run: bash scripts/plan-items.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd -P "$SELF_DIR/.." && pwd)
SHELL_BIN=bash
[ -x /bin/bash ] && SHELL_BIN=/bin/bash

PASS=0; FAIL=0
ok()     { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()    { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()     { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }

TMP=$(mktemp -d)
TMP=$(cd -P "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export EOW_HOME="$TMP/eow"
unset EXECUTOR_PLANS GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
mkdir -p "$HOME"
export READER="$SELF_DIR/plan-items.sh"

# The second script: it sources the reader and prints what it says about each item.
cat > "$TMP/second.sh" <<'SECOND_EOF'
set -u
. "$READER"
read_items "$1" || { echo "cannot read"; exit 0; }
echo "items ${#items[@]}"
[ "${#items[@]}" -gt 0 ] || exit 0
for item in "${items[@]}"; do
  parse_item "$item"
  echo "$(item_name "$item")|$ITEM_PR|$ITEM_BRANCH|$ITEM_BLOCKED|$ITEM_BUILDING|$ITEM_TICKED"
done
SECOND_EOF
second() { (cd "$TMP" && "$SHELL_BIN" "$TMP/second.sh" "$@" 2>&1); }

echo "plan-items.sh spec tests"

# A. What an item is, and what is read from it.
PLAN="$TMP/plan.md"
{
  printf '%s\n' '# A plan' \
    'Prose about - [ ] something, not an item' \
    '## Stack A' \
    '- [ ] Plain' \
    '- [x] Done thing [spec](spec.md#a) — PR #12' \
    '  - [X] Indented [spec](spec.md#b) branch `feat/x`' \
    '- [ ] Fix PR #9 in the name [spec](spec.md#c) — branch feat/y' \
    '- [ ] Blocked [spec](spec.md#d) ⛔ is PR #3 the one?' \
    '- [ ] Building [spec](spec.md#e) 🔨 branch feat/z' \
    '- [ ] ⛔ in the name [spec](spec.md#f)' \
    '- [ ] No link PR #4 branch both'
  printf '%s\r\n' '- [x] Windows line — PR #5'
  printf '%s' '- [ ] Last line, no newline'
} > "$PLAN"
out=$(second "$PLAN")
is "second script: the items, in order" "items 10
Plain|||0|0|0
Done thing|12||0|0|1
Indented||feat/x|0|0|1
Fix PR #9 in the name||feat/y|0|0|0
Blocked|3||1|0|0
Building||feat/z|0|1|0
⛔ in the name|||0|0|0
No link|4|both|0|0|0
Windows line|5||0|0|1
Last line, no newline|||0|0|0" "$out"

# A long name is cut the same way whatever locale the caller runs in, and never
# leaves half a character behind.
A59=$(printf 'a%.0s' $(seq 1 59))
printf '%s\n' "- [ ] ${A59}éééé [spec](spec.md)" > "$PLAN"
is "long name: cut at the limit, on a whole character" "items 1
$A59...|||0|0|0" "$(second "$PLAN")"
is "long name: the same in a UTF-8 locale" "items 1
$A59...|||0|0|0" "$(LC_ALL=en_US.UTF-8 second "$PLAN")"

# Empty and wrong input.
printf '# No items here\n' > "$PLAN"
is "no items: an empty list, under set -u" "items 0" "$(second "$PLAN")"
is "missing plan: says so, no noise" "cannot read" "$(second "$TMP/gone.md")"

# Sourcing has no side effect a caller can trip on.
out=$(cd "$TMP" && "$SHELL_BIN" -c 'set -u; trap "echo trapped" EXIT; . "$READER"; echo sourced' 2>&1)
is "sourcing: prints nothing, ends nothing, keeps the caller's trap" "sourced
trapped" "$out"
"$SHELL_BIN" -c '. "$READER"' >/dev/null 2>&1
is "sourcing: returns 0" "0" "$?"

# B. No second parser.
for def in 'ITEM_RE=' 'UNTICKED_RE=' 'PR_RE=' 'BRANCH_RE=' 'NAME_MAX=' 'short_name()' 'state_text()' 'item_name()'; do
  hits=$(grep -lF -- "$def" "$SELF_DIR"/*.sh | grep -v '\.test\.sh$' | grep -v '/plan-items\.sh$')
  is "only the reader defines $def" "" "$hits"
done

local_refs=$(grep -nE '/Users/|\[\[[A-Za-z]' "$REPO_ROOT/scripts/plan-items.sh")
is "the reader names nothing local" "" "$local_refs"

# C. Without the reader plan-state.sh still prints one line and exits 0: a plan it
# can't read is an UNKNOWN, logged, and no plan is still NONE.
BROKEN="$TMP/broken"; mkdir -p "$BROKEN"
cp "$SELF_DIR/plan-state.sh" "$SELF_DIR/plan-path.sh" "$BROKEN/"
printf -- '- [ ] Something\n' > "$PLAN"
out=$(cd "$TMP" && "$SHELL_BIN" "$BROKEN/plan-state.sh" "$PLAN" 2>&1); rc=$?
check "reader gone: UNKNOWN" "UNKNOWN: " "$out"
check "reader gone: names the file" "plan-items.sh" "$out"
is "reader gone: one line" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
is "reader gone: exit 0" "0" "$rc"
check "reader gone: logged" "plan-items.sh" "$(cat "$EOW_HOME/executor/plan-state.log" 2>/dev/null)"
is "reader gone, no plan: still NONE" "NONE" "$(cd "$TMP" && "$SHELL_BIN" "$BROKEN/plan-state.sh" "$TMP/gone.md" 2>&1)"

echo
printf 'plan-items.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
