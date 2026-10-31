---
name: init
description: "Executor: set Executor up — checks the GitHub CLI, its sign-in and the gh stack extension (Executor works best with it, and offers to install it), offers to enable Executor in the current build repository (its committed .claude/settings.json), the shared Engineer of Wealth setup if you want it, and a final check. Run it once after installing, or again any time."
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/self-audit.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-plugin-enable.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-check.sh:*)
model: sonnet
---

# EXECUTOR INIT

You type this; Claude never triggers it (`disable-model-invocation`). Run it again any time. The plugin root is `${CLAUDE_PLUGIN_ROOT}`.

0. **Assert the plugin is current.** This session may carry an old snapshot of Executor while a newer one is installed. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-check.sh 0.3.1`. On a `MISMATCH:` line, stop and give the user that one line (the loaded snapshot is stale; reload the plugin or start a fresh session). `OK:` or `STOP:` (the check could not read the manifest): carry on.
1. Read `${CLAUDE_PLUGIN_ROOT}/references/shared-setup.md` and `${CLAUDE_PLUGIN_ROOT}/references/init.md`.
2. **Shared part:** shared-setup S1. If `shared.md` exists, that is a KEEP or CHANGE. If it is missing, ask in one line: "The shared setup is used by the other Engineer of Wealth plugins, not by Executor. Set it up now, or skip?" Default **skip**. Only on "set it up" run S2–S4.
3. **Executor's part:** init E1, then E2 (enable Executor in this repository — it reads `.claude/settings.json` and offers to add the enable, asking before it writes and before any commit).
4. **Check:** init E3, with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/self-audit.sh` (the one Bash command this skill may run without asking).
5. End with: "Executor is ready. `/executor:help` shows what it does."

Every rule in those two files applies.
