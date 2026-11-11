#!/usr/bin/env bash
# review-verdicts.sh <review-file> <verdicts-file>
# Applies the verifiers' verdicts to a review file, so the caller never reads it:
#   DEBUNKED      the finding is removed
#   RECLASSIFIED  the drafted finding moves to the top of Suggestions; the verifier's
#                 one line replaces its header line when it starts with `#<n>`, else its
#                 defect sentence; Fails when and the fix line stay
#   CONFIRMED     the drafted finding stays Critical, untouched
# The verifier's SEVERITY is ignored: the verdict decides.
# Findings are renumbered #1..#n across both sections and the heading counts fixed.
#
# The verdicts file holds one block per verdict: a header line `#<n> <VERDICT>`,
# then, optionally, the verifier'"'"'s one-line FINDING (until the next header). A leading
# `FINDING:` is dropped and the `#<n>` may be missing. Only its first line is used, and
# only for RECLASSIFIED. Without it the finding keeps its drafted wording. A Critical with no verdict
# (a failed build or red CI) is left as it is.
#
# Prints `APPLIED: <c> Critical, <s> Suggestions`. On bad input it prints one
# `STOP: <why>` line, exits 1 and leaves the file untouched.
set -u

stop() { printf 'STOP: %s\n' "$1"; exit 1; }

