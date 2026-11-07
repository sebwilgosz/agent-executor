#!/usr/bin/env bash
# docs-mentions.sh — what a diff removed that the docs still name. No AI, no network.
# /executor:review reads this, then judges whether a doc now states something false.
#
# Usage: docs-mentions.sh <base> [<identifier>...]
# Reads the diff of <base>...HEAD. Identifiers: long flags and UPPER_SNAKE names
# on removed lines and on no added line (code files only), the paths of deleted
# and renamed files, and the arguments. Searches the tracked docs at HEAD:
# README*, docs/**, *.md, never a changelog. Output, exit code always 0:
#   MENTION: <identifier> <file>:<line>   one per hit, cut at 50 with ...and <n> more
#   DOCS TOUCHED: <file>                  each doc the diff changes
#   NONE                                  nothing to say, or the diff is docs only
#   UNKNOWN: <why>                        logged to ~/.engineer-of-wealth/executor/docs-mentions.log
#                                         (EOW_HOME overrides the root)
set -u

export LC_ALL=C
# A partial clone would otherwise fetch the blobs a diff needs.
export GIT_NO_LAZY_FETCH=1

LOG="${EOW_HOME:-${HOME:-}/.engineer-of-wealth}/executor/docs-mentions.log"
W=$(mktemp -d 2>/dev/null) || W=""
trap '[ -z "$W" ] || rm -rf "$W"' EXIT
ERR=/dev/null
[ -z "$W" ] || ERR="$W/err"

unknown() {
  {
    mkdir -p "$(dirname "$LOG")"
    printf '%s  %s  %s: %s\n' "$(date "+%F %T")" "$PWD" "$1" "$(head -1 "$ERR")" >> "$LOG"
  } 2>/dev/null
  printf 'UNKNOWN: %s\n' "$1"
  exit 0
}

[ -n "$W" ] || unknown "no temporary folder to work in"
: > "$ERR"
base="${1:-}"
[ -n "$base" ] || unknown "no base given"
shift

top=$(git rev-parse --show-toplevel 2>"$ERR") && [ -n "$top" ] || unknown "not a git repository"
cd "$top" 2>"$ERR" || unknown "not a git repository"
git rev-parse --verify --quiet "HEAD^{commit}" >/dev/null 2>"$ERR" || unknown "HEAD has no commit to read"
sha=$(git rev-parse --verify --quiet "$base^{commit}" 2>"$ERR") || unknown "can't read base $base"

