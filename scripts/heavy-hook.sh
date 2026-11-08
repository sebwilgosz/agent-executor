#!/usr/bin/env bash
# heavy-hook.sh — PreToolUse hook on Bash: puts a heavy command in the queue. No AI.
# When a command matches, it answers with the same tool input and this command:
#
#   bash '<plugin root>/scripts/heavy.sh' $$ <label>; <original command, byte for byte>
#
# The original stays unquoted, so deny and ask rules still see it, and the answer
# has no permissionDecision, so what is allowed never changes. Nothing is printed
# for any other command.
#
# Settings: heavy.json in the state folder, as in heavy.sh. No file means off.
#
# It runs on every Bash call, so an ordinary one starts no process at all: the
# reads, the text check and the exit are shell builtins. A command with a keyword
# starts jq once, and a match once more. A custom match can't be prefiltered, so it
# starts jq on every call.
#
# Always fails open: any failure prints nothing and logs one failed line, so the
# command runs at once, untouched. The log never holds the command text.
set -u

DIR="${EXECUTOR_HEAVY_DIR:-${HOME:-}/.engineer-of-wealth/executor}"
case "$DIR" in /*) ;; *) DIR="$PWD/$DIR" ;; esac
[ -e "$DIR/heavy.json" ] || exit 0

exec 2>/dev/null

failed() {
  printf '%s  heavy-hook  %s  waited=0  failed\n' "$(date '+%F %T')" "${PWD//[[:cntrl:]]/ }" >> "$DIR/heavy.log"
  exit 0
}

# Byte matching, since bash's multibyte match is most of the cost on a large event.
lc_was_set=${LC_ALL+1}
lc_was=${LC_ALL-}
LC_ALL=C

IFS= read -r -d '' event
IFS= read -r -d '' settings < "$DIR/heavy.json"

# Only the text from the command on: a folder named after a tool shouldn't start jq
# on every call. A \u escape could spell any keyword, so it goes on to jq as well.
case "$settings" in
  *match* | *\\u*) ;;
  *)
    case "${event#*\"command\"}" in
      *next*build* | *npm*test* | *npm*build* | *yarn*test* | *yarn*build* \
        | *vitest* | *jest* | *playwright*test* | *pytest* \
        | *python*test_* | *python*run_tests* | *.test.sh* | *--headless* | *\\u*) ;;
      *) exit 0 ;;
    esac
    ;;
esac

command -v jq >/dev/null || failed

# jq replaces half a surrogate pair in some versions, so the bytes wouldn't survive.
case "$event" in
  *\\u[dD][89a-fA-F]*) failed ;;
esac

# One record per field, each ended by a NUL: custom or default, the command's first
# line, the number of custom labels, each label and regex in file order, then the
# segments. jq splits them, since bash's ${x//;/...} takes minutes on a long heredoc.
# Errors stop jq before its first record.
JQ_READ='
  def positive: type == "number" and . > 0 and (isinfinite | not);
  ($cfg | if length == 1 and (.[0] | type) == "object" then .[0] else error("settings") end) as $c
  | if all(("slots", "wait_minutes", "hold_minutes") as $k
        | select($c | has($k)) | $c[$k]; positive)
      and (if $c | has("slots") then $c.slots == ($c.slots | floor) else true end)
      and (if $c | has("match")
        then ($c.match | type) == "object" and all($c.match[]; type == "string")
        else true end)
    then . else error("settings") end
  | .tool_input.command as $command
  | if ($command | type) != "string" then error("input") else . end
  | ($c.match // {} | to_entries) as $pairs
  | [ (if $c | has("match") then "custom" else "default" end),
      ($command | split("\n") | map(select(length > 0)) | .[0] // ""),
      ($pairs | length | tostring) ]
    + [$pairs[] | .key, .value]
    + [ reduce ("&&", "||", ";", "|", "\n") as $sep ([$command]; map(split($sep)) | add // [])
        | .[] | select(length > 0) ]
  | if all(.[]; explode | all(. != 0)) then .[] + "\u0000" else error("nul") end
'

ASSIGNMENT="^[A-Za-z_][A-Za-z0-9_]*=(\"([^\"\\\\]|\\\\.)*\"|'[^']*'|\\\\.|[^[:space:]\"'\\\\])*[[:space:]]+"

labels=()
patterns=()
segments=()

# bash compiles a regex on each use and a long heredoc can be thousands of segments,
# so a regex only runs on what a glob couldn't rule out.
{
  IFS= read -r -d '' mode || failed
  IFS= read -r -d '' first_line
  IFS= read -r -d '' count
  for ((i = 0; i < count; i++)); do
    IFS= read -r -d '' label
    IFS= read -r -d '' pattern
    case "$label" in
      '' | *[!A-Za-z0-9._-]*) failed ;;
    esac
    labels+=("$label")
    patterns+=("$pattern")
  done
  while IFS= read -r -d '' seg; do
    seg=${seg#"${seg%%[![:space:]]*}"}
    case "${seg%%=*}" in
      "$seg" | *[!A-Za-z0-9_]*) ;;
      *)
        while [[ $seg =~ $ASSIGNMENT ]]; do
          seg=${seg:${#BASH_REMATCH[0]}}
        done
        ;;
    esac
    if [ "$mode" = default ]; then
      case "$seg" in
        next* | npx* | npm* | pnpm* | yarn* | vitest* | jest* | playwright* | pytest* | python* \
          | *.test.sh* | *--headless*) ;;
        *) continue ;;
      esac
    fi
    segments+=("$seg")
  done
} < <(printf '%s' "$event" | jq -j --slurpfile cfg "$DIR/heavy.json" "$JQ_READ")

if [ -n "$lc_was_set" ]; then LC_ALL=$lc_was; else unset LC_ALL; fi

if [ "$mode" = custom ]; then
  for pattern in ${patterns[@]+"${patterns[@]}"}; do
    [[ '' =~ $pattern ]]
    [ $? -eq 2 ] && failed
  done
else
  S='[[:space:]]+'
  N='[^[:space:]]'
  END='($|[[:space:]&<>)])'
  PM="^(npm|pnpm|yarn)($S--prefix($S|=)$N+)?(${S}run)?($S--prefix($S|=)$N+)?$S"
  PY="^python3?($S-$N+)*$S"
  labels=(next-build npm-build npm-test js-test pytest py-test sh-test chrome)
  patterns=(
    "^(npx$S)?next${S}build$END"
    "${PM}build(:$N+)?$END"
    "${PM}test(:$N+)?$END"
    "^(npx$S)?(vitest|jest|playwright${S}test)$END"
    "^(pytest|python3?($S-$N+)*$S-m${S}pytest)$END"
    "$PY($N*/)?(test_[^[:space:]/]*|run_tests)\\.py$END"
    "^((bash|sh)($S-$N+)*$S)?$N*\\.test\\.sh$END"
    "--headless"
  )
