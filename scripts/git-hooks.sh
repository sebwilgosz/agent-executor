#!/usr/bin/env bash
# git-hooks.sh — two opt-in git hooks that save a machine work. No AI.
#
# Usage:   git-hooks.sh install [<repo>]     write the hooks into the repo's shared folder
#          git-hooks.sh uninstall [<repo>]   remove only what install wrote
#          git-hooks.sh post-checkout ...    called by the hook
#          git-hooks.sh post-commit          called by the hook
#
# post-checkout: a new worktree gets copy-on-write clones of node_modules and
# .next/cache from the main checkout, for each package up to two folders down, so it
# neither installs nor compiles from nothing. It waits, so they exist once
# `git worktree add` returns. It never falls back to a full copy.
#
# post-commit: the type check and lint of each package the commit touched. Passing
# prints nothing. Failing prints the errors in the commit's own output, and the commit
# stands, so an agent sees them with no model turn deciding to run anything.
#
# Log: git-hooks.log in ~/.engineer-of-wealth/executor (EXECUTOR_HEAVY_DIR overrides
# it): time, step, folder, seconds, outcome. Never a check's output.
#
# Always fails open: every path exits 0, so a hook can't stop git.
set -u

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX

MARK='# executor git-hooks'
STATE="${EXECUTOR_HEAVY_DIR:-${HOME:-}/.engineer-of-wealth/executor}"
LIMIT="${EXECUTOR_CHECK_SECONDS:-60}"
NULL_REF=0000000000000000000000000000000000000000

log() { # <step> <folder> <seconds> <outcome>
  { mkdir -p "$STATE" && printf '%s  %s  %s  %ss  %s\n' "$(date '+%F %T')" "$1" "${2//[[:cntrl:]]/ }" "$3" "$4" >> "$STATE/git-hooks.log"; } 2>/dev/null
}

note() { printf 'executor git-hooks: %s\n' "$1" >&2; }

# Package folders up to two levels down, one per line, "." for the top.
packages() {
  git ls-files -- package.json '*/package.json' 2>/dev/null \
    | awk -F/ 'NF <= 3 && !/(^|\/)node_modules\// { sub(/\/?package\.json$/, ""); print ($0 == "" ? "." : $0) }'
}

# The worktree on the default branch, else the first non-bare one other than this.
main_checkout() {
  local here=$1 default branch line wt='' bare='' first='' hit=''
  default=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null)
  default=${default#refs/remotes/origin/}
  while IFS= read -r line; do
    case "$line" in
      'worktree '*) wt=${line#worktree }; bare='' ;;
      bare) bare=1 ;;
      'branch refs/heads/'*)
        branch=${line#branch refs/heads/}
        if [ -z "$bare" ] && [ -d "$wt" ]; then
          if [ -n "$default" ]; then
            [ "$branch" = "$default" ] && hit=$wt
          elif [ "$branch" = main ] || [ "$branch" = master ]; then
            hit=$wt
          fi
        fi
        ;;
      '')
        if [ -z "$first" ] && [ -z "$bare" ] && [ -d "$wt" ] && [ "$wt" != "$here" ]; then first=$wt; fi
        ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null; echo)
  printf '%s' "${hit:-$first}"
}

# 0 cloned or nothing to do, 1 the source is missing, 2 it can't be cloned.
clone_folder() { # <source> <destination>
  local src=$1 dst=$2 real parent
  [ -e "$src" ] || return 1
  if [ -e "$dst" ] || [ -L "$dst" ]; then return 0; fi
  real=$(cd -P "$src" 2>/dev/null && pwd) || return 2
  parent=$(dirname "$dst")
  mkdir -p "$parent" 2>/dev/null || return 2
  # cp -c quietly makes a full copy where it can't clone, so rule that out first.
  [ "$(stat -f %d "$real" 2>/dev/null)" = "$(stat -f %d "$parent" 2>/dev/null)" ] || return 2
  [ "$(df -T apfs "$real" 2>/dev/null | wc -l)" -gt 1 ] || return 2
  if ! cp -cR "$real" "$dst" 2>/dev/null; then
    rm -rf "$dst" 2>/dev/null
    return 2
  fi
}

