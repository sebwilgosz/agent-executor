#!/usr/bin/env bash
# Spec tests for the model each Executor role runs on:
#   A. the builder runs on Sonnet.
#   B. the reviewer runs on Opus, high effort.
#   C. the verifier runs on Sonnet, high effort.
#   D. the fixer runs on Sonnet, high effort.
#   E. the review and build skills name no model: they run on the session's.
# Each agent names its own model.
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
field_of() {
  awk -v k="$2" 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f && $0 ~ "^" k ":" {print}' "$REPO/$1"
}
model_of() { field_of "$1" model; }

echo "role models spec tests"

is "the builder runs on Sonnet"        'model: sonnet'  "$(model_of agents/builder.md)"
is "the builder runs at medium effort" 'effort: medium' "$(field_of agents/builder.md effort)"
is "the reviewer runs on Opus"         'model: opus'    "$(model_of agents/reviewer.md)"
is "the reviewer runs at high effort"  'effort: high'   "$(field_of agents/reviewer.md effort)"
is "the verifier runs on Sonnet"       'model: sonnet'  "$(model_of agents/verifier.md)"
is "the verifier runs at high effort"  'effort: high'   "$(field_of agents/verifier.md effort)"
is "the fixer runs on Sonnet"          'model: sonnet'  "$(model_of agents/fixer.md)"
is "the fixer runs at high effort"     'effort: high'   "$(field_of agents/fixer.md effort)"
is "the review skill names no model"   ''               "$(model_of skills/review/SKILL.md)"
is "the build skill names no model"    ''               "$(model_of skills/build/SKILL.md)"

echo
printf 'role-models: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
