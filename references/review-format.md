# Review format

Every review prints the same shape, whatever it found. Sections never disappear: an empty one says `None.`

## A finding

One bullet, one line:

```markdown
- [`path/to/file.rb:42`](<link>) — **<Category>** 
  <the defect, one sentence>.
  Fails when: <concrete input or state → wrong result>.
  Proposed Fix: <concrete suggestion of resolving or clarifying>
```

- **Link.** For a pull request: `https://github.com/<owner>/<repo>/blob/<head-sha>/<path>#L<line>`, pinned to the head commit so it never drifts. For a local diff: the repo-relative path, `path/to/file.rb:42`.
- **Category** is one of: Duplication · Correctness · Test coverage · Security · Best practice · Convention · Build.
- **Fails when** names inputs or state, not a feeling. A finding that can't fill it in is a suggestion at most.

## Severity

- **Critical**: merging it causes wrong behaviour, data loss or a security hole, breaks the build, or leaves a spec requirement unmet or untested. Critical findings are bugs: the review fixes them.
- **Suggestion**: everything else worth changing. Suggestions are listed, never fixed by the review.

## The summary

```markdown
## Executor review · [<PR #123: title>](PR URL) | <branch name>

**Verdict:** <❌ Changes required | ⚠️ Mergeable | ✅ Ready>
**Build:** <✅ passed · `<command>`> | <❌ failed · `<command>`> | <⚪ not run · <reason>>
CI: <✅ green | ❌ red | ⏳ running | ⚪ none>
**Spec:** <link to the spec> | none found, PR description
**Rounds:** <n> · <f> bugs auto-fixed | no fixes needed

### Critical (<n>)

<findings still open after the last round, or None.>

### Suggestions (<n>)

<findings, or None.>

## Verdict rule

- ❌ **Changes required**: <reason>
- ⚠️ **Mergeable**: <reason>
- ✅ **Ready**
```
