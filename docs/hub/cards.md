# `<org>/current/` and `<org>/archive/` — the card

One file per piece of work, and the file is the record. This document is the shape's owner. It is the
**data model of the product**: every verb writes or reads this file, the agent serves it as fields, the
board draws it, and Daily is built from it. This is where a reader starts; the documents that own a
part of it keep their subjects and are linked from here -- `docs/CLI.md` (state, dates, bytes),
`AGENTS.md` (the id rule, the links), `consts.json` (the
tokens) and the templates.

**A card is a prompt.** It is called a prompt file because an agent works from it, and a card because a
person plans, tracks and accounts with it. Same file. "Custom" is not a concept in the code: a card that
did not come from Azure DevOps is a card with no link on it, and nothing else about it differs.

## Where it lives

```text
<promptsRoot>/                     the hub -- config's promptsRoot, never this repo's parent folder
  hub.json                         the hub's own orgs and folder names (optional)
  <promptsFolder>/                 one per org -- spaces[].promptsFolder, e.g. demo/
    current/                       cards in flight
      214-search-returns-duplicates.prompt.md
      Spike-K7M2-photo-import.prompt.md
    archive/                       cards that are done
      198-fix-the-export.prompt.md
      198-fix-the-export-r1.prompt.md      an earlier round of the same card
    assets/                        what a card keeps that is not text -- see "A card's pictures"
      214/before.png  214/cover.png
```

