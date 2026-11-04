---
name: help
description: "Executor front door: shows what Executor does and routes to the right skill. Today that is code review of a pull request, from any folder, or of the current branch, plus setup and its check."
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-sweep.sh:*)
---
# EXECUTOR (front door)

**You approve twice. It does the rest.**

**This skill is a ROUTER.** It loads no context; every skill loads its own.

## HELP

If called without text, show the help and wait for the user's input:

```
EXECUTOR PLUGIN:
  builds a spec into reviewed pull requests, reviews every pull request

INCLUDES:
  /executor:build <spec>           plan it with you, build in parallel,
                                   review every PR; you merge
  /executor:review [PR | branch]   review, verify, fix, review again
                                   no argument: the current branch
                                   owner/repo#N or a URL from any folder:
                                   opens it in that repo's checkout
  /executor:ship                   commit, push, open a draft PR
                                   the review starts on its own

SETUP:
  /executor:init                   checks gh and its sign-in, offers gh stack
                                   and the per-repo enable, asks where your
                                   checkouts and your plans live
  scripts/plan-sweep.sh [--dry-run]  marks every finished plan done
```

Below the block, print what `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh --summary` prints: the plans folder and where it comes from, this repo's folder and its live plans.

## Routing Table

| User says... | Skill |
|---|---|
| "review", "code review", a PR number, a PR URL, owner/repo#N, "let's review <ref>", "check this PR", "is this ready to merge" | /executor:review |
| "ship this", "push", "commit and push", "push changes", "open a PR", "submit the branch" | /executor:ship |
| "set up", "install gh stack", "is it set up", "check setup" | say the user types /executor:init themselves: Claude cannot run it. It ends with the setup check |
| "build this", "implement X", "implement the spec", a spec or RFC | /executor:build |
| "sweep the plans", "mark finished plans" | run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-sweep.sh`, with `--dry-run` when asked only to look, and show what it prints |

If the user types content directly, detect the intent from the table and invoke the matching skill with their text.
