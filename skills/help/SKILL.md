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
  builds a spec into reviewed pull requests, reviews every pull request

INCLUDES:
  /executor:build <spec>           plan it with you, build in parallel,
                                   review every PR; you merge
  /executor:review [PR | branch]   review, verify, fix, review again
                                   no argument: the current branch

SETUP:
  /executor:init                   checks gh and its sign-in, offers to install gh stack
```

## Routing Table

| User says... | Skill |
|---|---|
| "review", "code review", a PR number, a PR URL, "check this PR", "is this ready to merge" | /executor:review |
| "set up", "install gh stack", "is it set up", "check setup" | say the user types /executor:init themselves: Claude cannot run it. It ends with the setup check |
| "build this", "implement X", "implement the spec", a spec or RFC | /executor:build |

If the user types content directly, detect the intent from the table and invoke the matching skill with their text.
