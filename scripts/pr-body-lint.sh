#!/usr/bin/env bash
# pr-body-lint.sh — check a PR description against the readability rules of
# references/pull-request.md, whatever headings it uses. No AI, no judgement:
# only what a script can see the same way every time.
#   bash pr-body-lint.sh <body file>
#   bash pr-body-lint.sh --pr <n|url> [--repo <owner/name>]   (reads the PR's live body)
#
# It flags:
#   bare-url      a URL outside link syntax           → [ABC-123](…/browse/ABC-123), [#42](…/pull/42)
#   long-bullet   a bullet over 40 words (with its wrapped lines)
#   long-para     a paragraph over 60 words
#   dense         a bullet or paragraph with 4+ backticked names
#   internals     a label set {a, b, c} or query syntax (f(x) - y, < 1h, [5m]) in prose
#   long-body     over 40 non-blank lines, not counting the diagram or HTML comments
# Fenced code (the Mermaid diagram included) and HTML comments are not prose,
# so they are never flagged.
#
# Output is tagged lines, and the exit code is always 0:
#   LINT: <rule> line <n>: <what> → <fix>    one per problem, in body order
#   LINT: <k> issue(s) - rewrite the body as references/pull-request.md says
#   LINT: ok
#   UNKNOWN: <reason>                        --pr only: the body could not be read
set -u

EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/pr-body-lint.log"

unknown() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" >> "$LOG" 2>/dev/null
  printf 'UNKNOWN: %s\n' "$1"; exit 0
}

file=""; pr=""; repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pr)   pr=${2:-}; shift ;;
    --repo) repo=${2:-}; shift ;;
    -*)     unknown "unknown argument $1 - usage: pr-body-lint.sh <file> | --pr <n|url> [--repo <owner/name>]" ;;
    *)      file=$1 ;;
  esac
  shift
done

if [ -n "$pr" ]; then
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/pr-body-lint.XXXXXX" 2>/dev/null) || unknown "could not create a temp folder"
  trap 'rm -rf "$TMP"' EXIT
  args=(pr view "$pr" --json body -q .body)
  [ -n "$repo" ] && args+=(--repo "$repo")
  if ! gh "${args[@]}" > "$TMP/body.md" 2> "$TMP/err"; then
    unknown "could not read the body of PR $pr: $(tail -1 "$TMP/err")"
  fi
  file="$TMP/body.md"
fi
[ -n "$file" ] || unknown "usage: pr-body-lint.sh <file> | --pr <n|url> [--repo <owner/name>]"
[ -f "$file" ] || unknown "body file $file not found"

