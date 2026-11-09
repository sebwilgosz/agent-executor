# Sourced by branch-guard.sh (so ship.sh and pr-open.sh) and review-mode.sh, so all agree on the base. Sets:
#   def — the default branch's name: the local origin/HEAD, else what gh
#         reports, else a local main/master, else main
#   cmp — the ref to compare with: origin/<def> when it exists, else <def>
# Local first; gh only when origin/HEAD is unset. No output, never fails.

def=""
if ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
  def=${ref#refs/remotes/origin/}
fi
if [ -z "$def" ] && command -v gh >/dev/null 2>&1; then
  def=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
fi
if [ -z "$def" ]; then
  for b in main master; do
    git show-ref --verify --quiet "refs/heads/$b" && { def=$b; break; }
  done
fi
[ -n "$def" ] || def=main

cmp="$def"
git show-ref --verify --quiet "refs/remotes/origin/$def" && cmp="origin/$def"
