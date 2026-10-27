# Changelog

## Unreleased

- `/executor:build`: a spec to a stack of reviewed PRs. It checks the spec, plans it as a checklist in `.executor/plan.md` that you approve (`references/plan.md`), builds the foundation alone and stops for its merge, then runs one `executor:builder` per stack in parallel worktrees, reviews every PR, marks it ready on ✅ or ⚠️ and starts the next feature of its stack. A second run carries on from the first unticked item. You merge.
- The `executor:implementer` agent is now `executor:builder`. It stops at the open PR; build runs the review.
- `/executor:help` lists `/executor:build` and routes "build this" to it.
- `/executor:help` reads better in a busy terminal: sections in capitals (INCLUDES, SETUP), commands in one column and what they do in another, and the build step marked as coming next.

## 0.1.4 — 2026-10-27

- `/executor:menu` is now `/executor:help`, in `skills/help/`. The skill shows what Executor does and routes; the self-audit checks it under its new name and holds it to `disable-model-invocation` like `init` and `self-audit`.
- `/executor:help` on its own prints the help at once, with no model call: a hook in `hooks/register.ts` answers the command with the help block of `skills/help/SKILL.md`, the one place the help is written. With text after it (`/executor:help review 42`), or where Claude Code runs no plugin hooks, the skill runs and routes as before.
- The help skill no longer names a model. It now only routes, and the session's own model reads the conversation from its cache, where a switch to another model would read it all again.
- The help skill is yours to type and no longer Claude's to start (`disable-model-invocation`), so its description leaves the skill list every session sends to the model. Asking in plain words ("review #42") still reaches `/executor:review` through that skill's own description.

## 0.1.3 — 2026-10-27

- `references/implementation.md`: how a feature is built. It starts with a spec check: when there's no spec, or it leaves open what the feature does, its inputs and outputs, edge cases, scope or how to tell it's done, Executor says so and asks for the missing details instead of guessing, then confirms the requirements as a short list before writing anything. Then spec tests, automated where possible and written as manual scenarios where not, coarse and covering the edge cases, there to keep the work from drifting. Then the repo's existing patterns before anything new, correctness and performance as part of the job, a commit for every finished step, each graded on security, performance and correctness, then best practices and repo consistency.
- Spec tests serve a correct feature, not the other way round: code is never shaped to pass a test and a test is never weakened to pass. When building shows a spec test or the spec is wrong, Executor stops, says which, why and what it would change, and changes it only with your approval; the PR lists such changes. The review treats code shaped to pass a test as Critical.
- A refactor that would make the feature's PR big goes into its own PR, below the feature in the stack.
- No inline comments by default; explanations go in commit messages and the PR description. Project docs live in the README and dedicated Markdown files. Nothing ever refers to local material: local paths, notes-app notes or wikilinks, numbered items of a local spec, brainstorming sections.
- New `executor:implementer` agent, one per feature, at medium reasoning effort. Nothing spawns it yet; the build step that will comes next.
- The PR description gains manual scenarios in Testing, and its Spec section links only what a reader can open.
- The review flags references to local material (Critical in code and the description) and a refactor mixed into a feature PR.

## 0.1.2 — 2026-10-27

- A feature now starts with its spec tests: you write the spec, Executor turns each requirement the feature owns into a high-level test before the first line of code and commits them first. They are the ground the feature is built against, so it can't drift from the spec (`references/feature-done.md`).
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
