#!/usr/bin/env bash
# Spec tests for the model each Executor role runs on:
#   A. the builder runs on Sonnet.
#   B. the review runs on Opus.
#   C. the verifier runs on Sonnet.
# Each role names its own model, so none of them follows the session's.
#
# Run: bash scripts/role-models.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()  { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }

# The model line of a file's frontmatter, so a mention in its body doesn't count.
model_of() {
  awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f && /^model:/ {print}' "$REPO/$1"
}

echo "role models spec tests"

is "the builder runs on Sonnet"  'model: sonnet' "$(model_of agents/builder.md)"
is "the review runs on Opus"     'model: opus'   "$(model_of skills/review/SKILL.md)"
is "the verifier runs on Sonnet" 'model: sonnet' "$(model_of agents/verifier.md)"

echo
printf 'role-models: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
