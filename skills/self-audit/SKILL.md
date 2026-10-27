---
name: self-audit
description: "Executor: setup check — gh installed and signed in, gh stack installed, failed PR assignments, and whether the plugin is whole. Run it when a PR was not reviewed or assigned; /executor:init runs it at the end."
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/self-audit.sh)
model: haiku
---

# EXECUTOR SELF-AUDIT

You type this; Claude never triggers it (`disable-model-invocation`), so its description costs nothing in other sessions. The script below ran before this text reached the model, so its result is already here and no tool call is needed. A central audit runs the same script, `scripts/self-audit.sh`.

## RESULT

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/self-audit.sh`

## WHAT TO SAY

If the summary line shows 0 errors and 0 warnings, reply with that line only. Otherwise repeat every `✗` and `⚠` line as it is (each ends with `→` and what to do), then the summary line.

The script always finishes and its last line is the result, so this is one round. If RESULT is empty, say "the self-audit produced no output" in one line and stop. Never rerun it, run anything else, read the files, or invent the content of a missing one.
