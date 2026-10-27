# Changelog

## 0.1.0 — 2026-10-26

- `/executor:review`: builds the change and reviews it in six dimensions (duplication, correctness against the spec, test coverage, security, best practices, repo conventions). Findings are sorted into Critical and Suggestions, each linked to its file and line.
- New `executor:verifier` agent, one per finding, which tries to disprove it and answers confirmed, debunked or reclassified.
- Confirmed Critical findings are fixed on the PR's branch, one commit each, then reviewed again in the same context, at most three rounds.
- Every review ends with the same summary, laid out in `references/review-format.md`.
- A `PostToolUse` hook starts a review whenever Claude creates a pull request.
- A second hook assigns every PR Claude creates to its author (`gh pr edit --add-assignee @me`), since gh has no setting for a default assignee. Plain shell, no AI: the gh calls run detached, so the session never waits on GitHub, and a failure is written to `~/.engineer-of-wealth/executor/assign.log`. Both hooks are local and return in about 20 ms on an ordinary tool call.
- `/executor:menu`, the front door.
- `references/feature-done.md`: a feature is done only when its PR is open. Spec tests and the whole build green, then a draft PR in its stack with a fixed body (spec, done, build, depends on); the review starts through the hook and a ✅ or ⚠️ verdict marks it ready.
- `references/stacks.md`: features ship as GitHub stacked PRs with `gh stack`. The foundation merges first, one stack per dependency chain, every command non-interactive, plain chained PRs when the repo has no stacks.
- The review fixes a stacked PR on its own branch and rebases the branches above it. The hook also starts reviews for PRs opened by `gh stack submit` and `gh stack link`.
