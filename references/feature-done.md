# A feature is done when its PR is open

Executor builds a spec one feature at a time, each on its own branch. A feature ends in exactly one way: **a pull request is opened.** Not a summary, not a question, not a branch left on the machine. Every time, without asking.

## How it's built

`${CLAUDE_PLUGIN_ROOT}/references/implementation.md`: spec tests first (automated where possible, manual scenarios where not), the repo's own patterns, a commit per finished step graded on security, performance and correctness, refactors in their own PR, no inline comments, no references to local material.

## When it's finished

All of these, checked, not assumed:

1. Every spec requirement this feature owns has its spec test or manual scenario, and every one passes: tests run green, scenarios walked through where the session can, otherwise listed for you to check.
2. The whole build passes: install, build, lint or type check, the full test suite, with the repo's own commands (the same ones `executor:review` runs, step 2).
3. No spec test changed after its first commit.
4. The branch holds only this feature's commits, on top of the branch it depends on. A refactor it needed is in its own PR below it.

If any of these fails, the feature isn't finished: keep working, or stop and say what blocks it. Never open a PR for a red build to "show progress".

## Opening the PR

Features ship as stacked PRs: `${CLAUDE_PLUGIN_ROOT}/references/stacks.md` has the setup, how a spec maps to stacks, and every command.

1. The feature's branch sits in its stack: started with `gh stack init <branch>`, or added on top of the feature it depends on with `gh stack add <branch>`.
2. Push and open: `gh stack submit --auto`. It pushes every branch of the stack and opens a draft PR for each one that has none, based on the branch below it. If the repo has no stacked PRs (exit code 9), use `gh pr create --draft --base <the branch below> --head <branch>`.
3. Give the new PR its title and body as `${CLAUDE_PLUGIN_ROOT}/references/pull-request.md` lays them out: short, readable, a diagram when the change has a shape, and the spec tests under **Testing**, so the review finds the spec and the evidence. `gh pr edit <n> --title "<title>" --body-file <file>`.

4. Opening the PR starts `executor:review` on it through the plugin's hook, once the title and body are set. Let it run to its summary.

The feature is done when the review's summary says ✅ or ⚠️: mark the PR ready, `gh pr ready <n>`, and it's yours to merge. On ❌ it stays a draft: the review has already fixed what it could, and whatever is still Critical goes back to building this feature.
