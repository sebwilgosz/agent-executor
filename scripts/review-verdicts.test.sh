#!/usr/bin/env bash
# Spec tests for scripts/review-verdicts.sh: the caller applies the verifiers'
# verdicts to the review file with a script instead of a fixer agent.
#   A. all debunked: the Critical section is None, the Suggestions stay.
#   B. all reclassified: they move to Suggestions with the verifier's wording.
#   C. a mix: numbering stays continuous #1..#n and the heading counts are fixed.
#   D. a CONFIRMED verdict stays Critical (report-only mode applies only).
#   E. bad input prints one STOP: line and leaves the file untouched.
#   F. text outside the two sections is kept as it is.
#
# Run: bash scripts/review-verdicts.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
APPLY="$SELF_DIR/review-verdicts.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
lacks() { case "$3" in *"$2"*) bad "$1" "unwanted substring: $2" ;; *) ok "$1" ;; esac; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

review() {
  cat > "$ROOT/review.md" <<'MD'
# EXECUTOR REVIEW · [acme/api#7](https://github.com/acme/api/pull/7)
Add export

## CRITICAL (3)

#1: · **Correctness** · [`a.rb:1`](https://x/a.rb#L1)
First defect.

Fails when: a → b.
🛠️: fix a.

#2: · **Security** · [`b.rb:2`](https://x/b.rb#L2)
Second defect.

Fails when: c → d.
🛠️: fix b.

#3: · **Docs** · [`c.md:3`](https://x/c.md#L3)
Third defect.

Fails when: e → f.
🛠️: fix c.

## Suggestions (2)

#4: · **Best practice** · [`d.rb:4`](https://x/d.rb#L4)
Fourth.

Fails when: g → h.
🛠️: tidy d.

#5: · **Convention** · [`e.rb:5`](https://x/e.rb#L5)
Fifth.

Fails when: i → j.
🛠️: tidy e.

## VERDICT [acme/api#7](https://github.com/acme/api/pull/7)
  ▸ **Build:** ✅ passed
MD
}
run() { OUTPUT=$(bash "$APPLY" "$ROOT/review.md" "$ROOT/verdicts.md" 2>&1); RC=$?; FILE=$(cat "$ROOT/review.md"); }

echo "review-verdicts spec tests"

review
printf '#1 DEBUNKED\n#2 DEBUNKED\n#3 DEBUNKED\n' > "$ROOT/verdicts.md"
run
is    "A all debunked: exit 0" 0 "$RC"
check "A all debunked: summary line" 'APPLIED: 0 Critical, 2 Suggestions' "$OUTPUT"
check "A heading counts Critical 0" '## CRITICAL (0)' "$FILE"
check "A Critical section says None." $'## CRITICAL (0)\n\nNone.' "$FILE"
check "A Suggestions heading count" '## Suggestions (2)' "$FILE"
check "A suggestions renumbered from #1" '#1: · **Best practice**' "$FILE"
check "A second suggestion is #2" '#2: · **Convention**' "$FILE"
lacks "A debunked findings gone" 'First defect.' "$FILE"
check "F verdict block kept" '▸ **Build:** ✅ passed' "$FILE"
check "F header kept" '# EXECUTOR REVIEW · [acme/api#7]' "$FILE"

review
cat > "$ROOT/verdicts.md" <<'V'
#1 RECLASSIFIED
FINDING: First defect, only a style issue.
#2 RECLASSIFIED
#3 RECLASSIFIED
V
run
is    "B all reclassified: exit 0" 0 "$RC"
check "B summary line" 'APPLIED: 0 Critical, 5 Suggestions' "$OUTPUT"
check "B Critical is None." $'## CRITICAL (0)\n\nNone.' "$FILE"
check "B Suggestions count 5" '## Suggestions (5)' "$FILE"
check "B verifier wording used" 'First defect, only a style issue.' "$FILE"
lacks "B drafted wording replaced" $'First defect.\n' "$FILE"
check "B no-text reclassify keeps the drafted wording" 'Second defect.' "$FILE"
check "B reclassified come first, in order" $'#1: · **Correctness**' "$FILE"
check "B old suggestion renumbered to #4" '#4: · **Best practice**' "$FILE"
check "B old suggestion renumbered to #5" '#5: · **Convention**' "$FILE"

review
cat > "$ROOT/verdicts.md" <<'V'
#1 DEBUNKED
#2 CONFIRMED
#3 RECLASSIFIED
V
run
is    "C mix: exit 0" 0 "$RC"
check "C summary line" 'APPLIED: 1 Critical, 3 Suggestions' "$OUTPUT"
check "C Critical heading" '## CRITICAL (1)' "$FILE"
check "C Suggestions heading" '## Suggestions (3)' "$FILE"
check "C confirmed one is #1" $'#1: · **Security**' "$FILE"
check "C reclassified one is #2" $'#2: · **Docs**' "$FILE"
check "C old #4 is #3" '#3: · **Best practice**' "$FILE"
check "C old #5 is #4" '#4: · **Convention**' "$FILE"
lacks "C debunked finding gone" 'First defect.' "$FILE"
nums=$(grep -o '^#[0-9]*:' "$ROOT/review.md" | tr '\n' ' ')
is    "C numbering continuous" '#1: #2: #3: #4: ' "$nums"

