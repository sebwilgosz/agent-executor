#!/usr/bin/env bash
# plan-state.sh - is this build plan finished? No AI.
# An item is a "- [ ]" or "- [x]" line. It is finished when its PR ("PR #n" in the
# text after its spec link) is merged or closed, or, with no PR number, when its
# branch ("branch <name>" there) is an ancestor of the default branch. A blocked
# item (a stop sign) is unfinished: any PR it mentions is part of its question. So
# is one being built (a hammer): its new branch sits at the default branch's tip.
# An unticked item whose branch doesn't exist yet is not started, so unfinished; a
# ticked item's missing branch can't be told apart from a deleted one: UNKNOWN.
#
# The PR is looked up in the plan's own repo, from its folder, so this works from
# anywhere. The folder drops the host: it comes from this folder's origin when this
# is a checkout of the plan's repo, then the plan's "Host: <host>" line, then gh's
# default host. A branch needs a checkout: the current folder has to be in the plan's
# repo. Every gh and git call is wrapped; a failure is logged to
# ~/.engineer-of-wealth/executor/plan-state.log (EOW_HOME overrides the root) and
# is an UNKNOWN, which never marks anything. One failed item makes the whole plan
# UNKNOWN: a count built on a guess would be wrong.
#
# Usage:
#   plan-state.sh <plan>          read-only
#   plan-state.sh --mark <plan>   the same, and on DONE adds "Status: done <today>"
#                                 to the header, once
# Prints one line; the exit code is always 0:
#   NONE                              no plan
#   DONE <n> items[ (closed unmerged: PR #n <item>, ...)]
#   OPEN <k> of <n>: <first unfinished item, short>[ (closed unmerged: ...)]
#   UNKNOWN: <why>
#   STOP: <reason>                    from plan-path.sh, as it is
set -u
unset CDPATH
LC_ALL=C

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/plan-state.log"

say() { printf '%s\n' "$1"; exit 0; }

# Logs the failure and ends with the plain note.
unknown() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s  %s  %s\n' "$(date "+%F %T")" "$PWD" "$1" >> "$LOG" 2>/dev/null
  say "UNKNOWN: $1"
}

MARK=0
case "${1:-}" in
  --mark) MARK=1; shift ;;
  -*) say "UNKNOWN: usage: plan-state.sh [--mark] <plan>" ;;
esac

PLAN="${1:-}"
[ -n "$PLAN" ] && [ -f "$PLAN" ] || say "NONE"
[ -r "$PLAN" ] || unknown "cannot read $PLAN"

. "$SELF_DIR/plan-items.sh" 2>/dev/null \
  || unknown "scripts/plan-items.sh is missing, so $PLAN cannot be read"

TEXT_RE='[^[:space:]]'

read_items "$PLAN" || unknown "cannot read $PLAN"
[ "${#items[@]}" -gt 0 ] || unknown "no items in $PLAN"

# The plans folder's own STOP goes out as it is, before any lookup.
SLUG=$(plan_path --slug "$PLAN")
case "$SLUG" in STOP:*) say "$SLUG" ;; esac

ERR=$(mktemp) || unknown "cannot make a temp file"
TMP_PLAN=""
trap 'rm -f "$ERR" "$TMP_PLAN"' EXIT

# Sets REPO_ARG once, what gh gets as --repo.
REPO_ARG=""
set_repo_arg() {
  [ -z "$REPO_ARG" ] || return 0
  resolve_repo "$PLAN" "$SLUG" || unknown "$PLAN_WHY"
  REPO_ARG=$PLAN_REPO
}

# Sets PR_STATE to MERGED, CLOSED or OPEN, or ends with UNKNOWN.
pr_state() {
  local s
  case "$SLUG" in
    ""|local/*) unknown "PR #$1 on a plan with no GitHub repo: $PLAN" ;;
  esac
  command -v gh >/dev/null 2>&1 || unknown "gh is not installed, so PR #$1 cannot be read"
  set_repo_arg
  s=$(GH_PROMPT_DISABLED=1 gh pr view "$1" --repo "$REPO_ARG" --json state --jq .state 2>"$ERR" </dev/null) \
    || unknown "gh pr view $1 failed: $(head -1 "$ERR")"
  case "$s" in
    MERGED|CLOSED|OPEN) PR_STATE=$s ;;
    *) unknown "gh pr view $1 gave an unexpected state: $(printf '%s' "$s" | head -1)" ;;
  esac
}

# Returns 0 when the branch is merged, 1 when it isn't; ends with UNKNOWN when it
# can't tell.
branch_merged() {
  plan_branch_merged "$PLAN" "$1" "$2"
  case "$?" in
    0) return 0 ;;
    1) return 1 ;;
    *) unknown "$PLAN_WHY" ;;
  esac
}

TOTAL=${#items[@]}
OPEN_COUNT=0
FIRST_OPEN=""
CLOSED=""
note_open() { OPEN_COUNT=$((OPEN_COUNT+1)); [ -n "$FIRST_OPEN" ] || FIRST_OPEN=$(item_name "$1"); }

for item in "${items[@]}"; do
  parse_item "$item"
  if [ "$ITEM_BLOCKED" -eq 1 ] || [ "$ITEM_BUILDING" -eq 1 ]; then
    note_open "$item"
    continue
  fi
  if [ -n "$ITEM_PR" ]; then
    n=$ITEM_PR
    pr_state "$n"
    case "$PR_STATE" in
      MERGED) ;;
      CLOSED) CLOSED="${CLOSED:+$CLOSED, }PR #$n $(item_name "$item")" ;;
      *) note_open "$item" ;;
    esac
  elif [ -n "$ITEM_BRANCH" ]; then
    branch_merged "$ITEM_BRANCH" "$ITEM_TICKED" || note_open "$item"
  else
    note_open "$item"
  fi
done

SUFFIX=""
[ -z "$CLOSED" ] || SUFFIX=" (closed unmerged: $CLOSED)"

[ "$OPEN_COUNT" -eq 0 ] || say "OPEN $OPEN_COUNT of $TOTAL: $FIRST_OPEN$SUFFIX"

# Puts the line after the header's last text, above the blank lines before the
# first "## " heading or item. cat, not mv: a linked-in plan stays a link.
mark_done() {
  local lines=() l i end ins
  [ "$(plan_path --is-done "$PLAN")" = done ] && return 0
  while IFS= read -r l || [ -n "$l" ]; do
    lines[${#lines[@]}]=$l
  done < "$PLAN"
  end=${#lines[@]}
  i=0
  while [ "$i" -lt "$end" ]; do
    l=${lines[$i]}
    case "$l" in "## "*) break ;; esac
    [[ $l =~ $ITEM_RE ]] && break
    i=$((i+1))
  done
  end=$i
  ins=$end
  while [ "$ins" -gt 0 ]; do
    [[ ${lines[$((ins-1))]} =~ $TEXT_RE ]] && break
    ins=$((ins-1))
  done
  TMP_PLAN=$(mktemp) || return 1
  {
    i=0
    while [ "$i" -lt "$ins" ]; do printf '%s\n' "${lines[$i]}"; i=$((i+1)); done
    printf 'Status: done %s\n' "$(date +%F)"
    while [ "$i" -lt "${#lines[@]}" ]; do printf '%s\n' "${lines[$i]}"; i=$((i+1)); done
  } > "$TMP_PLAN" || return 1
  { cat "$TMP_PLAN" > "$PLAN"; } 2>/dev/null
}

if [ "$MARK" -eq 1 ]; then
  mark_done || unknown "every item is finished, but $PLAN cannot be marked"
fi
say "DONE $TOTAL items$SUFFIX"
