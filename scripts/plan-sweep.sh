#!/usr/bin/env bash
# plan-sweep.sh - marks every finished plan in the plans folder done. No AI.
# Walks every <org>/<repo> of the folder scripts/plan-path.sh resolves and runs
# scripts/plan-state.sh on each live plan. A plan already marked is left alone. An
# item with only a branch needs a checkout, so a plan with one is UNKNOWN unless
# the sweep runs from that repo.
#
# Usage: plan-sweep.sh [--dry-run]     --dry-run changes nothing
# Prints one line per live plan, the exit code is always 0:
#   marked: <plan> | <state line>
#   would mark: <plan> | <state line>
#   open: <plan> | <state line>
#   unknown: <plan> | <state line>
# or "No live plans in <folder>", or a STOP: line from plan-path.sh as it is.
set -u
unset CDPATH

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)

MARK=--mark
case "${1:-}" in
  "") ;;
  --dry-run) MARK="" ;;
  *) printf 'STOP: usage: plan-sweep.sh [--dry-run]\n'; exit 0 ;;
esac

PLANS=$("$BASH" "$SELF_DIR/plan-path.sh" --all-live 2>/dev/null)
case "$PLANS" in
  STOP:*) printf '%s\n' "$PLANS"; exit 0 ;;
esac

if [ -z "$PLANS" ]; then
  printf 'No live plans in %s\n' "$("$BASH" "$SELF_DIR/plan-path.sh" --root 2>/dev/null)"
  exit 0
fi

while IFS= read -r plan; do
  state=$("$BASH" "$SELF_DIR/plan-state.sh" $MARK "$plan" 2>/dev/null </dev/null)
  case "$state" in
    DONE*) if [ -n "$MARK" ]; then label=marked; else label="would mark"; fi ;;
    OPEN*) label=open ;;
    STOP:*) printf '%s\n' "$state"; exit 0 ;;
    *) label=unknown ;;
  esac
  printf '%s: %s | %s\n' "$label" "$plan" "$state"
done <<< "$PLANS"
exit 0
