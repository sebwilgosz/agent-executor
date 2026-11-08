# Sourced by pull-repos.sh and repo-tidy.sh, so both judge a folder the same way
# before touching it. Defines, for a folder that is a git checkout:
#   has_changes <folder>    - 0 when the tree has any change, untracked included
#   in_progress <folder>    - 0 when a merge or rebase is under way, or git can't say
#   folder_in_use <folder>  - 0 when a process has its working directory in the
#                             folder, or nobody can say
# No output. The caller's own working directory must be outside the folder.

in_progress() {
  local gd
  gd=$(git -C "$1" rev-parse --absolute-git-dir) || return 0
  [ -e "$gd/MERGE_HEAD" ] || [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]
}

has_changes() {
  [ -n "$(git -C "$1" status --porcelain)" ]
}

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
