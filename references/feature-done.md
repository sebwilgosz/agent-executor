# A feature is done when its PR is open

Executor builds a spec one feature at a time, each on its own branch. A feature ends in exactly one way: **a pull request is opened.** Not a summary, not a question, not a branch left on the machine. Every time, without asking.

## How it's built

`${CLAUDE_PLUGIN_ROOT}/references/implementation.md`: spec tests first (automated where possible, manual scenarios where not), the repo's own patterns, a commit per finished step graded on security, performance and correctness, refactors in their own PR, no inline comments, no references to local material.

## When it's finished

All of these, checked, not assumed:

1. Every spec requirement this feature owns has its spec test or manual scenario, and every one passes: tests run green, scenarios walked through where the session can, otherwise listed for you to check.
2. The build passes, as far as the brief's `CI:` line says (a brief without one, as when a builder runs outside a build: treat as `CI: none`). The repo's own commands, the same ones `executor:review` runs, step 2:
   - `CI: none`: the whole build, locally: install, build, lint or type check, the full test suite.
   - `CI: configured <file>`: install, build, and the tests covering this feature's code plus its spec tests, locally. The full suite is left to CI, and the review collects its result.
   - Lint and type check, by the brief's `HOOKS:` line: `HOOKS: installed`, not run by hand: fix what the commit check printed after your commits. `HOOKS: off` (or no line): run them once before the PR.

   The handback's Testing line says which of these ran.
3. No spec test was weakened to pass, and none changed without the user's approval.
4. The branch holds only this feature's commits, on top of the branch it depends on. A refactor it needed is in its own PR below it.

If any of these fails, the feature isn't finished: keep working, or stop and say what blocks it. Never open a PR for a red build to "show progress".

## Opening the PR

Two calls, nothing else: write the body, run the script. `pr-open.sh` puts the branch in its stack, pushes, opens the draft PR on the right base (or updates the one that exists), sets the title and body, and fills **Depends on** itself. Do not run `git`, `gh stack` or `gh pr` for this by hand; `${CLAUDE_PLUGIN_ROOT}/references/stacks.md` explains the stacks behind it.

1. Write the body to a file as `${CLAUDE_PLUGIN_ROOT}/references/pull-request.md` lays it out: short, readable, a diagram when the change has a shape, the spec tests under **Testing**. Leave out **Depends on**.
2. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pr-open.sh --branch <branch> --below <the branch below it in the stack, or default> --title "<title>" --body-file <file>`.
3. Act on the tagged line it prints (the exit code is always 0):
   - `PR: #<n> <url> base=<base> opened|updated`: the PR is open. Report its URL.
   - `RETARGETED: <old-base> merged, based on <default> instead`: the branch below was already merged, so the PR is based on the default branch. Say so in the report.
   - `UNSTACKED: <reason> - opened as a plain PR`: `gh stack` failed, so the PR is open outside the stack. Say so in the report, with the reason.
   - `STOP: <reason>`: nothing was opened. Report the reason and stop; do not try the git or gh steps by hand.

When the script prints `opened`, the plugin's hook starts `executor:review` on the new PR; an `updated` PR never starts it again. Let it run to its summary. A feature built by a builder agent under `/executor:build` stops at the open PR: build runs the review, since a builder can't start the review's agents.

The feature is done when the review's summary says ✅ or ⚠️: the review has marked your PR ready, and it's yours to merge. On ❌ it stays a draft: the review has already fixed what it could, and whatever is still Critical goes back to building this feature.
