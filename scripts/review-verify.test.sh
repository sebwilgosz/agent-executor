#!/usr/bin/env bash
# Spec tests for which findings the review verifies:
#   A. step 5 spawns one verifier per Critical finding, none for Suggestions.
#   B. a finding whose severity can't be settled is drafted as Critical.
#   C. verdicts are unchanged and a Critical brought down is listed as a Suggestion.
#   D. the format file says Suggestions are not verified.
#   E. no file still says every finding is verified.
# Whether exactly the Critical findings get a verifier is walked through by hand (see the PR).
#
# Run: bash scripts/review-verify.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2" ;; esac; }
lacks() { case "$3" in *"$2"*) bad "$1" "unwanted substring: $2" ;; *) ok "$1" ;; esac; }

SKILL="$REPO/references/review-steps.md"
STEP4=$(awk '/^## 4\. /{f=1; print; next} /^## /{f=0} f' "$SKILL")
STEP5=$(awk '/^## 5\. /{f=1; print; next} /^## /{f=0} f' "$SKILL")
FORMAT=$(cat "$REPO/references/review-format.md")

echo "review verify spec tests"

check "step 5 is headed one agent per Critical finding" '## 5. Verify: one agent per Critical finding' "$STEP5"
check "step 5 spawns one verifier per Critical finding" 'one `executor:verifier` agent per Critical finding' "$STEP5"
check "step 5 keeps the failed-build exception"        'except a failed build' "$STEP5"
check "step 5 keeps one message"                       'all in one message' "$STEP5"
check "step 5 says Suggestions get no verifier"        'Suggestions get no verifier' "$STEP5"
check "step 4 drafts an unsettled severity as Critical" 'draft it as Critical' "$STEP4"
check "RECLASSIFIED still moves the finding"           'move it to the severity the verifier gave, with its wording' "$STEP5"
check "DEBUNKED still removes the finding"             'remove from output' "$STEP5"
check "the format file says only Critical is verified" 'Only Critical findings are auto-verified' "$FORMAT"
check "the format file lists Suggestions as drafted"   'as the reviewer drafted them' "$FORMAT"
check "the verifier is spawned per Critical finding"   'one agent per Critical finding' "$(grep '^description:' "$REPO/agents/verifier.md")"
lacks "the skill no longer verifies every finding"     'verifying every finding' "$(cat "$SKILL")"
lacks "the README no longer sends every finding"       'Every finding goes to its own' "$(cat "$REPO/README.md")"
lacks "the manifest no longer verifies each finding"   'verifies each finding' "$(cat "$REPO/.claude-plugin/plugin.json")"

echo
printf 'review-verify: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
