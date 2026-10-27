# Sourced by the PostToolUse hooks. Reads the hook event (JSON) from stdin and
# sets: kind (stack | pr, empty when no PR was created), prs (PR numbers, or one
# PR URL), cwd (the session's directory). Local only: no network, no AI.

event=$(cat)
kind=
prs=

# Fast exit for the ordinary tool call: these hooks run after every Bash call.
case "$event" in
  *"gh pr create"* | *"gh stack submit"* | *"gh stack link"* | *create_pull_request*) ;;
  *) exit 0 ;;
esac

if command -v jq >/dev/null 2>&1; then
  tool=$(printf '%s' "$event" | jq -r '.tool_name // empty')
  command=$(printf '%s' "$event" | jq -r '.tool_input.command // empty')
  response=$(printf '%s' "$event" | jq -c '.tool_response // empty')
  cwd=$(printf '%s' "$event" | jq -r '.cwd // empty')
else
  # No jq: match the raw event. Coarser, but the last PR URL is still the new one.
  field() { printf '%s' "$event" | grep -oE "\"$1\" *: *\"[^\"]*\"" | head -1 | sed -E 's/.*"([^"]*)"$/\1/'; }
  tool=$(field tool_name)
  cwd=$(field cwd)
  command=$event
  response=$event
fi

case "$tool" in
  Bash)
    if printf '%s' "$command" | grep -qE -- '--help|--dry-run'; then
      kind=
    elif printf '%s' "$command" | grep -qE '(^|[;&|("[:space:]])gh +stack +(submit|link)'; then
      kind=stack
    elif printf '%s' "$command" | grep -qE '(^|[;&|("[:space:]])gh +pr +create'; then
      kind=pr
    fi
    ;;
  mcp__*__create_pull_request) kind=pr ;;
esac

if [ "$kind" = stack ]; then
  # gh stack reports each new PR as "Created PR #N for <branch>"; existing ones are skipped.
  prs=$(printf '%s' "$response" | grep -oE 'Created PR #[0-9]+' | grep -oE '[0-9]+' | sort -u -n)
elif [ "$kind" = pr ]; then
  prs=$(printf '%s' "$response" | grep -oE 'https://github\.com/[^/"[:space:]]+/[^/"[:space:]]+/pull/[0-9]+' | tail -1)
fi
[ -n "$prs" ] || kind=
