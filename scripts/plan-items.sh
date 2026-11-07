# Sourced by every script that reads a build plan's items, so all agree on what an
# item says. The one reader of them. An item is a "- [ ]" or "- [x]" line. Its state
# is read from the text after its spec link, or the whole line without one: a PR
# number or a stop sign in the feature's name is not its state.
# Sets LC_ALL=C: the name's cut counts bytes. Defines:
#   ITEM_RE                 what an item line matches
#   read_items <plan>       sets items, an array of the plan's item lines, in order;
#                           returns 1, with no output, when it can't read the plan
#   parse_item <line>       sets ITEM_PR (a number or empty), ITEM_BRANCH (a name or
#                           empty), ITEM_BLOCKED (a stop sign), ITEM_BUILDING (a
#                           hammer) and ITEM_TICKED, the last three 1 or 0
#   item_name <line>        prints the feature's name, cut to NAME_MAX
# No output when sourced, never fails.
LC_ALL=C

NAME_MAX=60
ITEM_RE='^[[:space:]]*- \[[ xX]\] '
UNTICKED_RE='^[[:space:]]*- \[ \] '
PR_RE='(^|[^[:alnum:]])PR #([0-9]+)'
BRANCH_RE='(^|[[:space:]])branch `?([^[:space:]`]+)'

read_items() {
  local line
  items=()
  [ -r "$1" ] && [ -f "$1" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    [[ $line =~ $ITEM_RE ]] && items[${#items[@]}]=$line
  done < "$1"
  return 0
}

parse_item() {
  local t=$1
  case "$t" in
    *"]("*) t=${t##*"]("}; t=${t#*\)} ;;
  esac
  ITEM_PR=""; ITEM_BRANCH=""; ITEM_BLOCKED=0; ITEM_BUILDING=0; ITEM_TICKED=1
  [[ $1 =~ $UNTICKED_RE ]] && ITEM_TICKED=0
  case "$t" in *⛔*) ITEM_BLOCKED=1 ;; esac
  case "$t" in *🔨*) ITEM_BUILDING=1 ;; esac
  [[ $t =~ $PR_RE ]] && ITEM_PR=${BASH_REMATCH[2]}
  [[ $t =~ $BRANCH_RE ]] && ITEM_BRANCH=${BASH_REMATCH[2]}
  return 0
}

# The item line up to its link or state.
item_name() {
  local s=$1 cut em=$'\xe2\x80\x94'
  s=${s#"${s%%[![:space:]]*}"}; s=${s#- \[?\] }
  case "$s" in
    *" ["*) s=${s%%" ["*} ;;
    *) for cut in ' PR #' ' branch ' ' ⛔' ' 🔨'; do s=${s%%"$cut"*}; done ;;
  esac
  while :; do
    case "$s" in
      *" "|*"-") s=${s%?} ;;
      *" $em") s=${s%" $em"} ;;
      *) break ;;
    esac
  done
  if [ "${#s}" -gt "$NAME_MAX" ]; then
    s=${s:0:$NAME_MAX}
    # bytes here, under LC_ALL=C: don't leave half a character behind.
    while :; do
      case "${s: -1}" in
        [$'\x80'-$'\xff']) s=${s%?} ;;
        *) break ;;
      esac
    done
    s="$s..."
  fi
  printf '%s' "$s"
}
