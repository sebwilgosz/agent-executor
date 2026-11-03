# Sourced by every script that looks for a PR's local checkout, so all agree
# on where to look. The one reader of the search-roots setting. Sets:
#   roots — an array of folders, in search order, from the "## Roots" list
#           of $EOW_HOME/executor/config.md (EOW_HOME defaults to
#           ~/.engineer-of-wealth), one "- <path>" line each, a leading ~
#           expanded. Missing file, section or list: ~/Projects.
# No output, never fails.

roots=()
_roots_cfg="${EOW_HOME:-$HOME/.engineer-of-wealth}/executor/config.md"
if [ -r "$_roots_cfg" ]; then
  _roots_in=0
  while IFS= read -r _roots_l || [ -n "$_roots_l" ]; do
    _roots_l="${_roots_l%"${_roots_l##*[![:space:]]}"}"
    case "$_roots_l" in
      "## Roots") _roots_in=1; continue ;;
      "#"*) _roots_in=0; continue ;;
    esac
    [ "$_roots_in" -eq 1 ] || continue
    case "$_roots_l" in "- "*) ;; *) continue ;; esac
    _roots_l="${_roots_l#- }"
    _roots_l="${_roots_l#"${_roots_l%%[![:space:]]*}"}"
    case "$_roots_l" in
      "") continue ;;
      "~") _roots_l="$HOME" ;;
      "~/"*) _roots_l="$HOME/${_roots_l#\~/}" ;;
    esac
    roots+=("$_roots_l")
  done < "$_roots_cfg" 2>/dev/null
fi
if [ "${#roots[@]}" -eq 0 ]; then
  roots=("$HOME/Projects")
fi
unset _roots_cfg _roots_in _roots_l
