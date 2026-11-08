# Sourced by every script that reads Executor's settings, so all agree on how
# $EOW_HOME/executor/config.md is parsed (EOW_HOME defaults to
# ~/.engineer-of-wealth). The one reader of the search-roots setting. Sets:
#   roots — an array of folders, in search order, from the "## Roots" list,
#           one "- <path>" line each, a leading ~ expanded. Missing file,
#           section or list: ~/Projects.
# Defines:
#   config_section <heading> — sets section_paths to the "- <path>" lines of
#           that "## <heading>" section, the same way, and section_found to 1
#           when the section exists, even with no lines, else 0.
# No output, never fails.

config_section() {
  section_paths=()
  section_found=0
  local cfg="${EOW_HOME:-$HOME/.engineer-of-wealth}/executor/config.md" inside=0 l
  [ -r "$cfg" ] || return 0
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%"${l##*[![:space:]]}"}"
    case "$l" in
      "## $1") inside=1; section_found=1; continue ;;
      "#"*) inside=0; continue ;;
    esac
    [ "$inside" -eq 1 ] || continue
    case "$l" in "- "*) ;; *) continue ;; esac
    l="${l#- }"
    l="${l#"${l%%[![:space:]]*}"}"
    case "$l" in
      "") continue ;;
      "~") l="$HOME" ;;
      "~/"*) l="$HOME/${l#\~/}" ;;
    esac
    section_paths+=("$l")
  done < "$cfg" 2>/dev/null
  return 0
}

config_section Roots
if [ "${#section_paths[@]}" -gt 0 ]; then
  roots=("${section_paths[@]}")
else
  roots=("$HOME/Projects")
fi
unset section_paths section_found
