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
| `> GitHub: <issue url>` | `NewItem -FromDesign` (Promote), after the title, through `Write-CardText` | the design's THREAD (`consts.json` `studio.threadRegex`): the issue's number and repo, read from the address on the same line as `> GitHub:`. Read from the note first, the spec when the note has none. Absent means not promoted yet, and a note published without it reads the same |
| `> Docs: <path>` | on a SPEC, by `MoveDesign -To Complete` (L3), from `-Doc <path>` -- a path that must already exist. The line goes under the title the title rule finds (the leading `#` heading, or the title line under `## Title`), else first in the body after the frontmatter, a blank line either side -- never above the frontmatter, which would cost the spec its id; a spec that already has one keeps it. Where it is looked for follows where the design is: in a repository, that repository; `-Hub` alone, the hub; **`-Hub -Space <slug>`, the Space's own repository, not the hub** -- the hub holds the design, the product's repository holds its docs. That repository is the one the Space's address names (`spaces[].org`, or its one `projects[]` repo; on Azure DevOps the organisation, project and repository), found on this machine as a clone whose `origin` is that repository: the Space's configured checkout (`spaceCheckouts.<slug>.path`) first, then the folder you stand in, then the nav shortcuts' paths (`aliases.<Name>.path`), then `<wsRoot>/<repo>` (the machine's `wsRoot`, where code repositories are checked out). A `-Doc` missing from that clone is refused, naming the repository and where it is checked out; with no clone here (or a Space whose address names no single repository) there is nothing to check against, so the path is taken as written and one `Note:` line says why. A person may type it on a live spec ahead of the move ([Marking a live design finished](#marking-a-live-design-finished)) | where the durable part landed, shown on a Complete row (`consts.json` `design.docsLine`; `design.docsRegex` reads it back); also read on a live design, as ready. **The path is what follows `> Docs:` on the same line**: an empty `> Docs:` line names no document, and the line below it is never read as one, with either line ending |
| the headings | the template, `templates/DesignNote.template.md` | nothing -- they are for the person writing |
| `**Created:**` | `NewDesign`, the day it ran | nothing yet |
| `**Closed:** yyyy-MM-dd` | the move verb, when a file enters an archive folder, through `Add-ClosedStamp.ps1` | a FACT, not a state: the date on a Complete (the spec's) or Archived (the note's) design, read from the stamp's own line |
| `**Outcome:** shipped` or `dropped` | the move verb, on a note archived WITHOUT a spec, and `dropped` on both files of a dropped spec (`consts.json` `stamps.outcome`, `design.outcomes`); `shipped` may be typed by a person on a live note ahead of the move | the outcome, a fact read only on an Archived design: a deck design that shipped as written, or an idea that never made it. Any other word, or none, reads as plain Archived. **The word is what follows the stamp on the same line**: a bare `**Outcome:**` line is no outcome, and a line below it reading `shipped` is never taken for its word, with either line ending. Also read on a live design, as ready |
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
thread, thread_number, thread_repo, closed, outcome, mismatch, docs, ready, note, spec }`, in road order then by
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
`MoveDesign -Space <slug>` and never committed -- and there the tab reads that clone's working tree, so the
moved row shows on the re-read; where it does not, the tab reads GitHub and its foot names the setting
([Studio](../modules/studio.md), "The web UI"). A card names its design with `{cliPrefix}NewPrompt -Design <name|id>`. The archive is read in the same room as
a live note, with its Closed date and outcome. No `design/` at all: the empty state says what the four
folders would give and links here (**Learn more**). Files with no id: one line under the list, counted,
naming `StampDesign` (or `StampDesign -Hub`) and linking here. Never inference, never a blank (D-DL11).

**The library**, the design lifecycle's search across designs. One box over the Design tab (the filter drawer's) and one over Hub Designs:
it filters on the title, the description, the id and the file names of the design's note and spec at once, every word in any order, across every state -- so a design can be found by the file name its row prints -- and opens the collapsed groups that
have a match. **Search inside** runs the same words over the documents' text, on the button only, after
the groups are drawn: on disk for the hub's folders (`GET /api/studio/design/search?q=`); for a repo
(`GET /api/design/search?q=`), on disk in the Space's checkout where this machine names one -- its working
tree, on the branch it has checked out -- and otherwise through the tracker's code search scoped to the four
folders, which reads the default branch only and lags a push by minutes. The note under the results says
which it searched, and a search that cannot run says why in a row rather than holding the tab. A hit names the design, its state and the
matching line, and opens its room; a file with no id is still a hit, with no state. The **Archived** group
filters by outcome: shipped, dropped, or nothing said.

**The CLI names it.** `{cliPrefix}Env` and `{cliPrefix}Menu -All` carry a `Design lifecycle` row: `on` when
the repository you stand in has `design/` and every file in the four folders is stamped, `off` with the
count of unstamped files when some are not, `not configured` when there is no `design/` to read -- and the
hub's own count in the note. Beside each count the note says `N ready` when N designs there are
[marked finished](#marking-a-live-design-finished) (`3 designs in this repository, 2 ready; the hub: 15
designs, 1 ready`); with none marked it adds nothing, so the row reads as it did before. Its question is
`How do I keep a design with its product?`.

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

**A move never contradicts the file.** `MoveDesign` never rewrites an `**Outcome:**` or `> Docs:` line a
file already carries, so a move whose own word or document differs from one is refused -- exit 2, one
sentence naming the file and the line, and a hint to edit the line or run the move that matches it --
before anything is moved, stamped or printed as done, `-WhatIf` included:

| The file already carries | Refused |
| --- | --- |
| `**Outcome:** dropped` on the note | `-To Archive` (it would record shipped) |
| `**Outcome:** shipped` on the note, or on the spec of a Spec | `-To Archive -Dropped` |
| an `**Outcome:**` whose word is neither `shipped` nor `dropped` (`Shipped 2026-11-20`, `maybe`, nothing) | either archive -- the line reads as no outcome while the Journey would name one; make it one of the two words or take it out |
| `**Outcome:** dropped` on the spec or the note | `-To Complete` (it would read Archived while the Journey says built) |
| `> Docs: <path>` naming another path than `-Doc` | `-To Complete` |
| a spec already in `spec/archive/`, the note still in `design/` | `-To Archive` (and `-To Archive -Dropped` when the spec was completed) -- the spec's move already recorded what became of the design; the hint names the move that finishes it, below |
| that shape, and a `-Doc` other than the spec's `> Docs:` line, or any `-Doc` when the spec has none | `-To Complete` -- finishing the completion changes nothing in the spec |

A line that agrees with the move -- the outcome word ignoring case, the same `-Doc` path -- is kept and not
written twice, and the move's output says `keep` for it. After any move, the word in the file, the word
printed and the word in the note's Journey are the same.

**Finishing the move a spec already made.** A design can be left half moved: its spec in `spec/archive/`,
its note still in `design/`. The note then follows its spec, through the verb like every other move:

- **A completed spec:** `{cliPrefix}MoveDesign <id> -To Complete`, with no `-Doc`, since the spec's own
  `> Docs:` line already names the document. A `-Doc` that is the same path is accepted and changes nothing.
- **A spec archived `dropped`:** `{cliPrefix}MoveDesign <id> -To Archive -Dropped -Reason <text>`, which
  also stamps `**Outcome:** dropped` on the note.

Either way the note moves to `design/archive/` and is stamped `**Closed:**` with the date the spec carries,
not today's; a spec with no `**Closed:**` line leaves the note stamped today, said in one `Note:` line.
The Journey line says the note followed its spec (`- <today> Complete: this note followed its spec,
completed <date>. The docs are <path>. ...`), the spec is not touched, and the design then reads with no
mismatch. `-WhatIf` prints the same move, stamp and Journey line and writes nothing.

## Marking a live design finished

A live design can say it is finished before anything moves, with one line typed by whoever decides what
the design means. The line is one the file contract already has (the `> Docs:` and `**Outcome:**` rows
of [The file](#the-file)); what is new is that both halves read it on a live design, as **ready**: a
fact beside the state, like `closed` and `outcome`, never a fifth state.

- **A note with no spec:** on its own line in the footer, beside `**Created:**`, type
  `**Outcome:** shipped` once the design shipped as written. The word is compared ignoring case, and
  nothing may follow it: `shipped 2026-11-20` or `shipped. prose` is not ready. The date is the
  `**Closed:**` stamp the move writes.
- **A live spec:** under its title, type `> Docs: <path>` -- the document the durable part landed in,
  relative to the root of the repository that holds the docs; for a hub Space folder, that is the Space's
  repository, not the hub. The reader does not check the path exists: `MoveDesign` does, when it runs.
- **The mark is on the token's own line.** The word, or the path, is what follows `**Outcome:**` or
  `> Docs:` on the same line. A token with nothing after it on its line marks nothing: a bare
  `**Outcome:**` line above a line reading `shipped`, or an empty `> Docs:` line above a paragraph, is
  not ready, with either line ending (`Tests/fixtures/parsers/same-line.json` holds both halves to it).
  `MoveDesign` reads a bare `**Outcome:**` line as no outcome too: `-To Archive` refuses it as it refuses
  any line that is neither word, and `-Ready` lists the design as held.
- **Ready is derived** by the state rule both halves implement, and pinned by the same table,
  `Tests/fixtures/design/states.json`: a **Design** with no spec at all whose note's first
  `**Outcome:**` line says `shipped`; or a **Spec** whose live spec carries a non-empty `> Docs:` line,
  when neither file's first `**Outcome:**` line says `dropped`. A note marked `shipped` whose spec is
  live is not ready, nor is any archived design. A design with neither line reads exactly as before.
- **Nothing moves until `MoveDesign` runs.** A ready Design implies `MoveDesign <id> -To Archive`; a
  ready Spec, `MoveDesign <id> -To Complete -Doc <the Docs path>`, and the move keeps the line it finds.
- **`dropped` is never written ahead of time.** Dropping a design needs its reason: run
  `MoveDesign <id> -To Archive -Dropped -Reason <text>`. A live note marked `dropped` is not ready.

The fact is on the model: `Ready` on `Read-P20DesignTree`'s row in the CLI, `ready` on each row
`GET /api/design` and `GET /api/studio/design` serve. The CLI reads it in two places: the `Design
lifecycle` row's `N ready` (above, "The CLI names it"), and `{cliPrefix}MoveDesign -Ready`, below. No
badge draws it on the Design tab yet, and nothing moves a ready design unattended: a person runs the call.
The templates carry no hint for either line: a hint holding the token at column 0 would read as the line
itself.

### Listing what is ready: `MoveDesign -Ready`

`{cliPrefix}MoveDesign -Ready` is a read. It moves nothing and writes nothing, with or without `-WhatIf`,
and exits 0 whether or not anything is ready. It takes the verb's scope flags and nothing else: none for
the repository you stand in, `-Hub`, `-Hub -Space <slug>`, or `-Space <slug>` for that Space's checkout.
A design name, `-To`, `-Doc`, `-Dropped` or `-Reason` beside it is a stated refusal (exit 2): `-Ready`
only lists.

It prints the designs the rule says are ready, each with the exact call that moves it, then the designs
that carry a mark but are held, each with why, then one count line. With nothing ready and nothing held it
prints one line saying so, under the line that names where it read. Each ready call is first run through
`MoveDesign`'s own `-WhatIf`, so a call the verb would refuse is never printed as ready: that design is
held, with the verb's own sentence. A line under ready is one that can be run as printed.

| The design | Listed | What the line says |
| --- | --- | --- |
| a live note, no spec, `**Outcome:** shipped` | ready | `MoveDesign <id> -To Archive [flags]` |
| a live spec with `> Docs: <path>` (a live or archived note, or none) | ready | `MoveDesign <id> -To Complete -Doc "<path>" [flags]`, the path exactly as the line has it |
| either, with open cards in a Space's `current/` naming its id | ready, with a note | the call, then the open cards by name. The mark is the decision; the move does not wait for them |
| a Space-folder spec (`-Hub -Space`) whose Space's repository has no clone here | ready, with a note | the call, then `MoveDesign`'s own `Note:` sentence: the path is taken as written, not checked |
| a live spec whose note is already in `design/archive/` | ready, with a note | the call, then that the completion journals onto the archived note |
| a note left in `design/` after its spec was completed (Complete) | ready, with a note | `MoveDesign <id> -To Complete [flags]`, with no `-Doc`, then that the move finishes the completion and changes nothing in the spec |
| a ready design whose call `MoveDesign` would refuse (the Docs path missing where it can be checked, a file of that name already archived) | held | `MoveDesign would refuse it:` and the verb's own sentence |
| a live note marked `dropped` | held | that dropping is a decision with its reason, and the `-To Archive -Dropped -Reason` call to make it |
| a live note whose `**Outcome:**` is neither word (`maybe`, `shipped 2026-11-20`) | held | that the line is no mark, and the line that would be |
| a live spec with a Docs line, and a note or spec marked `dropped` | held | that the two marks disagree |
| a live spec with no Docs line, and an `**Outcome:**` line on the note or the spec | held | that a Spec is marked finished by a Docs line in the spec |
| a note left in `design/` after its spec was archived `dropped` (Archived) | held | the state, both paths, and the `-To Archive -Dropped -Reason` call that finishes the drop |
| a live design with no mark, or any archived design | not listed | |

Every call names the design by its full id and carries the same scope flags `-Ready` was given.
`-AsJson` prints the same lists as one JSON line, for a script:

```json
{ "ready": [{ "id": "...", "title": "...", "state": "Design", "call": "tkMoveDesign <id> -To Archive -Hub",
              "args": ["<id>", "-To", "Archive", "-Hub"], "notes": [] }],
  "held":  [{ "id": "...", "title": "...", "state": "Spec", "reason": "..." }],
  "counts": { "ready": 1, "held": 1 } }
```

`args` is the call's arguments after the verb, one element each, so a caller need not parse `call`. The
`Design lifecycle` row's `N ready` counts what the rule says; `-Ready` may hold one of those when
`MoveDesign` would refuse its call, so its own count can be lower, and it also lists a note left behind
after its spec completed, which the rule does not call ready (the design is already Complete), so its
count can be higher.

## Examples

`Tests/fixtures/hub/design/board-ideas.md` is a promoted, stamped note the agent's tests and the smoke run
read. `Tests/fixtures/design/states.json` is every row of the state table, with the files' footer lines.
