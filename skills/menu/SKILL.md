---
name: menu
description: "Executor front door: shows the Executor menu and routes to the right skill. Today that is code review of a pull request or the current branch."
model: sonnet
---
# EXECUTOR (front door)

**You approve twice. It does the rest.**

**This skill is a ROUTER.** It loads no context; every skill loads its own.

## MENU

If called without text, show the menu and wait for the user's input:

```
1. REVIEW         → /executor:review   (a PR number or URL, a branch, or nothing for the current branch)

Coming next: build from a spec — features in parallel, each finished feature opens its PR, a stack of reviewed PRs, you merge.

Or just type what you need — I'll route it.
```

## Routing Table

| User says... | Skill |
|---|---|
| "review", "code review", a PR number, a PR URL, "check this PR", "is this ready to merge" | /executor:review |
| "build this", "implement the spec" | not built yet: say so in one line, and offer a review of what exists |

If the user types content directly, detect the intent from the table and invoke the matching skill with their text.