post_checkout() {
  [ "${1:-}" = "$NULL_REF" ] || return 0
  local here main pkg rc lock start=$SECONDS outcome=cloned
  here=$(pwd -P)
  main=$(main_checkout "$here")
  if [ -z "$main" ] || [ "$(cd -P "$main" 2>/dev/null && pwd)" = "$here" ]; then return 0; fi
  while IFS= read -r pkg; do
    clone_folder "$main/$pkg/node_modules" "$here/$pkg/node_modules"; rc=$?
    case "$rc" in
      1) note "no node_modules in $main/$pkg to clone; install there once"; outcome=partial ;;
      2) note "could not clone node_modules for $pkg"; outcome=partial ;;
    esac
    clone_folder "$main/$pkg/.next/cache" "$here/$pkg/.next/cache"
    [ $? -eq 2 ] && note "could not clone .next/cache for $pkg"
    [ "$rc" -eq 0 ] || continue
    for lock in package-lock.json yarn.lock pnpm-lock.yaml bun.lock; do
      if [ -f "$here/$pkg/$lock" ] && ! cmp -s "$here/$pkg/$lock" "$main/$pkg/$lock"; then
        note "$pkg/$lock differs from the main checkout, so node_modules may be out of date"
      fi
    done
  done < <(packages)
  log clone "$here" "$((SECONDS - start))" "$outcome"
}

# Runs a command in its own process group and stops the whole group at the limit.
limited() {
  perl -e '
    my $limit = shift;
    my $pid = fork // exit 126;
    if (!$pid) { setpgrp(0, 0); exec @ARGV; exit 127 }
    my $late = 0;
    $SIG{ALRM} = sub { $late = 1; kill "TERM", -$pid; sleep 1; kill "KILL", -$pid };
    alarm $limit;
    waitpid $pid, 0;
    my $code = $? >> 8;
    alarm 0;
    kill "KILL", -$pid if $late;
    exit($late ? 124 : $code);
  ' "$LIMIT" "$@"
}

run_check() { # <name> <package> <command...>
  local name=$1 pkg=$2 out rc start=$SECONDS lines
  shift 2
  out=$(mktemp) || return 0
  limited "$@" > "$out" 2>&1 </dev/null
  rc=$?
  case "$rc" in
    0) log "$name" "$PWD" "$((SECONDS - start))" passed ;;
    124)
      printf 'executor git-hooks: %s in %s stopped after %s s\n' "$name" "$pkg" "$LIMIT"
      log "$name" "$PWD" "$((SECONDS - start))" stopped
      ;;
    126 | 127)
      printf 'executor git-hooks: %s in %s could not start\n' "$name" "$pkg"
      log "$name" "$PWD" "$((SECONDS - start))" not-started
      ;;
    *)
      printf 'executor git-hooks: %s failed in %s\n' "$name" "$pkg"
      head -n 40 "$out"
      lines=$(wc -l < "$out" | tr -d ' ')
      [ "$lines" -le 40 ] || printf '... %s more lines\n' "$((lines - 40))"
      log "$name" "$PWD" "$((SECONDS - start))" failed
      ;;
  esac
  rm -f "$out"
}

