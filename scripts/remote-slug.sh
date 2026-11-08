# Sourced by plan-path.sh and pull-repos.sh, so both read a remote URL the same
# way, in any form (git@, https, ssh://). No network, never fails. Defines:
#   slug_from_url <url> — prints <owner>/<name>, the last two parts of the URL as
#                         written there, without .git; nothing when it doesn't
#                         hold both.

slug_from_url() {
  local p owner name
  case "$1" in
    *://*/*) p=${1#*://}; p=${p#*/} ;;
    *://*) return 0 ;;
    *:*) p=${1#*:} ;;
    *) p=$1 ;;
  esac
  while [ "${p%/}" != "$p" ]; do p=${p%/}; done
  case "$p" in */*) ;; *) return 0 ;; esac
  name=${p##*/}; name=${name%.git}
  p=${p%/*}; owner=${p##*/}
  case "$owner" in ""|.|..) return 0 ;; esac
  case "$name" in ""|.|..) return 0 ;; esac
  printf '%s/%s' "$owner" "$name"
}
