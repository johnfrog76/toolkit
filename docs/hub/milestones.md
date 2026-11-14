# Milestones -- the order file

A milestone is two things, and they live in two places. Its **membership** is on each card: the card's
`**Milestone:**` line ([the card](cards.md#milestone-and-sprint-two-lines)). Its **order** -- which card
comes first -- is one small file per milestone. The file holds only the order, so moving a card edits one
line of one file and never touches a card: no rank line on every card, nothing for two machines to
conflict over when the hub syncs.

## Where

`<promptsRoot>/<promptsFolder>/milestones/<slug>.md` -- a sibling of the Space's `current/`, `backlog/`
and `archive/`. The folder name is `consts.json` `folders.milestones`. It belongs to a Space: a hub-root
sibling such as `growth/` or `manager/` has none. A Space where no card has been ranked has no folder,
and that is not an error.

`<slug>` is the milestone's title slugged the way a card's slug is: lowercased, every run of anything but
`a-z` and `0-9` one hyphen, trimmed, at most 60 characters. `M2 -- 1.2.0` is `m2-1-2-0.md`.

## One milestone, one file

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
| `# <title>` | the exact string a card's `**Milestone:**` line names, case and all. A file whose heading names a different milestone is not this milestone's |
| `**Theme:**` | one line on what the milestone is for. `Plan` writes `(not set)`, and the line is a person's to fill in |
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

An id in the file with no card, or whose card names another milestone, is skipped and counted as
**stale**. A reader never deletes it; it stays in the file until a person does. A card that is archived
leaves the open cards, so its line reads as stale too. The cards read are the Space's open ones, in
`current/` and `backlog/`.

| Input | Read as |
| --- | --- |
| an id in `## Order` whose card names this milestone | ranked, in file order |
| a card naming this milestone that the file does not list | unranked, by created |
| an id with no open card | stale -- counted, skipped, kept |
| an id whose card names another milestone | stale -- and not a member here |
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
| `Plan <id> -Milestone "<title>"` | appends the id at the bottom of that milestone's order, creating the file if there is none; if the card was in another milestone, its line leaves that file. A card already listed is not added twice |
| `Plan <id> -Rank top` / `up` / `down` / `<n>` | moves the card's line within its milestone's order. A position counts the cards the order ranks, from 1, so a stale line is never a step; past the bottom is the bottom. A card the file does not list yet joins it at the bottom first. No card is touched |
| `Plan <id> -Remove`, `Plan <id> -Remove -Only Milestone` | the id's line leaves the order, with the card's line |
| `Plan <id> -Sprint "<title>"`, `-Remove -Only Sprint` | nothing: a sprint is not a milestone |

`-Rank` on a card with no milestone refuses, exit 2, naming `Plan <id> -Milestone`. Nothing else writes
this file: it is a hub file a person may also edit by hand, and editing the order by hand is a legitimate
way to rank.

Who may rank is the team lead's and the PM's call on a local or GitHub Space; a builder does not. Until a
Space has seats, whoever runs the verb ranks.

## The Backlog: the order as a table

The Backlog is the cards in a Space's `backlog/` as one table -- rank, id, type, milestone, tags, age and
title -- and its order is the milestones' order. A milestone's cards already in play sit in the same table, in
their ranked place and marked **in play**, so a milestone reads 1, 2, 3 from its top. `Backlog` prints it and `GET /api/backlog` serves it, from
the same rule:

1. **Milestone by milestone.** A milestone is in the table when a card in `backlog/` names it. Milestones that have a file go first, by the file's `**Created:**` day (a
   file with none after the dated ones), a tie by title. Then the milestones that have no file yet, by
   title. A milestone has a file when `milestones/<slug>.md` exists and its `#` heading names the title
   exactly -- the same lookup `Plan` makes.
2. **Inside a milestone**, every member in its order -- the ranked cards, then the unranked, as "How the
   order is read" says -- the ones in `current/` among them, marked in play.
3. **Then the cards in `backlog/` with no milestone**, oldest `**Created:**` first, no date last, a tie by id.

**Rank** is the card's place among its milestone's ranked cards, from 1 -- the count `Plan <id> -Rank <n>`
uses, and the `#2 of 3` it prints. Because a card in play is shown in its place, the numbers on the page are
the numbers `Plan` takes. An unranked card, and a card with no milestone, has no rank. A card in play is
there to be seen, not worked: the table's actions are for the waiting cards. **Age** is the whole days since `**Created:**`,
0 for a day in the future, none for no date or an impossible one. **Type** and **title** are read from the
card's `#` heading: a configured type name, the id, a colon, then the title; a heading that names no type
has none, and the whole heading is the title.

The filters -- `-Milestone`, `-Tag`, `-Type` on the verb, `?milestone=`, `?tag=`, `?type=` on the route --
go together (AND) and match ignoring case; the type ignores spaces too, so `UserStory` is `User Story`. A
filtered row keeps its rank, because the rank is the milestone's and not the table's. Sorting a column is
a view: nothing about the table ever writes a file, and only `Plan` changes the order.

| Input | Read as |
| --- | --- |
| a card in `backlog/` | a row |
| a card in `current/` naming a milestone that a waiting card names | a row in its place, marked in play |
| a card in `current/` whose milestone no waiting card names, or with no milestone | not a row |
| a milestone file at the title's slug whose heading names the title | the milestone has a file: sorted by its `**Created:**` |
| a file elsewhere, or whose heading names another title | no file for that milestone |
| a milestone file with no `**Created:**` | after the dated files, before the milestones with no file |
| a card the order does not list | after the ranked ones, by created; no rank |
| a card with no milestone | after every milestone, by created; no rank |
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
Agile's Releases tab shows no order, and the Backlog page on Home is a later piece of work. `Plan` never writes the tracker -- a
GitHub milestone's description is not the order, and mirroring the file into it is not built.

Known gap: [A milestone's order is not drawn](../KNOWN-GAPS.md#a-milestones-order-is-not-drawn).
