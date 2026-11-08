# Stacked pull requests

Executor ships dependent features as a GitHub stack, through the `gh stack` extension: one branch per feature, each PR based on the branch below it, so every PR shows only its own feature. You merge them bottom-up.

## Setup, once per machine and repo

```bash
gh extension install github/gh-stack
git config rerere.enabled true
git config remote.pushDefault origin
```

The repository needs stacked PRs enabled on GitHub. Without it, `gh stack submit` exits with code 9: then open plain PRs instead, each with `gh pr create --base <the branch below>`, the same chain without the stack object.

## How a spec maps to stacks

- **A stack is a line, never a tree.** Each branch has one parent and at most one child, and a branch can't sit in two stacks.
- **The foundation goes first, alone.** Schema, auth and the skeleton are one PR on the default branch, and it is merged before any feature stack starts, so every stack can root on the default branch.
- **One dependency chain, one stack.** Features that build on each other stack in dependency order, lowest first. Features that depend on nothing but the foundation each get a stack of their own. Those are the ones built in parallel.

## Commands

Every `gh stack` command runs non-interactively. Without these flags and arguments it opens a prompt and hangs:

| Task | Command |
|---|---|
| Start a stack with its first feature | `gh stack init <branch>` |
| Next feature on top | `gh stack top`, then `gh stack add <branch>` |
| Push every branch, open draft PRs for new ones | `gh stack submit --auto` |
| Read the stack | `gh stack view --json` (never without `--json`) |
| Go to a branch | `gh stack checkout <branch>` (never without an argument) |
| Fix a lower branch without leaving your checkout | `git worktree add "$TMPDIR/executor-fix-<n>" <branch>`, commit there, run the next row from it, then `git worktree remove` it; when the checkout is already on that branch and clean, fix in place there (dirty: leave the findings open) |
| After changing a lower branch | `gh stack rebase --upstack`, then `gh stack push` |
| After a lower PR was merged | `gh stack sync --prune`, then `bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo-tidy.sh <repo>` detached |
| A rebase conflict (exit 3) | resolve, `git add`, `gh stack rebase --continue`; or `gh stack rebase --abort` |

Commit with plain `git add <paths>` and `git commit`, never `-A`: each branch takes only its own feature's files.

## Keeping a stack healthy

The stack stays rooted in live branches, never in merged ones. The ship and review flows rely on this.

- **Use `gh stack` whenever it's available.** It keeps the chain's bases consistent; the manual `gh pr create --base <the branch below>` fallback is only for a repo without stacked PRs (exit 9).
- **After any PR in the stack merges, run `gh stack sync --prune`.** It restacks every branch above the merged one onto the live base, up to the default branch, and drops the merged branch (see the Commands table).
- **Then tidy the repo, detached.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo-tidy.sh <repo>` in the background (`run_in_background`) and carry on; it returns the checkout to the default branch and removes what the merge finished, and the session never waits on it.
- **Then see whether a plan just finished.** For each plan `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh --live` prints, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-state.sh --mark "<plan>"`. On `DONE`, the plan is now marked done; say so in one line.
- **Never leave a branch based on a merged branch.** A branch whose base merged is restacked with `gh stack sync --prune` before any more work lands on it.
- **Never merge in a way that bypasses the restack.** No manual merge that strands the branches above it; let the sync move them onto the live base.

## Titles and bodies

`submit --auto` writes titles and bodies from the commits. Right after it, give every new PR its real ones: `gh pr edit <n> --title "<feature name>" --body-file <file>`, with the body from `references/feature-done.md`.

## Draft until reviewed

New PRs open as drafts. A draft means Executor is still reviewing it. When the review's verdict is ✅ or ⚠️, the review marks your PR ready: now it's yours to merge. Stacked PRs are merged on github.com, not from the CLI.
