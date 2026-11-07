#!/usr/bin/env bash
# self-audit.sh — Executor health check. Read-only.
# SETUP: can Executor open and stack pull requests (gh, its sign-in, the
#        gh stack extension), did the assign hook fail, and is every search
#        root a folder (EOW_HOME overrides ~/.engineer-of-wealth).
# INTEGRITY: is the installed plugin whole (help, references, hooks, verifier).
#
# Every finding ends with "→ <what to do>", so a central caller (one loop over
# all installed plugins) needs nothing but this output.
#
# One round, always: every failure is a finding, never a crash. stderr is
# silenced, the summary line prints even on an unexpected exit, and the exit
# code is 0 so the caller has no reason to retry. The result is the summary:
#   executor: PASS|WARN|FAIL — N passed, N errors, N warnings
# -v      also print what passed
# --strict exit 0 clean, 1 warnings, 2 errors (for hooks and cron)

exec 2>/dev/null

VERBOSE=0; STRICT=0
for a in "$@"; do
  case "$a" in -v) VERBOSE=1 ;; --strict) STRICT=1 ;; esac
done
ERRS=0; WARNS=0; OKS=0; DONE=0
err()  { printf '  ✗ %s\n' "$1"; ERRS=$((ERRS+1)); }
warn() { printf '  ⚠ %s\n' "$1"; WARNS=$((WARNS+1)); }
ok()   { OKS=$((OKS+1)); [ "$VERBOSE" -eq 1 ] && printf '  ✓ %s\n' "$1"; return 0; }
info() { [ "$VERBOSE" -eq 1 ] && printf '  · %s\n' "$1"; return 0; }

finish() {
  local st=PASS code=0
  # Reaching here before the end means a check died; a partial PASS would lie.
  [ "$DONE" -eq 1 ] || err "self-audit stopped before its last check — the result is incomplete → $REINSTALL"
  [ "$WARNS" -gt 0 ] && { st=WARN; code=1; }
  [ "$ERRS" -gt 0 ]  && { st=FAIL; code=2; }
  printf '  executor: %s — %d passed, %d errors, %d warnings\n' "$st" "$OKS" "$ERRS" "$WARNS"
  [ "$STRICT" -eq 1 ] && exit "$code"
  exit 0
}
trap finish EXIT

REINSTALL="reinstall: /plugin install executor@engineer-of-wealth"
ROOT="${ROOT:-$(cd -P "$(dirname "$0")/.." && pwd)}"
SK="$ROOT/skills"
EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/assign.log"

# Skills only the user may run.
USER_ONLY="help init status"

# ===================================================================== SETUP
if command -v gh >/dev/null; then
  ok "setup: gh $(gh --version | head -1 | awk '{print $3}')"
  if gh auth status >/dev/null; then ok "setup: gh is signed in"
  else err "setup: gh is not signed in, so Executor cannot open, read or assign pull requests → run gh auth login"; fi
  if gh extension list | grep -q 'gh-stack'; then ok "setup: gh stack installed"
  else warn "setup: gh stack not installed, so features ship as plain PRs chained by base branch instead of a stack → gh extension install github/gh-stack"; fi
else
  err "setup: gh not installed — Executor cannot open, read or assign pull requests → install it from https://cli.github.com"
fi
command -v jq >/dev/null && ok "setup: jq" || info "setup: no jq — the hooks read events without it"

if [ -s "$LOG" ]; then
  n=$(wc -l < "$LOG" | tr -d ' ')
  warn "setup: $n PR assignment(s) failed, last: $(tail -1 "$LOG" | cut -c1-120) → read $LOG, then delete it"
else
  ok "setup: no failed PR assignments"
fi

if [ -s "$ROOT/scripts/roots.sh" ]; then
  . "$ROOT/scripts/roots.sh"
  e=$WARNS
  for r in "${roots[@]}"; do
    [ -d "$r" ] && continue
    case "$r" in "$HOME"/*) r="~/${r#"$HOME"/}" ;; esac
    warn "setup: search root $r is missing, so Executor finds no checkouts there → create the folder, or change the roots with /executor:init"
  done
  [ "$e" = "$WARNS" ] && ok "setup: search roots present (${#roots[@]})"
fi

# ================================================================= INTEGRITY
door="$SK/help/SKILL.md"
if [ ! -f "$door" ]; then
  err "integrity: Executor incomplete — no skills/help/SKILL.md under $ROOT → $REINSTALL"
  DONE=1; exit 0   # finish prints the summary; nothing below can run without the help
fi

# -- the help is the only way a user discovers a skill, so every skill must be
#    on it, and every skill it lists must exist.
e=$ERRS; w=$WARNS
[ -f "$ROOT/agents/verifier.md" ] || err "integrity: agents/verifier.md missing — review findings cannot be verified → $REINSTALL"
[ -f "$ROOT/agents/builder.md" ] || err "integrity: agents/builder.md missing — features cannot be built → $REINSTALL"
for d in "$SK"/*/; do
  s=$(basename "$d"); [ "$s" = help ] && continue
  [ -f "$d/SKILL.md" ] || { err "integrity: skills/$s/ has no SKILL.md → $REINSTALL"; continue; }
  grep -qF "/executor:$s" "$door" || warn "integrity: skill $s exists but the help never routes to it → $REINSTALL"
