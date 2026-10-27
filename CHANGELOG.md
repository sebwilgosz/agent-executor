# Changelog

## 0.1.2 — 2026-10-27

- A feature now starts with its spec tests: you write the spec, Executor turns each requirement the feature owns into a high-level test before the first line of code and commits them first. They are the ground the feature is built against, so it can't drift from the spec; the code changes to pass them, never the other way round (`references/feature-done.md`).
- `references/pull-request.md`: how Executor's PRs read. Fixed sections (Spec, What changes, Diagram, Testing, Depends on), bullets instead of paragraphs, one screen long, a Mermaid diagram or a screenshot when the change has a shape, and the spec tests in their own Testing section.
- The review checks two more things, both as Suggestions: inline comments that can be removed or cut shorter (best practices), and a PR description that breaks `pull-request.md` (repo conventions).

## 0.1.1 — 2026-10-27

- `/executor:init`, which you type once after installing. It checks the GitHub CLI, its sign-in, `jq` and the gh-stack extension. Executor works best with gh stack, so when it is missing init says why and offers to install it; it also offers the two git settings that keep `gh stack` from stopping at a prompt, in the current repository only. The shared Engineer of Wealth setup is offered too, skipped by default, since Executor itself reads nothing from it.
- `/executor:self-audit` and `scripts/self-audit.sh`: a read-only check of gh, its sign-in, gh stack, failed PR assignments in `assign.log`, the menu, the references, the two hooks and the user-only skills. One round, every finding says what to do, last line `executor: PASS|WARN|FAIL`.
- `references/shared-setup.md`, the copy every Engineer of Wealth plugin ships, and `references/init.md`, Executor's own steps, so a central setup can run Executor's init with the others.

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
