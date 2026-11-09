# Review steps

The steps of a review, shared by `/executor:review`, `/executor:build` and the agents they spawn. The output is always the summary in `references/review-format.md`: read it before step 4.

| Steps | Who | Notes |
|---|---|---|
| 1, hand-off part | the caller, a main thread | before any agent starts |
| 1, 2, 3, 4 | `executor:reviewer` | writes the draft to the review file |
| 5 | the caller spawns the verifiers; `executor:fixer` applies the verdicts | subagents can't spawn agents |
| 6, and 7 up to the Ready line | `executor:fixer` | only when a Critical finding is left |
| 7, save, post and print | the caller | |

## 1. Target and mode

**Caller only, before any agent starts.** **Caller only, before any agent starts.** **A PR named as `owner/repo#N` or `https://github.com/owner/repo/pull/N`** may belong to another repo, so first run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/find-checkout.sh "<ref>"`. Its first line, `PR:`, gives the PR's URL. Then:

- `HERE:` this folder is the PR's repo: go on below with the URL, as today.
- `CHECKOUT:` the repo is checked out in that folder, fetched, its default branch brought up to date where that was safe. Never review it from here: hand it off.
  - The new session runs `/executor:review <url>`, with `--base origin/<default>` after the URL when `BASE:` is `origin/<default>`, so its summary can say what it worked from.
  - With a tool that starts a session in a folder, propose that session with it: the `CHECKOUT:` folder, that command as its prompt. Otherwise print the `RUN:` line as the one command to run, with that `--base` after the URL, inside the quotes, when it applies.
  - Above it, one line each, as printed: `ALSO:` (other folders with the same repo, not used), `NOTE:` (a clone made, a fetch that failed), and `BASE:` when it is `origin/<default>` (the local default branch was left alone, and why).
  - Then stop: this session reviews nothing.
- `LOOKED:` and `CLONE:` no checkout under the search roots. List where it looked, show the `CLONE:` command and ask whether to clone. On no, stop: nothing is cloned. On yes, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/find-checkout.sh "<ref>" --clone` and read its lines as above.
- `STOP:` give the user that line, which says what to do, and stop.

A bare PR number or a branch name is in this repo: no lookup. The agents are given the resolved target and skip the lookup above. The agents are given the resolved target, so they skip the lookup above.

| User gave        | Target                                                                                                                                                                   |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| PR number or URL | that pull request (`gh pr view <n> --json number,title,url,headRefName,headRefOid,baseRefName,isCrossRepository,body,files,additions,deletions,closingIssuesReferences`) |
| a branch name    | that branch against its base                                                                                                                                             |
| nothing          | the current branch against its base, plus uncommitted changes                                                                                                            |

**Note the checkout's branch.** Run `git branch --show-current` in the folder you review from and keep the answer (empty for a detached HEAD, with `git rev-parse HEAD` as the answer then). Step 7 checks it.

**Mode.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/review-mode.sh pr <n|url>` for a PR, or `… branch [<name>]` for a branch, passing `--fix` or `--no-fix` if the user gave one. It prints one line, `MODE: fix · <why>` or `MODE: report-only · <why>`, and that is the mode for the whole review: fix only on your own PR or branch, never on a fork, where the push can't land; `--fix` and `--no-fix` override the rest. Keep `<why>` for the Rounds line.

**`--base origin/<default>`** comes from a hand-off: the checkout's local default branch was left behind or holds local work. Read the rules and neighbouring files below from the PR's head or `origin/<default>`, never from the local default branch, and say so on the summary's Branch line.

Load the rules the code must follow, all that exist: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, linter and formatter configs, and two or three neighbouring files of each changed file, for its idiom.

Find the spec, in this order: 
1. links in the PR body (Executor's own PRs carry it under `## Spec`, see `${CLAUDE_PLUGIN_ROOT}/references/pull-request.md`), 
2. the issues it closes (a linked issue is read as the spec), 
3. the spec home: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-home.sh --repo <repo>`, then pick the spec as `${CLAUDE_PLUGIN_ROOT}/references/spec-home.md` says, 
4. then `SPEC.md`, 
5. `specs/`, 
6. `docs/specs/`. 

If No spec found: correctness is judged against the PR description, and the summary says so.

## 2. Build (start first, it runs while you review)

The build must pass. For a PR, CI is the build where the repo has it.

- **CI first, for a PR.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ci-checks.sh <n> --wait 20` in the background before anything else. That one call is also the detection: do not run `--detect`. Review the diff meanwhile and collect the result before step 4. Keep its first line as step 2's answer.
  - `CI: green`: the Build line says CI passed.
  - `CI: red <check> <url>`: a Critical finding, category Build, linked to the first failing file when the `LOG:` lines name one. Its evidence is the check name, the url and the `LOG:` lines, so it needs no verifier.
  - `CI: running` after the wait: no Critical finding. The Build line says CI is still running, the CI line shows it, and the PR stays a draft (step 7).
  - `CI: none`, `UNKNOWN:`, or a review of a branch with no PR: build locally, as below.
