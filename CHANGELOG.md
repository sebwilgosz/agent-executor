# Changelog

## Unreleased

- `/executor:init` offers GitHub's "Automatically delete head branches" for the build repository (step E2b). It reads the setting and, only on a yes, turns it on, so a merged PR no longer leaves its branch behind. It changes a GitHub setting, so it always asks, and a check that fails (no network, no permission) is one line and init carries on. The engine is `scripts/init-delete-branches.sh`.

## 0.9.0 — 2026-11-08

- `/executor:review` verifies only Critical findings. Each Critical finding still goes to its own `executor:verifier`, which confirms, debunks or reclassifies it; Suggestions get no verifier, since the review only lists them and never fixes them. A Critical brought down to a Suggestion is listed among the Suggestions with the verifier's wording. A finding whose severity the review can't settle is drafted as Critical, so a verifier judges it and a real bug can't escape by being drafted as a Suggestion. A verifier run costs about 34k weighted tokens, and a six-PR build that drafts 2 Critical and 6 Suggestions per PR drops from 48 verifiers to 12, saving about 1.2M weighted tokens.

## 0.8.0 — 2026-11-07

- `scripts/git-hooks.sh install` adds two opt-in git hooks to a repo, bare or not. A new worktree gets copy-on-write clones of `node_modules` and `.next/cache` from the main checkout, so it starts with no install. Next.js may still recompile in the new folder, because its build cache is tied to the folder's path. After a commit, the type check and lint of each package it touched run on their own, and any errors print in the commit's output. The commit always stands, and no model is involved.
- Builders no longer have to run a full build for each commit. It runs once, before the PR opens.

## 0.7.0 — 2026-11-07

