#!/usr/bin/env bash
# Spec tests for the PostToolUse hooks after `gh stack submit` and `gh stack link`:
# they act on the PR whose URL gh stack printed, whatever folder the session is in,
# and they never delay a session. No network: stub `gh`, plus `git`, `ssh` and `jq`
# that record their calls, and HOME in a temporary folder.
#
# Run: bash scripts/stack-hooks.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
ASSIGN="$SELF_DIR/assign-author.sh"
REVIEW="$SELF_DIR/review-new-pr.sh"
NEW_PRS="$SELF_DIR/new-prs.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()    { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "must not hold: $2 | got: $3" ;; *) ok "$1" ;; esac; }

ROOT=$(mktemp -d)
ROOT=$(cd -P "$ROOT" && pwd)
trap 'rm -rf "$ROOT"' EXIT
BIN="$ROOT/bin"; mkdir -p "$BIN"
REAL_GIT=$(command -v git)
REAL_JQ=$(command -v jq)
REAL_PATH=$PATH
export HEADS="$ROOT/heads"; : > "$HEADS"
export REAL_GIT REAL_JQ

# `gh pr view <url>` answers from $HEADS ("<url> <branch>" lines), or fails.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  "pr view")
    head=$(grep -F "$3 " "$HEADS" | head -1 | cut -d' ' -f2-)
    [ -n "$head" ] || { echo "gh: no pull requests found" >&2; exit 1; }
    case "$*" in
      *--jq*) printf '%s\n' "$head" ;;
      *) printf '{"headRefName":"%s"}\n' "$head" ;;
    esac
    ;;
esac
exit 0
STUB

cat > "$BIN/git" <<'STUB'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$TOOLS"
exec "$REAL_GIT" "$@"
STUB

cat > "$BIN/ssh" <<'STUB'
#!/usr/bin/env bash
printf 'ssh %s\n' "$*" >> "$TOOLS"
exit 1
STUB

