#!/usr/bin/env bash
# Spec tests for scripts/review-post.sh: where a review is saved and when it is
# posted. `gh` is a stub on PATH that logs each call and answers from variables,
# so nothing touches the network.
#
# Run: bash scripts/review-post.test.sh   (exit 0 = all pass, non-zero = a failure)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
POST="$SELF_DIR/review-post.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check(){ case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
BIN="$ROOT/bin"; mkdir -p "$BIN"
export EOW_HOME="$ROOT/eow"
export GH_LOG="$ROOT/gh.log"
export GH_ME="me" GH_VIEW="me OPEN" GH_COMMENTS="" GH_FAIL=""

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
[ -n "$GH_FAIL" ] && { echo "boom" >&2; exit 1; }
case "$1 $2" in
  "api user") printf '%s\n' "$GH_ME" ;;
  "pr view") printf '%s\n' "$GH_VIEW" ;;
  "pr comment")
    while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$GH_LOG.body"; shift; done
    echo "https://github.com/o/r/pull/7#issuecomment-111" ;;
  "api -X")
    while [ $# -gt 0 ]; do case "$1" in body=@*) cp "${1#body=@}" "$GH_LOG.body" ;; esac; shift; done
    echo "https://github.com/o/r/pull/7#issuecomment-222" ;;
  "api repos/o/r/issues/7/comments") printf '%s\n' "$GH_COMMENTS" ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

URL="https://github.com/o/r/pull/7"
REV="$ROOT/review.md"
printf '# Executor review\n\n**Verdict:** ok\n' > "$REV"
cfg(){ mkdir -p "$EOW_HOME/executor"; printf '%s\n' "$@" > "$EOW_HOME/executor/config.md"; }
run(){ : > "$GH_LOG"; rm -f "$GH_LOG.body"; bash "$POST" "$URL" "${1:-$REV}" 2>&1; echo "exit=$?"; }
gh_never(){ if [ ! -s "$GH_LOG" ]; then ok "$1"; else bad "$1" "$(cat "$GH_LOG")"; fi; }

echo "review-post.sh spec tests"

rm -f "$EOW_HOME/executor/config.md"
out=$(run)
check "setting missing: saved" "SAVED: $REV" "$out"
refute "setting missing: not posted" "POSTED" "$out"
gh_never "setting missing: gh never called"

cfg "## Reviews" "Post: off"
out=$(run)
check "off: saved" "SAVED: $REV" "$out"
refute "off: not posted" "POSTED" "$out"
gh_never "off: gh never called"

cfg "# Executor settings" "" "## Roots" "- ~/code"
out=$(run)
check "no Reviews section: saved only" "SAVED: $REV" "$out"
refute "no Reviews section: not posted" "POSTED" "$out"

cfg "## Reviews" "Post: own PRs"
GH_COMMENTS=""; out=$(run)
check "own PR: posted" "POSTED: https://github.com/o/r/pull/7#issuecomment-111" "$out"
check "own PR: saved" "SAVED: $REV" "$out"
check "own PR: exit 0" "exit=0" "$out"
body=$(cat "$GH_LOG.body" 2>/dev/null)
check "own PR: header" '**Executor review** · by Claude, posted from this account' "$body"
check "own PR: marker" '<!-- executor-review -->' "$body"
check "own PR: review text" '**Verdict:** ok' "$body"
check "own PR: used gh pr comment --body-file" "pr comment $URL --body-file" "$(cat "$GH_LOG")"

GH_COMMENTS="555"; out=$(run)
check "marker comment exists: edited" "POSTED: https://github.com/o/r/pull/7#issuecomment-222" "$out"
check "marker comment exists: PATCH on its id" "-X PATCH repos/o/r/issues/comments/555" "$(cat "$GH_LOG")"
refute "marker comment exists: no new comment" "pr comment" "$(cat "$GH_LOG")"
check "marker comment exists: body keeps marker" '<!-- executor-review -->' "$(cat "$GH_LOG.body")"
GH_COMMENTS=""

GH_VIEW="someone OPEN"; out=$(run)
check "someone else's PR: saved" "SAVED: $REV" "$out"
check "someone else's PR: note" "NOTE: not posted, not your PR" "$out"
refute "someone else's PR: not posted" "POSTED" "$out"
refute "someone else's PR: no comment call" "comment" "$(cat "$GH_LOG")"
GH_VIEW="me OPEN"

