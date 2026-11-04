#!/usr/bin/env bash
# plan-path.sh - where build plans live, and which are live. No AI. The only
# code that knows the layout:
#   <plans folder>/<org>/<repo>/<YYYY-MM-DD> - <title>.md
# Plans folder: $EXECUTOR_PLANS, else the first "- <path>" line of "## Plans" in
# $EOW_HOME/executor/config.md (read by scripts/roots.sh), else
# $EOW_HOME/executor/plans. EOW_HOME defaults to ~/.engineer-of-wealth. It must be
# absolute once ~ is expanded: a relative one is a STOP.
# <org>/<repo> is the last two parts of the origin URL, as written there, without
# .git. No usable origin: local/<name>, the folder holding the git common dir, so
# every worktree of a repo shares one folder.
#
# Read-only: it creates nothing. The first write creates a missing folder.
#
# Usage:
#   plan-path.sh [<repo>]              the repo's plans folder
#   plan-path.sh --where               env | config | default
#   plan-path.sh --title <spec file>   the plan title a file name gives
#   plan-path.sh --new <title> [<repo>]  the path for a new plan, free right now
#   plan-path.sh --live [<repo>]       live plans, newest first, one path per line
#   plan-path.sh --summary [<repo>]    what /executor:help prints about plans
#   plan-path.sh --root                the plans folder
#   plan-path.sh --all-live            live plans of every <org>/<repo>, one per line
#   plan-path.sh --slug <plan>         the plan's <org>/<repo>, nothing when it is
#                                      not in a repo's folder of the plans folder
#   plan-path.sh --is-done <plan>      done | live
#   plan-path.sh --host [<repo>]       the origin's host, nothing when it names none;
#                                      the folder drops it, so a plan records any
#                                      but github.com in a "Host: <host>" line
# A plan is live until a line before its first "## " heading says
# "Status: done <YYYY-MM-DD>". <repo> defaults to the current folder.
#
# The exit code is always 0. A failure, like no git repository, is one line:
#   STOP: <one-line reason>
set -u
unset CDPATH
LC_ALL=C

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"

stop() { printf 'STOP: %s\n' "$1"; exit 0; }

trim() {
  local s=$1
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

expand_home() {
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Sets PLANS_ROOT and PLANS_SOURCE.
plans_root() {
  section_paths=()
  . "$SELF_DIR/roots.sh" 2>/dev/null && config_section Plans 2>/dev/null
  if [ -n "${EXECUTOR_PLANS:-}" ]; then
    PLANS_ROOT=$(expand_home "$EXECUTOR_PLANS"); PLANS_SOURCE=env
  elif [ -n "${section_paths[0]:-}" ]; then
    PLANS_ROOT=${section_paths[0]}; PLANS_SOURCE=config
  else
    PLANS_ROOT="$EOW/executor/plans"; PLANS_SOURCE=default
  fi
  while [ "$PLANS_ROOT" != "/" ] && [ "${PLANS_ROOT%/}" != "$PLANS_ROOT" ]; do
    PLANS_ROOT=${PLANS_ROOT%/}
  done
}

# Prints <owner>/<name> from a remote URL, nothing when it doesn't hold both.
slug_from_url() {
  local p owner name
  case "$1" in
    *://*/*) p=${1#*://}; p=${p#*/} ;;
    *://*) return 0 ;;
    *:*) p=${1#*:} ;;
    *) p=$1 ;;
  esac
  while [ "${p%/}" != "$p" ]; do p=${p%/}; done
  case "$p" in */*) ;; *) return 0 ;; esac
  name=${p##*/}; name=${name%.git}
  p=${p%/*}; owner=${p##*/}
  case "$owner" in ""|.|..) return 0 ;; esac
  case "$name" in ""|.|..) return 0 ;; esac
  printf '%s/%s' "$owner" "$name"
}

# Prints the host of a remote URL, nothing when it names none. An SSH one may name
# an alias: ssh -G reads the real host from the ssh config, with no network.
host_from_url() {
  local h real via_ssh=1
  case "$1" in
    ssh://*|git+ssh://*) h=${1#*://} ;;
    *://*) h=${1#*://}; via_ssh=0 ;;
    *:*) h=${1%%:*} ;;
    *) return 0 ;;
  esac
  h=${h%%/*}; h=${h##*@}; h=${h%%:*}
  case "$h" in [[:alnum:]]*) ;; *) return 0 ;; esac
  if [ "$via_ssh" -eq 1 ]; then
    real=$(ssh -G "$h" 2>/dev/null </dev/null | awk '$1 == "hostname" { print $2; exit }')
    h=${real:-$h}
  fi
  printf '%s\n' "$h"
}

# Prints local/<name> from the absolute git common dir.
slug_local() {
  local name=${1##*/} parent
  case "$name" in
    .git|.bare) parent=${1%/*}; name=${parent##*/} ;;
  esac
  name=${name%.git}
  printf 'local/%s' "${name:-repo}"
}

# Sets REPO_FOLDER; returns 1 when <repo> isn't in a git repository.
repo_folder() {
  local common slug
  common=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$common" in /*) ;; *) common="$1/$common" ;; esac
  common=$(cd -P "$common" 2>/dev/null && pwd) || return 1
  slug=$(slug_from_url "$(git -C "$1" config --get remote.origin.url 2>/dev/null)")
  [ -n "$slug" ] || slug=$(slug_local "$common")
  plans_root
  REPO_FOLDER="$PLANS_ROOT/$slug"
}

