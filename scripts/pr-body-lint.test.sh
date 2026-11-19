#!/usr/bin/env bash
# Spec tests for scripts/pr-body-lint.sh - the deterministic readability check
# of a PR description. The failing example is an invented PR body that
# followed a repo's own template and dropped the rules: bare ticket URLs, one
# bullet carrying a metric's label set, a query and a library's mechanics.
# No network: --pr reads through a stub `gh`.
#
# Run: bash scripts/pr-body-lint.test.sh   (exit 0 = all pass)
set -u

SELF_DIR=$(cd -P "$(dirname "$0")" && pwd)
LINT="$SELF_DIR/pr-body-lint.sh"

PASS=0; FAIL=0
ok()    { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; }
check() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring: $2 | got: $3" ;; esac; }
refute(){ case "$3" in *"$2"*) bad "$1" "did not want substring: $2 | got: $3" ;; *) ok "$1" ;; esac; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/pr-body-lint-test.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
export EOW_HOME="$ROOT/eow"
run() { printf '%s\n' "$1" > "$ROOT/body.md"; bash "$LINT" "$ROOT/body.md" 2>&1; }

echo "pr-body-lint.sh spec tests"

# The failing example: a repo template's headings, Executor's rules dropped.
BAD='## Link to the ticket

https://example.atlassian.net/browse/ABC-123 (epic https://example.atlassian.net/browse/ABC-100)

## Background

- Failed refund webhooks need to page on-call.

## Approach

- **Webhook name and error in the alert.** A new per-webhook gauge, `refund_webhook_failed_at{provider, region, failure_reason, error_code, webhook_id}`, holds the time the call failed. The alert fires while `time() - failed_at < 1h`, so it pages once per webhook and then clears. I did not put `webhook_id` on the counter: every webhook would start a new series at 1, and `increase()` never counts a first sample. `error_code` is the provider code (`unknown_error` otherwise). Same pattern as https://github.com/acme/shop/pull/42.

```mermaid
flowchart LR
  F[Refund webhook fails] --> G["failed_at gauge {webhook_id, error_code}"]
  G --> A["time() - failed_at < 1h"]
```

## Testing Instructions

1. Send a webhook with a bad signature → the alert fires, naming the webhook.'
out=$(run "$BAD")
check "bare ticket URL flagged"                     "LINT: bare-url line 3: https://example.atlassian.net/browse/ABC-123" "$out"
check "bare URL: suggests the linked ticket ID"     "[ABC-123](https://example.atlassian.net/browse/ABC-123)" "$out"
check "bare URL: every URL on the line"             "[ABC-100](https://example.atlassian.net/browse/ABC-100)" "$out"
check "bare PR URL: suggests the linked PR number"  "[#42](https://github.com/acme/shop/pull/42)" "$out"
check "long bullet flagged with its word count"     "LINT: long-bullet line 11:" "$out"
check "bullet dense with code names flagged"        "LINT: dense line 11: 6 code names" "$out"
check "label set in prose flagged"                  "LINT: internals line 11: a label set" "$out"
refute "the Mermaid diagram is never flagged"       "line 15" "$out"
refute "nor its query"                              "line 16" "$out"
check "a summary asks for a rewrite"                "issue(s) - rewrite the body as references/pull-request.md says" "$out"
refute "not ok"                                     "LINT: ok" "$out"
( printf '%s\n' "$BAD" > "$ROOT/b.md"; bash "$LINT" "$ROOT/b.md" >/dev/null 2>&1 ); [ $? = 0 ] && ok "exit 0 even with issues" || bad "exit 0 even with issues" "non-zero"

# The same PR, rewritten as the rules ask: linked IDs, short bullets, the mechanics left to the code.
GOOD='## Link to the ticket

