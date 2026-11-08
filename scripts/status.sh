#!/usr/bin/env bash
# status.sh - across every repo: what is yours to merge now, what waits on you, what
# is still moving. No AI. Read-only: it never marks a plan, never pushes, never posts.
#
# Reads the plans from plan-path.sh --all-live and each one's items through
# plan-items.sh. Each PR's state, draft flag and CI come from gh, at most 8 lookups at
# once, and win over a stale plan line; the review verdict exists only in the plan.
# Items of a local/<name> plan are read from its text, with no lookups.
#
#   MERGE NOW       PR open, not a draft, CI not red, nothing unfinished below it
#   WAITING ON YOU  a stop sign, a cross, a ready PR with red CI
#   MOVING          a hammer, a draft, a ready PR waiting on the one below, a count of
#                   the items not started per stack
#   UNKNOWN         its lookup failed, or a branch-only item outside its checkout, or
#                   a ready PR over an item that can't be read
#
# "Below" means earlier in its "## " section: plans list a stack bottom-up. Merged or
# closed items aren't printed but count in the position. A repo whose every lookup
# fails gets one "UNKNOWN: <why>" line and its plans' names.
#
# A repo holding Executor's own worktrees or branches left from finished builds gets
# one "DRIFT: <n> worktrees and <m> branches left from finished builds - fix: repo-tidy.sh <repo>" line under its name, from drift.sh,
# which is also what self-audit.sh -v reports. No line when GitHub can't be asked.
#
# Failures are logged to ~/.engineer-of-wealth/executor/status.log (EOW_HOME overrides
# the root). Takes no arguments; the exit code is always 0.
set -u
unset CDPATH
LC_ALL=C
exec 2>/dev/null

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/status.log"
WORK=""
trap 'rm -rf "$WORK"; exit 0' EXIT

MAX_LOOKUPS=8
ROW_CUT=40
EM=$'\xe2\x80\x94'
BUCKETS=("MERGE NOW" "WAITING ON YOU" "MOVING" "UNKNOWN")
CHECKS_JQ='"\(.state) \(.isDraft) \([.statusCheckRollup[]? | if (.conclusion // "") != "" then .conclusion elif (.state // "") != "" then .state else (.status // "PENDING") end] | join(","))"'

say() { printf '%s\n' "$1"; exit 0; }

log() {
  mkdir -p "$(dirname "$LOG")"
  printf '%s  %s  %s\n' "$(date "+%F %T")" "$PWD" "$1" >> "$LOG"
}

[ "$#" -eq 0 ] || say "STOP: usage: status.sh"

if ! . "$SELF_DIR/plan-items.sh"; then
  log "scripts/plan-items.sh is missing"
  say "UNKNOWN: scripts/plan-items.sh is missing, so no plan can be read"
fi

DRIFT_OK=0
if . "$SELF_DIR/roots.sh" && . "$SELF_DIR/repo-discovery.sh" && . "$SELF_DIR/remote-slug.sh" \
    && . "$SELF_DIR/drift.sh"; then
  DRIFT_OK=1
else
  log "scripts/drift.sh or what it needs is missing"
fi

ALL=$(plan_path --all-live)
case "$ALL" in STOP:*) say "$ALL" ;; esac
[ -n "$ALL" ] || say "No live plans in $(plan_path --root)"

WORK=$(mktemp -d) || { log "cannot make a temp folder"; say "UNKNOWN: cannot make a temp folder"; }