kind() {
  case "${1##*/}" in
    CHANGELOG* | [Cc]hangelog | [Cc]hangelog.[mM][dD]) K=changelog; return ;;
    README* | *.[mM][dD]) K=doc; return ;;
  esac
  case "$1" in docs/*) K=doc ;; *) K=code ;; esac
}

code=(); touched=(); gone=(); doc=""
note() {
  kind "$1"
  case "$K" in code) code+=("$1") ;; doc) doc=$1 ;; esac
}
forget() {
  kind "$1"
  [ "$K" = changelog ] || gone+=("$1")
}

git diff -M --name-status -z "$sha...HEAD" >"$W/status" 2>"$ERR" || unknown "can't diff $base...HEAD"
while IFS= read -r -d '' st && IFS= read -r -d '' p; do
  doc=""
  case "$st" in
    R*) IFS= read -r -d '' new; forget "$p"; note "$p"; note "$new" ;;
    D*) forget "$p"; note "$p" ;;
    *) note "$p" ;;
  esac
  [ -z "$doc" ] || touched+=("$doc")
done <"$W/status"

if [ ${#code[@]} -eq 0 ]; then
  echo NONE
  exit 0
fi

git --literal-pathspecs diff -U0 --no-color --no-ext-diff --no-textconv "$sha...HEAD" -- "${code[@]}" >"$W/patch" 2>"$ERR" \
  || unknown "can't diff $base...HEAD"

# Lines are told by the hunk they sit in, never by a --- or +++ prefix: a removed
# line that starts with a flag reads ---flag in a patch.
awk '
  function scan(s, re, inside, set,   before, after) {
    while (match(s, re)) {
      before = (RSTART > 1) ? substr(s, RSTART - 1, 1) : ""
      after = substr(s, RSTART + RLENGTH, 1)
      if (before !~ inside && after !~ inside) set[substr(s, RSTART, RLENGTH)] = 1
      s = substr(s, RSTART + RLENGTH - 1)
    }
  }
  function tokens(s, set) {
    scan(s, "--[A-Za-z][A-Za-z0-9]*([-_][A-Za-z0-9]+)*", "[A-Za-z0-9_-]", set)
    scan(s, "[A-Z][A-Z0-9]*(_[A-Z0-9]+)+", "[A-Za-z0-9_]", set)
  }
  /^diff --git / { hunk = 0; next }
  /^@@ /         { hunk = 1; next }
  hunk && /^-/   { tokens(substr($0, 2), removed); next }
  hunk && /^\+/  { tokens(substr($0, 2), added); next }
  END { for (t in removed) if (!(t in added)) print t }
' "$W/patch" | sort >"$W/found"

git ls-tree -r -z --name-only HEAD >"$W/tree" 2>"$ERR" || unknown "can't list the files at HEAD"
docs=()
while IFS= read -r -d '' p; do
  kind "$p"
  [ "$K" != doc ] || docs+=("$p")
done <"$W/tree"

: >"$W/hits"
# bare=1 is a file's bare name: after a slash it names another folder's file,
# unless that slash is ./
search() {
  local id=$1 bare=$2 rc
  shift 2
  case "$id" in *[![:space:]]*) ;; *) return 0 ;; esac
  case "$id" in *$'\n'*) return 0 ;; esac
  git --literal-pathspecs grep -n -z -I --no-color -F -e "$id" HEAD -- "$@" >"$W/grep" 2>"$ERR"; rc=$?
  [ "$rc" -le 1 ] || unknown "can't search the docs at HEAD"
  [ "$rc" -eq 0 ] || return 0
  tr '\000' '\001' <"$W/grep" | ID=$id BARE=$bare awk '
    function whole(line,   rest, off, i, at, before, after) {
      rest = line; off = 0
      while ((i = index(rest, id)) > 0) {
        at = off + i
        before = (at > 1) ? substr(line, at - 1, 1) : ""
        after = substr(line, at + length(id), 1)
        if (!(edge_left && before ~ inside) && !(edge_right && after ~ inside) &&
            (!bare || before != "/" || substr(line, 1, at - 1) ~ /(^|[^.])\.\/$/)) return 1
        off = at; rest = substr(line, at + 1)
      }
      return 0
    }
    BEGIN {
      id = ENVIRON["ID"]; bare = (ENVIRON["BARE"] == "1")
      inside = (id ~ /^[A-Za-z0-9_]+$/) ? "[A-Za-z0-9_]" : "[A-Za-z0-9_-]"
      edge_left = (substr(id, 1, 1) ~ inside)
      edge_right = (substr(id, length(id), 1) ~ inside)
    }
    {
      sep = index($0, "\001")
      file = substr($0, length("HEAD:") + 1, sep - length("HEAD:") - 1)
      rest = substr($0, sep + 1)
      sep = index(rest, "\001")
      if (whole(substr(rest, sep + 1))) print "MENTION: " id " " file ":" substr(rest, 1, sep - 1)
    }
  ' >>"$W/hits"
}

if [ ${#docs[@]} -gt 0 ]; then
  while IFS= read -r id; do search "$id" 0 "${docs[@]}"; done <"$W/found"
  for p in ${gone[@]+"${gone[@]}"}; do
    search "$p" 0 "${docs[@]}"
    case "$p" in */*) ;; *) continue ;; esac
    beside=()
    for d in "${docs[@]}"; do
      case "$d" in "${p%/*}"/*/*) ;; "${p%/*}"/*) beside+=("$d") ;; esac
    done
    [ ${#beside[@]} -eq 0 ] || search "${p##*/}" 1 "${beside[@]}"
  done
  for id in "$@"; do search "$id" 0 "${docs[@]}"; done
fi

awk '!seen[$0]++' "$W/hits" >"$W/mentions"
n=$(wc -l <"$W/mentions" | tr -d ' ')
head -n 50 "$W/mentions"
[ "$n" -le 50 ] || printf '...and %d more\n' "$((n - 50))"
for d in ${touched[@]+"${touched[@]}"}; do printf 'DOCS TOUCHED: %s\n' "$d"; done
[ "$n" -gt 0 ] || [ ${#touched[@]} -gt 0 ] || echo NONE
exit 0
