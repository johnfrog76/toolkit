# `design/` and `spec/` in the hub

The hub's designs: the notes that belong to no product yet -- the Studio's **seed drawer**
(D-S3 and D-S10) -- and, since the design lifecycle's reader (L2), the specs they graduate to and the archive each ends in. A design is owned by the product it is
for, and once it has one it lives in that product's repo, in the **same four folders**, read by the Design
tab through the tracker. Until then it is the engineer's, and it lives here.

**This document is the contract**, for the hub and for a product's repo alike (D-DL12: one contract, two
places it applies). One writer creates these files -- the CLI verb `{cliPrefix}NewDesign` (the web's **New
Design Note** runs it through the bridge) -- one more line is written into a note later, the thread, by
`{cliPrefix}NewItem -FromDesign`, and `{cliPrefix}StampDesign` gives a file written before the id existed
its identity. The agent's `GET /api/studio/design` reads the hub's folders and `GET /api/design` a repo's,
both into the same shape. All of it is held to what is written here by `Tests/test_studio.py`,
`Tests/test_design.py` and `tkTestToolkit -Design`, and the state rule by one table both halves assert,
`Tests/fixtures/design/states.json`.

## Where it lives

```text
<promptsRoot>/
  design/            active notes, one per file
    archive/         notes that are finished: dropped, shipped as written, or completed with their spec
  spec/              specs being built or worked
    archive/         specs whose feature is built and documented
  growth/  manager/  reminders/  ...   the other hub-root siblings
  <space>/           one folder per Space -- cards, not designs
```

**The same four folders, by the same names, in a product's repo** (at its root) **and in the hub.** A
repo's names are fixed. The hub's two roots are defaults, not constants: `design` and `spec` are declared
by the hub in `hub.json`'s `folders` block (`folders.design`, `folders.spec`); omit them and they keep the
names above. Both halves resolve them through one accessor -- `hub_folder("design")` in the agent,
`Get-P20HubFolder -Name design` in the CLI. The archive subfolder's name is the card's own, `consts.json`
`folders.archive`.

They are hub-root folders, siblings of the Space folders, because a design that belongs to no product
belongs to no Space either: it is the engineer's, the way the Studio that shows it is the engineer's view
across every Space. (A Space's own `design/` and `spec/` inside its folder -- `globex/spec/` in a
hub -- are the same pattern one level down, D-DL17; `StampDesign -Hub` stamps them, and
`MoveDesign -Hub -Space <slug>` moves them.)

**A hub may not have them yet.** The sample hub `Start` copies out carries all four folders (a live note, a design that graduated, a
completed pair and a dropped one, about RecipeBox); a hub an older `Start` copied out has no `design/`. That is not a fault: the Studio is core from the first run
(D-S13), `GET /api/studio/design` answers 200 with nothing in it and
`exists: false`, the Hub Designs card says `No design/ folder yet` with **Learn more** to this page, and the
first `NewDesign` makes the folder. A hub with `design/` and no `spec/` is read as it is (`structure.spec`
false); a spec folder appears the first time something graduates -- `MoveDesign -To Spec` makes it, the way the archive moves make theirs.

## Naming

```text
<slug>.md             a note
<stem>.spec.md        the spec it became -- the stem is for people; the pairing is the id (below)
```

The slug is the title lowercased, every run of anything but `a-z` and `0-9` one hyphen, trimmed, at most
60 characters: *Board ideas: the next lane* is `board-ideas-the-next-lane.md`. Whatever writes or reads
a file's name holds it to the contract's `studio.noteName` (`consts.json`): one markdown file, starting
with a letter or digit, no path. A file in any of the four folders whose name does not match is not read,
and `README.md` is not a design and is skipped.

## The file

```markdown
---
id: ee925272-9564-4816-8944-e6b39c86339c
description: "What the board could show next"
space: toolkit
---

# Board ideas

> GitHub: https://github.com/<owner>/<repo>/issues/<n>

## Problem

## The idea

## Open questions

## Source

**Created:** 2026-10-01
```

