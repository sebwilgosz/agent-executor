# Executor init: Executor's own setup steps

The steps only Executor needs. They run after the shared part (`references/shared-setup.md` S1–S3), whether `/executor:init` runs them or a central setup that loops over every installed Engineer of Wealth plugin. They never repeat the shared questions. Paths here are relative to this plugin's root.

Executor itself reads nothing from `shared.md`: it reads your repository. The shared part is there for the other Engineer of Wealth plugins, so when `shared.md` is missing, `/executor:init` offers it with **skip** as the default.

## E1: Tools

Executor works through the GitHub CLI. Check, in one go and without asking (all read-only):

| Check | Command | Missing means |
|---|---|---|
| gh installed | `command -v gh` | no pull requests at all: point to https://cli.github.com and stop E1 here |
| gh signed in | `gh auth status` | no pull requests: tell the user to run `gh auth login` themselves (it is interactive) |
| gh stack installed | `gh extension list` lists `github/gh-stack` | Executor opens plain PRs chained by base branch instead of a stack |
| jq | `command -v jq` | nothing: the hooks work without it, a little slower to read |

Show the result as a short table, found or missing per line.

**gh stack missing:** say it in these words, then ask:

```
Executor works best with gh stack. Every feature becomes its own small PR,
stacked on the feature it depends on, so each PR shows only its own change
and you merge them bottom-up. Without it Executor still works: it opens plain
PRs, each based on the branch below it.

Install it now?  gh extension install github/gh-stack
- YES — install it
- NO  — keep plain PRs; /executor:init offers it again
```

On YES run exactly `gh extension install github/gh-stack`, then `gh stack --version` to show it worked. On NO go on.

**gh stack installed (now or before):** add two notes, without running anything:

- Stacked PRs must be enabled on each GitHub repository. Where they are not, `gh stack submit` fails and Executor falls back to plain PRs on its own.
- In each repository Executor builds in, two settings keep `gh stack` from stopping at a prompt: `git config rerere.enabled true` and `git config remote.pushDefault origin`. If the current folder is a git repository and either is unset, offer to set them here (YES / NO); never set them globally.

**Files to write:** none. Executor has no settings yet. Its only file, `~/.engineer-of-wealth/executor/assign.log`, is written by the hook when assigning a PR fails.

## E2: Check

Run `bash <plugin root>/scripts/self-audit.sh` once, exactly that command with the absolute path and no quotes. Reply with its summary line and every `✗` and `⚠` line as it is: each one already says what to do.

## Rules

- Ask before installing or configuring anything; the table in E1 is the only thing that runs without asking.
- Never run `gh auth login` or any other interactive command: tell the user to run it.
- Write nothing outside `~/.engineer-of-wealth/` except the two git settings in the current repository, and only on YES.