done
for s in $(grep -oE '/executor:[a-z-]+' "$door" | sed 's#/executor:##' | sort -u); do
  [ -f "$SK/$s/SKILL.md" ] || err "integrity: the help routes to /executor:$s, which does not exist → $REINSTALL"
done
for r in shared-setup init review-format implementation feature-done pull-request stacks plan; do
  [ -s "$ROOT/references/$r.md" ] || err "integrity: references/$r.md missing → $REINSTALL"
done
# hooks/register.ts prints the fenced block under "## HELP" without the model.
awk '/^## HELP$/{h=1} h&&/^```$/{f++} END{exit !(f>=2)}' "$door" \
  || warn "integrity: skills/help/SKILL.md has no fenced block under \"## HELP\" — /executor:help falls back to the model → $REINSTALL"
[ "$e$w" = "$ERRS$WARNS" ] && ok "integrity: the help routes to every skill and all references are present"

# -- the hooks: without them no PR is reviewed or assigned on its own.
e=$ERRS
for s in assign-author review-new-pr; do
  grep -qF "scripts/$s.sh" "$ROOT/hooks/hooks.json" || err "integrity: hooks/hooks.json no longer runs $s.sh → $REINSTALL"
  [ -s "$ROOT/scripts/$s.sh" ] || err "integrity: scripts/$s.sh missing → $REINSTALL"
done
[ -s "$ROOT/scripts/new-prs.sh" ] || err "integrity: scripts/new-prs.sh missing — both hooks source it → $REINSTALL"
[ "$e" = "$ERRS" ] && ok "integrity: both PR hooks are wired"

# -- the review's mode: without review-mode.sh the review can't tell your PR
#    from a teammate's, so it would never know whether it may fix and push.
[ -s "$ROOT/scripts/review-mode.sh" ] \
  && ok "integrity: the review's fix/report-only engine is present" \
  || err "integrity: scripts/review-mode.sh missing — /executor:review cannot decide whether to fix → $REINSTALL"

# -- the review's docs check: without docs-mentions.sh a review can't tell which
#    docs still name what the diff removed.
[ -s "$ROOT/scripts/docs-mentions.sh" ] \
  && ok "integrity: the review's docs check is present" \
  || err "integrity: scripts/docs-mentions.sh missing - /executor:review cannot check the docs against the diff → $REINSTALL"

# -- the review's last step: without review-ready.sh a passing PR stays a draft.
[ -s "$ROOT/scripts/review-ready.sh" ] \
  && ok "integrity: the review's ready step is present" \
  || err "integrity: scripts/review-ready.sh missing - /executor:review cannot mark your PR ready → $REINSTALL"

# -- the heavy command queue: without heavy.sh heavy commands stop taking turns.
[ -s "$ROOT/scripts/heavy.sh" ] \
  && ok "integrity: the heavy command queue's slot script is present" \
  || err "integrity: scripts/heavy.sh missing - heavy commands cannot take turns → $REINSTALL"
e=$ERRS
grep -qF "scripts/heavy-hook.sh" "$ROOT/hooks/hooks.json" || err "integrity: hooks/hooks.json no longer runs heavy-hook.sh - heavy commands are never queued → $REINSTALL"
[ -s "$ROOT/scripts/heavy-hook.sh" ] || err "integrity: scripts/heavy-hook.sh missing - heavy commands are never queued → $REINSTALL"
[ "$e" = "$ERRS" ] && ok "integrity: the heavy command queue's hook is wired"

# -- ship: the skill and its engine. ship.sh does the guard/push/PR math; the
#    skill opens the draft PR so the PR hooks above take over.
e=$ERRS
[ -f "$SK/ship/SKILL.md" ] || err "integrity: skills/ship/SKILL.md missing — /executor:ship cannot run → $REINSTALL"
[ -s "$ROOT/scripts/ship.sh" ] || err "integrity: scripts/ship.sh missing — /executor:ship has no engine → $REINSTALL"
[ -s "$ROOT/scripts/default-branch.sh" ] || err "integrity: scripts/default-branch.sh missing — ship and review source it for the base → $REINSTALL"
[ "$e" = "$ERRS" ] && ok "integrity: ship skill and its engine are present"

# -- the search roots: every script that looks for a PR's local checkout
#    sources roots.sh, the one reader of the setting.
[ -s "$ROOT/scripts/roots.sh" ] \
  && ok "integrity: the search roots reader is present" \
  || err "integrity: scripts/roots.sh missing — Executor cannot read where to look for local checkouts → $REINSTALL"