- `current` and `archive` are `consts.json` `folders` -- a contract, not configuration.
- **A card travels one way**: `current/` -> `archive/`, through `Archive`, and nothing ever overwrites a
  card in either folder. Work that comes back is a NEW card; `Archive` keeps every round as `-r1`, `-r2`
  (matched by the card's ID, so a retitled card is still the same card and each round keeps its own slug)
  (AGENTS.md, "`current/` is protected").
- **Where the file is decides whether it is open.** A card in `archive/` is Done whatever it says inside.

## The filename

```text
[<type prefix>]<id>-<slug>.prompt.md
```

| Part | Rule |
| --- | --- |
| type prefix | From `workItemTypes.<Type>.filePrefix` in config, matched ignoring case: `US-`, `Task`, `Feat-`, `Spike-`, and **nothing** for a Bug. House style, from ~180 archived cards -- config, not code |
| id | **A string.** A work item number (`214`), or the four-character id of a card with no work item (`K7M2`: uppercase, at least one letter and one digit, from an alphabet with no look-alikes). `consts.json` `regex.cardId` |
| slug | The title, lower-cased and dashed. Decoration: nothing parses it |

**One rule reads an id out of a filename** -- `Scripts/Resolve-CardName.ps1` (`Get-P20CardId`), mirrored by
`card_id()` in `agent/core/parsers.py` and held to it by one shared table,
`Tests/fixtures/parsers/card-ids.json`. A file with no id by that rule **is not a card**: it is never
billed, and the status route serves it with `id: null` and no `type` -- it is still LISTED, because a
folder read does not hide a person's file from them. An id is never a substring: `39` does
not match `Task139` (AGENTS.md, "An id is not a substring").

## Inside the file

Three parts, in this order. Only the first and the last are parsed; the middle is for people and agents.

### 1. The heading -- type, id and name

```markdown
# Bug 214: Search returns duplicates when tags overlap
```

`# <Type> <id>: <name>`. **The heading is the record of a card's TYPE** -- the filename prefix is only a
filing convention. The type is matched against the configured `workItemTypes` names, so a team's own type
(`Chore`) is known once config names it. A leading emoji is ignored. A file whose heading does not fit
still has a `title`; it has no `type` and no `name`.

### 2. The sections -- by type, from the template

| Type | Template | Sections, in order |
| --- | --- | --- |
| Bug | `Bug.template.md` | Branch; Git; Repro; Summary; File Changes; Described Changes; Acceptance Criteria; Progress; Questions / Blockers |
| Task | `Task.template.md` | Branch; Git; Context; Summary; Described Changes; Implementation Details; Acceptance Criteria; Questions / Blockers |
| User Story | `UserStory.template.md` | Branch; Git; Summary; Scope; Implementation Details; Described Changes; Acceptance Criteria; Verification; Progress; Questions / Blockers |
| Feature | `Feature.template.md` | Branch; Git; Work Item Info; Summary; Scope; Described Changes; Implementation Details; Acceptance Criteria; Progress; Questions / Blockers |
| Spike | `Spike.template.md` | Branch; Git; Summary; Question; Findings; Recommendation; Done when; Questions / Blockers |
| Meeting | `Meeting.template.md` | Branch; Git; When; Where; Who; Purpose; Notes; Outcomes; Follow-ups; Questions / Blockers -- a meeting you ATTENDED, written after the fact (`NewPrompt -Date` puts `**Created:**` on the day it was); a meeting you RUN is the Meeting Agenda Planner's, under `manager/` |

Sections are documents, not a schema: nothing fails if one is missing or renamed, **except the things
below, which ARE parsed wherever they appear in the file.**

| What | Exactly | Who writes it | What reads it |
| --- | --- | --- | --- |
| A commit | a bullet that starts with a 7+ character hex hash: `- a41c2e9 message`. **Its own line** -- an inline or comma-separated list is not seen. `regex.commitBullet` | `ThreadHash`, under `## Git` / `Commits:` | state: **In Progress** |
| The pull request | a line that starts `PR URL: https://`. `tokens.prUrl` | `NewPR`, `GetPRComments` | state: **Code Review**; the card's `pr_url` |
| A person's Started | the footer line `**Started:** yyyy-MM-dd`. `stamps.started`, `regex.startedLine` | `Move -To InProgress`, a drop on the board, or a hand | state: **In Progress** -- for a card with nothing checked in |
| A person's Review | the footer line `**Review:** yyyy-MM-dd`. `stamps.review`, `regex.reviewLine` | `Move -To CodeReview`, a drop on the board, or a hand | state: **Code Review** -- for a card with no pull request; "look at this thing" |
| A previous round | a line that starts `> Previous round:` and a path relative to the card's own folder, directly under `> Template:` -- `../archive/Task113-title-r2.prompt.md`. `tokens.previousRound` | `NewPrompt`, when the id already has rounds in `archive/`; `Repair-CardLinks.ps1` re-aims it when `Archive` renames a round | the card's `previous_round` (a path, else `null`). **Not state**; the web does not draw it yet |
| The design it was worked against | one header line under `> Template:` (after `> Previous round:` when there is one): `> Design: [<title>](<link>) <id>` -- the design's own title, a link (relative to the card's folder for a hub design, its GitHub page for a repo design) and the design's whole id (`design.idRegex`). `tokens.design`, read by `design.cardLineRegex`. **The corpus's hand-written `> Spec: [<title>](<link>) <words>` (16 cards, `tokens.spec`) is read as written and never rewritten**: its link is shown, and it has no id to resolve. A card names ONE design -- its first Design line, else its first Spec line | `NewPrompt -Design <name\|id>` ([CLI](../CLI.md)); a hand, for an existing card | the card's `design`; the chip on the card page; and every design's row, which lists the cards whose line carries its id (`GET /api/design`, `GET /api/studio/design`). **Not state**: the link may go stale when the design moves -- the id is what is resolved. `Get-P20CardDesign` (`Scripts/Read-DesignTree.ps1`) and `card_design()` (`agent/core/parsers.py`) are held to one table, `Tests/fixtures/parsers/design-lines.json` |
| Review rounds | the heading `## PR Review Comments`, then one block per round. `tokens.prReviewHeading` | `GetPRComments` | the PR Comments card and page. **Not state**: the `PR URL:` LINE is the gate into Code Review, not the presence of comments |
| Checkboxes | every `- [ ]` and `- [x]`, anywhere in the file | a person, or an agent working the card | `progress` (`2/4`), `checked`, `total` -- the bar on the card |