check_package() { # <package folder>
  local pkg=$1 names
  (
    cd "$pkg" 2>/dev/null || exit 0
    [ -e node_modules ] || exit 0
    names=$(perl -MJSON::PP -0777 -ne '
      my $s = eval { JSON::PP->new->decode($_)->{scripts} };
      print "$_\n" for ref $s eq "HASH" ? keys %$s : ();
    ' package.json 2>/dev/null)
    has() { printf '%s\n' "$names" | grep -qx "$1"; }
    if has typecheck; then
      run_check type-check "$pkg" npm run --silent typecheck
    elif has type-check; then
      run_check type-check "$pkg" npm run --silent type-check
    elif [ -f tsconfig.json ] && [ -x node_modules/.bin/tsc ]; then
      run_check type-check "$pkg" node_modules/.bin/tsc --noEmit --incremental false
    fi
    if has lint; then
      run_check lint "$pkg" npm run --silent lint
    fi
  )
}

post_commit() {
  local git_dir marker changed pkgs pkg file best hit=$'\n'
  git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 0
  for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD; do
    [ -e "$git_dir/$marker" ] && return 0
  done
  changed=$(git diff-tree --no-commit-id --name-only --root -r HEAD 2>/dev/null \
    | grep -viE '\.(md|markdown|png|jpe?g|gif|webp|avif|svg|ico)$')
  [ -n "$changed" ] || return 0
  pkgs=$(packages | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-)
  [ -n "$pkgs" ] || return 0
  while IFS= read -r file; do
    best=''
    while IFS= read -r pkg; do
      case "$pkg" in
        .) best=. ;;
        *) case "$file" in "$pkg"/*) best=$pkg ;; esac ;;
      esac
      [ -z "$best" ] || break
    done <<< "$pkgs"
    [ -n "$best" ] || continue
    case "$hit" in *$'\n'"$best"$'\n'*) ;; *) hit+="$best"$'\n' ;; esac
  done <<< "$changed"
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && check_package "$pkg"
  done <<< "$hit"
}

# Plugin versions sit side by side, so the hook picks the newest and needs no reinstall.
hook_file() { # <hook name>
  local root parent find_script
  root=$(cd -P "$(dirname "$0")/.." && pwd)
  parent=$(dirname "$root")
  case "$(basename "$root")" in
    [0-9]*.[0-9]*) find_script="ls -d '$parent'/*/scripts/git-hooks.sh 2>/dev/null | sort -V | tail -1" ;;
    *) find_script="echo '$root/scripts/git-hooks.sh'" ;;
  esac
  printf '#!/usr/bin/env bash\n%s\nscript=$(%s)\n[ -f "$script" ] || exit 0\nexec bash "$script" %s "$@"\n' "$MARK" "$find_script" "$1"
}

ours() { [ -f "$1" ] && grep -qxF "$MARK" "$1" 2>/dev/null; }

hooks_folder() { # <repo>
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    note "$1 is not a git repo"
    return 1
  }
  printf '%s/hooks' "$common"
}

install() {
  local repo=${1:-.} folder name path
  folder=$(hooks_folder "$repo") || return 0
  if [ -n "$(git -C "$repo" config core.hooksPath 2>/dev/null)" ]; then
    note "$repo sets core.hooksPath, so hooks written here would not run; nothing installed"
    return 0
  fi
  case "$0" in *"'"*) note "this script's path holds a quote; nothing installed"; return 0 ;; esac
  mkdir -p "$folder" 2>/dev/null
  for name in post-checkout post-commit; do
    path="$folder/$name"
    if [ -e "$path" ] && ! ours "$path"; then
      note "$name left alone: another tool wrote $path"
      continue
    fi
    if hook_file "$name" > "$path" && chmod +x "$path"; then
      note "$name installed in $folder"
    else
      note "could not write $path"
    fi
  done
}

uninstall() {
  local repo=${1:-.} folder name
  folder=$(hooks_folder "$repo") || return 0
  for name in post-checkout post-commit; do
    if ours "$folder/$name"; then
      rm -f "$folder/$name" && note "$name removed from $folder"
    fi
  done
}

case "${1:-}" in
  install | uninstall | post-checkout | post-commit)
    step=$1
    shift
    case "$step" in
      post-checkout) post_checkout "$@" ;;
      post-commit) post_commit ;;
      *) "$step" "$@" ;;
    esac
    ;;
  *) note "usage: git-hooks.sh install|uninstall [<repo>]" ;;
esac
exit 0
