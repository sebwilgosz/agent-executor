#!/usr/bin/env bash
# plans-migrate.sh - moves legacy .executor/ folders to the plans folder. No AI.
# Finds every .executor/ under <root> (default ~/Projects, depth 4, skipping
# node_modules and .git) and moves its contents to the repo's folder, which only
# scripts/plan-path.sh knows:
#   plan.md, plan-*.md  <YYYY-MM-DD> - <title>.md, the date from the modification
#                       time, the title from the plan's heading or Spec line. A
#                       host other than github.com adds a "Host: <host>" line.
#   done/*.md           the name kept, "Status: done <date>" added from that name.
#   anything else       legacy/, in the same shape.
# It never overwrites: a clash is reported and that file stays. Once a repo has no
# .executor/ in any worktree, the .executor/ line leaves its shared exclude file.
# The emptied folder is removed. Symbolic links and tracked files are left alone.
#
# Usage: plans-migrate.sh [--dry-run] [<root>]     --dry-run changes nothing
# One line per file, exit code always 0:
#   moved: <file> -> <path> [(<added line>)]    would move: the same, on a dry run
#   clash: <file> stays, <path> is taken
#   left: <path>: <why>
#   failed: <file> stays: <why>
#   STOP: <.executor>: <why>                    nothing moves for that repo
# Then per folder: removed: <folder> | would remove: <folder>, and
#   removed .executor/ from <file> | would remove .executor/ from <file>
# Nothing found: No legacy .executor/ under <root>
set -u
unset CDPATH GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
NL=$'\n'
USAGE="STOP: usage: plans-migrate.sh [--dry-run] [<root>]"

DRY=0; ROOT=""; ROOT_SET=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -*) printf '%s\n' "$USAGE"; exit 0 ;;
    *)
      if [ "$ROOT_SET" -eq 1 ]; then printf '%s\n' "$USAGE"; exit 0; fi
      ROOT=$a; ROOT_SET=1
      ;;
  esac
done
[ "$ROOT_SET" -eq 1 ] || ROOT="$HOME/Projects"
while [ "$ROOT" != "/" ] && [ "${ROOT%/}" != "$ROOT" ]; do ROOT=${ROOT%/}; done

if [ -L "$ROOT" ]; then
  printf 'STOP: %s is a symbolic link: name the real folder\n' "$ROOT"; exit 0
fi
if [ ! -d "$ROOT" ]; then
  printf 'STOP: no such folder: %s\n' "$ROOT"; exit 0
fi
ROOT=$(cd -P "$ROOT" && pwd)

CLAIMED=""
GONE=""
LEFT=0

plan_path() { "$BASH" "$SELF_DIR/plan-path.sh" "$@" 2>/dev/null </dev/null; }
listed() { case "$NL$1$NL" in *"$NL$2$NL"*) return 0 ;; esac; return 1; }