plan_files=(); plan_slugs=(); plan_repos=(); plan_whys=()
while IFS= read -r plan; do
  plan_files[${#plan_files[@]}]=$plan
done <<< "$ALL"

HAVE_GH=1
command -v gh >/dev/null 2>&1 || HAVE_GH=0

lookup_key() { LOOKUP_KEY="${1//\//%}_$2"; }

# Resolves each plan's repo and queues one lookup per distinct PR.
queue_lookups() {
  local p=0 i slug
  while [ "$p" -lt "${#plan_files[@]}" ]; do
    slug=$(plan_path --slug "${plan_files[$p]}")
    case "$slug" in STOP:*) say "$slug" ;; esac
    plan_slugs[$p]=${slug:-local/unknown}
    plan_repos[$p]=""; plan_whys[$p]=""
    case "${plan_slugs[$p]}" in
      local/*) ;;
      *)
        if read_items "${plan_files[$p]}" && [ "${#items[@]}" -gt 0 ]; then
          i=0
          while [ "$i" -lt "${#items[@]}" ]; do
            parse_item "${items[$i]}"; i=$((i+1))
            [ -n "$ITEM_PR" ] && [ "$ITEM_BLOCKED" -eq 0 ] && [ "$ITEM_BUILDING" -eq 0 ] || continue
            if [ -z "${plan_repos[$p]}" ] && [ -z "${plan_whys[$p]}" ]; then
              if resolve_repo "${plan_files[$p]}" "${plan_slugs[$p]}"; then
                plan_repos[$p]=$PLAN_REPO
              else
                plan_whys[$p]=$PLAN_WHY
              fi
            fi
            [ -n "${plan_repos[$p]}" ] || continue
            lookup_key "${plan_repos[$p]}" "$ITEM_PR"
            [ ! -e "$WORK/$LOOKUP_KEY.job" ] || continue
            : > "$WORK/$LOOKUP_KEY.job"
            printf '%s\0%s\0%s\0' "$LOOKUP_KEY" "${plan_repos[$p]}" "$ITEM_PR" >> "$WORK/jobs"
          done
        fi
        ;;
    esac
    p=$((p+1))
  done
}

run_lookups() {
  [ "$HAVE_GH" -eq 1 ] && [ -s "$WORK/jobs" ] || return 0
  export WORK CHECKS_JQ GH_PROMPT_DISABLED=1
  xargs -0 -n 3 -P "$MAX_LOOKUPS" "$BASH" -c '
    gh pr view "$3" --repo "$2" --json state,isDraft,statusCheckRollup --jq "$CHECKS_JQ" \
      >"$WORK/$1.out" 2>"$WORK/$1.err" </dev/null
    echo $? >"$WORK/$1.rc"
    exit 0' _ < "$WORK/jobs"
}

# Sets CI from the check values gh printed, comma-separated.
ci_of() {
  local v pending=0 old_ifs=$IFS
  CI=none
  [ -n "$1" ] || return 0
  IFS=,
  for v in $1; do
    case "$v" in
      FAILURE|ERROR|TIMED_OUT|CANCELLED|ACTION_REQUIRED|STARTUP_FAILURE) CI=red; IFS=$old_ifs; return 0 ;;
      SUCCESS|NEUTRAL|SKIPPED) ;;
      *) pending=1 ;;
    esac
  done
  IFS=$old_ifs
  CI=green
  [ "$pending" -eq 0 ] || CI=running
}

# Sets LOOKUP_STATE, LOOKUP_DRAFT and CI; returns 1 with LOOKUP_WHY set.
read_lookup() {
  local rc="" line="" extra="" checks=""
  LOOKUP_STATE=""; LOOKUP_DRAFT=""; CI=none; LOOKUP_WHY=""
  if [ "$HAVE_GH" -eq 0 ]; then LOOKUP_WHY="gh is not installed"; return 1; fi
  lookup_key "$1" "$2"
  read -r rc < "$WORK/$LOOKUP_KEY.rc"
  if [ "$rc" != 0 ]; then
    IFS= read -r line < "$WORK/$LOOKUP_KEY.err"
    LOOKUP_WHY="gh pr view $2 failed: ${line:-no reason given}"
    return 1
  fi
  read -r LOOKUP_STATE LOOKUP_DRAFT checks extra < "$WORK/$LOOKUP_KEY.out"
  case "$LOOKUP_STATE:$LOOKUP_DRAFT" in
    MERGED:*|CLOSED:*|OPEN:true|OPEN:false) ;;
    *) LOOKUP_WHY="gh pr view $2 gave an unexpected answer: $LOOKUP_STATE $LOOKUP_DRAFT"; return 1 ;;
  esac
  ci_of "$checks"
}

# Sets CUT: at most <max> characters of <text>, counting a UTF-8 sequence as one.
cut_chars() {
  local s=$1 max=$2 i=0 chars=0 c
  CUT=$s
  [ "${#s}" -gt "$max" ] || return 0
  while [ "$i" -lt "${#s}" ]; do
    c=${s:$i:1}
    case "$c" in
      [$'\x80'-$'\xbf']) ;;
      *) [ "$chars" -lt "$max" ] || break; chars=$((chars+1)) ;;
    esac
    i=$((i+1))
  done
  CUT=${s:0:$i}
}

# Sets WIDTH: how many characters <text> shows as.
width_of() {
  local t=${1//[$'\x80'-$'\xbf']/}
  WIDTH=${#t}
}

# The rows of the plan being sorted, parallel arrays.
clear_rows() {
  row_buckets=(); row_nums=(); row_names=(); row_places=(); row_cis=(); row_reviews=(); row_notes=()
  started_labels=(); started_counts=()
}

add_row() {
  local n=${#row_buckets[@]}
  row_buckets[$n]=$1; row_nums[$n]=$NUM; row_names[$n]=$NAME; row_places[$n]=$PLACE
  row_cis[$n]=$CI; row_reviews[$n]=$ITEM_REVIEW; row_notes[$n]=$2
}

note_unknown() {
  log "$PLAN_NAME: $1"
  add_row UNKNOWN "$1"
  BELOW_UNKNOWN=1; BELOW_OPEN=1
}

# A failed lookup. The first reason is what a repo whose lookups all fail says.
note_failed() {
  REPO_FAILED=$((REPO_FAILED+1))
  [ -n "$REPO_WHY" ] || REPO_WHY=$1
  note_unknown "$1"
}

moving()  { add_row MOVING ""; BELOW_OPEN=1; }
waiting() { add_row "WAITING ON YOU" "$ITEM_NOTE"; BELOW_OPEN=1; }
finished() { DONE_COUNT=$((DONE_COUNT+1)); }

# A ready PR or branch: yours to merge, unless what is below it says otherwise.
sort_ready() {
  if [ "$BELOW_UNKNOWN" -eq 1 ]; then
    note_unknown "the item below can't be read"
  elif [ "$BELOW_OPEN" -eq 1 ]; then
    moving
  else
    add_row "MERGE NOW" ""
    BELOW_OPEN=1
  fi
}

# An item with no lookup to go on: its text says where it is.
sort_from_text() {
  if [ "$ITEM_MERGED" -eq 1 ]; then finished; return 0; fi
  case "$ITEM_REVIEW" in
    "open findings") waiting; return 0 ;;
    "in review") moving; return 0 ;;
    ready) sort_ready; return 0 ;;
  esac
  if [ "$NUM" != "-" ]; then
    moving
  elif [ "$ITEM_TICKED" -eq 1 ]; then
    note_unknown "ticked, but its line says no state"
  else
    NOT_STARTED=$((NOT_STARTED+1)); BELOW_OPEN=1
  fi
}

sort_from_github() {
  REPO_LOOKUPS=$((REPO_LOOKUPS+1))
  if ! read_lookup "$PLAN_REPO_ARG" "$ITEM_PR"; then note_failed "$LOOKUP_WHY"; return 0; fi
  case "$LOOKUP_STATE" in MERGED|CLOSED) finished; return 0 ;; esac
  if [ "$ITEM_REVIEW" = "open findings" ]; then
    waiting
  elif [ "$LOOKUP_DRAFT" = true ]; then
    moving
  elif [ "$CI" = red ]; then
    ITEM_NOTE=""
    waiting
  else
    sort_ready
  fi
}

sort_item() {
  CI=none; NUM="-"
  if [ "$ITEM_BLOCKED" -eq 1 ]; then
    ITEM_REVIEW=none
    waiting
    return 0
  fi
  if [ "$ITEM_BUILDING" -eq 1 ]; then ITEM_REVIEW=none; moving; return 0; fi
  [ -z "$ITEM_PR" ] || NUM="#$ITEM_PR"
  if [ "$PLAN_LOCAL" -eq 1 ]; then sort_from_text; return 0; fi
  if [ -n "$ITEM_PR" ]; then
    if [ -n "$PLAN_REPO_WHY" ]; then
      REPO_LOOKUPS=$((REPO_LOOKUPS+1))
      note_failed "$PLAN_REPO_WHY"
    else
      sort_from_github
    fi
    return 0
  fi
  if [ -n "$ITEM_BRANCH" ]; then
    plan_branch_merged "$PLAN_FILE" "$ITEM_BRANCH" "$ITEM_TICKED"
    case "$?" in
      0) finished; return 0 ;;
      2) note_unknown "$PLAN_WHY"; return 0 ;;
    esac
  fi
  sort_from_text
}

flush_not_started() {
  [ "$NOT_STARTED" -gt 0 ] || return 0
  local n=${#started_labels[@]}
  started_labels[$n]=$SECTION_LABEL; started_counts[$n]=$NOT_STARTED
  NOT_STARTED=0
}

# Sets SECTION_LABEL and SECTION_SIZE for the section starting at item <i>.
start_section() {
  local s=${item_sections[$1]} j=$1
  flush_not_started
  SECTION_SIZE=0
  while [ "$j" -lt "${#items[@]}" ] && [ "${item_sections[$j]}" = "$s" ]; do
    SECTION_SIZE=$((SECTION_SIZE+1)); j=$((j+1))
  done
  s=${s%%:*}; s=${s//$EM/-}
  cut_chars "${s:-Plan}" "$ROW_CUT"
  SECTION_LABEL=$CUT
  SECTION_SPOT=0; BELOW_OPEN=0; BELOW_UNKNOWN=0
}

sort_items() {
  local i=0 last="" first=1
  DONE_COUNT=0; NOT_STARTED=0
  while [ "$i" -lt "${#items[@]}" ]; do
    if [ "$first" -eq 1 ] || [ "${item_sections[$i]}" != "$last" ]; then
      start_section "$i"
      last=${item_sections[$i]}; first=0
    fi
    SECTION_SPOT=$((SECTION_SPOT+1))
    PLACE="$SECTION_LABEL $SECTION_SPOT/$SECTION_SIZE"
    parse_item "${items[$i]}"
    NAME=$(item_full_name "${items[$i]}"); NAME=${NAME//$EM/-}
    cut_chars "$NAME" "$ROW_CUT"; NAME=$CUT
    sort_item
    i=$((i+1))
  done
  flush_not_started
}

# pad <text> <column>: <text>, then spaces up to the column, counted in characters.
pad() {
  width_of "$1"
  printf '%s%*s' "$1" "$(($2 - WIDTH))" ""
}

# Appends the sorted plan to BUF, its columns lined up.
render_rows() {
  local i b h num_w=5 name_w=27 place_w=0 ci_w=0 row
  i=0
  while [ "$i" -lt "${#row_buckets[@]}" ]; do
    width_of "${row_nums[$i]}";  [ "$((WIDTH+2))" -le "$num_w" ]   || num_w=$((WIDTH+2))
    width_of "${row_names[$i]}"; [ "$((WIDTH+2))" -le "$name_w" ]  || name_w=$((WIDTH+2))
    width_of "${row_places[$i]}"; [ "$((WIDTH+3))" -le "$place_w" ] || place_w=$((WIDTH+3))
    if [ "${row_buckets[$i]}" != UNKNOWN ]; then
      width_of "CI ${row_cis[$i]}"; [ "$((WIDTH+3))" -le "$ci_w" ] || ci_w=$((WIDTH+3))
    fi
    i=$((i+1))
  done
  for b in "${BUCKETS[@]}"; do
    h=0
    i=0
    while [ "$i" -lt "${#row_buckets[@]}" ]; do
      if [ "${row_buckets[$i]}" = "$b" ]; then
        [ "$h" -eq 1 ] || { BUF="$BUF    $b"$'\n'; h=1; }
        row="      $(pad "${row_nums[$i]}" "$num_w")$(pad "${row_names[$i]}" "$name_w")"
        if [ "$b" = UNKNOWN ]; then
          row="$row${row_places[$i]}"
        else
          row="$row$(pad "${row_places[$i]}" "$place_w")"
          if [ "$b" = "WAITING ON YOU" ] && [ "${row_reviews[$i]}" = none ]; then
            row="${row}CI ${row_cis[$i]}"
          else
            row="$row$(pad "CI ${row_cis[$i]}" "$ci_w")review ${row_reviews[$i]}"
          fi
        fi
        BUF="$BUF$row"$'\n'
        [ -z "${row_notes[$i]}" ] || BUF="$BUF        ${row_notes[$i]}"$'\n'
      fi
      i=$((i+1))
    done
    if [ "$b" = MOVING ] && [ "${#started_labels[@]}" -gt 0 ]; then
      [ "$h" -eq 1 ] || BUF="$BUF    $b"$'\n'
      i=0
      while [ "$i" -lt "${#started_labels[@]}" ]; do
        BUF="$BUF      ${started_labels[$i]}: ${started_counts[$i]} not started"$'\n'
        i=$((i+1))
      done
    fi
  done
}

# Sorts plan <p> into BUF, and its name into NAMES for a repo with nothing to show.
render_plan() {
  PLAN_FILE=${plan_files[$1]}
  PLAN_REPO_ARG=${plan_repos[$1]}
  PLAN_REPO_WHY=${plan_whys[$1]}
  PLAN_LOCAL=0
  case "${plan_slugs[$1]}" in local/*) PLAN_LOCAL=1 ;; esac
  PLAN_NAME=${PLAN_FILE##*/}; PLAN_NAME=${PLAN_NAME%.md}
  if ! read_items "$PLAN_FILE"; then
    log "$PLAN_NAME: cannot read it"
    BUF="$BUF  $PLAN_NAME: cannot read it"$'\n'; NAMES="$NAMES  $PLAN_NAME"$'\n'
    return 0
  fi
  if [ "${#items[@]}" -eq 0 ]; then
    log "$PLAN_NAME: no items"
    BUF="$BUF  $PLAN_NAME: no items"$'\n'; NAMES="$NAMES  $PLAN_NAME"$'\n'
    return 0
  fi
  BUF="$BUF  $PLAN_NAME"$'\n'; NAMES="$NAMES  $PLAN_NAME"$'\n'
  clear_rows
  sort_items
  render_rows
  [ "$DONE_COUNT" -ne "${#items[@]}" ] || BUF="$BUF    finished, not marked: run scripts/plan-sweep.sh"$'\n'
}

