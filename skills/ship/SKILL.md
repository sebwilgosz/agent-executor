---
name: ship
description: "Executor: take the current branch from finished code to an open draft pull request — commit what is pending, push, and open a DRAFT PR (the review then starts on its own). Use when the user asks to ship, push or submit the branch: 'ship this', 'push', 'commit and push', 'push changes', 'open a PR'. Not a bare mechanical git push."
---

# EXECUTOR · SHIP

The on-ramp from "the code is done" to an open draft pull request. The
deterministic work — the guard, the push, the PR-exists check and the base
branch — is `${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh`. You write only the commit
message and the PR body. You never run the review; opening the PR starts it.

## 0. Assert the plugin is current

This session may carry an old snapshot of Executor while a newer one is installed. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-check.sh 0.4.0`. On a `MISMATCH:` line, stop and give the user that one line (the loaded snapshot is stale; reload the plugin or start a fresh session) — ship nothing. `OK:` or `STOP:` (the check could not read the manifest): carry on.

## 1. Commit what is pending

If the working tree has uncommitted changes, commit them first — `ship.sh`
stops on a dirty tree. Stage the branch's own files and commit with a message
that says what changed and why. Ask only if the changes are ambiguous (unrelated
work mixed in, or it is unclear what belongs on this branch); otherwise commit
them yourself. Nothing to commit: go on.

## 2. Run the engine

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh"
```

It prints one of (exit code is always 0 — a stop is a note, not a failure):

| Line | Meaning | Do |
|---|---|---|
| `STOP: <reason>` | the branch can't ship | tell the user the reason in one line; stop |
| `PUSHED: <branch>` then `PR_EXISTS: #<n> <url>` | pushed; a PR is already open | tell the user it is pushed and the PR already exists (#n); stop — never open a second, never re-review |
| `PUSHED: <branch>` then `OPEN_PR: base=<base> head=<branch>` | pushed; no PR yet | go to step 3 with that `base` and `head` |

Idempotent by design: a branch that already has a PR is only pushed. The review
of follow-up edits is the user's own explicit `/executor:review`.

## 3. Open the draft PR

Only on `OPEN_PR`. Write the title and body as
`${CLAUDE_PLUGIN_ROOT}/references/pull-request.md` and
`${CLAUDE_PLUGIN_ROOT}/references/feature-done.md` lay them out — short and
readable, the spec tests under **Testing**, a diagram when the change has a
shape. Write the body to a file, then:

```bash
gh pr create --draft --base <base> --head <head> --title "<title>" --body-file <file>
```

Always a **draft**. Run `gh pr create` as your own call (not from inside a
script): the plugin's hook watches for it and, once the PR is open, assigns the
author (detached) and starts `executor:review`.

## 4. Stop here

Ship does not run the review itself — the hook does. Report in one or two lines
what happened: committed (if you did), pushed, and either the PR it opened or
the PR that already existed. Nothing else.
