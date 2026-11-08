<!-- shared-setup v1 — identical in every Engineer of Wealth plugin. Change it in all of them at once. -->
# Shared setup: what every Engineer of Wealth plugin knows about you

Every plugin from the `engineer-of-wealth` marketplace needs the same few facts: who you are, what you sell, who you write for, and whether your notes are plain Markdown or Obsidian. They live once, in `~/.engineer-of-wealth/`, so the second plugin you install asks only its own questions.

## The folder

```text
~/.engineer-of-wealth/
  shared.md            ← format and context files, for every plugin
  about-me.md          ← starter context files, if init created them
  offer.md
  audience.md
  <plugin>/config.md   ← one plugin's own settings (e.g. ghost/config.md)
  <plugin>/…           ← that plugin's own files, unless its config points elsewhere
```

`EOW_HOME` overrides the folder, for testing.

## shared.md

```markdown
format: obsidian

## Context
- ~/notes/about-me.md | who I am | always
- ~/notes/offer.md | my products and prices | always
- ~/notes/audience.md | my reader | leads
```

| Setting | Default | What it is |
|---|---|---|
| `format` | `markdown` | `obsidian` writes `[[wikilinks]]` and may follow them in context files; `markdown` writes plain Markdown |
| context files | none | Each line is `path \| what it is \| when`. `always` loads before every piece of work; `leads` only for work with, or for, a lead or a customer |

A plugin reads `shared.md` first, then its own `<plugin>/config.md`. A missing file or setting means its default; never stop because of it.

## Every plugin ships the same three files

So one central setup can loop over every installed plugin without knowing any of them:

| File | What it is |
|---|---|
| `references/shared-setup.md` | This file, identical in every plugin; the version line says which copy it is |
| `references/init.md` | The plugin's own init steps, run after S1–S3. Lists the files it writes, so they join the one approval in S4, and ends by running its self-audit |
| `scripts/self-audit.sh` | Read-only check, one round, exit 0, last line `<plugin>: PASS\|WARN\|FAIL — N passed, N errors, N warnings`. Every `✗`/`⚠` line ends with `→` and what to do. Respects `EOW_HOME` |

`/<plugin>:init` and `/<plugin>:self-audit` are thin user-only wrappers around these files. A central setup:

1. Lists the installed plugins (`claude plugin list --json`, those `@engineer-of-wealth`) and their install paths.
2. Runs S1–S3 once, from the copy with the highest version.
3. Runs every plugin's `init.md` up to its approval, collecting the files each will write.
4. Runs S4 once, for all files of all plugins. On YES, writes them, then finishes each plugin's `init.md`.
5. Runs every `scripts/self-audit.sh` and shows one table.

A central audit is step 5 alone, plus checking that every plugin carries the same `shared-setup` version.

## The shared part

Only init writes `shared.md` and the starter context files: a plugin's own `/<plugin>:init`, or a central setup. Either runs these steps before any plugin's own.

### S1: What is there

Read `~/.engineer-of-wealth/shared.md`.
- **Exists:** show its format and context files in a short table, with found/missing per file, and say "Set up by an earlier init." Ask **KEEP** (go to the plugin's own steps) or **CHANGE** (S2, with these values as defaults). Never ask the shared questions again without being asked to.
- **Missing:** S2.

### S2: Ask

In one message, each with its default; an empty answer takes the default:

```
SHARED SETUP — asked once for all Engineer of Wealth plugins

1. FORMAT — markdown or obsidian?   Default: markdown
2. CONTEXT — files that say who you are, what you sell and who you write for.
   Give their paths, or say "create" and I'll ask three short questions
   and write them for you, or "skip".
```

If the current folder, or a folder the user names, is inside an Obsidian vault (a `.obsidian` folder in it or above it), suggest `obsidian`. For each path the user gives, ask `always` or `leads` unless it is obvious from what the file is.

### S3: Create context files (only on "create")

Ask one at a time and write down only what the user says:

1. **About you**: who are you, what do you do, what should a reader know about you? → `~/.engineer-of-wealth/about-me.md`, `always`
2. **Your offer**: what do you sell, at what price, with which links? → `~/.engineer-of-wealth/offer.md`, `always`
3. **Your reader**: who do you write for, what do they struggle with? → `~/.engineer-of-wealth/audience.md`, `leads`

Each file is a `# Title` and the answer as plain paragraphs or a list. Never fill a gap with a guess: an unanswered question becomes a `TODO:` line. "skip" on a question means no file and no context line.

### S4: Approve and write

Show the full `shared.md` and every new file with its path, together with the plugin's own files from its init, in one approval. Mark files that already exist; never overwrite one unless the user names it.

```
- YES — write it
- FIX — tell me what to change
```

## Rules

- Ask before writing anything.
- Context files hold only the user's words. No invented prices, bios, products or results.
- Init writes only in `~/.engineer-of-wealth/` and to context files the user approved. A plugin never edits another plugin's `<plugin>/` folder.
- Every other skill reads `shared.md` and the context files and never edits them.
