# Roadmap -- what ToolKit builds next, now that it is public

ToolKit 1.0.0 left its private repository on 2026-10-15. The roadmap that got it there was a waterfall
of eight phases and a public bar, and every line of it is either done or carried below. This file is
what replaced it: **the road so far**, kept short because the record is the cards; **five milestones**,
each a release or a refactor with a named "done when"; and the rule for keeping the file honest.

The owner's three sentences still set the direction. *"This is the core purpose of this software and it
can't be turned off -- ADO can be turned off."* *"Software is an offering."* And the front door: the
product is the answer to one question -- how do you want to work? -- by yourself, on a team in Azure,
or with agents, and the cards are the record either way.

## How the work is carried

- **Internal work is a card** in the hub's toolkit Space, never a public issue. GitHub issues are for
  what strangers report and ask for. A card names the milestone it belongs to on its `**Sprint:**`
  line, so the board's sprint filter shows a milestone's cards without a tracker.
- **A milestone is a release** (semantic version, [CHANGELOG.md](../CHANGELOG.md), a tag on main) or a
  refactor that ships no user-visible change and gets no version of its own.
- **The Azure DevOps way of working is not legacy.** The owner expects to work that way again -- an
  organisation's board, its sprints, its 1:1s and its accounting against Azure DevOps cards -- so every
  milestone keeps that path first-class: its verbs stay registered and tested, an Azure DevOps Space
  stays in the sample hub and in the owner's, and a release is not cut on the GitHub path alone. Where
  the Azure path can only be proved against a live organisation (VERIFY.md's gates), the release walks
  them or says it did not.
- **The public milestones on GitHub are the releases only**, named by version, so a visitor sees what
  shipped and what is next without seeing the crew's cards.

## The road so far

Where it started, in the owner's words: an Azure-based system -- agile, prompt engineering, 1:1s and
accounting, all against Azure DevOps cards, for one engineer in one organisation. Every row below is a
step from that to a studio with Spaces, where the card is the engineer's own record and Azure DevOps is
one tracker of two.

| Date | What changed |
| --- | --- |
| 2026-09-19 | Azure DevOps can be absent: a `local` org runs the product from its files |
| 2026-09-20 | A card no longer needs Azure DevOps. One id rule, a short id of its own, the Spike type, the board with lanes, Billable, Daily from the cards' own dates -- "a huge milestone" |
| 2026-09-22 | Meeting agendas, not manager agendas: the communication add-on's series and carry-forward |
| 2026-09-27 | The second tracker: GitHub Issues through the same seam as Azure DevOps, dogfooded on the product's own backlog |
| 2026-09-28 | The Lounge: the room and the skins |
| 2026-09-29 | The Studio: every product a Space with its ledger, its designs and its specs |
| 2026-10-02 | Team Agile: the standup and triage over a repository's issues, the engine as text first |
| 2026-10-09 | The front door: how do you want to work? Core is ToolKit alone; Azure DevOps and orchestration are the add-ons |
| 2026-10-15 | **1.0.0, public.** The bar met, one squashed commit, CI on every push, the landing page, Dependabot |

The waterfall's phases 0 to 4 and 7 are in that table. Phase 5 (the first run), phase 6 (ledgers) and
phase 8 (the rename) are below, under the milestones they now belong to. The four post-flip features F1
to F4 are there too, by their cards.

## The milestones

```text
M1  1.1.0  The bar, held            the defect queue dry, the three refactors done, the bar written down
        |
M2  1.2.0  The standup sees the work    Team Agile reads the cards; what moved, and how much
        |
M3  1.3.0  Ten minutes to your own board   the first run, the tour, the word for a Space
        |
M4         The engine on stage        the ritual engine in its own repository; the rename
        :
M5  2.0    ToolKit installs itself    the big-picture session decides what the product becomes
```

### M1 -- 1.1.0, the bar held

The first release after the flip is the one that proves the public bar was not a one-day event.
**Done when:** the defect queue is dry, the three refactors from the quick-wins note are done, the bar
the release was held to is a document in the tree, and main's verify is green on both hosts.

- The defect cards: every bug in the toolkit Space's `current/`, including the raw `git` sweep behind
  the widened Portability clause.
- **The performance set, measured on 2026-10-17 against a hub with thirteen Spaces:** the foyer's three
  `gh` reads per GitHub Space on every mount; a repository's design notes read one `gh` call per note;
  the Docs tab's call per folder; the standup re-reading the tracker and re-dressing unchanged facts
  through the model on every open; the ledger's `git log` per card; the prompts list carrying every
  body. One cache helper on disk, keyed by what GitHub already hands back (shas, updated-at), shared by
  all of them; the browser's own cache already holds a session. Each is a card with its numbers.
- The three refactors (the hub's quick-wins note, 2026-10-16): the standalone shims folded into one
  prelude -- done; `Menu` split into its four jobs -- done; one skeleton for the Team Agile rituals --
  open.
- The two quality passes, the Muse pass (2026-10-15, 27 findings) and the Fable pass (2026-10-16): each
  finding a card, worked or closed with a reason. The bugs already in the queue came out of them.
- **The public bar, written for real.** The old roadmap pointed at a bar document that was never written.
  `docs/PUBLIC-BAR.md` says what the release was held to and what every release after it is held to:
  the suites, the two hosts, the documentation rule, the changelog line, the refusal contract.
- The two public issues the flip left open: the landing page's links, and the Docker image on Linux.
- The counts pasted from full runs, once, at the end.

The CHANGELOG's Unreleased section already holds a Changed line a user would notice, so this is a minor
release, not a patch.

### M2 -- 1.2.0, the standup sees the work

Now that the team's own work runs on cards and the issues are the public's, Team Agile is blind to the
work that actually happens. **Done when:** on a GitHub Space the standup says the cards being worked as
well as the issues, says what moved and how many commits it took, and can answer for a stretch of days.

1. *Team Agile reads both records on a tracker Space* -- issues and cards joined on the id; a card
   checked not billable is not a standup row. (The card carries the Definition of Done.)
2. *The standup says what moved* -- closed, started, in progress, a counts line with the commits, and a
   `-Since <date>` window.
3. *The mirror points* -- a derived next move on the standup, and **Start work** beside Route that hands
   a seat its prompt, the card and the Space's how-we-work note. This is the old F2.
4. One skeleton for the rituals comes first, so the three above are built on it, not copied again.

### M3 -- 1.3.0, ten minutes to your own board

A stranger clones the repository, runs three lines, and ten minutes later has used the whole system on
their own board, without being asked for an account. **Done when:** that sentence is tested on a machine
that has never seen the product, and the tour is narrated.

- The first run: watch, do, make your own -- the tutorial cards, the Welcome page. This is the old phase 5.
- Kit's guided tour, built and baked in the Wasteland studio and shipped into the deck module.
- The word for a Space and its one-sentence definition, now that a Space is a connection to software.
- New Space asks how you want to work, and the orchestrating answer writes the team's files. The old F4.
- The landing page's links back and forth, and its look at banner size.

### M4 -- the engine on stage, no version

Two structural changes that ship no user-visible difference and are cleaner done in public than held.

- The ritual engine in its own repository: a portfolio piece that ToolKit consumes. The old F3.
- The rename: a `cards` core and `ado` a module beside growth, communication and deck. The invisible
  half of the carve, the old phase 8, done alone when nothing else is in flight.

### M5 -- 2.0, ToolKit installs itself

The owner's "ultimate milestone": ToolKit delivered as an app that installs itself, rather than a
PowerShell module, a Python agent and a Node build a person assembles. It is a major version because
it changes what a user does to get the product. **It is not designed yet.** It waits on the big-picture
session, below, and nothing in M1 to M4 builds toward it or away from it.

## Not placed

Kept as cards, fitted in when a milestone has room, none of them scheduled: a backlog of cards (plan
one for later); local sprints' write side; flights that protect unfinished work; Daily paging back
past last week, and a week that is not one engagement; Teams as a connection; a real stress-check verb;
the review archive's averages and exceptions; meet the team; the standup's voices; the Electron
question's smaller cousins. The known gaps a reader can trip over are in [Known gaps](KNOWN-GAPS.md).

## The big-picture session

After M1, before M3 is built, one session with the owner answers four questions, and the answers
go into this file:

1. **Who is the user now?** The front door says a studio developer orchestrating agents, and the owner
   is also the engineer who will work the Azure way again. Both are first-class (above); the question
   left is only which of them the first run walks first, since a ten-minute tour cannot do both.
2. **What does "installs itself" mean?** An Electron shell around the three halves, a single binary, or
   a better three-line install. This decides whether M5 exists.
3. **Is the ritual engine a feature or a product?** Its own repository with ToolKit as one consumer
   changes who files its issues and where its design lives.
4. **What is the bar for a release?** What `docs/PUBLIC-BAR.md` says, once it exists, is the answer.

## Keeping this file honest

When a milestone's "done when" is met, mark it with the date, here, in the same commit as the release
or the refactor's merge. When the order changes, change it here and say why. A card names its milestone
on its `**Sprint:**` line; this file names the milestones. This is the only place the order is written
down, and the GitHub milestones carry only the release versions.
