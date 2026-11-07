# Sourced by every script that reads a build plan's items, so all agree on what an
# item says. The one reader of them. An item is a "- [ ]" or "- [x]" line. Its state
# is read from the text after its spec link, or the whole line without one: a PR
# number or a stop sign in the feature's name is not its state.
# Sets LC_ALL=C: the name's cut counts bytes. Defines:
#   ITEM_RE                 what an item line matches
#   read_items <plan>       sets items, an array of the plan's item lines, in order,
#                           and item_sections, the "## " heading above each (empty
#                           before the first); returns 1, with no output, when it
#                           can't read the plan
#   parse_item <line>       sets ITEM_PR (a number or empty), ITEM_BRANCH (a name or
#                           empty), ITEM_BLOCKED (a stop sign), ITEM_BUILDING (a
#                           hammer), ITEM_TICKED and ITEM_MERGED (the line says
#                           merged), those four 1 or 0, ITEM_REVIEW (ready, in
#                           review, open findings or none) and ITEM_NOTE (a stop
#                           sign's question or what a cross says is open)
#   item_full_name <line>   prints the feature's name
#   item_name <line>        prints the feature's name, cut to NAME_MAX
#   plan_path <args>        runs plan-path.sh, with no stderr
#   resolve_repo <plan> <slug>  sets PLAN_REPO, what gh gets as --repo:
#                           [<host>/]<org>/<repo>. The host is this folder's origin
#                           when it is a checkout of the plan's repo, then the plan's
#                           "Host: <host>" line, then none: gh's default. Returns 1
#                           with PLAN_WHY set on a Host line that names no host
#   plan_branch_merged <plan> <branch> <ticked>  returns 0 when the branch is an
#                           ancestor of the default branch, 1 when it isn't or, on
#                           an unticked item, doesn't exist yet, 2 with PLAN_WHY set
#                           when this folder or git can't tell
# No output when sourced, never fails.
LC_ALL=C

ITEMS_DIR=$(CDPATH= cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)

NAME_MAX=60
ITEM_RE='^[[:space:]]*- \[[ xX]\] '
UNTICKED_RE='^[[:space:]]*- \[ \] '
PR_RE='(^|[^[:alnum:]])PR #([0-9]+)'
BRANCH_RE='(^|[[:space:]])branch `?([^[:space:]`]+)'
HOST_RE='^[[:alnum:]][[:alnum:].-]*$'

read_items() {
  local line section=""
  items=(); item_sections=()
  [ -r "$1" ] && [ -f "$1" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in "## "*) section=${line#"## "} ;; esac
    if [[ $line =~ $ITEM_RE ]]; then
      item_sections[${#items[@]}]=$section
      items[${#items[@]}]=$line
    fi
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
  ITEM_REVIEW=none; ITEM_NOTE=""; ITEM_MERGED=0
  case "$t" in
    *❌*) ITEM_REVIEW="open findings"; ITEM_NOTE=${t#*❌} ;;
    *⏳*) ITEM_REVIEW="in review" ;;
    *✅*) ITEM_REVIEW=ready; case "$t" in *"✅ merged"*) ITEM_MERGED=1 ;; esac ;;
  esac
  case "$t" in *⛔*) ITEM_NOTE=${t#*⛔} ;; esac
  ITEM_NOTE=${ITEM_NOTE#"${ITEM_NOTE%%[![:space:]]*}"}
  ITEM_NOTE=${ITEM_NOTE%"${ITEM_NOTE##*[![:space:]]}"}
  return 0
}

# The item line up to its link or state.
item_full_name() {
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
  printf '%s' "$s"
}

item_name() {
  local s
  s=$(item_full_name "$1")
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

plan_path() { "$BASH" "$ITEMS_DIR/plan-path.sh" "$@" 2>/dev/null; }

# Is this folder a checkout of the plan's repo? The folder's answer is asked once.
PLAN_HERE=""
in_plan_checkout() {
  local plan_dir
  [ -n "$PLAN_HERE" ] || PLAN_HERE=$(plan_path "$PWD")
  case "$PLAN_HERE" in STOP:*) return 1 ;; esac
  plan_dir=$(cd "$(dirname "$1")" 2>/dev/null && pwd)
  [ "$PLAN_HERE" = "$plan_dir" ]
}

# Prints the value of the plan's "Host:" header line, nothing without one.
plan_host() {
  local l
  while IFS= read -r l || [ -n "$l" ]; do
    l=${l%$'\r'}
    case "$l" in
      "## "*) return 0 ;;
      "Host: "*) printf '%s' "${l#Host: }"; return 0 ;;
    esac
  done < "$1"
}

resolve_repo() {
  local host=""
  if in_plan_checkout "$1"; then host=$(plan_path --host "$PWD"); fi
  [ -n "$host" ] || host=$(plan_host "$1")
  if [ -n "$host" ] && ! [[ $host =~ $HOST_RE ]]; then
    PLAN_WHY="not a host: $host, in $1"
    return 1
  fi
  PLAN_REPO="${host:+$host/}$2"
}

PLAN_CMP=""
plan_branch_merged() {
  local rc err
  if ! in_plan_checkout "$1"; then
    PLAN_WHY="no checkout of this plan's repo here, to read branch $2: $PWD"
    return 2
  fi
  if [ -z "$PLAN_CMP" ]; then
    . "$ITEMS_DIR/default-branch.sh" </dev/null
    PLAN_CMP=$cmp
  fi
  if ! git check-ref-format --branch "$2" >/dev/null 2>&1; then
    PLAN_WHY="not a branch name: $2"
    return 2
  fi
  if ! git rev-parse --verify --quiet "refs/heads/$2^{commit}" >/dev/null 2>&1; then
    [ "$3" -eq 0 ] && return 1
    PLAN_WHY="branch $2 not found, so it cannot be read"
    return 2
  fi
  err=$(git merge-base --is-ancestor "refs/heads/$2" "$PLAN_CMP" 2>&1)
  rc=$?
  case "$rc" in
    0|1) return "$rc" ;;
  esac
  PLAN_WHY="git cannot compare $2 with $PLAN_CMP: ${err%%$'\n'*}"
  return 2
}
