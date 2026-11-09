#!/usr/bin/env bash
# repo-audit.sh [<repo dir>] — what one repository is missing of the setup that saves
# tokens and turns. Read-only. User-only: /executor:init runs it, nothing else does.
# CI:      ci-checks.sh --detect (none: the full suite runs in model turns on every PR;
#          lint-only while the repo has a test command: a warning)
# HOOKS:   git-hooks.sh status (off: lint and type check run as model turns;
#          bypassed by core.hooksPath, or nothing to check: no install offered)
# PLUS:    gh stack, GitHub's "Automatically delete head branches", Executor enabled.
#
# Same contract as self-audit.sh: every finding ends with "→ <what to do>", a summary
# line closes the output, and the exit code is 0 so a caller has no reason to retry.
# A missing repo, remote or GitHub host is a finding, never a crash.
#   repo-audit: PASS|WARN|FAIL — N passed, N errors, N warnings
# -v       also print what passed
# --strict exit 0 clean, 1 warnings, 2 errors (for hooks and cron)

exec 2>/dev/null

VERBOSE=0; STRICT=0; DIR=.
for a in "$@"; do
  case "$a" in -v) VERBOSE=1 ;; --strict) STRICT=1 ;; *) DIR=$a ;; esac
done
ERRS=0; WARNS=0; OKS=0; DONE=0
err()  { printf '  ✗ %s\n' "$1"; ERRS=$((ERRS+1)); }
warn() { printf '  ⚠ %s\n' "$1"; WARNS=$((WARNS+1)); }
ok()   { OKS=$((OKS+1)); [ "$VERBOSE" -eq 1 ] && printf '  ✓ %s\n' "$1"; return 0; }

finish() {
  local st=PASS code=0
  [ "$DONE" -eq 1 ] || err "repo-audit stopped before its last check — the result is incomplete → run it again"
  [ "$WARNS" -gt 0 ] && { st=WARN; code=1; }
  [ "$ERRS" -gt 0 ]  && { st=FAIL; code=2; }
  printf '  repo-audit: %s — %d passed, %d errors, %d warnings\n' "$st" "$OKS" "$ERRS" "$WARNS"
  [ "$STRICT" -eq 1 ] && exit "$code"
  exit 0
}
trap finish EXIT

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
S="$ROOT/scripts"

if ! cd -P "$DIR"; then
  err "repo: $DIR is not a folder → pass the repository's folder"
  DONE=1; exit 0
fi
TOP=$(git rev-parse --show-toplevel)
if [ -z "$TOP" ]; then
  err "repo: not a git repository → run it inside a clone, or run git init"
  DONE=1; exit 0
fi
cd -P "$TOP" || { DONE=1; exit 0; }

# A test command: a package.json test script (up to two folders down), a Makefile
# test target, or a Go or Rust project.
has_test_command() {
  local f
  while IFS= read -r f; do
    perl -MJSON::PP -0777 -ne '
      my $s = eval { JSON::PP->new->decode($_)->{scripts} };
      exit(ref $s eq "HASH" && defined $s->{test} && $s->{test} !~ /no test specified/ ? 0 : 1);
    ' "$f" && return 0
  done < <(git ls-files -- package.json '*/package.json' | awk -F/ 'NF <= 3 && !/node_modules\//')
  local mk
  while IFS= read -r mk; do
    grep -qE '^test[[:space:]]*:' "$mk" && return 0
  done < <(git ls-files | grep -E '(^|/)Makefile$')
  git ls-files | grep -qE '(^|/)(go\.mod|Cargo\.toml)$' && return 0
  return 1
}

# The text of the workflows that run on push or pull_request, without their names.
ci_text() {
  local f
  . "$S/ci-checks.sh"
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$f" ] && ci_workflow_runs "$f" && grep -vE '^[[:space:]]*(-[[:space:]]+)?name:' "$f"
  done
}

# ------------------------------------------------------------------- remote
url=$(git remote get-url origin)
host=''
if [ -z "$url" ]; then
  err "remote: no origin remote, so there are no pull requests to check → add one: git remote add origin <url>"
  GITHUB=0
else
  host=$(bash "$S/plan-path.sh" --host "$TOP")
  case "$host" in
    github.com) GITHUB=1; ok "remote: origin is on GitHub" ;;
    *) GITHUB=0; err "remote: origin is on ${host:-a local path}, not on GitHub, so Executor's PR flow, gh stack and the CI draft do not apply → move the repository to GitHub, or build without them" ;;
  esac
fi

# ----------------------------------------------------------------------- CI
ci=$(bash "$S/ci-checks.sh" --detect "$TOP")
case "$ci" in
  "CI: configured"*)
    if has_test_command && ! ci_text | grep -qiE '(^|[^[:alnum:]])(test|jest|vitest|pytest|mocha|rspec|phpunit|cargo|go test)'; then
      warn "ci: the workflow only lints and the repo has a test command, so the suite still runs in model turns → add the test command to .github/workflows (/executor:init drafts it)"
    else
      ok "ci: $ci"
    fi ;;
  *) err "ci: none, so the full suite runs in model turns on every PR → add a CI workflow (/executor:init offers one)" ;;
esac

# --------------------------------------------------------------- commit hook
hooks=$(bash "$S/git-hooks.sh" status "$TOP")
case "$hooks" in
  "HOOKS: installed") ok "hooks: commit hook installed" ;;
  *)
    if [ -n "$(git config core.hooksPath)" ]; then
      err "hooks: core.hooksPath is set, so a hook written in this repo would not run → add the hook to the folder core.hooksPath points at, or unset it"
    elif [ "$(bash "$S/git-hooks.sh" checks "$TOP")" = "CHECKS: none" ]; then
      warn "hooks: no package has a lint or type check, so the commit hook would check nothing → add a lint or typecheck script first"
    else
      err "hooks: off, so lint and type check run as model turns → bash $S/git-hooks.sh install $TOP"
    fi ;;
esac

# ------------------------------------------------------------- GitHub extras
if [ "$GITHUB" -eq 1 ]; then
  if command -v gh >/dev/null && gh extension list | grep -q 'gh-stack'; then ok "stack: gh stack installed"
  else warn "stack: gh stack is not installed, so features ship as plain PRs chained by base branch → gh extension install github/gh-stack"; fi

  del=$(bash "$S/init-delete-branches.sh")
  case "$del" in
    *"STATE: on"*) ok "branches: merged branches are deleted" ;;
    *"STATE: off"*) warn "branches: merged PRs leave their branch behind → turn on \"Automatically delete head branches\" (/executor:init offers it)" ;;
    *) warn "branches: could not read the delete-head-branches setting ($(printf '%s' "$del" | sed -n 's/^STOP: //p' | head -1 | cut -c1-100)) → run /executor:init when online with gh signed in" ;;
  esac
fi

en=$(bash "$S/init-plugin-enable.sh")
case "$en" in
  *"STATE: enabled"*) ok "enable: Executor is enabled in this repo" ;;
  *) warn "enable: Executor is not enabled in this repo, so it stays off here → /executor:init adds it to .claude/settings.json" ;;
esac

DONE=1
