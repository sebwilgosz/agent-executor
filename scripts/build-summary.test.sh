#!/usr/bin/env bash
# Spec tests for the build orchestrating the review agents and printing one compact summary:
#   A. step 4 runs reviewer, verifiers, fixer and review-post.sh; no inline /executor:review.
#   B. one line per finished PR, one block for the whole build; no full summary per PR.
#   C. the failure rules.
#   D. the formats are documented; the standalone review keeps its full summary.
#   E. release 0.13.0: version, version-check calls, CHANGELOG.
#
# Run: bash scripts/build-summary.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2" ;; esac; }
lacks() { case "$3" in *"$2"*) bad "$1" "unwanted substring: $2" ;; *) ok "$1" ;; esac; }

BUILD=$(cat "$REPO/skills/build/SKILL.md")
REVIEW=$(cat "$REPO/skills/review/SKILL.md")
FORMAT=$(cat "$REPO/references/review-format.md")
CHANGELOG=$(cat "$REPO/CHANGELOG.md")
step4=$(printf '%s\n' "$BUILD" | awk '/^## 4\./{f=1; next} /^## 5\./{f=0} f')
step5=$(printf '%s\n' "$BUILD" | awk '/^## 5\./{f=1; next} f')

echo "build summary spec tests"

lacks "build never runs /executor:review inline"    '/executor:review <n>' "$BUILD"
lacks "build step 4 does not call the review skill" '/executor:review' "$step4"
check "step 4 spawns the reviewer"                  'executor:reviewer' "$step4"
check "step 4 spawns the fixer"                     'executor:fixer' "$step4"
check "step 4 runs the verifiers"                   'executor:verifier' "$step4"
check "step 4 posts through review-post.sh"         'review-post.sh' "$step4"
check "step 4 keeps only the return lines"          'never the review file' "$step4"
check "fixer reads CI and Spec from the file header" 'CI and Spec lines from the review file header' "$step4"
check "fixer takes head and base from gh pr view"   'gh pr view' "$step4"
check "reviews of different stacks run together"    'different stacks' "$step4"
check "one fixer per stack"                         'one fixer per stack' "$step4"

check "one line per finished PR"                    'PR #<n> · ✅ ready · <c> Critical · <s> suggestions · <r> rounds · <comment url | file path>' "$step4"
check "step 5 prints the build block"               'Executor build · <spec title>' "$step5"
check "block lists stacks bottom first"             'bottom first' "$step5"
check "block counts suggestions"                    'Suggestions: <n> across <m> PRs' "$step5"
check "block has the Merge line"                    'Merge: ' "$step5"
lacks "step 5 prints no plan checklist"             "Print the plan's checklist" "$step5"
lacks "step 5 prints no summary per PR"             'review summary' "$step5"
check "plan file keeps its checklist"              'plan file keeps its full checklist' "$step5"

check "a STOP of review-post links the file"        'STOP:' "$step4"
check "an unusable agent return fails the PR"       '❌ review failed: <reason>' "$step4"
check "a failed review stops its stack"             'its stack stops' "$step4"
check "nothing is retried silently"                 'nothing is retried silently' "$step4"

count_bullet() { printf '%s\n' "$step4" | grep -cF -- "- **$1:**"; }
for b in '✅ or ⚠️' '❌'; do
  n=$(count_bullet "$b")
  if [ "$n" = 1 ]; then ok "step 4 lists the $b outcome bullet once"
  else bad "step 4 lists the $b outcome bullet once" "found $n"; fi
done

check "no spec: /executor:spec drafts it"           '/executor:spec' "$BUILD"
check "planning stays in the build session"         'no planner agent' "$BUILD"

check "review skill still prints the full summary"  'prints the result' "$REVIEW"
check "format documents the review file"            '## Where the review lives' "$FORMAT"
check "format documents the per-PR line"            '## The line per PR' "$FORMAT"
check "format documents the build block"            '## The build block' "$FORMAT"

check "plugin.json is 0.13.2"                       '"version": "0.13.2"' "$(cat "$REPO/.claude-plugin/plugin.json")"
for s in build ship init; do
  check "$s skill checks version 0.13.2"            'version-check.sh 0.13.2' "$(cat "$REPO/skills/$s/SKILL.md")"
done
check "CHANGELOG has 0.13.0"                        '## 0.13.0' "$CHANGELOG"
check "CHANGELOG gives the measured reason"         '3.98M of 7.1M' "$CHANGELOG"
check "CHANGELOG covers the review file"            'review-post.sh' "$CHANGELOG"
check "CHANGELOG covers the agents"                 'executor:reviewer' "$CHANGELOG"

echo
printf 'build-summary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
