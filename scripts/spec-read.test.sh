#!/usr/bin/env bash
# Spec tests for reading a spec from its home: /executor:build (step 1) and
# /executor:review look in the spec home besides the repo paths they checked
# before. A Notion page, a GitHub issue, a Jira epic or a vault note all work as
# the spec. The behaviour is the model's, so the tests hold the text it reads:
# the order of the places, how one spec is picked when there are several, and
# that nothing is written back. No network.
#
# Run: bash scripts/spec-read.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
cd "$(cd -P "$SELF_DIR/.." && pwd)" || exit 1

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2" ;; esac; }
before(){ # before <name> <first> <second> <text>: first appears earlier in the text than second
  local t=$4 a b pre
  a=; b=
  case "$t" in *"$2"*) pre=${t%%"$2"*}; a=${#pre} ;; esac
  case "$t" in *"$3"*) pre=${t%%"$3"*}; b=${#pre} ;; esac
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && ok "$1" || bad "$1" "'$2' at ${a:-none}, '$3' at ${b:-none}"
}

BUILD=$(cat skills/build/SKILL.md)
STEP1=$(printf '%s\n' "$BUILD" | awk '/^## 1\. The spec/{f=1;next} /^## 2\./{f=0} f')
REVIEW=$(cat skills/review/SKILL.md)
FIND=$(printf '%s\n' "$REVIEW" | awk '/^Find the spec/{f=1} /^If No spec found/{f=0} f')
HOME_DOC=$(cat references/spec-home.md)
IMPL=$(cat references/implementation.md)

echo "reading a spec from its home spec tests"

# 1. Build step 1: what the user gave, then the spec home, then the repo.
check "build: may run the resolver" 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-home.sh:*)' "$BUILD"
check "build: resolves the home with the script" "scripts/spec-home.sh" "$STEP1"
before "build: what the user gave comes before the home" "what the user gave" "spec home" "$STEP1"
before "build: the home comes before the repo paths" "spec home" "docs/specs/" "$STEP1"
check "build: the repo paths still count" "SPEC.md" "$STEP1"
check "build: follows the shared rule for picking one" "references/spec-home.md" "$STEP1"

# 2. Review: the PR's own links first, then the home, then the repo.
before "review: the PR body comes before the home" "links in the PR body" "spec home" "$FIND"
before "review: the issues it closes come before the home" "issues it closes" "spec home" "$FIND"
before "review: the home comes before the repo paths" "spec home" "SPEC.md" "$FIND"
check "review: a linked issue is read as the spec" "linked issue" "$FIND"
check "review: resolves the home with the script" "scripts/spec-home.sh" "$FIND"
check "review: follows the shared rule for picking one" "references/spec-home.md" "$FIND"

# 3. The shared rule: which spec, in which home, and how it is read.
check "rule: a section for reading" "## Read a spec from the home" "$HOME_DOC"
check "rule: match by what the user named" "what the user named" "$HOME_DOC"
check "rule: match by the branch" "branch" "$HOME_DOC"
check "rule: match by the PR title" "PR title" "$HOME_DOC"
check "rule: several specs, none matches: ask" "ask which" "$HOME_DOC"
check "rule: a vault note is named <Name> - spec.md" "Scheduled Releases - spec.md" "$HOME_DOC"
for k in "Notion page" "GitHub issue" "Jira epic" "vault note"; do check "rule: a $k works as the spec" "$k" "$HOME_DOC"; done
check "rule: it never writes back" "never written back" "$HOME_DOC"
check "rule: a missing tool is named, not guessed" "unread" "$HOME_DOC"

# 4. The spec check names the same places.
check "spec check: finds the spec in the home" "spec home" "$IMPL"

echo
printf "spec-read: %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
