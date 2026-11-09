#!/usr/bin/env bash
# Spec tests for the reviewer and fixer agents and the review skill as their caller:
#   A. the agents' tools and their return shapes.
#   B. the steps live once, in references/review-steps.md; the skill does not copy them.
#   C. the flow: reviewer, then verifiers and fixer only for Critical findings, then the post.
#   D. the failure rules.
#
# Run: bash scripts/review-agents.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2" ;; esac; }
lacks() { case "$3" in *"$2"*) bad "$1" "unwanted substring: $2" ;; *) ok "$1" ;; esac; }
is()    { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }

field_of() {
  awk -v k="$2" 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f && $0 ~ "^" k ":" {print}' "$REPO/$1"
}

REVIEWER=$(cat "$REPO/agents/reviewer.md")
FIXER=$(cat "$REPO/agents/fixer.md")
SKILL=$(cat "$REPO/skills/review/SKILL.md")
STEPS=$(cat "$REPO/references/review-steps.md")

echo "review agents spec tests"

is "reviewer tools" 'tools: Read, Grep, Glob, Bash, Write' "$(field_of agents/reviewer.md tools)"
is "fixer tools"    'tools: Read, Grep, Glob, Edit, Write, Bash' "$(field_of agents/fixer.md tools)"
check "reviewer returns the REVIEW line"       'REVIEW: <file path>' "$REVIEWER"
check "reviewer returns the MODE line"         'MODE: fix · <why> | report-only · <why>' "$REVIEWER"
check "reviewer returns the BUILD line"        'BUILD: passed | failed | not run · <reason>' "$REVIEWER"
check "reviewer returns the Critical lines"    'each Critical finding line, verbatim' "$REVIEWER"
check "reviewer returns the SUGGESTIONS count" 'SUGGESTIONS: <n>' "$REVIEWER"
check "reviewer tags a build finding"          '[build]' "$REVIEWER"
check "reviewer never pushes"                  'never push' "$REVIEWER"
check "reviewer removes its worktree"          'Remove the throwaway build worktree' "$REVIEWER"
check "fixer returns one DONE line"            'DONE: #<n> · <✅|⚠️|❌> · <c> Critical open · <s> suggestions · <r> rounds · <f> fixed · <file>' "$FIXER"
check "fixer applies verdicts when all debunked" 'also when every finding was debunked' "$FIXER"
check "fixer removes its stack worktree on failure" 'also when you fail or stop early' "$FIXER"
check "fixer re-reviews every round"           'every round, the last included' "$FIXER"

check "steps file has step 7"                  '## 7. Report' "$STEPS"
check "skill points to the steps file"         'references/review-steps.md' "$SKILL"
lacks "skill does not copy step 3"             'Go through the diff once per dimension' "$SKILL"
lacks "skill does not copy step 6"             'at most **3 rounds**' "$SKILL"
lacks "agents do not copy step 3"              'Go through the diff once per dimension' "$REVIEWER$FIXER"

check "skill spawns the reviewer"              'executor:reviewer' "$SKILL"
check "skill spawns the fixer"                 'executor:fixer' "$SKILL"
check "verifiers only with Critical findings"  'only when `CRITICAL` is above 0' "$SKILL"
check "no Critical: caller runs review-ready"  'run `review-ready.sh`' "$SKILL"
check "steps: the caller spawns the verifiers" "subagents can't spawn agents" "$STEPS"
check "steps: a [build] finding goes as CONFIRMED" 'a `[build]` finding as CONFIRMED' "$STEPS"
check "steps: unusable return is a failed review"  '`❌ review failed: <reason>`' "$STEPS"
check "steps: nothing is retried silently"     'nothing is retried silently' "$STEPS"

order=$(printf '%s\n' "$STEPS" | awk '/^\*\*The caller then saves/{f=1} f')
a=${order%%Post it only through*}; b=${order%%Print the summary*}
[ ${#a} -lt ${#b} ] && ok "step 7: post before printing the summary" || bad "step 7: post before printing the summary" "order is wrong"
lacks "step 7: no stale 'nothing after it' sentence" 'nothing after it but the commit links' "$STEPS"

echo
printf 'review-agents: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
