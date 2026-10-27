# Review format

Every review prints the same shape, whatever it found. Sections never disappear: an empty one says `None.`

## A finding

One bullet, one line:

```markdown
- [`path/to/file.rb:42`](<link>) — **<Category>** — <the defect, one sentence>. Fails when: <concrete input or state → wrong result>.
```

- **Link.** For a pull request: `https://github.com/<owner>/<repo>/blob/<head-sha>/<path>#L<line>`, pinned to the head commit so it never drifts. For a local diff: the repo-relative path, `path/to/file.rb:42`.
- **Category** is one of: Duplication · Correctness · Test coverage · Security · Best practice · Convention · Build.
- **Fails when** names inputs or state, not a feeling. A finding that can't fill it in is a suggestion at most.

## Severity

- **Critical**: merging it causes wrong behaviour, data loss or a security hole, breaks the build, or leaves a spec requirement unmet or untested. Critical findings are bugs: the review fixes them.
- **Suggestion**: everything else worth changing. Suggestions are listed, never fixed by the review.

## The summary

```markdown
## Executor review · <PR #123: title> | <branch name>

**Verdict:** <❌ Changes required | ⚠️ Mergeable with suggestions | ✅ Ready to merge>
**Build:** <✅ passed · `<command>`> | <❌ failed · `<command>`> | <⚪ not run · <reason>>  ·  CI: <✅ green | ❌ red | ⏳ running | ⚪ none>
**Spec:** <link to the spec> | none found, checked against the PR description
**Scope:** <n> files · +<added> −<deleted> · `<head>` → `<base>`
**Rounds:** <n> · <f> bugs fixed in <commit links> | no fixes needed

### Critical (<n>)
<findings still open after the last round, or None.>

### Fixed (<n>)
- [`path:line`](<link>) — **<Category>** — <the defect>. Fixed in <commit link>.

### Suggestions (<n>)
<findings, or None.>

### Dismissed after verification (<n>)
- [`path:line`](<link>) — <the claim> — <why the verifier disproved it>.

### Checked
| Dimension | Result |
|---|---|
| Duplication | <✅ clean · ⚠️ n suggestions · ❌ n critical> |
| Correctness vs spec | … |
| Test coverage | … |
| Security | … |
| Best practices | … |
| Repo conventions | … |
| Build | … |
```

## Verdict rule

- ❌ **Changes required**: any Critical left open, or the build failed.
- ⚠️ **Mergeable with suggestions**: no Critical and the build did not fail, but there is at least one Suggestion or the build could not run.
- ✅ **Ready to merge**: no Critical, no Suggestion, build passed.

Order findings inside a section most severe first, then by path.
