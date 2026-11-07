# Sourced by find-checkout.sh and pull-repos.sh: the search for local repos under the roots
# (scripts/roots.sh reads those). No output, no network, never fails. Defines:
#   discover_repos <predicate> <root>... — sets repos to the folders that count.
#
# Depth-first over <root>/* and <root>/*/*, which is path order, root after root;
# a missing root is skipped. A folder is a repo when it is a checkout or looks
# like a bare repo. <predicate> <folder> runs on each repo and returns 0 when it
# counts. A bare repo or a clone and its worktrees share one common git dir: the
# first that counts stands for all.

discover_repo_at() {
  [ -e "$1/.git" ] || { [ -f "$1/HEAD" ] && [ -d "$1/objects" ] && [ -d "$1/refs" ]; } || return 0
  "$predicate" "$1" || return 0
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=$1
  case "$seen" in *"|$common|"*) return 0 ;; esac
  seen="$seen$common|"
  repos+=("$1")
}

discover_repos() {
  local predicate=$1 seen="|" root d e
  shift
  repos=()
  for root in "$@"; do
    [ -d "$root" ] || continue
    for d in "$root"/*; do
      [ -d "$d" ] || continue
      discover_repo_at "$d"
      for e in "$d"/*; do
        [ -d "$e" ] || continue
        discover_repo_at "$e"
      done
    done
  done
  return 0
}
