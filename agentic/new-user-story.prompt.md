---
description: "Turn a freeform description into a User Story on the active Space's tracker and a card for it, drafting the fields for you to confirm before tkNewItem and tkNewPrompt write them, then filling the card's Summary, Scope, Implementation Details, Described Changes and Acceptance Criteria."
argument-hint: "Describe the story -- what needs to be built, why, and what done looks like"
agent: "agent"
tools: ["read_file", "list_dir", "run_in_terminal", "grep_search"]
---

> Commands below use the default `tk` prefix. If you registered a different one, substitute it --
> the prefix is config (`commandPrefix`), not part of any command's name.

# New User Story

Turn a freeform description into a User Story on the tracker and a card in the hub, wired
together. Two commands do the writing -- `tkNewItem` creates the item, `tkNewPrompt <id>` creates the
card from it -- and this prompt decides what goes into them.

## Context

1. `tkSwitchSpace Status` -- the active Space is where the story is filed. Do not switch Space
   unless the user says to.
2. `tkConfig -List` -- the Space's `projects`. If it has more than one and the user didn't name
   one, list them and ask.
3. Read one or two recent User Story cards in the Space's `current/` or `archive/` to calibrate
   voice, story point conventions and acceptance-criteria style.

## Steps

### 1. Draft the story fields

From the user's description, extract or infer:

| Field | Notes |
|---|---|
| **Title** | Imperative, ≤ 80 chars -- "Add X to Y" not "X needs Y" |
| **Description** | 3-5 sentences: what, why, who benefits. Plain English. |
| **Acceptance Criteria** | Bullet list -- each criterion is independently verifiable. No vague words ("works", "looks good"). Minimum 4 criteria. |
| **Scope -- In** | What this story delivers. Derived from AC and description. Specific technology/files/flows named. |
| **Scope -- Out** | Explicit exclusions -- things adjacent to the work that are intentionally deferred. E.g. "E2E tests", "framework upgrade", "backend changes". |
| **Implementation Details** | File-level table: which files change and what changes in each. If files are not yet known, derive from the description and codebase context. |
| **Described Changes** | 4-5 PR-ready bullets. Present tense, in the user's voice. `tkNewPR` puts these into the PR description. |
| **Story Points** | 1=trivial, 2=half-day, 3=day, 5=2-3 days, 8=week. Default 3 if unclear. |
| **Priority** | 1=critical, 2=high (default), 3=medium, 4=low |

If the user's description doesn't include enough technical detail to fill Implementation Details, ask one question:
> "Which files or areas of the codebase does this touch?" -- then proceed with the answer.

Show the full draft (all fields) and confirm before creating anything.

### 2. Create the work item

`tkNewItem` derives the organisation, project and your identity from config, expands a sprint name
to a full iteration path, and assigns the item to you. Preview first with `-ReadOnly`, which prints
the fields and writes nothing:

```powershell
tkNewItem `
  -Type UserStory `
  -Title "{title}" `
  -Description "{description}" `
  -AcceptanceCriteria "{ac-html}" `
  -Points {points} `
  -Priority {priority} `
  -ReadOnly
```

Then run the same command without `-ReadOnly`. Add `-Project "{name}"` when the Space has more than
one project, and `-Sprint "{sprint}"` to set the iteration. Capture the new id from the output.

On a GitHub Space the item is an issue: drop `-Priority` and `-Points`, which an issue does not
have and the command refuses by name; the acceptance criteria and repro steps join the issue's
body as sections.

> **AC format (Azure DevOps):** acceptance criteria are stored as HTML. Wrap each bullet in `<li>` inside `<ul>...</ul>`. Example: `<ul><li>Login form shows error on bad credentials</li><li>Form clears on successful login</li></ul>`

### 3. Create the card

```powershell
tkNewPrompt {id}
```

It reads the item back from the tracker and writes the card into the Space's `current/` -- the
filename, the template, the branch suggestion, the sprint and the `**ADO Link:**` line are its job,
not yours. If a card for that id is already in `current/`, it returns that card and writes nothing.

Then fill the card **in place** (edit the sections; do not rewrite the file). Every section below
gets real content -- no `TBD`:

- `## Summary` -- the description from step 1, 3-5 sentences
- `## Scope`
  - **In scope:** specific technologies, flows, and files this story covers
  - **Out of scope:** adjacent work explicitly deferred (name it, don't say "other work")
- `## Implementation Details` -- one row per file/area that changes; keep each entry to one line
- `## Described Changes` -- 4-5 PR-ready bullets, present tense, in the user's voice
- `## Acceptance Criteria` -- a checklist (`- [ ]`) from the AC bullets

`## Progress` stays empty: it is filled as work lands.

### 4. Confirm and finish

Print:

- The work item URL
- The card's path
- A one-line summary of what was created

## Rules

- **Confirm before the tracker write.** Show the full field draft and wait for go-ahead.
- **Do not invent AC.** If the user's description is vague, ask for the specific done conditions before proceeding.
- **One story per run.** If the description implies multiple independent deliverables, ask which to file first.
- **Identity comes from config.** Never ask the user for their email -- `tkNewItem` reads `email` from config, else the signed-in `az` account.
- **The active Space is the target.** Never file into another Space unless the user says so.
- **The commands write; you fill.** The card is created by `tkNewPrompt` and only edited after, so it comes out in the same shape, with the same bytes, as every other card.
