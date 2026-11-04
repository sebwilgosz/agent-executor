#!/usr/bin/env bash
# Spec tests for where build plans live: scripts/plan-path.sh, the one script
# that knows the layout, and the skills and docs that go through it.
#   A. the plans folder's order (env, config, default), --where, and that it
#      must be absolute;
#   B. the repo's folder: SSH, HTTPS, any host, no origin, a bare repo's worktree;
#   C. a new plan's name and a title from a file name;
#   D. which plans are live;
#   E. nothing created on disk, failures as a plain note, exit 0;
#   F. nothing in the repo: the skills and docs go through the script.
# No network: HOME and EOW_HOME point at a temp dir, origins are never contacted.
# It runs the script with /bin/bash where there is one: macOS's is bash 3.2.
#
# Run: bash scripts/plan-path.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd -P "$SELF_DIR/.." && pwd)
SCRIPT="$SELF_DIR/plan-path.sh"
SHELL_BIN=bash
[ -x /bin/bash ] && SHELL_BIN=/bin/bash

PASS=0; FAIL=0
ok()     { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()    { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
is()     { [ "$3" = "$2" ] && ok "$1" || bad "$1" "want: $2 | got: $3"; }
check()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute() { case "$3" in *"$2"*) bad "$1" "did not want substring: $2" ;; *) ok "$1" ;; esac; }

