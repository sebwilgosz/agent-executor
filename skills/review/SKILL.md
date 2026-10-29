---
name: review
description: "Executor: review a pull request or the current branch auto-fixing verified confirmed bugs. Use when a PR was just created, when the user asks for a code review, or names a PR 'review #42', 'review github.com/…/pull/42"
---

# EXECUTOR · REVIEW

Review once, verify every finding independently, fix the confirmed bugs, review the fixes. The output is always the summary in `${CLAUDE_PLUGIN_ROOT}/references/review-format.md`: read it before step 4.

## 1. Target

| User gave        | Target                                                                                                                                                                   |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| PR number or URL | that pull request (`gh pr view <n> --json number,title,url,headRefName,headRefOid,baseRefName,isCrossRepository,body,files,additions,deletions,closingIssuesReferences`) |
| a branch name    | that branch against its base                                                                                                                                             |
| nothing          | the current branch against its base, plus uncommitted changes                                                                                                            |

Load the rules the code must follow, all that exist: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, linter and formatter configs, and two or three neighbouring files of each changed file, for its idiom.

Find the spec, in this order: 
1. links in the PR body (Executor's own PRs carry it under `## Spec`, see `${CLAUDE_PLUGIN_ROOT}/references/pull-request.md`), 
2. the issues it closes, 
3. then `SPEC.md`, 
4. `specs/`, 
5. `docs/specs/`. 

If No spec found: correctness is judged against the PR description, and the summary says so.

## 2. Build (start first, it runs while you review)

The build must pass. Find its commands in this order: the repo's own docs (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `README`)

- **Where.** If the working tree is clean and `HEAD` is the PR's head commit, build here. Otherwise build in a throwaway worktree: `git fetch origin pull/<n>/head` and `git worktree add --detach "$TMPDIR/executor-<n>" FETCH_HEAD`. Never check the PR out over the user's working tree.
- **Long builds** run in the background; carry on with step 3 and collect the result before step 4.
- **CI.** For a PR also read `gh pr checks <n>`. Report its state as it is; don't wait for it.
- **A failed build** is a Critical finding, category Build, linked to the first failing file when the log names one. Its evidence is the command and the failing lines of the log, so it needs no verifier.
- **Could not run** (no commands found, a missing service, a secret): say why in the Build line. Never report a build you didn't run as passed.

## 3. Review: six dimensions
Go through the diff once per dimension:

1. **Duplication**: code that repeats logic already in the repo or elsewhere in the diff.
2. **Correctness against the spec**: every requirement the change claims to meet is met; every behaviour it adds is asked for. Off-by-one, nil and empty input, error paths, concurrency, ordering. Code shaped to pass a test rather than meet the requirement is Critical.
3. **Test coverage**: each new or changed behaviour has a test that would fail without it. Each spec requirement has one. Tests that assert nothing count as missing.
4. **Security**: injection, missing authorisation, secrets in code or logs, unsafe deserialisation, user input reaching a shell, a query or a path, new dependencies.
5. **Best practices**: error handling, naming, dead code, needless complexity, resource leaks, performance traps in hot paths. **Inline comments**: say which can be removed or cut shorter. A comment that explains *why* stays. One finding per file, a Suggestion.
6. **Repo conventions**: whatever the files loaded in step 1 require, and the idiom of the surrounding code. For a PR, also its description against `${CLAUDE_PLUGIN_ROOT}/references/pull-request.md`: a wall of text, a missing Testing section, a missing diagram where the change has a shape. One finding for the whole description, a Suggestion, linked to the PR. A refactor mixed into a feature PR large enough to belong in its own PR is a Suggestion too.
   **References to local material** anywhere in the diff, the commit messages or the PR description: local file paths outside the repo, numbered items of a local spec, brainstorming sections.

Write each finding as the format file says. Merge findings with one root cause into one. Keep the ten most valuable Suggestions; Critical findings are never cut.
## 4. Draft the two sections

Sort the findings into **Critical** and **Suggestions**, one numbered finding each in the format file's finding line, the count running continuously across both sections. This draft is what the verifiers check.

## 5. Verify: one agent per finding

Spawn one `executor:verifier` agent per finding, except a failed build, **all in one message** so they run in parallel. Give each one only:

- the finding line as drafted, with its severity
- the repo path, and the worktree path if you built in one
- the head commit, the base branch, and the PR number if there is one
- the spec's path or link, if found

Tell to be sceptical. Never pass your reasoning, other findings or your confidence: the verifier's job is to disprove the claim.

Apply each verdict:

| Verdict      | Then                                                        |
| ------------ | ----------------------------------------------------------- |
| CONFIRMED    | keep the finding as the verifier restated it                |
| RECLASSIFIED | move it to the severity the verifier gave, with its wording |
| DEBUNKED     | remove from output                                          |

## 6. Fix the bugs, then review again

Every Critical finding left after step 5 is a bug, and Executor fixes it. Suggestions are never fixed here.

1. **Where.** On top of the PR's head commit
2. **Fix.** The smallest change that removes the failure. A bug with no test gets the failing test first, then the fix. Never edit a test to make it pass. A spec test that looks wrong stays as it is: leave the finding open, say why and what you would change; it changes only with the user's approval.
3. **Commit.** One commit per finding, the message naming the defect. Never amend or rewrite commits already on the branch unless explicitly asked.
4. **Review again, without spawning agents.** In this context: rerun the build; check that each fix removes its "Fails when" scenario; review only the fix commits against the six dimensions.
5. **Repeat** step 6 while Critical findings remain, at most **3 rounds**.
6. **Push** the fix commits to the PR's own branch: `git push origin HEAD:<headRefName>`. Never force-push, never push to any other branch. For a local review with no PR, commit and don't push.

**A PR in a stack** (its branch is in `gh stack view --json`, or its base isn't the default branch) is fixed on its own branch, so the branches above it pick the fix up: `gh stack checkout <headRefName>` in the current checkout, commit there, then `gh stack rebase --upstack` and `gh stack push`. That push rebases the branches above with `--force-with-lease`, the one rewrite allowed; commits are never changed. If the working tree isn't clean, don't switch: leave the findings open and say why. Commands and conflicts: `${CLAUDE_PLUGIN_ROOT}/references/stacks.md`.

## 7. Report

Clean up any worktree you added (`git worktree remove`). Then print the summary exactly as `references/review-format.md` lays it out, and nothing after it but the commit links. Never post the review to GitHub unless the user asks.
