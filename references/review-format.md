# Review format

Every review prints exactly in this format. Empty section says `None.`

## A finding

Findings are one numbered list across the whole review — Critical first, Suggestions continuing the same count — so every finding has a single stable number and `#4` means `#4` wherever it is cited. Number with a literal `**#n**` token, not a Markdown `1.` list: the count must run unbroken across the two sections, and a bare `#4` at the start of a line would render as a heading.

```markdown
#4: · **<Category>** · [`path/to/file.rb:42`](<link>)
<the defect, one sentence>.

Fails when: <concrete input or state → wrong result>.
🛠️: <concrete suggestion of resolving or clarifying>
```

- **Number.** Continuous `#1 … #n` over the whole review, assigned in print order (every Critical, then every Suggestion). It is how a finding is referred to afterwards; in a multi-repo build, as `#4  · [category] · <owner>/<repo>#<PR> · [PATH-TO-FILE]`.
- **Link.** For a pull request: `https://github.com/<owner>/<repo>/blob/<head-sha>/<path>#L<line>`, pinned to the head commit so it never drifts. For a local diff: the repo-relative path, `path/to/file.rb:42`.
- **Category** is one of: Duplication · Correctness · Test coverage · Security · Best practice · Convention · Docs · Other.
- **Fails when** names inputs or state, not a feeling. A finding that can't fill it in is a suggestion at most.

## Severity

- **Critical**: merging it causes wrong behaviour, data loss/leak or a security hole, breaks the build, leaves a spec requirement unmet or untested, adds a performance degradation, or leaves docs stating something false. Critical findings are bugs: in fix mode the review fixes them, in report-only mode they stay open.
- **Suggestion**: everything else worth changing/improving. Suggestions are listed, never fixed by the review.
- **Only Critical findings are auto-verified.** Suggestions are listed as the reviewer drafted them. A Critical brought down by its verifier is listed among the Suggestions, with the verifier's wording.

## The summary

```markdown
––––––––––––––––––
# EXECUTOR REVIEW · [<owner>/<repo>#<PR>](PR URL)
<title>

## CRITICAL (<n>)

<numbered findings #1…, still open after the last round, or None.>

## Suggestions (<n>)

<numbered findings continuing the count, or None.>

## VERDICT [<owner>/<repo>#<PR>](PR URL)
  ▸ **Verdict:** <❌ Changes required | ⚠️ Mergeable | ✅ Ready>
  ▸ **Build:** <✅ passed · `<command>`> | <❌ failed · `<command>`> | <⚪ not run · <reason>>
  ▸ **CI:** <✅ green | ❌ red | ⏳ running | ⚪ none> · **Spec:** <link to the spec> | none found, PR description
  ▸ [**Ready:** ✅ marked ready | ⚪ draft · <why>]
––––––––––––––––
```

- **A local diff has no PR**, so the header drops the link: `# Executor review · <owner>/<repo> @ <branch>`. Everything below it is unchanged.
- **The Docs line prints only when the docs check was skipped**, `<why>` as `docs-mentions.sh` printed it after `UNKNOWN:`.
- **The Ready line prints only when `review-ready.sh` printed `READY:`, `UNKNOWN:` or a `SKIP:` for CI**, `<why>` as it printed it after `UNKNOWN:` or `SKIP:`. A draft left because CI is still running reads `⚪ not marked · CI still running, rerun review-ready.sh <n> once green`: nothing flips it later.

## Where the review lives

Every review writes its full text, laid out as above, to a file under the Executor home, never in the repository (`EOW_HOME` overrides `~/.engineer-of-wealth`):

```text
~/.engineer-of-wealth/executor/reviews/<owner>/<repo>/PR-<n>.md      a PR
~/.engineer-of-wealth/executor/reviews/<owner>/<repo>/<branch>.md    a branch with no PR (a / in the name becomes -)
~/.engineer-of-wealth/executor/reviews/local/<folder name>/<branch>.md   no remote to read an owner and repo from
```

`scripts/review-post.sh --path pr <url>` or `--path branch [<name>]` prints the path and creates the folder. A re-review of the same PR overwrites its file, so a stacked PR re-reviewed after `gh stack rebase` keeps one file. `scripts/review-post.sh <pr-url> <file>` then follows the `Post:` setting in `## Reviews` of `executor/config.md`: `off` (the default) only prints `SAVED:`; `own PRs` posts the file as a comment on the user's own open PR, or edits the comment it posted before, and never posts on someone else's PR. A review with no findings is saved and posted as its short summary.

## The line per PR

In a build, the review file stays out of the build session's context. Each finished PR prints exactly one line instead of its summary:

```text
PR #41 · ✅ ready · 0 Critical · 4 suggestions · 2 rounds · <comment url | file path>
```

## The build block

When no builder or review is left, a build prints one block for the whole build, instead of a checklist and a summary per PR. The plan file keeps its full checklist.

```text
Executor build · <spec title>
<stack>: #41 ✅ · #42 ✅ · #43 ⚠️      (bottom first)
<stack>: #44 ❌ 1 Critical open
Suggestions: 23 across 9 PRs
Reviews: 
  - <comment links, or the reviews folder>
Open: 
  - <questions, wrong spec tests, or nothing>
Merge: #41, #42, #43, then #44 once fixed
––––––––––––––––
```
