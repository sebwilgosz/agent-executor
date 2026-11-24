#!/usr/bin/env bash
# tilde.sh - prints its argument with a leading $HOME swapped for "~/". Any
# other path, and a $HOME with no slash after it, print unchanged. Shared by
# every script that shows a path to a person instead of handing it to another
# program.
tilde() {
  case "$1" in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}
