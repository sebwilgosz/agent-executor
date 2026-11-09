#!/usr/bin/env bash
# Spec tests for the concrete terms in /executor:review's six dimensions:
#   A. correctness names integer overflow; security names cross-site scripting,
#      CSRF and SSRF; best practices spells out the performance traps and when
#      one is Critical.
#   B. the six dimensions stay the one rubric: no seventh, no separate checklist,
#      and a performance finding is `Best practice`, not a category of its own.
#   C. docs drift sits in dimension 6, with its own category and severity rule.
#   D. the review marks your PR ready, and it is the only place that does.
# Whether a review finds these things is walked through by hand (see the PR).
#
# Run: bash scripts/review-rubric.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2" ;; esac; }
is()    { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }

STEP3=$(awk '/^## 3\. /{f=1; print; next} /^## /{f=0} f' "$REPO/references/review-steps.md")
dimension() { printf '%s\n' "$STEP3" | grep "^$1\. \*\*"; }
CORRECTNESS=$(dimension 2)
SECURITY=$(dimension 4)
PRACTICES=$(dimension 5)
CATEGORIES=$(grep '^- \*\*Category\*\*' "$REPO/references/review-format.md")

echo "review rubric spec tests"

# A. The concrete terms, each in its own dimension.
check "correctness: integer overflow" 'integer overflow' "$CORRECTNESS"
for term in 'cross-site scripting' 'CSRF' 'SSRF'; do
  check "security: $term" "$term" "$SECURITY"
done
for term in 'N+1 and other queries in a loop' 'unbounded queries or loops' \
            'O(n²) over user-sized data' 'a new query with no index'; do
  check "best practices: $term" "$term" "$PRACTICES"
done
check "best practices: when a trap is Critical" \
  'Critical only when the cost is real on a path the diff touches (an unbounded query on a request path, an N+1 over user data); otherwise a Suggestion' \
  "$PRACTICES"
TRAP='a performance trap whose cost is real on a path the diff touches'
check "severity: the format's rule keeps a real trap Critical" "$TRAP" "$(grep '^- \*\*Critical\*\*' "$REPO/references/review-format.md")"
check "severity: the verifier's rule keeps a real trap Critical" "$TRAP" "$(grep 'Re-judge the severity' "$REPO/agents/verifier.md")"

# B. One rubric.
check "step 3 still says six dimensions" 'six dimensions' "$STEP3"
is "step 3 lists exactly six dimensions" 6 "$(printf '%s\n' "$STEP3" | grep -c '^[0-9]*\. \*\*')"
[ ! -e "$REPO/references/review-checklist.md" ] && ok "no separate review checklist" \
  || bad "no separate review checklist" "references/review-checklist.md exists"
check "a performance finding is Best practice" 'Best practice' "$CATEGORIES"
case "$CATEGORIES" in
  *[Pp]erformance*) bad "no Performance category" "$CATEGORIES" ;;
  *) ok "no Performance category" ;;
esac

# C. Docs drift lives in dimension 6: the script, then judgement.
CONVENTIONS=$(printf '%s\n' "$STEP3" | awk '/^6\. \*\*/{f=1} /^Write each finding/{f=0} f')
check "dimension 6 runs the docs check" 'scripts/docs-mentions.sh' "$CONVENTIONS"
check "docs not touched for a change: Suggestion" 'Suggestion' "$(printf '%s\n' "$CONVENTIONS" | grep 'docs-mentions')"
check "docs stating something false: Critical" 'Critical' "$(printf '%s\n' "$CONVENTIONS" | grep 'docs-mentions')"
check "UNKNOWN skips the check and goes on" 'UNKNOWN' "$(printf '%s\n' "$CONVENTIONS" | grep 'docs-mentions')"
check "Docs is a category" 'Docs' "$CATEGORIES"
FALSE_DOCS='leaves docs stating something false'
check "severity: the format's rule keeps false docs Critical" "$FALSE_DOCS" "$(grep '^- \*\*Critical\*\*' "$REPO/references/review-format.md")"
check "severity: the verifier's rule keeps false docs Critical" "$FALSE_DOCS" "$(grep 'Re-judge the severity' "$REPO/agents/verifier.md")"
check "the summary has a line for a skipped docs check" '**Docs:**' "$(cat "$REPO/references/review-format.md")"

# D. The review marks your PR ready, and it is the only place that does.
STEP7=$(awk '/^## 7\. /{f=1; print; next} /^## /{f=0} f' "$REPO/references/review-steps.md")
check "step 7 runs the ready script" 'scripts/review-ready.sh' "$STEP7"
check "step 7: only in fix mode" 'Fix mode' "$STEP7"
check "step 7: a review by branch too" 'review-ready.sh --branch' "$STEP7"
check "step 7: on a passing verdict" '✅ or ⚠️' "$STEP7"
check "the summary has a line for it" '**Ready:**' "$(cat "$REPO/references/review-format.md")"
for f in skills/build/SKILL.md skills/ship/SKILL.md agents/builder.md references/feature-done.md references/stacks.md; do
  is "$f doesn't run gh pr ready itself" "0" "$(grep -c 'gh pr ready' "$REPO/$f")"
done

# E. The review uses CI: step 2 asks ci-checks.sh, step 6 reuses the answer.
STEP2=$(awk '/^## 2\. /{f=1; print; next} /^## /{f=0} f' "$REPO/references/review-steps.md")
STEP6=$(awk '/^## 6\. /{f=1; print; next} /^## /{f=0} f' "$REPO/references/review-steps.md")
check "step 2 asks ci-checks.sh for a PR, waiting"  'scripts/ci-checks.sh <n> --wait 20' "$STEP2"
check "step 2: runs in the background"              'background' "$(printf '%s\n' "$STEP2" | grep 'ci-checks.sh')"
check "step 2: red is a Critical Build finding"     'Critical finding, category Build' "$STEP2"
check "step 2: red evidence has the LOG lines"      'LOG:' "$STEP2"
check "step 2: still running is no Critical"        'still running' "$STEP2"
check "step 2: no CI builds locally"                'CI: none' "$STEP2"
check "step 2: UNKNOWN builds locally"              'UNKNOWN' "$STEP2"
check "step 2: no longer only reads gh pr checks"   'ci-checks.sh' "$STEP2"
check "step 6 reuses step 2's answer"               "step 2's answer" "$STEP6"
check "step 6: only the tests that cover the fixes" 'only the tests that cover' "$STEP6"
check "step 6: CI on the pushed head"               'ci-checks.sh <n> --wait 20' "$STEP6"
check "build step 5 lists a draft left for CI"      'review-ready.sh' "$(awk '/^## 5\. /{f=1; print; next} /^## /{f=0} f' "$REPO/skills/build/SKILL.md")"
check "the Ready line says why a draft was left"    'CI still running' "$(cat "$REPO/references/review-format.md")"

echo
printf 'review-rubric: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
