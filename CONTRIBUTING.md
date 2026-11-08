# Contributing to Executor

These are the engineering rules Executor holds itself to. Every change to this plugin follows them, and `executor:review` reads this file as a conventions source when it reviews a pull request. Read them before you build.

## 1. Efficient by default

Do the least work the task needs. Load no context it doesn't call for, and keep descriptions short. A skill that pulls in a reference it never uses, or a paragraph where a line would do, is waste.

## 2. One unit, invokable by user and model — no duplicates

One capability is one unit with two entry points: the user types it and the model can call it. Never add a second skill that repeats what another already does. If a job exists, extend it; don't clone it.

## 3. Deterministic work is a script or a mod, never the model

Work with one right answer belongs in code. Help is a mod, assignment a script. Reserve a model turn for judgement — the parts that genuinely need reasoning — not for steps a script would run the same way every time.

## 4. Tool calls never fail into the conversation

Wrap every failable or network call — each `gh` and `git` call — in one of our own scripts. The script catches the failure, logs it, and returns a plain note. The agent never receives a raw failed tool call.

## 5. Non-blocking where it can be

Run side effects detached so the session never waits on them. Sequence only true dependencies; anything that can run on its own runs on its own.

## 6. Stacks

Use `gh stack` whenever it is available. When any PR in a stack merges, restack the rest onto the live base with `gh stack sync --prune`. Never strand a branch on a merged base, and never manual-merge in a way that bypasses the restack.

## 7. Two approvals

You act between the plan and the merge. Never merge, push to the default branch, force-push (outside a stack restack), or post to GitHub unless the user asks.

## 8. Never leave the user's checkout on another branch

Executor never leaves the user's checkout on another branch. Work happens in worktrees; a skill that must switch the checkout switches it back before it ends. After a merge, the checkout returns to the default branch and what the merge finished is cleaned up (`scripts/repo-tidy.sh`).
