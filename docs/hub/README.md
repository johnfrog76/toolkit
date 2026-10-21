# The hub -- what is in it, and which document owns each shape

The hub is a folder of plain files, and the files ARE the data: there is no database, and nothing here
needs the Toolkit installed to be read. It lives wherever `promptsRoot` says -- never inside the Toolkit's
own checkout -- and it need not be a git repository (`storeSync`, [Configuration](../CONFIGURATION.md)).

```text
<promptsRoot>/
  hub.json                  the hub's own orgs, folder names and storeSync   (optional)
  <promptsFolder>/          ONE PER ORG -- its cards
    current/  backlog/  archive/   in play, planned, done
    assets/<card key>/      a card's pictures -- cover.png, before.png (Cover)
  growth/                   trainings, presentations, goals        -- the engineer's, not an org's
    current/  archive/
  manager/                  1:1 sessions                           -- the engineer's
    current/  archive/
  reviews/                  generated work reviews, by org set and date range
  resume/                   resume.md
  reminders/                reminders                              -- the engineer's
    current/  archive/
  design/                   design notes that belong to no product yet -- the engineer's (Studio)
    archive/
  spec/                     the hub's specs, the four-folder road a product keeps too
    archive/
  agentic/                  the hub's own agentic workflow prompts, if it keeps any
```

| Folder | What one file is | Scope | The shape's owner | Example |
| --- | --- | --- | --- | --- |
| `<org>/current`, `<org>/backlog`, `<org>/archive` | **a card** -- one piece of work; the product's core. `backlog/` holds the planned ones, not yet in play | the org | [`cards.md`](cards.md) | `samples/hub/demo/` |
| `<org>/assets/<card key>/` | a card's picture -- its cover, or the before of a before/after -- named by the card's `**Cover:**` / `**Before:**` line | the org, beside its cards | [`cards.md`](cards.md#a-cards-pictures----spaceassets) | `Tests/fixtures/parsers/covers.json` |
| `growth/` | a training, a presentation or a goal | the engineer | [`growth.md`](growth.md) | `samples/hub/growth/`, `Tests/fixtures/hub/growth/` |
| `manager/` | one 1:1 session, through plan, prep and retro | the engineer | [`manager.md`](manager.md) | `Tests/fixtures/hub/manager/` |
| `reviews/` | `reviews/<slug-set>/<year>/<start>_<end>/review.md` -- a generated work review; `<slug-set>` is org slugs joined by `+`, and membership is SET membership, never a substring | the engineer | [the growth module](../modules/growth.md) (`NewWorkReview`); `consts.json` `reviews` | `samples/hub/reviews/` |
| `resume/` | `resume.md` | the engineer | [the growth module](../modules/growth.md) (`UpdateResume`) | `samples/hub/resume/` |
| `reminders/` | one reminder -- a note to yourself with a due date -- `current/` then `archive/` | the engineer | [`reminders.md`](reminders.md) | `samples/hub/reminders/`, `Tests/fixtures/hub/reminders/` |
| `design/`, `design/archive/`, `spec/`, `spec/archive/` | one design note, or the spec it graduated to -- the same four folders a product's repo keeps, and the same state read from where the files are (Design, Spec, Complete, Archived) | the engineer | [`design.md`](design.md) | `Tests/fixtures/hub/design/`, `Tests/fixtures/design/states.json` |
| `agentic/` | one prompt of yours, `<name>.prompt.md` -- listed on the Studio's Prompts card under **Your hub**, on every machine | the engineer | [A prompt of yours](#a-prompt-of-yours----agentic) below; [`agentic/README.md`](../../agentic/README.md) | `agentic/` in the package -- the shipped ones are the same shape |
| `hub.json` | the hub's manifest: its orgs, the eight folder names above, `storeSync`, and nothing else | the hub | [Configuration](../CONFIGURATION.md#the-hub-declares-its-orgs) | `samples/hub/hub.json` |

**Two scopes, and the difference is real.** A card belongs to an ORG: switch org and you see a different
board. Everything at the hub's root belongs to the ENGINEER: a training you took does not stop having
happened when an engagement ends, which is why `growth/` and `manager/` are siblings of the org folders
and not inside one, and why their feature flags cannot be set by an org.

**The folder names at the root are defaults, not constants** -- `hub.json`'s `folders` block renames them,
and both halves resolve each through one accessor (`hub_folder()` in the agent, `Get-P20HubFolder` in the
CLI). `current` and `archive` are constants (`consts.json` `folders`).

**Three rules hold for every folder here:**

1. **Status is read from the file's own words, never stored beside it.** A card's state is derived from
   tokens in it; a growth item's from its Status or Delivered line; a session's from its stage. Each
   shape's document has the exact rule, and each rule has a table-driven test.
2. **Files outlive their templates.** A reader must accept what earlier templates wrote, not only the
   current one -- a presentation from April heads its outcome `## Outcome`, one from July
   `## Outcome & Follow-Up`, and both are read.
3. **One writer, one byte contract.** Everything the tool writes goes through `Write-CardText`: UTF-8, no
   BOM, LF for a file it creates, the file's own endings for one it edits. Nothing the tool creates
   overwrites a file that exists.

## A prompt of yours -- `agentic/`

A file in the hub's `agentic/` is a prompt for your assistant, `<name>.prompt.md`, the shape the shipped
ones have ([`agentic/README.md`](../../agentic/README.md), "The shape of a prompt"). The Studio's Prompts
card reads every prompt into ONE record, whether it is ToolKit's, yours or the Space's, and the row shows
those four fields and nothing else:

| Field | Read from |
| --- | --- |
| title | the frontmatter's `title`, else the one `#` heading, else the file name |
| purpose | the frontmatter's `description` -- one sentence |
| owner | where the file lives -- a prompt here is **yours**. Worked out by the agent; a file never says it |
| category | the frontmatter's `category` line; `uncategorized` when there is none |

To give one a category, add the line to its frontmatter -- one of the vocabulary the shipped prompts use
(`ship`, `review`, `tracker`, `growth`, `meetings`, `rituals`, `design`) keeps it beside them:

```markdown
---
description: "Reconstruct last week from the cards and the commits."
category: growth
---

# Reconstruct a week
```

Nothing else is required. A prompt here has no index entry, so it is listed for every way of working, and
a copy under a shipped prompt's name in `agenticExtensionPath` runs instead of the shipped one
([`agentic/README.md`](../../agentic/README.md), "Tuning a prompt for one machine").