root_is_absolute() {
  case "$PLANS_ROOT" in /*) return 0 ;; *) return 1 ;; esac
}

require_repo() {
  repo_folder "$1" || stop "not a git repository: $1"
  root_is_absolute || stop "the plans folder must be absolute: $PLANS_ROOT"
}

is_done() {
  local l re='^Status: done [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$'
  [ -r "$1" ] || return 1
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in "## "*) return 1 ;; esac
    [[ $l =~ $re ]] && return 0
  done < "$1"
  return 1
}

# Prints the live plans of REPO_FOLDER. The dated names sort oldest first.
live_plans() {
  local files=() i f
  [ -d "$REPO_FOLDER" ] || return 0
  shopt -s nullglob
  files=("$REPO_FOLDER"/*.md)
  shopt -u nullglob
  i=${#files[@]}
  while [ "$i" -gt 0 ]; do
    i=$((i-1)); f=${files[$i]}
    [ -f "$f" ] || continue
    is_done "$f" || printf '%s\n' "$f"
  done
}

# Prints the live plans of every <org>/<repo>. Globs, so a linked-in folder counts.
all_live() {
  local dirs=() d
  shopt -s nullglob
  dirs=("$PLANS_ROOT"/*/*/)
  shopt -u nullglob
  [ "${#dirs[@]}" -gt 0 ] || return 0
  for d in "${dirs[@]}"; do
    REPO_FOLDER=${d%/}
    live_plans
  done
}

# Prints <org>/<repo> for a plan: its folder as written, then with links resolved.
slug_of_plan() {
  local dir root rel flag
  for flag in -L -P; do
    dir=$(cd "$flag" "$(dirname "$1")" 2>/dev/null && pwd "$flag") || return 0
    root=$(cd "$flag" "$PLANS_ROOT" 2>/dev/null && pwd "$flag") || return 0
    rel=${dir#"$root"/}
    [ "$rel" != "$dir" ] || continue
    case "$rel" in
      */*/*) ;;
      */*) printf '%s\n' "$rel"; return 0 ;;
    esac
  done
}

title_from_file() {
  local t=${1##*/}
  t=${t%.md}; t=${t#spec - }; t=${t% - spec}
  [ -n "$t" ] || stop "no title in that file name: $1"
  printf '%s\n' "$t"
}

new_plan() {
  local t base path n=2
  t=$(trim "$1"); t=${t#Spec:}; t=$(trim "$t")
  [ -n "$t" ] || stop "a new plan needs a title"
  t=${t//[\/:[:cntrl:]]/-}
  base="$REPO_FOLDER/$(date +%F) - $t"
  path="$base.md"
  while [ -e "$path" ] || [ -L "$path" ]; do
    path="$base $n.md"; n=$((n+1))
  done
  printf '%s\n' "$path"
}

summary() {
  local live first=1 l
  plans_root
  printf 'PLANS:\n  folder     %s (%s)\n' "$PLANS_ROOT" "$PLANS_SOURCE"
  if ! root_is_absolute; then
    printf '  this repo  the plans folder must be absolute\n'
  elif repo_folder "$1"; then
    printf '  this repo  %s\n' "$REPO_FOLDER"
    live=$(live_plans)
    if [ -z "$live" ]; then
      printf '  live       none\n'
    else
      while IFS= read -r l; do
        if [ "$first" -eq 1 ]; then printf '  live       %s\n' "$l"; first=0
        else printf '             %s\n' "$l"; fi
      done <<< "$live"
    fi
  else
    printf '  this repo  not a git repository\n'
  fi
  printf '  /executor:init sets where plans live\n'
}

case "${1:-}" in
  --where)
    plans_root
    printf '%s\n' "$PLANS_SOURCE"
    ;;
  --title)
    [ -n "${2:-}" ] || stop "usage: plan-path.sh --title <spec file>"
    title_from_file "$2"
    ;;
  --new)
    [ "$#" -ge 2 ] || stop "usage: plan-path.sh --new <title> [<repo>]"
    require_repo "${3:-.}"
    new_plan "$2"
    ;;
  --live)
    require_repo "${2:-.}"
    live_plans
    ;;
  --summary)
    summary "${2:-.}"
    ;;
  --root)
    plans_root
    root_is_absolute || stop "the plans folder must be absolute: $PLANS_ROOT"
    printf '%s\n' "$PLANS_ROOT"
    ;;
  --all-live)
    plans_root
    root_is_absolute || stop "the plans folder must be absolute: $PLANS_ROOT"
    all_live
    ;;
  --slug)
    [ -n "${2:-}" ] || stop "usage: plan-path.sh --slug <plan>"
    plans_root
    root_is_absolute || stop "the plans folder must be absolute: $PLANS_ROOT"
    slug_of_plan "$2"
    ;;
  --is-done)
    [ -n "${2:-}" ] || stop "usage: plan-path.sh --is-done <plan>"
    if is_done "$2"; then printf 'done\n'; else printf 'live\n'; fi
    ;;
  --host)
    require_repo "${2:-.}"
    host_from_url "$(git -C "${2:-.}" config --get remote.origin.url 2>/dev/null)"
    ;;
  -*)
    stop "unknown option: $1"
    ;;
  *)
    require_repo "${1:-.}"
    printf '%s\n' "$REPO_FOLDER"
    ;;
esac
exit 0
