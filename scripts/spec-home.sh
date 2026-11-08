#!/usr/bin/env bash
# spec-home.sh — where a spec is read from and written to. Local only: no
# network, no AI. It reads files and reports; the model reads the words that
# are left. Exit 0 always; a failure is a line, never a crash.
#
#   spec-home.sh [--repo <dir>] [<dir>]
#       The home for <dir> (default: the current folder). It reads the nearest
#       AGENTS.md or CLAUDE.md from <dir> upwards that has a "## Specs" section,
#       then, if none has, the same from --repo <dir>, the target repo. Prints
#         kind=<folder|repo|notion|github|linear|jira>
#         location=<where, in the instructions' own words>
#         tracker=<github|linear|jira|none>
#         tool=<what reaches it>
#         file=<the instructions file that names it>
#       or one line: "NONE: ..." (nothing names a home; run /executor:init) or
#       "AMBIGUOUS: ..." (two files or the words disagree; ask, never guess).
#   spec-home.sh --folder [<dir>]
#       The nearest folder at or above <dir> with an AGENTS.md or CLAUDE.md,
#       the folder an answer would apply to; "NONE" when there is none.
#   spec-home.sh --write <folder> <line>...
#       Writes the "## Specs" section (the lines are its body) into the
#       folder's instruction files, replacing an old section: both when both
#       exist, only AGENTS.md when CLAUDE.md imports it, and in a folder with
#       neither, an AGENTS.md plus a CLAUDE.md that imports it. One
#       "wrote <file>" line per file. It never commits.
#   spec-home.sh --local [<dir>]
#       The local fallback: creates and prints
#       ~/.engineer-of-wealth/executor/specs/<org>/<repo> (EOW_HOME overrides
#       the root; local/<name> without an origin), beside the plans folder and
#       never inside the repository.
#
# Instructions name a home in a short section:
#   ## Specs
#   Specs: Notion, the "RFCs" database. Tickets: Jira project TRAV.

exec 2>/dev/null

. "$(cd -P "$(dirname "$0")" && pwd)/remote-slug.sh"

trim() { local s=$1; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

# The body of the first "## Specs" section of a file, joined on one line.
section_body() {
  local l inside=0 body=
  while IFS= read -r l || [ -n "$l" ]; do
    l=${l%$'\r'}
    if [ "$inside" -eq 1 ]; then
      case "$l" in "#"*) break ;; esac
      l=$(trim "$l")
      [ -n "$l" ] && body="${body:+$body }$l"
    else
      [ "$(trim "$l")" = "## Specs" ] && inside=1
    fi
  done < "$1"
  printf '%s' "$body"
}

