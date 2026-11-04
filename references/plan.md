# The build plan

`/executor:build` keeps each plan as one file outside the repository: a checklist, one item per feature, each linked to the part of the spec it builds. It is the plan you approve, the progress you watch, and what a second run reads to carry on.

The file stays on your machine and the repository is never touched. Because it is local, it may link to a local spec; nothing that goes to GitHub ever does (`references/implementation.md`, step 5). A local spec is linked by its absolute path, since the plan isn't in the repo.

## Where plans live

`scripts/plan-path.sh` is the only code that knows the layout. Ask it; never build a plan's path by hand.

```
<plans folder>/<org>/<repo>/<YYYY-MM-DD> - <title>.md
```

- **The plans folder:** `$EXECUTOR_PLANS`, else the `## Plans` line in `~/.engineer-of-wealth/executor/config.md` (`/executor:init` writes it), else `~/.engineer-of-wealth/executor/plans`. `plan-path.sh --where` says which.
- **`<org>/<repo>`:** from the `origin` URL, or `local/<name>` without an origin. Every worktree of a repo shares the folder, which `plan-path.sh` prints. A missing folder is created on the first write, never on a read.
- **A plan's name:** `plan-path.sh --new "<title>"` prints it: today's date and the title, with a numeric suffix when the name is taken. The title of a local spec is its file name without `.md`, a leading `spec - ` or a trailing ` - spec` (`plan-path.sh --title "<file>"`). The title of an issue, a URL or text is its H1 or title without a leading `Spec:`.

## Which plan is live

The folder is the state: there is no pointer file. A plan stays live until its header says `Status: done <date>`, the date as `YYYY-MM-DD`. The header is the lines before the first `## ` heading. `plan-path.sh --live` prints the live plans, newest first. It reads only the `*.md` files directly in the repo's folder, so a subfolder never holds a plan. Two live plans in one repo are allowed; they never share a file.

## Shape

```markdown
# Build: <spec title>
Spec: [<spec title>](<path or URL of the spec>)

## Foundation
- [x] <feature> — [<spec part>](<link to that part>) — PR #40 ✅ merged

## Stack A: <what the stack is about>
- [x] <feature> — [<spec part>](<link>) — PR #41 ✅ ready
- [ ] <feature> — [<spec part>](<link>) — PR #42 ⏳ in review

## Stack B: <what the stack is about>
- [ ] <feature> — [<spec part>](<link>) — ⛔ <the question, or what blocks it>
- [ ] <feature> — [<spec part>](<link>)
```

- **One item per feature**: a checkbox, the feature's name, a link to the part of the spec it owns, then its PR and state once there is one.
- **Grouped by stack**, as `references/stacks.md` maps a spec: the foundation alone first, a chain of dependent features in one stack bottom-up, independent features in stacks of their own. Stacks are what runs in parallel; the items inside one run in order.
- **Every requirement of the spec belongs to exactly one item.** None is left out, none is built twice.
- **Leave out** a section with nothing in it (no foundation, say).

## States

The text after the link says where the item is. One state at a time:

| State | Meaning | Box |
|---|---|---|
| *(nothing)* | not started | `[ ]` |
| `🔨 building` | its builder is running | `[ ]` |
| `PR #n ⏳ in review` | PR open as a draft, the review is running | `[ ]` |
| `PR #n ✅ ready` | reviewed ✅ or ⚠️ and marked ready: yours to merge | `[x]` |
| `PR #n ✅ merged` | merged (the foundation, before the stacks start) | `[x]` |
| `PR #n ❌ <what is open>` | the review left Critical findings; stays a draft | `[ ]` |
| `⛔ <question or blocker>` | the builder stopped: a spec question, a red build, a spec test it thinks is wrong | `[ ]` |

A box is ticked only when its PR is ready or merged. An item at ❌ or ⛔ stops its stack: nothing above it starts until it is resolved.