review
printf '#1 CONFIRMED\n#2 CONFIRMED\n#3 CONFIRMED\n' > "$ROOT/verdicts.md"
run
is    "D all confirmed: exit 0" 0 "$RC"
check "D three stay Critical" '## CRITICAL (3)' "$FILE"
check "D suggestions unchanged" '## Suggestions (2)' "$FILE"
check "D summary line" 'APPLIED: 3 Critical, 2 Suggestions' "$OUTPUT"

review
printf '#2 CONFIRMED\n#2 CONFIRMED\n' > "$ROOT/verdicts.md"
cp "$ROOT/review.md" "$ROOT/before.md"
run
is    "E a duplicate verdict stops" 1 "$RC"
check "E prints a STOP: line" 'STOP:' "$OUTPUT"
is    "E file untouched after a duplicate" "$(cat "$ROOT/before.md")" "$FILE"

printf '#9 DEBUNKED\n' > "$ROOT/verdicts.md"
run
is    "E a verdict for a missing finding stops" 1 "$RC"
is    "E file untouched after a missing finding" "$(cat "$ROOT/before.md")" "$FILE"

printf '#4 DEBUNKED\n' > "$ROOT/verdicts.md"
run
is    "E a verdict on a Suggestion stops" 1 "$RC"
is    "E file untouched after a Suggestion verdict" "$(cat "$ROOT/before.md")" "$FILE"

printf '#1 MAYBE\n' > "$ROOT/verdicts.md"
run
is    "E an unknown verdict stops" 1 "$RC"
is    "E file untouched after an unknown verdict" "$(cat "$ROOT/before.md")" "$FILE"

: > "$ROOT/verdicts.md"
run
is    "E an empty verdicts file stops" 1 "$RC"
is    "E file untouched after an empty verdicts file" "$(cat "$ROOT/before.md")" "$FILE"

printf 'junk\n#1 DEBUNKED\n' > "$ROOT/verdicts.md"
run
is    "E text before the first header stops" 1 "$RC"

OUTPUT=$(bash "$APPLY" "$ROOT/none.md" "$ROOT/verdicts.md" 2>&1); RC=$?
is    "E a missing review file stops" 1 "$RC"
check "E and says STOP:" 'STOP:' "$OUTPUT"
OUTPUT=$(bash "$APPLY" "$ROOT/review.md" "$ROOT/none.md" 2>&1); RC=$?
is    "E a missing verdicts file stops" 1 "$RC"
OUTPUT=$(bash "$APPLY" 2>&1); RC=$?
is    "E no arguments stops" 1 "$RC"

printf '# x\n\nno sections here\n' > "$ROOT/review.md"
printf '#1 DEBUNKED\n' > "$ROOT/verdicts.md"
run
is    "E a file with no sections stops" 1 "$RC"
is    "E and stays untouched" $'# x\n\nno sections here' "$FILE"

# G. the verifier's real one-line format keeps the drafted detail
review
cat > "$ROOT/verdicts.md" <<'V'
#1 CONFIRMED
FINDING: #1: · **Correctness** · [`a.rb:1`](https://x/a.rb#L1) one line only.
#2 RECLASSIFIED
FINDING: Second defect, only cosmetic.
#3 RECLASSIFIED
FINDING: #3: · **Docs** · [`c.md:3`](https://x/c.md#L3) reworded header
V
run
is    "G one-line verdicts: exit 0" 0 "$RC"
check "G confirmed keeps Fails when" 'Fails when: a → b.' "$FILE"
check "G confirmed keeps fix line" '🛠️: fix a.' "$FILE"
check "G confirmed keeps drafted defect" 'First defect.' "$FILE"
lacks "G confirmed ignores the verifier text" 'one line only' "$FILE"
check "G reclassified defect sentence replaced" 'Second defect, only cosmetic.' "$FILE"
lacks "G old defect sentence gone" $'Second defect.\n' "$FILE"
check "G reclassified keeps Fails when" 'Fails when: c → d.' "$FILE"
check "G reclassified keeps fix line" '🛠️: fix b.' "$FILE"
check "G reclassified header replaced" 'reworded header' "$FILE"
check "G header-reworded keeps Fails when" 'Fails when: e → f.' "$FILE"
check "G summary" 'APPLIED: 1 Critical, 4 Suggestions' "$OUTPUT"
lacks "G no FINDING: prefix left" 'FINDING:' "$FILE"

review
cat > "$ROOT/verdicts.md" <<'V'
#2 RECLASSIFIED
FINDING: **#2**: · **Security** · [`b.rb:2`](https://x/b.rb#L2) restated
#1 DEBUNKED
#3 DEBUNKED
V
run
is    "G bold number restated: exit 0" 0 "$RC"
check "G bold number renumbered" '**#1**: · **Security**' "$FILE"
check "G bold keeps Fails when" 'Fails when: c → d.' "$FILE"

echo
printf 'review-verdicts: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
