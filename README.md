# Executor

The engineer on your team who reviews every pull request, builds it, fixes the bugs it finds and reviews again, for Claude Code. You approve twice: the plan, and the merge. Executor does the rest.

Free and open source (MIT).

## Install

In Claude Code:

```
/plugin marketplace add sebwilgosz/agent-plugins
/plugin install executor@engineer-of-wealth
```

Then type `/executor:init`. It checks the GitHub CLI and its sign-in, and the [gh-stack](https://github.com/github/gh-stack) extension: Executor works best with it, and init offers to install it. In a build repository it also offers to enable Executor there — Claude Code settings don't inherit down the tree, so the enable goes in the repo's committed `.claude/settings.json`, merged in without touching your other settings, so every worktree inherits it. It asks where your local checkouts live (see [Review from any folder](#review-from-any-folder)) and where your build plans live (see [Where plans live](#where-plans-live)). It ends with a setup check, `scripts/self-audit.sh` in the plugin, which you can run again any time something looks off.

## What it does today: review

Type `/executor:review` with a PR number, a PR URL, a branch, or nothing for the current branch. It also starts on its own:

- whenever Claude creates a pull request in your session (a hook watches for `gh pr create`, `gh stack submit` and `gh stack link`), and
- whenever you ask Claude for a code review or name a pull request.

A review runs in five steps:

1. **Build.** Install, build, lint and tests, with the commands your repo already defines. The build must pass. A PR is built in a throwaway worktree, never over your working tree.
2. **Review** the diff in six dimensions: duplication, correctness against your spec, test coverage, security, best practices (including inline comments that can go or be shorter) and your repo's conventions (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, linter configs, the code around the change, and for a PR its description). It also checks your docs against the diff (`scripts/docs-mentions.sh`, no AI): a doc that now states something false, like a removed flag still documented, is Critical and gets corrected.
3. **Verify.** Every finding goes to its own `executor:verifier` agent, which tries to disprove it. Each comes back confirmed, debunked or reclassified. Debunked findings are dropped from the report.
4. **Fix**, on your own PRs. Every confirmed Critical finding is a bug: Executor writes the failing test, fixes it, commits it on the PR's branch and reviews again, at most three rounds and without new agents. It never edits a test to make it pass, never force-pushes and never touches a PR from a fork. On a teammate's PR or someone else's branch it only reports: nothing is committed or pushed. `--fix` and `--no-fix` override that, and a fork stays report-only either way.
5. **Report**, always in the same shape: verdict, build, CI, spec, which mode ran and how many bugs were fixed, then what is still Critical and the Suggestions. Each finding links to the file and line and says when it fails and how to fix it.

On ✅ or ⚠️ it marks your own draft PR ready (`scripts/review-ready.sh`), a draft you opened by hand too. A teammate's draft stays a draft, and so does yours under `--no-fix`.

Suggestions are listed, never fixed for you. Nothing is posted to GitHub unless you ask.

### Review from any folder

Name a pull request of another repository as `owner/repo#N` or by its URL, in any session: "let's review acme/api#7", or `/executor:review https://github.com/acme/api/pull/7`. A review always runs in the repository's own checkout, so Executor finds that first (`scripts/find-checkout.sh`, no AI):

1. **Already there.** When the current folder's `origin` is the PR's repository, it reviews here, as above.
2. **Find the checkout** under your search roots, two levels deep, so a bare repository with its worktrees (`~/Projects/api/main`) is found, as one checkout.
3. **Update it.** It fetches `origin`, then fast-forwards the default branch only where it is checked out clean. Uncommitted work, local commits and the branch someone is on are left alone; the review then works from `origin/<default>` and its summary says so.
4. **Hand off.** It proposes a new session in that checkout running `/executor:review <url>`. Where your client can't start one, it prints the one command to run:

   ```
   cd "/home/you/Projects/api" && claude "/executor:review https://github.com/acme/api/pull/7"
   ```

5. **No checkout.** It lists where it looked and asks before cloning into the first root (`gh repo clone acme/api ~/Projects/api`). On no, nothing is cloned.

The search roots are a setting in `~/.engineer-of-wealth/executor/config.md`, searched in order. `/executor:init` asks for them, `~/Projects` by default, and the setup check warns about a root that doesn't exist:

```markdown
## Roots
- ~/Projects
- ~/code
```

A bare PR number or a branch name always means the current repository.

Every PR Claude opens is also assigned to you, its author. That one is plain shell, not AI: a second hook runs `gh pr edit --add-assignee @me` in the background, so your session never waits on GitHub. If it fails, the reason is in `~/.engineer-of-wealth/executor/assign.log`.

| Skill | What it does |
|---|---|
| `/executor:help` | What Executor does; routes what you type to the right skill |
| `/executor:build` | Plan a spec with you, build it in parallel, review every PR |
| `/executor:review` | Review, verify, fix and re-review a PR or a branch; another repo's PR opens in its checkout |
| `/executor:ship` | Commit the current branch, push it and open a draft PR; the review starts on its own |
| `/executor:status` | Across every repo, what to merge now, what waits on you, what is still moving. You type it |
| `/executor:init` | Setup: gh, its sign-in, gh stack (offers to install it), the per-repo enable, the search roots and the plans folder. You type it |

## Build from a spec

Type `/executor:build` with a spec (a path, a URL, an issue, or the text itself), or ask in plain words ("build docs/rfc-12.md"). You write the spec; a thin one gets questions, each with a suggested answer, before anything is built.

1. **Plan.** Executor splits the spec into features and stacks and writes the plan as a checklist: one item per feature, linked to its part of the spec. The file stays on your machine, outside the repository (see [Where plans live](#where-plans-live)). You approve it before anything is built.
2. **Foundation.** Shared groundwork (schema, auth, skeleton) is built alone first. Executor stops after its PR; merge it and run `/executor:build` again.
3. **Build.** One `executor:builder` agent per stack, all in parallel, each in its own worktree. A builder gets only its own feature's requirements. It starts by writing high-level tests from the spec (or manual scenarios where a test can't be automated) so the code can't drift from it, builds in the repo's own patterns with a commit per finished step, and opens a draft PR.
4. **Review.** Every PR is reviewed as above. A ✅ or ⚠️ marks it ready and starts the next feature of its stack. A builder that stops on a question stops only its own stack.
5. **Report.** The checklist as it stands, the open questions in one message, and what is yours to merge, bottom of each stack first. Run `/executor:build` again to carry on.

A feature always ends in an open pull request: once its spec tests and the whole build pass, Executor opens it as a draft in a GitHub stack, on top of the feature it depends on, and the review starts on its own. The PR is short and readable: what changes in a few bullets, a diagram when the change has a shape, and a Testing section with the spec tests. A ✅ or ⚠️ review marks it ready: then it's yours to merge, bottom of the stack first. A refactor the feature needs gets its own PR below it. The rules are in `references/implementation.md`, `references/feature-done.md`, `references/pull-request.md` and `references/stacks.md`.

## Where your builds are

Type `/executor:status`, or ask "where are my builds" or "what's in flight". It reads every live plan and each PR's state on GitHub (`scripts/status.sh`, no AI) and prints what is yours to merge now, what waits on you and what is still moving, across every repo:

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

The bare command prints this with no model turn. Text after it ("what blocks acme/api?") gets an answer from the same output. It only reads: it never marks a plan, pushes or posts. A plan whose items are all merged or closed but which isn't marked yet ends with `finished, not marked: run scripts/plan-sweep.sh`. Finished plans stay in their folder: there is no archive step.

## Where plans live

Plans never go in your repository. Each is one dated file in a folder of its own for that repository, shared by all its worktrees:

```
~/.engineer-of-wealth/executor/plans/<org>/<repo>/<YYYY-MM-DD> - <title>.md
```

`<org>/<repo>` comes from the `origin` URL, or is `local/<name>` without one. A plan stays live until its header says `Status: done <date>`, and two live plans in one repository never share a file. Executor adds that line itself once every item's PR is merged or closed, when a build runs in the repository or a stack syncs after a merge; `scripts/plan-sweep.sh` does it for every repository at once, and `--dry-run` only shows what it would mark.

Plans from an older version sit in a legacy `.executor/` folder in the repository. `scripts/plans-migrate.sh` moves every legacy `.executor/` under `~/Projects`, or the folder you name, to this layout, and `--dry-run` only shows what it would move. It never overwrites: a clash is reported and that file stays. A folder inside a repository means that repository alone, and a build moves its own repository's on its first run.

To put them elsewhere, run `/executor:init`, which writes a `## Plans` section in `~/.engineer-of-wealth/executor/config.md`. The `EXECUTOR_PLANS` environment variable wins over it. Moving the folder moves nothing: init prints the `mv` to run. `/executor:help` shows the folder in use, where the setting comes from and this repository's live plans.

To keep plans in a notes app, link the folder in: `ln -s ~/.engineer-of-wealth/executor/plans ~/Notes/plans`.

## Requirements

- [GitHub CLI](https://cli.github.com) (`gh`), signed in, for pull requests
- For stacked PRs: the [gh-stack](https://github.com/github/gh-stack) extension (`gh extension install github/gh-stack`) and stacked PRs enabled on the repository; without them Executor opens plain PRs chained by base branch
- `jq` is used when present; the hook works without it
