#!/usr/bin/env bash
# version-check.sh — the deterministic guard behind the entry skills' version
# assertion (build, ship, init). No AI.
#
# A session spawned from a long-lived one inherits that session's snapshot of
# the plugin's instructions. When the plugin was updated on disk after the
# session started, the spawn runs the OLD instructions against the NEW install:
# a skill or agent the snapshot expects may be gone, and the skill fails with a
# generic error that hides the real cause. Each entry skill calls this at its
# start with the version baked into its own (snapshotted) text; the script reads
# the version of the plugin on disk and reports whether they match, so a drift
# stops with a one-line fix instead of a silent or generic failure.
#
# Usage:   version-check.sh <loaded-version>
# Output is one tagged line; the exit code is always 0 (a stop is a note):
#   OK: executor <version>                         — match; carry on
#   MISMATCH: loaded <a>, installed <b> — reload the plugin or start a fresh session
#   STOP: <reason>                                 — could not check
set -u

ROOT="${ROOT:-$(cd -P "$(dirname "$0")/.." && pwd)}"
MANIFEST="$ROOT/.claude-plugin/plugin.json"

loaded="${1:-}"
[ -n "$loaded" ] || { printf 'STOP: version-check needs the loaded version as its argument\n'; exit 0; }
[ -f "$MANIFEST" ] || { printf 'STOP: cannot read the installed plugin manifest at %s\n' "$MANIFEST"; exit 0; }

if command -v jq >/dev/null 2>&1; then
  disk=$(jq -r '.version // empty' "$MANIFEST" 2>/dev/null)
else
  disk=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$MANIFEST" | head -1 | grep -oE '"[^"]+"$' | tr -d '"')
fi
[ -n "$disk" ] || { printf 'STOP: the installed plugin manifest has no version\n'; exit 0; }

if [ "$loaded" = "$disk" ]; then
  printf 'OK: executor %s\n' "$disk"
else
  printf 'MISMATCH: loaded %s, installed %s — reload the plugin or start a fresh session\n' "$loaded" "$disk"
fi
exit 0
