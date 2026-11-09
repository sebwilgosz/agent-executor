# Sourced by ship.sh and pr-open.sh, so both guard a branch and work out its base
# the same way. The caller sets LOG (its failure log) before sourcing. Provides:
#   stop <reason>            print "STOP: <reason>" and exit 0
#   log_fail <message>       append a line to $LOG
#   guard_branch [branch]    stop unless <branch> (default: the checked-out one)
#                            is a real feature branch on a clean tree; sets
#                            branch, def and cmp (see default-branch.sh)
#   guard_ahead              stop unless the branch has commits beyond $cmp
#   pr_lookup <head> [state] sets pr_json (gh's list for that head, state open|all),
#                            and pr_n, pr_url, pr_base of the open PR, if any
#   resolve_base             sets base: the branch below in a gh stack, else $def
# Call stop from the main shell only, never inside $( ).

stop()     { printf 'STOP: %s\n' "$1"; exit 0; }
log_fail() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s  %s  %s\n' "$(date "+%F %T")" "$PWD" "$1" >> "$LOG"
}

guard_branch() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || stop "not a git repository"

  branch=${1:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}
  [ -n "$branch" ] && [ "$branch" != HEAD ] || stop "detached HEAD — check out a branch first"

  . "$(dirname "${BASH_SOURCE[0]}")/default-branch.sh"

  [ "$branch" = "$def" ] && stop "on the default branch ($def) — switch to a feature branch"

  [ -z "$(git status --porcelain 2>/dev/null)" ] || \
    stop "uncommitted changes — commit (or set aside) them, then try again"
}

guard_ahead() {
  local ahead
  ahead=$(git rev-list --count "$cmp..$branch" 2>/dev/null || echo 0)
  [ "${ahead:-0}" -gt 0 ] || stop "$branch has no commits beyond $def — nothing to ship"
}

pr_lookup() {
  pr_json=""; pr_n=""; pr_url=""; pr_base=""
  local out
  if ! out=$(gh pr list --head "$1" --state "${2:-open}" --json number,url,state,baseRefName 2>&1); then
    log_fail "gh pr list $1: $(printf '%s' "$out" | tail -1)"
    return 1
  fi
  pr_json=$out
  if command -v jq >/dev/null 2>&1; then
    pr_n=$(printf '%s' "$out" | jq -r '[.[]? | select((.state // "OPEN") == "OPEN")][0].number // empty' 2>/dev/null)
    pr_url=$(printf '%s' "$out" | jq -r '[.[]? | select((.state // "OPEN") == "OPEN")][0].url // empty' 2>/dev/null)
    pr_base=$(printf '%s' "$out" | jq -r '[.[]? | select((.state // "OPEN") == "OPEN")][0].baseRefName // empty' 2>/dev/null)
  else
    pr_n=$(printf '%s' "$out" | grep -oE '"number":[0-9]+' | head -1 | grep -oE '[0-9]+')
    pr_url=$(printf '%s' "$out" | grep -oE 'https://[^"]+/pull/[0-9]+' | head -1)
  fi
  return 0
}

# gh stack reports each branch's base as a commit SHA, not a name, so map that
# SHA to the stack branch whose head it is - that branch's name is a valid PR
# base. A base that is the trunk commit (the bottom of the stack) matches no
# branch, so the default branch stands.
resolve_base() {
  base="$def"
  command -v jq >/dev/null 2>&1 && command -v gh >/dev/null 2>&1 || return 0
  local sv below
  if sv=$(gh stack view --json 2>/dev/null) && [ -n "$sv" ]; then
    below=$(printf '%s' "$sv" | jq -r '
      (.branches[]? | select(.isCurrent==true) | .base) as $pb
      | ([.branches[]? | select(.head==$pb) | .name] | first) // empty' 2>/dev/null)
    [ -n "$below" ] && [ "$below" != null ] && base="$below"
  fi
  return 0
}
