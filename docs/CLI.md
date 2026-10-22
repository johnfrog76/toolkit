# The CLI

The CLI is the whole workflow as PowerShell verbs, `tkNewPrompt` to `tkCloseItem`: it makes a card,
threads the work into it, ships it and closes it, and nothing else has to be running. This document is
its manual -- the prefix, the workflow and the state it derives, every command, what works without a
tracker, how a command refuses, the log, AI review and the agentic workflows. The five verbs are on
the front page, the root [README](../README.md), and [a day in them](#a-day-in-the-cli) is below;
installing is [Quick start](QUICKSTART.md); settings are [Configuration](CONFIGURATION.md).

## The prefix

Every command is `{prefix}{Command}` -- `tkStatus`, `tkNewPrompt`, `tkArchive`. **The prefix is
data, not code.** It comes from `commandPrefix` in config and defaults to `tk`.

Change it by setting `commandPrefix` in `config.local.json`, or register additional prefixes at
runtime:

```powershell
Register-PromptAlias -Prefix gt                            # gtStatus, gtNewPrompt, ... every command
Register-PromptAlias -Prefix ab -Commands Status,Archive   # just these two
```

This is a **multiton**: any number of named prefixes over one shared implementation. Nothing is
duplicated and nothing is forked -- `tkStatus` and `gtStatus` are the same function. Prefixes may
carry different command subsets and are free to drift; there is nothing to keep in sync.

Registering a prefix will not silently steal a name that already points elsewhere. It warns and
skips unless you pass `-Force`. Registering the same prefix twice is silent.

That is the whole mechanism. There is no per-prefix data file and no registry of prefixes: a prefix
is a registration in the shell that made it, `Menu` prints the one config names, and nothing
reconciles two prefixes because nothing needs to -- they are the same functions. `tkTestToolkit
-Menu` holds the contract: every alias a second prefix registers resolves to the same function
the first one does, `-Commands` registers exactly what it lists, and a collision is a warning.

---

## The workflow

The loop, end to end. Everything accumulates in one file.

```powershell
tkNewPrompt 113        # ADO card 113 -> prompt file in {promptsRoot}/{org}/backlog/ -- planned
tkNewPrompt 113 -Now   # ...or in {promptsRoot}/{org}/current/ -- in play at once
```

Creates the file in the shape matching the work item type, seeded with the card's title,
repro, acceptance criteria, sprint and link -- plus a suggested branch name.

**A new card is planned, not in play.** It lands in the Space's `backlog/`, and `Status` lists it after
the cards in play. It is pulled into `current/` when you decide -- `tkMove 113 -To Active` -- or by its
first write: the first `tkThreadHash` into it, its `tkNewPR`, or `tkMove 113 -To InProgress`. Each of
those MOVES the file to `current/` before it writes, so the flow below is typed exactly as it always was
and the card arrives in play with its first commit on it. `-Now` skips the backlog. `tkMove <id> -To
Backlog` parks an Active card again -- one with nothing threaded; anything threaded is in play and the
verb refuses ([the card](hub/cards.md), "State is derived, never stored").

**With no `az`, the same verb takes a title instead of an id**, makes no ADO call, and produces the
same file with the board's fields marked not linked:

```powershell
tkNewPrompt -Title "Timeout on large files" -Type Bug
```

That is the Tier-2 entry point to everything below -- see
[Creating a card with no ADO](#creating-a-card-with-no-ado).

**`current/` is protected: a card travels one way.** Run `tkNewPrompt 113` again while card 113 is
still in `current/` or `backlog/` and you get *that card back* -- its path, exit 0, nothing written, and no ADO
call, so the board card is not reassigned or moved either (with `-Now` on a planned card, it also names
`tkMove 113 -To Active`). A day's notes, commits and review rounds
are never scaffolded over. The card is found by **id**, through the same rule `Archive` uses, so `Task113-an-older-title` is
still card 113. There is no switch that overwrites; to start a card over, move or delete the file.

A card that has already gone to `archive/` does not block anything: `tkNewPrompt 113` then scaffolds
a fresh card in `current/` -- the bug came back -- and archiving *that* one keeps both, the earlier
round renamed `-r1` and the new one filed `-r2`, then `-r3` -- by the card's ID, so a card whose title
was edited between rounds is still the same card and each round keeps its own slug. Nothing in `archive/` is ever
overwritten either (`tkArchive -Help`, "Round history").

The new card **links back, and quotes nothing**. When `NewPrompt` scaffolds a card (the board form or
`-Title`) whose id already has rounds in the Space's `archive/` -- matched by id, the rule `Archive`
counts rounds with -- it writes one line under `> Template:`, `> Previous round: ../archive/<latest round>`,
and prints `[*] Round N of this card; previous round: archive/<file>` (N is the earlier rounds plus one).
There is no `-Round` switch: the number is `Archive`'s to assign, at archive time. No `## Outcome` or any
other text is carried forward, and a card already in `current/` is still returned untouched.

Work the card. Write your diagnosis and decisions **into the prompt file** as you go; that is the
whole point of it. Commit as normal, then:

```powershell
tkThreadHash           # run IN the code repo -- every commit on this branch lands in the Git section
tkStatus               # every active card and its derived state
tkNewPR                # opens the PR, moves the ADO card to Code Review, writes PR URL back
```

**`ThreadHash` reads the repository you run it in, and only that one.** It asks git for every commit
on the current branch that is not yet on the project's `defaultBranch` -- the same branch `NewPR`
will target -- and writes each as its own `- {short-hash} {message}` bullet under `Commits:`, oldest
first. Run it once after the last commit, not once per commit: a hash the card already carries is
skipped, so re-running adds nothing and the `- (pending)` placeholder goes the moment a real commit
lands. The card is found from the branch name when you do not name one.

The hub is **not** the code repo -- it need not even be a git repository (`storeSync: none`) -- and
reading the hub's history here would record the hub's own commits as the work's and report success.
So **a location that is not a git repository is a refusal**, not a guess, and it names the way round
it:

```powershell
tkThreadHash -Hash abc1234    # thread one explicit hash, from anywhere
```

Then review:

```powershell
tkGetPRComments        # fetch PR review comments, append them to the file
tkReplyPR <pr> <thread> -Reply "..."
```

**A thread is a conversation, and the card gets all of it.** `GetPRComments` is append-only and
idempotent -- run it as often as you like; a comment the card already holds is never written twice
-- and it deduplicates by **comment**, not by thread. So when a reviewer comes back inside a thread
the card already has ("that fix is not enough, see line 40"), the next run appends that reply as a
triage item of its own, with its own `Decision:` and `Reply:` slot, marked
`Follow-up: (Thread 874 / Comment 3)`. Your own replies arrive the same way -- and `tkReplyPR` also
fills the thread's `Reply:` slot the moment it posts, so the card is the record before the next fetch
as well as after it.

**The side record.** Besides the card, a run writes one small file per PR fetch,
`<promptsRoot>/<promptsFolder>/pr-comments/<date>-PR<id>.md` (the PR title, its URL, the fetch time, the
repository and the count of new comments). It exists so `prsReviewed` is countable at archive time; nothing
else reads it. **With `-OutputFile <path>` it is not written at all** -- the named file is the only file
that run writes, and the verb prints one line saying the side record was skipped -- so a run aimed at a
scratch file leaves nothing behind in the hub.

And when it ships:

```powershell
tkArchive <ID>         # move current/ (or backlog/) -> archive/, and commit if storeSync is 'git'
tkArchive <filename>   # the long form; a partial name is named before it moves
tkArchive -Relink      # rewrite every card's package links from where things are now
```

### A day in the CLI

```powershell
tkMyWork                     # Coffee in hand -- what's assigned to you
tkNewPrompt 12345            # Work item 12345 blooms into backlog/ -- yours, planned
# ... code, commit, push ...
tkThreadHash                 # From the CODE repo: the card moves to current/, its commits thread in; In Progress
tkNewPR                      # Open the PR; the card walks itself to Code Review
tkGetPRComments              # Pull every review thread into the prompt file
tkReplyPR 140123 1342185 -Reply "Fixed in abc1234." -Status fixed
tkArchive 12345              # Your ledger says Done -- the file moves to archive/
tkCloseItem 12345 -Comment "Shipped."   # ...and the board agrees
```

Nothing in that sequence asks you where anything is. The active Space is assumed, the prompt file is
found from the branch, and the PR is found from the card. Switch context any time -- `tkSwitchSpace
demo` for a presentation, `tkSwitchSpace globex` to come back -- and every query and prompt re-scopes.

A shell that is already open follows the file. `config.local.json` and the hub's `hub.json` are read once, at import, and their write times are remembered; the next verb you type (and `Env`) compares them and, if either changed -- the GUI's switch, `Config -Set` or `SwitchSpace` from another window, a hand edit -- re-reads the config before it runs, saying `Space changed to <slug> since this shell loaded (it was <slug>); re-read.` once (`Config changed since this shell loaded; re-read.` when it was not the Space, a module flag for one). So `NewPrompt` never files a card into a Space you already left. `P20_ACTIVE_SPACE` still wins for the process it is set in -- and the two environment overrides, `PROMPTS_ROOT` and `P20_ACTIVE_SPACE`, are compared the same way, so one exported after the shell loaded the toolkit is seen on the next verb like a changed file (`Hub changed to <path> since this shell loaded (it was <path>); re-read.`), and `Env`'s `Hub` check and its `Your hub` row cannot name two hubs in one report.

**Those last two lines are one event, posted twice.** `tkArchive` writes to your ledger; the tracker
is the organisation's. Neither is a copy of the other, and nothing reconciles them automatically, so
if you run only the first, your files say Done while the board still says Code Review.
[The two can disagree](#3-the-two-can-disagree-and-nothing-notices) explains why that separation is
deliberate rather than a missing feature.

### The other day: triage

Not every card earns a prompt file. Working a queue of accessibility bugs, most of the answer is
"not reproducible on the current build" -- no branch, no PR, nothing to archive:

```powershell
tkMyWork -State New
tkCloseItem 232271 -Comment "No repro on iOS 18 / VoiceOver 17.6." -Reason CannotReproduce
tkCloseItem 232284 -Comment "Host app sets role=application; see 232271." -Reason AsDesigned
tkCloseItem 232290 -Comment "Superseded by the 4.2 control rewrite." -Reason Obsolete
```

`-WhatIf` prints the transition it would make and calls nothing, which is worth using on the first
one of a batch. On Azure DevOps, bugs go to **Resolved** with the reason; stories, tasks and features
go to **Closed**. The reason list the tool knows is a convenience, not a limit -- anything else is
passed to ADO verbatim and the project's process template decides.

### State: three machines, not one

This trips people up, so it is worth being exact. There are **three** states in play and they are
kept in different places by different things.

| | Lives in | Changed by | Can go backwards |
| --- | --- | --- | --- |
| **Prompt file** | derived from the file's own text | writing a token into the file | Yes -- delete the line |
| **ADO work item** | stored in ADO | `NewPrompt`, `NewPR` | Only by hand |
| **Pull request** | stored in ADO | ADO itself, when merged or abandoned | No |

#### 1. The prompt file -- derived, never stored

No status field exists. `tkStatus` re-reads the file every time, in **this order** (the rule and
the fixtures that hold both halves to it are [docs/hub/cards.md](hub/cards.md), "State is derived,
never stored"):

| Check | State |
| --- | --- |
| File is in `backlog/` | **Backlog** -- planned, not in play |
| File is in `archive/` | **Done** |
| A line starts `PR URL: https://`, or a footer line `**Review:**` | **Code Review** |
| A line is a bullet with a 7+ character hex hash -- `- 80e2168 message` -- or a footer line `**Started:**` | **In Progress** |
| None of the above | **Active** |

**Order matters.** `PR URL:` is tested first, so a card with a PR URL and no commit bullets still
reads Code Review. And the hash must be **its own bullet line** -- an inline or comma-separated
list is not detected.

Writing the token *is* the state change. That is why the commands that write to the file are the
state machine rather than conveniences, and why editing the file by hand is a legitimate way to
correct state.

**Two writers per lane.** Git's tokens move a card by themselves; for the card that has
nothing checked in or no pull request -- a PowerShell script written on a bench, a spike that ends in a
finding -- a person writes the line instead, with `Move`: `-To InProgress` writes `**Started:** <today>`
into the footer, `-To CodeReview` writes `**Review:** <today>` ("look at this thing"), and `-To Done` is
`Archive`, exactly. The state rule (`Scripts/Get-PromptFileStatus.ps1`, its own file, dot-sourced by
`Status` and `Move` alike) reads a person's line exactly as it reads git's; the `**Review:**` line outranks
a commit bullet as `PR URL:` does. A card travels one way: `Move` refuses a lane behind the card, and the
way back is to remove the line by hand. Dropping a card on the board runs this verb through the bridge.
The org may CALL its lanes what it likes (`spaces[].laneNames`, [Configuration](CONFIGURATION.md)); `Status`
prints the contract's five words, because it is the ledger.

**Two lanes are folders.** `Move -To Active` moves a planned card from `backlog/` to `current/`, and
`Move -To Backlog` moves an Active card back -- refused, exit 2, for a card with a commit bullet, a
`PR URL:`, `**Started:**` or `**Review:**` (threaded work is in play, not backlog). Either move is a
rename: the card's bytes are not touched. `-To InProgress` and `-To CodeReview` on a planned card pull it
into `current/` first and then write their line, as `ThreadHash` and `NewPR` do -- one helper,
`Scripts/Move-CardFolder.ps1` (`Invoke-P20PullIntoPlay`), so a card in `backlog/` never carries an
in-play token.

**`Status` lists the cards in play, then the backlog folded.** The numbered list is `current/`; after it,
one block names `backlog/`: `Backlog (3), planned -- not in play:`, the file names on one line, and the
`Move <id> -To Active` hint. A planned card is never a numbered row.

#### The two dates a card carries, and the cards that never got them

A card is stamped `**Created:** yyyy-MM-dd` when it is scaffolded and `**Closed:** yyyy-MM-dd` when
it is archived. The pair is what lets an archived corpus be reported over -- billing included --
**without reading git**, and an existing stamp is never rewritten: re-archiving a card does not
change when it closed.

#### The third line: Billable

Daily -- the week, a day at a time, that a timesheet is filled in from -- is **built from the cards'
own dates**: a card is on every working day from its `**Created:**` to its `**Closed:**`, or to today
while it is open. Git, when the hub has it -- as a repository of its own or as a folder inside one --
only **enriches** that: it says which of those days a card
was actually touched and lends a date to a card that has none. It never adds a day outside a card's
own interval, so reorganising the hub never brings an archived card back onto the timesheet. A hub with **no git at all** -- the first-run hub is one -- is billed the same way.
**A weekend belongs to the week after.** Only weekdays render, and time is in by Friday, so anything
dated Saturday or Sunday -- a `**Closed:**`, a commit, a `**Review:**` -- is billed on the Monday
after: a card closed on Saturday reads active through Friday and `resolved` on Monday.

One line takes a card off it:

```text
**Billable:** no
```

**No line means billable**, so a card written before the line existed, and a card that came from a
work item, is billable without anyone saying so. `Billable <id|file> -No` writes the line, directly above
`**Created:**`; `Billable <id|file>` **removes** it rather than writing "yes", so a card that was
marked and unmarked is byte for byte what it was. The card is looked for in `current/` and then in
`archive/` -- the usual moment to notice is Friday, when it is often already closed -- by its exact id
(typed in any case) or its filename; a name that matches two cards is refused with both named. It
writes through `Set-P20CardLine` (`Scripts/Set-CardLine.ps1`), the one way a verb adds a footer line to
a card that already exists: the card keeps its own line endings, and a card that already says what was
asked is **not written**, so its modified time does not move. Daily says what it left off -- "1 card
marked not billable is left off" -- because a card missing from a timesheet without a word reads as a
bug. A card with **no date at all** and no git to lend one is counted and never guessed at. The same
line keeps the card off Team Agile's standup ([`docs/modules/solitaire-agile.md`](modules/solitaire-agile.md),
"The two sources, joined"), read by the same reader, `Test-P20CardBillable` in
`Scripts/Get-PromptFileStatus.ps1` (`card_billable` in the agent).

Cards written before the stamps existed carry neither, and their dates live in exactly one place,
the hub's commit history -- which is not permanent: a repo gets squashed, re-homed or archived.
`Scripts/Backfill-CardStamps.ps1` is the one-time repair. It is **not a verb**; run it once per hub:

```powershell
pwsh -NoProfile -File Scripts/Backfill-CardStamps.ps1 -WhatIf     # what it would write
pwsh -NoProfile -File Scripts/Backfill-CardStamps.ps1             # write; it does NOT commit
git -C <hub> commit -am "backfill: Created/Closed stamps from git history"
```

It follows each file through its renames. **Created** is the oldest commit that is still that card;
**Closed** is the day the file most recently *entered* an `archive/` folder. Three rules: a folder reorganisation is not an event (a move *of* `archive/` is not a move
*into* it); a "copy" git detects from another card lends this card no history; and a stamp that is
already there is never touched, so it is idempotent. Every day it writes is the commit's AUTHOR
instant read on this machine's clock (`git log --format=%at`, converted by `ConvertTo-P20LocalDay` in
`Scripts/ConvertTo-LocalDay.ps1`) -- never `%ad`/`%ai`, which is the day where the commit was made. Every
reader of a date from git uses that one helper (the agent's twin is `agent/core/clock.py`), and
`Tests/Test-BackfillStamps.ps1` fails if a script asks git for a zoned date. Dated PR records and
`growth/` are not cards and are skipped; a hub that is not a git repository is a stated refusal.

**Commit it with a subject that starts `backfill:`.** Billing skips the commits the toolkit itself
makes for mechanical reasons -- that one, and `sync: refresh package links` -- because they touch
cards nobody worked on.

#### A card's picture: Cover

A card can carry a picture -- the snap of what was wrong, and of what landed. Nothing is configured and
nothing is required; a card without one is a complete card.

```powershell
tkCover K7M2 ./snap.png              # the cover: assets/Spike-K7M2/cover.png, and one footer line
tkCover 214 ./before.png -Before     # the other half of a before/after proof
tkCover K7M2 ./snap.png -WhatIf      # what it would copy and write; changes nothing
tkCover K7M2 -Remove                 # deletes the picture and its line
tkCover -Samples -WhatIf             # an older Demo: which sample cards would be dressed; changes nothing
tkCover -Samples                     # ...and dress them
tkNewPrompt -Title "Tags overlap in search" -Type Bug -Before ./snap.png   # born with it
```

The picture is copied into the Space's `assets/<card key>/` -- beside `current/` and `archive/`, never
among the cards -- and the card names it with one line written through `Set-P20CardLine`, above
`**Created:**`: `**Cover:** ../assets/Spike-K7M2/cover.png`. The card key is the filename's type prefix and
id (`US-467`, `Task211`, `Spike-K7M2`, `214`). The card is found in `current/` and then `archive/` (proof
often arrives after a card is Done), by its exact id or its filename.

- **Refusals, exit 2, one sentence each:** no such card; a path that is not a file; a type that is not
  png, jpg, jpeg, webp or gif; a picture over 5 MB, with the limit in the sentence.
- **Attaching again replaces that card's own picture** and says so. A file the verb did not write -- a
  mock someone put in the folder -- is never touched.
- **Rounds share a folder.** A card that came back takes the first name no other round's line holds:
  `cover`, `cover-r2`, `cover-r3`. The archived round keeps drawing its own picture.
- **With `storeSync: git`, the picture and the card are one commit**, the way `Archive` commits a move;
  otherwise nothing is committed and the verb says so.
- **`-Samples` is the upgrade path for a Demo copied out before the sample cards had covers**. For
  every card the package's `samples/hub` ships with a cover, in a Space of the same folder name in your
  hub, it attaches that picture -- through the same writer, one card at a time -- when the card has no
  `**Cover:**` line. It never touches a card that has a cover line (even one whose file is gone), a card
  the sample does not ship (matched by exact filename), or a Space that is not a sample's, and it copies
  no `assets/` in bulk. It takes no card, no image, `-Before` or `-Remove` (exit 2 if given one);
  `-WhatIf` lists the cards and writes nothing; a second run finds nothing to do. `Update` prints the
  count and this command when there is something to dress, and never writes it itself
  (`Scripts/Get-SampleCoverGaps.ps1` is the one list both read).

The board draws the cover as the top of the card's face, the Home list as a thumbnail, the card page under
its header (Before and After side by side). The rule a reader applies to the line is in
[the card's own document](hub/cards.md#a-cards-pictures----spaceassets).

#### 2. The ADO work item -- stored, changed as a side effect

| Transition | Done by | Only when |
| --- | --- | --- |
| `New` -> `Active` | `tkNewPrompt <id>` | The card is **exactly** `New`. Any other state is left alone with a warning. |
| `Active` -> `Code Review` | `tkNewPR` | That work-item **type** has a `Code Review` state in that project -- some Bug definitions do not, and it says so and skips. Already `Code Review`, `Resolved` or `Closed` is also skipped. |
| anything -> `Closed` | **nothing** | `tkArchive` never contacts ADO. Closing the card is manual. |

#### 3. The two can disagree, and nothing notices

`tkArchive` marks the file **Done** and leaves the ADO card wherever it was. Archive a month of
work and ADO may still show every card in Code Review.

That is deliberate rather than an oversight -- the file is the record
([docs/hub/cards.md](hub/cards.md)), and the tracker is a place the organisation looks. So **"Done"
locally does not mean "Closed" in ADO**, and **no command reconciles the two**: `Archive` never contacts
ADO, and nothing writes the board for you. If the board matters to someone else, close the card yourself.

What notices is **`tkStatus -Board`**, an opt-in, read-only join. For every card in `current/` linked to a
work item it reads the item's `System.State` once (`az boards work-item show`) and adds `Board: <state>`
to the card's line; a card with no work item (a lettered id, or `(not linked)`) has no Board cell. It
flags, with `(differs)`, only a **definite** mismatch -- a card in `current/` whose item is Closed, Done,
Removed or Resolved -- and ends with a one-line count. Everything else is shown, not judged: there is no
defined mapping between a local Code Review and an ADO state, and none is invented. The other definite
mismatch, a card in `archive/` whose item is still open, is part of the rule
(`Get-P20BoardMismatch` in `Scripts/Get-WorkItemRecord.ps1`) but `Status` lists `current/` only, so it is
not read yet. `-Board` is **refused** -- one stated `Error:` and exit 2, naming what is missing -- when
Azure DevOps is off for the Space, the Space's board is GitHub, there is no board address, `az` is not
installed, or `az` is not signed in; plain `Status` is unchanged and works with no ADO at all. It never
writes, to a card or to the board.

#### Every tracker verb names the space it acts in

`NewPrompt`, `CloseItem`, `NewPR`, `MyWork`, `MyPRs` and `Dashboard` each print one header line
before they contact a tracker -- `[*] In <Space> (<tracker>)`, the active space's display name and
`ado`, `gh` or `local`. An id is unambiguous **within** a space; across two configured tenants the
same number names two different cards, and the active space decides which one silently. A guard
refuses a wrong-tenant write, but a refusal is read after the fact; the header line is read before
the number even resolves, so the product says where it stands rather than leaving a person to work
it out from an email string. `Scripts/Resolve-Tracker.ps1`'s `Write-P20TrackerHeader` is the
one place this is written.

#### A write to a public repository says so

On a GitHub Space, the verbs that write to the tracker -- `NewItem`, `EditItem`, `CloseItem`, `Route`
and `NewPR` -- print one line before they write when the repository they write to is public:

```text
[!] This repository is public
```

A public repository is read by strangers, and GitHub keeps an edited issue's first wording. The line
comes after the verb's reads and before its write, so the dry run shows it too -- `-WhatIf`, and
`NewItem`'s `-ReadOnly`. It is the line only: nothing is asked, so a script or the web's bridge runs
exactly as before. A private repository (gh's `INTERNAL` too), or one `gh` did not answer about,
prints nothing. `ReplyPR` replies on Azure DevOps only, so it has no line; an Azure DevOps Space, or one
with no tracker, has no visibility and `gh` is not asked. The rule is `Scripts/Get-RepoVisibility.ps1`
-- one `gh api repos/<owner>/<name>` per verb -- and the words are `consts.json` `visibility`, the same
three the agent's `GET /api/visibility` serves: `public`, `private`, `unknown`.

---

## Command reference

**43 always on, 57 with every opt-in module switched on.** The 43 are `config.default.json`'s
`commands`, and are below -- the Studio's `NewDesign`, `StampDesign`, `MoveDesign`, `NewSpace`, `RetireSpace` and `RemoveSpace` among them, because the Studio is
core ([Studio](modules/studio.md); D-S13); the fourteen the growth,
communication, organize and Team Agile modules contribute have their own table further down, each marked
with the flag that produces it.

As `{prefix}Command`. `tkMenu` lists them live; `tkMenu -All` shows everything;
`tkMenu -Markdown` emits these tables. Every command takes `-Help`, module verbs included.

### Cards and prompt files

| Command | Does |
| --- | --- |
| `NewPrompt <id>` | Create a prompt file from the board's tracker: an ADO work item, or on a GitHub board an issue (`gh issue view`; the repo comes from a repo-grained address or the board's one `projects[]` entry -- several repos refuse, because issue numbers are per-repo; a label naming a card type sets the type, else Task; assignment and a closed issue's reopen prompt mirror the ADO flow). The card is written to the Space's `backlog/` -- planned, not in play -- and with **`-Now`** to `current/`. If card `<id>` is already in `current/` or `backlog/` it is **returned, not overwritten** -- found by id, before any tracker call. On an Azure DevOps board it also reads the work item's comments, which needs an `az` token: with none (`az login` has not been run, or `az` printed nothing) it is a stated refusal (exit 2, naming `az login`) before any card is written or the work item assigned or moved |
| `NewPrompt -Title "..." [-Type <t>] [-Id <n>]` | The same file with **no ADO call** -- the Tier-2 way to start a card ([Tiers](#creating-a-card-with-no-ado)) |
| `NewPrompt ... -Cover <image>` / `-Before <image>` | Make the card **with its picture**, attached by the same code `Cover` runs -- for a GUI issue the snap is the report. The picture is checked first, so a refused one writes no card; on a card that is already in `current/` (returned, not overwritten) nothing is attached and the line says to use `Cover` ([A card's picture](#a-cards-picture-cover)) |
| `NewPrompt ... -Design <name\|id>` | Make the card **bound to the design it is worked against**: one header line under `> Template:` (after `> Previous round:` when there is one), `> Design: [<title>](<link>) <id>` -- the design's own title (a square bracket in it written round) and its whole id, the link relative to the card for a hub design and its page on GitHub (`/blob/HEAD/<path>`) for a repo design; a design with a spec links the spec. Resolved before anything is written or fetched, against the hub's `design/`, `spec/` and their archives, and the repository you stand in when its `origin` is one of the active Space's GitHub repos and it has `design/` -- one id in both is one design, and the repo's copy is named. What you type is read by the lifecycle's one rule (`Select-P20Design`, which `MoveDesign` asks too): a file name, its stem, or an id prefix of four or more. Nothing, or more than one, is a stated refusal (exit 2) and no card is written; on a card already in `current/` (returned, not overwritten) no line is written either. The corpus's hand-written `> Spec:` lines are read as written and never rewritten ([the card](hub/cards.md#2-the-sections----by-type-from-the-template)) |
| `NewItem <title>` | Create a work item (UserStory/Task/Bug/Feature) -- on a GitHub space, an issue: Bug/Feature fold to labels, `-Tags` become labels, `-Sprint` is the milestone, AC/repro join the body; `-Parent <n>` makes the new issue a sub-issue of `#n` -- GitHub's sub-issues route (`POST repos/<repo>/issues/<n>/sub_issues`, by the new issue's id) after the create, or, where GitHub refuses that route, a `- [ ] #<new>` line appended to `#n`'s body, the output saying which; the parent is read first, so a wrong number is refused (exit 2) with nothing created, and `-WhatIf` prints both calls and makes neither; `-Priority`/`-Points` are refused by name. `-FromDesign <note>` promotes a hub design note (the Studio's): the issue is the note's title and body, labelled `design`, and its URL is written back as the note's `> GitHub:` line ([Studio](modules/studio.md#the-verbs)) |
| `NewItem -FromCard <id>` | **Publish a card** made with no tracker, once its Space is on GitHub: one issue on the Space's repo, titled by the card's name (its heading after `<Type> <id>:`), its body the card's `## Summary` (template comments dropped; a `(TBD)` one leaves nothing) ending with the line `Toolkit card: <id>`; a Bug or Feature card folds to its label. The issue's URL is then written into the card's `**ADO Link:**` line through `Set-P20CardLine` -- nothing else in the card moves, and it keeps its line endings -- so the card reads `linked` and wears its **gh** badge from then on, and keeps its own id. Found in `current/`, then `archive/`, by the one id rule. Refused, exit 2 in one sentence, before anything is asked of GitHub: a card already linked, an id that is not a card, `-Title`/`-Description` beside it, a Space with no tracker, an Azure DevOps Space (publishing to Azure DevOps is not built). `-WhatIf` (the same dry run as `-ReadOnly`) prints the whole issue and writes nothing ([the card](hub/cards.md#3-the-footer----one-fact-per-line)) |
| `MyWork` | List work items assigned to you -- from the board's own tracker: WIQL through `az` on an ADO board, your assigned issues through `gh search issues` on a GitHub one (`-State open\|closed\|all` there, default open) |
| `MyPRs` | List your active pull requests across the org -- on a GitHub board, PRs you authored and PRs awaiting your review (`gh search prs`), owner-wide |
| `Dashboard` | Morning view -- PRs across projects, assigned items with staleness, recent pipeline runs. On a GitHub board the pipeline rows are Actions runs per repo (`gh run list`) |
| `Status [-Board]` | Active prompts with progress and last-modified, then the backlog folded to a count and its names (`Backlog (N), planned -- not in play:`). `-Board` is an opt-in, read-only join against the board: each linked card's work item state, `(differs)` on a `current/` card whose item is closed ([the two can disagree](#3-the-two-can-disagree-and-nothing-notices)); refused with ADO off, no `az` or no sign-in |
| `Archive <name>` | Move a prompt to `archive/` -- from `current/`, or from `backlog/` for a planned card retired without being in play -- and commit if the store is a git repo (`storeSync`). The commit stages the two folders the move touched (the one it left and `archive/`, nothing else in the hub), so a card created and archived before it was ever committed commits cleanly, and a tracked one is a rename. If git refuses the commit (a hook, say), the file has still moved: `Archive` states git's own sentence, exits 2 and says to commit it yourself or run `Sync`. A card that comes back for a second round first commits a rename of the earlier archived copy to `-r1`; if git refuses that commit, `Archive` stops before moving the card, names the rename, states git's own sentence and exits 2. A card that is already there answers `[=] Already archived: <path>` and exit 0: Archive touches no tracker, so twice is harmless. `CloseItem` and `NewPR` act on Azure DevOps and are not idempotent in this way |
| `Move <id\|file> -To Backlog\|Active\|InProgress\|CodeReview\|Done` | Move a card to a lane **by hand**, for a card with nothing checked in or no pull request: In Progress writes `**Started:**`, Code Review writes `**Review:**`, Done is `Archive` exactly. Active and Backlog move the FILE: `-To Active` pulls a planned card from `backlog/` into `current/`, `-To Backlog` parks an Active card -- refused, exit 2, when anything is threaded. A planned card moved to In Progress or Code Review is pulled into `current/` first. Found in `current/` or `backlog/`. A card travels one way; moving back is refused ([State](#state-three-machines-not-one)) |
| `Billable <id\|file> [-No]` | `-No` keeps a card **off Daily** and off Team Agile's standup; without it the card is billable again. A card is billable unless it says otherwise ([below](#the-third-line-billable)) |
| `Plan <id\|file> -Milestone <title>` / `Plan <id\|file> -Remove` | Plan a card into a sprint or milestone -- the write side of the `**Sprint:**` token (the read side already worked: the board's sprint filter and the card's tag). `-Milestone` writes the title **whole, never truncated**, through `Set-P20CardLine`; `-Remove` deletes the line. Never touches the tracker: the different, tracker-bound `-Sprint` on `NewItem`/`EditItem` sets a milestone on the work item itself, through `gh`/`az`. Found in `current/` or `backlog/`, and **never** pulls a planned card into play first -- being planned before being pulled into play is the point. Sprints stay opt-in at every grain: no verb here ever requires one ([the card](hub/cards.md#3-the-footer----one-fact-per-line)) |
| `Cover <id\|file> <image> [-Before] [-Remove] [-WhatIf]` / `Cover -Samples [-WhatIf]` | Give a card a picture: copied into the Space's `assets/<card key>/`, named by a `**Cover:**` line (or `**Before:**`). Found in `current/` or `archive/`; attaching again replaces the card's own picture; a card that came back takes `cover-r2`; `-Remove` deletes the picture and the line; with `storeSync: git` the two are one commit, and a commit git refuses is a stated refusal (exit 2) that says the picture and the line are already written; `-Samples` dresses the sample cards of an older Demo that have no cover ([below](#a-cards-picture-cover)) |
| `CloseItem <id> -Comment "..."` (formerly `CloseWorkItem`; `NewItem` was `NewAdoItem`, `EditItem` was `EditWorkItem` -- the old names still answer, with a one-time hint) | Close or resolve the tracker's card (`-Reason`, `-WhatIf`). On a GitHub board: `gh issue close`, where GitHub knows exactly two reasons -- the default and `Completed`/`Fixed` close as **completed**, the not-doing-it shorthands (`WontFix`, `Obsolete`, `Duplicate`, ...) close as **not planned**, and a word mapping to neither is refused with both named. The comment stays markdown there; GitHub renders it |
| `EditItem <id>` | Change what a work item says or wears -- title, description, sprint, assignee, tags (`-AddTag`/`-RemoveTag`, merged read-modify-write on ADO). On a GitHub space the words translate: tags are labels, `-Sprint` is the milestone, `-Description` is the body. `-Pin` / `-Unpin` are GitHub's own pin (`gh issue pin` / `gh issue unpin`), so a pinned issue sorts first on the Issues tab on every machine; GitHub pins three per repository and a fourth is refused as "GitHub pins three issues per repository; unpin one first"; on an Azure DevOps Space both are a stated refusal (exit 2) -- a work item has no pin. `-WhatIf` prints the exact edit, the pin included |
| `Connect <slug>` | Connect a Space to its tracker in four steps, each named as whose it is (settings by workflow W2, D-W12 to D-W17): `-Address <url>` is yours and we write it through `Config` (an address implies active; a Space shipped with an address and still `local`, the GitHub demo, reports step 1 not done until the same `-Address` connects it); signing in (`az login` / `gh auth login`) is yours, said and checked, never run; `-Discover` lists what the address holds and `-Projects` (Azure DevOps: the organisation's projects) or `-Repo` (GitHub: the one repo the Space IS) writes what you pick; `-Sprint true` is the last step. With no step it reports where the Space stands; `-AsJson` is the web wizard's form (`/connect/<slug>`); `-As <slug>` graduates a shipped demo Space (the Azure demo, `test`) into your own Space (its folder moved, made active); `-WhatIf` says the `Config` lines it would run. |

#### The bytes a card is written with

A card is a file in **your** store, so the tool owes it byte stability across the hosts that write
it. One contract, in one writer -- `Write-CardText`, in
[`Scripts/Write-CardText.ps1`](../Scripts/Write-CardText.ps1), dot-sourced by everything that puts a
file in the hub:

- **UTF-8, never a BOM.** Through `[System.IO.File]::WriteAllText` with a BOM-less `UTF8Encoding`,
  the same pattern `Prompt20Toolkit/Update-ToolkitManifest.ps1` uses, and for the same reason:
  `Set-Content -Encoding UTF8` means two different things -- Windows PowerShell 5.1 emits a BOM and
  PowerShell 7 does not, so the same verb on the same card produced different bytes depending on
  which shell ran it.
- **A file the tool CREATES is LF** -- `Write-CardText -New`, which normalises CRLF to LF once, in
  the writer. The switch is the contract: a create says so at the call site, and nothing else in the
  package normalises. It has to be there because on a Windows clone the content arrives CRLF from
  two directions at once -- `* text=auto` plus `core.autocrlf=true` checks `templates/*.template.md`
  out CRLF, and checks the `.ps1` files whose here-strings build card bodies out CRLF too -- so a
  writer that "wrote the string it was given" produced CRLF on the PC and LF on the Mac for the same
  verb into the same hub.
  Pinning `templates/*.md eol=lf` in `.gitattributes` would fix the template readers and leave the
  here-string builders alone, so it is not the fix.
- **A file the tool EDITS keeps the line ending it already has** -- the same writer with no `-New`,
  which reads the bytes on disk and writes the new content in the terminator the file already uses
  (a file with any CRLF in it is CRLF; a mixed file comes out consistent). The writer decides, not
  the caller, so no caller can forget the rule and leave a CRLF card with one bare-LF line, or a
  `> Template:` line the link repair cannot match.
  A card you edited in Notepad stays CRLF.
- **Every reader tolerates both.** The PowerShell parsers, `agent/core/parsers.py` and
  `agent/ado/reporting.py`'s stamp parse are multiline regexes, asserted CRLF-against-LF on both
  sides (`tkTestToolkit -Archive`, `Tests/test_parsers.py`).
- **The agent has one writer too.** `agent/core/cards.py`'s `write_card_text` is the edit half of
  this contract in Python: it reads the card's terminator and writes with it, UTF-8, no BOM. No
  route in the ADO core edits a card today -- the PR comments `save` that did was retired,
  because `ReplyPR` through the bridge already fills the same slot -- so the writer waits for the
  next native edit, held to the rule by `Tests/test_card_writer.py`. It has no create, on purpose.

Why it is worth a rule: with `storeSync: git`, a BOM that depends on the host, or a mixed ending the
next editor normalises, turns an archive commit into a whole-file diff that carries noise besides
the stamp.

**It is not only cards.** Every file the tool writes into the hub goes through the one writer:
the `manager/` session writers (`New-Meeting.ps1` and both of `Get-MeetingAgenda.ps1`'s), so a
session's first bytes do not depend on which verb touched it last and a close is not a whole-file
diff -- which is why the writer is its own file rather than part of `Add-ClosedStamp.ps1`;
the review scaffold `NewWorkReview` writes (`reviews/<slugs>/<year>/<range>/review.md`), through
`Write-CardText -New`;
and `New-PromptFromWorkItem.ps1`, `New-GrowthItem.ps1` and `Write-PeerReviewLog.ps1`, with no
`WriteAllText` of their own. A session is **not** an exception: it is a file the tool creates, so it
is LF like everything else, whatever `templates/ManagerSession.template.md` checked out as.

### Ship it

| Command | Does |
| --- | --- |
| `NewPR [<card>]` | PR + move card to Code Review + comment + write PR URL back to the file. `-WhatIf` resolves everything and calls nothing. On a GitHub board: `gh pr create` (repo from the checkout's github remote, else the board's one repo; `-Draft` and `-AutoComplete` map to draft and auto-merge), the PR body references the issue PLAINLY -- never `Closes #n`, because closing is `CloseItem`'s job -- and the ledger entry is a markdown comment on the issue; GitHub has no Code Review state to move, and the card's lane comes from the `PR URL:` line as ever. A card in `backlog/` is found too, and is moved to `current/` before its `PR URL:` is written |
| `PublishPR [<card>]` | Stage 2 of the ship flow: flip the card's draft pull request on Azure DevOps to ready. Reads the card's `PR URL:` line (the card by id or filename, else the one for this branch from the code repository), takes the token `NewPR` takes, confirms the pull request is an active draft, sends `PATCH .../pullrequests/{id}?api-version=7.1` with `{"isDraft":false}`, and writes one line under `PR URL:` -- `PR published: <url>`, once, not a dated stamp and not state. `-WhatIf` prints the exact call and sends nothing. Refused, exit 2 and nothing written: no `PR URL:` line, a pull request already ready or not active, and a GitHub pull request, whose hint is `gh pr ready <url>` |
| `GetPRComments [<id>]` | Fetch PR review comments and append to the prompt file -- every comment of every thread, a reviewer's follow-ups included; append-only and idempotent |
| `ReplyPR <pr> <thread> -Reply "..."` | Post a reply to a PR thread (`-Status` to set its state) and fill that thread's `Reply:` slot in the card -- the card in `current/` whose `PR URL:` names the PR, else the branch's |
| `ThreadHash [<id\|file>] [-Hash <h>]` | Thread **this repo's** branch commits into the Git section and PR replies. Run it from the code repo. A card in `backlog/` is found too, and its first thread moves it to `current/` before writing |
| `AddPRReview <pr>` | Post an AI code review to a PR as inline comments (`-DryRun` to preview) |
| `Sync` | Pull with rebase, then push, on the prompt store -- when `storeSync` is `git` (the hub's `hub.json`, or `config.local.json` per machine). The hub must be the **root** of its own repository: a hub sitting inside some other repository is refused before anything is committed, because `git add -A` from a subfolder stages that whole repository |

**Where `NewPR` gets its facts.** From the code repository, on the work branch, everything is inferred:
the branch finds the card, and the card gives the work item, title and described changes. Named from
anywhere else -- `tkNewPR 119`, or *Create PR* in the browser, whose verbs run in the Toolkit's own
folder -- the **card** answers instead: its `ADO Link` names the project, and the first line of its
`## Branch` section is the source branch. The Toolkit's own checkout is never read as a card's code
repository. A project or repository it cannot tell is a stated refusal naming `-Project` and
`-Repository`; it never defaults to the first configured project, which for a write is a guess that
opens a pull request somewhere unrelated. `GetPRComments` with no id and no branch refuses in the
Toolkit's folder for the same reason.
Before it creates anything, `NewPR` asks Azure DevOps whether the source branch exists there. From the
browser there is no checkout to push from, so a branch that was never pushed is refused with the
`git push` to run, instead of Azure DevOps' bare `400 (Bad Request)`. Any other rejection shows the
sentence Azure DevOps sent back, not just the status code.

**The Toolkit and the hub must each be the root of their own repository, or not be in one at all.**
`git rev-parse --is-inside-work-tree` searches UPWARD, so a plain folder anywhere under another
repository answers "yes" and every git command afterwards would run against that other repository:
`Update` would fast-forward a monorepo and `Sync` would commit and push a dotfiles repo, reporting
success. So both compare `rev-parse --show-toplevel` with the folder itself (`Scripts/Test-GitRoot.ps1`) and refuse with a hint naming the repository they found instead.
`BackfillStamps` asks a different question on purpose: it READS history, a hub that is a tracked
subfolder of its own repository is legitimate, and what it refuses is a repository that tracks none
of the hub's files.

### Environment

| Command | Does |
| --- | --- |
| `Menu` | Discover commands (`-All`, `-Markdown`, `-Help`). **It shows what this machine can use:** with Azure DevOps not in use -- `features.ado`, else the status of the org you are in -- the ADO verbs' rows are not listed, what is left of "Pull Requests" and "Work Items" is listed with the rest under **Cards**, and `NewPrompt` describes making a card. In an `active` org nothing changes. `-All` names Azure DevOps in its opt-in inventory either way, with the line that changes it. The verbs stay registered: typed by name they still answer, with their tier sentence ([Azure DevOps](modules/ado.md), "Tiers: what happens when ADO does not answer") |
| `Env` | `Version:` (the product's, `consts.json`'s `version`), machine, OS, tier, hub (`[--] Hub  not configured -- run {prefix}Start` as a note until someone SAID where it is -- `PROMPTS_ROOT` or `promptsRoot`, the test `Start` uses -- rather than a green tick on the folder above the package), active org, az identity, and which commands the tier allows. On a GitHub Space, `Visibility:` under the org -- `public`, `private`, or `unknown` when the tracker did not answer |
| `Setup` | Check what the tool NEEDS and **state the tier** this machine runs at. What is optional is a note (`[--]`), never a warning or a failure: `az` is looked for only when Azure DevOps is in use, and a machine working from its cards is told nothing is missing |
| `SwitchSpace <slug>` | Change the active Space (`SwitchSpace Status` to check: it names each GitHub Space's repository visibility -- `(public)`, `(private)`, `(unknown)` for one not `active` or not answered); a slug that names no Space is refused, exit 2, with the slugs it knows. `SwitchOrg` still answers, with a one-time hint |
| `Config` | Read and write this machine's configuration -- the one writer for `config.local.json` and the hub's `hub.json` (`-List`, `-Set <key>=<value>`, `-Unset <key>`, `-Schema`, `-AsJson`, `-Local`, `-Hub`). `-Unset spaces.<slug> -Hub` un-declares a whole Space -- its entry leaves `hub.json`; refused for the Space you are in and for one `config.default.json` ships -- and `-Unset spaces.<slug>` drops this machine's patch for it; neither touches the Space's folder (the two lines `RemoveSpace` runs). A successful write of a `features.*` key ends with one note -- open shells keep their menu until they re-import; the agent and the web UI see it on the next request. [Configuration](CONFIGURATION.md) |
| `InstallAutoload` | Install the module shim so commands autoload everywhere. `-Remove` takes it back out of every Modules folder it is in (link or copy; never the checkout), prints each path, says `nothing to remove` when there is none, and checks in a cold `-NoProfile` shell that the commands no longer resolve; `-WhatIf` prints and removes nothing; `-Remove -Force` is refused (exit 2). [Quick start](QUICKSTART.md), "Removing ToolKit" |
| `Start` | The first run. Copies the sample hub (`samples/hub`) to a folder you own -- `-Path`, default `~/toolkit-hub` -- points this machine at it (`promptsRoot`, `activeSpace=demo`, the four opt-in modules on -- growth, communication, deck and organize --, all through `Config`), re-imports, and opens the web UI (`-NoWeb` to skip). The sample org is `local`: no ADO, no login. **Never overwrites**: a machine that already has a hub keeps it; a folder with anything in it, a folder inside the Toolkit, and a configured hub that has gone missing are refusals (exit 2) that change nothing. `-WhatIf` says what it would do |
| `Update` | Bring this machine's Toolkit up to date: pull it, **fast-forward only**, re-import it into this shell, and say what else moved -- the autoload shim, the web UI's lockfile, the agent's requirements. `-Sync` then syncs the prompt store: software first, then data. `-WhatIf` fetches and reports. Never commits, rebases or pushes the Toolkit. The package must be the **root** of its own checkout; a copy inside another repository is refused rather than fast-forwarding that one |
| `Log` | Diagnostic log (`-Errors`, `-Today`, `-Days <n>`, `-Count <n>`, `-Command`, `-Type`, `-Clear`; `-Tail` follows live) |

#### Navigation shortcuts

The menu's first category is **Navigation**, and it ships empty on purpose: the four shortcuts in
`config.default.json` -- `Hub` (your prompt hub), `Home`, `Repos` (the workspace root) and `Prompt`
(this package) -- carry no path, because a path is personal and
belongs in the gitignored `config.local.json`. Until one has a path the category renders its title
and `not configured`, with the line that fills it in:

```text
  Navigation
    not configured
      tkConfig -Set aliases.Home.path=<path>
```

Set one and it registers as `{prefix}Home`, listed like any other command. **The keys are bare.**
`Home`, not `tkHome`: the prefix is applied when the alias is registered and again when the menu
renders it, so changing `commandPrefix` moves the shortcuts with the verbs instead of leaving a
frozen `tk` behind -- and `Register-PromptAlias -Prefix gt` yields `gtHome` from the same config. A
`config.local.json` that still spells a key with the prefix keeps working: it is read as the bare
name, once, with a warning naming the canonical spelling.

**A shipped name autoloads; a name of your own does not.** The autoload manifest is committed, so it
exports only the names `config.default.json` declares -- which is why they ship with empty paths
rather than not at all. `tkHub` typed first in a brand-new shell loads the module and goes. A name
that exists only in your `config.local.json` works once any other command has loaded the module.
It is shown as soon as it has a path: `tkConfig -Set aliases.Bowling.path=~/Repos/BowlingApp` writes
`"display": true` beside it in the same write and says, once, that the name answers after the module
has loaded. `"display": false` hides it (a hidden alias is skipped, not merely left off the menu).
Add your own with any name:

```jsonc
// config.local.json
{ "aliases": { "Bowling": { "path": "~/Repos/BowlingApp", "display": true, "description": "Bowling app" } } }
```

A shortcut that must survive a profile-less shell needs its name in `config.default.json` (an empty
path is enough) -- the autoload manifest is generated from the committed config, so one that exists
only in `config.local.json` is, by construction, local.

#### Working in the package and the hub at once

The package and the hub are two repositories, and a lot of real work involves both. For example,
you notice something in the hub, such as a `tkSync` warning or a card with a broken link, and the
fix for it belongs in the package. If you open one repo per editor window,
the other repo is out of reach: search doesn't cover it, a relative link into it gets no
completion, and nothing warns you when such a link is broken.

**Open both as one VS Code workspace.** Save a `.code-workspace` file in the folder above the two
repos (the one `tkRepos` goes to). Keep it outside both repos, because the folder names are yours:

```jsonc
// <workspace root>/toolkit.code-workspace
{
  "folders": [
    { "path": "toolkit",     "name": "package" },
    { "path": "toolkit-hub", "name": "hub" }
  ],
  "settings": { "markdown.validate.enabled": true }
}
```

Open it with File > Open Workspace from File. The two repos then share one explorer, one search and
one git view. Markdown path completion (`](../`), ctrl+click and broken-link checking reach from a
card into the package and back. With `markdown.validate.enabled` on, a card's `> Template:` link
that points nowhere is flagged in the editor, so you don't only find out when a sync prints a
warning.

**An assistant needs the same reach.** Claude Code sessions start in one folder. List the other repo
in that repo's `.claude/settings.local.json`, and do the same in the other repo pointing back. That
file is gitignored because the path is specific to one machine:

```json
{ "permissions": { "additionalDirectories": ["<workspace root>/toolkit-hub"] } }
```

**Issues don't link across repos.** An issue names package files as repo-relative paths in backticks
(`Scripts/Repair-CardLinks.ps1:87`). It names hub files by their path and the hub commit, because a
link into the hub is only correct on the machine where it was written. The
only links that cross between the repos are the two in a card, and the Toolkit writes those itself
and repairs them on `Sync`.

### Keeping a machine current: `Update`, and why it is not `Sync -All`

```powershell
tkUpdate              # pull the Toolkit, re-import it, say what else moved
tkUpdate -Sync        # ...then sync the prompt store
tkUpdate -WhatIf      # am I stale? fetch and report, change nothing
```

Updating a machine by hand is three things to remember -- `git pull` in whatever folder the checkout
is in, re-import the module in the open shell, and re-run `tkInstallAutoload -Force` if the alias set
moved -- and the third is the one that fails quietly: a verb that works after an explicit import and
is "not recognized" in a profile-less shell. `Update` does the first two and **notices** the third,
along with a changed `web/package-lock.json` (`npm ci`), changed agent requirements (`pip
install`), and an assistant's copy of `AGENTS.md` that is behind its source
(`Scripts/Update-AgentDocs.ps1`, which regenerates every copy -- the one in the checkout and the one in
your home folder, each checked on its own; it reads `AGENTS.md` as UTF-8 and writes through `Write-CardText`, so Windows PowerShell 5.1 and 7 render and accept the same bytes). It names the command; it does not run it. The `pip install` line names the Python that answers on
this machine (`python` on Windows, where `python3` is the Store stub); if none answers, it says
`python3 is a guess` and why, rather than guessing quietly. `Setup` reports the same copy check. It also notices a Demo copied out before the sample cards had covers
and names `Cover -Samples` (a count and the command, once; it writes nothing).

**It refuses rather than guesses.** The Toolkit is software, so this verb never auto-commits it,
never rebases it and never pushes it -- it fast-forwards or it stops. Uncommitted changes to tracked
files, a detached HEAD, a branch with no upstream, local commits that have diverged from the remote,
and a Toolkit that was installed as a copy are each a stated refusal (exit 2) that changes nothing.
An untracked scratch file is not a reason to refuse, and local commits with nothing to pull are
mentioned rather than pushed. It finds its repository from where the script sits, never from the
current directory, and never from `promptsRoot`.

**Why `-Sync` is here and not an `-All` on `Sync`.** `Sync` is the *data* verb: it auto-commits your
cards, pulls with rebase and pushes the hub. The rules for the *software* are the opposite, and one
command running two repositories under opposite rules is how a bad afternoon starts -- "data separate
from software" is this tool's oldest rule. So the two stay two verbs, and the one whose name already
says "change this machine" may call the other: after the re-import, so the sync runs the code that
was just pulled, and **never after a refusal** -- a refused update is a stop, not a detour. It goes
through the `Sync` verb, not around it, so `storeSync`, the refusal contract and the log are the
verb's own.

### The other two halves

| Command | Does |
| --- | --- |
| `Web` | Start, stop or check the web UI. Bare: the Docker production build. `-Dev`: Vite and the agent on the host, hot reload. `-Restart`: stop both, start again (production unless `-Dev` is given too). `-Stop`: the server, any dev server left on its port, and the agent. `-Status`: what is up, on which port. `-NoBrowser`: do not open the URL. `-Dev -Fixture [-Modules on\|off]`: the smoke's servers -- this checkout's agent restarted against `Tests/fixtures/hub` as a test run, Space and flags through its environment, no webhook, `config.local.json` never written |
| `Agent` | Start, stop or check the agent alone, on `web.agentPort`. `-Dev` reloads on edit. `-Stop` ends the one this command started. `-Status`: running, healthy, which hub -- and any listener that is not ours. `-Port <n>` overrides the port for one run |

**It opens the UI.** All three start paths -- production, `-Restart` and `-Dev` -- open the URL in
the default browser once the server answers, because bringing the UI up for the person who typed the
command is what the command is for. The URL is the one the server actually printed (Vite takes the
next free port silently) or, in production, the one `web/docker-compose.yml` publishes. It is
skipped in three cases, and then the URL is printed to open by hand instead: `-NoBrowser`, a `CI`
environment variable, and a non-interactive session -- no `UserInteractive`, or a redirected stdout,
which is what an agent tool call and a CI step look like. "No popup ever, unless I act on it":
typing the command is that act, a script running it is not.

`Web -Dev` starts both halves and returns, rather than holding the terminal, so `Web -Status`
reports each of them and `Web -Stop` ends both. The port the agent listens on is
`web.agentPort` in config ([Configuration](CONFIGURATION.md#what-tkconfig-writes-and-where)), not a number in either script.
Vite asks for 5174 and takes the next free port, so `Web -Status` reads the URL back out of
`web.log` rather than printing one that is merely likely.

**`Web -Dev -Fixture` starts the servers `npm run smoke` asserts, and writes nothing**.
The fixture hub, its Space and the module flags reach the servers through their environment and
nothing else, so a smoke run never rewrites the machine's own `config.local.json`; and the run marker
keeps a webhook in `.env` -- which the module reads into the shell at import, out of reach of any
`unset` -- from arming a live send button. How to run the smoke itself is
[Testing](TESTING.md); what the switch sets is this:

| Variable | Value | What it does |
| --- | --- | --- |
| `P20_TEST_RUN` (`consts.json` `env.testRunMarker`) | `fixture` | The Teams engine refuses a POST, and every bridge child skips `.env` at import |
| `PROMPTS_ROOT` | `Tests/fixtures/hub` | The hub, as it has always been overridable |
| `P20_ACTIVE_SPACE` (`env.activeSpace`) | `test` | Stands in for `config.local.json`'s `activeSpace` |
| `P20_FEATURES` (`env.features`) | `{}`, or growth and communication with `-Modules on` | Stands in for its top-level `features` block |
| every `TEAMS_WEBHOOK_*` | removed | Not handed to either server, whatever the shell holds |

This checkout's agent is **restarted**, never reused -- a running agent's environment can be neither
read nor changed, and a fixture agent started with the other `-Modules` is indistinguishable from
outside -- and `Agent -Stop` still ends only this checkout's. The variables are applied to the
launcher's own process for the length of the start, so `Agent`'s hub check asks the same question
its child will, and put back afterwards: the shell keeps its webhooks. A running dev server is
reused; Vite reads none of this. `-Modules` without `-Fixture`, and `-Fixture` without `-Dev` (or
with `-Stop` / `-Status`), are stated refusals. Plain `Web -Dev` afterwards goes back to your own
hub: it sees an agent of this checkout serving the fixture hub and restarts it
([Configuration](CONFIGURATION.md) has the two overrides; `web/README.md`, "The smoke test", the run).

**`-Stop` stops the process tree, and `-Status` trusts the port as well as the PID file.** The PID
recorded at start is `npm`; the process holding the socket is its `vite` child. Killing the parent
alone would leave a live server on 5174 that `-Status` denies and `-Stop` will not touch -- and
`npm run smoke` defaults to that port, so the orphan could quietly serve a *stale* tree to a passing
test run. So `-Stop` walks the descendants (`pgrep -P` on macOS and Linux,
`Win32_Process` children on Windows), and both verbs probe the dev port -- the one
`web/vite.config.ts` asks for **and** the one Vite actually took.

**The sweep stops a dev server and nothing else.** A listener the toolkit did not start is named
with its PID either way, but it is only *stopped* if its image is `node`, which is what Vite runs
in. Anything else gets `Port 5174 is held by <name> (PID <n>) -- not a dev server; not stopping it`
from both `-Status` and `-Stop`. In production mode the only listeners on that port are Docker
Desktop's own forwards, and force-killing them takes the Docker backend down, which makes the
`docker compose down` about to run impossible: the container is left defined and every other
container goes with it. For the same reason `-Stop` and
`-Restart` run `docker compose down` **first** -- the container's forward has to be gone before
anything looks at the port. Being unrecognised is not evidence of being an orphan.

**`Agent -Status` looks at the port, not only at its own PID file.** Before starting, and in
`-Status`, it asks who is listening on `web.agentPort` and -- if anything answers `/api/health` --
which hub that listener reports. Three outcomes: an agent on **this** hub that this command did not
record is **reused** and named (a lost PID file, or another shell's; `-Stop` will not stop it, and
the message says so); anything else is a **stated refusal** naming the PID, the process and the hub
it serves, suggesting `Agent -Port <n>`; and `-Status` reports the same listener rather than "not
running". The case is real: on a machine migrating from the predecessor package, its agent sits on
`0.0.0.0:4100`, Windows lets this one bind `127.0.0.1:4100` beside it, and `localhost` resolves to
the more specific socket -- so the browser, the Vite proxy and `npm run smoke` read whichever hub
wins, and a PID-file check denies a listener `curl` can reach.
**Ours is a question about the checkout, not the PID file**: `/api/health` reports
`package_root` -- which checkout the process runs from -- beside `prompts_root`, whose hub it
serves, so `-Stop` stops this checkout's agent wherever it was started (including from another
shell) and names anything else without touching it. An agent of this checkout serving a different
hub from the one the caller's environment asks for (`PROMPTS_ROOT` set after it started) is
**restarted**, not reused, because the override can only win in a process started with it. Every
reuse prints `Serving hub:`. An agent started from an older build reports no `package_root` and
reads as foreign until it is restarted once.

**Both launchers return, including through a pipe.** `Agent` and `Web -Dev` hand back a PID and a
URL and end; the servers keep running. (So does `StartWork -Launch`, a third caller of the same
launcher: it hands back a session's PID and its log.) That has to hold when the caller reads the output through a
pipe -- `pwsh -c "tkAgent" | Out-String`, an agent tool call, a CI step. On Windows a child started
the plain way inherits every inheritable handle the caller holds along with the two log files -- its
stdout, the second copy of stdout Windows PowerShell 5.1 keeps, any pipe the caller itself inherited --
so the reader never sees EOF and the call sits until the agent is stopped. Both start their child through
`Scripts/Start-Detached.ps1`, the one place that owns "start it, log it, return", and it keeps every
pipe but stdin from crossing.

**And on macOS and Linux, a server gets a session of its own.** .NET starts a child in the caller's
process group with the caller's stdin, so a server started that way from a terminal shares that
terminal with the shell that started it. Vite, finding a TTY on stdin, binds its keyboard shortcuts
there and puts the terminal into raw mode, and the shell's readline goes quiet -- "pwsh freezes when I
start `tkWeb -Dev`"; a Ctrl+C in that terminal reaches both servers; and a server started from an agent
tool call dies when the tool call's shell is reaped, still being in its session. `Start-Detached.ps1`
wraps the command, off Windows, in a session leader (`Resolve-SessionLeader`): a perl one-liner
that starts a new session, opens `/dev/null` as stdin -- or the file a launch names (`-StdInFile`,
how `StartWork -Launch` hands a session its prompt) -- opens the two log files as its stdout and stderr,
and execs the command in place, so the PID the launcher records is the server's own. The log files are
opened by the child on purpose: `Start-Process`'s redirection off Windows is a pipe that pwsh copies
into the file only while pwsh lives, so everything a server wrote after `tkAgent` or `tkWeb -Dev`
returned used to be lost, and the log stopped at its startup lines. `Web -Dev` also hands Vite `CI=true` in the child's environment
only (`-Environment`), Vite's documented switch for not exiting when stdin ends and not binding
shortcuts -- the launcher itself never exports it, because `Test-BrowserAllowed` reads `$env:CI` as
"no person is here". Windows keeps its own console handles and gets the `CI=true` half.

**And on Windows, `npm` is not a program.** A current Node install ships `npm.ps1`, `npm.cmd` and a
bash `npm` side by side, and PowerShell's `Get-Command npm` answers the `.ps1` -- which
`Start-Process` cannot use as a process image, and neither can it use the `.cmd`; handed either, it
fails with `%1 is not a valid Win32 application`. `Scripts/Start-Detached.ps1` owns both halves of the answer: `Resolve-LaunchExecutable` asks
for an **Application**, never an ExternalScript, and `Resolve-DetachedCommand` launches a `.cmd` or
`.bat` through `cmd.exe /d /s /c "<shim> <args>"` with each argument quoted. Anything that is
already a process image -- `python.exe`, the Mac's `npm` -- is passed through untouched, so this is
a Windows widening rather than a change of launch method. A `.cmd` shim costs one extra process
between the launcher and Vite, which `-Stop` already handles because it stops the tree rather than
the PID.

### The Studio: Spaces and design notes

The Studio is part of the core, from the first run (D-S13): there is no
`features.studio`, and `Config -Set features.studio=...` is refused with one sentence saying so -- a line
left in `config.local.json` is ignored. Its verbs are core verbs, in the autoload manifest, `Menu`
(under **Studio**), `-Help` and the bridge like every other ([Studio](modules/studio.md)). `NewSpace`
sits with them because the Studio's Spaces card is where a Space is added, with its **+** --
and `RetireSpace` and `RemoveSpace` because a Space's row on that card is where it ends.

| Command | Does |
| --- | --- |
| `NewSpace [<slug>] [-Repo <owner/name>] [-Address <url>] [-Name <text>] [-Discover] [-Owner <owner>] [-AsJson] [-WhatIf]` | Add a Space. **`-Repo owner/name`** is a GitHub Space (status `active`, address `https://github.com/owner/name`; a pasted `https://github.com/owner/name(.git)` reads the same): the slug is the repository's name lowercased with every run of anything else one dash, the name is it with dashes, underscores and dots as spaces and each word capitalised (`juggling-engine` -> `Juggling Engine`); `<slug>` and `-Name` change either. **`<slug> -Address <url>`** is an Azure DevOps organisation (`active`); its projects are not discovered here -- the output names `Connect <slug> -Discover` as the next step. **`<slug>` alone** is your own cards, no tracker (`local`). Every key is written **through `Config`** into the hub's `hub.json` (one in-process call, `-Hub`), then `<hub>/<slug>/current` and `archive` are made; a folder already there is **adopted, never touched**, and its cards are counted (removing a Space never deletes its folder, so adding it again brings them back). With `gh` signed in the repository is checked and `PUBLIC` or `PRIVATE` said, followed by `ARCHIVED` when GitHub has archived it (the same one `gh repo view` call reads both, and the Space's status stays `active` -- it is the engineer's word, not GitHub's) and `READ-ONLY` when the account can read the repository and not write to it (`viewerPermission` `TRIAGE` or `READ`, from the same call; still added -- you can keep cards for a project you contribute to); a repository the login cannot see is added anyway and the line says it was `not visible to this login`, with the line `gh` answered; with no `gh`, or `gh` signed out, the Space is added anyway and the line says the repository was not checked. It does **not** switch: the last line is `SwitchSpace <slug>`. Refused, exit 2, one sentence each: no arguments (the three forms named), a slug or folder already declared (or the hub's own folder, `growth` and the like), a slug that is not `^[a-z][a-z0-9-]*$`, `-Repo` not `owner/name`, `-Repo` with `-Address`, a repository that is already a Space (named), an Azure DevOps address with no slug. `-WhatIf` prints every `Config` line and the folder, and writes nothing; `-AsJson` answers one object (slug, name, status, address, folder, adopted, cards, visibility, isArchived, viewerPermission, readOnly) for the bridge. **`-Discover`** lists the signed-in account's repositories (`gh repo list`), marks the ones already Spaces and the ones GitHub has archived (an `ARCHIVED` tag before the line; each row carries `isArchived` in `-AsJson`) and prints the exact `NewSpace -Repo` line for each -- the + dialog's picker reads it as `GET /api/spaces/candidates`; with no `gh` it says what is unavailable and why. **`-Discover -Owner <owner>`** lists someone else's: a user's or an organisation's (`gh repo list <owner>`), or, with the word `collaborator`, the repositories shared with you (`gh api user/repos`, the affiliation, `per_page` and `page` sent as `-f` fields, a page of 100 at a time); every row says `READ-ONLY` where you can only read, and the list ends with the owners you can name (`Owners: you (yours), your organisations, collaborator`, from `gh api user/orgs`). An owner `gh` cannot see is refused, exit 2, with the line `gh` answered; an owner that is not letters, digits and dashes, and `-Owner` without `-Discover`, are refused too. **A list is read to 1000** -- an owner's, the ones shared with you, your organisations: past that the first 1000 are listed, the count says `(the first 1000)` and a line says there are more and how to reach one past them (`ceiling` and `more` in `-AsJson`). **`-Discover -Repo owner/name`** reads one repository before it is added -- the same `gh repo view` the Add makes -- and prints its visibility, its marks and the line that adds it; a repository the login cannot see is printed all the same, `unknown`, with `not visible to this login: gh answered '...'` and that it can still be added, exit 0 (in `-AsJson` one row, `visibility` `UNKNOWN` and a `note`). It is what the dialog's **Add owner/name** row reads. `-Discover -Repo` with `-Owner` is refused, exit 2. A repository you know the name of needs no listing: `-Repo owner/name` takes any repository the login can read ([Configuration](CONFIGURATION.md#adding-a-space), [Studio](modules/studio.md)) |
| `RetireSpace <slug> [-WhatIf]` | Retire a Space: the engagement is over, keep the record. The Space stays declared with status `archive` -- its cards stay where they are and stay readable, Daily and reviews still count them, its row on the Studio's Spaces card moves under **Archive**, and nothing asks its tracker again (an archived Space is never Azure DevOps-enabled). Written **through `Config`** (`Config -Set spaces.<slug>.status=archive -Hub`, in process); a `status` this machine overrides in `config.local.json` is unset with it, so the retire holds here too. The output names the folder and its cards, and the `Config` line that brings the Space back to the status it had. A Space already archived is said, exit 0, nothing written. Any declared Space may be retired, the shipped Azure demo and the one you are in included. Refused, exit 2, one sentence each: no slug, a slug that is not declared. `-WhatIf` prints the `Config` lines and the folder that stays, and writes nothing ([Configuration](CONFIGURATION.md#retiring-or-removing-a-space), [Studio](modules/studio.md)) |
| `RemoveSpace <slug> [-Force] [-WhatIf]` | Remove a Space: it should never have been one, or it is truly gone. The Space is **un-declared**: its entry leaves `hub.json` (`Config -Unset spaces.<slug> -Hub`) and this machine's `config.local.json` patch for it goes too (`Config -Unset spaces.<slug>`), both through `Config`, in process. **Removing never deletes a card**: the folder stays in the hub exactly as it was, and the output says where it is, how many cards it holds (current and archive), and the line that brings them back -- `NewSpace <folder>` with the Space's own `-Repo` or `-Address` and `-Name`, which adopts the folder untouched (or the `Config` line, for a folder that is not a slug). Deleting the folder is a person's act, in their own file manager. Refused, exit 2, one sentence each: no slug; a slug that is not declared; the Space you are in (switch first); a Space `config.default.json` ships (the team's -- hide it with `isDemoDismissed` or retire it). A Space with cards in `current/` asks first, naming the count (`[y/N]`; anything but yes changes nothing); a caller that cannot answer -- the bridge, a script, redirected input -- is refused without **`-Force`**, which removes without asking. `-WhatIf` prints the keys that would go and the folder that would stay, with its cards counted, and writes nothing ([Configuration](CONFIGURATION.md#retiring-or-removing-a-space), [Studio](modules/studio.md)) |
| `NewDesign -Title <t> [-Description <text>] [-Space <slug>]` | Scaffold a design note into the hub's `design/` from `templates/DesignNote.template.md`: the frontmatter `id:` (a fresh UUID v4), description (and the Space it is for), the title, the template's headings, a `**Created:**` stamp. The file is the title's slug; never overwrites ([Studio](modules/studio.md), [the shape](hub/design.md)) |
| `StampDesign [-Hub] [-WhatIf]` | Give every design note and spec an `id:` (design lifecycle L1; the identity rule is [the shape](hub/design.md), "The file"): walks `design/`, `design/archive/`, `spec/` and `spec/archive/` of the git root of the current directory (printed on the first line; it must hold `design/`) and adds `id: <uuid>` to the frontmatter of every markdown file that has none, creating the block where there is none. A spec takes the id of the note whose stem it shares (`design/x.md` and `spec/x.spec.md`); an id already there is never changed, a file that needs nothing is not written, a second run writes nothing, each file keeps its own line endings, `README.md` is skipped. `-Hub` works on the hub's `design/` and `spec/` (and a declared Space folder's own) instead. `-WhatIf` names every file and writes none. It stamps; it does not commit ([Studio](modules/studio.md), [the shape](hub/design.md)) |
| `MoveDesign <name\|id> -To Spec\|Archive\|Complete [-Dropped] [-Reason <text>] [-Doc <path>] [-Hub] [-Space <slug>] [-WhatIf]` | Move a design along its road (design lifecycle L3; the states are [the shape](hub/design.md), "State -- derived, never stored"). The design is a note's or spec's file name, the stem both share, or any unique prefix of its id (four characters or more); its state is read from where its files are, and the verb refuses by that rule, exit 2 and one sentence. `-To Spec` scaffolds `spec/<stem>.spec.md` from `templates/Spec.template.md` with the note's id, description and thread (the note stays); refused for a spec standing alone, a design that already has its spec, or an archived note. `-To Archive` moves the note to `design/archive/` and stamps `**Closed:**` and `**Outcome:** shipped`, or `dropped` with `-Dropped`, which needs `-Reason`; refused while the spec is live. `-To Complete` moves the spec to `spec/archive/` and the note to `design/archive/` in one go, stamps both and writes `> Docs: <path>` into the spec; `-Doc` must exist in the same tree. Every move appends one dated, self-contained line to the note's `## Journey` (the first move adds the note's birth line, dated from `**Created:**`); `-Reason` joins any line. In a repo it names the git root first, STAGES (`git mv`, `git add`) and never commits, printing the commit line it suggests; `-Hub` works on the hub's folders, `-Hub -Space <slug>` on that Space's own, and follows `storeSync` the way `Archive` does, so a commit git refuses is a stated refusal (exit 2) that says the files are already moved. Never overwrites; `-WhatIf` prints every move and stamp and writes nothing ([Studio](modules/studio.md), [the shape](hub/design.md)) |

### The opt-in modules' verbs

These fourteen exist **only** when their module's flag is on. With the flag off there is no alias, no
command row in `tkMenu`, no `-Help` and nothing for the bridge to call -- they are absent, not
refused ([the modules guide](modules/README.md)). The one place an off module is *named* is the
`Opt in by configuration` block at the foot of `tkMenu -All` and in `tkEnv` -- each row led by the
question it answers, in the person's words, from `Config/settings-workflows.json` (settings by
workflow, [CONFIGURATION.md](CONFIGURATION.md#settings-by-workflow-the-questions-and-the-one-list-behind-them);
`Get-P20SurfaceInventory` is the same inventory as one JSON, for the agent) -- which say the module
exists and which key switches it on; naming a surface is not mounting it
([AGENTS.md](../AGENTS.md), "Opt in by configuration"). Flags below are the ones each script's
`param()` block declares. Team Agile's three are the one case with a second condition: its flag
resolves on only where the Space you are in answers `agents` to "How do you want to work in \<Space>?"
(`spaces[].howIWork`, [CONFIGURATION.md](CONFIGURATION.md#spaceshowiwork----how-you-work-in-this-space)),
so in a Space worked alone -- or on Azure DevOps, or with no tracker -- they are absent like a module that
is off, and `SwitchSpace` brings them back in one that works with agents.

| Command | Flag | Does |
| --- | --- | --- |
| `NewGrowth -Title <t> [-Type training\|presentation\|goal] [-Date <d>] [-DueDate <d> (required for a training)] [-Provider <p>] [-Hours <h>] [-Notes <n>]` | `features.growth` | Create a training, presentation or goal artifact under `growth/current/`. `training` is the **default** type and a training **needs** `-DueDate`, so the shortest form the usage suggests is the one that is refused |
| `NewWorkReview -StartDate <d> -EndDate <d> [-Slugs <csv>]` | `features.growth` | Generate a work review scaffold for a date range from local history. Answers JSON on stdout, because the agent parses it |
| `PublishWorkReview [-NoPush] [-Preview]` | `features.growth` | Stage and commit `reviews/`, then sync the hub. `-Preview` emits the pending diff as JSON instead |
| `UpdateResume [-NoPush] [-Preview]` | `features.growth` | The same three for `resume/` |
| `LogPeerReview <id> [-Title <t>] [-Notes <n>]` | `features.growth` | Log a completed review of someone else's PR. The one thing growth writes that is **org**-scoped: it lands in the active Space's `pr-comments/` |
| `SendTeams <recipient> <message> [-Session <file>] [-WhatIf] [-AsJson]` | `features.communication` | Post one line to a Teams recipient through the communication engine. `-Session` names the meeting record in `manager/current/` the send is for, and a sent message is noted under its `## Sent` |
| `NewMeeting [-Date <YYYY-MM-DD>]` | `features.communication` | Scaffold a 1:1 session from `templates/ManagerSession.template.md`. Never overwrites, and refuses a date already closed into `manager/archive/`. Created out of order, it prints a `Check:` line naming the later session whose `## Carried from` heading is now stale ([Which session a record carries from](hub/manager.md#which-session-a-record-carries-from)) |
| `MeetingAgenda [-Plan] [-Prep] [-Retro] [-Close] [-Date <d>] [-Type <t>] [-DryRun]` | `features.communication` | Drive a session through its stages -- plan, prep, retro -- and `-Close` it: the file moves to `manager/archive/` and is stamped `**Closed:**`. A `Check:` line says when a session's `## Carried from` heading no longer names the latest earlier session; nothing rewrites it |
| `NewReminder -Title <t> [-Due <when>] [-Source <tag>] [-Ref <ref>]` | `features.organize` | Create a reminder in `reminders/current/` with a fresh short id. `-Due` takes a date, a date and time, or `1h` / `tomorrow` / `nextweek`. Never overwrites |
| `Reminders [<id>] [-Snooze 1h\|tomorrow\|nextweek] [-Archive] [-Due <when>] [-NoDue] [-Title <text>] [-Source <tag>] [-Ref <ref>] [-All]` | `features.organize` | No id: the open reminders grouped overdue / today / upcoming. `-Snooze` rewrites the due time and nothing else; `-Due`, `-NoDue`, `-Title`, `-Source` and `-Ref` correct the entry, each rewriting its own line; `-Archive` moves it to `reminders/archive/` and stamps `**Closed:**` ([Organize](modules/organize.md)) |
| `Standup [-Space <slug>] [-AsJson] [-Brief] [-Grain <detail\|work\|brief>] [-Since <yyyy-MM-dd>] [-Remind <HH:mm>] [-Days <Mon,Tue,...>] [-Walk]` | `features.solitaireAgile` | Today's standup for the Space you are in; each item says what moved after its number where that adds to its slot -- `started` (its card began in the window) and its card's commits (`#141 (started, 2 commits) Count the commits`, `#143 (2 commits) Rename the slug`); closed under Yesterday and in progress under Today are the slot's own word and not repeated -- and the brief opens on the counts line (`Since <day>: 3 closed, 1 started, 2 in progress, 7 commits.`, a hash counted once however many cards thread it); `-Since <yyyy-MM-dd>` widens yesterday back to that day, so everything closed or archived since then is said and counted -- today and the blockers stay what is open now, and it is not `-Days`, which is the reminder's cadence (a day that is not one, one after today, or `-Since` with `-Remind` is a stated refusal); `-Grain` picks the register of detail: `detail`, the default, every item with its number; `work`, the ritual's grain -- each worker's items grouped by milestone, else the design card the issue names, else the titles' common stem, spoken as standup prose, one sentence a group, no model (`Opus: Yesterday I closed two in Team Agile (#<n>, #<n>). Nothing blocked.`); `brief`, the same as `-Brief` -- a word that is not a grain, or `-Brief` with another, is a stated refusal; `-Walk` prints only the walk list -- each open `verify-close` issue by number with the VERIFY.md Gate 12 row that names it under it, or `no VERIFY row -- close on the issue's own words` (`-AsJson`: `walk[]` of `number`, `title`, `url`, `verifyRow`; not with `-Remind`; a read, it does not re-arm the reminder); `-Remind <HH:mm> [-Days ...]` writes the Organize reminder that wakes the bell before it (source `standup`, needs `features.organize`), and opening the standup re-arms it for the next day in the cadence -- archive the reminder in Organize to stop it. Also: (or the declared Space `-Space` names): what is waiting on you -- every open `verify-close` issue -- then one block per worker label ("Routed to \<Name> -- ..."), yesterday, today and blockers from the Space's GitHub issues. A local Space (no tracker address, or status `local`) fills from its own cards instead -- one tile named for the Space, Code Review waiting on you. An Azure DevOps Space, or a tracker that does not answer, still prints, the reason on its `Tracker` line, exit 0. `-AsJson` prints the agent's response shape, `text`, `work` and `brief` included -- all but `spoken`, the agent's model dress: the CLI calls no model, and `-Grain work` prints the prose. `-Brief` prints only the chair's reading: a few lines, each a count or a derived fact -- what waits on you by kind, each worker as closed / open / in flight / blockers, the one thing next -- with no model, and it does not re-arm the reminder. With nothing waiting, the one thing next is the suggestion: one derived next move -- the item, the rule that chose it and the command that acts on it (`Next: 23A3 is the last open card in milestone B -- start it? (tkStartWork 23A3)`) -- in place of `Next: nothing is waiting on you.`; `-AsJson` carries every candidate as `suggestions` and the first as `suggestion`; off where the Space says `spaces.<slug>.features.suggestions=false` ([the suggestion](modules/solitaire-agile.md#the-suggestion-one-next-move-derived)). Wherever the suggestion is on, the brief's last line is the PM Corner -- the nearest milestone, what is left in it and the item to start, or a milestone reached in the window (`Corner: 3 more issues to get milestone B - start #5 now > (tkStartWork 5)`, `Corner: milestone B reached`) -- and `-AsJson` carries it as `corner` ([the PM Corner](modules/solitaire-agile.md#the-pm-corner-the-line-the-chevron-the-confetti)). Writes nothing ([Team Agile](modules/solitaire-agile.md)) |
| `Triage [-Space <slug>] [-AsJson]` | `features.solitaireAgile` | The Space's open GitHub issues grouped by milestone: the ones in **no** milestone first, then each milestone with most open first, under its context line "N open, M routed, K unrouted" (routed: someone has it -- an assignee or a worker label). One line an issue -- number, title, who has it (`me` when its GitHub assignee is the signed-in `gh` user, `@<login>` for another assignee, else its worker -- the size: the worker label is the size -- else `nobody`), severity or `--`, `deep-water` marked. An Azure DevOps or local Space, or `gh` not answering, prints a `Tracker` line and exits 0. `-AsJson` is `GET /api/ritual/triage`'s shape. Writes nothing ([Team Agile](modules/solitaire-agile.md)) |
| `Route <n\|id> [-Size <label>] [-Assign <me\|size>] [-Milestone <title>] [-Severity <sev>] [-DeepWater] [-Space <slug>] [-WhatIf]` | `features.solitaireAgile` | Answer triage's three questions for issue `<n>`, **one `gh issue edit` per switch**: `-Size` adds that worker label and removes the other sizes, `-Assign me` makes you the assignee (`gh issue edit <n> --add-assignee @me`) and `-Assign <size>` is the `-Size` write, `-Milestone` sets an open milestone by title, `-Severity` adds `sev1`/`sev2`/`sev3` and removes the other two, `-DeepWater` adds `deep-water` and prints deep water's two moves -- Fable (`Route <n> -Size fable`) or split (`NewItem -Parent <n> -Title <text>`, each piece a sub-issue). On a **card** -- an id of its own (`K7M2`), or any card in a Space with no tracker or a local one -- `-Assign me` or `-Assign <size>` writes one `**Assigned:**` footer line and nothing else (the sizes: the repo's worker labels on a connected GitHub Space; a Space with no connected repository has no labels to read, so there a card takes `-Assign me` alone). `-WhatIf` prints every write and makes none. Refused with exit 2 and nothing written: no number, no switch, an unknown severity, a size that is no worker label on the repo, `-Assign` and `-Size` that disagree, a milestone that is not open there (the hint lists them), an undeclared or non-GitHub Space (an Azure DevOps Space refuses `-Assign` too), a card given any switch but `-Assign`, an `-Assign` that is neither `me` nor a size, a size on a card in a Space with no connected GitHub repository. Writes nothing else to the hub ([Team Agile](modules/solitaire-agile.md)) |
| `StartWork <id> [-Clip] [-Prompt <path>] [-Space <slug>] [-Launch] [-WhatIf]` | `features.solitaireAgile` | Print **one markdown block** a cold agent can start the work from, and nothing else: `# Start work: <Kind> <id> -- <title>`, then how we work in this Space (its `how-we-work.md`, else one sentence from `spaces[].howIWork`), the card whole -- commit bullets, `PR URL:` and footer included, CRLF read as LF -- and the kind's prompt from `startWork.prompts`, each heading naming the file it came from. `<id>` is a card in `current/` (an id is never a substring), else the Space's GitHub issue of that number. `-Clip` copies it and says so in one line; `-Prompt` carries another prompt for this call. Refused with exit 2: no id, nothing matching, an archived card, a card in `backlog/` (naming `Move <id> -To Active`), a closed issue or a pull request, an Azure DevOps Space, a partial name from the bridge, a kind with no prompt row or a row whose file is missing (naming `startWork.prompts.<kind>`). Writes nothing. `-Launch` hands the same block to a session: from a clone whose `origin` is the Space's GitHub address, with `claude` on the PATH (the derived surface `startWorkLaunch`), it adds a detached worktree under `.claude/worktrees/`, writes the block to `startwork-<ref>-<stamp>.block.log` and starts `claude --print --model <size> --output-format stream-json --verbose` there with that file as stdin, output to `startwork-<ref>-<stamp>.log` (all `*.log`, ignored), prints the PID, the worktree and the log, and returns. The model is the item's size, `sonnet` or `opus`; refused with exit 2: `fable` (the owner's own seat), assigned to you, no size or a size with no model (each naming `Route <id> -Assign sonnet`), not in a git repository, another repository's origin, no `claude`, a failed worktree add, `-Clip` with `-Launch`, `-WhatIf` without it. `-WhatIf` prints the commands and starts nothing ([Team Agile](modules/solitaire-agile.md#the-launch-the-block-handed-to-a-session)) |

> **`SendTeams` posts to a real webhook.** Use `-WhatIf` first: every gate runs, the markdown is
> formatted, and the would-be payload comes back unsent. See
> [Communication](modules/README.md#communication) for the two gates and where the URL lives.

### Tests

| Command | Does |
| --- | --- |
| `Test [-Half cli\|agent\|web] [-Fast]` | Run the three halves -- the agent's `pytest`, the CLI runner, the web UI's `npm test` -- in that order, then one summary (per half its counts and time) and one verdict. A half that cannot run is skipped with its reason and the verdict names it SKIPPED, not passed. `-Half` runs one; `-Fast` is the CLI runner's `-Fast`. Exit 0 when every half that ran passed, exit 2 when one failed or none ran. Prints expected (`docs/TESTING.md`) vs actual per half as information, and writes all three halves into `test-summary.<machine>.json` ([Testing](TESTING.md)) |
| `TestToolkit` | Run every suite (`-List` to enumerate, `-<Suite>` to run one, including `-Portability`) |
| `TestCompat` | PowerShell 5.1 compatibility suite only |
| `TestMenu` | Menu system suite only |
| `TestSync` | `Sync` auto-commit / pre-commit hook suite only |

The Portability suite -- "could a stranger clone and use this", see [Contributing](CONTRIBUTING.md) --
runs inside `TestToolkit`, is listed by `TestToolkit -List`, and can be selected alone like every
other suite: `tkTestToolkit -Portability`. The suites themselves, their counts and the other three
runners are [Testing](TESTING.md).

`tkTestToolkit -Help` renders its **usage from `config.default.json`**, through the same
`Show-ConfigHelp` renderer `tkWeb` and `tkAgent` use, and generates its **suite list from the suite
table** -- the one thing config cannot hold, because adding a suite is a code change in the runner.
No `-Help` in the package is hand-written: a hand-written one is how the runner's help once named the
**legacy system's** runner and offered switches that matched no suite.

---

## Tiers: what works without ADO

The toolkit degrades by capability rather than failing:

| Tier | Means | Available |
| --- | --- | --- |
| 1 | the board's tracker tool present, authenticated, the tracker reachable | Everything |
| 2 | Repo + git, no tracker | `NewPrompt -Title`, `Archive`, `Billable`, `Cover`, `Status`, `Sync`, `Menu`, `Log`, `Env`, tests |
| 3 | Repo or git missing | `Menu`, tests |

**Which tool tier 1 means follows the board's address**
(`Scripts/Resolve-Tracker.ps1`; the rule is [Configuration](CONFIGURATION.md), "The `org` address also decides the TRACKER"): on an Azure DevOps
board it is `az`, signed in, with ADO answering; on a GitHub board
it is `gh`, signed in (`gh auth login`), with GitHub answering, and `Env`'s rows, `Setup`'s checks
and the tier sentences all say gh and GitHub there. A local board has no tracker and no tool to
miss.

Tracker commands check tier **once**, before running, and say what is unavailable and why -- never a
silent empty result, never a raw API error.

**The invariant:** a Tier-2 machine still produces and maintains prompt files. Losing the tracker
degrades the workflow; it must not break the discipline.

### Creating a card with no ADO

`NewPrompt` has two forms and only the first one needs a board:

```powershell
tkNewPrompt 113                                        # Tier 1: read card 113, assign it, scaffold
tkNewPrompt -Title "Timeout on large files" -Type Bug  # Tier 2: scaffold from nothing, no az call
```

`-Title` is what makes it offline. Nothing about the resulting file is second class: it is built by
the same code, in the same shape, with the same house-style filename and branch
(`K7M2-timeout-on-large-files.prompt.md`, `you/K7M2-timeout-on-large-files`), and `Status` lists it under
**Backlog** the moment it lands (**Active** with `-Now`). `ThreadHash`, `Archive` and the rest work on it
unchanged -- the first `ThreadHash` pulls it into `current/`.

- **`-Type`** is `Task` (the default), `Bug`, `User Story` (or `UserStory`), `Feature`, **`Spike`**,
  **`Meeting`**, or any key a team has added to `workItemTypes`. An unknown one is refused by name
  and the known ones listed. A **Spike** is work that ends in a finding, not in code -- a proof of
  concept, a design, a question: its card has Question, Findings, Recommendation and "Done when", and
  no Described Changes or Implementation Details, because there may be no pull request at all. A
  **Meeting** is one you attended -- it took time, it is billable, it is on Daily -- with When,
  Where, Who, Purpose, Notes, Outcomes and Follow-ups; a meeting you run is the Meeting Agenda
  Planner's, under `manager/`.
- **`-Date YYYY-MM-DD`** sets `**Created:**` to the day the work WAS -- a meeting attended yesterday
  -- so Daily lands the card on that day rather than on the day the card was typed. Daily also reads
  a person's `**Started:**` and `**Review:**` lines the way it reads git's days.
- **The id.** A card with no work item gets a **short random id of its own: four characters, at least
  one letter and one digit, no look-alike characters** (no `0 O 1 I L B 8 S 5 Z`) -- `K7M2`. Never all
  digits, so it can never be mistaken for a work item number; never all letters, so never for a type
  prefix. It is unique across the org's `current/` and `archive/`, and it is RANDOM, not a counter: a
  counter collides with a real work item number sooner or later, and two machines generate the same
  one before a sync. The file is house style with the id in it: `Spike-K7M2-...`, `US-K7M2-...`,
  `TaskK7M2-...`, bare `K7M2-...` for a Bug; the branch is `{user}/K7M2-{slug}`. A card that carries a
  number keeps it. **`-Id`** takes a work item number you already know, or a lettered id of your own,
  and is validated: `-Id TASK` is refused. `NewPrompt K7M2` with no `-Title` returns that card if it
  is in `current/`, and is otherwise a stated refusal: a lettered id is not a work item, so there is
  nothing to fetch.
- **What a card is, and what an id is.** "Card" is the house-style filename and only that: an
  optional type prefix from `workItemTypes`, the id, then the dash that starts the slug (`140-`,
  `Task139-`, `US-142-`, and the same with an `-rN` re-archive suffix). **An id is a work item
  number, or four characters with at least one letter and one digit (`K7M2`)**; its shape is
  `regex.cardId` in `consts.json`, read by all three halves. Every verb reads an id with the **same**
  rule, from the same file (`Scripts/Resolve-CardName.ps1`): `tkArchive 39` matches the card whose id
  **is** 39 and never `Task139-...`, and `tkArchive k7m2` -- typed in any case -- matches
  `TaskK7M2-...` and never a card that merely mentions K7M2. `CloseItem` and `NewPR`, and the branch
  resolver `ThreadHash` and `NewPR` share, read ids through that one file too; the first two act on a
  NUMBER only, because only a work item has a board to move.
  A dated file such as the `2026-05-14-PR141415.prompt.md` the PR-comment flow writes into
  `archive/`, or a slug that merely contains a year, is not a card -- reading the first run of digits
  in any name would take a date for an id.
- The fields a card would have got from ADO say so: `**Sprint:** (not linked)` and
  `**ADO Link:** (not linked -- created offline with -Title)`. Fill them in by hand if the work
  later gets a card; nothing reconciles them for you.
- `-AssignTo`, `-ReadOnly` and `-Force` are about the board. Passing them with `-Title` prints a
  line saying they were ignored.

**A card's links back into the package are refreshed, not frozen.** A card carries two: the
`> Template:` line, and the `ado-comments workflow` line `GetPRComments` appends. Both are relative
paths from the card to a file that ships with the Toolkit. The hub need not contain the package
([Configuration](CONFIGURATION.md)), the hub is synced across machines whose clones sit in different
places, and folders get reorganised -- so a path computed once at write time is wrong on the next
machine, with no warning and no fix but counting `../` by hand.

`Scripts/Repair-CardLinks.ps1` is the one place that knows which links a card has: it **builds**
both lines (so `NewPrompt` and `GetPRComments` cannot write them two ways) and **rewrites** them
from wherever the card sits now. `Archive` refreshes the card it moves, and `Sync` refreshes
**every declared org's** `current/` and `archive/` after a pull and before the push -- so the machine
that pulls a move is the machine that publishes the repair. `tkArchive -Relink` does the same whole
hub at once, for a reorganisation that never goes through `Sync`. Both walk every org the hub and the
config declare (`Get-P20CardFolders`), not only the active one, so an org nobody switches to -- an
archived one -- is repaired too. A line the repair does not recognise as its own (a hand edit that added text after the link) is left
exactly as it is. The pass is idempotent and does not write an
unchanged card, so it produces no diff and no line-ending churn. When the package cannot be found
at all, the line carries the file's **name and no link** -- a `../../templates/` guess is the
legacy single-repo layout and is wrong for every toolkit hub. The same holds when the hub and the
package are on different drives, or the hub is on a network share: no relative path exists there,
and `Resolve-Path -Relative` would answer with the absolute one (Windows PowerShell 5.1 spells it
`.\C:\...`), so the builder returns its `-Fallback` and the card keeps the name, never a machine
path. A card that already holds a drive-letter, share or leading-slash path in either line is
rewritten to the same form by the repair, and a second pass changes nothing.

For the same reason a card writes `{cliPrefix}`, not the prefix registered on the machine that
wrote it: the prefix is config, and a card that spelled out one machine's prefix would tell the next
reader to run commands that may not exist on theirs.

**The `templates/` folder is reference, not the generator.** A generated card *links* to
`templates/<Type>.template.md` and the body is built in `Scripts/New-PromptFromWorkItem.ps1`, which
is why both forms cannot drift apart. If you do scaffold one by hand from a template, these are the
placeholders in the files: `{ID}`, `{Title}` and `{branch-name}` everywhere;
`{parent-id}` and `{parent-ado-url}` on `Task.template.md`; `{emoji}`, `{cliPrefix}`, `{username}`
and `{slug}` on `UserStory.template.md` (the emoji is the large-story marker the generator adds at
5+ points, and the rest are inside a comment describing the branch shape). Put the result in
`{promptsRoot}/{promptsFolder}/current/` and `Status` will pick it up -- but `NewPrompt -Title` is
the supported path and fills all of them.

---

## Errors

Commands fail with a stated reason and a hint, not a stack trace:

**One refusal, one block.** A command that refuses says why **once**. The exit code is what carries
that across the boundary between a script and the wrapper that ran it:

| Exit code | Means | What the wrapper adds |
| --- | --- | --- |
| `0` | it worked | nothing; one `CMD` line in the log |
| `2` | a **stated refusal** -- the script has already printed its own `Error:`/`Hint:` block | **nothing.** The log records the stated reason, not "exit code 2", and `$LASTEXITCODE` stays `2` so a script that checks it sees the failure |
| any other non-zero | a failure that said nothing | the generic `Error: exit code <n>` block and the hint that points at `tkLog -Errors` |
| none -- the script **threw** | a terminating error the script did not catch | one `Error:` block with the error's own message and the same hint, and `$LASTEXITCODE = 2`: the wrapper has stated it now. Left at `0`, it once let `tkNewSpace` print an error and report success |

Through the agent (`TOOLKIT_QUIET_STARTUP`), every row but the first is `status: error` with the
sentence: a stated refusal, a silent non-zero exit and a throw are each re-raised after the block.

`tkArchive` on a name that matches nothing, `tkNewGrowth` without the `-DueDate` a training needs,
`tkNewPrompt -Type` on a type that does not exist -- each exits `2` and prints one block, never the
readable sentence followed by a generic `Error: exit code 1` that says less than the line above it.

A refusal is a failure the caller can see. `tkArchive does-not-exist` leaves `$LASTEXITCODE = 2`,
and through the agent it is `status: error` with the stated sentence -- never `success`.

**A script run on its own refuses the same way.** A script in `Scripts/` can be run with no module
loaded (`pwsh -File Scripts/<name>.ps1`, a test, a `-Help` before the first import). It then takes
`Get-CliPrefix` and `Write-CliError` from `Scripts/Initialize-CliFallbacks.ps1`, which it dot-sources
at the top and which defines each one only when the module has not: the same `Error:`/`Hint:` block,
the same exit 2, and the stated reason recorded in `$global:P20StatedError` as the module records it.
That file is the one copy; `Tests/Test-Portability.ps1` refuses a script that carries its own.

**A verb is two `param()` blocks, and they are held in step by a test.** The wrapper in
`utilities.psm1` owns the alias and forwards `$PSBoundParameters`; the script in `Scripts/` does the
work. A switch the wrapper does not declare is rejected by the **binder**, before the script runs --
and a binding error sets no `$LASTEXITCODE`, so the failed call reports **success** with nothing
started -- a switch in the help and not in the wrapper does exactly that.
So a switch goes in three places: the script's `param()`, the wrapper's, and the verb's `usage` in
`config.default.json`. `tkTestToolkit -Menu` checks every script-backed verb in every direction --
usage to wrapper, wrapper to script, and script to usage and wrapper (`-Help` excepted: the wrapper
answers it and returns; composition parameters nobody types are named per verb in the test). Add a
switch to a script and its help, and that suite tells you the wrapper is missing it.

| Condition | Message |
| --- | --- |
| Work item not found, or not fetchable | `Could not fetch work item <id>.` -- check the id and that `az` is signed in to this org; what ADO said is in the `Hint:`. Like every refusal in `CloseItem` and `NewItem`, it exits 2 |
| Not authenticated | `Failed to get ADO access token.` with the hint `Run 'az login' first.` and what `az` said -- every verb that calls the Azure DevOps API, before any call is made; exit 2. `az` exiting non-zero is this refusal even when it printed something, and so is `az` printing no token. One helper, `Scripts/Get-AdoToken.ps1`, asks every time (`NewPrompt <id>` words its own sentence, about the comments it could not read) |
| Access denied | `Access denied (HTTP <status>) by Azure DevOps`, then the fix: `az login`, and if that is not enough, sign in to the org once in a browser (or `az devops login --organization <org>`). Said for a 401 and a 403 alike, by `GetPRComments` and `AddPRReview`; exit 2 |
| Tier too low | `<command> needs ADO (Tier 1); currently Tier <n>.` -- on a GitHub board the sentence says `needs GitHub` and the hint names `gh` (`gh auth login`); either way the hint says why (the org is `local`, the tool is not signed in, the tracker did not answer); exit 2, so the bridge reports it as an error. `-Help` answers on any tier |
| Branch matches no prompt file | `No prompt file matches branch '<branch>'.` -- the hint names the folder it looked in; `-File` names the card |
| Branch matches several | `Branch '<branch>' matches <n> prompt files.` -- the candidates are listed; `-File` picks one. Never the first of them |
| Prompt file already exists | Not an error. `Card <id> is already in current/ -- nothing was written, and ADO was not contacted.`, the card's path, exit 0. There is no switch that overwrites: move or delete the file to start it over |
| Archiving with no argument | `no card given.` -- pass the card's ID, or `tkArchive -List` |
| Archiving an ID no card carries | `No card with id '<id>' in current/.` -- an argument with the shape of an ID (`141`, `k7m2`) is an ID, not a partial name. Only when it is in neither `current/` nor `archive/`: an archived one is success |
| Archiving a name that matches nothing | `No file matching '<name>' found in current/.` -- `tkArchive -List` shows the candidates |
| Archiving a name that matches several | `'<name>' matches <n> files in current/.` -- be more specific |
| Archiving a partial name through the bridge | `'<name>' is not a card in current/; it matches '<file>' only by partial name.` -- pass the ID or the full filename |
| Hub not found | `Hub not found: '<root>' -- is the drive connected? promptsRoot in config.local.json` -- said once at import, and by every verb that reads the hub |

Ambiguity is never guessed at.

---

## The log

A **diagnostic** log: environment, command, failure, and when. Nothing else -- no prompt bodies,
no card content.

```powershell
tkLog -Errors            # failures only
tkLog -Today
tkLog -Days 7
tkLog -Count 50          # how many entries to show (default 20)
tkLog -Command NewPR
tkLog -Type ERR
tkLog -Tail              # FOLLOWS the log live, like tail -f -- Ctrl-C to stop
tkLog -Clear             # archive every usage.*.log to a dated .bak, start fresh
tkLog -Ack               # dismiss the error indicator in tkMenu
```

It lives beside the module as `usage.<MACHINE>.log`, one file per machine, and is gitignored.
An entry is one line of tab-separated columns (time, type, machine, source, detail). Both writers --
`Write-ToolkitLog` and the agent's `POST /api/log` -- turn a tab or a line break in the source or the
detail into one space before writing, so a work item title or an error message with a newline in it
cannot start a second entry or move a column. `Write-P20TestResult` does the same for
`test-results.<MACHINE>.log`.

**A test run does not write into it.** `P20_USAGE_LOG_DIR` moves the log -- a **directory**, read by
both halves (`Get-ToolkitLogDir` in `utilities.psm1`, `log_dir()` in `agent/core/log_writer.py`),
and by the readers as well as the writers, since `tkLog`, the scoring engine, the error count and
the web UI's Log card all glob `usage.*.log`. Unset, the log is beside the module.
`tkTestToolkit` points it at a temp directory for the length of the run and restores it afterwards,
and `Tests/conftest.py` does the same for pytest -- at **import** time, because pytest runs
module-level code during collection and one file starts a child PowerShell there. (Importing the
module in the shell you run it from still logs one `INFO tkEnv` row, as any shell that imports the
toolkit does. That is the import, not the run.) So a suite's failing assertions never show up as
the engineer's own errors on the Log card.

`test-results.<MACHINE>.log` and `test-summary.<MACHINE>.json` deliberately do **not** follow it:
the Health card reading real test results is the point of those two.

---

## AI review (optional)

```powershell
tkAddPRReview 34 -DryRun    # print what it would post, send nothing
tkAddPRReview 34            # post up to 3 inline comments on the PR
```

Reads the PR's diff, asks a model for up to three real problems, and posts each as an inline
comment anchored to a file and line.

**Run it from the repository the PR belongs to** -- it computes the diff locally. If you run it
somewhere else the command stops and says so rather than sending you a review of nothing.

With no PR number it finds the PR for the current branch, asking each of the Space's projects in
turn. A project that answers 404, or with no PR, is simply not the one and the search goes on. An
answer of 401 or 403 is the token or the permission, not a missing PR, so the search stops there:
`Azure DevOps refused the PR search in '<project>' (HTTP 401)`, with a hint to `az login` and exit
2. Only when every project answered "not here" does it say `No open PR found for branch`.
The fetch of the PR's details (with or without a number) reads the status the same way: 401 and 403 both
print `Access denied (HTTP <status>)` with the `az login` fix ("Access denied" under [Errors](#errors)) and exit 2, where 401 used to fall through to
`Could not fetch PR #N` with the raw exception. Any other failure there is unchanged.

**It is optional and nothing depends on it.** Without `ANTHROPIC_API_KEY` the command declines and
names the fix; every other command is unaffected. The key is read from the environment, or from a
`.env` beside this package -- copy [`.env.example`](../.env.example) to `.env` and fill it in. That
file is gitignored and must never be committed; `.env.example` is the committed record of what it
may contain, and the test suite fails the build if a credential reaches a tracked file. The module
reads `.env` at import, and not at all while a test run's marker (`P20_TEST_RUN`) is set -- a suite
sees nothing the file holds.

### The prompt is the part that matters

The reviewing is done by [`agentic/pr-review.prompt.md`](../agentic/pr-review.prompt.md), not by the
script. The PowerShell is transport: fetch a diff, call the API, post the findings back.

Edit that file to change what gets reviewed -- what counts as a real problem, how many findings,
how they are worded -- with no code change. It is also what makes the model replaceable: point the
transport at a different API and the reviewing logic travels unchanged. The model it sends is
`ai.model` in config -- the one provider profile the CLI and the agent's `suggest` and `rewrite`
routes share, shipped in `config.default.json` and overridden per machine with
`tkConfig -Set ai.model=<id>` ([docs/CONFIGURATION.md](CONFIGURATION.md)); `-Model` overrides it
for a single run.

That split is deliberate. A prompt welded into a script can only be changed by editing code, and
cannot travel at all.

### Useful for testing, not just review

It is also the practical way to produce realistic PR-comment data. The ADO comment commands are
hard to test because hand-writing threads is tedious; this generates real, file-anchored,
multi-thread reviews on demand. `-DryRun` costs an API call and posts nothing.

---

## The agentic workflows

The commands move a card between states. [`agentic/`](../agentic/) holds the part that decides *what
to do* at each one -- prose, run by an assistant, no runtime of its own.

Six ship as the **card-workflow** set, and the bar for that set is deliberately high:

| Prompt | What it drives |
| --- | --- |
| `new-bug` | Draft a Bug, create it with `tkNewItem`, create its card with `tkNewPrompt`, fill in the repro |
| `new-user-story` | The same for a User Story: scope, implementation details, described changes, acceptance criteria |
| `ado-comments` | Two-pass PR comment triage -- the agent prepares every comment, then you decide one at a time |
| `pr-ship` | Stage 1: verify the card's context is real, commit, open a **draft** PR |
| `pr-publish` | Stage 2: draft → ready, plus comms. Deliberately separate from stage 1 |
| `pr-review` | The prompt behind `tkAddPRReview` |

A fifth, `new-issue`, ships beside them for a different reason: it is the front end of
the GitHub issue list ([Contributing, "Start with an issue"](CONTRIBUTING.md#start-with-an-issue)), and a triage rule that says "an
issue before a fix" is only real if filing one is a single command.

Four more ship here as **module content** -- they are part of growth and communication the way a
script in `Scripts/` or a template in `templates/` is, and they come with their module rather than
through the bar above:

| Prompt | Module | What it drives |
| --- | --- | --- |
| `generate-review` | growth | Turn a `NewWorkReview` scaffold into a shareable work review for one or more orgs over a date range |
| `growth-create-training` | growth | Write a training artifact into the hub's `growth/current/` |
| `growth-create-presentation` | growth | The same for a talk, demo, brown bag or workshop |
| `manager1on1` | communication | Work a 1:1 session file end to end, deciding from the file's own contents which stage it is in. It is what `MeetingAgenda -Plan` and `-Retro` point at |

They ship because a module's prose is part of the module: turning growth on and finding no prompt
to run would be the same defect as turning it on and finding no help text. `MeetingAgenda -Prep`
deliberately points at nothing -- it is a state check, not a writing pass.

They were selected on evidence rather than on looking useful. They come out of roughly 180 worked
cards -- including a full sprint on a ten-developer AI-delivery engagement, worked by an engineer
outside their primary language and keeping pace with the review that came back. Across those, the
thing that separated them was **scar tissue** -- a Safety Contract, or a note recording
something that broke in real use with the workaround beside it. `new-bug` and `new-user-story` have
less of it; they are in the set as its front door, and because they drive the two commands that
create an item and its card rather than writing a card by hand. Nothing else is kept in reserve.
Every prompt opens with one header shape -- frontmatter (`description`, `argument-hint`, `agent`),
the prefix note, one `#` title -- which [`agentic/README.md`](../agentic/README.md), "The shape of
a prompt", states and `Tests/test_agentic_index.py` holds.

Two details worth not "simplifying", because they are the expensive part:

**`ado-comments` carries a Safety Contract** -- an explicit table of who may do what, in which
`Commit` and `Push` are *never* the agent's. The two-pass shape matters just as much: the agent
prepares **all** comments before you see any, so triage is a series of decisions rather than a
conversation. Bot and human comments get different default trust, which is the difference between
a useful triage and a rubber stamp.

**`pr-ship` refuses to write your PR description.** It checks that `Summary`, `Described Changes`
and `Implementation Details` are not still template placeholders, and stops if they are -- with the
diff alongside so filling them in is quick. It will not write them for you: the engineer's voice
belongs in the PR. Its whole job is making that step harder to skip than to do.

Where a tool they drive still has a gap, a prompt says what to do in one line and links to
[Known gaps](KNOWN-GAPS.md), which carries the gap and its issue. A gap that is fixed leaves the
prompt: the prompt says the rule, and the story of how it came about is the commit's.

**Where the line falls.** A prompt ships here when it moves a *card*
through the workflow, and it ships **generic** -- no org, no client, no engagement. Anything else
stays in the engineer's own hub, under `agentic/` beside the cards: deck authoring, publication
review, and any tuned variant of one of the six above. That is the same line templates fall on,
and it is the reason these read blandly compared to the ones on a working machine.

The four module prompts do not bend that rule, they come in through the other door. They are not
card-workflow prompts and they were not selected on scar tissue; they are a module's own content,
held to the same **generic** bar as the rest of it -- no org, no client, no employer, nobody's
name. An engineer's own copy of a workflow is not a module's, and does not ship.

The other half of that arrangement is the **extension folder**:
`tkConfig -Set agenticExtensionPath=<folder>` names a folder of your own, absolute or relative to
the hub, and a shipped prompt's copy in it wins on this machine while the package stays generic for
everyone else. One resolver, `Scripts/Resolve-AgenticPrompt.ps1`, so the search order cannot differ
per caller: the folder's copy when it has the file, the package's `agentic/` otherwise, and nothing
changes when no folder is set. `AddPRReview` reads `pr-review.prompt.md` through it and prints
which copy it chose; `MeetingAgenda` names the copy it hands you. The `ado-comments workflow` link
a card carries points at the package's copy: a card is a file in the hub, synced across
machines, and the link is repaired from the package's position, not from one machine's folder.

Commands appear with the default `tk` prefix; substitute yours if you changed it.

---
