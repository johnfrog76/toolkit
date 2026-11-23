# Releases -- the order file

A **release** is the toolkit's own plan: the cards a Space means to ship together, in order. It is two
things, and they live in two places. Its **membership** is on each card: the card's `**Milestone:**` line
([the card](cards.md#milestone-and-sprint-two-lines)). Its **order** -- which card comes first -- is one
small file per release. The file holds only the order, so moving a card edits one line of one file and
never touches a card: no rank line on every card, nothing for two machines to conflict over when the hub
syncs.

Two words, two owners. A **release** is the hub's: the order file and the card's line, written by `Plan`.
A **GitHub milestone** is the tracker's, written by `Route -Milestone`, and shown on the Stats tab and Team
Agile's Releases tab. The two can name the same title, and can differ: nothing here writes the tracker, and
nothing on the tracker writes a card's line. The release kept older names where a hub already holds them --
the card's `**Milestone:**` line, the `milestones/` folder, the `-Milestone` switch and this file's own
name -- so every hub written before the word changed reads exactly as it did.

## Where

`<promptsRoot>/<promptsFolder>/milestones/<slug>.md` -- a sibling of the Space's `current/`, `backlog/`
and `archive/`. The folder name is `consts.json` `folders.milestones`. It belongs to a Space: a hub-root
sibling such as `growth/` or `manager/` has none. A Space where no card has been ranked has no folder,
and that is not an error.

`<slug>` is the release's title slugged the way a card's slug is: lowercased, every run of anything but
`a-z` and `0-9` one hyphen, trimmed, at most 60 characters. `M2 -- 1.2.0` is `m2-1-2-0.md`.

## One release, one file

```markdown
# M2 -- 1.2.0

**Theme:** the standup sees the work
**Created:** 2026-11-02

## Order

- K7M2 the one that unblocks the rest
- 141
- Q4R9
```

| Part | What it is |
| --- | --- |
| `# <title>` | the exact string a card's `**Milestone:**` line names, case and all. A file whose heading names a different release is not this release's |
| `**Theme:**` | one line on what the release is for. `Plan` writes `(not set)`, and the line is a person's to fill in |
| `**Created:**` | the day the file was made |
| `## Order` | one bullet per card, `- <cardId>`, with an optional note after the id. **The line order is the rank**: there are no numbers, so a move is one line removed and one inserted |

Anything outside `## Order` -- a paragraph under the title, a `## Notes` section -- is free text a person
may write. It is never read as the order and never rewritten. Inside `## Order`, a line that is not a
bullet is kept where it is and not read. The file is written UTF-8 with no BOM, LF when `Plan` creates it,
and an edit keeps the terminator the file already has (`Write-CardText`).

## How the order is read

The ranked list is the file's ids that a card carrying that `**Milestone:**` line still answers, in file
order. Then come the members the file does not list, by their `**Created:**` day, oldest first (a card with
no date last, a tie broken by id) -- **unranked, never dropped**. On the first day every member is unranked.

An id in the file with no card, or whose card names another release, is skipped and counted as
**stale**. A reader never deletes it; it stays in the file until a person does. A card that is archived
leaves the open cards, so its line reads as stale too. The cards read are the Space's open ones, in
`current/` and `backlog/`.

| Input | Read as |
| --- | --- |
| an id in `## Order` whose card names this release | ranked, in file order |
| a card naming this release that the file does not list | unranked, by created |
| an id with no open card | stale -- counted, skipped, kept |
| an id whose card names another release | stale -- and not a member here |
| an id listed twice | ranked once, at its first line |
| no file, or a file with no `## Order` | nothing ranked; every member unranked |
| a CRLF file | read the same |

`Get-P20MilestoneOrder` (`Scripts/Get-MilestoneOrder.ps1`) and `milestone_order()`
(`agent/core/parsers.py`) are the readers, one per half, held to one table,
`Tests/fixtures/parsers/milestone-order.json` (`tkTestToolkit -Plan` and `Tests/test_parsers.py`). The
slug rule is in the same table.

## The one writer: `Plan`

| Call | What it does to the order |
| --- | --- |
| `Plan <id> -Milestone "<title>"` | appends the id at the bottom of that release's order, creating the file if there is none; if the card was in another release, its line leaves that file. A card already listed is not added twice |
| `Plan <id> -Rank top` / `up` / `down` / `<n>` | moves the card's line within its release's order. A position counts the cards the order ranks, from 1, so a stale line is never a step; past the bottom is the bottom. A card the file does not list yet joins it at the bottom first. No card is touched |
| `Plan <id> -Remove`, `Plan <id> -Remove -Only Milestone` | the id's line leaves the order, with the card's line |
| `Plan <id> -Sprint "<title>"`, `-Remove -Only Sprint` | nothing: a sprint is not a release |

`-Rank` on a card with no release refuses, exit 2, naming `Plan <id> -Milestone`. So does `-Milestone`
with a title that has no letter or digit to slug, and with a title whose slug is a file already holding
another release's order (`milestones/<slug>.md is the order of 'X', not 'Y'.`): two titles cannot share one
file, so one of them is renamed, on its cards and in that file's heading. Nothing else writes
this file: it is a hub file a person may also edit by hand, and editing the order by hand is a legitimate
way to rank.

Who may rank is the team lead's and the PM's call on a local or GitHub Space; a builder does not. Until a
Space has seats, whoever runs the verb ranks.

## The Backlog: the order as a table

The Backlog is the cards in a Space's `backlog/` as one table -- rank, id, type, release, tags, age and
title -- and its order is the releases' order. A release's cards already in play sit in the same table, in
their ranked place and marked **in play**, so a release reads 1, 2, 3 from its top. `Backlog` prints it and `GET /api/backlog` serves it, from
the same rule:

1. **Release by release.** A release is in the table when a card in `backlog/` names it. Releases that have a file go first, by the file's `**Created:**` day (a
   file with none after the dated ones), a tie by title. Then the releases that have no file yet, by
   title. A release has a file when `milestones/<slug>.md` exists and its `#` heading names the title
   exactly -- the same lookup `Plan` makes.
2. **Inside a release**, every member in its order -- the ranked cards, then the unranked, as "How the
   order is read" says -- the ones in `current/` among them, marked in play.
3. **Then the cards in `backlog/` with no release**, oldest `**Created:**` first, no date last, a tie by id.

**Rank** is the card's place among its release's ranked cards, from 1 -- the count `Plan <id> -Rank <n>`
uses, and the `#2 of 3` it prints. Because a card in play is shown in its place, the numbers on the page are
the numbers `Plan` takes. An unranked card, and a card with no release, has no rank. A card in play is
there to be seen, not worked: the table's actions are for the waiting cards. **Age** is the whole days since `**Created:**`,
0 for a day in the future, none for no date or an impossible one. **Type** and **title** are read from the
card's `#` heading: a configured type name, the id, a colon, then the title; a heading that names no type
has none, and the whole heading is the title.

The filters -- `-Milestone` (the release), `-Tag`, `-Type` on the verb, `?milestone=`, `?tag=`, `?type=` on
the route, each keeping its name -- go together (AND) and match ignoring case; the type ignores spaces too, so
`UserStory` is `User Story`. The verb's table heads the column `Release`, and its count line names the
filter (`-- release 'm2'`). A filtered row keeps its rank, because the rank is the release's and not the table's. Sorting a column is
a view: nothing about the table ever writes a file, and only `Plan` changes the order.

| Input | Read as |
| --- | --- |
| a card in `backlog/` | a row |
| a card in `current/` naming a release that a waiting card names | a row in its place, marked in play |
| a card in `current/` whose release no waiting card names, or with no release | not a row |
| a release's file at the title's slug whose heading names the title | the release has a file: sorted by its `**Created:**` |
| a file elsewhere, or whose heading names another title | no file for that release |
| a release's file with no `**Created:**` | after the dated files, before the releases with no file |
| a card the order does not list | after the ranked ones, by created; no rank |
| a card with no release | after every release, by created; no rank |
| no date, or `2026-13-45` | sorted as written; no age |

`Get-P20BacklogRows` (`Scripts/Read-Backlog.ps1`) and `backlog_rows()` (`agent/core/parsers.py`) are the
readers, one per half, held to one table, `Tests/fixtures/parsers/backlog-order.json`
(`tkTestToolkit -Backlog` and `Tests/test_backlog.py`).

## Not on an Azure DevOps Space

On a Space whose tracker is Azure DevOps the board belongs to the organisation and keeps its own order, so
ToolKit keeps none: `Plan -Rank` refuses (exit 2, "ranking lives in Azure DevOps; `MyWork` lists what is
assigned to you"), `Plan -Milestone` writes the card's line and no order file, and the disk reader returns
nothing there. There is no Backlog either: the company's backlog is in Azure DevOps, and a card there is work
assigned to you, in `current/` until it is archived. `Backlog` refuses (exit 2, "this Space's backlog is in
Azure DevOps; `MyWork` lists what is assigned to you") and `GET /api/backlog` is a 404 with the same sentence.

## Not yet

The order is read by the CLI and the agent, and `Backlog` prints it, but no page draws it yet: Team
Agile's Releases tab shows the Space's GitHub milestones and no release's order, and the Backlog page on Home is a later piece of work. `Plan` never writes the tracker -- a
GitHub milestone's description is not a release's order, and mirroring the file into it is not built.

Known gap: [A release's order is not drawn](../KNOWN-GAPS.md#a-releases-order-is-not-drawn).
