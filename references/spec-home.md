# The spec home

Where a spec is read from and written to. It is rarely the repo: a Notion RFC, a note in a vault, a GitHub parent issue. Executor never decides it. The agent instructions of the place you work in name it, and `scripts/spec-home.sh` finds them; the model only reads the words.

## Resolve it

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-home.sh [--repo <target repo>]` from the working folder. It reads the nearest `AGENTS.md` or `CLAUDE.md` from there upwards that has a `## Specs` section, then the target repo's own, and prints:

- `kind` — `folder`, `repo`, `notion`, `github`, `linear` or `jira`
- `location` — where, in the instructions' own words
- `tracker` — `github`, `linear`, `jira` or `none`: where tickets go
- `tool` — what reaches it: the file tools, `git`, `gh`, or an MCP connector
- `file` — the instructions file that names it

Or one line: `NONE:` (nothing names a home) or `AMBIGUOUS:` (two files at one level, or the words, name more than one home). On `AMBIGUOUS:` ask which; never guess.

## How instructions name it

A short section in plain words:

```markdown
## Specs
Specs: Notion, the "RFCs" database. Tickets: Jira project TRAV.
```

Other examples:

- `Specs: in this vault, 623. Projects/<project>/<Name> - spec.md; next to the product note when the work belongs to no project.`
- `Specs: GitHub, a parent issue in this repo, one sub-issue per feature.`
- `Specs: docs/specs/ in this repo.` The only case where a spec is committed.

## Before using a home

- **The tool is missing** (the Notion connector is off, `gh` is signed out): stop before drafting, name what is missing and offer the local default below.
- **GitHub issues in a public repo:** say once, before writing, that the spec will be public.
- **A spec is intent; the repo's docs are the result.** The README and `docs/` change with the code (`references/implementation.md`, step 5). They are a source for a spec, never its destination. No spec, RFC or roadmap is committed to the repo unless the instructions say so.

## Nothing names a home: ask once, then write it down

The first skill that needs a home (`/executor:spec`, `/executor:build` or `/executor:init`) asks, so the question comes up once per place:

1. **Where.** One question with a suggested answer built from what you see: a `Projects` folder beside the instructions file suggests `<that folder>/<project>/<Name> - spec.md`, a GitHub remote suggests a parent issue, otherwise the local folder below. In the same message: do tickets go to a tracker (Jira, Linear, GitHub issues, none)?
2. **For which folder.** The answer applies to everything under one folder. Suggest the one `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-home.sh --folder` prints, the nearest folder above the working folder with an instructions file. The nearest file wins, so a sub-folder keeps its own home.
3. **Write it on a yes.** Show the exact `## Specs` section and the files it goes into, then run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-home.sh --write <folder> "<line>" ...`. It writes `AGENTS.md` and `CLAUDE.md` when both exist, only `AGENTS.md` when `CLAUDE.md` imports it, and in a folder with neither, an `AGENTS.md` plus a one-line `CLAUDE.md` that imports it. An existing `## Specs` section is replaced, never duplicated.
4. **Inside a git repo the file is left uncommitted** and the user is told. Executor never commits it.
5. **Declined:** the spec stays local for this run, in the folder `bash ${CLAUDE_PLUGIN_ROOT}/scripts/spec-home.sh --local` prints, `~/.engineer-of-wealth/executor/specs/<org>/<repo>/`, beside the plans folder and never inside the repository, and the question comes again next run.

## Out of scope

Creating the home (a Notion database, a Linear project), and moving specs between homes.
