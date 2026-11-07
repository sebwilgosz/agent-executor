# The shape of a spec

What `/executor:spec` writes and `/executor:build` reads. A spec is intent; the repo's docs are the result. It is as long as the work needs and passes the spec check of `references/implementation.md`, step 0.

Every fact names its source in the margin of the line (a note, a PR, the CHANGELOG, a file). What was inferred says so and appears again under open points.

## Sections, in this order

1. **Why.** The problem, in a few lines, and who has it.
2. **Decisions already made.** Each with who decided it and where it is written. Nothing inferred goes here.
3. **Current state.** What exists now, taken from the code and the CHANGELOG, and what is already built. Where the notes disagree with the code, the disagreement is listed here.
4. **Features.** One section per buildable feature, each with:
   - **What it does**, as the user or the caller sees it
   - **Inputs and outputs**
   - **Edge cases and failures**
   - **Out of scope**
   - **Done when**, checkable
5. **Stacks.** The dependency split: the foundation alone first, then the features that depend on nothing else but it, each in a stack of its own, and the chains in dependency order (`references/stacks.md`). A small diagram when it helps.
6. **Not for build.** Manual, release, asset and docs work, so nothing is lost.
7. **Open points.** What is inferred or unknown, each with a suggested answer. Empty once answered.

## Rules

- One requirement belongs to one feature.
- A feature small enough to be one readable PR; split it otherwise.
- No secrets. A spec headed for GitHub holds no local paths, personal notes or wikilinks.
