---
name: status
description: "Executor: across every repo, what is yours to merge now, what waits on you and what is still moving. Read-only."
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh)
---
# EXECUTOR STATUS

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh`. It takes no arguments.

- No text after the command: show what it prints, as it is.
- Text after it: answer from that output.
- It prints nothing: say the status could not be read, in one line.
