#!/usr/bin/env bash
# Spec tests for scripts/repo-audit.sh: the per-repo cost audit. Read-only, one finding
# per line ending in "→ <what to do>", a summary line last, exit 0 (--strict: 1 warnings,
# 2 errors). Plus the guards that keep it user-only: only init mentions it, init stays
# disable-model-invocation, and init can neither install the hook nor open a PR.
# No network: a stub `gh` on PATH. HOME and EOW_HOME point at a temp dir.
#
# Run: bash scripts/repo-audit.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd -P "$SELF_DIR/.." && pwd)
AUDIT="$SELF_DIR/repo-audit.sh"
HOOKS="$SELF_DIR/git-hooks.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }
code()  { local want=$1 name=$2; shift 2; bash "$AUDIT" "$@" >/dev/null 2>&1; local rc=$?; [ "$rc" -eq "$want" ] && ok "$name" || bad "$name" "want exit $want, got $rc"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
export HOME="$TMP/home"; mkdir -p "$HOME"
export EOW_HOME="$TMP/eow"
export EXECUTOR_HEAVY_DIR="$TMP/heavy"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_SYSTEM=/dev/null
git config --global user.email t@t
git config --global user.name t
git config --global init.defaultBranch main
export PATH="$BIN:$PATH"

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "extension list") echo "gh stack  github/gh-stack  v0.3.0" ;;
  "api repos/"*) echo true ;;
esac
exit 0
STUB
chmod +x "$BIN/gh"

TESTWF='name: test
on:
  pull_request:
jobs:
  t:
    runs-on: ubuntu-latest
    steps:
      - run: npm test
'
LINTWF='name: lint
on:
  pull_request:
jobs:
  t:
    runs-on: ubuntu-latest
    steps:
      - run: npm run lint
'

# mkrepo <name> <url>: lint and test scripts, a test workflow, the commit hook, Executor enabled.
mkrepo() {
  local d="$TMP/$1"
  mkdir -p "$d/.github/workflows" "$d/.claude"
  git -C "$d" init -q
  [ -z "${2:-}" ] || git -C "$d" remote add origin "$2"
  printf '{"scripts":{"lint":"eslint .","test":"jest"}}\n' > "$d/package.json"
  printf '%s' "$TESTWF" > "$d/.github/workflows/test.yml"
  printf '{"enabledPlugins":{"executor@engineer-of-wealth":true}}\n' > "$d/.claude/settings.json"
  git -C "$d" add -A
  git -C "$d" commit -q -m init
  bash "$HOOKS" install "$d" >/dev/null 2>&1
  printf '%s' "$d"
}

run() { bash "$AUDIT" "$@" 2>&1; }

d=$(mkrepo clean git@github.com:o/clean.git)
out=$(run "$d")
check "nothing missing: PASS summary" "repo-audit: PASS — " "$out"
refute "nothing missing: no finding" "→" "$out"
code 0 "nothing missing: exit 0" "$d"
code 0 "--strict clean exits 0" --strict "$d"

d=$(mkrepo noci git@github.com:o/noci.git)
rm "$d/.github/workflows/test.yml"
git -C "$d" add -A; git -C "$d" commit -q -m x
out=$(run "$d")
check "no CI: names the cost and the fix" "full suite runs in model turns on every PR → add a CI workflow (/executor:init offers one)" "$out"
check "no CI: FAIL" "repo-audit: FAIL" "$out"
code 2 "--strict with an error exits 2" --strict "$d"
code 0 "an error still exits 0 without --strict" "$d"
[ -z "$(git -C "$d" status --porcelain)" ] && ok "read-only: nothing changed" || bad "read-only" "tree changed"

d=$(mkrepo hookoff git@github.com:o/hookoff.git)
bash "$HOOKS" uninstall "$d" >/dev/null 2>&1
out=$(run "$d")
check "hook off: cost and install command" "lint and type check run as model turns → bash " "$out"

d=$(mkrepo bypass git@github.com:o/bypass.git)
git -C "$d" config core.hooksPath "$TMP/elsewhere"
out=$(run "$d")
check "hook bypassed: says so" "core.hooksPath" "$out"
refute "hook bypassed: no install offer" "git-hooks.sh install" "$out"