[ $# -eq 2 ] || stop "usage: review-verdicts.sh <review-file> <verdicts-file>"
REVIEW=$1; VERDICTS=$2
[ -f "$REVIEW" ]   || stop "review file not found: $REVIEW"
[ -f "$VERDICTS" ] || stop "verdicts file not found: $VERDICTS"

OUT=$(mktemp) || stop "cannot create a temporary file"
ERR=$(mktemp) || stop "cannot create a temporary file"
trap 'rm -f "$OUT" "$ERR" "$ERR.res"' EXIT

awk -v vfile="$VERDICTS" -v out="$OUT" '
function fail(msg) { print msg > "/dev/stderr"; failed = 1; exit 1 }
function isfinding(l) { return l ~ /^(\*\*)?#[0-9]+(\*\*)?:?([ \t]|$)/ }
function fnum(l,   t) { t = l; sub(/^(\*\*)?#/, "", t); sub(/[^0-9].*$/, "", t); return t + 0 }
function trim(s) { gsub(/^\n+/, "", s); gsub(/\n+$/, "", s); return s }
function renum(text, n,   p, first, rest) {
  p = index(text, "\n")
  if (p) { first = substr(text, 1, p - 1); rest = substr(text, p) } else { first = text; rest = "" }
  if (match(first, /^\*\*#[0-9]+\*\*/)) first = "**#" n "**" substr(first, RLENGTH + 1)
  else if (match(first, /^#[0-9]+/)) first = "#" n substr(first, RLENGTH + 1)
  else fail("a finding does not start with its number: " first)
  return first rest
}
function vline(b,   p) {
  p = index(b, "\n"); if (p) b = substr(b, 1, p - 1)
  sub(/^[ \t]*(\*\*)?FINDING(\*\*)?:[ \t]*/, "", b)
  sub(/[ \t]+$/, "", b)
  return b
}
function reclass(draft, vt,   a, na, i, out2, j) {
  if (vt == "") return draft
  if (vt ~ /^(\*\*)?#[0-9]+/) {
    na = split(draft, a, "\n"); out2 = vt
    for (i = 2; i <= na; i++) out2 = out2 "\n" a[i]
    return out2
  }
  na = split(draft, a, "\n"); out2 = a[1] "\n" vt
  for (i = 2; i <= na; i++) if (a[i] ~ /^[ \t]*$/) break
  for (j = i; j <= na; j++) out2 = out2 "\n" a[j]
  return out2
}
function emit(count, list, name,   i) {
  printf "## %s (%d)\n\n", name, count > out
  if (count == 0) { print "None." > out; return }
  for (i = 1; i <= count; i++) { print list[i] > out; if (i < count) print "" > out }
}
BEGIN {
  nv = 0; cur = ""
  while ((getline line < vfile) > 0) {
    if (line ~ /^#[0-9]+[ \t]+[A-Z]+[ \t]*$/) {
      split(line, h, /[ \t]+/); n = substr(h[1], 2) + 0; v = h[2]
      if (v != "CONFIRMED" && v != "DEBUNKED" && v != "RECLASSIFIED") fail("unknown verdict " v " for #" n)
      if (n in verdict) fail("two verdicts for #" n)
      verdict[n] = v; body[n] = ""; cur = n; nv++
    } else if (cur == "") {
      if (line !~ /^[ \t]*$/) fail("the verdicts file has text before its first verdict header")
    } else body[cur] = body[cur] "\n" line
  }
  if (nv == 0) fail("the verdicts file has no verdicts")
  for (n in verdict) body[n] = vline(trim(body[n]))
  section = 0; nc = 0; ns = 0; pre = ""; post = ""; cf = 0
}
{
  if (section == 0 && $0 ~ /^## CRITICAL[ \t]*(\(|$)/) { section = 1; cf = 0; next }
  if (section == 1 && $0 ~ /^## Suggestions[ \t]*(\(|$)/) { section = 2; cf = 0; next }
  if (section == 1 && $0 ~ /^## /) fail("no Suggestions section right after CRITICAL")
  if (section == 2 && $0 ~ /^## /) section = 3
  if (section == 0) { pre = pre $0 "\n"; next }
  if (section == 3) { post = post $0 "\n"; next }
  if (isfinding($0)) {
    cf = 1
    if (section == 1) { nc++; ctext[nc] = $0; cnum[nc] = fnum($0) }
    else { ns++; stext[ns] = $0 }
    next
  }
  if (!cf) next
  if (section == 1) ctext[nc] = ctext[nc] "\n" $0
  else stext[ns] = stext[ns] "\n" $0
}
END {
  if (failed) exit 1
  if (section < 2) fail("the review file has no CRITICAL and Suggestions sections")
  for (i = 1; i <= nc; i++) { ctext[i] = trim(ctext[i]); bynum[cnum[i]] = i }
  for (i = 1; i <= ns; i++) stext[i] = trim(stext[i])
  for (n in verdict) if (!(n in bynum)) fail("verdict for #" n ", which is not a Critical finding")
  kc = 0; moved = 0
  for (i = 1; i <= nc; i++) {
    n = cnum[i]; v = (n in verdict) ? verdict[n] : "NONE"
    if (v == "DEBUNKED") continue
    if (v == "RECLASSIFIED") { moved++; mtext[moved] = reclass(ctext[i], body[n]); continue }
    kc++; keep[kc] = ctext[i]
  }
  total = 0
  for (i = 1; i <= kc; i++) { total++; fin_c[i] = renum(keep[i], total) }
  for (i = 1; i <= moved; i++) { total++; fin_s[i] = renum(mtext[i], total) }
  for (i = 1; i <= ns; i++) { total++; fin_s[moved + i] = renum(stext[i], total) }
  if (failed) exit 1
  printf "%s", pre > out
  emit(kc, fin_c, "CRITICAL")
  print "" > out
  emit(moved + ns, fin_s, "Suggestions")
  if (post != "") { print "" > out; printf "%s", post > out }
  close(out)
  printf "APPLIED: %d Critical, %d Suggestions\n", kc, moved + ns
}
' "$REVIEW" > "$ERR.res" 2> "$ERR"
rc=$?
RES=$(cat "$ERR.res" 2>/dev/null); rm -f "$ERR.res"
if [ "$rc" -ne 0 ]; then
  stop "$(head -n 1 "$ERR")"
fi
cp "$OUT" "$REVIEW" || stop "could not write $REVIEW"
printf '%s\n' "$RES"
