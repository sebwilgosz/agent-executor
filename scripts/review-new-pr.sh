#!/usr/bin/env bash
# PostToolUse hook: after Claude creates pull requests, tell it to review them.
# Local only, no network: it reads the tool's output and returns in milliseconds.
# Prints nothing unless a PR was created.
set -u

. "$(dirname "$0")/new-prs.sh"
[ -n "$kind" ] || exit 0

if [ "$kind" = stack ]; then
  list=
  while IFS= read -r pr <&3; do
    IFS= read -r branch <&4
    case "$pr" in
      https://*) ;;
      *) pr="#$pr" ;;
    esac
    list="$list${list:+, }$pr (head branch: $branch)"
  done 3<<< "$prs" 4<<< "$branches"
  case $'\n'"$prs" in
    *$'\n'[0-9]*)
      context="Executor: stacked pull requests were just created, bottom of the stack first: $list. The repo could not be identified for each one listed by number. Find the repo before reviewing; do not resolve these numbers from the current folder. Then check each PR's head branch matches the branch listed here; if one doesn't, stop and say so, and leave that PR alone. Then give each one its title and body as references/feature-done.md says (gh pr edit <url>), run the executor:review skill on each by its URL, bottom of the stack first, and finish with each summary."
      ;;
    *)
      context="Executor: stacked pull requests were just created, bottom of the stack first: $list. Before anything else, check each PR's head branch matches the branch listed here (gh pr view <url> --json headRefName); if one doesn't, stop and say so, and leave that PR alone. Then give each one its title and body as references/feature-done.md says (gh pr edit <url>), run the executor:review skill on each by its URL, bottom of the stack first, and finish with each summary."
      ;;
  esac
else
  context="Executor: a pull request was just created: $prs. Run the executor:review skill on it now, before anything else, and finish with its summary."
fi

context=${context//\\/\\\\}
context=${context//\"/\\\"}
context=${context//$'\n'/\\n}
context=${context//$'\t'/\\t}
context=${context//$'\r'/\\r}
context=${context//[[:cntrl:]]/}

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$context"
