#!/usr/bin/env bash
# Spec test: every line the review instructions tell an agent to write has a place in
# the template of references/review-format.md, so a layout change fails here, not in a review.
#
# Run: bash scripts/review-format-lines.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }

TEMPLATE=$(awk '/^## The summary/{f=1} /^## Where the review lives/{f=0} f' "$REPO/references/review-format.md")
SOURCES="references/review-steps.md skills/review/SKILL.md skills/build/SKILL.md agents/fixer.md agents/reviewer.md"

for line in Verdict Build CI Spec Ready Branch Rounds Docs Checkout; do
  case "$TEMPLATE" in
    *"**$line:**"*) ok "the template has the $line line" ;;
    *) bad "the template has the $line line" "no **$line:** in the summary template of review-format.md" ;;
  esac
done

for f in $SOURCES; do
  for line in Branch Rounds Docs Checkout; do
    if grep -q "$line" "$REPO/$f"; then
      case "$TEMPLATE" in
        *"**$line:**"*) ok "$f names $line: the template has it" ;;
        *) bad "$f names $line" "the template has no **$line:** line" ;;
      esac
    fi
  done
done

echo
printf 'review-format-lines: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
