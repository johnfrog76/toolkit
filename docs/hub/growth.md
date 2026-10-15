# `growth/` in the hub

Professional development as first-class artifacts: **trainings**, **presentations**
and **goals**. They live in the hub next to your cards, they are read by the
review generator the same way cards are, and they are plain markdown a person
can open.

**This document is the contract.** Two consumers read and write these files --
the CLI verb `{cliPrefix}NewGrowth` and the agent's `POST /api/growth` -- and
neither one's source is the source of truth. Both are held to what is written
here, and `Tests/test_growth.py` asserts they produce identical bytes for
identical inputs. A change to the shape below is a breaking change: both
consumers' fixtures and this file change in the same sitting.

## Where it lives

```text
<promptsRoot>/
  growth/
    current/     in-progress trainings, upcoming talks, active goals
    archive/     completed trainings, delivered talks, achieved goals
  reviews/       generated work reviews, per slug-set
  resume/        resume.md
  <org>/         one folder per engagement -- cards, not growth
```

**The hub-root names are defaults, not constants.** `growth`, `reviews`, `resume`,
`manager`, `reminders`, `design` and `agentic` are declared by the hub, in `<promptsRoot>/hub.json`'s `folders` block;
omit a key and it keeps the name above. Both consumers resolve them through one accessor --
`hub_folder()` in the agent, `Get-P20HubFolder` in the CLI -- so this document's shape is the same
whatever they are called. [Configuration](../CONFIGURATION.md#the-hub-declares-its-orgs) has the manifest.

`growth/`, `reviews/` and `resume/` are **hub-root** folders: siblings of the
per-org folders, not children of one. That is deliberate. A training you took
does not stop having happened when you switch org, and a resume is not an
engagement's. It is the same reason `features.growth` is a top-level flag rather
than a per-org one.

## Naming

A type prefix and a date, so a directory listing sorts by kind and then
chronologically without opening anything:

```text
training-YYYY-MM-DD-short-title.prompt.md
presentation-YYYY-MM-DD-short-title.prompt.md
goal-YYYY-short-title.prompt.md
```

```text
training-2026-03-02-distributed-systems-fundamentals.prompt.md
presentation-2026-05-14-designing-for-non-determinism.prompt.md
goal-2026-improve-test-coverage-patterns.prompt.md
```

**A goal is dated by year, not by day.** A goal belongs to a review period, not
to an afternoon. The short title is the item's title lowercased, non-alphanumeric
runs replaced by a single hyphen, trimmed to 40 characters.

**The prefix is what decides the type.** Not a field inside the file, not a
folder: the first segment of the filename. A file in `growth/current/` whose name
starts with none of the three prefixes is not a growth artifact and is ignored
rather than guessed at.

## Lifecycle

1. Create it in `current/` -- `{cliPrefix}NewGrowth`, the web UI's Growth page, or
   by hand from a template.
2. Fill it in as you go. A training gets takeaways, a talk gets an outline, a
   goal gets progress-log entries. Evidence written down while it is fresh is
   the whole point.
3. When it is finished, record the outcome in the file's own words -- `Completed`,
   `Delivered`, `Status` -- because that is what the readers key on.
4. Retire it: `{cliPrefix}NewGrowth -Close <file>`, or *Retire* on the Growth
   page, moves it to `archive/` and stamps `**Closed:** YYYY-MM-DD` through the
   shared stamp writer. The review generator reads both folders, so archiving
   loses nothing.

There is no status field anywhere else, and nothing is stored about these files
outside the files. State is derived by reading them, the same rule cards follow.

## How a reader decides what state an item is in

| Type | Status comes from | Reads as |
| --- | --- | --- |
| Training | the line under `## Status` | `Not Started` -> **new**; `Completed` or `Achieved` -> **complete**; anything else -> **active** |
| Presentation | `- **Delivered**:` under a section whose heading STARTS WITH `## Outcome` | `Yes` -> **complete**; otherwise **active** |
| Goal | `- **Status**:` under a section whose heading STARTS WITH `## Outcome` | `Not Started` -> **new**; `Completed` or `Achieved` -> **complete**; anything else -> **active** |

**The heading is matched by how it starts, on purpose.** A file outlives the template it was made from: a
talk written up in April is headed `## Outcome`, one from July `## Outcome & Follow-Up`, and both say whether
it was given. Matching the current template's heading exactly read the April talk as never delivered.
Every rule in
this table is pinned, case by case, in `Tests/test_growth_status.py` -- change one and that file says so.

The deadline is read from the item's date field. A range is written
`2026-03-02 to 2026-04-30` and the deadline is the end of it; a single date is
its own deadline; `TBA` is not a date. **ASCII `to`, never a dash** -- these
files are written by a PowerShell script that has to parse on PowerShell 5.1,
where an en dash inside a double-quoted string is misread on a Windows-1252
code page.

## The file shapes

LF line endings, UTF-8 with no BOM, one trailing newline. Every heading below is
written even when its value is empty -- a reader looks up a heading, and a
missing one is indistinguishable from a file it does not understand.

### Training

```markdown
# Training Artifact

---

## Title

Distributed Systems Fundamentals

## Type

Voluntary

## Date(s)

2026-03-02 to 2026-04-30

## Hours

12

## Provider

Internal Academy

---

## Description

Consensus, partitioning and failure modes, for the queue rewrite.

---

## Status

Not Started

## Key Takeaways

-
-
-

---

## Outcome

- **Completed**: No
- **Certificate / badge**:
- **Applied to work**:
```

`## Hours` defaults to `TBD` when none is given. `## Type` is `Voluntary` on a
new file; `Required` and `Certification` are the other values a person writes by
hand. `## Hours` is also what the Growth page's quarter line adds up, for a Space that states
`trainingHoursPerQuarter`: the number in the text, summed over `Complete` trainings whose end date falls in the
current calendar quarter ([growth module](../modules/growth.md#the-quarter-line)).

### Presentation

```markdown
# Presentation Artifact

---

## Title

Designing for Non-Determinism

## Presenter

## Date & Time

2026-05-14

## Format

## Prep Estimate

## Audience

---

## Context & Intent

Testing systems whose answers are allowed to differ.

---

## Outline / Slide Summary

### Section 1 -
### Section 2 -
### Section 3 -

---

## Key Themes

---

## Outcome & Follow-Up

- **Delivered**: No
- **Audience size**:
- **Feedback received**:
- **Follow-up actions**:
- **Recording / materials link**:
```

`## Presenter` is filled from `branchUser` in config and is otherwise left
empty. No name is ever written into it from source.

### Goal

```markdown
# Goal Artifact

---

## Goal

Improve test coverage patterns

## Category

## Time Frame

2026-01-01 to 2026-12-31

---

## Why This Matters

Make the suites say something about behaviour rather than shape.

---

## Milestones

- [ ]
- [ ]
- [ ]

---

## Progress Log

| Date | Update |
|------|--------|
|      |        |

---

## Outcome

- **Status**: Not Started
- **Evidence**:
- **Impact**:
```

`## Category` is free text -- Technical Skill, Career Growth, Leadership,
Process Improvement are the ones that recur. `## Milestones` is a checklist, and
the review generator counts the boxes.

## How reviews pick these up

`{cliPrefix}NewWorkReview` scans `archive/`, `current/` and the growth folder
for markdown committed in the period, and groups what it finds by folder. Growth
items land under a **Professional Development** heading. Nothing about that is
special-cased for this module: the growth folder is simply one of the folders
scanned, which is why growth data has to be in the hub rather than somewhere
else.

**The folder's name is the hub's**, from `hub.json`'s `folders.growth`, and the
scan follows it. What does **not** follow it is the section: the review groups,
labels and orders by a stable *kind* -- `archive`, `current`, `growth` -- so a
hub that renames the folder still gets a Professional Development heading rather
than a group with no label. The path is data; the section is a contract.

## Templates

For writing one by hand rather than generating it:
[Training](../../templates/Training.template.md),
[Presentation](../../templates/Presentation.template.md),
[Goal](../../templates/Goal.template.md).

The templates are the human version -- comments explaining each field -- and the
generated files are the same headings with the comments removed. A file made
from a template and a file made by `{cliPrefix}NewGrowth` are read identically,
because of how a heading's value is read: **the first line under the heading
that is a value**. The section ends at the next `##`; a blank line, the `---`
the writer puts between groups of headings, and an HTML comment (over one line
or several) are skipped, not returned. So a training with no provider reads
`provider` as empty rather than `---`, and a template-made file whose headings
are each followed by a `<!-- hint -->` reads its title from the filename and
its provider, hours and date as empty -- exactly what a generated file with
those fields blank would say. `Tests/test_growth.py` pins both
(`HeadingReaderTests`).