TMP=$(mktemp -d)
TMP=$(cd -P "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export EOW_HOME="$TMP/eow"
unset EXECUTOR_PLANS GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
mkdir -p "$HOME"
CFG="$EOW_HOME/executor/config.md"
DEFAULT="$EOW_HOME/executor/plans"
TODAY=$(date +%F)

plan_path() { "$SHELL_BIN" "$SCRIPT" "$@" 2>&1; }
config() { mkdir -p "$(dirname "$CFG")"; printf '%s\n' "$@" > "$CFG"; }
new_repo() { git init -q "$1" 2>/dev/null; [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"; }
plan() { mkdir -p "$(dirname "$1")"; printf '%b\n' "$2" > "$1"; }

echo "plan-path.sh spec tests"

WEB="$TMP/src/web"
new_repo "$WEB" "git@github.com:acme/web.git"

# A. The plans folder: env, then config, then the default.
is "no setting: the default"        "default"          "$(plan_path --where)"
is "no setting: the default folder" "$DEFAULT/acme/web" "$(plan_path "$WEB")"
is "EOW_HOME unset: ~/.engineer-of-wealth" \
  "$HOME/.engineer-of-wealth/executor/plans/acme/web" \
  "$(env -u EOW_HOME "$SHELL_BIN" "$SCRIPT" "$WEB" 2>&1)"
config "# Executor settings" "" "## Roots" "- ~/code" "" "## Other" "- /nope"
is "no Plans section: the default"  "default"          "$(plan_path --where)"
config "## Plans" "" "## Other" "- /nope"
is "empty Plans section: the default" "default"        "$(plan_path --where)"
config "# Executor settings" "" "## Roots" "- ~/code" "" "## Plans" "- ~/my plans" "- /second" "" "## Other" "- /nope"
is "config: --where"                "config"           "$(plan_path --where)"
is "config: first line wins, ~ expanded, Roots ignored" "$HOME/my plans/acme/web" "$(plan_path "$WEB")"
config "## Plans" "- /srv/plans/"
is "config: a trailing slash stays out of the path" "/srv/plans/acme/web" "$(plan_path "$WEB")"
config "## Plans" "- ~/from-config"
is "env beats config: --where"      "env"              "$(EXECUTOR_PLANS=/srv/env-plans "$SHELL_BIN" "$SCRIPT" --where 2>&1)"
is "env beats config: the folder"   "/srv/env-plans/acme/web" "$(EXECUTOR_PLANS=/srv/env-plans "$SHELL_BIN" "$SCRIPT" "$WEB" 2>&1)"
is "env: ~ expanded"                "$HOME/env/acme/web" "$(EXECUTOR_PLANS='~/env' "$SHELL_BIN" "$SCRIPT" "$WEB" 2>&1)"
is "empty env: not set"             "config"           "$(EXECUTOR_PLANS= "$SHELL_BIN" "$SCRIPT" --where 2>&1)"
rm -f "$CFG"

# A relative plans folder would put plans inside whatever folder the call runs in.
RELATIVE="STOP: the plans folder must be absolute: plans"
env_plans() { EXECUTOR_PLANS=plans "$SHELL_BIN" "$SCRIPT" "$@" 2>&1; }
is "relative env: the repo's folder stops" "$RELATIVE" "$(env_plans "$WEB")"
is "relative env: --new stops"       "$RELATIVE"        "$(env_plans --new "A title" "$WEB")"
is "relative env: --live stops"      "$RELATIVE"        "$(env_plans --live "$WEB")"
is "relative env: still exit 0"      "0"                "$(env_plans "$WEB" >/dev/null; echo $?)"
is "relative env: --where names it"  "env"              "$(env_plans --where)"
OUT=$(env_plans --summary "$WEB")
check "relative env: summary shows it" "plans (env)"    "$OUT"
check "relative env: summary says why" "must be absolute" "$OUT"
refute "relative env: summary no STOP" "STOP:"          "$OUT"
refute "relative env: summary no path" "plans/acme/web" "$OUT"
config "## Plans" "- plans"
is "relative config: the repo's folder stops" "$RELATIVE" "$(plan_path "$WEB")"
is "relative config: --new stops"    "$RELATIVE"        "$(plan_path --new "A title" "$WEB")"
is "relative config: --live stops"   "$RELATIVE"        "$(plan_path --live "$WEB")"
is "relative config: --where names it" "config"         "$(plan_path --where)"
rm -f "$CFG"

# B. The repo's folder.
slug() {
  local r="$TMP/slug/$RANDOM$RANDOM"
  new_repo "$r" "$1"
  plan_path "$r"
}
is "SSH origin"              "$DEFAULT/acme/web" "$(slug git@github.com:acme/web.git)"
is "HTTPS origin"            "$DEFAULT/acme/web" "$(slug https://github.com/acme/web.git)"
is "without .git"            "$DEFAULT/acme/web" "$(slug https://github.com/acme/web)"
is "a trailing slash"        "$DEFAULT/acme/web" "$(slug https://github.com/acme/web/)"
is "SSH without .git"        "$DEFAULT/acme/web" "$(slug git@github.com:acme/web)"
is "any host"                "$DEFAULT/acme/web" "$(slug git@git.example.org:acme/web.git)"
is "ssh:// with a port"      "$DEFAULT/acme/web" "$(slug ssh://git@git.example.org:2222/acme/web.git)"
is "credentials stay out"    "$DEFAULT/acme/web" "$(slug https://user:secret@github.com/acme/web.git)"
is "as written: case kept"   "$DEFAULT/Acme/Web" "$(slug git@github.com:Acme/Web.git)"
is "a dot in the name"       "$DEFAULT/acme/web.app" "$(slug git@github.com:acme/web.app.git)"
is "a deeper path: the last two parts" "$DEFAULT/team/web" "$(slug https://gitlab.example.org/acme/team/web.git)"

# The origin's host, which the folder drops. A stub stands in for `ssh -G`.
SSH_BIN="$TMP/ssh-stub"; mkdir -p "$SSH_BIN"
cat > "$SSH_BIN/ssh" <<'STUB_EOF'
#!/bin/sh
[ "$1" = "-G" ] || exit 1
case "$2" in work-alias) h=git.example.org ;; *) h=$2 ;; esac
printf 'user git\nhostname %s\n' "$h"
STUB_EOF
chmod +x "$SSH_BIN/ssh"
host_of() {
  local r="$TMP/slug/$RANDOM$RANDOM"
  new_repo "$r" "$1"
  PATH="$SSH_BIN:$PATH" plan_path --host "$r"
}
is "host: SSH origin"          "git.example.org" "$(host_of git@git.example.org:acme/web.git)"
is "host: HTTPS origin"        "github.com"      "$(host_of https://github.com/acme/web.git)"
is "host: ssh:// with a port"  "git.example.org" "$(host_of ssh://git@git.example.org:2222/acme/web.git)"
is "host: credentials stay out" "github.com"     "$(host_of https://user:secret@github.com/acme/web.git)"
is "host: an SSH alias is read as its real host" "git.example.org" "$(host_of git@work-alias:acme/web.git)"
is "host: an HTTPS name is not an SSH alias" "work-alias" "$(host_of https://work-alias/acme/web.git)"
is "host: a path has none"     ""                "$(host_of /srv/git/acme/web.git)"
is "host: a file URL has none" ""                "$(host_of file:///srv/git/acme/web.git)"
is "host: an option is no host" ""               "$(host_of git@-oProxyCommand=x:acme/web.git)"

NOPE="$TMP/src/no-remote"
new_repo "$NOPE"
is "no origin: local/<folder>" "$DEFAULT/local/no-remote" "$(plan_path "$NOPE")"
is "host: no origin has none" "" "$(plan_path --host "$NOPE")"
mkdir -p "$NOPE/deep/er"
is "from a subfolder"          "$DEFAULT/local/no-remote" "$(plan_path "$NOPE/deep/er")"
is "from the current folder"   "$DEFAULT/local/no-remote" "$(cd "$NOPE/deep" && "$SHELL_BIN" "$SCRIPT" 2>&1)"
ODD="$TMP/slug/odd"
new_repo "$ODD" "../../web"
is "an origin that climbs out: no .. in the path" "$DEFAULT/local/odd" "$(plan_path "$ODD")"

git -C "$NOPE" -c user.name=t -c user.email=t@example.org commit -q --allow-empty -m first
BARE="$TMP/bare/shop.git"
mkdir -p "$TMP/bare"
git clone -q --bare "$NOPE" "$BARE" 2>/dev/null
git -C "$BARE" remote remove origin
git -C "$BARE" worktree add -q "$TMP/bare/wt-one" -b one 2>/dev/null
git -C "$BARE" worktree add -q "$TMP/bare/wt-two" -b two 2>/dev/null
is "bare repo, no origin: its folder without .git" "$DEFAULT/local/shop" "$(plan_path "$BARE")"
is "a worktree of a bare repo"       "$DEFAULT/local/shop" "$(plan_path "$TMP/bare/wt-one")"
is "another worktree: the same folder" "$DEFAULT/local/shop" "$(plan_path "$TMP/bare/wt-two")"
git -C "$BARE" remote add origin git@github.com:acme/shop.git
is "a worktree of a bare repo with origin" "$DEFAULT/acme/shop" "$(plan_path "$TMP/bare/wt-one")"
git -C "$NOPE" worktree add -q "$TMP/src/no-remote-wt" -b side 2>/dev/null
is "a worktree of a normal repo: the main folder's name" "$DEFAULT/local/no-remote" "$(plan_path "$TMP/src/no-remote-wt")"

# C. A title from a file name, a new plan's name.
is "title: spec - x.md"      "Invite flow" "$(plan_path --title 'spec - Invite flow.md')"
is "title: x - spec.md"      "Invite flow" "$(plan_path --title 'Invite flow - spec.md')"
is "title: a full path"      "Invite flow" "$(plan_path --title '/notes/some dir/spec - Invite flow.md')"
is "title: plain x.md"       "Invite flow" "$(plan_path --title 'Invite flow.md')"
is "title: spec inside stays" "the spec - review" "$(plan_path --title 'the spec - review.md')"
check "title: nothing given" "STOP:" "$(plan_path --title)"

F="$DEFAULT/acme/web"
is "new: date and title"     "$F/$TODAY - Invite flow.md" "$(plan_path --new 'Invite flow' "$WEB")"
is "new: from the current folder" "$F/$TODAY - Invite flow.md" "$(cd "$WEB" && "$SHELL_BIN" "$SCRIPT" --new 'Invite flow' 2>&1)"
is "new: a leading Spec: stripped" "$F/$TODAY - Invite flow.md" "$(plan_path --new 'Spec: Invite flow' "$WEB")"
is "new: only a leading Spec:" "$F/$TODAY - Why Spec- matters.md" "$(plan_path --new 'Why Spec: matters' "$WEB")"
is "new: / and : turned into -" "$F/$TODAY - a-b- c.md" "$(plan_path --new 'a/b: c' "$WEB")"
tab=$(printf 'a\tb\nc')
is "new: control characters turned into -" "$F/$TODAY - a-b-c.md" "$(plan_path --new "$tab" "$WEB")"
is "new: other characters kept" "$F/$TODAY - Zażółć & \$x (1).md" "$(plan_path --new 'Zażółć & $x (1)' "$WEB")"
check "new: an empty title is a plain note" "STOP:" "$(plan_path --new '' "$WEB")"
check "new: only Spec: is a plain note"     "STOP:" "$(plan_path --new 'Spec: ' "$WEB")"

mkdir -p "$F"
: > "$F/$TODAY - Taken.md"
is "new: taken, a suffix"    "$F/$TODAY - Taken 2.md" "$(plan_path --new 'Taken' "$WEB")"
: > "$F/$TODAY - Taken 2.md"
is "new: taken twice, the next suffix" "$F/$TODAY - Taken 3.md" "$(plan_path --new 'Taken' "$WEB")"
rm -rf "$DEFAULT"

# D. Live plans.
L="$DEFAULT/acme/web"
is "live: the folder is missing" "" "$(plan_path --live "$WEB")"
mkdir -p "$L"
is "live: none in the folder"    "" "$(plan_path --live "$WEB")"
plan "$L/2026-01-10 - One.md" '# Build: One\nSpec: [One](/x/one.md)\n\n## Stack A: a\n- [ ] item'
is "live: one" "$L/2026-01-10 - One.md" "$(plan_path --live "$WEB")"
is "live: from the current folder" "$L/2026-01-10 - One.md" "$(cd "$WEB" && "$SHELL_BIN" "$SCRIPT" --live 2>&1)"
plan "$L/2026-03-02 - Two.md" '# Build: Two\nSpec: [Two](/x/two.md)\n\n## Stack A: a\n- [ ] item'
is "live: two, newest first" "$L/2026-03-02 - Two.md
$L/2026-01-10 - One.md" "$(plan_path --live "$WEB")"
plan "$L/2026-02-01 - Done.md" '# Build: Done\nSpec: [Done](/x/done.md)\nStatus: done 2026-02-20\n\n## Stack A: a\n- [x] item'
is "live: a done plan skipped" "$L/2026-03-02 - Two.md
$L/2026-01-10 - One.md" "$(plan_path --live "$WEB")"
plan "$L/2026-02-02 - Body.md" '# Build: Body\n\n## Notes\nStatus: done 2026-02-20'
plan "$L/2026-02-03 - Nodate.md" '# Build: Nodate\nStatus: done\n\n## Stack'
plan "$L/2026-02-04 - Prose.md" '# Build: Prose\nThe Status: done 2026-02-20 line\n\n## Stack'
is "live: only a dated Status line in the header counts" "$L/2026-03-02 - Two.md
$L/2026-02-04 - Prose.md
$L/2026-02-03 - Nodate.md
$L/2026-02-02 - Body.md
$L/2026-01-10 - One.md" "$(plan_path --live "$WEB")"
rm -f "$L/2026-02-02 - Body.md" "$L/2026-02-03 - Nodate.md" "$L/2026-02-04 - Prose.md"
plan "$L/legacy/2026-04-01 - Old.md" '# Build: Old'
plan "$L/legacy/plan.md" '# Build: Old'
plan "$L/notes.txt" 'not a plan'
mkdir -p "$L/folder.md"
is "live: legacy/, other files and a folder ignored" "$L/2026-03-02 - Two.md
$L/2026-01-10 - One.md" "$(plan_path --live "$WEB")"
rm -rf "$DEFAULT"

# E. Reads create nothing; failures are a plain note and exit 0.
config "## Plans" "- $TMP/never-made"
before=$(find "$TMP" | sort)
plan_path "$WEB" >/dev/null
plan_path --where >/dev/null
plan_path --title 'spec - x.md' >/dev/null
plan_path --new 'x' "$WEB" >/dev/null
plan_path --live "$WEB" >/dev/null
plan_path --summary "$WEB" >/dev/null
is "no read creates anything" "$before" "$(find "$TMP" | sort)"
rm -f "$CFG"

NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"
for args in "$NOGIT" "--live $NOGIT" "--new x $NOGIT"; do
  # shellcheck disable=SC2086
  out=$(plan_path $args); rc=$?
  is "not a repo ($args): exit 0" 0 "$rc"
  is "not a repo ($args): one line" 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  check "not a repo ($args): says so" "STOP: not a git repository" "$out"
done
check "not a repo, current folder: says so" "STOP: not a git repository" "$(cd "$NOGIT" && "$SHELL_BIN" "$SCRIPT" 2>&1)"
check "a repo that doesn't exist: says so"  "STOP: not a git repository" "$(plan_path "$TMP/gone")"
is "--where needs no repo"  "default" "$(cd "$NOGIT" && "$SHELL_BIN" "$SCRIPT" --where 2>&1)"
is "--title needs no repo"  "x" "$(cd "$NOGIT" && "$SHELL_BIN" "$SCRIPT" --title 'spec - x.md' 2>&1)"
out=$(plan_path --nonsense); rc=$?
check "an unknown option: a plain note" "STOP:" "$out"
is "an unknown option: exit 0" 0 "$rc"

BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\necho "fatal: boom" >&2\nexit 128\n' > "$BIN/git"
chmod +x "$BIN/git"
out=$(PATH="$BIN:$PATH" "$SHELL_BIN" "$SCRIPT" "$WEB" 2>&1); rc=$?
is "git failing: exit 0" 0 "$rc"
check "git failing: the plain note" "STOP: not a git repository" "$out"
refute "git failing: no raw error" "fatal" "$out"

mkdir -p "$F"
plan "$F/2026-05-01 - Live one.md" '# Build: Live one\n\n## Stack'
out=$(plan_path --summary "$WEB")
check "summary: the plans folder and its source" "$DEFAULT (default)" "$out"
check "summary: this repo's folder" "$F" "$out"
check "summary: the live plans" "$F/2026-05-01 - Live one.md" "$out"
check "summary: points at init" "/executor:init" "$out"
check "summary: env named" "/srv/env (env)" "$(EXECUTOR_PLANS=/srv/env "$SHELL_BIN" "$SCRIPT" --summary "$WEB" 2>&1)"
out=$(plan_path --summary "$NOGIT"); rc=$?
is "summary outside a repo: exit 0" 0 "$rc"
check "summary outside a repo: still the plans folder" "$DEFAULT (default)" "$out"
check "summary outside a repo: says so" "not a git repository" "$out"
refute "summary outside a repo: no STOP" "STOP:" "$out"
rm -rf "$DEFAULT"

# F. Nothing in the repo: the skills and docs go through the script.
cd "$REPO_ROOT" || exit 1
docs="skills references agents README.md CONTRIBUTING.md"
# shellcheck disable=SC2086
leftover=$(grep -rnE '\.executor|info/exclude' $docs | grep -iv legacy)
is "skills and docs write no .executor or .git/info/exclude" "" "$leftover"
check "the changelog keeps its history" '.executor/plan.md' "$(cat CHANGELOG.md)"

BUILD=$(cat skills/build/SKILL.md)
PLANDOC=$(cat references/plan.md)
INIT=$(cat skills/init/SKILL.md)
INITDOC=$(cat references/init.md)
README=$(cat README.md)
HELP=$(cat skills/help/SKILL.md)

check "build: finds live plans through the script" 'scripts/plan-path.sh --live' "$BUILD"
check "build: names a new plan through the script" 'scripts/plan-path.sh --new' "$BUILD"
check "build: titles a local spec through the script" 'scripts/plan-path.sh --title' "$BUILD"
check "build: may run the script"  'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh:*)' "$BUILD"
refute "build: never replaces a plan" 'replace the plan' "$BUILD"
check "plan doc: where plans live" 'scripts/plan-path.sh' "$PLANDOC"
check "plan doc: how they are named" '<YYYY-MM-DD> - <title>.md' "$PLANDOC"
check "plan doc: which one is live" 'Status: done <date>' "$PLANDOC"

check "init: may run the script"   'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh:*)' "$INIT"
check "init: ends with the plans summary" 'plan-path.sh --summary' "$INIT"
heads=$(grep -E '^## E[0-9]' references/init.md | sed 's/^## //')
is "init: the plans step follows the roots, the check follows it" "E1: Tools
E2: Enable Executor in this repository
E3: Search roots
E4: Plans folder
E5: Check" "$heads"
check "init: suggests the default"      '~/.engineer-of-wealth/executor/plans' "$INITDOC"
check "init: writes a Plans section"    '## Plans' "$INITDOC"
check "init: moving moves nothing"      'moves nothing' "$INITDOC"
check "init: prints the mv"             'mv ' "$INITDOC"
check "init: the env var wins"          '$EXECUTOR_PLANS' "$INITDOC"
check "init: no mv while the env var is set" 'With `$EXECUTOR_PLANS` set, print no `mv`' "$INITDOC"
check "init: the config folder waits for the unset" 'once the variable is unset' "$INITDOC"

check "help: runs the summary" 'plan-path.sh --summary' "$HELP"
check "help mod: runs the summary" 'plan-path.sh' "$(cat hooks/register.ts)"

check "README: the section"     '## Where plans live' "$README"
check "README: the layout"      '<org>/<repo>/' "$README"
check "README: init"            '/executor:init' "$README"
check "README: the config file" '~/.engineer-of-wealth/executor/config.md' "$README"
check "README: the env var"     'EXECUTOR_PLANS' "$README"
check "README: a symlink"       'ln -s' "$README"

local_refs=$(grep -nE '/Users/|\[\[[A-Za-z]' scripts/plan-path.sh references/plan.md skills/build/SKILL.md)
is "nothing local in what ships" "" "$local_refs"

echo
printf 'plan-path.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
