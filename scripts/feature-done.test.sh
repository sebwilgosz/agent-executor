#!/usr/bin/env bash
# Spec tests for how a builder opens its PR: one body file and one pr-open.sh call.
#   A. feature-done.md tells the builder to run pr-open.sh and act on its tagged line.
#   B. feature-done.md no longer hands the builder the git and gh steps.
#   C. the builder agent points at it, and STOP is reported, not worked around.
#   E. ship's skill opens through pr-open.sh and never runs gh pr create.
#   D. pull-request.md says the script fills Depends on.
#
# Run: bash scripts/feature-done.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
has() { grep -qF -- "$2" "$REPO/$3" && ok "$1" || bad "$1" "$3 lacks: $2"; }
lacks() { grep -qF -- "$2" "$REPO/$3" && bad "$1" "$3 still has: $2" || ok "$1"; }

echo "feature-done spec tests"

has   "feature-done runs pr-open.sh"                  'scripts/pr-open.sh' references/feature-done.md
has   "feature-done acts on the PR: line"             'PR: #' references/feature-done.md
has   "feature-done acts on the STOP: line"           'STOP:' references/feature-done.md
lacks "feature-done has no by-hand gh stack submit"   'gh stack submit' references/feature-done.md
lacks "feature-done has no by-hand gh pr create"      'gh pr create' references/feature-done.md
lacks "feature-done has no by-hand gh pr edit"        'gh pr edit' references/feature-done.md
has   "the builder points at the opening step"        'pr-open.sh' agents/builder.md
has   "the builder reports a STOP, not git by hand"   'STOP' agents/builder.md
has   "pull-request says the script fills Depends on" 'pr-open.sh' references/pull-request.md
has   "ship runs pr-open.sh"                           'scripts/pr-open.sh' skills/ship/SKILL.md
has   "the PR template opens with Why"                '## Why' references/pull-request.md
has   "the PR template asks for plain words"          'Write for a person' references/pull-request.md
has   "the builder opens the PR with Why"             'opens with Why' agents/builder.md
has   "the spec shape gives each feature a Why"       '**Why**, in one or two plain sentences' references/spec.md
has   "the build brief carries the background"        'the background:' skills/build/SKILL.md
has   "ship acts on the STOP: line"                   'STOP:' skills/ship/SKILL.md
lacks "ship has no by-hand gh pr create"              'gh pr create' skills/ship/SKILL.md

# E. Step 2 depends on the CI line the build puts in the brief.
has   "step 2 reads the CI line from the brief"       'CI: configured' references/feature-done.md
has   "step 2 keeps the full local build for no CI"   'CI: none' references/feature-done.md
has   "step 2 leaves the full suite to CI"            'full suite is left to CI' references/feature-done.md
has   "step 2 reads the HOOKS line"                   'HOOKS: installed' references/feature-done.md
has   "step 2: no brief line means no CI"             'treat as `CI: none`' references/feature-done.md
has   "the builder's brief has the lines"             '`CI:` and `HOOKS:`' agents/builder.md
detect=$(grep -rnF 'ci-checks.sh --detect' "$REPO/skills" "$REPO/agents" "$REPO/references")
[ -z "$detect" ] && ok "no skill, agent or reference runs --detect itself" || bad "no skill, agent or reference runs --detect itself" "$detect"

echo
printf 'feature-done: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