| Part | Written by | Read as |
| --- | --- | --- |
| frontmatter `id:` | `NewDesign` at birth -- a UUID v4, lowercase, hyphenated (`consts.json` `design.idKey` and `design.idRegex`); `StampDesign` for a file that has none. The first frontmatter line. Never changed once written | **the design's identity** (design lifecycle L1): it travels with the note when it is promoted into a repo, and a spec carries the SAME id as the note it graduated from -- that is the pairing, not the stem. The Design tab and the hub drawer group by it and show its first eight characters. **A file with no id is not a design**: it is counted (`notShown`, reason `no id`) and not shown. Two notes with one id, or two specs, are a conflict: all of them counted, none shown, the reason naming the id |
| frontmatter `description:` | `NewDesign -Description` -- one line, in double quotes; a `"` in it is written as `'` | the line under the title in the list. The note's line is the row's when there is a note; a spec standing alone lends its own |
| frontmatter `space:` | `NewDesign -Space <slug>` -- a declared Space; absent when none is named | the Space the note is for: its chip in the list, and where Promote files the thread |
| `# Title` | `NewDesign -Title` | the title, by the rule under this table: a leading `#` heading, else the line under `## Title`, else the file name |
| `> GitHub: <issue url>` | `NewItem -FromDesign` (Promote), after the title, through `Write-CardText` | the design's THREAD (`consts.json` `studio.threadRegex`): the issue's number and repo. Read from the note first, the spec when the note has none. Absent means not promoted yet, and a note published without it reads the same |
| `> Docs: <path>` | on a SPEC, by `MoveDesign -To Complete` (L3), from `-Doc <path>` -- a path that must already exist. Where it is looked for follows where the design is: in a repository, that repository; `-Hub` alone, the hub; **`-Hub -Space <slug>`, the Space's own repository, not the hub** -- the hub holds the design, the product's repository holds its docs. That repository is the one the Space's address names (`spaces[].org`, or its one `projects[]` repo), found on this machine as a clone whose `origin` is that repository: the Space's configured checkout (`spaceCheckouts.<slug>.path`) first, then the folder you stand in, then the nav shortcuts' paths (`aliases.<Name>.path`), then `<wsRoot>/<repo>` (the machine's `wsRoot`, where code repositories are checked out). A `-Doc` missing from that clone is refused, naming the repository and where it is checked out; with no clone here (or a Space whose address names no single GitHub repository) there is nothing to check against, so the path is taken as written and one `Note:` line says why | where the durable part landed, shown on a Complete row (`consts.json` `design.docsLine`) |
| the headings | the template, `templates/DesignNote.template.md` | nothing -- they are for the person writing |
| `**Created:**` | `NewDesign`, the day it ran | nothing yet |
| `**Closed:** yyyy-MM-dd` | the move verb, when a file enters an archive folder, through `Add-ClosedStamp.ps1` | a FACT, not a state: the date on a Complete (the spec's) or Archived (the note's) design |
| `**Outcome:** shipped` or `dropped` | the move verb, on a note archived WITHOUT a spec, and `dropped` on both files of a dropped spec (`consts.json` `stamps.outcome`, `design.outcomes`) | a fact, read only on an Archived design: a deck design that shipped as written, or an idea that never made it. Any other word, or none, reads as plain Archived |
| `## Journey` | the move verb, one dated line per move (L3, D-DL18) | nothing -- a record a person reads, never state |

### How the title is read

A note's or a spec's title -- what the list, the drawer and the reading room show it as -- is read from
the text after the frontmatter, in this order:

1. **The first heading, when it is level one.** `# Board ideas` before any other heading is the title,
   which is what `NewDesign` writes. A `#` line that comes AFTER any other heading is a sentence in the
   body, not the title, and is passed over.
2. **Else the first non-empty line after the first `## Title` heading** -- the shape the studio's design
   contract template writes, the heading on one line and the title on the next. When that line is itself
   a heading (an empty Title section), there is no title here.
