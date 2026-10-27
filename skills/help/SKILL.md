---
name: help
description: "Executor front door: shows what Executor does and routes to the right skill. Today that is code review of a pull request or the current branch, plus setup and its check."
disable-model-invocation: true
---
# EXECUTOR (front door)

**You approve twice. It does the rest.**

**This skill is a ROUTER.** It loads no context; every skill loads its own.

## HELP

If called without text, show the help and wait for the user's input:

```
EXECUTOR PLUGIN:
  reviews every pull request, fixes what it finds

INCLUDES:
  /executor:review [PR | branch]   review, verify, fix, review again
                                   no argument: the current branch

SETUP:
  /executor:init                   installs gh, gh stack with which executor works best
  /executor:self-audit             checks if everything is in place

COMING NEXT: point me at a feature spec and watch me build it.
```

## Routing Table

| User says... | Skill |
|---|---|
| "review", "code review", a PR number, a PR URL, "check this PR", "is this ready to merge" | /executor:review |
| "set up", "install gh stack", "is it set up", "check setup" | say the user types /executor:init (setup) or /executor:self-audit (check) themselves: Claude cannot run them |
| "build this", "implement X", "implement the spec" | not built yet: say so in one line. First run the spec check of `${CLAUDE_PLUGIN_ROOT}/references/implementation.md`, step 0: with no spec, or one that leaves points open, say so and ask for the missing details, so the spec is ready when building lands. Offer a review of what exists |

If the user types content directly, detect the intent from the table and invoke the matching skill with their text.
