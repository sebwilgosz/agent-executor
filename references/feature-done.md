# A feature is done when its PR is open

Executor builds a spec one feature at a time, each on its own branch. A feature ends in exactly one way: **a pull request is opened.** Not a summary, not a question, not a branch left on the machine. Every time, without asking.

## It starts with the spec tests

You write the spec; Executor writes the tests. Before the first line of the feature's code, Executor turns every spec requirement the feature owns into a high-level test: what the user or the caller sees, not how the code does it. They fail at first. They are the ground the feature is built against, so it can't drift from the spec by accident.

- One test per requirement, named after it, in the repo's test framework and style.
- Commit them first, on the feature's branch, in their own commit: `Spec tests for <feature>`.
- From then on they are **spec tests**: the code changes to pass them, they never change to pass the code. A spec test that turns out wrong (the spec says something else, or it can't be met as written) stops the feature: say which test and why, and ask.

## When it's finished

All of these, checked, not assumed:

1. Every spec requirement this feature owns has its spec test, and every one passes.
2. The whole build passes: install, build, lint or type check, the full test suite, with the repo's own commands (the same ones `executor:review` runs, step 2).
3. No spec test changed after its first commit.
4. The branch holds only this feature's commits, on top of the branch it depends on.

If any of these fails, the feature isn't finished: keep working, or stop and say what blocks it. Never open a PR for a red build to "show progress".

## Opening the PR

Features ship as stacked PRs: `${CLAUDE_PLUGIN_ROOT}/references/stacks.md` has the setup, how a spec maps to stacks, and every command.

1. The feature's branch sits in its stack: started with `gh stack init <branch>`, or added on top of the feature it depends on with `gh stack add <branch>`.
2. Push and open: `gh stack submit --auto`. It pushes every branch of the stack and opens a draft PR for each one that has none, based on the branch below it. If the repo has no stacked PRs (exit code 9), use `gh pr create --draft --base <the branch below> --head <branch>`.
3. Give the new PR its title and body as `${CLAUDE_PLUGIN_ROOT}/references/pull-request.md` lays them out: short, readable, a diagram when the change has a shape, and the spec tests under **Testing**, so the review finds the spec and the evidence. `gh pr edit <n> --title "<title>" --body-file <file>`.

4. Opening the PR starts `executor:review` on it through the plugin's hook, once the title and body are set. Let it run to its summary.

The feature is done when the review's summary says ✅ or ⚠️: mark the PR ready, `gh pr ready <n>`, and it's yours to merge. On ❌ it stays a draft: the review has already fixed what it could, and whatever is still Critical goes back to building this feature.
