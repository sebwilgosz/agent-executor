#!/usr/bin/env bash
# review-post.sh — where a review is saved, and whether it is posted. No AI.
# Every review is a file under ~/.engineer-of-wealth/executor/reviews/ (EOW_HOME
# overrides the root), never in the repository. Posting it to GitHub is opt-in:
# the setting lives in executor/config.md.
#
#   ## Reviews
#   Post: off          (default, also with no file or no section) | own PRs
#
# Usage:   review-post.sh <pr-url> <file>
#          review-post.sh --on <pr-url> <file>     as `own PRs` for this one call (the user asked)
#          review-post.sh --path pr <pr-url>
#          review-post.sh --path branch [<name>]   (no name: HEAD)
# --path creates the folder and prints the file the review goes to:
#   reviews/<owner>/<repo>/PR-<n>.md      a PR
#   reviews/<owner>/<repo>/<branch>.md    a branch with no PR (/ becomes -)
#   reviews/local/<folder name>/...       no remote to read an owner and repo from
# A re-review of the same PR writes the same file.
#
# Posting: with `own PRs`, and only on an open PR written by the gh user, the
# file becomes a PR comment headed "Executor review", carrying the hidden marker
# <!-- executor-review -->. A comment with that marker by the same account is
# edited instead, so re-reviews never stack comments. Someone else's PR is never
# posted, whatever the setting. A review with no findings is posted as it is.
#
# Output lines, the exit code is always 0:
#   POSTED: <comment url>
#   SAVED: <file>
#   NOTE: not posted, not your PR
#   STOP: <reason>        (SAVED: <file> follows when the file exists)
set -u

EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
DIR="$EOW/executor/reviews"
MARKER='<!-- executor-review -->'

. "$(cd -P "$(dirname "$0")" && pwd)/remote-slug.sh"

if [ "${1:-}" = --path ]; then
  kind="${2:-}"; target="${3:-}"
  slug=""; name=""
  case "$kind" in
    pr)
      slug=$(printf '%s' "$target" | sed -nE 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*$#\1#p')
      n=$(printf '%s' "$target" | sed -nE 's#^.*/pull/([0-9]+).*$#\1#p')
      [ -n "$slug" ] && [ -n "$n" ] || { echo "STOP: not a pull request URL: $target"; exit 0; }
      name="PR-$n" ;;
    branch)
      [ -n "$target" ] || target=$(git branch --show-current 2>/dev/null)
      [ -n "$target" ] || { echo "STOP: no branch to name the review file"; exit 0; }
      slug=$(slug_from_url "$(git remote get-url origin 2>/dev/null)")
      [ -n "$slug" ] || slug="local/$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
      name=${target//\//-} ;;
    *) echo "STOP: --path needs pr or branch"; exit 0 ;;
  esac
  mkdir -p "$DIR/$slug" 2>/dev/null || { echo "STOP: could not create $DIR/$slug"; exit 0; }
  printf '%s/%s/%s.md\n' "$DIR" "$slug" "$name"
  exit 0
fi

force=0
[ "${1:-}" = --on ] && { force=1; shift; }
url="${1:-}"; file="${2:-}"

ERR=$(mktemp); BODY=$(mktemp)
trap 'rm -f "$ERR" "$BODY"' EXIT

saved() { [ -f "$file" ] && printf 'SAVED: %s\n' "$file"; return 0; }
stop()  { printf 'STOP: %s\n' "$1"; saved; exit 0; }
gh_why() { head -1 "$ERR" | cut -c1-160; }

[ -n "$file" ] && [ -f "$file" ] || stop "no review file to post: ${file:-none given}"

post=off
cfg="$EOW/executor/config.md"
if [ -f "$cfg" ]; then
  v=$(awk '/^## /{s=($0=="## Reviews")} s && /^[Pp]ost:/{sub(/^[Pp]ost:[ \t]*/,""); print; exit}' "$cfg" | tr '[:upper:]' '[:lower:]' | sed -E 's/[ \t]+$//')
  [ "$v" = "own prs" ] && post=own
fi
[ "$force" = 1 ] && post=own
[ "$post" = off ] && { saved; exit 0; }

slug=$(printf '%s' "$url" | sed -nE 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*$#\1#p')
n=$(printf '%s' "$url" | sed -nE 's#^.*/pull/([0-9]+).*$#\1#p')
[ -n "$slug" ] && [ -n "$n" ] || stop "not a pull request URL: $url"

out=$(gh pr view "$url" --json author,state --jq '"\(.author.login) \(.state)"' 2>"$ERR") || stop "could not read the PR: $(gh_why)"
read -r author state <<<"$out"
me=$(gh api user --jq .login 2>"$ERR") && [ -n "$me" ] || stop "could not read the gh user: $(gh_why)"

if [ "$author" != "$me" ]; then
  saved
  echo "NOTE: not posted, not your PR"
  exit 0
fi
[ "$state" = OPEN ] || stop "the PR is $state, not posting"

{
  printf '**Executor review** · by Claude, posted from this account\n%s\n\n' "$MARKER"
  cat "$file"
} > "$BODY"

id=$(gh api "repos/$slug/issues/$n/comments" --paginate \
  --jq ".[] | select(.user.login == \"$me\" and (.body | contains(\"$MARKER\"))) | .id" 2>"$ERR") || stop "could not list the PR's comments: $(gh_why)"
id=$(printf '%s\n' "$id" | head -1)

if [ -n "$id" ]; then
  link=$(gh api -X PATCH "repos/$slug/issues/comments/$id" -F "body=@$BODY" --jq .html_url 2>"$ERR") || stop "could not edit the comment: $(gh_why)"
else
  link=$(gh pr comment "$url" --body-file "$BODY" 2>"$ERR") || stop "could not post the comment: $(gh_why)"
fi
printf 'POSTED: %s\n' "$(printf '%s' "$link" | tail -1)"
saved
exit 0
