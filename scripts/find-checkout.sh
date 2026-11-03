#!/usr/bin/env bash
# find-checkout.sh — finds your local checkout of a pull request's repository,
# so /executor:review works from any folder. No AI.
# When the current folder is already in the PR's repository it says so and does
# nothing else. Otherwise it searches the roots (scripts/roots.sh) two levels
# deep, fetches origin in the checkout it finds and brings the default branch
# up to date: fast-forward only, never over uncommitted work, never switching
# the branch anyone is on. With nothing found it names the clone it would make,
# and makes it only with --clone (the skill asks you first). Read-only on
# GitHub. Every git/gh failure is logged to
# ~/.engineer-of-wealth/executor/checkout.log (EOW_HOME overrides the root)
# and comes back as one line.
#
# A checkout is the PR's repository when its origin URL names the same
# owner/repo on github.com, in any form (git@, https, ssh://), in any case.
# A bare repository and its worktrees are one checkout, opened at the worktree
# that has the default branch, else at its first worktree.
#
# Usage:   find-checkout.sh <owner/repo#N | https://github.com/owner/repo/pull/N> [--clone]
# Output is tagged lines, one per line; the exit code is always 0:
#   PR: owner/repo#N · <url>          — always first, unless STOP
#   HERE: <folder>                    — already in the PR's repo; review here
#   LOOKED: <root> [(missing)]        — nothing found: one per root, in search order
#   CLONE: gh repo clone owner/repo "<first root>/<repo>"
#   NOTE: <one line>                  — a clone made, a fetch that failed (with the fix)
#   CHECKOUT: <folder>                — the folder to review in
#   ALSO: <folder> · <folder>         — the same repo found elsewhere, unused
#   BASE: <branch> · <why>            — what the review compares with, and why:
#                                       <default> when the folder has it checked out
#                                       and level with origin, else origin/<default>
#   RUN: cd "<folder>" && claude "/executor:review <url>"
#   STOP: <one line>                  — could not go on, with the fix
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/checkout.log"

ERR=$(mktemp)
trap 'rm -f "$ERR"' EXIT

tag()      { printf '%s: %s\n' "$1" "$2"; }
stop()     { tag STOP "$1"; exit 0; }
# stderr is kept apart from the reply, so a notice can't end up in a field.
log_fail() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s  %s  %s: %s\n' "$(date "+%F %T")" "$PWD" "$1" "$(head -1 "$ERR")" >> "$LOG" 2>/dev/null
}
first_err() { head -1 "$ERR" | sed -E 's/^(fatal|error): //'; }

ref=""; clone=0
for a in "$@"; do
  case "$a" in --clone) clone=1 ;; *) [ -z "$ref" ] && ref=$a ;; esac
done

shopt -s nocasematch
re_short='^([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)#([1-9][0-9]*)$'
re_url='^https?://(www\.)?github\.com/([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)/pull/([1-9][0-9]*)([/?#].*)?$'
if [[ $ref =~ $re_short ]]; then
  owner=${BASH_REMATCH[1]}; repo=${BASH_REMATCH[2]}; num=${BASH_REMATCH[3]}
elif [[ $ref =~ $re_url ]]; then
  owner=${BASH_REMATCH[2]}; repo=${BASH_REMATCH[3]}; num=${BASH_REMATCH[4]}
else
  shopt -u nocasematch
  stop "find-checkout.sh needs a pull request as owner/repo#N or https://github.com/owner/repo/pull/N, got '$ref'"
fi
shopt -u nocasematch
case "$repo" in . | ..) stop "find-checkout.sh needs a pull request as owner/repo#N or https://github.com/owner/repo/pull/N, got '$ref'" ;; esac
url="https://github.com/$owner/$repo/pull/$num"
tag PR "$owner/$repo#$num · $url"

re_remote='^((ssh|https?|git)://([^@/]+@)?github\.com(:[0-9]+)?/|([^@/:]+@)?github\.com:)([^/]+)/([^/]+)$'
# Whether a remote URL names the PR's repo on github.com.
is_pr_repo() {
  local u=${1%/} hit=1
  shopt -s nocasematch
  if [[ $u =~ $re_remote ]]; then
    [[ ${BASH_REMATCH[6]} == "$owner" && ( ${BASH_REMATCH[7]} == "$repo" || ${BASH_REMATCH[7]} == "$repo.git" ) ]] && hit=0
  fi
  shopt -u nocasematch
  return $hit
}

if origin=$(git config --get remote.origin.url 2>/dev/null) && is_pr_repo "$origin"; then
  top=$(git rev-parse --show-toplevel 2>/dev/null) || top=$PWD
  tag HERE "$top"
  exit 0
fi

. "$SELF_DIR/roots.sh"

