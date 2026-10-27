---
name: init
description: "Executor: set Executor up — checks the GitHub CLI, its sign-in and the gh stack extension (Executor works best with it, and offers to install it), the shared Engineer of Wealth setup if you want it, and a final check. Run it once after installing, or again any time."
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/self-audit.sh)
model: sonnet
---

# EXECUTOR INIT

You type this; Claude never triggers it (`disable-model-invocation`). Run it again any time. The plugin root is `${CLAUDE_PLUGIN_ROOT}`.

1. Read `${CLAUDE_PLUGIN_ROOT}/references/shared-setup.md` and `${CLAUDE_PLUGIN_ROOT}/references/init.md`.
2. **Shared part:** shared-setup S1. If `shared.md` exists, that is a KEEP or CHANGE. If it is missing, ask in one line: "The shared setup is used by the other Engineer of Wealth plugins, not by Executor. Set it up now, or skip?" Default **skip**. Only on "set it up" run S2–S4.
3. **Executor's part:** init E1.
4. **Check:** init E2, with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/self-audit.sh` (the one Bash command this skill may run without asking).
5. End with: "Executor is ready. `/executor:help` shows what it does."

Every rule in those two files applies.
