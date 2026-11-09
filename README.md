# Executor

The engineer on your team, for Claude Code. Give it a spec and get back a stack of reviewed pull requests. You approve twice: the plan, and the merge.

Free and open source (MIT).

| Skill | What you get |
|---|---|
| `/executor:spec` | A spec drafted from your notes and the repo, saved where your specs live |
| `/executor:build` | A spec planned with you, built in parallel: one reviewed draft PR per feature, in stacks |
| `/executor:review` | A PR or branch built, reviewed and its bugs fixed, even another repo's |
| `/executor:ship` | The current branch committed, pushed and opened as a draft PR |
| `/executor:status` | What to merge now, across every repo |
| `/executor:init` | Setup |
| `/executor:help` | What Executor does, and the right skill for what you type |

## Install

In Claude Code:

```
/plugin marketplace add sebwilgosz/agent-plugins
/plugin install executor@engineer-of-wealth
```

Then type `/executor:init`. It checks the GitHub CLI, its sign-in and the [gh-stack](https://github.com/github/gh-stack) extension, offering to install it. In a build repository it offers to enable Executor in the committed `.claude/settings.json`, merged in without touching your other settings, so every worktree inherits it. It asks for your [search roots](#search-roots), [plans folder](#where-plans-live) and [spec home](#where-specs-live), then ends with a setup check, `scripts/self-audit.sh`, rerunnable any time.

## Spec and build

Type `/executor:spec` with your notes for a spec, then type `/executor:build` with it (a path, URL, issue or the text), or ask in plain words ("build docs/rfc-12.md"). A thin spec gets questions, each with a suggested answer, before anything is built.

1. **Plan.** Executor splits the spec into features and stacks and writes a checklist, one item per feature, linked to the spec. You approve it.
2. **Foundation.** Shared groundwork (schema, auth, skeleton) is built alone first. Merge its PR and run `/executor:build` again.
3. **Build.** One `executor:builder` agent per stack, on Sonnet, in parallel, each in its own worktree with only its feature's requirements. It first writes tests from the spec (manual scenarios where a test can't be automated) so the code can't drift, then builds in the repo's patterns, a commit per step.
4. **Open.** Once the spec tests and the build pass, the feature becomes a draft PR in a GitHub stack, on top of the one it depends on: a few bullets, a diagram when the change has a shape, and a Testing section. A needed refactor gets its own PR below.
5. **Review.** Every PR is [reviewed](#review). A ✅ or ⚠️ marks it ready and starts the next feature of its stack. A builder stuck on a question stops only its stack.
6. **Report.** The checklist, the open questions, and what to merge, bottom of each stack first. Run `/executor:build` again to carry on.

### Tickets

When the spec home names a tracker (`Tickets: GitHub`, `Jira project TRAV`, `Linear`), build offers, after you approve the plan, one ticket per plan item: a sub-issue of the spec's parent issue on GitHub, or via your Linear or Jira connector. It holds the builder's brief and a spec link; the PR closes it (`Closes #n`, or the key). A rerun never duplicates one; an unreachable tracker never stops the build.

## Review

Type `/executor:review` with a PR number or URL, a branch, or nothing for the current branch. It also starts on its own when Claude opens a PR or you ask for one. An `executor:reviewer` agent (Opus) does the build and the review and writes the draft to a file, so a long review never fills your session; an `executor:fixer` agent (Sonnet) does the fixing. Five steps:

1. **Build.** Install, build, lint and tests, with your repo's commands, must pass. A PR is built in a throwaway worktree, never in yours.
2. **Review** the diff for duplication, correctness against your spec, test coverage, security, best practices (including needless inline comments) and your repo's conventions (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, linter configs, the code around). A doc the diff makes false, like a removed flag, is Critical and gets corrected.
3. **Verify.** Each Critical finding goes to its own `executor:verifier` agent, on Sonnet, which tries to disprove it. Debunked ones are dropped.
4. **Fix**, on your own PRs. A confirmed Critical finding is a bug: Executor writes the failing test, fixes it, commits and reviews again, at most three rounds, without new agents. It never edits a test to make it pass, never force-pushes and never touches a PR from a fork. On a teammate's PR or someone else's branch it only reports. `--fix` and `--no-fix` override that; a fork stays report-only.
5. **Report**, always in the same shape: verdict, build, CI, spec, mode and bugs fixed, then what is still Critical and the Suggestions. Each finding links to the line, says when it fails and how to fix it.

Suggestions are listed as drafted, never verified or fixed. Nothing is posted to GitHub unless you ask.

On ✅ or ⚠️ your own draft PR, one opened by hand too, is marked ready. A review by branch does so only when it saw exactly the PR's head commit, nothing uncommitted. A teammate's draft stays a draft, as does yours under `--no-fix`.

Every PR Claude opens is assigned to you, a stacked one once its head branch matches what `gh stack` reported.

### Review from any folder

In any session, name another repository's PR as `owner/repo#N` or by URL: "let's review acme/api#7". A bare number or a branch name always means the current repository. A review runs in the repository's own checkout. If the current folder's `origin` is that repository, it reviews here. Otherwise:

1. **Find the checkout** under your [search roots](#search-roots), two levels deep. A bare repository with its worktrees (`~/Projects/api/main`) counts as one.
2. **Update it.** It fetches `origin` and fast-forwards the default branch only where checked out clean. Uncommitted work, local commits and the branch someone is on are left alone; the review works from `origin/<default>`.
3. **Hand off.** It proposes a new session there running the review, or prints the command:

   ```
   cd "/home/you/Projects/api" && claude "/executor:review https://github.com/acme/api/pull/7"
   ```

4. **No checkout.** It asks before cloning into the first root (`gh repo clone acme/api ~/Projects/api`). On no, nothing is cloned.

## Status

Type `/executor:status`, or ask "where are my builds". It reads every live plan and its PRs:

```
EXECUTOR STATUS

acme/api
  2026-11-07 - billing export
    MERGE NOW
      #31  CSV export                 Stack A 1/2   CI green   review ready
    WAITING ON YOU
      #32  Invoice emails             Stack B 1/1   CI red     review ready
    MOVING
      Stack A: 1 not started
```

The bare command needs no model turn; text after it ("what blocks acme/api?") is answered from the same output. It only reads: it never marks a plan, pushes or posts.

- A finished, unmarked plan ends with `finished, not marked: run scripts/plan-sweep.sh`.
- Executor's own leftover worktrees and branches from finished builds show as a `DRIFT` line with the clearing command, `scripts/repo-tidy.sh <repo>`. Your own branches and a finished-branch checkout are not drift. `scripts/self-audit.sh -v` reports the same for the current repo.

## Settings

### Search roots

Where Executor looks for checkouts, in order, in `~/.engineer-of-wealth/executor/config.md`. Default `~/Projects`; the setup check warns about a missing root:

```markdown
## Roots
- ~/Projects
- ~/code
```

### Where plans live

Plans never go in your repository. Each is a dated file in one folder per repository, shared by its worktrees:

```
~/.engineer-of-wealth/executor/plans/<org>/<repo>/<YYYY-MM-DD> - <title>.md
```

`<org>/<repo>` comes from the `origin` URL, or is `local/<name>` without one. A plan is live until its header says `Status: done <date>`, added once every item's PR is merged or closed. `scripts/plan-sweep.sh` does that for every repository at once; `--dry-run` only shows. Finished plans stay put; there is no archive step.

To move plans, init writes a `## Plans` section in `config.md`; the `EXECUTOR_PLANS` environment variable wins over it. Moving it moves nothing: init prints the `mv` to run. `/executor:help` shows the folder, its source and live plans. For a notes app, link the folder: `ln -s ~/.engineer-of-wealth/executor/plans ~/Notes/plans`.

Older plans in a repository's legacy `.executor/` folder move on its first build. `scripts/plans-migrate.sh` moves every one under `~/Projects`, or the folder you name (`--dry-run` only shows). It never overwrites: a clash is reported and that file stays.

### Where specs live

A spec may be a Notion RFC, a vault note or a GitHub issue. Executor never decides where; it reads a short section from the nearest `AGENTS.md` or `CLAUDE.md`, from your working folder upwards, then the target repo's own:

```markdown
## Specs
Specs: Notion, the "RFCs" database. Tickets: Jira project TRAV.
```

Others: `Specs: GitHub, a parent issue in this repo` and `Specs: docs/specs/ in this repo`, the only case where a spec is committed. `scripts/self-audit.sh -v` names the file in use.

Where nothing names a home, init asks once and writes the section only on a yes, uncommitted. Declined, specs stay in `~/.engineer-of-wealth/executor/specs/<org>/<repo>/`.

## Faster worktrees and commit checks

Optional, per repo; the clones need macOS with APFS:

```
bash <plugin root>/scripts/git-hooks.sh install <repo>
```

- **New worktree:** `node_modules` and `.next/cache` are cloned from the main checkout, for each package up to two folders down, at almost no disk cost; bare repos work too. If it has none, install there once.
- **After a commit:** the type check and lint of each touched package run, up to 60 seconds each. Errors print; the commit stands. Markdown- or image-only commits run nothing.
- **Is it on:** `git-hooks.sh status <repo>` prints `HOOKS: installed` only when the post-commit hook is in place, not bypassed by `core.hooksPath`, and a package has a lint or type check to run; otherwise `HOOKS: off`. It changes nothing.
- **Off again:** `git-hooks.sh uninstall <repo>` removes only what `install` wrote. Another tool's hook is never overwritten, and a repo with `core.hooksPath` set is left alone.

## Requirements

- [GitHub CLI](https://cli.github.com) (`gh`), signed in
- For stacked PRs: the [gh-stack](https://github.com/github/gh-stack) extension (`gh extension install github/gh-stack`) and stacked PRs enabled on the repository. Without them, plain PRs chained by base branch.
- `jq` is used when present; the hook works without it
