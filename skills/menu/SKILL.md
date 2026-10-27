---
name: menu
description: "Executor front door: shows the Executor menu and routes to the right skill. Today that is code review of a pull request or the current branch, plus setup and its check."
disable-model-invocation: true
---
# EXECUTOR (front door)

**You approve twice. It does the rest.**

**This skill is a ROUTER.** It loads no context; every skill loads its own.

## MENU

If called without text, show the menu and wait for the user's input:

```
1. REVIEW         → /executor:review   (a PR number or URL, a branch, or nothing for the current branch)

Setup (you type these):
   INIT           → /executor:init     (gh, its sign-in and gh stack, which Executor works best with)
   SELF-AUDIT     → /executor:self-audit   (is everything in place)

Coming next: build from a spec — features in parallel, each finished feature opens its PR, a stack of reviewed PRs, you merge.

Or just type what you need — I'll route it.
```

## Routing Table

| User says... | Skill |
|---|---|
| "review", "code review", a PR number, a PR URL, "check this PR", "is this ready to merge" | /executor:review |
| "set up", "install gh stack", "is it set up", "check setup" | say the user types /executor:init (setup) or /executor:self-audit (check) themselves: Claude cannot run them |
| "build this", "implement X", "implement the spec" | not built yet: say so in one line. First run the spec check of `${CLAUDE_PLUGIN_ROOT}/references/implementation.md`, step 0: with no spec, or one that leaves points open, say so and ask for the missing details, so the spec is ready when building lands. Offer a review of what exists |

If the user types content directly, detect the intent from the table and invoke the matching skill with their text.
