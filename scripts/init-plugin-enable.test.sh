#!/usr/bin/env bash
# Spec tests for scripts/init-plugin-enable.sh — the deterministic engine behind
# /executor:init's per-repo plugin-enable step. One case per requirement:
#   absent file        → offer to create, then a valid fresh file
#   present, no key     → MERGE the enable in, never clobber other settings
#   present, key there   → no-op (idempotent), no second write
#   settings.local.json  → never touched
#   on-disk & untracked  → reminds the user to commit so worktrees inherit it
#   invalid JSON        → never clobbered
# No network: each case runs in a throwaway git repo so the tracked/untracked
# reminder is exercised honestly.
#
# Run: bash scripts/init-plugin-enable.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
SCRIPT="$SELF_DIR/init-plugin-enable.sh"
KEY="executor@engineer-of-wealth"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check(){ # name  expected-substring  actual
  case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac
}
refute(){ # name  forbidden-substring  actual
  case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac
}

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
export EOW_HOME="$ROOT/eow"

# A fresh git repo for a scenario; prints its path.
new_repo(){
  local w; w=$(mktemp -d "$ROOT/repo.XXXXXX")
  git init -q "$w"; git -C "$w" config user.email t@t.t; git -C "$w" config user.name t
  printf 'a\n' > "$w/a.txt"; git -C "$w" add a.txt; git -C "$w" commit -qm init
  printf '%s' "$w"
}
run(){ ( cd "$1" && shift && bash "$SCRIPT" "$@" 2>&1 ); } # run <repo> [--apply]
settings(){ printf '%s/.claude/settings.json' "$1"; }

echo "init-plugin-enable.sh spec tests"

# 1. Absent file → detect reports missing-file.
W=$(new_repo)
check "detect: absent file → missing-file" "STATE: missing-file" "$(run "$W")"
[ ! -e "$(settings "$W")" ] && ok "detect: read-only, writes nothing" \
  || bad "detect: read-only, writes nothing" "settings.json was created by a detect"

# 2. Apply on absent file → creates a valid file carrying the enable.
out=$(run "$W" --apply)
check "apply: absent file → wrote" "STATE: wrote" "$out"
jq . "$(settings "$W")" >/dev/null 2>&1 && ok "apply: fresh file is valid JSON" \
  || bad "apply: fresh file is valid JSON" "not parseable JSON"
jq -e --arg k "$KEY" '.enabledPlugins[$k]==true' "$(settings "$W")" >/dev/null 2>&1 \
  && ok "apply: fresh file has the enable" \
  || bad "apply: fresh file has the enable" "key not set true"

# 3. Detect again → already enabled (idempotent).
check "detect: key present → enabled" "STATE: enabled" "$(run "$W")"

# 4. Apply again → still enabled, never writes a second time / duplicates.
before=$(cat "$(settings "$W")")
out=$(run "$W" --apply)
check  "apply: already enabled → enabled" "STATE: enabled" "$out"
refute "apply: already enabled → no re-write" "STATE: wrote" "$out"
[ "$before" = "$(cat "$(settings "$W")")" ] && ok "apply: idempotent, file unchanged" \
  || bad "apply: idempotent, file unchanged" "file changed on a no-op apply"

# 5. Present without the key → MERGE, never clobber other settings.
W=$(new_repo); mkdir -p "$W/.claude"
cat > "$(settings "$W")" <<'JSON'
{
  "enabledPlugins": { "other@vendor": true },
  "model": "opus",
  "env": { "FOO": "bar" }
}
JSON
check "detect: present without the key → missing-key" "STATE: missing-key" "$(run "$W")"
out=$(run "$W" --apply)
check "apply: present without the key → wrote" "STATE: wrote" "$out"
s=$(settings "$W")
jq . "$s" >/dev/null 2>&1 && ok "merge: result is valid JSON" || bad "merge: result is valid JSON" "unparseable"
jq -e --arg k "$KEY" '.enabledPlugins[$k]==true' "$s" >/dev/null 2>&1 \
  && ok "merge: the enable is added" || bad "merge: the enable is added" "enable missing"
jq -e '.enabledPlugins["other@vendor"]==true' "$s" >/dev/null 2>&1 \
  && ok "merge: keeps the other plugin" || bad "merge: keeps the other plugin" "other plugin lost"
jq -e '.model=="opus" and .env.FOO=="bar"' "$s" >/dev/null 2>&1 \
  && ok "merge: keeps unrelated settings" || bad "merge: keeps unrelated settings" "other settings lost"

# 6. settings.local.json is never touched.
W=$(new_repo); mkdir -p "$W/.claude"
local_f="$W/.claude/settings.local.json"
printf '{"enabledPlugins":{"secret@local":true}}\n' > "$local_f"
local_before=$(cat "$local_f")
run "$W" --apply >/dev/null
[ "$local_before" = "$(cat "$local_f")" ] && ok "never touches settings.local.json" \
  || bad "never touches settings.local.json" "settings.local.json changed"

# 7. On-disk but untracked → reminds; committed → tracked.
W=$(new_repo); mkdir -p "$W/.claude"
run "$W" --apply >/dev/null
check "track: fresh file is untracked" "TRACK: untracked" "$(run "$W")"
git -C "$W" add .claude/settings.json; git -C "$W" commit -qm "enable executor"
check "track: committed file is tracked" "TRACK: tracked" "$(run "$W")"

# 8. Invalid JSON → never clobbered.
W=$(new_repo); mkdir -p "$W/.claude"
printf 'this is { not json\n' > "$(settings "$W")"
bad_before=$(cat "$(settings "$W")")
check "detect: invalid JSON is flagged" "STATE: invalid-json" "$(run "$W")"
run "$W" --apply >/dev/null
[ "$bad_before" = "$(cat "$(settings "$W")")" ] && ok "apply: invalid JSON is not clobbered" \
  || bad "apply: invalid JSON is not clobbered" "the broken file was overwritten"

echo
printf 'init-plugin-enable.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
