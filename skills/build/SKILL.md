---
name: build
description: "Executor: build a spec (an RFC, a feature spec, an issue) into a stack of reviewed pull requests. Checks the spec, plans it as a checklist of features you approve, builds each feature with its own builder agent in parallel worktrees, reviews and fixes every PR, and leaves the merging to you. Use when the user asks to build or implement a spec ('build this', 'executor, build docs/rfc-12.md', 'implement this RFC')."
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-github.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-home.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-state.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/plans-migrate.sh:*)
---

# EXECUTOR · BUILD

You approve twice: the plan, and the merge. Build does everything between them. It never merges, never pushes to the default branch and never edits the spec.

Read before you start, from the plugin root: `references/implementation.md` (step 0, the spec check), `references/plan.md` (the checklist), `references/stacks.md` (how a spec maps to stacks, and the commands).

**First, assert the plugin is current.** This session may carry an old snapshot of Executor while a newer one is installed. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-check.sh 0.6.3`. On a `MISMATCH:` line, stop and give the user that one line (the loaded snapshot is stale; reload the plugin or start a fresh session) — build nothing. `OK:` or `STOP:` (the check could not read the manifest): carry on.

## 0. Carry on, or start

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh`: this repo's plans folder. On a `STOP:` line, give the user that line and stop, so nothing moves outside a repository.

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plans-migrate.sh .`, which moves a legacy `.executor/` this repo still holds to its plans folder, from the repo's top folder and not a repository nested in it. On `No legacy .executor/ under ...`, say nothing. Otherwise say in one line that it moved the legacy `.executor/`, naming any `clash:`, `left:`, `failed:` or `STOP:` line, and go on: what it reports stays where it is.

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh --live`: this repo's live plans, newest first, one path per line. On a `STOP:` line, give the user that line and stop.

For each one, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-state.sh --mark "<plan>"`:

- **`DONE`:** the script has marked it done. Say so in one line. It no longer counts as a live plan below, so with none left this starts at step 1 as if there were no plan, with no question.
- **`OPEN`:** it stays live, as below.
- **`UNKNOWN`:** it stays live, as below; name the reason when you carry it on or ask about it.
- **`STOP:`:** give the user that line and stop.

**With a spec:**

- **A live plan whose `Spec:` line names it:** carry that plan on.
- **Only other live plans:** ask in one line whether to start a new plan beside them. On yes, go to step 1; on no, stop. Nothing is ever replaced.
- **No live plan:** step 1.

**With no argument:**

- **One live plan:** carry it on.
- **Several:** ask in one line which to carry on.
- **None:** step 1.

**Carrying a plan on:** run `gh stack sync --prune` if a stack exists, update each item's state from its PR (`gh pr view <n> --json state,isDraft`), then go to step 3 with the first item that isn't ticked.

From here on, "the plan" is that one file. Two live plans in one repo are allowed; they never share a file.

## 1. The spec

Find it: what the user gave (a path, a URL, an issue, text in the message), then the spec home (`bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-home.sh --repo <repo>`, with `references/spec-home.md` for how to pick the spec and read it), then `SPEC.md`, `specs/`, `docs/specs/` in the repo. Read it whole. With no spec at all, offer `/executor:spec` to draft one from the user's sources in place of the question list below, and carry on with what it writes.

Run the spec check of `references/implementation.md`, step 0, on the whole spec. Open points are asked in one message, each with a suggested answer, and nothing is planned until they are answered. The answers are part of the spec from now on: the plan's `Spec:` line keeps the link, and the answers go under it as a short list.

## 2. The plan

Split the spec into features and stacks as `references/stacks.md` maps them, each feature small enough to be one readable PR. Every requirement belongs to exactly one feature.

Name the plan with the spec's title: for a spec that is a local file, `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh --title "<spec file>"`; for an issue, a URL or text, its H1 or title. Then `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh --new "<title>"` prints the plan's path. Write the plan there in the shape of `references/plan.md`, creating the folder if it is missing. If `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-path.sh --host` prints a host other than `github.com`, its header gets the `Host: <host>` line. Nothing goes in the repository. Show the user the checklist and stop: **this is the first approval.** On changes, rewrite the file and show it again. Build nothing before a yes.

## 2b. Tickets

Only when the spec home (`scripts/spec-home.sh`) names a tracker, and only once the plan is approved. Ask once per run, never on its own: "Create one ticket per plan item in <tracker>?" Creating tickets posts to an outside service, so a no is final for this run.

On yes, create one ticket per plan item, skipping any item the plan already shows a ticket for: a rerun never creates a ticket twice, because the plan holds the link.

- **Body:** exactly what that item's builder is given (step 3, point 2), the feature's name, the requirements it owns and the spec answers that touch them, plus a link to the spec. One text, two uses. Write it to a temporary file.
- **GitHub:** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-github.sh <owner/repo> <the spec's issue number> "<feature name>" <body file>`; it creates the issue and links it as a sub-issue. Read its `TICKET:` and `NOTE:` lines.
- **Linear, Jira:** create the issue or ticket through the connector the home names, with the same body.
- **Record it:** add `ticket #<n>` (GitHub) or `ticket <KEY>` (Jira, Linear) to the item in the plan, after its spec link.
- **The tracker is unreachable, or a ticket fails:** carry on without tickets, mark nothing, and say so in one line. Never stop the build for it.

