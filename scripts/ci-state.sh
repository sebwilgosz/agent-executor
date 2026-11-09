# Sourced by status.sh and ci-checks.sh, so both read the state of a check the same way.
# Provides:
#   CHECK_VALUE_JQ   a jq expression: one check (a check run or a commit status) to its
#                    value - the conclusion, else the state, else the status
#   CHECKS_JQ        a jq expression over `gh pr view --json state,isDraft,statusCheckRollup`:
#                    "<state> <isDraft> <values, comma-separated>"
#   check_kind <v>   sets KIND to red, ok or pending for one value
#   ci_of <values>   sets CI to none, red, running or green for comma-separated values

CHECK_VALUE_JQ='if (.conclusion // "") != "" then .conclusion elif (.state // "") != "" then .state else (.status // "PENDING") end'
CHECKS_JQ='"\(.state) \(.isDraft) \([.statusCheckRollup[]? | '"$CHECK_VALUE_JQ"'] | join(","))"'

check_kind() {
  case "$1" in
    FAILURE|ERROR|TIMED_OUT|CANCELLED|ACTION_REQUIRED|STARTUP_FAILURE) KIND=red ;;
    SUCCESS|NEUTRAL|SKIPPED) KIND=ok ;;
    *) KIND=pending ;;
  esac
}

ci_of() {
  local v pending=0 old_ifs=$IFS
  CI=none
  [ -n "$1" ] || return 0
  IFS=,
  for v in $1; do
    check_kind "$v"
    case "$KIND" in
      red) CI=red; IFS=$old_ifs; return 0 ;;
      pending) pending=1 ;;
    esac
  done
  IFS=$old_ifs
  CI=green
  [ "$pending" -eq 0 ] || CI=running
}