# Depth-first over <root>/* and <root>/*/*, which is path order. A bare repo
# and its worktrees share one common git dir: the first one seen stands for all.
found=(); seen="|"
consider() {
  [ -e "$1/.git" ] || { [ -f "$1/HEAD" ] && [ -d "$1/objects" ] && [ -d "$1/refs" ]; } || return 0
  local o common
  o=$(git -C "$1" config --get remote.origin.url 2>/dev/null) && is_pr_repo "$o" || return 0
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=$1
  case "$seen" in *"|$common|"*) return 0 ;; esac
  seen="$seen$common|"
  found+=("$1")
}
for root in "${roots[@]}"; do
  [ -d "$root" ] || continue
  for d in "$root"/*; do
    [ -d "$d" ] || continue
    consider "$d"
    for e in "$d"/*; do [ -d "$e" ] && consider "$e"; done
  done
done

if [ "${#found[@]}" -eq 0 ]; then
  for root in "${roots[@]}"; do
    if [ -d "$root" ]; then tag LOOKED "$root"; else tag LOOKED "$root (missing)"; fi
  done
  target="${roots[0]}/$repo"
  tag CLONE "gh repo clone $owner/$repo \"$target\""
  [ "$clone" -eq 1 ] || exit 0
  [ -e "$target" ] && stop "$target already exists and is not a checkout of $owner/$repo, so nothing was cloned → move it aside, or clone $owner/$repo under another root"
  command -v gh >/dev/null 2>&1 || stop "gh is not installed, so $owner/$repo can't be cloned → install it from https://cli.github.com"
  if ! GIT_TERMINAL_PROMPT=0 gh repo clone "$owner/$repo" "$target" >/dev/null 2>"$ERR"; then
    log_fail "gh repo clone $owner/$repo $target"
    gh auth status >/dev/null 2>&1 || stop "gh is not signed in, so $owner/$repo can't be cloned → run gh auth login"
    stop "gh repo clone $owner/$repo failed: $(first_err) → see $LOG"
  fi
  tag NOTE "cloned $owner/$repo into $target"
  found=("$target")
fi

co=${found[0]}
also=""
if [ "${#found[@]}" -gt 1 ]; then
  also=${found[1]}
  for f in "${found[@]:2}"; do also="$also · $f"; done
fi

cd "$co" 2>/dev/null || stop "can't enter $co → check its permissions"

export GIT_TERMINAL_PROMPT=0
if [ -z "${GIT_SSH_COMMAND:-}${GIT_SSH:-}" ] && ! git config --get core.sshCommand >/dev/null 2>&1; then
  export GIT_SSH_COMMAND="ssh -o BatchMode=yes"
fi
note=""
# A plain `git clone --bare` has no fetch refspec, so origin/<default> would never appear.
fetch=(origin)
git config --get-all remote.origin.fetch >/dev/null 2>&1 || fetch+=('+refs/heads/*:refs/remotes/origin/*')
if ! git fetch --quiet "${fetch[@]}" 2>"$ERR"; then
  log_fail "git fetch origin in $co"
  note="git fetch origin failed in $co ($(first_err)), so this works from what is local → check your connection and GitHub access (gh auth status), see $LOG"
fi

. "$SELF_DIR/default-branch.sh"

# Where the default branch is checked out, and the folder to open. Bare is
# read from the list, not the folder: a bare repo's worktree isn't bare itself.
main_wt=""; first_wt=""; def_wt=""; p=""; p_bare=0; bare=0
while IFS= read -r l; do
  case "$l" in
    "worktree "*) p=${l#worktree }; p_bare=0; [ -n "$main_wt" ] || main_wt=$p ;;
    bare) p_bare=1; [ "$p" = "$main_wt" ] && bare=1 ;;
    "branch refs/heads/$def") [ -d "$p" ] && def_wt=$p ;;
    "") [ "$p_bare" -eq 0 ] && [ -z "$first_wt" ] && [ -d "$p" ] && first_wt=$p ;;
  esac
done < <(git worktree list --porcelain 2>/dev/null; echo)
if [ "$bare" -eq 1 ]; then
  folder=${def_wt:-${first_wt:-$co}}
else
  folder=${main_wt:-$co}
fi

base="origin/$def"; level=0
where=""
[ -n "$def_wt" ] && [ "$def_wt" != "$folder" ] && where=" in $def_wt"
if ! git show-ref --verify --quiet "refs/remotes/origin/$def"; then
  base=$def; why="origin/$def not found locally, $def left as is"
elif ! git show-ref --verify --quiet "refs/heads/$def"; then
  why="no local $def branch"
else
  here=$(git rev-parse "refs/heads/$def"); there=$(git rev-parse "refs/remotes/origin/$def")
  if [ "$here" = "$there" ]; then state=level
  elif git merge-base --is-ancestor "$here" "$there" 2>/dev/null; then state=behind
  else state=ahead; fi

  if [ "$state" = ahead ]; then
    why="$def$where has local commits not on origin, left alone"
  elif [ -z "$def_wt" ]; then
    if [ "$state" = level ]; then why="$def is not checked out, already up to date"
    elif git update-ref "refs/heads/$def" "$there" "$here" 2>"$ERR"; then why="$def is not checked out, its ref fast-forwarded to origin/$def"
    else log_fail "git update-ref refs/heads/$def in $co"; why="$def is not checked out, fast-forwarding its ref failed ($(first_err)), left alone"; fi
  elif [ -n "$(git -C "$def_wt" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    why="$def$where has uncommitted changes, left alone"
  elif [ "$state" = level ]; then
    why="$def$where is up to date with origin/$def"; level=1
  elif git -C "$def_wt" merge --ff-only --quiet "refs/remotes/origin/$def" >/dev/null 2>"$ERR"; then
    why="$def$where fast-forwarded to origin/$def"; level=1
  else
    log_fail "git merge --ff-only origin/$def in $def_wt"
    why="fast-forwarding $def$where failed ($(first_err)), left alone"
  fi
  [ "$level" -eq 1 ] && [ "$folder" = "$def_wt" ] && base=$def
fi

q=$folder
q=${q//\\/\\\\}; q=${q//\"/\\\"}; q=${q//\$/\\\$}; q=${q//\`/\\\`}
tag CHECKOUT "$folder"
[ -n "$also" ] && tag ALSO "$also"
[ -n "$note" ] && tag NOTE "$note"
tag BASE "$base · $why"
tag RUN "cd \"$q\" && claude \"/executor:review $url\""
