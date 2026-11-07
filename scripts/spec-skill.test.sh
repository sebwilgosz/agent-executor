#!/usr/bin/env bash
# Spec tests for /executor:spec: a skill that drafts a spec from every relevant
# source and saves it to the spec home after a yes. Its behaviour is the
# model's, so the tests hold what makes it right to the text the model reads:
# the skill, the shape of a spec, the wiring that makes it discoverable and the
# self-audit that notices a missing piece. No network.
#
# Run: bash scripts/spec-skill.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)
cd "$REPO" || exit 1

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2" ;; *) ok "$1" ;; esac; }

SKILL=$(cat skills/spec/SKILL.md 2>/dev/null)
SHAPE=$(cat references/spec.md 2>/dev/null)
HELP=$(cat skills/help/SKILL.md)
README=$(cat README.md)
BUILD=$(cat skills/build/SKILL.md)

echo "spec skill spec tests"

# 1. The skill: how it is reached.
check "skill: named spec" "name: spec" "$SKILL"
check "skill: an Executor skill" "Executor:" "$(sed -n 3p skills/spec/SKILL.md)"
check "skill: reached by plain words" "write a spec for" "$(sed -n 3p skills/spec/SKILL.md)"
check "skill: reached by notes" "from my notes" "$(sed -n 3p skills/spec/SKILL.md)"
refute "skill: Claude may start it" "disable-model-invocation" "$SKILL"

# 2. The skill: where it looks, in order.
check "reads the shape" "references/spec.md" "$SKILL"
check "reads the spec home rule" "references/spec-home.md" "$SKILL"
check "resolves the home with the script" "scripts/spec-home.sh" "$SKILL"
src=$(printf '%s\n' "$SKILL" | awk '/^## Sources/{f=1;next} /^## /{f=0} f')
l1=$(printf '%s\n' "$src" | grep -E '^1\. '); l2=$(printf '%s\n' "$src" | grep -E '^2\. ')
l3=$(printf '%s\n' "$src" | grep -E '^3\. '); l4=$(printf '%s\n' "$src" | grep -E '^4\. ')
check "source 1: what the user passes" "passes" "$l1"
check "source 2: the instruction files" "instruction files" "$l2"
check "source 3: the spec home" "spec home" "$l3"
check "source 4: the repo" "README" "$l4"
for w in "CHANGELOG.md" "git log" "open issues and PRs" "an earlier plan"; do check "repo source: $w" "$w" "$SKILL"; done
check "an existing spec is updated, never duplicated" "never duplicated" "$SKILL"

# 3. The rules that keep a draft honest.
check "every fact names its source" "names its source" "$SKILL"
check "inferred is an open question" "inferred" "$SKILL"
check "disagreement: code and changelog for state, notes for intent" "the code and the CHANGELOG" "$SKILL"
check "open points in one message with suggested answers" "one message" "$SKILL"
check "nothing saved before a yes" "after a yes" "$SKILL"
check "secrets never in a spec" "Secrets never" "$SKILL"
check "a spec headed for GitHub is clean" "no local paths" "$SKILL"
check "unread sources are listed, never guessed" "unread" "$SKILL"
check "already built is reported as done" "reported as done" "$SKILL"
check "nothing found: the spec check's questions" "spec check" "$SKILL"
check "it never builds" "never builds" "$SKILL"
check "a missing tool stops before drafting" "stop before drafting" "$SKILL"
check "public GitHub issue: say so before writing" "public" "$SKILL"

# 4. Saving: each kind of home has a way.
for k in "folder" "Notion" "GitHub" "Linear" "Jira" "repo"; do check "saves to a $k home" "$k" "$SKILL"; done
check "a folder spec is named <Name> - spec.md" "<Name> - spec.md" "$SKILL"

# 5. The shape of a spec.
for h in "Why" "Decisions already made" "Current state" "Feature" "Stacks" "Not for build"; do
  check "shape: $h" "$h" "$SHAPE"
done
for f in "What it does" "Inputs and outputs" "Edge cases" "Out of scope" "Done when"; do
  check "shape: each feature has $f" "$f" "$SHAPE"
done
check "shape: foundation then independent stacks" "foundation" "$SHAPE"
check "shape: passes the build spec check" "references/implementation.md" "$SHAPE"
check "shape: facts carry their source" "source" "$SHAPE"

# 6. Wiring: discoverable, listed, routed, checked.
check "help: lists the command" "/executor:spec" "$HELP"
check "help: routes plain words" "write a spec" "$HELP"
check "README: in the table" "/executor:spec" "$README"
check "build: offers the spec skill when it finds no spec" "/executor:spec" "$BUILD"

# 7. The self-audit notices a missing piece.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/usr/bin/env bash\ncase "$1 $2" in "--version ") echo "gh version 2.99.0 (x)";; "extension list") echo "gh stack github/gh-stack v1";; esac\nexit 0\n' > "$BIN/gh"; chmod +x "$BIN/gh"
export PATH="$BIN:$PATH" HOME="$TMP/home" EOW_HOME="$TMP/eow"; mkdir -p "$HOME"
PLUG="$TMP/plugin"; mkdir -p "$PLUG"
for d in .claude-plugin agents hooks references scripts skills; do cp -R "$REPO/$d" "$PLUG/"; done
out=$(ROOT="$PLUG" bash "$REPO/scripts/self-audit.sh")
refute "audit: whole plugin has no spec error" "spec.md missing" "$out"
refute "audit: whole plugin has no spec warning" "skill spec exists but" "$out"
rm -f "$PLUG/references/spec.md"
out=$(ROOT="$PLUG" bash "$REPO/scripts/self-audit.sh")
check "audit: missing shape is an error" "✗ integrity: references/spec.md missing" "$out"
cp "$REPO/references/spec.md" "$PLUG/references/"
rm -f "$PLUG/references/spec-home.md"
out=$(ROOT="$PLUG" bash "$REPO/scripts/self-audit.sh")
check "audit: missing spec home rule is an error" "✗ integrity: references/spec-home.md missing" "$out"
cp "$REPO/references/spec-home.md" "$PLUG/references/"
rm -f "$PLUG/skills/spec/SKILL.md"
out=$(ROOT="$PLUG" bash "$REPO/scripts/self-audit.sh")
check "audit: the help routes to a missing skill" "/executor:spec, which does not exist" "$out"

echo
printf 'spec-skill: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
