#!/usr/bin/env bash
# self-audit.sh — Executor health check. Read-only.
# SETUP: can Executor open and stack pull requests (gh, its sign-in, the
#        gh stack extension) and did the assign hook fail (EOW_HOME overrides
#        ~/.engineer-of-wealth).
# INTEGRITY: is the installed plugin whole (menu, references, hooks, verifier).
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

# Skills only the user may run: they install, configure or run scripts.
USER_ONLY="init self-audit"

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

# ================================================================= INTEGRITY
door="$SK/menu/SKILL.md"
if [ ! -f "$door" ]; then
  err "integrity: Executor incomplete — no skills/menu/SKILL.md under $ROOT → $REINSTALL"
  DONE=1; exit 0   # finish prints the summary; nothing below can run without the menu
fi

# -- the menu is the only way a user discovers a skill, so every skill must be
#    on it, and every skill it lists must exist.
e=$ERRS; w=$WARNS
[ -f "$ROOT/agents/verifier.md" ] || err "integrity: agents/verifier.md missing — review findings cannot be verified → $REINSTALL"
for d in "$SK"/*/; do
  s=$(basename "$d"); [ "$s" = menu ] && continue
  [ -f "$d/SKILL.md" ] || { err "integrity: skills/$s/ has no SKILL.md → $REINSTALL"; continue; }
  grep -qF "/executor:$s" "$door" || warn "integrity: skill $s exists but the menu never routes to it → $REINSTALL"
done
for s in $(grep -oE '/executor:[a-z-]+' "$door" | sed 's#/executor:##' | sort -u); do
  [ -f "$SK/$s/SKILL.md" ] || err "integrity: the menu routes to /executor:$s, which does not exist → $REINSTALL"
done
for r in shared-setup init review-format feature-done pull-request stacks; do
  [ -s "$ROOT/references/$r.md" ] || err "integrity: references/$r.md missing → $REINSTALL"
done
[ "$e$w" = "$ERRS$WARNS" ] && ok "integrity: the menu routes to every skill and all references are present"

# -- the hooks: without them no PR is reviewed or assigned on its own.
e=$ERRS
for s in assign-author review-new-pr; do
  grep -qF "scripts/$s.sh" "$ROOT/hooks/hooks.json" || err "integrity: hooks/hooks.json no longer runs $s.sh → $REINSTALL"
  [ -s "$ROOT/scripts/$s.sh" ] || err "integrity: scripts/$s.sh missing → $REINSTALL"
done
[ -s "$ROOT/scripts/new-prs.sh" ] || err "integrity: scripts/new-prs.sh missing — both hooks source it → $REINSTALL"
[ "$e" = "$ERRS" ] && ok "integrity: both PR hooks are wired"

# -- user-only skills. Claude must never trigger init (it installs and
#    configures) or self-audit (it runs a script); disable-model-invocation
#    keeps them yours.
e=$ERRS
for s in $USER_ONLY; do
  [ -f "$SK/$s/SKILL.md" ] || { err "integrity: skill $s missing → $REINSTALL"; continue; }
  sed -n '1,/^---$/{/^---$/!p;}' "$SK/$s/SKILL.md" | sed 1d | grep -q '^disable-model-invocation:[[:space:]]*true' \
    || err "integrity: $s lost disable-model-invocation: true — Claude could run it without you → $REINSTALL"
done
[ "$e" = "$ERRS" ] && ok "integrity: init and self-audit run only when you type them"
grep -q '^<!-- shared-setup v[0-9]' "$ROOT/references/shared-setup.md" \
  || warn "integrity: references/shared-setup.md has no version line — plugins cannot tell whether their copies match → $REINSTALL"

DONE=1