`- (pending)` under `Commits:` is a placeholder, not a commit; `ThreadHash` removes it when it writes a
real one.

### 3. The footer -- one fact per line

After a `---` rule, bold-label lines. **This is the part of the model that is stored rather than derived.**

```markdown
---

**Sprint:** RecipeBox\Sprint 8
**Story Points:** 2
**ADO Link:** https://dev.azure.com/YOUR-ADO-ORG/RecipeBox/_workitems/edit/214
**Billable:** no
**Before:** ../assets/214/before.png
**Cover:** ../assets/214/cover.png
**Created:** 2026-09-14
**Closed:** 2026-09-18
```

| Line | Means | Written by | Read by |
| --- | --- | --- | --- |
| `**Sprint:**` | The iteration path. Only the LAST segment is shown (`Sprint 8`) | `NewPrompt`, from the work item; `(not linked)` text offline | the board's Sprint filter; the card's tag |
| `**Story Points:**` | As the work item had it | `NewPrompt` | people |
| `**ADO Link:**` | The work item's address. **An `https://` value here is what makes a card `linked`**; offline it reads `(not linked -- created offline with -Title)` | `NewPrompt`; and `NewItem -FromCard`, which publishes a card made offline as a GitHub issue and writes the issue's URL here, through `Set-P20CardLine` (the card keeps its id) | `linked`, `ado_url`, the repo filter (a card with no ADO link is never hidden by it), *Open in ADO* |
| `**Billable:**` | `no` takes the card off Daily and the standup. **No line means billable** -- "billable again" removes the line | `Billable -No`, through `Set-P20CardLine` | Daily and Team Agile's standup (one reader a half: `card_billable`, `Test-P20CardBillable`); the *Not billable* tag. `stamps.billable` |
| `**Cover:**` | The card's picture: a path relative to the card's folder, `../assets/<card key>/cover.<ext>`. **No line means no picture**; a line whose file is missing, or that resolves outside the Space's `assets/`, reads as none too | `Cover`, or `NewPrompt -Cover`, through `Set-P20CardLine` | the board's card face, the list's thumbnail, the card page; the model's `cover`. `stamps.cover` |
| `**Before:**` | The other half of a before/after proof, the same way: `../assets/<card key>/before.<ext>` | `Cover -Before`, or `NewPrompt -Before` | the card page, side by side with the cover; the model's `before`. `stamps.before` |
| `**Created:**` | `yyyy-MM-dd`, the day the card was made -- or the day the work was, with `NewPrompt -Date` | `NewPrompt` | Daily, reviews, the engagement timeline. `stamps.created` |
| `**Closed:**` | `yyyy-MM-dd`, the day it was archived. **Never rewritten**: re-archiving does not change when a card closed | `Archive`, through `Add-ClosedStamp.ps1` | the same. `stamps.closed` |

