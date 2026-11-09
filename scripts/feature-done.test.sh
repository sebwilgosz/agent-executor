#!/usr/bin/env bash
# Spec tests for how a builder opens its PR: one body file and one pr-open.sh call.
#   A. feature-done.md tells the builder to run pr-open.sh and act on its tagged line.
#   B. feature-done.md no longer hands the builder the git and gh steps.
#   C. the builder agent points at it, and STOP is reported, not worked around.
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

echo
printf 'feature-done: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
