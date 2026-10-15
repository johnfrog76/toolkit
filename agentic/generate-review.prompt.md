---
description: "Turn a tkNewWorkReview scaffold into a shareable work review of one or more Spaces over a date range, for a performance review, a status update or an accomplishments report."
argument-hint: "Space slug(s) and a date range, e.g. 'first: Q1' or 'first second: January 1 through April 30'. Defaults to the active Space."
agent: "agent"
---

> Commands below use the default `tk` prefix. If you registered a different one, substitute it --
> the prefix is config (`commandPrefix`), not part of any command's name.

# Generate Review

Two halves, and knowing which one you are in is the whole job.

`tkNewWorkReview -StartDate <d> -EndDate <d>` walks the hub's history and writes a **scaffold**:
every card and growth item in the period, grouped, counted, with checklist progress. It is
accurate and it is a list. It takes a second and it cannot be wrong about what happened.

This prompt is the other half. It reads the same evidence and writes **prose** -- what the work
added up to, which is the thing a list cannot say. Run the command first, then this.

---

## Inputs

1. **Space slugs** -- one or more of the Spaces this machine declares. No slug given means the
   `activeSpace`. An unknown slug: stop and ask, rather than guessing at a near match.
2. **Date range** -- parsed to a concrete `START` and `END` in ISO form.

Run `tkConfig -List` to validate the slugs and to read each Space's `orgType` -- it shows the
resolved settings from every file they can come from (the shipped config, the hub's `hub.json` and
this machine's `config.local.json`), so there is no file to guess at.

---

## Step 1: find the work

Run the scaffold first, and let it do the searching:

```
tkNewWorkReview -StartDate <START> -EndDate <END> -Slugs "<slug>[,<slug>]"
```

It writes `reviews/<slug-set>/<year>/<START>_<END>/review.md` and prints JSON saying what it
scanned. Read that file: it is the inventory, already deduplicated and already grouped, and it is
the machine-readable handoff between the two halves.

If you need to go wider than the scaffold -- it decides by each card's own `**Created:**` and
`**Closed:**` stamps (git history only for a card with no `**Created:**`), so a card whose stamp is
wrong is left out -- the folders are:

| Folder | What is in it |
|---|---|
| `<slug>/archive/` | closed cards |
| `<slug>/current/` | cards still open |
| `growth/current/`, `growth/archive/` | trainings, presentations, goals -- shared across Spaces |

**Deduplication:** a card created in `current/` and moved to `archive/` inside the period appears
in both. Keep the `archive/` entry.

---

## Step 2: read the cards

For each item in the inventory, open the file and take:

- the work-item id, from the filename
- which Space it came from -- growth items belong to no Space
- title, area, status
- **what actually changed, and why** -- the Described Changes and Implementation Details sections
  are there precisely so this pass does not have to guess
- PR numbers and collaborators where the file names them

For a growth item also take its type, dates, hours, format, audience, and the outcome or
milestones -- see [docs/hub/growth.md](../docs/hub/growth.md) for where each of those lives in the
file.

**When the set is large** (50 or more), read in this order: user stories and features first, they
carry the narrative; then a sample of bugs with counts per area; then the growth artifacts in
full. Synthesize bug areas from filenames and counts rather than opening every one.

---

## Step 3: write the summary

`summary.md` is the user's own reference, and completeness beats brevity: the full inventory by
category and by Space, technical specifics, ids, PR numbers, status, counts.

---

## Step 4: write the review

`review.md` is the shareable one. Rewrite the scaffold in place -- keep its frontmatter, replace
its body.

- **First person, active voice.** "I delivered", "I found and fixed".
- **Lead with impact**, not with a task list. The task list is what the scaffold already was.
- **Group by theme** -- feature delivery, quality, engineering practice, security, whatever the
  work actually clustered into -- not by folder.
- Each theme: one paragraph, then three to five bullets.
- Keep a **By the Numbers** section. The scaffold's counts are already correct; do not recount.
- One to two pages rendered. A review nobody finishes is not a review.

**More than one Space:** say in the opening paragraph which Spaces are covered and what each
was, using `orgType` -- client work, a portfolio project, internal tooling, whatever the Space says. Prefix each
bullet with its source Space in bold brackets, `**[first]**`. Growth items are unlabelled: they
belong to the user, not to a Space.

---

## Step 5: where it goes

Slugs sorted and joined with `+`, which is the same folder the scaffold wrote to:

| Selected | Path |
|---|---|
| `[first]` | `reviews/first/<YEAR>/<START>_<END>/` |
| `[first, second]` | `reviews/first+second/<YEAR>/<START>_<END>/` |
| `[first, second, third]` | `reviews/first+second+third/<YEAR>/<START>_<END>/` |

```
<output-path>/
  summary.md
  review.md
```

### The frontmatter is the handoff

```yaml
---
orgs: [first, second]      # selected slugs, sorted; one is still a list
period: <START>_<END>      # copied from the scaffold
generated: <today, ISO>
generator: prose           # the scaffold writes "scaffold"; this pass sets "prose"
---
```

Read `orgs` and `period` off the scaffold rather than re-deriving them, and always write the
`orgs:` **list** form -- never a scalar `org:`, which the readers accept only for older files.

---

## Step 6: hand it back

Say which files you wrote, how many artifacts per Space went into them, and offer to adjust the tone
or the sections. Then the user reads the diff and runs `tkPublishWorkReview`.