# The drift checks run in the background while the plan lookups run, one per repo,
# from a single scan of the roots (each scan costs seconds, and so does each gh call).
has_origin() { git -C "$1" config --get remote.origin.url >/dev/null 2>&1; }

start_drift() {
  local i r s slug want=() found=()
  DRIFT_PIDS=()
  [ "$DRIFT_OK" -eq 1 ] && [ -n "$WORK" ] || return 0
  discover_repos has_origin ${roots[@]+"${roots[@]}"}
  i=0
  for r in ${repos[@]+"${repos[@]}"}; do
    s=$(slug_from_url "$(git -C "$r" config --get remote.origin.url 2>/dev/null)")
    found[$i]="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]') $r"; i=$((i+1))
  done
  i=0
  while IFS= read -r slug; do
    i=$((i+1))
    case "$slug" in ""|local/*) continue ;; esac
    s=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')
    for r in ${found[@]+"${found[@]}"}; do
      [ "${r%% *}" = "$s" ] || continue
      ( repo_drift "${r#* }" && printf '  %s\n' "$DRIFT" > "$WORK/drift-$i" ) &
      DRIFT_PIDS+=($!)
      break
    done
  done <<< "$SLUGS"
}

# Sets DRIFT_LINE: the DRIFT line of the <n>th repo, or nothing.
drift_line() {
  DRIFT_LINE=""
  [ -s "$WORK/drift-$1" ] && DRIFT_LINE=$(cat "$WORK/drift-$1")$'\n'
  return 0
}

render_repo() {
  local slug=$1 n=$2 p=0
  BUF=""; NAMES=""; REPO_LOOKUPS=0; REPO_FAILED=0; REPO_WHY=""
  while [ "$p" -lt "${#plan_files[@]}" ]; do
    [ "${plan_slugs[$p]}" != "$slug" ] || render_plan "$p"
    p=$((p+1))
  done
  drift_line "$n"
  OUT="$OUT$slug"$'\n'"$DRIFT_LINE"
  if [ "$REPO_LOOKUPS" -gt 0 ] && [ "$REPO_FAILED" -eq "$REPO_LOOKUPS" ]; then
    OUT="$OUT  UNKNOWN: $REPO_WHY"$'\n'"$NAMES"
  else
    OUT="$OUT$BUF"
  fi
}

queue_lookups
SLUGS=$(printf '%s\n' "${plan_slugs[@]}" | sort -f | uniq)
start_drift
run_lookups
for pid in ${DRIFT_PIDS[@]+"${DRIFT_PIDS[@]}"}; do wait "$pid"; done

OUT=""
FIRST=1
n=0
while IFS= read -r slug; do
  [ "$FIRST" -eq 1 ] || OUT="$OUT"$'\n'
  FIRST=0
  n=$((n+1))
  render_repo "$slug" "$n"
done <<< "$SLUGS"

printf 'EXECUTOR STATUS\n\n%s' "${OUT//$EM/-}"
exit 0
