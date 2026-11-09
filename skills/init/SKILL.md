---
name: init
description: "Executor: set Executor up — checks the GitHub CLI, its sign-in and the gh stack extension (Executor works best with it, and offers to install it), offers to enable Executor in the current build repository (its committed .claude/settings.json), offers GitHub's 'Automatically delete head branches' setting for it, asks where your local checkouts, your build plans and your specs live, the shared Engineer of Wealth setup if you want it, and a final check. Run it once after installing, or again any time."
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/self-audit.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-plugin-enable.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-delete-branches.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo-audit.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-check.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-home.sh:*)
model: sonnet
---

# EXECUTOR INIT

You type this; Claude never triggers it (`disable-model-invocation`). Run it again any time. The plugin root is `${CLAUDE_PLUGIN_ROOT}`.

0. **Assert the plugin is current.** This session may carry an old snapshot of Executor while a newer one is installed. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-check.sh 0.11.0`. On a `MISMATCH:` line, stop and give the user that one line (the loaded snapshot is stale; reload the plugin or start a fresh session). `OK:` or `STOP:` (the check could not read the manifest): carry on.
1. Read `${CLAUDE_PLUGIN_ROOT}/references/shared-setup.md` and `${CLAUDE_PLUGIN_ROOT}/references/init.md`.
2. **Shared part:** shared-setup S1. If `shared.md` exists, that is a KEEP or CHANGE. If it is missing, ask in one line: "The shared setup is used by the other Engineer of Wealth plugins, not by Executor. Set it up now, or skip?" Default **skip**. Only on "set it up" run S2–S4.
3. **Executor's part:** init E1, then E2 (enable Executor in this repository — it reads `.claude/settings.json` and offers to add the enable, asking before it writes and before any commit), then E2b (GitHub's "Automatically delete head branches" setting for this repository, changed only on a yes), then E2c (the repo audit: what this repository is missing of CI, the commit hook and the rest, walked through one finding at a time; Executor applies none of it), then E3 (the search roots: the folders where Executor looks for a PR's local checkout, written to `executor/config.md` only on YES), then E4 (the plans folder, written the same way; moving it moves nothing), then E5 (the spec home: where specs are kept for this folder, written to its `AGENTS.md` and `CLAUDE.md` only on YES).
4. **Check:** init E6, with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/self-audit.sh` and `bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo-audit.sh`.
5. End with: "Executor is ready." Then print what `/executor:help` prints: the fenced block under `## HELP` in `${CLAUDE_PLUGIN_ROOT}/skills/help/SKILL.md`, then what `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh --summary` prints.

Every rule in those two files applies.
