#!/usr/bin/env bash
# PostToolUse hook: after Claude creates pull requests, tell it to review them.
# Local only, no network: it reads the tool's output and returns in milliseconds.
# Prints nothing unless a PR was created.
set -u

. "$(dirname "$0")/new-prs.sh"
[ -n "$kind" ] || exit 0

if [ "$kind" = stack ]; then
  list=$(printf '%s\n' $prs | sed 's/^/#/' | paste -sd ',' - | sed 's/,/, /g')
  context="Executor: stacked pull requests were just created: $list. First give each one its title and body as references/feature-done.md says (gh pr edit), then run the executor:review skill on each, bottom of the stack first, and finish with each summary."
else
  context="Executor: a pull request was just created: $prs. Run the executor:review skill on it now, before anything else, and finish with its summary."
fi

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$context"