3. **Else the file's name**, `gym-llm-workouts.md`.

A heading is a line of one to six `#` and then a space or a tab (or nothing). The frontmatter is never
read for a title. Both halves implement the rule -- `Get-P20DesignTitle` in
`Scripts/Read-DesignTree.ps1` and `doc_title` (through `parse_doc`) in `agent/ado/design.py`, which the
hub drawer and a repo's Design tab both read through -- and `Tests/fixtures/design/titles.json` pins it
row for row from both suites (`tkTestToolkit -Design`, `Tests/test_design.py`).

## State -- derived, never stored

The unit is the **design**: one id, a note, and at most one spec. Its state is read from WHERE the files
are, by one rule both halves implement (`design_state` in `agent/ado/design.py`;
`Resolve-P20DesignState` in `Scripts/Read-DesignTree.ps1`), pinned row for row by
`Tests/fixtures/design/states.json`:

| Note is in | Spec with the same id | State |
| --- | --- | --- |
| `design/` | none | **Design** |
| `design/` | in `spec/` | **Spec** |
| `design/archive/` | in `spec/archive/` | **Complete** |
| `design/archive/` | none | **Archived** |
| `design/archive/` | in `spec/archive/` with `**Outcome:** dropped` | **Archived**, outcome dropped -- a spec dropped before it was built (`MoveDesign -To Archive -Dropped`); the spec's `**Closed:**` date is the design's |
| `design/` | in `spec/archive/` | **Complete** -- the spec's folder wins; the row says the note was left behind |
| `design/archive/` | in `spec/` | **Spec** -- the same, the other way round |
| none | in `spec/` or `spec/archive/` | **Spec** / **Complete** -- a spec may stand without a note |

The four names are `consts.json` `design.states`, in that order -- the road's order, which is the order the
list groups them in. `Closed` is a fact about a design that has reached an archive state (`""` for Design
and Spec: a note archived before its spec is still a Spec), and `Outcome` only about an Archived one (a
Complete design needs none: its spec was built). An archived spec stamped `**Outcome:** dropped` is the one
spec that reads Archived rather than Complete: `MoveDesign <id> -To Archive -Dropped -Reason <text>` on a
Spec archives the spec and its note together, stamps both, and appends the reason to the note's Journey;
without `-Dropped` a live spec still refuses `-To Archive`. A design archived before this rule keeps its state.