A verb that adds a footer line to a card that already exists goes through **`Set-P20CardLine`**
(`Scripts/Set-CardLine.ps1`): the line lands directly above `**Created:**`, and a card that already says
what was asked is not written. Cards from before the stamps existed carry no dates; git history can lend
them one (`Scripts/Backfill-CardStamps.ps1`, [CLI](../CLI.md#the-two-dates-a-card-carries-and-the-cards-that-never-got-them)).

Two lines near the top are **links back into the package**, not data: `> Template: ...` and the
`ado-comments workflow` line. They are relative paths, rebuilt whenever a card moves
(`Scripts/Repair-CardLinks.ps1`), and nothing reads them as state. When the hub and the package are
on different drives (or the hub is on a network share) there is no relative path, and the lines carry
the file's **name** instead -- `> Template: Bug.template.md`, and the workflow line without a link --
never a drive letter or an absolute path, which would be wrong on the next machine; a card that
already holds one is rewritten to that form the next time it is repaired. A third line, `> Previous round:`
(see the table above), is a link **inside** the hub: `current/` to `archive/` of one Space does not move
with the package, so it is never recounted -- only re-aimed at the latest earlier round when `Archive`
renames a plain one to `-r1`. A fourth, `> Design:` (the table above), points at a design and is **never
repaired**: its link is for the person reading the file and may go stale when the design moves; the id
after it is what the agent resolves.

### A card's pictures -- `<space>/assets/`

A card can carry a picture: a screen snap of what was wrong (`**Before:**`) and of what landed
(`**Cover:**`) -- for a GUI issue the snap is often the report itself. Never required, never configured: there is no flag, and a card without one is a complete card.

```text
<promptsRoot>/<space>/
  current/   archive/          the cards
  assets/<card key>/           what a card keeps that is not text
    cover.png                  written by Cover
    before.png                 written by Cover -Before
    cover-r2.png               a later round of the same card
    add_prize_drawer.html      a mock someone put there by hand -- never touched
```

- **`assets/` is the Space's**, a sibling of `current/` and `archive/` (`consts.json` `folders.assets`), so
  `../assets/...` is right from either card folder and `Archive` moves nothing. Images never sit beside the
  cards: `current/` is a person's list of files.
- **The card key** is the filename's type prefix as written and its id as the one id rule reads it --
  `US-467`, `Task211`, `Spike-K7M2`, `214`. An existing folder that differs only in case is used as it is.
- **The sample cards ship with covers**: every card in `samples/hub/demo/current/` and
  `samples/hub/github-demo/current/` has one, drawn as SVG and sliced to a 800x500 WebP (6-11 KB each),
  attached through `Cover` so the line and the folder are exactly what the verb writes. `Start` copies
  them out with the cards, and from then on they are the person's files. A Demo copied out before this
  has no covers; `Cover -Samples` dresses each sample card that has no `**Cover:**` line, and no other. The twenty drawn covers, their
  SVG sources and the generator are `samples/covers/`.
- **Types and size**: png, jpg, jpeg, webp, gif (`assets.coverExtensions`), at most 5 MB
  (`assets.coverMaxBytes`); `Cover` refuses anything else, naming the limit.
- **One cover and one before per card.** Attaching again replaces that card's own picture and says so.
- **Rounds share an id, so they share a folder.** A card that came back takes the first name no other
  round's line holds -- `cover`, `cover-r2`, `cover-r3` -- read from the `**Cover:**` / `**Before:**` lines of
  the cards with that id in `current/` and `archive/`, so an archived round still draws its own picture.
- **The line is the truth.** A picture is served only when the line resolves INSIDE that Space's `assets/`
  (resolved first, then checked), exactly `<card key>/<file>`, an image type, and the file is there.
  `Resolve-P20CardImage` (`Scripts/Add-CardImage.ps1`) and `card_image()` (`agent/core/assets.py`) are held
  to one table, `Tests/fixtures/parsers/covers.json`, from both suites.
- With `storeSync: git`, `Cover` commits the picture and the card together, the way `Archive` commits a move.
- `Repair-CardLinks` is not involved: the path is inside the hub and does not move with the package.
- **From the browser, the same writer** (C2). The card page's drop zone, the header's Replace cover /
  Add before / Remove cover, and the + dialog's picture field all go one way: the bytes to
  `POST /api/assets/upload`, which puts them in a temp file under the system temp folder and answers its
  path, writing nothing into the hub; then `Cover <card> <path>` (or `NewPrompt -Cover` / `-Before <path>`)
  through the bridge, which copies the file into `assets/<card key>/` and writes the line, after which the bridge removes the upload's temp folder (success or failure; and the agent sweeps any a day old at start). The route
  refuses what the verb would -- a type not in the list, a size over the limit, no bytes -- so the person
  hears it before a shell starts; the zone says the same sentence before the upload. `Tests/test_assets.py`
  asserts the hub's bytes are unchanged after an upload with no `Cover` call. A drop only stages the
  picture: the zone names the file and the button that attaches it, in that button's own label
  (`Press Add cover to attach it.`, or the dialog's), and that button takes focus; a second drop replaces
  the first and says so.

## State is derived, never stored

There is no status field. It is worked out from the file every time, in this order -- the first that
holds wins:

| # | Condition | State |
| --- | --- | --- |
| 1 | the file is in `archive/` | **Done** |
| 2 | a `PR URL: https://` line, **or** a `**Review:**` line | **Code Review** |
| 3 | a commit bullet, **or** a `**Started:**` line | **In Progress** |
| 4 | none of the above | **Active** |

The four words are `consts.json` `status` -- the vocabulary the web sorts and colours by, and the board's
lanes. **Writing the token IS the transition**, and **every lane has two writers**: git's
token, and a person's. `ThreadHash` moves a card to In Progress and so does `Move -To InProgress` (a
`**Started:**` line); `NewPR` moves it to Code Review and so does `Move -To CodeReview` (a `**Review:**`
line); `Archive` moves it to Done and so does `Move -To Done`, which IS `Archive`. Dropping a card on a
lane of the board runs `Move`. The rule does not care who wrote the line, and editing the file by hand is
still a legitimate way to correct a state. A card travels one way: `Move` refuses a lane behind the card.

**What a lane is called is the org's.** The four words above are what is stored, compared and served as
`status` and never change; an org may name each lane for display -- `spaces[].laneNames.{active,
inProgress, codeReview, done}` in `hub.json` -- and the sample hub's Demo does: To do, Doing, Waiting,
Done, for someone with no team and no tracker. An org that says nothing is called by the four words, so an
Azure DevOps user sees no change. `/env` serves `config.laneNames` keyed by the contract word; the CLI's
`Status` prints the contract words, because it is the ledger.

**The board edits a lane's name in place**: a pencil on the lane header
(`web/src/modules/ado/LaneLabelEditor.tsx`), hover or keyboard-focus to reveal it, click turns the label
into a text box, Enter writes `spaces.<slug>.laneNames.<key>` through `PUT /api/config` -- the one writer,
the `ConfigSettings` precedent, never a second implementation -- Esc or a blur cancels, and a blank value
is the existing "clear a field" shape (`buildConfigEdit`): an `-Unset`, which restores the contract's own
word. `web/src/modules/ado/laneNames.ts`'s `laneConfigKey` is the one place that translates between the
contract word `/env` keys `laneNames` by and the camelCase field name the schema and `Config -Set` take.
Per-lane, per-space: renaming a lane on one org touches nothing on another. Not offered on an archived
org's retrospective, which is read-only by the same rule every other write on that view follows.

**The editor occupies the exact box of the heading it replaces**: one shared inline
style, no margin, one explicit height, the same four typography tokens the resting heading draws from,
worn by both states, with the pencil button staying mounted in both so the row's own height never moves.
And the write follows the Board's own no-optimistic-update rule for a card move: Enter awaits the write
and exits editing only once it succeeds; a refusal -- the hub not writable, or any other error the bridge
reports -- leaves the editor open, the draft intact, and shows the refusal's own sentence, rather than
silently reverting to the old name.

The rule
exists once per half on purpose -- `Scripts/Get-PromptStatus.ps1` and `agent/core/parsers.py` -- and
both run against the same fixture files in `Tests/fixtures/parsers/`, so a rule that drifts on one side
fails on that side. It only holds for shapes a fixture HAS: `review-heading-no-url.md` holds that a
`## PR Review Comments` heading with no `PR URL:` line is not Code Review, on either side.
**Add a rule, add a fixture -- and assert it from both suites.**

Not a state: **Planned**, or a backlog of any kind. A card is in play the moment it is made
(D-C12). A card with no pull request enters Code Review only by a
person's `**Review:**` line, and need not enter it at all: a Spike may go from In Progress to Done.

### A card in a standup

A local Space -- no tracker address, or status `local` -- has a standup over its cards (Team Agile;
Team Agile is on only in a Space answered *With agents*, so this is a GitHub Space still
`local`, or a no-tracker Space read with `-Space` from one). An active GitHub Space reads its cards
too, joined to its issues on the id: a card whose id is an issue's number adds its lane to the issue's
row (and a `Check` line where the two disagree), and any other card goes in the tile below. A card that
says `**Billable:** no` is in neither. For a card of its own:
the derived state above, plus the `**Closed:**` day of an archived card, puts each card in at most one
slot of the engineer's one tile, read fresh every time and never written back. The days are the
standup's window: `since` is the start of the previous working day, `asOf` is now.

| The card | Slot |
| --- | --- |
| `archive/`, `**Closed:**` on a day from `since` to `asOf` | **yesterday** |
| `current/`, In Progress | **today** |
| `current/`, Code Review | **today**, and the walk queue ("what waits on you") |
| `current/`, Active; `archive/` closed earlier or never stamped | nowhere |

The line names the card by its id (`K7M2 Wire the board`) and its title from the heading. Both halves
hold it to one table, `Tests/fixtures/rituals/standup-cards.json`; the add-on's document has the rest
([Team Agile](../modules/solitaire-agile.md#the-two-sources-joined)).

## The model, as the agent serves it

`GET /api/status` lists `current/`; `GET /api/status/{file}` is one card with its text. The same facts, as
fields, so nothing downstream parses a heading or a filename (`PromptInfo`, `agent/ado/status.py`):

| Field | From | Notes |
| --- | --- | --- |
| `file` | the filename | the card's identity in every route and every bridge call |
| `id` | the filename, by the one id rule | a **string**; `null` for a file that is not a card |
| `type`, `name` | the heading | `null` / `""` when the heading does not fit |
| `title` | the heading, whole, cut to 60 characters | predates the model; kept for display |
| `linked` | an `https://` `**ADO Link:**` | the only difference between an ADO card and any other. The filter drawer's **Linked / Custom** row reads it and nothing else |
| `tracker` | the tracker rule (`tracker()`, D-G2) over the card's OWN `**ADO Link:**`, never the Space's address | `github`, `ado`, or `none` -- `none` exactly when not `linked`. The card's **gh** / **ado** badge, first in the list row's meta line and on the board's card face; a custom card wears none |
| `pinned` | NOT read from the file -- asked of the tracker: the card's `tracker` is `github`, its `**ADO Link:**` is an issue of the Space's own repository, and that number is in the repository's pinned set (one `gh api graphql` `pinnedIssues` call per repo, held 60 seconds and dropped when `EditItem` runs) | `false` unless all three hold **and** the Space is GitHub at Tier 1; at Tier 2, on Azure DevOps and on no tracker `gh` is not asked. The board's card face wears the pin and "Pinned on GitHub" in its meta line and sorts pinned cards first within a lane; the list and the detail route do not carry it |
| `billable` | no `**Billable:** no` line | default `true` |
| `status` | derived, above | `Active`, `In Progress`, `Code Review` (and `Done` for archive readers) |
| `progress`, `checked`, `total` | the checkboxes | `--` when there are none |
| `sprint` | `**Sprint:**`, last segment, cut to 20 | `--` when absent |
| `ado_url`, `pr_url` | the footer; the `PR URL:` line | `null` when absent |
| `cover`, `before` | the `**Cover:**` / `**Before:**` lines, by the rule in "A card's pictures" | the URL of `GET /api/assets/{space}/{card key}/{file}`, or `null` -- no line, a missing file, or a path outside the Space's `assets/`. On the list and the detail route. The board draws `cover` as the top of the card's face (16:10, cropped); the list as a thumbnail inside the meta line; the card page under its header, Before and After side by side. The page reads the line itself to say "the image is missing" rather than draw a broken one |
| `design` | the `> Design:` line, else a hand-written `> Spec:` line, by the rule in the table above | `{ kind, title, link, id, short, note, state, where, path }`, or `null` when the card names none. On the list it is the line as written (`state`, `where`, `path` empty). On the detail route the id is resolved -- the hub's designs from disk, the active GitHub Space's repo through the Design tab's own cached listing when the line's link is a GitHub URL and the tab's gate passes -- and `state` (`Design`, `Spec`, `Complete`, `Archived`), `where` (`hub`, `repo`) and `path` (the document to open) say what was found; a design that cannot be read leaves them empty and the line stands as last written. The card page draws it as a chip that opens the design's reading room |
| `previous_round` | the `> Previous round:` line, as written (relative to the card's folder) | `null` when absent; on the list and the detail route. Held by `Tests/fixtures/parsers/previous-round.md` from both suites |
| `commits` | the commit bullets (`regex.commitBullet`), counted | `0` for `- (pending)` and for a card In Progress only by a `**Started:**` line. What the web's *Create PR* gate reads -- a card with none has nothing to open a pull request from (`web/src/modules/ado/cardActions.ts`) |
| `modified` | the last commit that touched the file, when the hub is a git repository; else the file system | what Home's list sorts by -- a write that changes nothing must not happen. A day from git is the commit's AUTHOR instant on the reader's clock (`%at`), the same rule in `tkStatus` and `/api/status`, so the two cannot show one card two days |
| `path` | the file system (detail route only) | the file's absolute path on the agent's machine, shown on the card page with a copy button -- the address a person hands to an assistant |

## Who writes a card

**The CLI, and nothing else.** The web changes a card only through `POST /api/cmd/{name}`, which runs the
verb; there is no native route that CREATES a card in `current/`. Every write goes through `Write-CardText`:
UTF-8, no BOM; a file the tool CREATES is LF (`-New`), a file it EDITS keeps the line endings it has
([CLI](../CLI.md#the-bytes-a-card-is-written-with)). Every reader tolerates both endings. The one
exception is an edit, not a create: the agent's `POST /api/pr-comments/{filename}/save` writes a decision
and a reply into a card's review section, through the agent's own writer, `agent/core/cards.py`, which
keeps the same edit rule -- the card's own line ending, no BOM.

| Verb | Does to the file |
| --- | --- |
| `NewPrompt <id>` / `-Title` | creates it from the type's template. For a card already in `current/` it RETURNS that card and writes nothing. `-Design <name\|id>` adds the `> Design:` header line |
| `ThreadHash` | adds commit bullets under `Commits:`; fills `[commit]` placeholders in PR replies |
| `NewPR` | writes `PR URL:` |
| `PublishPR` | writes `PR published: <url>` on the line under `PR URL:`, once -- a record, not state |
| `GetPRComments` | writes `PR URL:` if absent; appends review rounds under `## PR Review Comments`. Append-only, safe to re-run. It also writes a side record, `pr-comments/<date>-PR<id>.md` in the Space (read at archive time for `prsReviewed`), except with `-OutputFile`, which writes only the file it names ([CLI](../CLI.md)) |
| `Billable` | adds or removes `**Billable:** no` |
| `NewItem -FromCard` | files the card as a GitHub issue -- its name and Summary, the body ending `Toolkit card: <id>` -- and writes the issue's URL into `**ADO Link:**`; refuses a card that is already linked |
| `Cover` | copies a picture into `<space>/assets/<card key>/` and writes `**Cover:**` (or `**Before:**`); `-Remove` deletes both. `NewPrompt -Cover` / `-Before` attach the same way at birth |
| `Move` | adds `**Started:**` or `**Review:**` with today's date; `-To Done` is `Archive` |
| `Archive` | moves it to `archive/`, stamps `**Closed:**`, refreshes its package links. Already in `archive/` (by id or exact name): says so, exit 0 |

## A whole card

`samples/hub/demo/current/214-search-returns-duplicates-when-tags-overlap.prompt.md` is a complete, real
example in the In Progress state; `US-209-...` beside it is in Code Review, `Spike-K7M2-...` is a card with
no work item, and `demo/archive/` holds two that are Done. The parser fixtures
(`Tests/fixtures/parsers/`) are one card per state.

## What is NOT in the model

Hours. An assignee. A priority. A parent or a child. A due date. A status field. Planned / backlog. Any of
them may come; none is here, and a reader should not look for one.
