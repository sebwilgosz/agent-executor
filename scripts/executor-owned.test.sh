#!/usr/bin/env bash
# Spec tests for scripts/executor-owned.sh - the one rule for what is Executor's
# own: a branch named by `PR #<n>` in a plan of the repo, or worktree-agent-*; a
# worktree on such a branch, or under <main checkout>/.claude/worktrees/agent-.
# A stub gh stands in for GitHub and counts its calls.
#
# Run: bash scripts/executor-owned.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()  { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }

ROOT=$(cd -P "$(mktemp -d)" && pwd)
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"; mkdir -p "$HOME"
export EOW_HOME="$ROOT/eow"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$ROOT/gitconfig"
export EXECUTOR_PLANS="$ROOT/plans"
git config --global user.email t@example.com
git config --global user.name T
git config --global init.defaultBranch main
BIN="$ROOT/bin"; mkdir -p "$BIN"
export CALLS="$ROOT/calls"; : > "$CALLS"
cat > "$BIN/gh" <<'STUB'
#!/bin/sh
echo "$*" >> "$CALLS"
[ ! -e "$ROOT/down" ] || { echo "no network" >&2; exit 1; }
printf '7 feat-seven\n8 feat-eight\n9 feat-nine\n'
STUB
chmod +x "$BIN/gh"
export ROOT PATH="$BIN:$PATH"

REPO="$ROOT/api"
git init -q "$REPO"
git -C "$REPO" remote add origin https://github.com/acme/api.git
mkdir -p "$ROOT/plans/acme/api"
printf 'Status: done 2026-01-02\n\n## Items\n- PR #7\n' > "$ROOT/plans/acme/api/2026-01-01 - done.md"
printf '## Items\n- PR #8 and PR #80\n' > "$ROOT/plans/acme/api/2026-01-03 - live.md"

. "$SELF_DIR/executor-owned.sh"

echo "executor-owned.sh spec tests"
executor_owned_load "$REPO"; is "load: GitHub answered" 0 "$?"
is "load: one gh call" 1 "$(wc -l < "$CALLS" | tr -d ' ')"
executor_branch_owned feat-seven; is "branch in a done plan: owned" 0 "$?"
executor_branch_owned feat-eight; is "branch in a live plan: owned" 0 "$?"
executor_branch_owned feat-nine; is "branch of a PR no plan names: not owned" 1 "$?"
executor_branch_owned worktree-agent-ab12; is "worktree-agent-*: owned" 0 "$?"
executor_branch_owned feat-user; is "any other branch: not owned" 1 "$?"
executor_worktree_owned "$REPO" "$REPO/.claude/worktrees/agent-x" feat-user
is "worktree under .claude/worktrees/agent-*: owned" 0 "$?"
executor_worktree_owned "$REPO" "$ROOT/elsewhere" feat-seven
is "worktree on an owned branch: owned" 0 "$?"
executor_worktree_owned "$REPO" "$ROOT/elsewhere" feat-user
is "user worktree elsewhere: not owned" 1 "$?"
executor_worktree_owned "$REPO" "$REPO/.claude/worktrees/mine" feat-user
is "worktree under .claude/worktrees without agent-: not owned" 1 "$?"
is "queries make no gh call" 1 "$(wc -l < "$CALLS" | tr -d ' ')"

touch "$ROOT/down"
executor_owned_load "$REPO"; is "GitHub down: unknown code" 2 "$?"

rm -f "$ROOT/down"; rm -rf "$ROOT/plans"; : > "$CALLS"
executor_owned_load "$REPO"; is "no plans: loads" 0 "$?"
is "no plans: no gh call" 0 "$(wc -l < "$CALLS" | tr -d ' ')"
executor_branch_owned feat-seven; is "no plans: PR branch not owned" 1 "$?"
executor_branch_owned worktree-agent-q; is "no plans: worktree-agent-* still owned" 0 "$?"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