d=$(mkrepo nochecks git@github.com:o/nochecks.git)
printf '{"scripts":{"test":"jest"}}\n' > "$d/package.json"
out=$(run "$d")
check "no lint or type check: says the hook would check nothing" "check nothing" "$out"
refute "no lint or type check: no install offer" "git-hooks.sh install" "$out"

d=$(mkrepo lintonly git@github.com:o/lintonly.git)
printf '%s' "$LINTWF" > "$d/.github/workflows/test.yml"
out=$(run "$d")
check "lint-only CI: warns" "only lints" "$out"
check "lint-only CI: WARN not FAIL" "repo-audit: WARN" "$out"
code 1 "--strict with a warning exits 1" --strict "$d"
printf '{"scripts":{"lint":"eslint ."}}\n' > "$d/package.json"
out=$(run "$d")
refute "lint-only CI without a test command: no warning" "only lints" "$out"

mkdir -p "$TMP/plain"
out=$(run "$TMP/plain")
check "not a repo: a finding" "not a git repository → " "$out"
check "not a repo: summary" "repo-audit: FAIL" "$out"
code 0 "not a repo: exit 0" "$TMP/plain"
out=$(run "$TMP/does-not-exist")
check "missing folder: a finding, no crash" "→" "$out"
d=$(mkrepo noremote "")
out=$(run "$d")
check "no remote: a finding" "no origin remote" "$out"

d=$(mkrepo gitlab git@gitlab.com:o/r.git)
out=$(run "$d")
check "non-GitHub host: a finding" "not on GitHub" "$out"
check "non-GitHub host: summary" "repo-audit:" "$out"
code 0 "non-GitHub host: exit 0" "$d"

# An SSH alias for github.com (Host github-work / HostName github.com) is GitHub.
cat > "$BIN/ssh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "-G" ] && [ "$2" = "github-work" ] && { echo "hostname github.com"; exit 0; }
echo "hostname $2"
STUB
chmod +x "$BIN/ssh"
d=$(mkrepo alias git@github-work:o/alias.git)
out=$(run "$d")
refute "ssh alias for github.com: not a non-GitHub finding" "not on GitHub" "$out"
check "ssh alias for github.com: PASS summary" "repo-audit: PASS — " "$out"
rm "$BIN/ssh"

d=$(mkrepo extras git@github.com:o/extras.git)
rm "$d/.claude/settings.json"
out=$(run "$d")
check "Executor not enabled: reported" "Executor is not enabled in this repo" "$out"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "extension list") echo "nothing" ;;
  "api repos/"*) echo false ;;
esac
exit 0
STUB
out=$(run "$d")
check "no gh stack: reported" "gh extension install github/gh-stack" "$out"
check "auto-delete off: reported" "Automatically delete head branches" "$out"

others=$(cd "$REPO" && grep -rlF 'repo-audit.sh' . --exclude-dir=.git --exclude-dir=node_modules \
  | sed 's#^\./##' \
  | grep -vxE 'skills/init/SKILL.md|references/init.md|scripts/repo-audit.sh|scripts/repo-audit.test.sh|CHANGELOG.md')
[ -z "$others" ] && ok "only init, the script, its test and the changelog mention repo-audit.sh" || bad "repo-audit.sh is user-only" "also named in: $others"
INIT="$REPO/skills/init/SKILL.md"
front=$(sed -n '1,/^---$/{/^---$/!p;}' "$INIT" | sed 1d)
printf '%s\n' "$front" | grep -q '^disable-model-invocation:[[:space:]]*true' && ok "init keeps disable-model-invocation: true" || bad "init keeps disable-model-invocation" "missing"
tools=$(printf '%s\n' "$front" | grep '^allowed-tools:')
check "init may run repo-audit.sh" "scripts/repo-audit.sh" "$tools"
refute "init may not install the hook" "git-hooks.sh" "$tools"
refute "init may not open a PR" "pr-open.sh" "$tools"
grep -q '^## E2c' "$REPO/references/init.md" && ok "init has E2c" || bad "init has E2c" "missing"
e6=$(sed -n '/^## E6/,/^## Rules/p' "$REPO/references/init.md")
check "E6 runs repo-audit.sh" "repo-audit.sh" "$e6"
check "E6 runs self-audit.sh" "self-audit.sh" "$e6"
e2c=$(sed -n '/^## E2c/,/^## E3/p' "$REPO/references/init.md")
check "E2c applies nothing" "Executor applies none of it" "$e2c"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
