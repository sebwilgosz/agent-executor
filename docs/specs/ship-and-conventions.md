# Spec: explicit ship + repo conventions

Executor builds this spec into reviewed PRs. It has **three independent features (A, B, C)** that can be built in parallel, plus one confirmation (D) that needs no work.

## Background (context, not a requirement)
Today the review flow is triggered only by PR creation — the `PostToolUse` hook in `scripts/review-new-pr.sh` catches `gh pr create` / `gh stack submit` / `gh stack link` and tells Claude to run `executor:review`. There is no on-ramp from "I finished the code and pushed" to a reviewed PR, and no single place stating the engineering rules this plugin holds itself to.

## Locked decisions (apply to the whole spec)
- Ship triggers on an **explicit** user ask only — no hook on a bare `git push`.
- A ship-created PR is always a **draft**.
- Ship is **idempotent**: if a PR already exists for the branch it only pushes, never opens a second PR and never re-reviews. The final review after follow-up edits is the user's explicit `/executor:review`.
- Deterministic work is a **script or mod**, never a model turn. Scripts **wrap every `gh`/`git` call**, log failures and return a note so the agent never receives a raw failed tool call.

## Feature A — `/executor:ship`
The explicit on-ramp from "the code is done" to "a reviewed draft PR".

- **Trigger (explicit only):** user types `/executor:ship`, or says "push", "commit and push", "push changes", "ship this" (routed by the skill's description). Model-invocable. Not a bare mechanical `git push`.
- **Behaviour**, given the current branch:
  1. Guard: not the default branch, and has commits the default branch lacks — else stop with a one-line reason.
  2. Commit uncommitted changes (ask only if ambiguous).
  3. Push the branch to origin.
  4. `gh pr list --head <branch>`: PR exists → stop after the push; none → open a **draft** PR, body per `references/pull-request.md` + `references/feature-done.md`, base = default branch or the branch below in a stack.
  5. Opening the PR runs `gh pr create`; the existing hook then assigns the author (detached) and runs `executor:review`. Ship does not run the review itself.
- **Shape:** `skills/ship/SKILL.md` + `scripts/ship.sh`. The script does the guard, PR-exists check, push and base-branch math; the model writes only the PR body / commit message. The script logs `gh`/`git` failures to `~/.engineer-of-wealth/executor/ship.log` and returns a note.
- **Wiring:** list ship in `skills/help/SKILL.md`, check its files in `scripts/self-audit.sh`, add it to the README table.

## Feature B — `CONTRIBUTING.md`
Create `CONTRIBUTING.md` at the repo root stating the rules below. `executor:review` already loads `CONTRIBUTING.md` as a conventions source, so creating the file is the whole feature — no wiring.

1. **Efficient by default** — least work; load no context the task doesn't need; short descriptions.
2. **One unit, invokable by user and model — no duplicates** — one capability, two entry points; never a second skill repeating another's job.
3. **Deterministic work is a script or a mod, never the model** — help is a mod, assignment a script; reserve the model for judgement.
4. **Tool calls never fail into the conversation** — wrap failable/network calls in our own scripts that catch, log and return a note.
5. **Non-blocking where it can be** — side effects run detached; sequence only true dependencies.
6. **Stacks** — use `gh stack` whenever available; on any stack merge restack the rest onto the live base (`gh stack sync --prune`); never strand a branch on a merged base; never manual-merge in a way that bypasses the restack.
7. **Two approvals** — act between the plan and the merge; never merge, push to the default branch, force-push (outside a stack restack) or post to GitHub unasked.

## Feature C — stack hygiene in `references/stacks.md`
Extend `references/stacks.md` with the rule from CONTRIBUTING #6, as operational steps: use `gh stack` when available; after any PR in a stack merges, run `gh stack sync --prune` to restack the rest onto the live base up to `main`; a branch is never left based on a merged branch; a manual merge that bypasses the restack is not allowed. The ship and review flows reference this section.

## D — review-and-fix: already in place (no work)
`/executor:review` already reviews, verifies, auto-fixes confirmed Critical findings and re-reviews (its description: "review … auto-fixing verified confirmed bugs"). Per rule #2, **do not** build a second `review-and-fix` skill; confirm `/executor:review` covers it and skip.