cat > "$BIN/jq" <<'STUB'
#!/usr/bin/env bash
printf 'jq %s\n' "$*" >> "$TOOLS"
exec "$REAL_JQ" "$@"
STUB
chmod +x "$BIN"/*

# A PATH holding every tool the hooks use, but no jq.
NOJQ="$ROOT/nojq"; mkdir -p "$NOJQ"
for t in bash cat cut date dirname grep head mkdir mktemp nohup rm sed tail awk; do
  ln -s "$(command -v "$t")" "$NOJQ/$t"
done
for t in gh git ssh; do ln -s "$BIN/$t" "$NOJQ/$t"; done
export PATH="$BIN:$REAL_PATH"

head_of(){ printf '%s %s\n' "$1" "$2" >> "$HEADS"; }

# Each run gets its own call files and HOME: a detached run can't leak into the next.
RUN=0
fresh(){
  RUN=$((RUN+1))
  export CALLS="$ROOT/calls.$RUN" TOOLS="$ROOT/tools.$RUN" HOME="$ROOT/home.$RUN"
  mkdir -p "$HOME"
  LOG="$HOME/.engineer-of-wealth/executor/assign.log"
  : > "$CALLS"; : > "$TOOLS"
}

# event <command> <stdout> <cwd>
event(){
  "$REAL_JQ" -nc --arg c "$1" --arg o "$2" --arg d "$3" \
    '{tool_name:"Bash",tool_input:{command:$c},tool_response:{stdout:$o,stderr:"",interrupted:false},cwd:$d}'
}

assign(){ event "$1" "$2" "$3" | bash "$ASSIGN"; }
review(){ event "$1" "$2" "$3" | bash "$REVIEW"; }
context(){ printf '%s' "$1" | "$REAL_JQ" -r '.hookSpecificOutput.additionalContext'; }

# Bounded poll: assign-author.sh detaches, so wait for what it leaves behind.
wait_lines(){
  local i=0
  while [ "$i" -lt 200 ]; do
    [ -f "$1" ] && [ "$(grep -c -- "$2" "$1")" -ge "$3" ] && return 0
    sleep 0.05; i=$((i+1))
  done
  return 1
}
edits(){ grep '^pr edit' "$CALLS" | paste -sd '|' -; }
log_lines(){ if [ -f "$LOG" ]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }

# What new-prs.sh sets, for one event: kind, then the PRs, then the branches.
probe(){
  event "$1" "$2" "$3" | bash -c '. "$1"; printf "%s\n" "$kind|$(printf "%s" "$prs" | paste -sd , -)|$(printf "%s" "${branches:-}" | paste -sd , -)"' probe "$NEW_PRS"
}
prs_of(){ probe "$@" | cut -d'|' -f2; }

# probe, with a limit: a command the hook can't get past must fail here, not hang.
within_limit(){
  local out="$ROOT/bounded.$$" i=0 pid
  : > "$out"
  probe "$@" > "$out" 2>/dev/null &
  pid=$!
  while [ "$i" -lt 60 ] && kill -0 "$pid" 2>/dev/null; do sleep 0.05; i=$((i+1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null; pkill -P "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    printf 'HUNG'
    return
  fi
  wait "$pid" 2>/dev/null
  cat "$out"
}

URL=https://github.com/acme/b/pull/27
URL_OTHER=https://github.com/acme/a/pull/27
head_of "$URL" feat-a
head_of "$URL_OTHER" other-branch
REAL="Checking stack state...
Pushing to origin...
✓ Created PR #27 ($URL) for feat-a
✓ Pushed and synced 1 branches"
BARE="Created PR #27 for feat-a"
LOG_SHAPE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}  .+  .+  .+$'

# A session folder that is a repo with a PR of that number, and one that is no repo.
REPO_A="$ROOT/a"; mkdir -p "$REPO_A"; "$REAL_GIT" -C "$REPO_A" init -q
"$REAL_GIT" -C "$REPO_A" remote add origin https://github.com/acme/a.git
NOREPO="$ROOT/not a repo"; mkdir -p "$NOREPO"

echo "stack hooks spec tests"

# The session's folder is not a repo: the printed URL is assigned, head read first.
fresh
assign 'cd "/some/where else" && gh stack submit --auto' "$REAL" "$NOREPO"
wait_lines "$CALLS" '^pr edit' 1
is "not a repo: the printed URL is assigned" "pr edit $URL --add-assignee @me" "$(edits)"
check "not a repo: head branch read first" "pr view $URL --json headRefName" "$(head -1 "$CALLS")"
is "not a repo: nothing logged" "0" "$(log_lines)"

# The session is in another repo with a PR of that number: that one is never touched.
fresh
assign "cd /elsewhere && gh stack submit --auto" "$REAL" "$REPO_A"
wait_lines "$CALLS" '^pr edit' 1
is "other repo: the printed PR is assigned" "pr edit $URL --add-assignee @me" "$(edits)"
refute "other repo: the session's repo is never touched" "acme/a/" "$(cat "$CALLS")"

# No cd, a cd in a variable or a cd that doesn't exist: the folder no longer matters.
is "no cd"              "$URL" "$(prs_of "gh stack submit" "$REAL" "$REPO_A")"
is "cd to a variable"   "$URL" "$(prs_of 'cd "$REPO" && gh stack submit' "$REAL" "$REPO_A")"
is "cd to a missing folder" "$URL" "$(prs_of "cd /no/such/folder && gh stack submit" "$REAL" "$REPO_A")"
is "cd ~"               "$URL" "$(prs_of "cd ~/code && gh stack submit" "$REAL" "$REPO_A")"
is "--remote"           "$URL" "$(prs_of "gh stack submit --remote upstream" "$REAL" "$REPO_A")"
is "gh stack link"      "$URL" "$(prs_of "gh stack link a b" "$REAL" "$REPO_A")"

# Every form that really runs gh stack counts. These were dropped with no log line.
is "captured in \$(...)" "$URL" "$(prs_of 'out=$(gh stack submit --auto 2>&1); echo "$out"' "$REAL" "$REPO_A")"
is "echoed from \$(...)" "$URL" "$(prs_of 'echo "$(gh stack submit --auto 2>&1)"' "$REAL" "$REPO_A")"
is "under eval"          "$URL" "$(prs_of 'eval "gh stack submit --auto"' "$REAL" "$REPO_A")"
is "in backticks"        "$URL" "$(prs_of 'x=`gh stack submit --auto`; echo "$x"' "$REAL" "$REPO_A")"
is "under bash -c"       "$URL" "$(prs_of "bash -c 'gh stack submit'" "$REAL" "$REPO_A")"
is "under bash -lc, cd first" "$URL" "$(prs_of "bash -lc 'cd /x && gh stack submit'" "$REAL" "$REPO_A")"
is "in a subshell"       "$URL" "$(prs_of "(cd /x && gh stack submit)" "$REAL" "$REPO_A")"
is "in a pipe"           "$URL" "$(prs_of "gh stack submit --auto 2>&1 | tail -5" "$REAL" "$REPO_A")"
is "under if !"          "$URL" "$(prs_of "if ! gh stack submit; then echo no; fi" "$REAL" "$REPO_A")"
is "with a variable set" "$URL" "$(prs_of "GH_TOKEN=x gh stack submit" "$REAL" "$REPO_A")"
is "gh by absolute path" "$URL" "$(prs_of "/opt/homebrew/bin/gh stack submit --auto" "$REAL" "$REPO_A")"
is "gh by relative path" "$URL" "$(prs_of "./gh stack submit --auto" "$REAL" "$REPO_A")"
is "gh by home path"     "$URL" "$(prs_of "cd /x && ~/bin/gh stack link a b" "$REAL" "$REPO_A")"
is "gh by path, under eval" "$URL" "$(prs_of 'eval "/opt/homebrew/bin/gh stack submit"' "$REAL" "$REPO_A")"
is "gh by path, in \$(...)" "$URL" "$(prs_of 'out=$(/opt/homebrew/bin/gh stack submit --auto 2>&1); echo "$out"' "$REAL" "$REPO_A")"
is "after a here-document" "$URL" "$(prs_of "cat <<EOF
it's :)
EOF
gh stack submit" "$REAL" "$REPO_A")"
fresh
assign 'out=$(gh stack submit --auto 2>&1); echo "$out"' "$REAL" "$REPO_A"
wait_lines "$CALLS" '^pr edit' 1
is "captured in \$(...): assigned" "pr edit $URL --add-assignee @me" "$(edits)"
fresh
ctx=$(context "$(review 'out=$(gh stack submit --auto 2>&1); echo "$out"' "$REAL" "$REPO_A")")
check "captured in \$(...): reviewed" "$URL (head branch: feat-a)" "$ctx"

# No character in a command can hang the hook.
is "a carriage return" "stack|$URL|feat-a" "$(within_limit $'cd /x\r\ngh stack submit' "$REAL" "$REPO_A")"
is "a carriage return on the line" "stack|$URL|feat-a" "$(within_limit $'cd /x \r&& gh stack submit' "$REAL" "$REPO_A")"
is "a form feed" "stack|$URL|feat-a" "$(within_limit $'cd /x\f&& gh stack submit' "$REAL" "$REPO_A")"
is "a vertical tab" "stack|$URL|feat-a" "$(within_limit $'cd /x\v&& gh stack submit' "$REAL" "$REPO_A")"
is "unbalanced quotes" "stack|$URL|feat-a" "$(within_limit "echo 'it; gh stack submit \"\$(\`" "$REAL" "$REPO_A")"
BIGMSG=$(printf 'fix the thing in the place, (it is long) and "quoted"\n%.0s' $(seq 1 2000))
is "a 100 KB command" "stack|$URL|feat-a" "$(within_limit "git commit -m \"$BIGMSG\" && gh stack submit" "$REAL" "$REPO_A")"

# The head branch doesn't match: nothing assigned, one log line.
fresh
assign "gh stack submit --auto" "Created PR #27 ($URL_OTHER) for feat-a" "$NOREPO"
wait_lines "$LOG" . 1
is "mismatch: nothing assigned" "" "$(edits)"
is "mismatch: one log line" "1" "$(log_lines)"
check "mismatch: names the PR" "$URL_OTHER" "$(cat "$LOG")"
grep -qE "$LOG_SHAPE" "$LOG" && ok "mismatch: the log line keeps its format" || bad "mismatch: the log line keeps its format" "$(cat "$LOG")"

# The lookup fails: the same.
fresh
assign "gh stack submit --auto" "Created PR #27 (https://github.com/acme/unseen/pull/27) for feat-a" "$NOREPO"
wait_lines "$LOG" . 1
is "lookup fails: nothing assigned" "" "$(edits)"
is "lookup fails: one log line" "1" "$(log_lines)"
check "lookup fails: logs gh's reason" "no pull requests found" "$(cat "$LOG")"

# No URL printed: the repo is unknown, even when the session's folder holds that number.
fresh
assign "gh stack submit --auto" "$BARE" "$REPO_A"
wait_lines "$LOG" . 1
is "no URL: gh pr edit never called" "" "$(edits)"
is "no URL: one log line" "1" "$(log_lines)"
grep -qE "$LOG_SHAPE" "$LOG" && ok "no URL: the log line keeps its format" || bad "no URL: the log line keeps its format" "$(cat "$LOG")"
refute "no URL: no gh call on a bare number" "27" "$(cat "$CALLS")"
is "no URL: no git or ssh" "" "$(grep -E '^(git|ssh) ' "$TOOLS")"
fresh
ctx=$(context "$(review "gh stack submit --auto" "$BARE" "$REPO_A")")
check "no URL: the review context says so" "repo could not be identified" "$ctx"
check "no URL: gives the number" "#27" "$ctx"
check "no URL: gives the branch" "feat-a" "$ctx"
check "no URL: not from the current folder" "not resolve" "$ctx"

# The (base: ...) suffix gh stack link prints is not part of the branch.
BASED="Created PR #27 ($URL) for feat-a (base: main)"
is "base suffix: branch parsed without it" "stack|$URL|feat-a" "$(probe "gh stack link a" "$BASED" "$REPO_A")"
is "base suffix, no URL" "stack|27|feat-a" "$(probe "gh stack link a" "Created PR #27 for feat-a (base: main)" "$REPO_A")"
fresh
assign "gh stack link a" "$BASED" "$REPO_A"
wait_lines "$CALLS" '^pr edit' 1
is "base suffix: the branch check passes" "pr edit $URL --add-assignee @me" "$(edits)"

# Only a URL that really is this PR's counts.
GHE=https://ghe.example.com/o/r/pull/5
is "an enterprise host" "stack|$GHE|x" "$(probe "gh stack submit" "Created PR #5 ($GHE) for x" "$NOREPO")"
is "another PR's number: unknown" "stack|27|x" "$(probe "gh stack submit" "Created PR #27 (https://github.com/o/r/pull/99) for x" "$NOREPO")"
is "not https: unknown" "stack|27|x" "$(probe "gh stack submit" "Created PR #27 (http://github.com/o/r/pull/27) for x" "$NOREPO")"
is "not a PR URL: unknown" "stack|27|x" "$(probe "gh stack submit" "Created PR #27 (https://github.com/o/r/issues/27) for x" "$NOREPO")"
is "an option as a host: unknown" "stack|27|x" "$(probe "gh stack submit" "Created PR #27 (--repo=o/r/pull/27) for x" "$NOREPO")"
is "a quote in the owner: unknown" 'stack|27|x' "$(probe "gh stack submit" 'Created PR #27 (https://github.com/o"o/r/pull/27) for x' "$NOREPO")"
is "an escaped slash in the JSON" "stack|$URL|feat-a" \
  "$(printf '{"tool_name":"Bash","tool_input":{"command":"gh stack submit"},"tool_response":{"stdout":"Created PR #27 (https:\\/\\/github.com\\/acme\\/b\\/pull\\/27) for feat-a"},"cwd":"/x"}' | bash -c '. "$1"; printf "%s\n" "$kind|$prs|$branches"' probe "$NEW_PRS")"

# Odd branch names: the review's output stays valid JSON.
ODD='we"ird\name'
fresh
out=$(review "gh stack submit" "Created PR #27 ($URL) for $ODD" "$NOREPO")
is "odd branch: output parses" "PostToolUse" "$(printf '%s' "$out" | "$REAL_JQ" -r '.hookSpecificOutput.hookEventName')"
check "odd branch: named exactly" "$ODD" "$(context "$out")"
is "odd branch: parsed exactly" "stack|$URL|$ODD" "$(probe "gh stack submit" "Created PR #27 ($URL) for $ODD" "$NOREPO")"
out=$(review "gh stack submit" "Created PR #27 for $ODD" "$NOREPO")
check "odd branch, no URL: output parses" "$ODD" "$(context "$out")"
out=$(review "gh stack submit" $'Created PR #27 for feat\001x' "$NOREPO")
is "a control character: output parses" "PostToolUse" "$(printf '%s' "$out" | "$REAL_JQ" -r '.hookSpecificOutput.hookEventName')"

# A stack: bottom first, a repeated line is one PR, and one bad URL says so.
S1=https://github.com/acme/b/pull/52
S2=https://github.com/acme/b/pull/51
STACK="Created PR #52 ($S1) for bottom
Created PR #51 ($S2) for top
Created PR #52 ($S1) for bottom"
fresh
ctx=$(context "$(review "gh stack submit" "$STACK" "$NOREPO")")
check "URLs with branches, bottom first" "$S1 (head branch: bottom), $S2 (head branch: top)" "$ctx"
check "tells the review to compare" "check each PR's head branch" "$ctx"
check "tells the review to stop on a mismatch" "stop and say so" "$ctx"
is "a repeated line is one PR" 1 "$(printf '%s' "$ctx" | grep -o 'pull/52' | wc -l | tr -d ' ')"
is "review hook: no gh at all" "" "$(cat "$CALLS")"
is "a stack: no git or ssh" "" "$(grep -E '^(git|ssh) ' "$TOOLS")"
fresh
ctx=$(context "$(review "gh stack submit" "Created PR #52 ($S1) for bottom
Created PR #51 for top" "$NOREPO")")
check "one PR with no URL: the review is told" "repo could not be identified" "$ctx"
check "one PR with no URL: lists it by number" "#51 (head branch: top)" "$ctx"
fresh
assign "gh stack submit" "Created PR #52 ($S1) for bottom
Created PR #51 ($S2) for top" "$NOREPO"
wait_lines "$LOG" . 2
is "a stack, no head matches: one log line each" 2 "$(log_lines)"
is "a stack, assign hook: no git or ssh" "" "$(grep -E '^(git|ssh) ' "$TOOLS")"

# With no jq at all.
nojq_review(){ event "$1" "$2" "$3" | PATH="$NOJQ" "$NOJQ/bash" "$REVIEW"; }
nojq_probe(){
  event "$1" "$2" "$3" | PATH="$NOJQ" "$NOJQ/bash" -c '. "$1"; printf "%s\n" "$kind|$prs|${branches:-}"' probe "$NEW_PRS"
}
fresh
out=$(nojq_review "gh stack submit" "Created PR #27 ($URL) for $ODD" "$NOREPO")
check "no jq: odd branch still parses" "$ODD" "$(context "$out")"
check "no jq: lists the URL" "$URL" "$(context "$out")"
is "no jq: the printed URL" "stack|$URL|feat-a" "$(nojq_probe "cd /x && gh stack submit" "$REAL" "$REPO_A")"
is "no jq: base suffix dropped" "stack|$URL|feat-a" "$(nojq_probe "gh stack submit" "$BASED" "$REPO_A")"
is "no jq: no URL is unknown" "stack|27|feat-a" "$(nojq_probe "gh stack submit" "$BARE" "$REPO_A")"
is "no jq: under eval" "stack|$URL|feat-a" "$(nojq_probe 'eval "gh stack submit"' "$REAL" "$REPO_A")"
is "no jq: gh by path" "stack|$URL|feat-a" "$(nojq_probe "/opt/homebrew/bin/gh stack submit" "$REAL" "$REPO_A")"
is "no jq: gh pr create keeps its URL" "pr|https://github.com/acme/a/pull/9|" \
  "$(nojq_probe "gh pr create --fill" "https://github.com/acme/a/pull/9" "$REPO_A")"
fresh
event "gh stack submit" "$REAL" "$NOREPO" | PATH="$NOJQ" "$NOJQ/bash" "$ASSIGN"
wait_lines "$CALLS" '^pr edit' 1
is "no jq: assigned by URL" "pr edit $URL --add-assignee @me" "$(edits)"

# gh pr create: its URL, assigned directly, with no lookup.
PR_URL=https://github.com/acme/a/pull/9
is "gh pr create: prs is its URL" "pr|$PR_URL|" "$(probe "gh pr create --fill" "$PR_URL" "$NOREPO")"
fresh
assign "gh pr create --fill" "$PR_URL" "$NOREPO"
wait_lines "$CALLS" '^pr edit' 1
is "gh pr create: assigned by URL" "pr edit $PR_URL --add-assignee @me" "$(edits)"
refute "gh pr create: no lookup" "pr view" "$(cat "$CALLS")"
is "gh pr create: no git or ssh" "" "$(grep -E '^(git|ssh) ' "$TOOLS")"
fresh
out=$(review "gh pr create --fill" "$PR_URL" "$NOREPO")
check "gh pr create: the review context names it" "$PR_URL" "$(context "$out")"

# An unrelated Bash command: no git, jq or ssh, and nothing printed.
fresh
out=$(assign "ls -la" "total 0" "$REPO_A"; review "ls -la" "total 0" "$REPO_A")
is "unrelated command: prints nothing" "" "$out"
# event() itself runs the real jq, so TOOLS only records the hooks' own calls.
is "unrelated command: no git, jq or ssh" "" "$(cat "$TOOLS")"

# A command or output that merely mentions gh stack acts on nothing.
mention(){
  fresh
  assign "$1" "$2" "$REPO_A" >/dev/null
  out=$(review "$1" "$2" "$REPO_A")
  is "$3: prints nothing" "" "$out"
  is "$3: no git or ssh" "" "$(grep -E '^(git|ssh) ' "$TOOLS")"
  is "$3: no gh" "" "$(cat "$CALLS")"
}
mention 'grep "gh stack submit" README.md' "README.md: run gh stack submit --auto" "a grep"
is "a grep: no jq either" "" "$(cat "$TOOLS")"
mention 'cat references/stacks.md' "Run gh stack submit --auto to open PRs." "a doc read"
is "a doc read: no jq either" "" "$(cat "$TOOLS")"
mention 'gh stack submit --auto' "All branches up to date; no PR created" "a submit that creates no PR"
is "a submit that creates no PR: no jq either" "" "$(cat "$TOOLS")"
mention 'grep "gh stack submit" notes' "$REAL" "a grep that also hits a Created PR line"
mention "grep 'gh stack submit' notes" "$REAL" "a single-quoted grep that hits one"
mention 'grep "/x/gh stack submit" notes' "$REAL" "a grep for a path that hits one"
mention "grep '/x/gh stack submit' notes" "$REAL" "a single-quoted grep for a path"
mention 'cat notes' "gh stack submit printed: Created PR #27 ($URL) for feat-a" "a doc that quotes the output"
mention 'grep "gh stack submit" notes' "see https://github.com/o/r/pull/3" "a grep that hits a PR URL"
fresh
event 'grep "gh stack submit" notes' "$REAL" "$REPO_A" | PATH="$NOJQ" "$NOJQ/bash" "$REVIEW" >/dev/null
is "no jq, a grep: no git or ssh" "" "$(cat "$TOOLS")"

# The second fast check and the locale: real PR creation is untouched.
locale_probe(){
  printf '%s' "$1" | env "${@:2}" bash -c '. "$1"; printf "%s" "${LC_ALL-unset}"' probe "$NEW_PRS"
}
PR_EVENT=$(event "gh pr create --fill" "$PR_URL" "$NOREPO")
is "locale: an LC_ALL is restored" "en_US.UTF-8" "$(locale_probe "$PR_EVENT" LC_ALL=en_US.UTF-8)"
is "locale: no LC_ALL stays unset" "unset" "$(locale_probe "$PR_EVENT" -u LC_ALL)"

# No fixed wait or retry in a hook, and nothing left of the local lookup.
refute "new-prs.sh: no sleep"       "sleep" "$(cat "$NEW_PRS")"
refute "assign-author.sh: no sleep" "sleep" "$(cat "$ASSIGN")"
refute "review-new-pr.sh: no sleep" "sleep" "$(cat "$REVIEW")"
refute "new-prs.sh: runs no git"    "git -C" "$(cat "$NEW_PRS")"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