- **Local build.** Find its commands in this order: the repo's own docs (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `README`).
  - **Where.** If the working tree is clean and `HEAD` is the PR's head commit, build here. Otherwise build in a throwaway worktree: `git fetch origin pull/<n>/head` and `git worktree add --detach "$TMPDIR/executor-<n>" FETCH_HEAD`. Never check the PR out over the user's working tree. The reviewer removes that worktree before it returns, also when the build fails.
  - **Long builds** run in the background; carry on with step 3 and collect the result before step 4.
  - **A failed build** is a Critical finding, category Build, linked to the first failing file when the log names one. Its evidence is the command and the failing lines of the log, so it needs no verifier.
  - **Could not run** (no commands found, a missing service, a secret): say why in the Build line. Never report a build you didn't run as passed.

## 3. Review: six dimensions
Go through the diff once per dimension:

1. **Duplication**: code that repeats logic already in the repo or elsewhere in the diff.
2. **Correctness against the spec**: every requirement the change claims to meet is met; every behaviour it adds is asked for. Off-by-one, integer overflow, nil and empty input, error paths, concurrency, ordering. Code shaped to pass a test rather than meet the requirement is Critical.
3. **Test coverage**: each new or changed behaviour has a test that would fail without it. Each spec requirement has one. Tests that assert nothing count as missing.
4. **Security**: injection, cross-site scripting, CSRF, SSRF, missing authorisation, secrets in code or logs, unsafe deserialisation, user input reaching a shell, a query or a path, new dependencies.
5. **Best practices**: error handling, naming, dead code, needless complexity, resource leaks. **Performance traps**: N+1 and other queries in a loop, unbounded queries or loops, O(n²) over user-sized data, a new query with no index. Critical only when the cost is real on a path the diff touches (an unbounded query on a request path, an N+1 over user data); otherwise a Suggestion. **Inline comments**: say which can be removed or cut shorter. A comment that explains *why* stays. One finding per file, a Suggestion.
6. **Repo conventions**: whatever the files loaded in step 1 require, and the idiom of the surrounding code. For a PR, also its description against `${CLAUDE_PLUGIN_ROOT}/references/pull-request.md`: a wall of text, a missing Testing section, a missing diagram where the change has a shape. One finding for the whole description, a Suggestion, linked to the PR. A refactor mixed into a feature PR large enough to belong in its own PR is a Suggestion too.
   **References to local material** anywhere in the diff, the commit messages or the PR description: local file paths outside the repo, numbered items of a local spec, brainstorming sections.
   **Docs**, category `Docs`: run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/docs-mentions.sh <base> [<identifier>...]` where you build, with the changed function, route or config names you judge public; `<base>` as `origin/<branch>` for a PR. Docs that now state something false (a removed flag still documented): Critical. Behaviour, flags, config, CLI or API changed without touching the docs that describe them: Suggestion. `UNKNOWN`: skip this check, say so on the summary's Docs line, and go on.

Write each finding as the format file says. Merge findings with one root cause into one. Keep the ten most valuable Suggestions; Critical findings are never cut.
## 4. Draft the two sections

Sort the findings into **Critical** and **Suggestions**, one numbered finding each in the format file's finding line, the count running continuously across both sections. When you cannot settle a finding's severity, draft it as Critical: a verifier then judges it and can bring it down. A real bug must not escape verification by being drafted as a Suggestion. This draft is what the verifiers check.

**The reviewer writes the whole draft to the review file** (`bash ${CLAUDE_PLUGIN_ROOT}/scripts/review-post.sh --path pr <url>`, or `--path branch [<name>]`, prints where), laid out as `references/review-format.md` says, and never edits a tracked file or pushes. With no Critical finding the file is final: it writes the Verdict, the Rounds line (`fix · <why> · no fixes needed`, or `report-only · <why>`) and the Build and CI lines itself. With Critical findings it leaves the Verdict, Rounds, Ready and Checkout lines to the fixer.

It returns only this, so the caller's context stays small:

```text
REVIEW: <file path>
MODE: fix · <why> | report-only · <why>
BUILD: passed | failed | not run · <reason>
CRITICAL: <n>
<each Critical finding line, verbatim, one per finding, with its number>
SUGGESTIONS: <n>
```

A Critical finding that needs no verifier (a failed build, or red CI) ends its line with ` [build]`. Suggestions stay in the file.

## 5. Verify: one agent per Critical finding

The caller does this, from the reviewer's finding lines: subagents can't spawn agents. Spawn one `executor:verifier` agent per Critical finding, except a failed build (a `[build]` line), **all in one message** so they run in parallel. Suggestions get no verifier: they are only listed, never fixed. Give each one only:

- the finding line as drafted, with its severity
- the repo path
- the head commit, the base branch, and the PR number if there is one
- the spec's path or link, if found

Tell to be sceptical. Never pass your reasoning, other findings or your confidence: the verifier's job is to disprove the claim.

The verdicts go to the fixer with the review file and the mode, a `[build]` finding as CONFIRMED. The fixer applies each one to the file, also when every finding was debunked (then it only applies, and fixes nothing):

| Verdict      | Then                                                        |
| ------------ | ----------------------------------------------------------- |
| CONFIRMED    | keep the finding as the verifier restated it                |
| RECLASSIFIED | move it to the severity the verifier gave, with its wording; a Critical brought down to Suggestion is listed among the Suggestions |
| DEBUNKED     | remove from output                                          |

## 6. Fix the bugs, then review again (fix mode only)

The fixer does this, given the review file, the verdicts, the mode and the branch the checkout was on. It reviews its own fix commits in its own context, on its own model in every round, the last included.

**Report-only** skips this step: nothing is committed, checked out or pushed, and every Critical finding stays open in the summary. Go to step 7.

Every Critical finding left after step 5 is a bug, and Executor fixes it. Suggestions are never fixed here.

1. **Where.** On top of the PR's head commit
2. **Fix.** The smallest change that removes the failure. A bug with no test gets the failing test first, then the fix; a false doc is simply corrected. Never edit a test to make it pass. A spec test that looks wrong stays as it is: leave the finding open, say why and what you would change; it changes only with the user's approval.
3. **Commit.** One commit per finding, the message naming the defect. Never amend or rewrite commits already on the branch unless explicitly asked.
4. **Review again, without spawning agents.** In this context: check that each fix removes its "Fails when" scenario; review only the fix commits against the six dimensions. Reuse step 2's answer, with no new detection. With CI (`CI: green`, `red` or `running`), run only the tests that cover the round's fixes (the failing test it added, the test files of the code it touched), not the full build. Without CI (`CI: none`, `UNKNOWN:`, no PR), rerun the build as before.
5. **Repeat** step 6 while Critical findings remain, at most **3 rounds**.
6. **Push** the fix commits to the PR's own branch: `git push origin HEAD:<headRefName>`. Never force-push, never push to any other branch. For a local review with no PR, commit and don't push.
7. **CI on the pushed head** (a PR with CI): after the last round and the push, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ci-checks.sh <n> --wait 20`. `CI: red` with rounds left: another round on its `LOG:` lines. `CI: red` with none left: the finding stays open and the verdict is ❌, as today. `CI: running` after the wait: the CI line says so and the PR stays a draft.