[ABC-123](https://example.atlassian.net/browse/ABC-123) (epic [ABC-100](https://example.atlassian.net/browse/ABC-100))

## Background

- Failed refund webhooks need to page on-call.
- The alert said only "N webhooks failed", so on-call had to dig for which one.

## Approach

- A new gauge with one series per failed webhook stores its ID, the error code and the time it failed.
- The alert fires for an hour after a webhook fails, then clears.
- Same approach as [ABC-124](https://example.atlassian.net/browse/ABC-124) ([#42](https://github.com/acme/shop/pull/42)).

```mermaid
flowchart LR
  F[Refund webhook fails] --> G["failed_at gauge {webhook_id, error_code}"]
  G --> A["time() - failed_at < 1h"]
```

## Testing Instructions

1. Send a webhook with a bad signature → the alert fires, naming the webhook.
2. Run `make test` and `make lint`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)'
out=$(run "$GOOD")
[ "$out" = "LINT: ok" ] && ok "the rewritten body passes: LINT: ok alone" || bad "the rewritten body passes: LINT: ok alone" "$out"

# Bare URLs: what counts as link syntax
check "a plain URL is bare"            "bare-url" "$(run 'See https://example.com/docs for more.')"
check "an autolink <url> is bare too"  "bare-url" "$(run 'See <https://example.com/docs>.')"
check "an issue URL: linked #n"        "[#12](https://github.com/o/r/issues/12)" "$(run 'Closes https://github.com/o/r/issues/12')"
check "any other URL: a named link"    "[<what it is>](https://example.com/x)" "$(run 'Logs: https://example.com/x')"
is_ok() { [ "$(run "$2")" = "LINT: ok" ] && ok "$1" || bad "$1" "$(run "$2")"; }
is_ok "a markdown link is fine"            '[the docs](https://example.com/docs)'
is_ok "an image is fine"                   '![screenshot](https://example.com/a.png)'
is_ok "a reference definition is fine"     '[docs]: https://example.com/docs'
is_ok "a URL in backticks is code"         'Run `curl https://example.com/health`.'
is_ok "a URL in a code block is code"      '```
curl https://example.com/health
```'
is_ok "a URL in an HTML comment is ignored" '<!-- Link the ticket: https://example.com/browse/X-1 -->'
is_ok "a multi-line HTML comment is ignored" '<!--
Template help: describe https://example.com/browse/X-1 and the background, with many many many many many many many many many many many many many many many many many many many many many many many many many many many many words.
-->'

# Bullets and paragraphs
long40=$(printf 'word %.0s' $(seq 1 40))
long41=$(printf 'word %.0s' $(seq 1 41))
is_ok "a 40-word bullet is fine"           "- $long40"
check "a 41-word bullet is long"           "LINT: long-bullet line 1: 41 words" "$(run "- $long41")"
check "a bullet's wrapped lines count"     "LINT: long-bullet line 1: 41 words" "$(run "- $long40
  word")"
check "numbered items are bullets"         "long-bullet" "$(run "1. $long41")"
check "checklist items are bullets"        "long-bullet" "$(run "- [ ] $long41")"
is_ok "a link counts as its text"          "- $(printf 'w %.0s' $(seq 1 38)) [two words](https://example.com/a/very/long/path)"
is_ok "a 41-word paragraph is fine"        "$long41"
check "a 61-word paragraph is long"        "LINT: long-para line 1: 61 words" "$(run "$(printf 'word %.0s' $(seq 1 61))")"
is_ok "a table row is not a bullet"        "| $long41 | x |"

# The Testing layout of references/pull-request.md: bold-label lines, one per line,
# render as separate lines, so they are not one paragraph
TESTING='## Testing

**Spec tests**, written before the code:
- [x] A webhook that fails pages once — `spec/webhook_spec.rb`

**Also added:** `spec/models/webhook_spec.rb` — covers the retry window
**Changed with approval:** none
**Build:** `bundle exec rspec`, `bundle exec rubocop` — all green
**Try it:** run `bin/dev`, then fail a webhook from the console'
is_ok "bold-label lines are not one paragraph"  "$TESTING"
long_label=$(printf 'word %.0s' $(seq 1 31))
is_ok "two labelled lines are not one long paragraph" "**Build:** $long_label
**Try it:** $long_label"
check "a long labelled line is still long"      "LINT: long-para line 1:" "$(run "**Build:** $(printf 'word %.0s' $(seq 1 61))")"

# Dense and internals
is_ok "three code names are fine"          '- Run `a`, `b` and `c`.'
check "four code names are dense"          "LINT: dense line 1: 4 code names" "$(run '- Set `a`, `b`, `c` and `d`.')"
check "a label set is internals"           "internals" "$(run '- A gauge `failed_at{file_name, error_code}` holds it.')"
check "a label set without backticks too"  "internals" "$(run '- It is labelled {file_name, error_code} now.')"
check "a query is internals"               "query syntax" "$(run '- It fires while `time() - failed_at < 1h`.')"
check "a range selector is internals"      "query syntax" "$(run '- It uses rate(errors[5m]).')"
is_ok "a parenthesis in prose is fine"     '- Upload a file that fails (for example a stale one) → it pages.'
is_ok "JSON in prose is not a label set"   '- The response is `{"ok": true, "n": 2}`.'

# Body length: the diagram and comments are free, other code blocks count
lines() { for i in $(seq 1 "$1"); do printf -- '- point %s\n' "$i"; done; }
is_ok "40 lines are fine"                  "$(lines 40)"
check "41 lines are long"                  "LINT: long-body line 1: 41 lines" "$(run "$(lines 41)")"
is_ok "the diagram does not count"         "$(lines 38)
\`\`\`mermaid
flowchart LR
  A --> B
  B --> C
\`\`\`"
check "another code block counts"          "long-body" "$(run "$(lines 38)
\`\`\`
one
two
\`\`\`")"
is_ok "blank lines do not count"           "$(lines 20 | sed 's/$/\
/')"

# --pr reads the live body through gh; a failure is a plain note
BIN="$ROOT/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$ROOT_CALLS"
[ -n "${GH_FAIL:-}" ] && { echo "HTTP 404: Not Found" >&2; exit 1; }
printf 'See https://example.atlassian.net/browse/ABC-1\n'
STUB
chmod +x "$BIN/gh"
export ROOT_CALLS="$ROOT/calls.log"
out=$(PATH="$BIN:$PATH" bash "$LINT" --pr 600 --repo acme/shop 2>&1)
check "--pr: lints the live body"          "[ABC-1](https://example.atlassian.net/browse/ABC-1)" "$out"
check "--pr: asks gh for that PR's body"   "pr view 600 --json body -q .body --repo acme/shop" "$(cat "$ROOT_CALLS")"
out=$(GH_FAIL=1 PATH="$BIN:$PATH" bash "$LINT" --pr 600 2>&1)
check "--pr failure: UNKNOWN, not a raw error" "UNKNOWN: could not read the body of PR 600: HTTP 404: Not Found" "$out"
check "--pr failure: logged"               "HTTP 404" "$(cat "$EOW_HOME/executor/pr-body-lint.log")"
check "missing file: UNKNOWN"              "UNKNOWN: body file $ROOT/nope.md not found" "$(bash "$LINT" "$ROOT/nope.md" 2>&1)"

echo
printf 'pr-body-lint.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
