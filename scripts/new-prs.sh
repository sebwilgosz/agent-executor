# Sourced by the PostToolUse hooks. Reads the hook event (JSON) from stdin and
# sets: kind (stack | pr, empty when no PR was created), cwd (the session's
# directory), prs and branches.
# prs holds one PR per line: the URL gh pr create printed, or for a stack each new
# PR's URL, bottom of the stack first, read from the repo gh stack ran in. A bare
# number means that repo could not be found. branches holds each stack PR's branch,
# line for line; it is empty on the pr path.
# Local only: no network, no AI. git and ssh run once at most, and only once a
# gh stack command has really reported a new PR.

event=$(cat)
kind=
prs=
branches=

# Fast exit for the ordinary tool call: these hooks run after every Bash call. Byte
# matching, since bash's multibyte match is most of the cost on a large event. The
# second check: with neither text, prs is always empty, so no PR was created.
lc_was_set=${LC_ALL+1}
lc_was=${LC_ALL-}
LC_ALL=C
case "$event" in
  *"gh pr create"* | *"gh stack submit"* | *"gh stack link"* | *create_pull_request*) ;;
  *) exit 0 ;;
esac
case "$event" in
  *"Created PR #"* | */pull/*) ;;
  *) exit 0 ;;
esac
if [ -n "$lc_was_set" ]; then LC_ALL=$lc_was; else unset LC_ALL; fi

if command -v jq >/dev/null 2>&1; then
  have_jq=1
  tool=$(printf '%s' "$event" | jq -r '.tool_name // empty')
  command=$(printf '%s' "$event" | jq -r '.tool_input.command // empty')
  response=$(printf '%s' "$event" | jq -c '.tool_response // empty')
  cwd=$(printf '%s' "$event" | jq -r '.cwd // empty')
else
  # No jq: match the raw event. Coarser, but the last PR URL is still the new one.
  have_jq=
  field() { printf '%s' "$event" | grep -oE "\"$1\" *: *\"[^\"]*\"" | head -1 | sed -E 's/.*"([^"]*)"$/\1/'; }
  tool=$(field tool_name)
  cwd=$(field cwd)
  command=$(printf '%s' "$event" | grep -aoE '"command" *: *"([^"\\]|\\.)*"' | head -1)
  if [ -n "$command" ]; then
    command=${command#*\"command\"}
    command=${command#*\"}
    command=${command%\"}
  else
    command=$event
  fi
  response=$event
fi

case "$tool" in
  Bash)
    if printf '%s' "$command" | grep -qE -- '--help|--dry-run'; then
      kind=
    elif printf '%s' "$command" | grep -qE '(^|[;&|("[:space:]])gh +stack +(submit|link)'; then
      kind=stack
    elif printf '%s' "$command" | grep -qE '(^|[;&|("[:space:]])gh +pr +create'; then
      kind=pr
    fi
    ;;
  mcp__*__create_pull_request) kind=pr ;;
esac

# The next shell token of $src from $pos: token is word, op (its character in op_char)
# or end. A word's value, unquoted, is in word; word_ok is empty when the shell would
# expand it to something only it can know. A substring of a long $src is slow in bash,
# so plain text and here-document bodies are taken in one step, never by the character.
next_token() {
  local c run
  word=
  word_ok=1
  while :; do
    c=${src:pos:1}
    case "$c" in
      ' ' | $'\t') pos=$((pos+1)) ;;
      \\) [ "${src:pos+1:1}" = $'\n' ] || break; pos=$((pos+2)) ;;
      '#')
        run=${src:pos}
        run=${run%%$'\n'*}
        pos=$((pos+${#run}))
        ;;
      *) break ;;
    esac
  done
  case "$c" in
    '') token=end; return ;;
    $'\n') pos=$((pos+1)); skip_heredoc; token=op; op_char=$c; return ;;
    ';' | '&' | '|' | '(' | ')') pos=$((pos+1)); token=op; op_char=$c; return ;;
    '<' | '>')
      if [ "${src:pos:2}" = '<<' ] && [ "${src:pos:3}" != '<<<' ]; then
        pos=$((pos+2))
        [ "${src:pos:1}" != - ] || pos=$((pos+1))
        next_token
        heredoc_end=$word
        next_token
        return
      fi
      pos=$((pos+1))
      case "${src:pos:1}" in
        '&' | '<' | '>') pos=$((pos+1)) ;;
      esac
      next_token
      return
      ;;
  esac
  token=word
  while :; do
    c=${src:pos:1}
    case "$c" in
      '' | ' ' | $'\t' | $'\n' | ';' | '&' | '|' | '(' | ')' | '<' | '>') return ;;
      \\)
        c=${src:pos+1:1}
        pos=$((pos+2))
        [ "$c" = $'\n' ] || word=$word$c
        ;;
      \')
        pos=$((pos+1))
        run=${src:pos}
        case "$run" in
          *\'*) ;;
          *) word_ok= ;;
        esac
        run=${run%%\'*}
        word=$word$run
        pos=$((pos+${#run}+1))
        ;;
      \")
        pos=$((pos+1))
        double_quoted
        ;;
      '$') expansion ;;
      '`') backticks ;;
      '~')
        if [ -z "$word" ]; then
          case "${src:pos+1:1}" in
            '' | / | ' ' | $'\t' | $'\n' | ';' | '&' | '|' | '(' | ')' | '<' | '>') home_into_word ;;
            *) word_ok=; word='~' ;;
          esac
        else
          word=$word'~'
        fi
        pos=$((pos+1))
        ;;
      '*' | '?' | '[') word_ok=; word=$word$c; pos=$((pos+1)) ;;
      *)
        run=${src:pos}
        run=${run%%[[:space:]\;\&\|\(\)\<\>\\\'\"\$\`\~\*\?\[]*}
        word=$word$run
        pos=$((pos+${#run}))
        ;;
    esac
  done
}

# Inside a double quote, $pos just past the opening one.
double_quoted() {
  local c run
  while :; do
    c=${src:pos:1}
    case "$c" in
      '') word_ok=; return ;;
      \") pos=$((pos+1)); return ;;
      \\)
        c=${src:pos+1:1}
        case "$c" in
          '$' | '`' | \" | \\) word=$word$c ;;
          *) word=$word\\$c ;;
        esac
        pos=$((pos+2))
        ;;
      '$') expansion ;;
      '`') backticks ;;
      *)
        run=${src:pos}
        run=${run%%[\"\\\$\`]*}
        word=$word$run
        pos=$((pos+${#run}))
        ;;
    esac
  done
}

# Past a newline with a here-document pending: past its closing line.
skip_heredoc() {
  [ -n "$heredoc_end" ] || return 0
  local rest=${src:pos} line=$heredoc_end
  heredoc_end=
  case "$rest" in
    "$line"$'\n'*) pos=$((pos+${#line}+1)) ;;
    *$'\n'"$line"$'\n'*)
      rest=${rest%%$'\n'"$line"$'\n'*}
      pos=$((pos+${#rest}+${#line}+2))
      ;;
    *) pos=${#src} ;;
  esac
}

home_into_word() {
  if [ -n "${HOME:-}" ]; then word=$HOME; else word_ok=; fi
}

# A $ at $pos: $HOME or ${HOME} expands at the start of a word; any other is unreadable.
expansion() {
  if [ -z "$word" ]; then
    if [ "${src:pos:7}" = '${HOME}' ]; then home_into_word; pos=$((pos+7)); return; fi
    if [ "${src:pos:5}" = '$HOME' ]; then
      case "${src:pos+5:1}" in
        [[:alnum:]_]) ;;
        *) home_into_word; pos=$((pos+5)); return ;;
      esac
    fi
  fi
  if [ "${src:pos+1:1}" = '(' ]; then
    substitution
  else
    word=$word'$'
    word_ok=
    pos=$((pos+1))
  fi
}

# A $( at $pos: its own commands, so a cd or a gh stack in it doesn't count, and its
# text stays in the word for a -c script.
substitution() {
  local outer=$word start=$pos depth=1
  pos=$((pos+2))
  while [ "$depth" -gt 0 ]; do
    next_token
    case "$token" in
      end) break ;;
      op)
        case "$op_char" in
          '(') depth=$((depth+1)) ;;
          ')') depth=$((depth-1)) ;;
        esac
        ;;
    esac
  done
  word=$outer${src:start:pos-start}
  word_ok=
}

backticks() {
  local run
  word_ok=
  run=${src:pos+1}
  run=${run%%\`*}
  word=$word'`'$run'`'
  pos=$((pos+${#run}+2))
}

# The arguments of a cd just read.
read_cd() {
  cd_seen=1
  cd_ok=1
  cd_path=
  at_command=
  while next_token; do
    case "$token" in
      word)
        case "$word" in
          -L | -P | -e | -@ | --) continue ;;
          -) cd_ok= ;;
        esac
        cd_path=$word
        [ -n "$word_ok" ] && [ -n "$word" ] || cd_ok=
        return
        ;;
      op) at_command=1 ;;
    esac
    cd_path=${HOME:-}
    [ -n "$cd_path" ] || cd_ok=
    return
  done
}

# The arguments of a gh stack command just read: the remote it names, if any.
read_remote() {
  while next_token; [ "$token" = word ]; do
    case "$word" in
      --remote) next_token; [ "$token" = word ] || return 0 ;;
      --remote=*) word=${word#--remote=} ;;
      *) continue ;;
    esac
    remote_name=$word
    case "$word" in
      '' | -*) remote_ok= ;;
    esac
    [ -n "$word_ok" ] || remote_ok=
    return
  done
}

# Walks $1 up to the gh stack it runs: the last cd before it, and its --remote. A gh
# stack in a quoted word only counts as the script of a -c: elsewhere it is a mention,
# such as a grep's pattern. stack_found stays empty then.
scan_command() {
  local before1= before2= script_re='gh +stack +(submit|link)'
  src=$1
  pos=0
  at_command=1
  heredoc_end=
  while next_token; [ "$token" != end ]; do
    if [ "$token" = op ]; then
      at_command=1; before1=; before2=
      continue
    fi
    case "$word" in
      submit | link)
        if [ "$before1" = stack ] && [ "$before2" = gh ]; then
          stack_found=1
          read_remote
          return
        fi
        ;;
    esac
    case "$before1" in
      -*c)
        if [[ $word =~ $script_re ]]; then
          scan_command "$word"
          return
        fi
        ;;
    esac
    before2=$before1
    before1=$word
    if [ -n "$at_command" ]; then
      case "$word" in
        cd) read_cd; continue ;;
        if | then | elif | else | do | while | until | '{' | '!' | time | command | builtin) continue ;;
        [[:alpha:]_]*=*) continue ;;
      esac
      at_command=
    fi
  done
}

# Sets stack_dir, the folder gh stack ran in; empty when it can't be known. A relative
# cd missing under cwd may already be in cwd: Claude Code can apply it to the event.
# A literal ~ can't be that, since the shell's cd would have failed on it.
find_stack_dir() {
  stack_dir=
  if [ -z "$cd_seen" ]; then
    stack_dir=$cwd
    return
  fi
  [ -n "$cd_ok" ] || return 0
  case "$cd_path" in
    /*) stack_dir=$cd_path; return ;;
  esac
  [ -n "$cwd" ] || return 0
  if [ -d "$cwd/$cd_path" ]; then
    stack_dir=$cwd/$cd_path
  else
    case "$cd_path" in
      '~'*) ;;
      *) stack_dir=$cwd ;;
    esac
  fi
}

# Sets repo_url, https://<host>/<owner>/<repo>, from the one remote lookup of this
# run; empty when the repo can't be known.
find_repo_url() {
  local remote host slug
  repo_url=
  [ -n "$stack_dir" ] && [ -n "$remote_ok" ] || return 0
  remote=$(git -C "$stack_dir" remote get-url "$remote_name" 2>/dev/null </dev/null) || return 0
  . "${BASH_SOURCE[0]%/*}/remote-url.sh"
  slug=$(slug_from_url "$remote")
  host=$(host_from_url "$remote")
  [ -n "$slug" ] && [ -n "$host" ] || return 0
  case "$host/$slug" in
    *[[:space:][:cntrl:]]*) return 0 ;;
  esac
  repo_url=https://$host/$slug
}

# "Created PR #N for <branch>", maybe with " (<url>)" after the number, as gh stack
# prints when it isn't on a terminal, or " (base: x)" at the end; existing PRs are
# skipped. $response is JSON-encoded here, on both paths, so a branch ends at the
# first space, closing quote or escape other than an escaped \, " or /. One grep picks
# the lines, since a bash regex over a large output takes far longer than the hook has.
parse_created() {
  local line n b seen=' ' nl=$'\n'
  created_numbers=
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=${line#Created PR #}
    n=${n%% *}
    case "$seen" in
      *" $n "*) continue ;;
    esac
    seen="$seen$n "
    b=${line#* for }
    b=${b//\\\\/$'\002'}
    b=${b//\\\"/\"}
    b=${b//\\\//\/}
    b=${b//$'\002'/\\}
    created_numbers=$created_numbers${created_numbers:+$nl}$n
    branches=$branches${branches:+$nl}$b
  done <<< "$(printf '%s' "$response" | grep -aoE 'Created PR #[0-9]+( \([^)[:space:]]*\))? for ([^"\\[:space:]]|\\["\\/])+')"
}

if [ "$kind" = stack ]; then
  parse_created
  stack_found=
  cd_seen=
  cd_ok=
  cd_path=
  remote_name=origin
  remote_ok=1
  if [ -n "$created_numbers" ]; then
    if [ -n "$have_jq" ]; then
      lc_was_set=${LC_ALL+1}
      lc_was=${LC_ALL-}
      LC_ALL=C
      scan_command "$command"
      if [ -n "$lc_was_set" ]; then LC_ALL=$lc_was; else unset LC_ALL; fi
    else
      # The raw event's quotes are escaped, so its cd stays unread and the branch
      # check guards a wrong folder. A gh stack right after a quote is a mention.
      stack_re='(^|[;&|([:space:]])gh +stack +(submit|link)'
      remote_re='--remote[ =]([[:alnum:]._/][[:alnum:]._/-]*)'
      [[ $command =~ $stack_re ]] && stack_found=1
      [[ $command =~ $remote_re ]] && remote_name=${BASH_REMATCH[1]}
    fi
  fi
  if [ -n "$stack_found" ]; then
    find_stack_dir
    find_repo_url
    while IFS= read -r n; do
      prs=$prs${prs:+$'\n'}${repo_url:+$repo_url/pull/}$n
    done <<< "$created_numbers"
  else
    branches=
  fi
elif [ "$kind" = pr ]; then
  prs=$(printf '%s' "$response" | grep -oE 'https://github\.com/[^/"[:space:]]+/[^/"[:space:]]+/pull/[0-9]+' | tail -1)
fi
[ -n "$prs" ] || kind=
