# The pull request Executor opens

A reviewer reads the PR before the code, so the description is written for the reviewer. The code already says what changed; the description says what the code can't: **why** the change exists, what was wrong or missing, and how to judge it. It starts from the background, in plain words a person can follow without knowing the code, and it shows the problem as a picture. No wall of text.

## Title

The feature's name from the spec, under 70 characters. No prefix, no ticket number unless the repo's convention asks for one.

## Body

Always these sections, in this order. A section with nothing to say is left out, never filled with filler.

```markdown
## Why
<the background and the problem, in plain words for a human: what happened or was missing, who it hurts, what it looked like. Two or three short bullets or sentences, no code names unless the reader needs them.>

## Spec
<`Closes #n` when the feature has a ticket, or its Jira or Linear key>
<link to the spec, only when the reader can open it: an issue, a URL, a file in this repo> | <the requirements this PR meets, in a few words>

## Scope
- <one line per change, as the user or the caller sees it; the how, only where the code can't show it>

## Diagram
<a Mermaid diagram of the problem and the fix, or a screenshot, see below>

## Testing
**Spec tests**, written before the code:
- [x] <requirement> — `<test that proves it>`

**Manual scenarios**, where a requirement can't be automated:
- [ ] <steps> → <expected result>  (ticked only when walked through)

**Also added:** `<test>` — <what it covers> | none
**Changed with approval:** `<spec test>` — <why it was wrong> | none
**Build:** `<commands run>` — all green
**Try it:** <steps to see it working> (only when there is something to see)

## Depends on
<#PR it is stacked on, e.g. its refactor PR> | nothing
```

`scripts/pr-open.sh` fills **Depends on** from the base it used, so a body file written for it leaves the section out.

## Readable, not long

- **Write for a person, not a parser.** Why and Scope read like you would explain the change to a colleague at their desk: full sentences, everyday words, the effect on a user or a run before any file or function name. Telegraphic fragments, internal jargon, requirement numbers and code identifiers as the subject of a sentence are what make a description feel machine-written. Names go in backticks where the reviewer needs to find something, never in place of the explanation.
- **Bullets, not paragraphs.** One idea per bullet, one line per bullet. A paragraph is at most two sentences, and only where a bullet can't carry it.
- **Start from Why.** The first section is the problem in human terms, never a list of what was edited. A reviewer who reads only Why knows what to expect. If you can't write it without naming functions, you haven't found the problem yet.
- **Scope has at most five bullets.** More means the feature is too big or the bullets describe code instead of behaviour. It restates what the diff shows only as far as the reviewer needs a map; it never replaces Why.
- **The whole body fits on one screen**, about 40 lines without the diagram. Longer detail belongs in the code, the spec or a linked file.
- **Code in backticks**: files, functions, commands, flags.
- **Link, don't paste.** No logs, no full test output, no copied spec text: link to them.
- **Only the change.** No story of how it was built, no "I ran…", no notes to the reviewer about the session.
- **Explain here, not in the code.** The why of a decision goes in the PR description and the commit messages; the code carries at most a short comment.
- **Nothing local.** No local file paths, notes from a personal notes app (such as Obsidian) or `[[wikilinks]]`, numbered items of a local spec, or brainstorming sections. Say the thing itself.

## Diagram

**Include one by default.** A reader gets the problem faster from a picture than from a paragraph: draw how it went wrong and how it works now (before and after, or the flow with the broken step marked). Skipping it is the exception, for changes with no shape: a typo, a rename, a version bump, one changed value.

- **Mermaid** in a ` ```mermaid ` block; GitHub renders it. `flowchart`, `sequenceDiagram` or `stateDiagram`, at most about 8 nodes, labels in the spec's words.
- **A screenshot** for a visible UI change, when the session can attach one. When it can't, `Try it` says how to see the change.
- **Leave it out** only when a diagram would just redraw one bullet. Never leave it out because it takes effort: the review flags a missing diagram on a change that has a flow, states or parts that connect.

## Before opening

Read the body once as the reviewer will. If any rule above fails, fix the body first; the review checks it against this file.