awk '
function excerpt(s) { gsub(/^[ \t]+/, "", s); return length(s) > 60 ? substr(s, 1, 57) "..." : s }
function flag(n, rule, what, fix) { issues++; printf "LINT: %s line %d: %s → %s\n", rule, n, what, fix }
function nwords(s,   t, a, i, n, k) {
  t = s
  gsub(/\]\([^)]*\)/, "]", t)                                        # a link counts as its text
  gsub(/^[ \t]*([-*+]|[0-9]+[.)])[ \t]+(\[[ xX]\][ \t]+)?/, "", t)    # list marker, checkbox
  k = split(t, a, /[ \t]+/); n = 0
  for (i = 1; i <= k; i++) if (a[i] != "") n++
  return n
}
function ncode(s,   t) { t = s; return gsub(/`[^`]+`/, "", t) }
function linked_id(u,   id) {
  id = u
  if (id ~ /\/browse\/[A-Z][A-Z0-9]*-[0-9]+/) { sub(/.*\/browse\//, "", id); sub(/[^A-Z0-9-].*/, "", id); return "[" id "](" u ")" }
  if (id ~ /\/(pull|issues)\/[0-9]+/) { sub(/.*\/(pull|issues)\//, "", id); sub(/[^0-9].*/, "", id); return "[#" id "](" u ")" }
  return "[<what it is>](" u ")"
}
function bare_urls(s, n,   t, u) {
  t = s
  gsub(/`[^`]*`/, "", t)                       # code spans are not prose
  gsub(/\]\([^)]*\)/, "]", t)                  # [text](url) and ![alt](url)
  if (t ~ /^[ \t]*\[[^]]+\]:[ \t]/) return     # reference definition [id]: url
  while (match(t, /https?:\/\/[^ \t)>]+/)) {
    u = substr(t, RSTART, RLENGTH)
    t = substr(t, RSTART + RLENGTH)
    sub(/[.,;:!?]+$/, "", u)                   # trailing punctuation belongs to the sentence
    flag(n, "bare-url", u, "write it as a linked ID: " linked_id(u))
  }
}
function close_block(   w, c) {
  if (blk == "") return
  w = nwords(blk); c = ncode(blk)
  if (blk_bullet && w > 40)  flag(blk_line, "long-bullet", w " words: " excerpt(blk), "one idea per bullet, at most two lines")
  if (!blk_bullet && w > 60) flag(blk_line, "long-para", w " words: " excerpt(blk), "split it into short bullets, or cut it")
  if (c >= 4) flag(blk_line, "dense", c " code names: " excerpt(blk), "say what it does in words; the names live in the code")
  if (blk ~ /[{][ \t]*[A-Za-z_][A-Za-z0-9_]*[^{}]*,[ \t]*[A-Za-z_][A-Za-z0-9_]*[^{}]*[}]/)
    flag(blk_line, "internals", "a label set {a, b, ...}: " excerpt(blk), "name the effect, not the labels")
  else if (blk ~ /[A-Za-z_]+\([^()]*\)[ \t]*[-+*\/<>]/ || blk ~ /[<>]=?[ \t]*[0-9]+(ms|s|m|h|d|w)([^A-Za-z0-9]|$)/ || blk ~ /\[[0-9]+(ms|s|m|h|d|w)\]/)
    flag(blk_line, "internals", "query syntax: " excerpt(blk), "say the rule in words; the query lives in the code")
  blk = ""; blk_bullet = 0
}
BEGIN { issues = 0; body = 0; fence = ""; mermaid = 0; comment = 0; blk = "" }
{
  line = $0
  # HTML comments (PR templates are full of them): not counted, not checked
  if (comment) { if (line ~ /-->/) comment = 0; next }
  if (line ~ /^[ \t]*<!--/) { close_block(); if (line !~ /-->/) comment = 1; next }

  # fenced code: the diagram is free, other code counts as lines but is not prose
  if (fence != "") {
    if (line ~ ("^[ \t]*" fence)) fence = ""
    if (!mermaid) body++
    next
  }
  if (line ~ /^[ \t]*(```|~~~)/) {
    close_block()
    fence = (line ~ /^[ \t]*```/) ? "```" : "~~~"
    mermaid = (line ~ /^[ \t]*(```|~~~)[ \t]*mermaid/)
    if (!mermaid) body++
    next
  }

  if (line ~ /^[ \t]*$/) { close_block(); next }
  body++
  bare_urls(line, NR)

  if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*\|/) { close_block(); next }   # headings, table rows
  if (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+/) {                          # a new bullet
    close_block(); blk = line; blk_line = NR; blk_bullet = 1; next
  }
  if (blk == "") { blk = line; blk_line = NR; blk_bullet = 0 }             # a new paragraph
  else blk = blk " " line                                                  # a wrapped line
}
END {
  close_block()
  if (body > 40) flag(1, "long-body", body " lines without the diagram (about 40 at most)", "cut to what a reviewer needs; detail goes in the code, the spec or a link")
  if (issues) printf "LINT: %d issue(s) - rewrite the body as references/pull-request.md says\n", issues
  else print "LINT: ok"
}' "$file"
exit 0