- Spec from sources. `/executor:spec` drafts a spec for what you name from every relevant source (what you pass, your instruction files and the notes they name, the spec home, then the repo: README, `docs/`, `CHANGELOG.md`, `git log`, issues, PRs, an earlier plan) in the shape of `references/spec.md`. Every fact names its source, what it inferred becomes an open question asked in one message with suggested answers, and nothing is saved before a yes. `/executor:build` offers it when it finds no spec.
- The spec home: where a spec is read from and written to. A short `## Specs` section in the nearest `AGENTS.md` or `CLAUDE.md` (the working folder upwards, then the target repo's own) names it: a folder, the repo, Notion, GitHub issues, Linear or Jira, with the ticket tracker if there is one. `scripts/spec-home.sh` finds it, flags files or words that disagree instead of guessing, writes the section on a yes into `AGENTS.md` and `CLAUDE.md` as they exist, and prepares the local fallback, `~/.engineer-of-wealth/executor/specs/<org>/<repo>/`. `references/spec-home.md` is the rule every skill follows.
- `/executor:init` gains a step, E5, that shows the home for the folder or asks where specs live; the setup check is now E6. `scripts/self-audit.sh` checks the resolver, the ticket script and the two spec references, and with `-v` prints the file that names the home.
- Build and review read the spec from its home. Build looks after what you gave it, review after the PR's own links and the issues it closes, both before `SPEC.md`, `specs/` and `docs/specs/`. With several specs in the home, the one you named, the branch or the PR title wins; none or several matching: it asks. A spec is never written back.
- Tickets from the plan. When the spec home names a tracker, build offers once per run, after you approve the plan, one ticket per plan item: a sub-issue of the spec's parent issue on GitHub (`scripts/ticket-github.sh`), or an issue or ticket through your Linear or Jira connector. The ticket holds the builder's brief and a link to the spec, the PR closes it, and the plan records it so a rerun never creates one twice. An unreachable tracker never stops the build.

## 0.6.4 — 2026-11-07

- Each role now names its model. The `executor:builder` agent runs on Sonnet, `/executor:review` on Opus, including its fixes and re-review, and the `executor:verifier` agent on Sonnet. Before, all three followed the session's model, so a session on Opus built everything on Opus, and a session on Sonnet reviewed on Sonnet. Planning still runs on the session's model. A review started in a session on another model switches to Opus for that turn, which reads the conversation again instead of from its cache.

## 0.6.3 — 2026-11-07

- The stack hooks read the URL `gh stack` prints for each new PR, instead of working it out from the command's `cd` and the repo's remote. That URL names the right repo from any folder and needs no local lookup, so about 300 lines of command parsing are gone, along with the hooks' `git` and `ssh -G` calls. A line with no URL means the repo is unknown: nothing is assigned, one line goes in `assign.log`, and the review is told to find the repo.
- Fixes two bugs from 0.6.2. A command holding a carriage return, form feed or vertical tab hung both hooks until their 5 second limit, and that PR got no assignment or review. And `gh stack` run inside `$(...)` or `eval` was skipped with no log line. `$(...)` and `eval` count again, and backticks and `gh` called by its path, like `/opt/homebrew/bin/gh`, now count too.
- `scripts/remote-url.sh` is gone, its parsing back in `scripts/plan-path.sh`, which is the only script that still needs it.

## 0.6.2 — 2026-11-07

- After `gh stack submit` or `gh stack link`, the hooks act on the PR's own repo. Before, they resolved a bare PR number from the session's folder, so from another folder `gh` failed, or the wrong PR of that number got assigned and reviewed. They now read the folder from the command's `cd` and the repo from its remote, whichever folder the session is in.
- A stack PR is assigned only once its head branch matches the branch `gh stack` reported. A mismatch, a failed lookup or an unknown repo assigns nothing and logs one line in `assign.log`. The review is given each URL with its branch and told to compare them, or told the repo is unknown and to find it first.
- The hooks cost a session less. An event that only mentions `gh stack submit` exits before `jq` or `grep`, about 150 ms down to 40 ms per hook, and a large event is matched by bytes, 5 MB from about 2500 ms down to 630 ms. `ssh -G` runs only for an SSH host that isn't literally `github.com`, since it can run a `Match exec` from your ssh config.
- The review hook's output stays valid JSON for any branch name, with or without `jq`.
- The self-audit checks `scripts/remote-url.sh` is present.

## 0.6.1 — 2026-11-07

- `/executor:review` marks your own draft PR ready on ✅ or ⚠️. Before, only `/executor:build` did, so a PR from `/executor:ship` or a plain `gh pr create` stayed a draft after a passing review until you flipped it by hand. It now applies to every review of your own PR, a draft you opened by hand included. A review by branch does so only when it saw exactly what the PR holds: its head commit, nothing uncommitted. A teammate's draft stays a draft, even under `--fix`, and `--no-fix` leaves yours alone. `scripts/review-ready.sh` does it, no AI, and the summary says when a PR was marked or could not be.
- The self-audit checks `scripts/review-ready.sh` is present.

## 0.6.0 — 2026-11-07

- `/executor:status`: where your builds are, across every repo. It prints what is yours to merge now, what waits on you and what is still moving, from every live plan and each PR's state on GitHub, whose state wins over a stale plan line. It is read-only: it never marks a plan, pushes or posts. A bare `/executor:status` runs through the plugin's hook with no model turn, and falls through to the skill on a failure, blank output or after 15 s. `/executor:help` lists it and routes "where are my builds" and "what's in flight" to it.
- `scripts/status.sh` does the work, no AI, with at most 8 lookups at once. When a lookup fails, that item goes to UNKNOWN with why and the rest of the plan prints; when `gh` is missing or a whole repo can't be read, the repo gets one `UNKNOWN` line with its plans named and the other repos carry on. Failures go to `status.log`.
- `/executor:review` checks the docs against the diff, inside its repo-conventions dimension. `scripts/docs-mentions.sh`, no AI, finds flags, `UPPER_SNAKE` names and deleted or renamed paths the diff removed, and where the docs still mention them, along with any names the review passes it. Never `CHANGELOG*`: history may name old things. Docs that now state something false are Critical, so fix mode corrects them; behaviour changed without touching the docs that describe it is a Suggestion. Findings use the new category `Docs`. If the check can't run, the summary says so in one line and the review goes on.
- The review's dimensions name more of what they look for: integer overflow under correctness; cross-site scripting, CSRF and SSRF under security; and under best practices the performance traps: N+1 and other queries in a loop, unbounded queries or loops, O(n²) over user-sized data, a new query with no index. A trap is Critical only when its cost is real on a path the diff touches, otherwise a Suggestion. It is still six dimensions, and a performance finding is still `Best practice`.
- `scripts/plan-items.sh`: the one reader of a plan's items, shared by `plan-state.sh` and `status.sh`.
- The self-audit checks `scripts/docs-mentions.sh`, `scripts/plan-items.sh` and `scripts/status.sh` are present, and that `/executor:status` runs only when you type it.

## 0.5.0 — 2026-11-07

- **Existing users: run `scripts/plans-migrate.sh` once**, from the plugin's folder, with `--dry-run` first to see what it would do. Plans no longer live in the repository, so it moves every `.executor/` under `~/Projects`, or the folder you name, to the plans folder. It never overwrites: a clash is reported and that file stays. It removes the `.executor/` line from the repo's `info/exclude` and the emptied folder. Build step 0 does the same for the repo it runs in.
- Plans live outside the repository, by default in `~/.engineer-of-wealth/executor/plans/<org>/<repo>/`, one dated file per plan. `/executor:init` or `EXECUTOR_PLANS` moves that folder; `scripts/plan-path.sh` is the only code that knows the layout. Build no longer writes to the repository or its exclude file, and two live plans in one repo never share a file.
- A finished plan says so: `scripts/plan-state.sh --mark` adds `Status: done <date>` once every item's PR is merged or closed, from build and after `gh stack sync --prune`. `scripts/plan-sweep.sh [--dry-run]` does it for the whole plans folder.

## 0.4.0 — 2026-11-03

- Review a pull request from any folder. Say "let's review acme/api#7", or run `/executor:review` with `owner/repo#N` or a pull URL, in any session. In the PR's own repository it reviews as before. Anywhere else it finds the repository's checkout and proposes a new session there running `/executor:review <url>`; where the client can't start one, it prints one command, `cd "<checkout>" && claude "/executor:review <url>"`. It never reviews a repository from a folder that isn't its checkout. With no checkout it lists where it looked and asks before cloning into the first root; on no, nothing is cloned. A bare PR number or a branch name still means the current repository.
- `scripts/find-checkout.sh` does the finding, no AI. It searches the roots two levels deep, so a bare repository and its worktrees are found as one checkout, opened at its default-branch worktree. It fetches `origin` and fast-forwards the default branch only where it is checked out clean; uncommitted work, local commits and the branch someone is on are left alone. Then the hand-off passes `--base origin/<default>` and the summary's Branch line says the review worked from `origin/<default>`. Every `git` and `gh` failure is logged to `~/.engineer-of-wealth/executor/checkout.log` and comes back as one line.
- The search roots, Executor's first setting: a `## Roots` list in `~/.engineer-of-wealth/executor/config.md`, `~/Projects` by default, read by `scripts/roots.sh`. `/executor:init` asks for them, and the self-audit warns about a root that doesn't exist and checks the roots reader and the checkout finder are present.
- `/executor:help` lists the review from any folder and routes "let's review <ref>" to it.

## 0.3.2 — 2026-11-02

- `/executor:review` and the `verifier` agent run at `effort: high` whatever the session's effort is. Before, review ran at the session's effort and the verifier inherited it, so lowering the session default quietly weakened the checks that decide what ships. The builder stays at `effort: medium`: the spec has already settled the design, and it is the expensive agent.

## 0.3.1 — 2026-10-30

- `/executor:review` fixes only your own work. Before, every confirmed Critical finding was committed and pushed to the PR's branch whoever wrote the PR, which is wrong on a teammate's PR and fails on a fork. Now step 1 decides the mode: fix by default only when the PR's author is the `gh` user and the PR isn't from a fork, or, for a branch with no PR, when every commit past the default branch carries your git email (in any case). A branch is judged by its open PR only when that PR's head lives with origin's owner, so a stranger's fork PR that shares the branch name doesn't count. Anything else is report-only: steps 1–5 and 7 run unchanged, nothing is committed, checked out or pushed, the Critical findings stay open and the verdict rule applies to them. `--fix` forces fixing, never on a fork, where the push can't land; `--no-fix` forces report-only. The decision is `scripts/review-mode.sh`, which wraps the `gh` and `git` calls, logs failures to `~/.engineer-of-wealth/executor/review.log` and falls back to report-only when it can't tell.
- The summary's `Rounds:` line names the mode and why it ran, e.g. `report-only · PR by @teammate` or `fix · your PR · 1 · 2 bugs auto-fixed`.
- `/executor:build` runs the review with `--fix`: its PRs are yours, and a failed `gh` lookup shouldn't stop it fixing them. The hook-started review needs no flag, since the PRs Claude opens are yours.
- `scripts/default-branch.sh`: the one default-branch lookup, sourced by `ship.sh` and `review-mode.sh` so both agree on the base.
- The self-audit checks `scripts/review-mode.sh` and `scripts/default-branch.sh` are present.

## 0.3.0 — 2026-10-30

- `/executor:ship`: from finished code to an open draft PR. It commits what is pending, pushes, and opens a **draft** PR; the existing hook then assigns the author and starts the review. `scripts/ship.sh` does the deterministic work (the branch guard, the push, the PR-exists check, the base branch) and wraps every `gh` and `git` call, logging failures to `~/.engineer-of-wealth/executor/ship.log` instead of failing into the conversation. A branch that already has a PR is only pushed, never given a second PR. In a `gh` stack the base is the branch below, resolved to its name from the commit `gh stack view --json` reports.
- `CONTRIBUTING.md`: the seven rules Executor holds itself to, from "deterministic work is a script, never the model" to "two approvals". The review already reads it as a conventions source.
- `references/stacks.md` gains "Keeping a stack healthy": after any PR in a stack merges, `gh stack sync --prune` restacks the rest onto the live base, and no branch is left on a merged one.
- `/executor:init` offers to enable Executor in the repo's own `.claude/settings.json`, for anyone who keeps it off globally: it merges the enable into `enabledPlugins`, keeps every other setting, never touches `settings.local.json` and never commits on its own. The detect-and-merge is `scripts/init-plugin-enable.sh`.
- Review findings carry one number (`#1` … `#n`) running through Critical and Suggestions, so a finding can be cited after the review. The summary header names the PR as `<owner>/<repo>#<n>`, with the branch on its own line.
- The entry skills (`/executor:build`, `/executor:ship`, `/executor:init`) assert at their start that the loaded plugin matches the installed one. A session spawned from a long-lived session inherits that session's snapshot of the plugin; when the plugin was updated afterwards, the spawn would run the old instructions against the new install and fail with a generic error. Now `scripts/version-check.sh` compares the version baked into the skill's own text against the on-disk manifest and, on a drift, the skill stops with one line — the two versions and "reload the plugin or start a fresh session" — instead of a silent or generic failure. The self-audit checks each entry skill asserts the version and that the baked version tracks the manifest. (A snapshot from before this change still cannot self-check: an absent skill can't run a guard, so a truly pre-0.2.0 session falls back to the generic error.)

## 0.2.0 — 2026-10-27

- `/executor:build`: a spec to a stack of reviewed PRs. It checks the spec, plans it as a checklist in `.executor/plan.md` that you approve (`references/plan.md`), builds the foundation alone and stops for its merge, then runs one `executor:builder` per stack in parallel worktrees, reviews every PR, marks it ready on ✅ or ⚠️ and starts the next feature of its stack. A second run carries on from the first unticked item. You merge.
- The `executor:implementer` agent is now `executor:builder`. It stops at the open PR; build runs the review.
- `/executor:help` lists `/executor:build` and routes "build this" to it.
- `/executor:self-audit` is gone: one skill fewer for Claude Code to load. The check is `scripts/self-audit.sh`, which init runs at its end and a central audit can call.
- Review: a shorter description (it goes out with every request) and a shorter skill. The report drops the Fixed, Dismissed and dimensions sections: verdict, build, CI, spec and rounds, then what is still Critical and the Suggestions, each finding with a proposed fix. Debunked findings leave the report.
- `/executor:help` reads better in a busy terminal: sections in capitals (INCLUDES, SETUP), commands in one column and what they do in another, and the build step marked as coming next.

## 0.1.4 — 2026-10-27

- `/executor:menu` is now `/executor:help`, in `skills/help/`. The skill shows what Executor does and routes; the self-audit checks it under its new name and holds it to `disable-model-invocation` like `init` and `self-audit`.
- `/executor:help` on its own prints the help at once, with no model call: a hook in `hooks/register.ts` answers the command with the help block of `skills/help/SKILL.md`, the one place the help is written. With text after it (`/executor:help review 42`), or where Claude Code runs no plugin hooks, the skill runs and routes as before.
- The help skill no longer names a model. It now only routes, and the session's own model reads the conversation from its cache, where a switch to another model would read it all again.
- The help skill is yours to type and no longer Claude's to start (`disable-model-invocation`), so its description leaves the skill list every session sends to the model. Asking in plain words ("review #42") still reaches `/executor:review` through that skill's own description.

## 0.1.3 — 2026-10-27

- `references/implementation.md`: how a feature is built. It starts with a spec check: when there's no spec, or it leaves open what the feature does, its inputs and outputs, edge cases, scope or how to tell it's done, Executor says so and asks for the missing details instead of guessing, then confirms the requirements as a short list before writing anything. Then spec tests, automated where possible and written as manual scenarios where not, coarse and covering the edge cases, there to keep the work from drifting. Then the repo's existing patterns before anything new, correctness and performance as part of the job, a commit for every finished step, each graded on security, performance and correctness, then best practices and repo consistency.
- Spec tests serve a correct feature, not the other way round: code is never shaped to pass a test and a test is never weakened to pass. When building shows a spec test or the spec is wrong, Executor stops, says which, why and what it would change, and changes it only with your approval; the PR lists such changes. The review treats code shaped to pass a test as Critical.
- A refactor that would make the feature's PR big goes into its own PR, below the feature in the stack.
- No inline comments by default; explanations go in commit messages and the PR description. Project docs live in the README and dedicated Markdown files. Nothing ever refers to local material: local paths, notes-app notes or wikilinks, numbered items of a local spec, brainstorming sections.
- New `executor:implementer` agent, one per feature, at medium reasoning effort. Nothing spawns it yet; the build step that will comes next.
- The PR description gains manual scenarios in Testing, and its Spec section links only what a reader can open.
- The review flags references to local material (Critical in code and the description) and a refactor mixed into a feature PR.

## 0.1.2 — 2026-10-27

- A feature now starts with its spec tests: you write the spec, Executor turns each requirement the feature owns into a high-level test before the first line of code and commits them first. They are the ground the feature is built against, so it can't drift from the spec (`references/feature-done.md`).
- `references/pull-request.md`: how Executor's PRs read. Fixed sections (Spec, What changes, Diagram, Testing, Depends on), bullets instead of paragraphs, one screen long, a Mermaid diagram or a screenshot when the change has a shape, and the spec tests in their own Testing section.
- The review checks two more things, both as Suggestions: inline comments that can be removed or cut shorter (best practices), and a PR description that breaks `pull-request.md` (repo conventions).

## 0.1.1 — 2026-10-27

- `/executor:init`, which you type once after installing. It checks the GitHub CLI, its sign-in, `jq` and the gh-stack extension. Executor works best with gh stack, so when it is missing init says why and offers to install it; it also offers the two git settings that keep `gh stack` from stopping at a prompt, in the current repository only. The shared Engineer of Wealth setup is offered too, skipped by default, since Executor itself reads nothing from it.
- `/executor:self-audit` and `scripts/self-audit.sh`: a read-only check of gh, its sign-in, gh stack, failed PR assignments in `assign.log`, the menu, the references, the two hooks and the user-only skills. One round, every finding says what to do, last line `executor: PASS|WARN|FAIL`.
- `references/shared-setup.md`, the copy every Engineer of Wealth plugin ships, and `references/init.md`, Executor's own steps, so a central setup can run Executor's init with the others.

## 0.1.0 — 2026-10-26

- `/executor:review`: builds the change and reviews it in six dimensions (duplication, correctness against the spec, test coverage, security, best practices, repo conventions). Findings are sorted into Critical and Suggestions, each linked to its file and line.
- New `executor:verifier` agent, one per finding, which tries to disprove it and answers confirmed, debunked or reclassified.
- Confirmed Critical findings are fixed on the PR's branch, one commit each, then reviewed again in the same context, at most three rounds.
- Every review ends with the same summary, laid out in `references/review-format.md`.
- A `PostToolUse` hook starts a review whenever Claude creates a pull request.
- A second hook assigns every PR Claude creates to its author (`gh pr edit --add-assignee @me`), since gh has no setting for a default assignee. Plain shell, no AI: the gh calls run detached, so the session never waits on GitHub, and a failure is written to `~/.engineer-of-wealth/executor/assign.log`. Both hooks are local and return in about 20 ms on an ordinary tool call.
- `/executor:menu`, the front door.
- `references/feature-done.md`: a feature is done only when its PR is open. Spec tests and the whole build green, then a draft PR in its stack with a fixed body (spec, done, build, depends on); the review starts through the hook and a ✅ or ⚠️ verdict marks it ready.
- `references/stacks.md`: features ship as GitHub stacked PRs with `gh stack`. The foundation merges first, one stack per dependency chain, every command non-interactive, plain chained PRs when the repo has no stacks.
- The review fixes a stacked PR on its own branch and rebases the branches above it. The hook also starts reviews for PRs opened by `gh stack submit` and `gh stack link`.
