#!/usr/bin/env bash
# pull-repos.sh - brings the default branch of local repos up to date. No AI.
# Searches the roots (scripts/roots.sh) two levels deep, skipping folders named
# Archive; a bare repo or a clone and all its worktrees count once. Asks each
# remote what its default branch is, then only ever fast-forwards: never stash,
# reset, force, rebase, clean, delete a branch, remove a worktree or push, and
# never touch a feature-branch worktree.
#
#   Bare, a worktree on the default          fast-forward in that worktree
#   Bare, no worktree on the default         update or create the branch ref
#   Plain, on the default                    fast-forward
#   Plain, elsewhere, clean, unused          switch to the default, fast-forward
#   Plain, elsewhere, changes or in use      stay, update the ref, name it
#   Plain, detached                          stay, update the ref, name it
#   Plain, elsewhere, default in a worktree  fast-forward there, stay, name it
#
# Usage: pull-repos.sh [group]
# With no group, every repo. A group is a "## Group <name>" section in
# $EOW_HOME/executor/config.md (EOW_HOME defaults to ~/.engineer-of-wealth), each
# "- <line>" an owner or an owner/repo, ignoring case. A name with no such section
# matches any repo whose owner or repo name equals it, ignoring case.
#
# Prints nothing until the end, then one short list. Full git output and that list
# go to pull.log in the same folder, overwritten each run. The exit code is always 0.
set -u
unset CDPATH

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
# A working directory in a repo would count as a process using that folder.
cd / || exit 0

STATE="${EOW_HOME:-$HOME/.engineer-of-wealth}/executor"
LOG="$STATE/pull.log"
TAB=$'\t'
NL=$'\n'

WORK=$(mktemp -d) || { printf 'Could not pull: no temporary folder.\n'; exit 0; }
trap 'rm -rf "$WORK"' EXIT
exec 2>"$WORK/script.log"

mkdir -p "$STATE"
: > "$LOG"

. "$SELF_DIR/roots.sh"
. "$SELF_DIR/repo-discovery.sh"
. "$SELF_DIR/remote-slug.sh"

# Sessions run in these repos, so a status check must not take their index lock.
export GIT_OPTIONAL_LOCKS=0

same_text() {
  local hit=1
  shopt -s nocasematch
  [[ $1 == "$2" ]] && hit=0
  shopt -u nocasematch
  return $hit
}