trim() {
  local s=$1
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

clean_title() {
  local t
  t=$(trim "$1"); t=${t#Build:}; t=$(trim "$t"); t=${t#Spec:}; t=$(trim "$t")
  t=${t#spec - }; t=${t% - spec}
  printf '%s' "$t"
}

# Prints the plan's title: its heading, its Spec line's link text, the file name
# that line names, then its own file name without plan and plan-.
plan_title() {
  local l heading="" spec="" t re='^\[([^]]+)\]'
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in
      "## "*) break ;;
      "# "*) [ -n "$heading" ] || heading=${l#"# "} ;;
      "Spec: "*) [ -n "$spec" ] || spec=${l#"Spec: "} ;;
      "Specs: "*) [ -n "$spec" ] || spec=${l#"Specs: "} ;;
    esac
  done < "$1"
  t=$(clean_title "$heading")
  if [ -z "$t" ] && [ -n "$spec" ]; then
    if [[ $spec =~ $re ]]; then
      t=$(clean_title "${BASH_REMATCH[1]}")
    else
      t=$(plan_path --title "$(trim "$spec")")
      case "$t" in STOP:*) t="" ;; esac
    fi
  fi
  if [ -z "$t" ]; then
    t=${1##*/}; t=${t%.md}; t=${t#plan-}
  fi
  printf '%s' "$t"
}

# Prints the plan with LINE under the header's first line matching AFTER, else
# under the header's last text, as plan-state.sh --mark places its line.
with_header_line() {
  LINE=$2 AFTER=$3 awk '
    { l[NR] = $0 }
    END {
      end = NR + 1
      for (i = 1; i <= NR; i++)
        if (l[i] ~ /^## / || l[i] ~ /^[[:space:]]*- \[[ xX]\] /) { end = i; break }
      ins = 0
      if (ENVIRON["AFTER"] != "")
        for (i = 1; i < end; i++)
          if (l[i] ~ ENVIRON["AFTER"]) { ins = i; break }
      if (!ins) {
        ins = end - 1
        while (ins > 0 && l[ins] !~ /[^[:space:]]/) ins--
      }
      for (i = 1; i <= ins; i++) print l[i]
      print ENVIRON["LINE"]
      for (i = ins + 1; i <= NR; i++) print l[i]
    }' < "$1"
}

has_header_host() {
  sed '/^## /q' "$1" 2>/dev/null | grep -q '^Host: '
}

# Moves <file> to <path> without overwriting, adding <line> under <after> if given.
place() {
  local src=$1 dest=$2 line=${3:-} after=${4:-} note="" dir tmp
  dir=${dest%/*}
  [ -z "$line" ] || note=" ($line)"
  if [ -e "$dest" ] || [ -L "$dest" ] || listed "$CLAIMED" "$dest"; then
    printf 'clash: %s stays, %s is taken\n' "$src" "$dest"
    LEFT=$((LEFT+1)); return 0
  fi
  CLAIMED="$CLAIMED$NL$dest"
  if [ "$DRY" -eq 1 ]; then
    printf 'would move: %s -> %s%s\n' "$src" "$dest" "$note"
    return 0
  fi
  if ! mkdir -p "$dir" 2>/dev/null; then
    printf 'failed: %s stays: cannot create %s\n' "$src" "$dir"
    LEFT=$((LEFT+1)); return 0
  fi
  if [ -n "$line" ]; then
    # Written beside the destination, so a failure leaves the original untouched.
    tmp=$(mktemp "$dir/.migrate.XXXXXX" 2>/dev/null) \
      && cp -p "$src" "$tmp" 2>/dev/null \
      && with_header_line "$src" "$line" "$after" > "$tmp" 2>/dev/null \
      && touch -r "$src" "$tmp" 2>/dev/null \
      && mv -n "$tmp" "$dest" 2>/dev/null </dev/null
    if [ -e "${tmp:-}" ] || [ ! -e "$dest" ]; then
      [ -z "${tmp:-}" ] || rm -f "$tmp"
      printf 'failed: %s stays: cannot write %s\n' "$src" "$dest"
      LEFT=$((LEFT+1)); return 0
    fi
    rm -f "$src" 2>/dev/null
  else
    mv -n "$src" "$dest" 2>/dev/null </dev/null
    if [ ! -e "$dest" ] || [ -e "$src" ]; then
      printf 'failed: %s stays: cannot move it to %s\n' "$src" "$dest"
      LEFT=$((LEFT+1)); return 0
    fi
  fi
  printf 'moved: %s -> %s%s\n' "$src" "$dest" "$note"
}

move_plan() {
  local f=$1 repo=$2 title date dest host="" line=""
  if [ ! -r "$f" ]; then
    printf 'failed: %s stays: cannot read it\n' "$f"
    LEFT=$((LEFT+1)); return 0
  fi
  title=$(plan_title "$f")
  date=$(date -r "$f" +%F 2>/dev/null)
  dest=$(plan_path --dated "$date" "$title" "$repo")
  case "$dest" in
    STOP:*|"")
      printf 'failed: %s stays: %s\n' "$f" "${dest#STOP: }"
      LEFT=$((LEFT+1)); return 0
      ;;
  esac
  host=$(plan_path --host "$repo")
  case "$host" in STOP:*|github.com) host="" ;; esac
  if [ -n "$host" ] && ! has_header_host "$f"; then line="Host: $host"; fi
  place "$f" "$dest" "$line" '^Specs?: '
}

move_done() {
  local f=$1 folder=$2 name=${1##*/} date line="" re='^([0-9]{4}-[0-9]{2}-[0-9]{2})'
  if [[ $name =~ $re ]]; then date=${BASH_REMATCH[1]}
  else date=$(date -r "$f" +%F 2>/dev/null); fi
  if [ "$(plan_path --is-done "$f")" != done ]; then line="Status: done $date"; fi
  place "$f" "$folder/$name" "$line"
}

move_file() {
  local f=$1 dir=$2 repo=$3 folder=$4 rel=${1#"$2"/}
  if [ -L "$f" ]; then
    printf 'left: %s: a symbolic link\n' "$f"
    LEFT=$((LEFT+1)); return 0
  fi
  if [ ! -f "$f" ]; then
    printf 'left: %s: not a file\n' "$f"
    LEFT=$((LEFT+1)); return 0
  fi
  case "$rel" in
    plan.md|plan-*.md)
      case "$rel" in */*) ;; *) move_plan "$f" "$repo"; return 0 ;; esac
      ;;
    done/*.md)
      case "${rel#done/}" in */*) ;; *) move_done "$f" "$folder"; return 0 ;; esac
      ;;
  esac
  place "$f" "$folder/legacy/$rel"
}

# Removes the .executor/ line once no worktree of the repo holds a .executor/.
drop_exclude_line() {
  local repo=$1 common file wt tmp
  common=$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null </dev/null) || return 0
  case "$common" in /*) ;; *) common="$repo/$common" ;; esac
  common=$(cd -P "$common" 2>/dev/null && pwd) || return 0
  file="$common/info/exclude"
  grep -qxF '.executor/' "$file" 2>/dev/null || return 0
  while IFS= read -r wt; do
    case "$wt" in "worktree "*) wt=${wt#worktree } ;; *) continue ;; esac
    if { [ -e "$wt/.executor" ] || [ -L "$wt/.executor" ]; } && ! listed "$GONE" "$wt/.executor"; then
      return 0
    fi
  done <<< "$(git -C "$repo" worktree list --porcelain 2>/dev/null </dev/null)"
  if [ "$DRY" -eq 1 ]; then
    printf 'would remove .executor/ from %s\n' "$file"
    return 0
  fi
  tmp=$(mktemp "$file.XXXXXX" 2>/dev/null) && cp -p "$file" "$tmp" 2>/dev/null \
    && { grep -vxF '.executor/' "$file" > "$tmp"; [ "$?" -le 1 ]; } \
    && mv -f "$tmp" "$file" 2>/dev/null
  if grep -qxF '.executor/' "$file" 2>/dev/null; then
    [ -z "${tmp:-}" ] || rm -f "$tmp"
    printf 'failed: .executor/ stays in %s: cannot write it\n' "$file"
    return 0
  fi
  printf 'removed .executor/ from %s\n' "$file"
}

migrate_folder() {
  local dir=$1 repo=${1%/*} folder files f
  if [ -L "$dir" ]; then
    printf 'left: %s: a symbolic link\n' "$dir"; return 0
  fi
  if [ ! -d "$dir" ]; then
    printf 'left: %s: not a folder\n' "$dir"; return 0
  fi
  folder=$(plan_path "$repo")
  case "$folder" in
    STOP:*) printf 'STOP: %s: %s\n' "$dir" "${folder#STOP: }"; return 0 ;;
    "") printf 'STOP: %s: no plans folder\n' "$dir"; return 0 ;;
  esac
  if [ -n "$(git -C "$repo" ls-files -- .executor 2>/dev/null </dev/null)" ]; then
    printf 'left: %s: tracked by git\n' "$dir"; return 0
  fi
  LEFT=0
  files=$(find "$dir" -mindepth 1 ! -type d 2>/dev/null | LC_ALL=C sort)
  if [ -n "$files" ]; then
    while IFS= read -r f; do
      move_file "$f" "$dir" "$repo" "$folder"
    done <<< "$files"
  fi
  [ "$LEFT" -eq 0 ] || return 0
  GONE="$GONE$NL$dir"
  drop_exclude_line "$repo"
  if [ "$DRY" -eq 1 ]; then
    printf 'would remove: %s\n' "$dir"
    return 0
  fi
  find "$dir" -depth -type d -empty -delete 2>/dev/null
  if [ -e "$dir" ]; then printf 'failed: %s stays: it is not empty\n' "$dir"
  else printf 'removed: %s\n' "$dir"; fi
}

FOUND=$(find "$ROOT" -maxdepth 4 \( -name node_modules -o -name .git \) -prune \
  -o -name .executor -print -prune 2>/dev/null | LC_ALL=C sort)
if [ -z "$FOUND" ]; then
  printf 'No legacy .executor/ under %s\n' "$ROOT"
  exit 0
fi
while IFS= read -r d; do
  migrate_folder "$d"
done <<< "$FOUND"
exit 0
