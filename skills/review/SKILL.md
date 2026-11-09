---
name: review
description: "Executor: review a pull request or the current branch, verifying every Critical finding; fixes the confirmed bugs on your own PRs, only reports on anyone else's. Use when a PR was just created, when the user asks for a code review, or names a PR as #42, owner/repo#N or a pull URL ('review #42', 'let's review acme/api#7'), from any folder: another repo's PR is handed off to its local checkout."
---

# EXECUTOR · REVIEW

Review once, verify every Critical finding independently, then fix the confirmed bugs and review the fixes, or only report them. This skill is the caller: it runs the agents in turn and prints the result. The steps themselves are in `${CLAUDE_PLUGIN_ROOT}/references/review-steps.md`, which the agents follow; the output is always the summary in `${CLAUDE_PLUGIN_ROOT}/references/review-format.md`.

## Flow

1. **Hand-off.** Do step 1's hand-off part yourself, before any agent starts. Note the checkout's branch (`git branch --show-current`, or `git rev-parse HEAD` when detached). Pass `--fix`, `--no-fix` and `--base origin/<default>` on to the reviewer if the user gave them.
2. **Reviewer.** Spawn `executor:reviewer` with the resolved target, those flags and the repo path. It does steps 1 to 4 and returns the `REVIEW:`, `MODE:`, `BUILD:`, `CRITICAL:` and `SUGGESTIONS:` lines.
3. **Verifiers**, only when `CRITICAL` is above 0: step 5, from the finding lines.
4. **Fixer**, only when `CRITICAL` is above 0. Spawn `executor:fixer` with the review file, the verdicts, the mode, the target, the noted branch and the `CI:` answer. It applies the verdicts and, in fix mode, steps 6 and 7 up to the Ready line. It returns one `DONE:` line.
5. **No Critical finding:** the reviewer's file is final. In fix mode and with a verdict of ✅ or ⚠️, run `review-ready.sh` and the checkout assertion as step 7 says, and add the Ready and Checkout lines to the file.
6. **Save, post, print:** step 7's last part, in its order.

An agent that returns nothing usable marks the PR `❌ review failed: <reason>`; nothing is retried silently. The review is posted to GitHub only through `review-post.sh`, as the setting or the user's request says.