# -- where plans live: without plan-path.sh /executor:build has no way to find,
#    name or carry on a plan.
[ -s "$ROOT/scripts/plan-path.sh" ] \
  && ok "integrity: the plans resolver is present" \
  || err "integrity: scripts/plan-path.sh missing - /executor:build cannot find or name a plan → $REINSTALL"

# -- legacy plans: build step 0 and /executor:help run the migration.
[ -s "$ROOT/scripts/plans-migrate.sh" ] \
  && ok "integrity: the plans migration is present" \
  || err "integrity: scripts/plans-migrate.sh missing - /executor:build cannot move a legacy plan → $REINSTALL"

# -- finished plans: without plan-state.sh a merged plan stays live and the next
#    build stops to ask about it; the sweep is what /executor:help lists.
e=$ERRS
[ -s "$ROOT/scripts/plan-state.sh" ] || err "integrity: scripts/plan-state.sh missing - /executor:build cannot tell a finished plan → $REINSTALL"
[ -s "$ROOT/scripts/plan-sweep.sh" ] || err "integrity: scripts/plan-sweep.sh missing - the sweep /executor:help lists cannot run → $REINSTALL"
[ -s "$ROOT/scripts/plan-items.sh" ] || err "integrity: scripts/plan-items.sh missing - plan-state.sh sources it to read a plan's items → $REINSTALL"
[ "$e" = "$ERRS" ] && ok "integrity: finished plans can be told and marked"

# -- status: /executor:status and the help's routing row both run this script.
[ -s "$ROOT/scripts/status.sh" ] \
  && ok "integrity: the status script is present" \
  || err "integrity: scripts/status.sh missing - /executor:status has nothing to run → $REINSTALL"

# -- finding a PR's checkout: without find-checkout.sh a review of another
#    repo's PR has no way to its local checkout.
e=$ERRS
[ -s "$ROOT/scripts/find-checkout.sh" ] || err "integrity: scripts/find-checkout.sh missing — /executor:review cannot find a PR's local checkout → $REINSTALL"
[ -s "$ROOT/scripts/repo-discovery.sh" ] || err "integrity: scripts/repo-discovery.sh missing — find-checkout.sh sources it to search the roots → $REINSTALL"
[ "$e" = "$ERRS" ] && ok "integrity: the PR checkout finder is present"

# -- init's per-repo enable: the engine behind E2. Without it /executor:init
#    cannot detect or add the repo's .claude/settings.json enable.
[ -s "$ROOT/scripts/init-plugin-enable.sh" ] \
  && ok "integrity: init's per-repo enable engine is present" \
  || err "integrity: scripts/init-plugin-enable.sh missing — /executor:init cannot offer the per-repo enable → $REINSTALL"

# -- user-only skills. Claude must never trigger init (it installs and
#    configures) and has no reason to start help or status (you type them; the
#    help runs status.sh itself); disable-model-invocation keeps them yours and
#    out of the skill list every request carries.
e=$ERRS
for s in $USER_ONLY; do
  [ -f "$SK/$s/SKILL.md" ] || { err "integrity: skill $s missing → $REINSTALL"; continue; }
  sed -n '1,/^---$/{/^---$/!p;}' "$SK/$s/SKILL.md" | sed 1d | grep -q '^disable-model-invocation:[[:space:]]*true' \
    || err "integrity: $s lost disable-model-invocation: true — Claude could run it without you → $REINSTALL"
done
[ "$e" = "$ERRS" ] && ok "integrity: help, init and status run only when you type them"
grep -q '^<!-- shared-setup v[0-9]' "$ROOT/references/shared-setup.md" \
  || warn "integrity: references/shared-setup.md has no version line — plugins cannot tell whether their copies match → $REINSTALL"

# -- version assertion: each entry skill (build, ship, init) calls
#    version-check.sh at its start, baking the installed version, so a session
#    carrying a stale snapshot stops with a reload note instead of a generic
#    failure. A baked version that lags the manifest would make a current
#    session falsely report a mismatch, so the two must stay in step.
e=$ERRS
[ -s "$ROOT/scripts/version-check.sh" ] || err "integrity: scripts/version-check.sh missing — entry skills cannot assert the loaded version → $REINSTALL"
if command -v jq >/dev/null; then pv=$(jq -r '.version // empty' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
else pv=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$ROOT/.claude-plugin/plugin.json" | head -1 | grep -oE '"[^"]+"$' | tr -d '"'); fi
for s in build ship init; do
  bv=$(grep -oE "version-check\.sh[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+" "$SK/$s/SKILL.md" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ -z "$bv" ]; then err "integrity: skill $s does not assert the loaded version (no version-check.sh call) → $REINSTALL"
  elif [ -n "$pv" ] && [ "$bv" != "$pv" ]; then err "integrity: skill $s asserts version $bv but the plugin is $pv — bump its version-check.sh call → $REINSTALL"; fi
done
[ "$e" = "$ERRS" ] && ok "integrity: build, ship and init assert the installed version"

DONE=1
