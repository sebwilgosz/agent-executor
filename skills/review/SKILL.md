---
name: review
description: "Executor: code review of a pull request or the current branch — duplication, correctness against the spec, test coverage, security, best practices, repo conventions, and a build that must pass. Each finding is verified by its own agent, confirmed bugs are fixed and reviewed again. Use when a pull request was just created, when the user asks for a code review, or gives a PR number or URL ('review #42', 'review this PR', 'check github.com/…/pull/42')."
---

# EXECUTOR · REVIEW

Review once, verify every finding independently, fix the confirmed bugs, review the fixes. The output is always the summary in `${CLAUDE_PLUGIN_ROOT}/references/review-format.md`: read it before step 4.

## 1. Target

| User gave | Target |
|---|---|
| PR number or URL | that pull request (`gh pr view <n> --json number,title,url,headRefName,headRefOid,baseRefName,isCrossRepository,body,files,additions,deletions,closingIssuesReferences`) |
| a branch name | that branch against its base |
| nothing | the current branch against its base, plus uncommitted changes |

The diff is `gh pr diff <n>` for a PR, `git diff <base>...HEAD` (and `git diff HEAD`) otherwise. Review the changed lines and what they affect, not the whole repository.

Load the rules the code must follow, all that exist: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, linter and formatter configs, and two or three neighbouring files of each changed file, for its idiom.

Find the spec, in this order: links in the PR body (Executor's own PRs carry it under `## Spec`, see `${CLAUDE_PLUGIN_ROOT}/references/pull-request.md`), the issues it closes, then `SPEC.md`, `specs/`, `docs/specs/`. No spec found: correctness is judged against the PR description, and the summary says so.

## 2. Build (start first, it runs while you review)

The build must pass. Find its commands in this order: the repo's own docs (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `README`), the CI workflow steps, then the manifest (`package.json` scripts, `Makefile`, `Rakefile`, `Gemfile` + test framework, `Cargo.toml`, `go.mod`, `pyproject.toml`). Run install, build, lint or type check, and the tests: every one of them the repo defines.

- **Where.** If the working tree is clean and `HEAD` is the PR's head commit, build here. Otherwise build in a throwaway worktree: `git fetch origin pull/<n>/head` and `git worktree add --detach "$TMPDIR/executor-<n>" FETCH_HEAD`. Never check the PR out over the user's working tree.
- **Long builds** run in the background; carry on with step 3 and collect the result before step 4.
- **CI.** For a PR also read `gh pr checks <n>`. Report its state as it is; don't wait for it.
- **A failed build** is a Critical finding, category Build, linked to the first failing file when the log names one. Its evidence is the command and the failing lines of the log, so it needs no verifier.
- **Could not run** (no commands found, a missing service, a secret): say why in the Build line. Never report a build you didn't run as passed.

## 3. Review: six dimensions

Go through the diff once per dimension:

1. **Duplication**: code that repeats logic already in the repo or elsewhere in the diff. Name the existing function it should call.
2. **Correctness against the spec**: every requirement the change claims to meet is met; every behaviour it adds is asked for. Off-by-one, nil and empty input, error paths, concurrency, ordering.
3. **Test coverage**: each new or changed behaviour has a test that would fail without it. Each spec requirement has one. Tests that assert nothing count as missing.
4. **Security**: injection, missing authorisation, secrets in code or logs, unsafe deserialisation, user input reaching a shell, a query or a path, new dependencies.
5. **Best practices**: error handling, naming, dead code, needless complexity, resource leaks, performance traps in hot paths. **Inline comments**: say which can be removed or cut shorter: a comment that restates the code, narrates its history, or went stale; one that a clearer name would make unnecessary. A comment that explains *why* stays. One finding per file, a Suggestion.
6. **Repo conventions**: whatever the files loaded in step 1 require, and the idiom of the surrounding code. For a PR, also its description against `${CLAUDE_PLUGIN_ROOT}/references/pull-request.md`: a wall of text, a missing Testing section, a missing diagram where the change has a shape. One finding for the whole description, a Suggestion, linked to the PR. A refactor mixed into a feature PR large enough to belong in its own PR (`${CLAUDE_PLUGIN_ROOT}/references/implementation.md`, step 4) is a Suggestion too.
   **References to local material** anywhere in the diff, the commit messages or the PR description: local file paths outside the repo, Obsidian notes or `[[wikilinks]]`, numbered items of a local spec, brainstorming sections. A reader of the repo can't follow them. Critical in the diff and the description, where the fix loop replaces them with the thing itself; in a commit message, which is never rewritten, a Suggestion that names the commit.

Write each finding as the format file says: location, category, defect, "Fails when", severity. Merge findings with one root cause into one. Keep the ten most valuable Suggestions; Critical findings are never cut.

## 4. Draft the two sections

Sort the findings into **Critical** and **Suggestions**, one bullet each, in the format file's finding line. This draft is what the verifiers check.

## 5. Verify: one agent per finding

Spawn one `executor:verifier` agent per finding, except a failed build, **all in one message** so they run in parallel. Give each one only:

- the finding line as drafted, with its severity
- the repo path, and the worktree path if you built in one
- the head commit, the base branch, and the PR number if there is one
- the spec's path or link, if found

Never pass your reasoning, other findings or your confidence: the verifier's job is to disprove the claim, and a hypothesis handed to it tends to come back confirmed.

Apply each verdict:

| Verdict | Then |
|---|---|
| CONFIRMED | keep the finding as the verifier restated it |
| RECLASSIFIED | move it to the severity the verifier gave, with its wording |
| DEBUNKED | move it to "Dismissed after verification", with the verifier's reason |

## 6. Fix the bugs, then review again

Every Critical finding left after step 5 is a bug, and Executor fixes it. Suggestions are never fixed here.

1. **Where.** On top of the PR's head commit: in the worktree from step 2 if you built in one (commit on its detached `HEAD`), otherwise in the current checkout. A PR from a fork (`isCrossRepository`) is not yours to change: skip fixing and list its Critical findings as open.
2. **Fix.** The smallest change that removes the failure. A bug with no test gets the failing test first, then the fix. Never edit a test to make it pass, and never touch a spec test: if one looks wrong, leave the finding open and say why.
3. **Commit.** One commit per finding, the message naming the defect. Never amend or rewrite commits already on the branch.
4. **Review again, without spawning agents.** In this context: rerun the build; check that each fix removes its "Fails when" scenario; review only the fix commits against the six dimensions. A finding you check yourself here needs the same evidence a verifier would give: the lines that produce the failure.
5. **Repeat** step 6 while Critical findings remain, at most **3 rounds**. Whatever is still open after round 3 stays in Critical, with what was tried.
6. **Push** the fix commits to the PR's own branch: `git push origin HEAD:<headRefName>`. Never force-push, never push to any other branch. For a local review with no PR, commit and don't push.

**A PR in a stack** (its branch is in `gh stack view --json`, or its base isn't the default branch) is fixed on its own branch, so the branches above it pick the fix up: `gh stack checkout <headRefName>` in the current checkout, commit there, then `gh stack rebase --upstack` and `gh stack push`. That push rebases the branches above with `--force-with-lease`, the one rewrite allowed; commits are never changed. If the working tree isn't clean, don't switch: leave the findings open and say why. Commands and conflicts: `${CLAUDE_PLUGIN_ROOT}/references/stacks.md`.

## 7. Report

Clean up any worktree you added (`git worktree remove`). Then print the summary exactly as `references/review-format.md` lays it out, and nothing after it but the commit links. Never post the review to GitHub unless the user asks.
