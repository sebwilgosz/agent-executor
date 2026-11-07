#!/usr/bin/env bash
# Spec tests for the PostToolUse hooks after `gh stack submit` and `gh stack link`:
# they act on the PR's own repo, whatever folder the session is in, and they never
# delay a session. No network: stub `gh` and `ssh` on PATH, a `git` that records its
# calls, real temporary repos with a fake origin, HOME in a temporary folder.
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
REAL_PATH=$PATH
export HEADS="$ROOT/heads"; : > "$HEADS"
export REAL_GIT

# `gh pr view <url>` answers from $HEADS ("<url> <branch>" lines), or fails.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  "pr view")
    echo "A new release of gh is available" >&2
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

# The real ssh -G reads the user's config, not $HOME: an alias maps to the real host.
cat > "$BIN/ssh" <<'STUB'
#!/usr/bin/env bash
printf 'ssh %s\n' "$*" >> "$TOOLS"
[ "$1" = -G ] || exit 1
case "$2" in
  github.com-work) printf 'user git\nhostname github.com\n' ;;
  *) printf 'user git\nhostname %s\n' "$2" ;;
esac
STUB

cat > "$BIN/jq" <<'STUB'
#!/usr/bin/env bash
printf 'jq %s\n' "$*" >> "$TOOLS"
exec "$REAL_JQ" "$@"
STUB
export REAL_JQ; REAL_JQ=$(command -v jq)
chmod +x "$BIN"/*

# A PATH holding every tool the hooks use, but no jq.
NOJQ="$ROOT/nojq"; mkdir -p "$NOJQ"
for t in bash cat cut date dirname grep head mkdir mktemp nohup rm sed awk; do
  ln -s "$(command -v "$t")" "$NOJQ/$t"
done
for t in gh git ssh; do ln -s "$BIN/$t" "$NOJQ/$t"; done
export PATH="$BIN:$REAL_PATH"

mkrepo(){ mkdir -p "$1" && "$REAL_GIT" -C "$1" init -q && "$REAL_GIT" -C "$1" remote add origin "$2"; }
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

SUB="Pushed 1 branch
Created PR #27 for feat-a"
LOG_SHAPE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}  .+  .+  .+$'

echo "stack hooks spec tests"

# Repos used across the tests.
NOREPO="$ROOT/not a repo"; mkdir -p "$NOREPO"
SPACED="$ROOT/my projects/the repo"; mkrepo "$SPACED" https://github.com/acme/spaced.git
URL_S=https://github.com/acme/spaced/pull/27
head_of "$URL_S" feat-a
REPO_A="$ROOT/a"; mkrepo "$REPO_A" https://github.com/acme/a.git
REPO_B="$ROOT/b"; mkrepo "$REPO_B" https://github.com/acme/b.git
URL_A=https://github.com/acme/a/pull/27
URL_B=https://github.com/acme/b/pull/27
head_of "$URL_A" other-branch
head_of "$URL_B" feat-a

# 1. The session's folder is not a repo; the command's cd names one, with a space.
fresh
assign "cd \"$SPACED\" && gh stack submit --auto" "$SUB" "$NOREPO"
wait_lines "$CALLS" '^pr edit' 1
is "cd into a spaced path: its URL is assigned" "pr edit $URL_S --add-assignee @me" "$(edits)"
check "cd into a spaced path: head branch read first" "pr view $URL_S --json headRefName" "$(head -1 "$CALLS")"
is "cd into a spaced path: nothing logged" "0" "$(log_lines)"

# 2. The session is in repo A, which has a PR of that number; the cd names repo B.
fresh
assign "cd $REPO_B && gh stack submit --auto" "$SUB" "$REPO_A"
wait_lines "$CALLS" '^pr edit' 1
is "other repo: B's PR is assigned" "pr edit $URL_B --add-assignee @me" "$(edits)"
refute "other repo: A is never touched" "acme/a/" "$(cat "$CALLS")"

# 3. No cd, the session's folder is the repo: by URL.
fresh
assign "gh stack submit --auto" "$SUB" "$REPO_B"
wait_lines "$CALLS" '^pr edit' 1
is "no cd: the session's repo, by URL" "pr edit $URL_B --add-assignee @me" "$(edits)"

# The forms a cd comes in.
is "subshell cd"      "$URL_B" "$(prs_of "(cd $REPO_B && gh stack submit)" "$SUB" "$REPO_A")"
is "single-quoted cd" "$URL_S" "$(prs_of "cd '$SPACED' && gh stack submit" "$SUB" "$REPO_A")"
is "double-quoted cd" "$URL_S" "$(prs_of "cd \"$SPACED\" && gh stack submit" "$SUB" "$REPO_A")"
is "escaped space"    "$URL_S" "$(prs_of "cd ${SPACED// /\\ } && gh stack submit" "$SUB" "$REPO_A")"
is "last cd wins"     "$URL_B" "$(prs_of "cd $REPO_A && cd $REPO_B && gh stack submit" "$SUB" "$NOREPO")"
is "relative cd"      "$URL_B" "$(prs_of "cd b && gh stack submit" "$SUB" "$ROOT")"
is "a cd after gh stack doesn't count" "$URL_A" "$(prs_of "cd $REPO_A && gh stack submit; cd $REPO_B" "$SUB" "$NOREPO")"
is "a cd in a message doesn't count" "$URL_B" \
  "$(prs_of "git commit -m \"cd $REPO_A\" && gh stack submit" "$SUB" "$REPO_B")"
is "a cd in a command substitution doesn't count" "$URL_B" \
  "$(prs_of "X=\$(cd $REPO_A && pwd) && gh stack submit" "$SUB" "$REPO_B")"
is "gh stack under bash -c" "$URL_B" "$(prs_of "bash -c 'cd $REPO_B && gh stack submit'" "$SUB" "$NOREPO")"
is "gh stack link"    "$URL_B" "$(prs_of "cd $REPO_B && gh stack link" "$SUB" "$REPO_A")"

# --remote names the remote to read.
REMOTES="$ROOT/remotes"; mkrepo "$REMOTES" https://github.com/acme/origin-one.git
"$REAL_GIT" -C "$REMOTES" remote add upstream https://github.com/acme/upstream-one.git
is "--remote <name>" https://github.com/acme/upstream-one/pull/27 \
  "$(prs_of "gh stack submit --remote upstream" "$SUB" "$REMOTES")"
is "--remote=<name>" https://github.com/acme/upstream-one/pull/27 \
  "$(prs_of "gh stack submit --remote=upstream" "$SUB" "$REMOTES")"
is "--remote with no such remote: unknown" 27 "$(prs_of "gh stack submit --remote nope" "$SUB" "$REMOTES")"
is "--remote it can't read: unknown" 27 "$(prs_of "gh stack submit --remote \"\$R\"" "$SUB" "$REMOTES")"

# 4. The head branch doesn't match: nothing assigned, one log line.
fresh
assign "gh stack submit --auto" "$SUB" "$REPO_A"
wait_lines "$LOG" . 1
is "mismatch: nothing assigned" "" "$(edits)"
is "mismatch: one log line" "1" "$(log_lines)"
check "mismatch: names the PR" "$URL_A" "$(cat "$LOG")"
grep -qE "$LOG_SHAPE" "$LOG" && ok "mismatch: the log line keeps its format" || bad "mismatch: the log line keeps its format" "$(cat "$LOG")"

# The lookup fails: the same.
fresh
UNSEEN="$ROOT/unseen"; mkrepo "$UNSEEN" https://github.com/acme/unseen.git
assign "gh stack submit --auto" "$SUB" "$UNSEEN"
wait_lines "$LOG" . 1
is "lookup fails: nothing assigned" "" "$(edits)"
is "lookup fails: one log line" "1" "$(log_lines)"
check "lookup fails: logs gh's reason" "no pull requests found" "$(cat "$LOG")"

# 5. Repo unknown: no gh pr edit, one log line, and the review is told.
fresh
assign "cd \"\$REPO\" && gh stack submit --auto" "$SUB" "$REPO_A"
wait_lines "$LOG" . 1
is "unknown repo: gh pr edit never called" "" "$(edits)"
is "unknown repo: one log line" "1" "$(log_lines)"
grep -qE "$LOG_SHAPE" "$LOG" && ok "unknown repo: the log line keeps its format" || bad "unknown repo: the log line keeps its format" "$(cat "$LOG")"
refute "unknown repo: no gh call on a bare number" "27" "$(cat "$CALLS")"
fresh
ctx=$(context "$(review "cd \"\$REPO\" && gh stack submit --auto" "$SUB" "$REPO_A")")
check "unknown repo: the review context says so" "repo could not be identified" "$ctx"
check "unknown repo: gives the number" "#27" "$ctx"
check "unknown repo: gives the branch" "feat-a" "$ctx"
check "unknown repo: not from the current folder" "not resolve" "$ctx"

is "cd \$VAR beats the session's repo" 27 "$(prs_of "cd \"\$REPO\" && gh stack submit" "$SUB" "$REPO_A")"
is "cd \$(...): unknown"       27 "$(prs_of "cd \"\$(git rev-parse --show-toplevel)\" && gh stack submit" "$SUB" "$REPO_A")"
is "cd a glob: unknown"        27 "$(prs_of "cd rep* && gh stack submit" "$SUB" "$REPO_A")"
is "cd -: unknown"             27 "$(prs_of "cd - && gh stack submit" "$SUB" "$REPO_A")"
is "missing absolute: unknown" 27 "$(prs_of "cd $ROOT/missing && gh stack submit" "$SUB" "$REPO_A")"
is "not a repo: unknown"       27 "$(prs_of "cd \"$NOREPO\" && gh stack submit" "$SUB" "$REPO_A")"
NOORIGIN="$ROOT/no-origin"; mkdir -p "$NOORIGIN"; "$REAL_GIT" -C "$NOORIGIN" init -q
is "no origin: unknown"        27 "$(prs_of "cd $NOORIGIN && gh stack submit" "$SUB" "$REPO_A")"
LOCALR="$ROOT/local-remote"; mkrepo "$LOCALR" /srv/git/thing.git
is "a local-path origin: unknown" 27 "$(prs_of "gh stack submit" "$SUB" "$LOCALR")"

# 6. The (base: ...) suffix is not part of the branch.
fresh
BASED="Created PR #27 for feat-a (base: main)"
is "base suffix: branch parsed without it" "stack|$URL_B|feat-a" "$(probe "gh stack submit" "$BASED" "$REPO_B")"
assign "gh stack submit" "$BASED" "$REPO_B"
wait_lines "$CALLS" '^pr edit' 1
is "base suffix: the branch check passes" "pr edit $URL_B --add-assignee @me" "$(edits)"

# 7. Remote forms give the real host's URL, and ssh -G runs only for an alias.
remote_case(){
  fresh
  local d="$ROOT/remote.$RUN"
  mkrepo "$d" "$2"
  is "$1" "$3" "$(prs_of "cd $d && gh stack submit" "Created PR #5 for x" "$NOREPO")"
  is "$1: ssh -G calls" "$4" "$(grep -c '^ssh ' "$TOOLS")"
}
remote_case "HTTPS remote"       https://github.com/o/r.git      https://github.com/o/r/pull/5 0
remote_case "HTTPS with no .git" https://github.com/o/r          https://github.com/o/r/pull/5 0
remote_case "enterprise HTTPS"   https://ghe.example.com/o/r.git https://ghe.example.com/o/r/pull/5 0
remote_case "SSH remote"         git@github.com:o/r.git          https://github.com/o/r/pull/5 0
remote_case "ssh:// remote"      ssh://git@github.com/o/r.git    https://github.com/o/r/pull/5 0
remote_case "SSH alias"          git@github.com-work:o/r.git     https://github.com/o/r/pull/5 1
check "SSH alias: asks for that host" "ssh -G github.com-work" "$(cat "$TOOLS")"
remote_case "SSH on another host" git@git.example.com:o/r.git    https://git.example.com/o/r/pull/5 1

# 8. Odd branch names and paths: the review's output stays valid JSON.
ODD='we"ird\name'
fresh
out=$(review "gh stack submit" "Created PR #27 for $ODD" "$REPO_B")
is "odd branch: output parses" "PostToolUse" "$(printf '%s' "$out" | "$REAL_JQ" -r '.hookSpecificOutput.hookEventName')"
check "odd branch: named exactly" "$ODD" "$(context "$out")"
is "odd branch: parsed exactly" "stack|$URL_B|$ODD" "$(probe "gh stack submit" "Created PR #27 for $ODD" "$REPO_B")"
out=$(review "gh stack submit" "Created PR #27 for $ODD" "$NOREPO")
check "odd branch, unknown repo: output parses" "$ODD" "$(context "$out")"
ODDDIR="$ROOT/qu\"o\\te"; mkrepo "$ODDDIR" https://github.com/acme/odd.git
out=$(review "cd '$ODDDIR' && gh stack submit" "$SUB" "$ODDDIR")
check "odd path: output parses" "https://github.com/acme/odd/pull/27" "$(context "$out")"
out=$(review "gh stack submit" $'Created PR #27 for feat\001x' "$REPO_B")
is "a control character: output parses" "PostToolUse" "$(printf '%s' "$out" | "$REAL_JQ" -r '.hookSpecificOutput.hookEventName')"

# With no jq at all.
nojq_review(){ event "$1" "$2" "$3" | PATH="$NOJQ" "$NOJQ/bash" "$REVIEW"; }
nojq_probe(){
  event "$1" "$2" "$3" | PATH="$NOJQ" "$NOJQ/bash" -c '. "$1"; printf "%s\n" "$kind|$prs|${branches:-}"' probe "$NEW_PRS"
}
fresh
out=$(nojq_review "gh stack submit" "Created PR #27 for $ODD" "$REPO_B")
check "no jq: odd branch still parses" "$ODD" "$(context "$out")"
check "no jq: lists the URL" "$URL_B" "$(context "$out")"
is "no jq: a cd is not parsed, cwd is used" "stack|$URL_A|feat-a" \
  "$(nojq_probe "cd \"$SPACED\" && gh stack submit" "$SUB" "$REPO_A")"
is "no jq: base suffix dropped" "stack|$URL_B|feat-a" "$(nojq_probe "gh stack submit" "$BASED" "$REPO_B")"
is "no jq: --remote is read" "stack|https://github.com/acme/upstream-one/pull/27|feat-a" \
  "$(nojq_probe "gh stack submit --remote upstream" "$SUB" "$REMOTES")"
is "no jq: gh pr create keeps its URL" "pr|https://github.com/acme/a/pull/9|" \
  "$(nojq_probe "gh pr create --fill" "https://github.com/acme/a/pull/9" "$REPO_A")"
fresh
event "cd \"$SPACED\" && gh stack submit" "$SUB" "$REPO_A" | PATH="$NOJQ" "$NOJQ/bash" "$ASSIGN"
wait_lines "$LOG" . 1
is "no jq: a missed cd is refused by the branch check" "" "$(edits)"

# 9. gh pr create: its URL, assigned directly, with no lookup.
PR_URL=https://github.com/acme/a/pull/9
is "gh pr create: prs is its URL" "pr|$PR_URL|" "$(probe "gh pr create --fill" "$PR_URL" "$NOREPO")"
fresh
assign "gh pr create --fill" "$PR_URL" "$NOREPO"
wait_lines "$CALLS" '^pr edit' 1
is "gh pr create: assigned by URL" "pr edit $PR_URL --add-assignee @me" "$(edits)"
refute "gh pr create: no lookup" "pr view" "$(cat "$CALLS")"
is "gh pr create: no git" "" "$(cat "$TOOLS")"
fresh
out=$(review "gh pr create --fill" "$PR_URL" "$NOREPO")
check "gh pr create: the review context names it" "$PR_URL" "$(context "$out")"

# 10. An unrelated Bash command: no git, jq or ssh, and nothing printed.
fresh
out=$(assign "ls -la" "total 0" "$REPO_A"; review "ls -la" "total 0" "$REPO_A")
is "unrelated command: prints nothing" "" "$out"
# event() itself runs the real jq, so TOOLS only records the hooks' own calls.
is "unrelated command: no git, jq or ssh" "" "$(cat "$TOOLS")"

# 11. ~ expands unquoted, and stays literal quoted.
fresh
mkrepo "$HOME/code/tilde" https://github.com/acme/tilde.git
TILDE=https://github.com/acme/tilde/pull/27
is "~/x expands against HOME" "$TILDE" "$(prs_of "cd ~/code/tilde && gh stack submit" "$SUB" "$NOREPO")"
is "~/\"x\" expands too" "$TILDE" "$(prs_of "cd ~/\"code/tilde\" && gh stack submit" "$SUB" "$NOREPO")"
is "a quoted ~/x stays literal: unknown" 27 "$(prs_of "cd \"~/code/tilde\" && gh stack submit" "$SUB" "$REPO_A")"
is "a single-quoted ~/x stays literal: unknown" 27 "$(prs_of "cd '~/code/tilde' && gh stack submit" "$SUB" "$REPO_A")"
is "~user can't be read: unknown" 27 "$(prs_of "cd ~someone/x && gh stack submit" "$SUB" "$REPO_A")"

# 12. Claude Code may already have applied the cd to the event's cwd.
FOO="$ROOT/parent/foo"; mkrepo "$FOO" https://github.com/acme/foo.git
URL_F=https://github.com/acme/foo/pull/27
head_of "$URL_F" feat-a
fresh
assign "cd foo && gh stack submit --auto" "$SUB" "$FOO"
wait_lines "$CALLS" '^pr edit' 1
is "cwd already moved: the repo at cwd is used" "pr edit $URL_F --add-assignee @me" "$(edits)"
check "cwd already moved: the branch check ran" "pr view $URL_F" "$(cat "$CALLS")"

# 13. A command or output that merely mentions gh stack runs no git or ssh.
ALIASED="$ROOT/aliased"; mkrepo "$ALIASED" git@github.com-work:o/r.git
mention(){
  fresh
  assign "$1" "$2" "$ALIASED" >/dev/null
  out=$(review "$1" "$2" "$ALIASED")
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
mention 'grep "gh stack submit" notes' "Created PR #27 for feat-a" "a grep that also hits a Created PR line"
mention 'cat notes' "gh stack submit printed: Created PR #27 for feat-a" "a doc that quotes the output"
mention 'grep "gh stack submit" notes' "see https://github.com/o/r/pull/3" "a grep that hits a PR URL"
fresh
event 'grep "gh stack submit" notes' "Created PR #27 for feat-a" "$ALIASED" | PATH="$NOJQ" "$NOJQ/bash" "$REVIEW" >/dev/null
is "no jq, a grep: no git or ssh" "" "$(cat "$TOOLS")"

# 14. $HOME and ${HOME} at the start of a path expand, except in single quotes.
fresh
mkrepo "$HOME/code/home-var" https://github.com/acme/home-var.git
HOMEVAR=https://github.com/acme/home-var/pull/27
is "unquoted \$HOME"      "$HOMEVAR" "$(prs_of 'cd $HOME/code/home-var && gh stack submit' "$SUB" "$NOREPO")"
is "double-quoted \$HOME" "$HOMEVAR" "$(prs_of 'cd "$HOME/code/home-var" && gh stack submit' "$SUB" "$NOREPO")"
is "unquoted \${HOME}"    "$HOMEVAR" "$(prs_of 'cd ${HOME}/code/home-var && gh stack submit' "$SUB" "$NOREPO")"
is "double-quoted \${HOME}" "$HOMEVAR" "$(prs_of 'cd "${HOME}/code/home-var" && gh stack submit' "$SUB" "$NOREPO")"
is "\$HOME itself is the home folder" https://github.com/acme/at-home/pull/27 \
  "$(mkrepo "$HOME" https://github.com/acme/at-home.git; prs_of 'cd "$HOME" && gh stack submit' "$SUB" "$NOREPO")"
is "single-quoted \$HOME stays literal: unknown" 27 "$(prs_of "cd '\$HOME/code/home-var' && gh stack submit" "$SUB" "$NOREPO")"
is "cd \"\$REPO\": unknown" 27 "$(prs_of 'cd "$REPO" && gh stack submit' "$SUB" "$REPO_A")"
is "\$HOMEX is another variable: unknown" 27 "$(prs_of 'cd "$HOMEX/code" && gh stack submit' "$SUB" "$REPO_A")"
is "\$HOME past the start: unknown" 27 "$(prs_of 'cd "/x$HOME/code" && gh stack submit' "$SUB" "$REPO_A")"

# The second fast check and the locale: real PR creation is untouched.
locale_probe(){
  printf '%s' "$1" | env "${@:2}" bash -c '. "$1"; printf "%s" "${LC_ALL-unset}"' probe "$NEW_PRS"
}
PR_EVENT=$(event "gh pr create --fill" "$PR_URL" "$NOREPO")
is "locale: an LC_ALL is restored" "en_US.UTF-8" "$(locale_probe "$PR_EVENT" LC_ALL=en_US.UTF-8)"
is "locale: no LC_ALL stays unset" "unset" "$(locale_probe "$PR_EVENT" -u LC_ALL)"

# One remote lookup per hook run, whatever the size of the stack.
STACK3="Created PR #41 for s-one (base: main)
Created PR #42 for s-two (base: s-one)
Created PR #43 for s-three (base: s-two)"
fresh
out=$(review "cd $ALIASED && gh stack submit" "$STACK3" "$NOREPO")
is "three PRs, review hook: one git call" 1 "$(grep -c '^git ' "$TOOLS")"
is "three PRs, review hook: one ssh -G" 1 "$(grep -c '^ssh ' "$TOOLS")"
is "review hook: no gh at all" "" "$(cat "$CALLS")"
# Numbers out of order: bottom of the stack is the first line gh stack prints.
fresh
ctx=$(context "$(review "cd $REPO_B && gh stack submit" "Created PR #52 for bottom
Created PR #51 for top
Created PR #52 for bottom" "$NOREPO")")
check "URLs with branches, bottom first" "https://github.com/acme/b/pull/52 (head branch: bottom), https://github.com/acme/b/pull/51 (head branch: top)" "$ctx"
check "tells the review to compare" "check each PR's head branch" "$ctx"
check "tells the review to stop on a mismatch" "stop and say so" "$ctx"
is "a repeated line is one PR" 1 "$(printf '%s' "$ctx" | grep -o 'pull/52' | wc -l | tr -d ' ')"

fresh
assign "cd $ALIASED && gh stack submit" "$STACK3" "$NOREPO"
is "three PRs, assign hook: one git call" 1 "$(grep -c '^git ' "$TOOLS")"
is "three PRs, assign hook: one ssh -G" 1 "$(grep -c '^ssh ' "$TOOLS")"
wait_lines "$LOG" . 3
is "three PRs, assign hook: one log line each when none matches" 3 "$(log_lines)"

# No fixed wait or retry in a hook.
refute "new-prs.sh: no sleep"       "sleep" "$(cat "$NEW_PRS")"
refute "assign-author.sh: no sleep" "sleep" "$(cat "$ASSIGN")"
refute "review-new-pr.sh: no sleep" "sleep" "$(cat "$REVIEW")"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
