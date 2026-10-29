# Review format

Every review prints the same shape, whatever it found. Sections never disappear: an empty one says `None.`

## A finding

Findings are one numbered list across the whole review — Critical first, Suggestions continuing the same count — so every finding has a single stable number and `#4` means `#4` wherever it is cited. Number with a literal `**#n**` token, not a Markdown `1.` list: the count must run unbroken across the two sections, and a bare `#4` at the start of a line would render as a heading.

```markdown
**#4** · [`path/to/file.rb:42`](<link>) · **<Category>**
<the defect, one sentence>.
Fails when: <concrete input or state → wrong result>.
Proposed Fix: <concrete suggestion of resolving or clarifying>
```

- **Number.** Continuous `#1 … #n` over the whole review, assigned in print order (every Critical, then every Suggestion). It is how a finding is referred to afterwards; in a multi-repo build, as `<owner>/<repo>#<PR> · #4`.
- **Link.** For a pull request: `https://github.com/<owner>/<repo>/blob/<head-sha>/<path>#L<line>`, pinned to the head commit so it never drifts. For a local diff: the repo-relative path, `path/to/file.rb:42`.
- **Category** is one of: Duplication · Correctness · Test coverage · Security · Best practice · Convention · Build.
- **Fails when** names inputs or state, not a feeling. A finding that can't fill it in is a suggestion at most.

## Severity

- **Critical**: merging it causes wrong behaviour, data loss or a security hole, breaks the build, or leaves a spec requirement unmet or untested. Critical findings are bugs: the review fixes them.
- **Suggestion**: everything else worth changing. Suggestions are listed, never fixed by the review.

## The summary

```markdown
# Executor review · [<owner>/<repo>#<PR>](PR URL) — <title>

**Branch:** `<branch name>`
**Verdict:** <❌ Changes required | ⚠️ Mergeable | ✅ Ready>
**Build:** <✅ passed · `<command>`> | <❌ failed · `<command>`> | <⚪ not run · <reason>>
CI: <✅ green | ❌ red | ⏳ running | ⚪ none>
**Spec:** <link to the spec> | none found, PR description
**Rounds:** <n> · <f> bugs auto-fixed | no fixes needed

### Critical (<n>)

<numbered findings #1…, still open after the last round, or None.>

### Suggestions (<n>)

<numbered findings continuing the count, or None.>

## Verdict rule

- ❌ **Changes required**: <reason>
- ⚠️ **Mergeable**: <reason>
- ✅ **Ready**
```

- **The header is the review's reference.** `[<owner>/<repo>#<PR>](PR URL)` is the GitHub shorthand that stays unambiguous when several reviews are printed together — one per repo or per PR — in a multi-repo build. Keep it an `#` heading so each review is its own self-contained, linkable section.
- **A local diff has no PR**, so the header drops the link: `# Executor review · <owner>/<repo> @ <branch>`. Everything below it is unchanged.
