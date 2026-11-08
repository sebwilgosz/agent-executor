#!/usr/bin/env bash
# ticket-github.sh — one ticket for one plan item, on GitHub. Wraps every gh call,
# so build never receives a failed tool call (CONTRIBUTING #4).
#   ticket-github.sh <owner/repo> <parent issue number> <title> <body file>
# Creates an issue from the body file and links it as a sub-issue of the parent,
# the spec's own issue. Prints one of:
#   TICKET: #<n> <url>             created and linked
#   TICKET: #<n> <url>, then
#   NOTE: #<n> is not linked under #<parent>: <why>
#                                  created, not linked
#   NOTE: <why>                    nothing was created
# Failures are also logged to ~/.engineer-of-wealth/executor/tickets.log
# (EOW_HOME overrides the root). Exit 0 always.

exec 2>/dev/null
LOG="${EOW_HOME:-$HOME/.engineer-of-wealth}/executor/tickets.log"

log() { mkdir -p "$(dirname "$LOG")" && printf '%s  %s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG"; }
note() { log "$repo" "$1"; echo "NOTE: $1"; exit 0; }

repo=${1:-}; parent=${2:-}; title=${3:-}; body=${4:-}
if [ "$#" -ne 4 ]; then echo "NOTE: usage: ticket-github.sh <owner/repo> <parent issue number> <title> <body file>"; exit 0; fi
case "$parent" in ""|*[!0-9]*) note "the parent issue must be a number, got: $parent" ;; esac
[ -r "$body" ] || note "no body file at $body"

url=$(gh issue create --repo "$repo" --title "$title" --body-file "$body") || note "could not create the ticket in $repo: gh issue create failed"
n=${url##*/}
case "$n" in ""|*[!0-9]*) note "gh issue create printed no issue number: $url" ;; esac
echo "TICKET: #$n $url"

id=$(gh api "repos/$repo/issues/$n" --jq .id) && [ -n "$id" ] \
  && gh api -X POST "repos/$repo/issues/$parent/sub_issues" -F "sub_issue_id=$id" >/dev/null \
  || { log "$repo" "#$n created but not linked under #$parent (sub_issues)"; echo "NOTE: #$n is not linked under #$parent: the sub-issue call failed"; }
exit 0
