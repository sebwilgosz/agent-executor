# The pull request Executor opens

A reviewer reads the PR before the code. It has to show in one screen what changed, how it looks and how it was tested. No wall of text.

## Title

The feature's name from the spec, under 70 characters. No prefix, no ticket number unless the repo's convention asks for one.

## Body

Always these sections, in this order. A section with nothing to say is left out, never filled with filler.

```markdown
## Spec
<link to the spec, only when the reader can open it: an issue, a URL, a file in this repo> | <the requirements this PR meets, in a few words>

## What changes
- <one line per change, as the user or the caller sees it>

## Diagram
<a Mermaid diagram or a screenshot, see below>

## Testing
**Spec tests**, written before the code:
- [x] <requirement> — `<test that proves it>`

**Manual scenarios**, where a requirement can't be automated:
- [ ] <steps> → <expected result>  (ticked only when walked through)

**Also added:** `<test>` — <what it covers> | none
**Build:** `<commands run>` — all green
**Try it:** <steps to see it working> (only when there is something to see)

## Depends on
<#PR it is stacked on, e.g. its refactor PR> | nothing
```

## Readable, not long

- **Bullets, not paragraphs.** One idea per bullet, one line per bullet. A paragraph is at most two sentences, and only where a bullet can't carry it.
- **What changes has at most five bullets.** More means the feature is too big or the bullets describe code instead of behaviour.
- **The whole body fits on one screen**, about 40 lines without the diagram. Longer detail belongs in the code, the spec or a linked file.
- **Code in backticks**: files, functions, commands, flags.
- **Link, don't paste.** No logs, no full test output, no copied spec text: link to them.
- **Only the change.** No story of how it was built, no "I ran…", no notes to the reviewer about the session.
- **Explain here, not in the code.** The why of a decision goes in the PR description and the commit messages; the code carries at most a short comment.
- **Nothing local.** No local file paths, Obsidian notes or `[[wikilinks]]`, numbered items of a local spec, or brainstorming sections. Say the thing itself.

## Diagram

Include one when the change has a shape worth seeing: a flow, a sequence of calls, states, or how new parts connect.

- **Mermaid** in a ` ```mermaid ` block; GitHub renders it. `flowchart`, `sequenceDiagram` or `stateDiagram`, at most about 8 nodes, labels in the spec's words.
- **A screenshot** for a visible UI change, when the session can attach one. When it can't, `Try it` says how to see the change.
- **Leave it out** when a diagram would only redraw one bullet. A diagram that adds nothing is noise too.

## Before opening

Read the body once as the reviewer will. If any rule above fails, fix the body first; the review checks it against this file.
