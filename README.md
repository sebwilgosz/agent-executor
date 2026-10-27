# Executor

The engineer on your team who reviews every pull request, builds it, fixes the bugs it finds and reviews again, for Claude Code. You approve twice: the plan, and the merge. Executor does the rest.

Free and open source (MIT).

## Install

In Claude Code:

```
/plugin marketplace add sebwilgosz/agent-plugins
/plugin install executor@engineer-of-wealth
```

Then type `/executor:init`. It checks the GitHub CLI and its sign-in, and the [gh-stack](https://github.com/github/gh-stack) extension: Executor works best with it, and init offers to install it. It ends with `/executor:self-audit`, which you can run again any time something looks off.

## What it does today: review

Type `/executor:review` with a PR number, a PR URL, a branch, or nothing for the current branch. It also starts on its own:

- whenever Claude creates a pull request in your session (a hook watches for `gh pr create`, `gh stack submit` and `gh stack link`), and
- whenever you ask Claude for a code review or name a pull request.

A review runs in five steps:

1. **Build.** Install, build, lint and tests, with the commands your repo already defines. The build must pass. A PR is built in a throwaway worktree, never over your working tree.
2. **Review** the diff in six dimensions: duplication, correctness against your spec, test coverage, security, best practices and your repo's conventions (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, linter configs, the code around the change).
3. **Verify.** Every finding goes to its own `executor:verifier` agent, which tries to disprove it. Each comes back confirmed, debunked or reclassified. What can't be shown in the code is dropped.
4. **Fix.** Every confirmed Critical finding is a bug: Executor writes the failing test, fixes it, commits it on the PR's branch and reviews again, at most three rounds and without new agents. It never edits a test to make it pass, never force-pushes and never touches a PR from a fork.
5. **Report**, always in the same shape: verdict, build, spec, Critical, Fixed, Suggestions, what was dismissed and why, and a table of the six dimensions plus the build. Every finding links to the file and line.

Suggestions are listed, never fixed for you. Nothing is posted to GitHub unless you ask.

Every PR Claude opens is also assigned to you, its author. That one is plain shell, not AI: a second hook runs `gh pr edit --add-assignee @me` in the background, so your session never waits on GitHub. If it fails, the reason is in `~/.engineer-of-wealth/executor/assign.log`.

| Skill | What it does |
|---|---|
| `/executor:menu` | The menu; routes what you type to the right skill |
| `/executor:review` | Review, verify, fix and re-review a PR or a branch |
| `/executor:init` | Setup: gh, its sign-in, gh stack (offers to install it). You type it |
| `/executor:self-audit` | Is everything in place, and is the plugin whole. You type it |

## Coming next

Build from a spec: hand Executor a spec with tests and it plans the features, builds them in parallel worktrees, reviews each one as above and hands you a stack of small PRs. You merge.

A feature always ends in an open pull request: once its spec tests and the whole build pass, Executor opens it as a draft in a GitHub stack, on top of the feature it depends on, and the review starts on its own. A ✅ or ⚠️ review marks it ready: then it's yours to merge, bottom of the stack first. The rules are in `references/feature-done.md` and `references/stacks.md`.

## Requirements

- [GitHub CLI](https://cli.github.com) (`gh`), signed in, for pull requests
- For stacked PRs: the [gh-stack](https://github.com/github/gh-stack) extension (`gh extension install github/gh-stack`) and stacked PRs enabled on the repository; without them Executor opens plain PRs chained by base branch
- `jq` is used when present; the hook works without it
