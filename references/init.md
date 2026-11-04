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

**Files to write:** `~/.engineer-of-wealth/executor/config.md`, Executor's settings (the search roots, E3, and the plans folder, E4), only on approval. Its other file, `~/.engineer-of-wealth/executor/assign.log`, is written by the hook when assigning a PR fails.

## E2: Enable Executor in this repository

Executor is disabled user-globally and turned on per build repository, because Claude Code settings do not inherit down the directory tree: the enable has to sit in the repository's committed `.claude/settings.json` (never `settings.local.json`, which is gitignored) so every worktree inherits it. Run this only when the current folder is a git repository; otherwise skip E2 with one line saying so.

Run `bash <plugin root>/scripts/init-plugin-enable.sh` once — the deterministic engine, no AI — and read its tagged lines (`TARGET:`, `STATE:`, `TRACK:`). It reads the **on-disk** `.claude/settings.json`, what Claude Code actually loads, not the version in git HEAD.

- `STATE: enabled` — the enable is already there; say so and do nothing. If `TRACK: untracked`, remind the user to commit `.claude/settings.json` so every worktree inherits it.
- `STATE: missing-file` or `STATE: missing-key` — offer to add it in these words, then ask:

  ```
  Executor is enabled per repository, not globally, so it stays out of your
  non-build trees and present in this one. The enable goes in this repo's
  committed .claude/settings.json ("executor@engineer-of-wealth": true under
  enabledPlugins); any other plugins and settings there are kept.

  Add it now?
  - YES — merge the enable into .claude/settings.json (uncommitted)
  - NO  — leave it; /executor:init offers it again
  ```

  On YES run `bash <plugin root>/scripts/init-plugin-enable.sh --apply`. On `STATE: wrote`, tell the user the file was written **uncommitted** and, since `TRACK: untracked` until they commit it, offer to commit it (YES / NO — ask first, and only commit `.claude/settings.json`). Never commit on your own. On NO, go on without writing.
- `STATE: invalid-json` — the file exists but does not parse; say so and stop E2 without touching it. The user fixes the JSON, then runs `/executor:init` again.
- `STOP: <reason>` — show the reason as it is; it already says what to do.

Running E2 again after the enable is in place reports `STATE: enabled` and writes nothing: the step is idempotent.

## E3: Search roots

Executor finds a PR's local checkout under these folders, up to two levels deep, and clones into the first one only when you say yes.

Read `~/.engineer-of-wealth/executor/config.md` (`EOW_HOME` overrides `~/.engineer-of-wealth`). Its roots are the `- ` lines of its `## Roots` section, in search order.

- **Roots set:** show them in order and ask **KEEP** (write nothing, go to E4) or **CHANGE** (ask as below, with these as the default).
- **No file, no `## Roots` section or an empty list:** ask, with `~/Projects` as the default.

```
SEARCH ROOTS — where Executor looks for a PR's local checkout
Executor finds it under these folders, up to two levels deep, and clones
into the first one only when you say yes.

Folders, in search order?   Default: ~/Projects
```

An empty answer takes the default. Say which folders don't exist yet; never create them (E5 flags them too). Then show the file with the user's roots, for example:

```markdown
# Executor settings

## Roots
- ~/Projects
- ~/code
```

and ask:

```
- YES — write it
- FIX — tell me what to change
```

On YES write it. Paths go in as given, `~` unexpanded. When the file exists, replace only the `## Roots` list and keep everything else. Under a central setup the file joins its one approval (S4) instead.

## E4: Plans folder

Where `/executor:build` keeps its plans, one folder per repository inside it. Nothing goes in the repository itself.

Read the same file. The plans folder is the first `- ` line of its `## Plans` section. With `$EXECUTOR_PLANS` set, say first: "`$EXECUTOR_PLANS` is set to <value> and wins over what is written here."

- **Folder set:** show it and ask **KEEP** (write nothing, go to E5) or **CHANGE** (ask as below, with it as the default).
- **No file, no `## Plans` section or an empty list:** ask, with `~/.engineer-of-wealth/executor/plans` as the default.

```
PLANS FOLDER - where Executor keeps its build plans

Folder?   Default: ~/.engineer-of-wealth/executor/plans
```

An empty answer takes the default. The answer is an absolute path or starts with `~`. Never create the folder: the first plan does. Then show the section, for example:

```markdown
## Plans
- ~/.engineer-of-wealth/executor/plans
```

and ask:

```
- YES - write it
- FIX - tell me what to change
```

On YES write it. The path goes in as given, `~` unexpanded. When the file exists, replace only the `## Plans` section and keep everything else; when it has no such section, add it at the end. Under a central setup the file joins its one approval (S4) instead.

Moving the plans folder moves nothing. When the answer differs from the folder in use, say so and print the command to run yourself: `mkdir -p "<new folder>" && mv "<old folder>"/* "<new folder>"/`, with both paths absolute. Never run it. Before the first plan there is nothing to move: when the old folder doesn't exist, skip this.

## E5: Check

Run `bash <plugin root>/scripts/self-audit.sh` once, exactly that command with the absolute path and no quotes. Reply with its summary line and every `✗` and `⚠` line as it is: each one already says what to do.

## Rules

- Ask before installing or configuring anything; the table in E1, the read-only detect in E2 and reading `config.md` in E3 and E4 are the only things that run without asking. The E2, E3 and E4 writes run only on YES.
- Never run `gh auth login` or any other interactive command: tell the user to run it.
- Never commit `.claude/settings.json`, or anything else, without asking; never touch `settings.local.json`.
- Write nothing outside `~/.engineer-of-wealth/` except, in the current repository and only on YES, the two git settings in E1 and the `.claude/settings.json` enable in E2.