**A PR in a stack** (its branch is in `gh stack view --json`, or its base isn't the default branch) is fixed on its own branch, so the branches above it pick the fix up: in a worktree on that branch, so the user's checkout is never switched: `git worktree add "$TMPDIR/executor-fix-<n>" <headRefName>`, then run every fix, build, commit and `git push` below from there. Finish with `gh stack rebase --upstack` and `gh stack push`, also from the worktree. That push rebases the branches above with `--force-with-lease`, the one rewrite allowed; commits are never changed. Remove the worktree (`git worktree remove "$TMPDIR/executor-fix-<n>"`) when the fixes are pushed, and also when they fail or stop early. If the checkout is already on the PR's own branch (`<headRefName>`), git won't add a second worktree on it: when its tree is clean, fix in place there instead, with the same commits, rebase and push, and no worktree; no switch happens, so nothing drifts. When it is on that branch and the tree has uncommitted changes, touch nothing: leave the findings open and say why. If the checkout is on one of the branches above the PR's and has uncommitted changes, the rebase would move them: leave the findings open and say why. Commands and conflicts: `${CLAUDE_PLUGIN_ROOT}/references/stacks.md`.

## 7. Report

**The fixer finishes the file.** Remove any worktree you added (`git worktree remove`). Then assert the checkout is where the review found it: `git -C <checkout> branch --show-current` must equal the branch noted in step 1. If it doesn't, switch back when the tree is clean; either way, the Checkout line says so. **Fix mode and a verdict of ✅ or ⚠️:** run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/review-ready.sh <n|url>` for a PR, or `… review-ready.sh --branch [<name>]` for a branch. It marks your own draft ready once CI is green or absent, and leaves any other PR, or one whose CI is still running or red, as it is. A `SKIP:` for CI goes in the Ready line; for a running CI it says to rerun `review-ready.sh <n>` once CI is green, because nothing flips the draft later. Write the final Verdict, Rounds, Ready and Checkout lines into the file, and return the one `DONE:` line:

```text
DONE: #<n> · <✅|⚠️|❌> · <c> Critical open · <s> suggestions · <r> rounds · <f> fixed · <file>
```

With no Critical finding there is no fixer: the caller does what this paragraph says, from the reviewer's file.

**The caller then saves, posts and prints, in this order:**

1. The file is already where `review-post.sh --path` said; read the summary from it.
2. Post it only through `review-post.sh`, which follows the setting: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/review-post.sh <url> <file>` for a PR. A branch with no PR is only saved. The user asking in chat to post counts as `Post: own PRs` for that one review (`review-post.sh --on <url> <file>`), and never for someone else's PR. Never post any other way.
3. Print the summary exactly as `references/review-format.md` lays it out, then the `POSTED:`, `NOTE:` and `STOP:` lines of the post, then the commit links, if fix mode made any. Nothing else.

An agent that returns nothing usable (no `REVIEW:` line, no `DONE:` line): the PR is marked `❌ review failed: <reason>` in the summary, and nothing is retried silently.