GH_VIEW="me CLOSED"; out=$(run)
check "closed PR: STOP" "STOP:" "$out"
check "closed PR: still saved" "SAVED: $REV" "$out"
refute "closed PR: not posted" "POSTED" "$out"
GH_VIEW="me OPEN"

GH_FAIL=1; out=$(run)
check "gh failure: STOP" "STOP:" "$out"
check "gh failure: SAVED" "SAVED: $REV" "$out"
check "gh failure: exit 0" "exit=0" "$out"
GH_FAIL=""

out=$(run "$ROOT/nope.md")
check "missing file: STOP" "STOP:" "$out"
refute "missing file: no SAVED" "SAVED:" "$out"
check "missing file: exit 0" "exit=0" "$out"

printf '# Executor review\n\n### Critical (0)\n\nNone.\n\n### Suggestions (0)\n\nNone.\n' > "$ROOT/empty.md"
out=$(run "$ROOT/empty.md")
check "empty review: still posted" "POSTED:" "$out"
check "empty review: body has the summary" "None." "$(cat "$GH_LOG.body")"

out=$(bash "$POST" "not a url" "$REV" 2>&1)
check "bad PR url: STOP" "STOP:" "$out"
check "bad PR url: SAVED" "SAVED: $REV" "$out"

cfg "## Reviews" "Post: off"
: > "$GH_LOG"; out=$(bash "$POST" --on "$URL" "$REV" 2>&1)
check "--on with the setting off: posted" "POSTED:" "$out"
GH_VIEW="someone OPEN"; out=$(bash "$POST" --on "$URL" "$REV" 2>&1)
check "--on on someone else's PR: still not posted" "NOTE: not posted, not your PR" "$out"
GH_VIEW="me OPEN"

echo "review-post.sh --path"
p=$(bash "$POST" --path pr "$URL")
if [ "$p" = "$EOW_HOME/executor/reviews/o/r/PR-7.md" ]; then ok "path: a PR"; else bad "path: a PR" "$p"; fi
if [ -d "$EOW_HOME/executor/reviews/o/r" ]; then ok "path: folder created"; else bad "path: folder created" "missing"; fi
p=$(env -u EOW_HOME HOME="$ROOT/home" bash "$POST" --path pr "$URL")
if [ "$p" = "$ROOT/home/.engineer-of-wealth/executor/reviews/o/r/PR-7.md" ]; then ok "path: EOW_HOME unset"; else bad "path: EOW_HOME unset" "$p"; fi

WORK="$ROOT/withremote"; git init -q -b main "$WORK"
git -C "$WORK" remote add origin git@github.com:acme/widgets.git
p=$(cd "$WORK" && bash "$POST" --path branch feat/x)
if [ "$p" = "$EOW_HOME/executor/reviews/acme/widgets/feat-x.md" ]; then ok "path: branch with remote"; else bad "path: branch with remote" "$p"; fi
p=$(cd "$WORK" && bash "$POST" --path branch)
if [ "$p" = "$EOW_HOME/executor/reviews/acme/widgets/main.md" ]; then ok "path: branch defaults to HEAD"; else bad "path: branch defaults to HEAD" "$p"; fi

NOREM="$ROOT/lonely"; git init -q -b main "$NOREM"
p=$(cd "$NOREM" && bash "$POST" --path branch topic)
if [ "$p" = "$EOW_HOME/executor/reviews/local/lonely/topic.md" ]; then ok "path: no remote goes to local/"; else bad "path: no remote goes to local/" "$p"; fi

echo "docs"
REPO=$(cd -P "$SELF_DIR/.." && pwd)
INIT=$(cat "$REPO/references/init.md")
FORMAT=$(cat "$REPO/references/review-format.md")
SKILLDOC=$(cat "$REPO/skills/review/SKILL.md" "$REPO/references/review-steps.md")
AUDIT=$(cat "$REPO/scripts/self-audit.sh")
check "init: E7 asks about posting" "## E7: Review comments" "$INIT"
check "init: E7 writes ## Reviews" '## Reviews' "$INIT"
check "init: E7 says whose account" "labelled as an Executor review by Claude" "$INIT"
check "self-audit: knows ## Reviews" '## Reviews' "$AUDIT"
check "review-format: where the file lives" 'executor/reviews/<owner>/<repo>/PR-<n>.md' "$FORMAT"
check "review skill: posts only through review-post.sh" 'only through `review-post.sh`' "$SKILLDOC"
refute "review skill: the old sentence is gone" 'unless the user asks' "$SKILLDOC"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