# Sets kind, location, tracker, tool from a section body, or problem.
classify() {
  local body=$1 specs tickets low k found=0
  kind=; location=; tracker=none; tool=; problem=
  case "$body" in
    *Tickets:*) specs=${body%%Tickets:*}; tickets=${body#*Tickets:} ;;
    *) specs=$body; tickets= ;;
  esac
  specs=$(trim "${specs#Specs:}")
  low=$(printf '%s' "$specs" | tr '[:upper:]' '[:lower:]')
  for k in notion jira linear github; do
    case "$low" in *"$k"*) kind=$k; found=$((found+1)) ;; esac
  done
  if [ "$found" -eq 0 ]; then
    case "$low" in *docs/specs*) kind=repo; found=1 ;; esac
  fi
  if [ "$found" -eq 0 ]; then
    case "$low" in *vault*|*folder*|*projects/*) kind=folder; found=1 ;; esac
  fi
  if [ "$found" -eq 0 ]; then problem="no recognizable home in: $specs"; return; fi
  if [ "$found" -gt 1 ]; then problem="more than one home in: $specs"; return; fi
  location=$specs
  case "$kind" in
    notion|jira|linear|github)
      location=$(trim "$(printf '%s' "$specs" | sed -E 's/^[A-Za-z]+[[:space:]]*,?//')")
      case "$location" in *[[:alnum:]]*) ;; *) location=$specs ;; esac ;;
  esac
  low=$(printf '%s' "$tickets" | tr '[:upper:]' '[:lower:]')
  for k in jira linear github; do
    case "$low" in *"$k"*) tracker=$k; break ;; esac
  done
  case "$kind" in
    notion) tool="the Notion connector (MCP)" ;;
    jira) tool="the Atlassian connector (MCP)" ;;
    linear) tool="the Linear connector (MCP)" ;;
    github) tool="gh" ;;
    repo) tool="git" ;;
    folder) tool="the file tools" ;;
  esac
}

# Looks in one folder. Prints the result and returns 0 when it names a home
# (or is ambiguous); returns 1 when neither file has a Specs section.
look_in() {
  local d=$1 f body first_file= first_sig= sig
  for f in AGENTS.md CLAUDE.md; do
    [ -f "$d/$f" ] || continue
    body=$(section_body "$d/$f")
    [ -n "$body" ] || continue
    classify "$body"
    if [ -n "$problem" ]; then
      echo "AMBIGUOUS: $d/$f — $problem"
      return 0
    fi
    sig="$kind|$location|$tracker"
    if [ -z "$first_file" ]; then
      first_file=$d/$f; first_sig=$sig
      r_kind=$kind; r_location=$location; r_tracker=$tracker; r_tool=$tool
    elif [ "$sig" != "$first_sig" ]; then
      echo "AMBIGUOUS: $first_file and $d/$f name different homes"
      return 0
    fi
  done
  [ -n "$first_file" ] || return 1
  printf 'kind=%s\nlocation=%s\ntracker=%s\ntool=%s\nfile=%s\n' "$r_kind" "$r_location" "$r_tracker" "$r_tool" "$first_file"
  return 0
}

walk() {
  local d
  d=$(cd -P "$1" 2>/dev/null && pwd) || return 1
  while :; do
    look_in "$d" && return 0
    [ "$d" = / ] && return 1
    d=$(dirname "$d")
  done
}

resolve() {
  local repo= dir=
  while [ $# -gt 0 ]; do
    case "$1" in --repo) repo=${2:-}; shift 2 ;; *) dir=$1; shift ;; esac
  done
  dir=${dir:-$PWD}
  [ -d "$dir" ] || { echo "NONE: $dir is not a folder; no spec home named; run /executor:init"; return; }
  walk "$dir" && return
  [ -n "$repo" ] && [ -d "$repo" ] && walk "$repo" && return
  echo "NONE: no spec home named; run /executor:init"
}

folder() {
  local d
  d=$(cd -P "${1:-$PWD}" 2>/dev/null && pwd) || { echo NONE; return; }
  while :; do
    if [ -f "$d/AGENTS.md" ] || [ -f "$d/CLAUDE.md" ]; then echo "$d"; return; fi
    [ "$d" = / ] && { echo NONE; return; }
    d=$(dirname "$d")
  done
}

# Puts the section into one file: replaces the old one in place, else appends.
put_section() {
  local file=$1 bodyfile=$2 tmp
  tmp=$(mktemp "$file.XXXXXX") || return 1
  if [ -f "$file" ]; then
    awk -v bodyfile="$bodyfile" '
      function emit(   l) {
        print "## Specs"
        while ((getline l < bodyfile) > 0) print l
        close(bodyfile)
      }
      { sub(/\r$/, "") }
      skipping && /^#/ { skipping = 0; print "" }
      skipping { next }
      !done && $0 ~ /^[ \t]*## Specs[ \t]*$/ { emit(); done = 1; skipping = 1; next }
      { print }
      END {
        if (!done) { if (NR > 0) print ""; emit() }
      }
    ' "$file" > "$tmp"
  else
    { echo "## Specs"; cat "$bodyfile"; } > "$tmp"
  fi
  cat "$tmp" > "$file" && rm -f "$tmp"
}

write_home() {
  local d=${1:-} bodyfile targets=() f
  shift
  [ -n "$d" ] && [ -d "$d" ] || { echo "STOP: ${d:-no folder} is not a folder, so no spec home was written"; return; }
  [ "$#" -gt 0 ] && [ -n "$(trim "$*")" ] || { echo "STOP: no section text given, so no spec home was written"; return; }
  d=$(cd -P "$d" && pwd)
  bodyfile=$(mktemp) || { echo "STOP: could not write a temporary file"; return; }
  printf '%s\n' "$@" > "$bodyfile"
  if [ -f "$d/AGENTS.md" ] && [ -f "$d/CLAUDE.md" ]; then
    if grep -qE '^[[:space:]]*@AGENTS\.md[[:space:]]*$' "$d/CLAUDE.md"; then targets=("$d/AGENTS.md")
    else targets=("$d/AGENTS.md" "$d/CLAUDE.md"); fi
  elif [ -f "$d/AGENTS.md" ]; then targets=("$d/AGENTS.md")
  elif [ -f "$d/CLAUDE.md" ]; then targets=("$d/CLAUDE.md")
  else
    targets=("$d/AGENTS.md")
    printf '@AGENTS.md\n' > "$d/CLAUDE.md" && echo "wrote $d/CLAUDE.md"
  fi
  for f in "${targets[@]}"; do
    if put_section "$f" "$bodyfile"; then echo "wrote $f"; else echo "STOP: could not write $f"; fi
  done
  rm -f "$bodyfile"
  return 0
}

local_home() {
  local d top slug
  d=${1:-$PWD}
  [ -d "$d" ] || { echo "STOP: $d is not a folder"; return; }
  d=$(cd -P "$d" && pwd)
  top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || top=$d
  slug=$(slug_from_url "$(git -C "$d" config --get remote.origin.url 2>/dev/null)")
  [ -n "$slug" ] || slug=local/$(basename "$top")
  d="${EOW_HOME:-$HOME/.engineer-of-wealth}/executor/specs/$slug"
  mkdir -p "$d" || { echo "STOP: could not create $d"; return; }
  echo "$d"
}

case "${1:-}" in
  --folder) shift; folder "$@" ;;
  --write) shift; write_home "$@" ;;
  --local) shift; local_home "$@" ;;
  *) resolve "$@" ;;
esac
exit 0
