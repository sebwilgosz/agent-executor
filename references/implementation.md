# Implementing a feature

How Executor builds one feature, from its first test to its last commit. We do high-quality work: correct, fast where it matters, and in the repo's own style. The feature ends in a PR, as `references/feature-done.md` says.

## 1. Spec tests first

Before the first line of the feature's code, turn the requirements this feature owns into **spec tests**. They are the ground to come back to, so the work doesn't drift from the spec.

- **Automated where possible:** high-level tests of what the user or the caller sees, in the repo's test framework and style. Not how the code does it.
- **Manual scenarios where not:** when a requirement can't be automated (a visual result, an outside service, a device), write it as a short scenario: steps and the expected result. They go in the PR's Testing section.
- **Coarse, not fine-grained.** One test or scenario per requirement, plus the edge cases that matter: empty, too much, wrong input, failure of what it depends on. Don't polish them; finer tests come while building, where the code needs them.
- **They fail at first.** That is the point. Commit the automated ones before any code, in their own commit.
- **They don't move.** The code changes to pass them, never the other way round. A spec test that turns out wrong stops the feature: say which and why, and ask.

## 2. Build in the repo's way

- **Existing patterns first.** Before writing something, find how the repo already does it and do it the same way: its structure, naming, error handling, libraries. Reuse an existing function before writing a new one. A new dependency needs a reason the existing ones can't meet.
- **Correctness and performance are not optional.** Handle edge cases and error paths. Watch the hot paths: queries in loops, needless allocations, work repeated per request that could be done once.
- **Follow the rules** of the repo (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, linter configs) and of this file.

## 3. Commit every finished step

Commit each self-contained change as soon as it is complete: it builds, its tests pass, and it makes sense on its own. Never a pile of changes at the end.

- **The message explains.** A subject that says what changed, and a body that says why when it isn't obvious. That's where reasoning lives, not in the code.
- **Grade the commit before the next step**, in this order:
  1. Security
  2. Performance
  3. Correctness
  4. Best practices
  5. Repo consistency

  A problem in the first three is fixed now, in its own commit, before anything else. A problem in the last two is fixed before the PR opens. The grade stays out of the commit message.

## 4. Refactoring goes in its own PR

When the feature needs a refactor that would make its PR big, the refactor is a separate PR: same behaviour, its own branch, placed below the feature in the stack (`gh stack`, see `references/stacks.md`). The feature's PR then holds only the feature. A small, local tidy-up of code the feature touches anyway may stay.

## 5. Comments, docs, references

- **No inline comments by default.** The code should read without them. When one is needed, it is short and says *why*, never what the next line does. Explanations belong in commit messages and the PR description.
- **Project docs live in the repo:** the README and dedicated Markdown files (for example `docs/`). When a change alters what users or other developers see, update them in the same PR.
- **Never refer to local material.** Code, tests, comments, commits, docs and PRs never mention local file paths outside the repo, notes from a personal notes app (Obsidian notes or `[[wikilinks]]`), numbered items of a local spec ("requirement 3.2"), or sections of local brainstorming. A reader of the repo can't follow them. Say the thing itself.

## Effort

Implementation runs at medium reasoning effort: the `executor:implementer` agent sets `effort: medium`. Planning and review keep their own.
