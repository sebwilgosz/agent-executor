#!/usr/bin/env bash
# init-plugin-enable.sh — the deterministic engine behind /executor:init's
# per-repo plugin-enable step. No AI. Executor is disabled user-globally and
# enabled per build repo, and Claude Code settings do not inherit down the tree,
# so the enable must live in the repo's committed .claude/settings.json (never
# settings.local.json, which is gitignored) for every worktree to inherit it.
#
# It reads the ON-DISK .claude/settings.json (what Claude Code actually loads,
# not git HEAD) and either reports its state or, with --apply, merges
# "executor@engineer-of-wealth": true into the top-level enabledPlugins object
# without clobbering any other plugin or setting. It never commits — the skill
# tells the user and asks. EOW_HOME overrides ~/.engineer-of-wealth.
#
# Output is tagged lines the init skill reads; the exit code is always 0 (a
# problem is a note, not a crash):
#   TARGET: <abs path>                 — the file it looked at
#   STATE: enabled                     — the enable is present; nothing to do
#   STATE: missing-file                — no .claude/settings.json on disk
#   STATE: missing-key                 — the file exists but lacks the enable
#   STATE: invalid-json                — the file exists but is not valid JSON
#   STATE: wrote                       — (--apply) merged and wrote the file
#   TRACK: tracked | untracked         — only when the file exists on disk
#   STOP: <one-line reason>            — could not act; see the log
set -u

KEY="executor@engineer-of-wealth"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

EOW="${EOW_HOME:-$HOME/.engineer-of-wealth}"
LOG="$EOW/executor/init.log"

stop()     { printf 'STOP: %s\n' "$1"; exit 0; }
log_fail() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s  %s  %s\n' "$(date "+%F %T")" "$PWD" "$1" >> "$LOG"
}

# The repo root (so the enable lands once, at the repo's .claude/), else here.
root=$(git rev-parse --show-toplevel 2>/dev/null) || root="$PWD"
SETTINGS="$root/.claude/settings.json"
printf 'TARGET: %s\n' "$SETTINGS"

has_jq() { command -v jq >/dev/null 2>&1; }

# Is the enable already present and true?
key_enabled() {
  [ -f "$SETTINGS" ] || return 1
  if has_jq; then
    jq -e --arg k "$KEY" '.enabledPlugins[$k]==true' "$SETTINGS" >/dev/null 2>&1
  else
    grep -q "\"$KEY\"[[:space:]]*:[[:space:]]*true" "$SETTINGS"
  fi
}

# Does the file parse as JSON? (Only answerable with jq; without it, assume yes
# and let the write fall back to the fresh-file path for a missing file.)
valid_json() {
  [ -f "$SETTINGS" ] || return 0
  has_jq || return 0
  jq empty "$SETTINGS" >/dev/null 2>&1
}

track_line() {
  [ -f "$SETTINGS" ] || return 0
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
     && git -C "$root" ls-files --error-unmatch .claude/settings.json >/dev/null 2>&1; then
    printf 'TRACK: tracked\n'
  else
    printf 'TRACK: untracked\n'
  fi
}

# ----- detect the current state -------------------------------------------
if key_enabled; then
  printf 'STATE: enabled\n'; track_line; exit 0
fi
if [ ! -f "$SETTINGS" ]; then
  state=missing-file
elif ! valid_json; then
  printf 'STATE: invalid-json\n'; track_line; exit 0
else
  state=missing-key
fi

if [ "$APPLY" -eq 0 ]; then
  printf 'STATE: %s\n' "$state"; track_line; exit 0
fi

# ----- --apply: write the merged file, never clobbering -------------------
mkdir -p "$root/.claude" 2>/dev/null || { log_fail "mkdir .claude"; stop "could not create $root/.claude — see $LOG"; }
tmp="$SETTINGS.tmp.$$"

if [ "$state" = missing-file ]; then
  if has_jq; then
    merged=$(printf '{}' | jq --arg k "$KEY" '.enabledPlugins[$k]=true') \
      || { log_fail "jq fresh build"; stop "could not build the settings file — see $LOG"; }
  else
    merged=$(printf '{\n  "enabledPlugins": {\n    "%s": true\n  }\n}' "$KEY")
  fi
else
  # Existing file without the key: a true merge needs a JSON parser.
  if ! has_jq; then
    stop "$SETTINGS exists without the enable and jq is not installed to merge it safely — install jq (https://jqlang.github.io/jq/) or add \"$KEY\": true under enabledPlugins by hand"
  fi
  merged=$(jq --arg k "$KEY" '.enabledPlugins[$k]=true' "$SETTINGS") \
    || { log_fail "jq merge"; stop "could not merge into $SETTINGS — see $LOG"; }
fi

printf '%s\n' "$merged" > "$tmp" || { log_fail "write tmp"; rm -f "$tmp"; stop "could not write $SETTINGS — see $LOG"; }
mv "$tmp" "$SETTINGS" || { log_fail "mv into place"; rm -f "$tmp"; stop "could not write $SETTINGS — see $LOG"; }

printf 'STATE: wrote\n'
track_line
exit 0
