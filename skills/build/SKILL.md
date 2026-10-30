---
name: build
description: "Executor: build a spec (an RFC, a feature spec, an issue) into a stack of reviewed pull requests. Checks the spec, plans it as a checklist of features you approve, builds each feature with its own builder agent in parallel worktrees, reviews and fixes every PR, and leaves the merging to you. Use when the user asks to build or implement a spec ('build this', 'executor, build docs/rfc-12.md', 'implement this RFC')."
---

# EXECUTOR · BUILD

You approve twice: the plan, and the merge. Build does everything between them. It never merges, never pushes to the default branch and never edits the spec.

Read before you start, from the plugin root: `references/implementation.md` (step 0, the spec check), `references/plan.md` (the checklist), `references/stacks.md` (how a spec maps to stacks, and the commands).

**First, assert the plugin is current.** This session may carry an old snapshot of Executor while a newer one is installed. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/version-check.sh 0.3.0`. On a `MISMATCH:` line, stop and give the user that one line (the loaded snapshot is stale; reload the plugin or start a fresh session) — build nothing. `OK:` or `STOP:` (the check could not read the manifest): carry on.

## 0. Carry on, or start

If `.executor/plan.md` exists:

- **Same spec** (its `Spec:` line names what the user gave, or the user gave nothing): carry on. Run `gh stack sync --prune` if a stack exists, update each item's state from its PR (`gh pr view <n> --json state,isDraft`), then go to step 3 with the first item that isn't ticked.
- **Another spec:** ask in one line whether to replace the plan. Never overwrite it without a yes.

Otherwise start at step 1.

## 1. The spec

Find it: what the user gave (a path, a URL, an issue, text in the message), then `SPEC.md`, `specs/`, `docs/specs/` in the repo. Read it whole.

Run the spec check of `references/implementation.md`, step 0, on the whole spec. Open points are asked in one message, each with a suggested answer, and nothing is planned until they are answered. The answers are part of the spec from now on: the plan's `Spec:` line keeps the link, and the answers go under it as a short list.

## 2. The plan

Split the spec into features and stacks as `references/stacks.md` maps them, each feature small enough to be one readable PR. Every requirement belongs to exactly one feature.

Write `.executor/plan.md` in the shape of `references/plan.md`, and add `.executor/` to `.git/info/exclude` if it isn't there. Show the user the checklist and stop: **this is the first approval.** On changes, rewrite the file and show it again. Build nothing before a yes.

## 3. Build

Branch names: `<stack>/<feature>`, short and in kebab case (`invites/send-email`).

1. **Foundation first.** If the plan has an unmerged foundation item, build it alone (point 2), review it (step 4), then stop: "Merge PR #n, then run `/executor:build` again." Nothing else starts before it is merged.
2. **One builder per stack.** For each stack whose next item isn't blocked, spawn one `executor:builder` agent for that item, **all in one message**, each with `isolation: "worktree"` and in the background. Give each one only:
   - the feature's name and the full text of the requirements it owns, with the spec answers that touch them
   - the repo path, its branch name and the branch below it: the previous item's branch, or the default branch for the bottom of a stack
   - the spec's path or link, to read for context

   Never give a builder the plan, other features' requirements or your reasoning. Mark each item `🔨 building` in the plan.
3. **As each builder reports**, read its report block (`agents/builder.md`) and update its item:
   - **PR opened:** remove the builder's worktree (`git worktree remove <path>`; its branch is pushed), so the review can check the branch out to fix it. Mark it `PR #n ⏳ in review` and go to step 4 for it.
   - **Stopped** (a spec question, a red build, a spec test it thinks is wrong): mark it `⛔` with the reason in a few words, and keep the full questions for step 5. Its stack stops there; the other stacks carry on.
4. **Next in the stack.** When an item is ticked, spawn the builder for the next item of its stack, as in point 2.

Builders run at the same time; reviews run one at a time, in this session, as their PRs come in.

## 4. Review each PR

Run `/executor:review` on the PR, here: the builder can't, because it can't start the review's verifier agents. The review fixes what it can on the PR's own branch and ends with its summary.

- **✅ or ⚠️:** `gh pr ready <n>`, mark the item `PR #n ✅ ready` and tick it. The next item of its stack can start (step 3, point 4).
- **❌:** the PR stays a draft. Mark the item `PR #n ❌` with what is still Critical; its stack stops there.

## 5. Report

When no builder is running and no review is left:

1. Remove the worktrees still left from builders that stopped (`git worktree remove`), once their branches are pushed.
2. If any item is `⛔` or `❌`: ask everything that is open in one message, each question with a suggested answer, and a wrong spec test with its proposed change. With the answers, a run of `/executor:build` carries on from the first unticked item.
3. Print the checklist from `.executor/plan.md` as it now stands, then one line: what is yours to merge, bottom of each stack first.
