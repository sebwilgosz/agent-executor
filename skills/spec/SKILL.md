---
name: spec
description: "Executor: draft a spec for what you want built, from every relevant source (your notes, the repo, its CHANGELOG, issues), and save it where your specs live. Use when the user asks to write a spec or plan something from sources: 'write a spec for X', 'plan X from my notes', 'draft an RFC for X'."
model: opus
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-home.sh:*)
---

# EXECUTOR · SPEC

Drafts the document `/executor:build` starts from, in the shape its spec check passes. It never builds, and it never decides where the spec is kept: the agent instructions of the place you work in do.

Read from the plugin root: `references/spec.md` (the shape) and `references/spec-home.md` (where specs live).

## 1. Where it goes

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-home.sh --repo <target repo>` and read its output as `references/spec-home.md` says. `NONE:` or `AMBIGUOUS:` means asking and writing the answer down, as that file lays out, before anything is drafted. If the home needs a tool this machine lacks (the Notion connector is off, `gh` is signed out), stop before drafting, name what is missing and offer the local default.

## 2. Sources

Read what exists, in this order:

1. What the user passes: paths, URLs, issues, Notion pages, notes.
2. The instruction files from step 1, and the notes they name (a product note, by name or wikilink).
3. The spec home: a spec for the same work is updated, never duplicated.
4. The repo: README and `docs/` (what exists now), `CHANGELOG.md`, `git log` since the last release, open issues and PRs, and an earlier plan for the same work.

A source that can't be read (a private URL, a missing connector) is listed as unread, never guessed.

## 3. Draft

Write one spec in the shape of `references/spec.md`. Rules:

- Write Why, and each feature's Why line, for a person: the problem in everyday words, before any requirement. A spec that only lists what to do makes every PR built from it read like a diff.
- Every fact names its source. What you inferred is marked as inferred and becomes an open question; it is never written as decided.
- When sources disagree, current state comes from the code and the CHANGELOG, intent from the notes, and the disagreement is listed.
- Work the code shows as already built is reported as done, not drafted again.
- Secrets never go into a spec. A spec headed for GitHub follows `references/implementation.md` step 5: no local paths, no personal notes, no wikilinks. A GitHub home in a public repo: say once, before writing, that the spec will be public.
- Nothing found beyond the request: fall back to the spec check's questions (`references/implementation.md` step 0) instead of inventing a spec.

## 4. Ask, then save

Show the open points in one message, each with a suggested answer, and the draft with them applied. Save nothing before the answers. Then ask once to save, and only after a yes write it to the home:

| Home | How |
|---|---|
| folder | `<Name> - spec.md` at the location, next to the product note when the work belongs to no project |
| repo | `<Name> - spec.md` in the repo folder named; it is the one case where a spec is committed, and you still don't commit it |
| Notion, Linear, Jira | create the page, issue or epic through the connector the home names |
| GitHub | `gh issue create` for the parent issue in the repo named |

Report where it went, then stop: building is `/executor:build`.