tilde() {
  case "$1" in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

is_repo() {
  local r
  for r in "${roots[@]}"; do
    case "$1" in "$r"/Archive|"$r"/Archive/*|"$r"/*/Archive) return 1 ;; esac
  done
  git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

looked_in() {
  local r list=""
  for r in "${roots[@]}"; do
    list="$list${list:+, }$(tilde "$r")"
  done
  printf '%s' "$list"
}

# The final word, on the screen and in pull.log.
say() {
  cat "$WORK/script.log" >> "$LOG"
  printf '%s\n' "$1"
  printf '%s\n' "$1" >> "$LOG"
}

# Whether the group selects a repo of this <owner>/<name>.
group_selects() {
  local slug=$1 owner=${1%/*} name=${1##*/} i
  [ -n "$slug" ] || return 1
  if [ "$group_has_section" -eq 0 ]; then
    same_text "$owner" "$group" || same_text "$name" "$group"
    return
  fi
  i=0
  while [ "$i" -lt "${#group_lines[@]}" ]; do
    case "${group_lines[$i]}" in
      */*) same_text "$slug" "${group_lines[$i]}" && return 0 ;;
      *) same_text "$owner" "${group_lines[$i]}" && return 0 ;;
    esac
    i=$((i+1))
  done
  return 1
}

# ---------------------------------------------------------- updating one repo
# update_repo runs in its own subshell and shares nothing with the others: all it
# leaves is its two files, the result and the git output. Result: a first line
# pulled | failed | left, and a second line with the reason.

repo_result() { printf '%s\n%s\n' "$1" "$2" > "$result"; }

run_git() {
  printf '$ git %s\n' "$*"
  git "$@"
}

# Sets def and reachable; told is 1 when the remote itself named the branch.
# Returns 1 when the remote answers with no HEAD at all.
remote_default() {
  local out l has_head=0
  def=""; told=0; reachable=1
  printf '$ git ls-remote --symref origin HEAD\n'
  if out=$(git -C "$folder" ls-remote --symref origin HEAD); then
    printf '%s\n' "$out"
    [ -n "$out" ] || return 1
    while IFS= read -r l; do
      case "$l" in
        "ref: refs/heads/"*"$TAB"HEAD)
          l=${l#ref: refs/heads/}; def=${l%"$TAB"HEAD}; told=1; has_head=1 ;;
        *"$TAB"HEAD) has_head=1 ;;
      esac
    done <<< "$out"
    [ "$has_head" -eq 1 ] || return 1
  else
    reachable=0
  fi
  [ -n "$def" ] || def=$(cd "$folder" && . "$SELF_DIR/default-branch.sh" && printf '%s' "$def")
  printf 'default branch: %s\n' "$def"
  return 0
}

# Sets main_wt, is_bare, main_branch, def_wt (a live worktree on the default) and
# stale_def (1 when an entry on the default points to a folder that is gone).
read_worktrees() {
  local l p="" b
  main_wt=""; is_bare=0; main_branch=""; def_wt=""; stale_def=0
  while IFS= read -r l; do
    case "$l" in
      "worktree "*) p=${l#worktree }; [ -n "$main_wt" ] || main_wt=$p ;;
      bare) [ "$p" = "$main_wt" ] && is_bare=1 ;;
      "branch refs/heads/"*)
        b=${l#branch refs/heads/}
        [ "$p" = "$main_wt" ] && main_branch=$b
        if [ "$b" = "$def" ]; then
          if [ -e "$p/.git" ]; then def_wt=$p; else stale_def=1; fi
        fi ;;
    esac
  done < <(git -C "$folder" worktree list --porcelain)
  [ -n "$main_wt" ] || main_wt=$folder
}

in_progress() {
  local gd
  gd=$(git -C "$1" rev-parse --absolute-git-dir) || return 0
  [ -e "$gd/MERGE_HEAD" ] || [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]
}

has_changes() {
  [ -n "$(git -C "$1" status --porcelain)" ]
}

# True when a process has its working directory in the folder, or nobody can say.
folder_in_use() {
  local dir out l
  dir=$(cd -P "$1" && pwd) || return 0
  out=$(lsof -d cwd -Fn -n -P)
  [ -n "$out" ] || return 0
  while IFS= read -r l; do
    case "$l" in "n$dir"|"n$dir"/*) return 0 ;; esac
  done <<< "$out"
  return 1
}

# Fast-forwards the default branch's ref with no checkout. A non-forced refspec, so
# git refuses anything else, and refuses a branch a live worktree holds.
update_default_ref() {
  [ "$local_sha" != "$origin_sha" ] || return 0
  # Git would refuse for a worktree entry whose folder is gone, and that entry is to be ignored.
  local head_ok=""
  [ "$stale_def" -eq 0 ] || head_ok=--update-head-ok
  run_git -C "$main_wt" fetch --refmap= $head_ok origin "refs/heads/$def:refs/heads/$def" || return 1
  [ -n "$local_sha" ] || run_git -C "$main_wt" branch --set-upstream-to="origin/$def" "$def"
  return 0
}

update_repo() {
  local folder=$1 result=$2 log=$3
  local def told reachable main_wt is_bare main_branch def_wt stale_def local_sha origin_sha where
  exec >"$log" 2>&1

  if ! remote_default; then
    repo_result failed "could not update"; return
  fi
  if ! git check-ref-format --branch "$def" >/dev/null; then
    repo_result failed "could not update"; return
  fi
  # The tracking ref follows the remote as a default fetch refspec would, with its
  # plus. A plain bare clone has no such refspec, so this names it. --refmap= keeps a
  # forced refspec in the repo's own config, as in a mirror, from moving local branches.
  if ! run_git -C "$folder" fetch --refmap= origin "+refs/heads/$def:refs/remotes/origin/$def"; then
    if [ "$reachable" -eq 1 ]; then
      repo_result failed "could not update"
    else
      repo_result failed "could not reach origin"
    fi
    return
  fi
  [ "$told" -eq 0 ] || run_git -C "$folder" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$def"

  read_worktrees
  if { [ "$is_bare" -eq 0 ] && in_progress "$main_wt"; } || { [ -n "$def_wt" ] && in_progress "$def_wt"; }; then
    repo_result failed "could not update"; return
  fi

  origin_sha=$(git -C "$main_wt" rev-parse --quiet --verify "refs/remotes/origin/$def")
  local_sha=$(git -C "$main_wt" rev-parse --quiet --verify "refs/heads/$def")
  if [ -z "$origin_sha" ]; then
    repo_result failed "could not update"; return
  fi
  if [ -n "$local_sha" ] && ! git -C "$main_wt" merge-base --is-ancestor "$local_sha" "$origin_sha"; then
    repo_result failed "diverged from origin"; return
  fi

  if [ -n "$def_wt" ]; then
    if [ "$local_sha" != "$origin_sha" ] && ! run_git -C "$def_wt" merge --ff-only "refs/remotes/origin/$def"; then
      if has_changes "$def_wt"; then
        repo_result failed "local changes in the way"
      else
        repo_result failed "could not update"
      fi
      return
    fi
    if [ "$is_bare" -eq 0 ] && [ "$def_wt" != "$main_wt" ]; then
      where="on ${main_branch:-detached HEAD}"
      repo_result left "$where, $def in a worktree, $def updated"
    else
      repo_result pulled ""
    fi
    return
  fi

  if [ "$is_bare" -eq 1 ]; then
    if update_default_ref; then repo_result pulled ""; else repo_result failed "could not update"; fi
    return
  fi

  if [ -z "$main_branch" ]; then
    where="on detached HEAD"
  elif has_changes "$main_wt"; then
    where="on $main_branch, local changes"
  elif folder_in_use "$main_wt"; then
    where="on $main_branch, in use"
  else
    where=""
  fi
  if ! update_default_ref; then
    repo_result failed "could not update"; return
  fi
  if [ -n "$where" ]; then
    repo_result left "$where, $def updated"; return
  fi
  if [ "$stale_def" -eq 1 ]; then
    run_git -C "$main_wt" switch --ignore-other-worktrees "$def"
  else
    run_git -C "$main_wt" switch "$def"
  fi
  if [ $? -eq 0 ]; then repo_result pulled ""; else repo_result failed "could not update"; fi
}

# ------------------------------------------------------------------ the run
group=${1:-}
group_has_section=0
group_lines=()
if [ -n "$group" ]; then
  config_section "Group $group"
  group_has_section=$section_found
  i=0
  while [ "$i" -lt "${#section_paths[@]}" ]; do
    group_lines+=("${section_paths[$i]}")
    i=$((i+1))
  done
fi

discover_repos is_repo "${roots[@]}"

picked=(); names=(); skipped=0
i=0
while [ "$i" -lt "${#repos[@]}" ]; do
  folder=${repos[$i]}
  i=$((i+1))
  origin=$(git -C "$folder" config --get remote.origin.url)
  if [ -z "$origin" ]; then
    [ -n "$group" ] || skipped=$((skipped+1))
    continue
  fi
  slug=$(slug_from_url "$origin")
  if [ -n "$group" ] && ! group_selects "$slug"; then
    continue
  fi
  name=${slug##*/}
  [ -n "$name" ] || { name=${folder##*/}; name=${name%.git}; }
  picked+=("$folder")
  names+=("$name")
done
total=${#picked[@]}

if [ "$total" -eq 0 ]; then
  if [ -n "$group" ]; then
    say "No repos match $group (looked in $(looked_in))."
  elif [ "$skipped" -gt 0 ]; then
    say "No repos to pull. $skipped skipped, no remote."
  else
    say "No repos found (looked in $(looked_in))."
  fi
  exit 0
fi

i=0
while [ "$i" -lt "$total" ]; do
  ( update_repo "${picked[$i]}" "$WORK/$i.result" "$WORK/$i.log" )
  i=$((i+1))
done

# ------------------------------------------------------------- the final list
# Two repos of one name can't be told apart by it, so they show their folders.
shown=()
i=0
while [ "$i" -lt "$total" ]; do
  shown[$i]=${names[$i]}
  j=0
  while [ "$j" -lt "$total" ]; do
    if [ "$j" -ne "$i" ] && same_text "${names[$i]}" "${names[$j]}"; then
      shown[$i]=$(tilde "${picked[$i]}")
      break
    fi
    j=$((j+1))
  done
  i=$((i+1))
done

pulled=0; unreachable=0; failed_lines=""; left_lines=""
i=0
while [ "$i" -lt "$total" ]; do
  status=failed; detail="could not update"
  if [ -s "$WORK/$i.result" ]; then
    { IFS= read -r status; IFS= read -r detail; } < "$WORK/$i.result"
  fi
  case "$status" in
    pulled) pulled=$((pulled+1)) ;;
    left)
      pulled=$((pulled+1))
      left_lines="$left_lines- ${shown[$i]}: $detail$NL" ;;
    *)
      failed_lines="$failed_lines- ${shown[$i]}: $detail$NL"
      [ "$detail" != "could not reach origin" ] || unreachable=$((unreachable+1)) ;;
  esac
  {
    printf '== %s\n' "${picked[$i]}"
    cat "$WORK/$i.log"
    printf 'result: %s %s\n\n' "$status" "$detail"
  } >> "$LOG"
  i=$((i+1))
done

if [ "$unreachable" -eq "$total" ]; then
  say "Could not reach any origin. Are you online?"
  exit 0
fi

noun=repos
[ "$total" -ne 1 ] || noun=repo
if [ "$pulled" -eq "$total" ]; then
  list="Pulled all $total $noun."
else
  list="Pulled $pulled of $total $noun."
fi
[ "$skipped" -eq 0 ] || list="$list $skipped skipped, no remote."
[ -z "$failed_lines" ] || list="$list${NL}Could not pull:$NL${failed_lines%"$NL"}"
[ -z "$left_lines" ] || list="$list${NL}Left on another branch:$NL${left_lines%"$NL"}"
say "$list"
exit 0