**What the agent serves.** `GET /api/design` (a repo, through `gh`) and `GET /api/studio/design` (the hub,
from disk) answer the same shape: `designs` -- one row per id, `{ id, short, state, title, description,
thread, thread_number, thread_repo, closed, outcome, mismatch, docs, note, spec }`, in road order then by
title -- plus `notShown: [{ path, reason }]` and `structure: { design, spec }` (which roots exist), so the
web decides nothing. A hub row carries two more words, `space` and `thread_space`. **Every row carries its
`cards`** (the Toolkit card's C3): `[{ file, id, title, status, space, archived }]`, every card whose
`> Design:` line names the design's id -- `current/` first, then `archive/` read as Done. For a repo they are
the active Space's cards; for the hub, every declared Space's, because a design that belongs to no product
can be worked from any of them. Derived by reading the cards on every request (the repo's listing stays
cached; its cards do not), stored nowhere. How a repo's listing is cached: for 60 seconds per agent, and
under that each file's parsed row -- its id, title, description, stamps, Docs and thread line, never its
body -- on disk by the blob's sha, so a restart asks GitHub for the folders' names and shas alone and fetches
the text of only a note that changed; a note's body is kept the same way once it has been opened
([the agent's cache](../CONFIGURATION.md#the-agents-cache)). A hand-written `> Spec:` line carries no id, so it binds nothing
here ([the card](cards.md)).
Only a live note names its Space: a row whose note is archived (Complete, Archived) has `space` empty even when the note's frontmatter still says `space: demo`, because the chip belongs to the list a person is still working from; `thread_space` is read for every row. The hub's answer keeps
`items` and `count` as before: the live notes in `design/`, which the + and Promote read. One document is
read by its path: `GET /api/design/{path}` and `GET /api/studio/design/{path}` take `design/x.md`,
`design/archive/x.md`, `spec/x.spec.md` or `spec/archive/x.spec.md` (a bare name is still the live note),
and refuse any other path with a 404 before anything is read.

**What the person sees.** The Design tab and the Hub Designs card draw ONE list grouped by state --
Design, Spec, Complete, Archived -- with Complete and Archived collapsed to a count until opened or
searched. A row is the design: its title, description, state, short id and thread chip, and under them the
cards worked against it -- each its id and state, opening the card when it is in this Space's `current/`,
named only when it is archived or another Space's; a Complete row's `Docs:` line opens the document it names in the Docs tab (on the Hub Designs card, when the design names the Space you are in, else it is a caption); in Spec and Complete the repo's row opens the spec with
the note in its menu. A hub row's menu carries its road's moves (`MoveDesign -Hub`); a repo's row carries the same
moves where this machine names the Space's checkout (`spaceCheckouts.<slug>.path`), staged in that clone by
`MoveDesign -Space <slug>` and never committed -- and where it does not, the tab's foot names the setting
([Studio](../modules/studio.md), "The web UI"). A card names its design with `{cliPrefix}NewPrompt -Design <name|id>`. The archive is read in the same room as
a live note, with its Closed date and outcome. No `design/` at all: the empty state says what the four
folders would give and links here (**Learn more**). Files with no id: one line under the list, counted,
naming `StampDesign` (or `StampDesign -Hub`) and linking here. Never inference, never a blank (D-DL11).

**The library** (4.6, L2b). One box over the Design tab (the filter drawer's) and one over Hub Designs:
it filters on title, description and id at once, across every state, and opens the collapsed groups that
have a match. **Search inside** runs the same words over the documents' text, on the button only, after
the groups are drawn: on disk for the hub's folders (`GET /api/studio/design/search?q=`), and for a repo
through the tracker's code search scoped to the four folders (`GET /api/design/search?q=`), which reads the
default branch only and lags a push by minutes -- the note under the results says so, and a search that
cannot run says why in a row rather than holding the tab. A hit names the design, its state and the
matching line, and opens its room; a file with no id is still a hit, with no state. The **Archived** group
filters by outcome: shipped, dropped, or nothing said.

**The CLI names it.** `{cliPrefix}Env` and `{cliPrefix}Menu -All` carry a `Design lifecycle` row: `on` when
the repository you stand in has `design/` and every file in the four folders is stamped, `off` with the
count of unstamped files when some are not, `not configured` when there is no `design/` to read -- and the
hub's own count in the note. Its question is `How do I keep a design with its product?`.

**Identity is the `id:` line, and `StampDesign` is how a file gets one.** `NewDesign` writes it at birth.
A note written before that, or by hand, has none; `{cliPrefix}StampDesign` adds one to every markdown
file in the four folders that lacks it (`-Hub` for the hub's), creating a frontmatter block where there
is none, and gives a spec the id of the note whose file stem it shares. It never changes an id that is
present, never writes a file it did not change, and keeps each file's line endings.

The bytes are the house's: UTF-8, no BOM, LF for the file `NewDesign` creates; every edit keeps whatever
endings the file has (`Write-CardText`, AGENTS.md "One byte contract for a card"). A note carries no link
into the Toolkit package, so `Repair-CardLinks` does not apply to it.

**Never overwritten.** `NewDesign` refuses a title whose file exists, with exit 2 and a sentence that
names it (AGENTS.md, "current/ is protected"). A design leaves a folder only through the move verb (L3,
`MoveDesign`), which never overwrites in either folder.

## Examples

`Tests/fixtures/hub/design/board-ideas.md` is a promoted, stamped note the agent's tests and the smoke run
read. `Tests/fixtures/design/states.json` is every row of the state table, with the files' footer lines.
