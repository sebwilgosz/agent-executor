# Sourced by the PostToolUse hooks. Reads the hook event (JSON) from stdin and
# sets: kind (stack | pr, empty when no PR was created), cwd (the session's
# directory), prs and branches.
# prs holds one PR per line: the URL gh pr create printed, or for a stack each new
# PR's URL as gh stack printed it, bottom of the stack first. A bare number means it
# printed none, so the repo is unknown. branches holds each stack PR's branch, line
# for line; it is empty on the pr path.
# Local only: no network, no AI.

event=$(cat)
kind=
prs=
branches=

# Fast exit for the ordinary tool call: these hooks run after every Bash call. Byte
# matching, since bash's multibyte match is most of the cost on a large event. The
# second check: with neither text, prs is always empty, so no PR was created.
lc_was_set=${LC_ALL+1}
lc_was=${LC_ALL-}
LC_ALL=C
case "$event" in
  *"gh pr create"* | *"gh stack submit"* | *"gh stack link"* | *create_pull_request*) ;;
  *) exit 0 ;;
esac
case "$event" in
  *"Created PR #"* | */pull/*) ;;
  *) exit 0 ;;
esac
if [ -n "$lc_was_set" ]; then LC_ALL=$lc_was; else unset LC_ALL; fi

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
  command=$(printf '%s' "$event" | grep -aoE '"command" *: *"([^"\\]|\\.)*"' | head -1)
  if [ -n "$command" ]; then
    command=${command#*\"command\"}
    command=${command#*\"}
    command=${command%\"}
  else
    command=$event
  fi
  response=$event
fi

case "$tool" in
  Bash)
    # A gh stack right after a quote is a mention, such as a grep's pattern, unless
    # the quote opens a script for eval or a -c.
    if printf '%s' "$command" | grep -qE -- '--help|--dry-run'; then
      kind=
    elif printf '%s' "$command" | grep -qE '(^|[;&|(`[:space:]]|(eval|-[[:alpha:]]*c) +\\?["'\''])gh +stack +(submit|link)'; then
      kind=stack
    elif printf '%s' "$command" | grep -qE '(^|[;&|("[:space:]])gh +pr +create'; then
      kind=pr
    fi
    ;;
  mcp__*__create_pull_request) kind=pr ;;
esac

# "Created PR #N (<url>) for <branch>", maybe with " (base: x)" at the end; existing
# PRs are skipped. Off a terminal gh stack prints the URL, and a line without one, or
# with one that isn't this PR's, leaves the bare number. $response is JSON-encoded
# here, on both paths, so a branch ends at the first space, closing quote or escape
# other than an escaped \, " or /. One grep picks the lines, since a bash regex over a
# large output takes far longer than the hook has.
read_created() {
  local line n url b url_re seen=' ' nl=$'\n'
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=${line#Created PR #}
    n=${n%%[!0-9]*}
    case "$seen" in
      *" $n "*) continue ;;
    esac
    seen="$seen$n "
    url=${line#Created PR #$n}
    url=${url%% for *}
    url=${url# (}
    url=${url%)}
    url=${url//\\\//\/}
    url_re="^https://[[:alnum:]][[:alnum:].-]*(:[0-9]+)?/[[:alnum:]._-]+/[[:alnum:]._-]+/pull/$n\$"
    [[ $url =~ $url_re ]] || url=$n
    b=${line#* for }
    b=${b//\\\\/$'\002'}
    b=${b//\\\"/\"}
    b=${b//\\\//\/}
    b=${b//$'\002'/\\}
    prs=$prs${prs:+$nl}$url
    branches=$branches${branches:+$nl}$b
  done <<< "$(printf '%s' "$response" | grep -aoE 'Created PR #[0-9]+( \([^)[:space:]]*\))? for ([^"\\[:space:]]|\\["\\/])+')"
}

if [ "$kind" = stack ]; then
  read_created
elif [ "$kind" = pr ]; then
  prs=$(printf '%s' "$response" | grep -oE 'https://github\.com/[^/"[:space:]]+/[^/"[:space:]]+/pull/[0-9]+' | tail -1)
fi
[ -n "$prs" ] || kind=