fi

# By hand or by another copy of this hook, under any root and with any label.
PREFIXED="^[[:space:]]*bash[[:space:]]+('[^']*|\"[^\"]*|[^[:space:];&|'\"]*)heavy\\.sh['\"]?[[:space:]]+\\\$\\\$([[:space:]]|;)"
[[ $first_line =~ $PREFIXED ]] && exit 0

[ "${#segments[@]}" -gt 0 ] || exit 0

matched=
for ((i = 0; i < ${#labels[@]}; i++)); do
  pattern=${patterns[i]}
  for seg in "${segments[@]}"; do
    if [[ $seg =~ $pattern ]]; then
      matched=${labels[i]}
      break 2
    fi
  done
done
[ -n "$matched" ] || exit 0

# The slot script can't run from a folder it can't write, and a quote or control
# character in the root would break the prefix.
{ [ -w "$DIR" ] && : >> "$DIR/heavy.log"; } || failed
root=$(cd -P "${0%/*}/.." && pwd)
case "$root" in
  '' | *"'"* | *[[:cntrl:]]*) failed ;;
esac
[ -f "$root/scripts/heavy.sh" ] || failed

# jq adds the prefix to the command it read itself, so nothing here can lose a byte.
printf '%s' "$event" | jq -c --arg prefix "bash '$root/scripts/heavy.sh' \$\$ $matched; " '
  {hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: (.tool_input + {command: ($prefix + .tool_input.command)})
  }}' || failed
exit 0
