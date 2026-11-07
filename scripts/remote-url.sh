# Sourced by plan-path.sh and new-prs.sh: reads a git remote's URL. No network.

# Prints <owner>/<name> from a remote URL, nothing when it doesn't hold both.
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

# Prints the host of a remote URL, nothing when it names none. An SSH one may name
# an alias: ssh -G reads the real host from the ssh config, with no network. It also
# evaluates any Match exec there, so it runs only when the host needs resolving:
# never for HTTPS, nor for github.com, which is already the real host.
host_from_url() {
  local h real via_ssh=1
  case "$1" in
    ssh://*|git+ssh://*) h=${1#*://} ;;
    *://*) h=${1#*://}; via_ssh=0 ;;
    *:*) h=${1%%:*} ;;
    *) return 0 ;;
  esac
  h=${h%%/*}; h=${h##*@}; h=${h%%:*}
  case "$h" in [[:alnum:]]*) ;; *) return 0 ;; esac
  if [ "$via_ssh" -eq 1 ] && [ "$h" != github.com ]; then
    real=$(ssh -G "$h" 2>/dev/null </dev/null | awk '$1 == "hostname" { print $2; exit }')
    h=${real:-$h}
  fi
  printf '%s\n' "$h"
}
