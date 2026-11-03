#!/usr/bin/env bash
# Spec tests for reviewing a pull request from any folder:
#   A. /executor:review is wired to scripts/find-checkout.sh for owner/repo#N
#      and github.com pull URLs, acts on every tag it prints, and keeps a bare
#      PR number or a branch name as before.
#   B. its description triggers on "let's review <ref>" from any session.
#   C. the help, the README and the review format describe the flow.
#   D. the release: one version in the manifest, the entry skills and the
#      changelog's top entry, which covers the roots, the finder and the hand-off.
#   E. nothing shipped for this flow names local or personal material.
# The skill's behaviour itself is walked through by hand (see the PR).
#
# Run: bash scripts/review-handoff.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2" ;; esac; }
is()    { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }

REVIEW=$(cat "$REPO/skills/review/SKILL.md")
HELP=$(cat "$REPO/skills/help/SKILL.md")
README=$(cat "$REPO/README.md")
FORMAT=$(cat "$REPO/references/review-format.md")
desc=$(sed -n '2,/^---$/p' "$REPO/skills/review/SKILL.md" | grep '^description:')

echo "review hand-off spec tests"

# A. Wiring.
check "review runs the checkout finder" 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/find-checkout.sh' "$REVIEW"
check "review sends owner/repo#N refs to it" 'owner/repo#N' "$REVIEW"
check "review sends github.com pull URLs to it" 'github.com/owner/repo/pull/N' "$REVIEW"
for t in PR HERE CHECKOUT ALSO NOTE BASE RUN LOOKED CLONE STOP; do
  check "review acts on $t:" "\`$t:" "$REVIEW"
done
check "review clones only with --clone, after asking" 'find-checkout.sh "<ref>" --clone' "$REVIEW"
check "a bare PR number keeps today's lookup" 'gh pr view <n> --json number,title,url,headRefName,headRefOid,baseRefName,isCrossRepository,body,files,additions,deletions,closingIssuesReferences' "$REVIEW"
check "a branch name keeps today's target" '| a branch name' "$REVIEW"
check "the hand-off runs the review on the URL" '/executor:review <url>' "$REVIEW"
check "the hand-off carries the base to the new session" '--base origin/<default>' "$REVIEW"
check "the review reads --base" '`--base origin/<default>`' "$REVIEW"

# B. Triggering.
check "description: 'let's review'" "let's review" "$desc"
check "description: owner/repo#N" "owner/repo#N" "$desc"
check "description: any folder" "any folder" "$desc"

# C. Docs.
check "help lists a ref from another repo" 'owner/repo#N' "$HELP"
check "help routes 'let's review'" "\"let's review <ref>\"" "$HELP"
check "README: review from any folder" 'Review from any folder' "$README"
check "README: the roots setting" '## Roots' "$README"
check "README: where the setting lives" '~/.engineer-of-wealth/executor/config.md' "$README"
check "README: the printed command" 'cd "' "$README"
check "review format: the Branch line names the origin base" 'from origin/<default>' "$FORMAT"

# D. Release.
if command -v jq >/dev/null 2>&1; then
  pv=$(jq -r '.version // empty' "$REPO/.claude-plugin/plugin.json")
else
  pv=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$REPO/.claude-plugin/plugin.json" | head -1 | grep -oE '"[^"]+"$' | tr -d '"')
fi
is "manifest is 0.4.0" "0.4.0" "$pv"
top=$(grep -m1 '^## ' "$REPO/CHANGELOG.md")
check "changelog's top entry is the manifest's version" "## $pv — " "$top"
entry=$(awk '/^## /{n++} n==1' "$REPO/CHANGELOG.md")
check "changelog: the roots setting" '## Roots' "$entry"
check "changelog: the checkout finder" 'scripts/find-checkout.sh' "$entry"
check "changelog: the hand-off" 'claude "/executor:review' "$entry"
for s in build ship init; do
  check "skill $s asserts $pv" "version-check.sh $pv" "$(cat "$REPO/skills/$s/SKILL.md")"
done

# E. Nothing local.
local_re='secondbrain|kaligo|mindskein|/Users/|~/work|\[\['
for f in skills/review/SKILL.md skills/help/SKILL.md README.md references/review-format.md; do
  hit=$(grep -niE "$local_re" "$REPO/$f" | head -1)
  [ -z "$hit" ] && ok "$f names nothing local" || bad "$f names nothing local" "$hit"
done
hit=$(printf '%s\n' "$entry" | grep -niE "$local_re" | head -1)
[ -z "$hit" ] && ok "the changelog entry names nothing local" || bad "the changelog entry names nothing local" "$hit"

echo
printf 'review-handoff: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