Updating a ticket's status is not build's job: the PR link and the tracker's GitHub integration do that.

## 3. Build

Branch names: `<stack>/<feature>`, short and in kebab case (`invites/send-email`).

1. **Foundation first.** If the plan has an unmerged foundation item, build it alone (point 2), review it (step 4), then stop: "Merge PR #n, then run `/executor:build` again." Nothing else starts before it is merged.
2. **One builder per stack.** For each stack whose next item isn't blocked, spawn one `executor:builder` agent for that item, **all in one message**, each with `isolation: "worktree"` and in the background. Give each one only:
   - the feature's name and the full text of the requirements it owns, with the spec answers that touch them
   - the repo path, its branch name and the branch below it: the previous item's branch, or the default branch for the bottom of a stack
   - the spec's path or link, to read for context
   - its ticket, when the plan records one: `Closes #<n>` on GitHub, the key on Jira and Linear

   Never give a builder the plan, other features' requirements or your reasoning. Mark each item `🔨 building` in the plan.
3. **As each builder reports**, read its report block (`agents/builder.md`) and update its item:
   - **PR opened:** remove the builder's worktree (`git worktree remove <path>`; its branch is pushed), so the review can check the branch out to fix it. Mark it `PR #n ⏳ in review` and go to step 4 for it.
   - **Stopped** (a spec question, a red build, a spec test it thinks is wrong): mark it `⛔` with the reason in a few words, and keep the full questions for step 5. Its stack stops there; the other stacks carry on.
4. **Next in the stack.** When an item is ticked, spawn the builder for the next item of its stack, as in point 2.

Builders run at the same time; reviews run one at a time, in this session, as their PRs come in.

## 4. Review each PR

Run `/executor:review <n> --fix` on the PR, here: the builder can't, because it can't start the review's verifier agents. The review fixes what it can on the PR's own branch and ends with its summary.

- **✅ or ⚠️:** the review has marked the PR ready. Mark the item `PR #n ✅ ready` and tick it; a **Ready:** line saying it was not marked goes in step 5. The next item of its stack can start (step 3, point 4).
- **❌:** the PR stays a draft. Mark the item `PR #n ❌` with what is still Critical; its stack stops there.

## 5. Report

When no builder is running and no review is left:

1. Remove the worktrees still left from builders that stopped (`git worktree remove`), once their branches are pushed.
2. If any item is `⛔` or `❌`: ask everything that is open in one message, each question with a suggested answer, and a wrong spec test with its proposed change. With the answers, a run of `/executor:build` carries on from the first unticked item.
3. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan-state.sh --mark "<the plan>"`: everything may have been merged while this ran. On `DONE`, say in one line that the plan is marked done.
4. Print the plan's checklist as it now stands, then one line: what is yours to merge, bottom of each stack first.
