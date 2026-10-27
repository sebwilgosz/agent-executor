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
| After changing a lower branch | `gh stack rebase --upstack`, then `gh stack push` |
| After a lower PR was merged | `gh stack sync --prune` |
| A rebase conflict (exit 3) | resolve, `git add`, `gh stack rebase --continue`; or `gh stack rebase --abort` |

Commit with plain `git add <paths>` and `git commit`, never `-A`: each branch takes only its own feature's files.

## Titles and bodies

`submit --auto` writes titles and bodies from the commits. Right after it, give every new PR its real ones: `gh pr edit <n> --title "<feature name>" --body-file <file>`, with the body from `references/feature-done.md`.

## Draft until reviewed

New PRs open as drafts. A draft means Executor is still reviewing it. When the review's verdict is ✅ or ⚠️, mark it ready, `gh pr ready <n>`: now it's yours to merge. Stacked PRs are merged on github.com, not from the CLI.
