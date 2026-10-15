# Reminders -- the file

The shape of one reminder, and how every reader reads it. The Organize add-on writes and reads these;
its document is [`docs/modules/organize.md`](../modules/organize.md). This file is about the FOLDER.

## Where

`<promptsRoot>/reminders/current/` for open reminders, `reminders/archive/` for done ones -- a hub-root
sibling of `growth/` and `manager/`, **never under an org**, and keyed by no slug: an org is an Azure
DevOps idea and a reminder has no work item, repo or board. The folder's name is the hub's to declare
(`hub.json` `folders.reminders`, default `reminders`; `tkConfig -Set folders.reminders=<name> -Hub`).
A hub that has never had a reminder has no folder, and that is not an error.

## One reminder, one file

```text
reminders/current/K7M2-review-sprint-goals.md
```

```markdown
# Review sprint goals

---

**Due:** 2026-09-24T14:00
**Source:** ado
**Ref:** 41
**Created:** 2026-09-23
```

| Part | Rule |
| --- | --- |
| The filename | `<ID>-<slug>.md`. The id is the short id a card with no work item gets -- four characters, at least one letter and one digit, uppercase, `consts.json` `regex.cardId` -- read by the ONE id rule, no type prefix. A file whose name carries no id is not a reminder |
| The H1 | the title. No H1: the filename stands in |
| `**Due:**` | `YYYY-MM-DD` (a day, due at its end) or `YYYY-MM-DDTHH:MM` (a moment), **local, no offset**. Absent: no due date. `consts.json` `stamps.due`, pattern `regex.dueLine` |
| `**Source:**` | where it came from, a free tag -- `manual` by default. Shown as the row's tag, **never followed** |
| `**Ref:**` | an optional pointer inside that source (a card's id, a meeting date), free text. When the whole of it is the id of a card in the active Space, the reader resolves it to that card and the web links to it; anything else is shown as written ([the module's document](../modules/organize.md#a-ref-that-names-a-card)) |
| `**Created:**` | the day it was written |
| `**Closed:**` | written when it is archived, after the move, by the one shared stamp writer |

**Open versus done is the folder.** A snooze rewrites `**Due:**` and nothing else -- being pushed is not
a new reminder. The bytes are the card's: UTF-8 with no BOM, LF on create, the file's own ending on edit
(`Write-CardText`). A person may edit the file by hand; nothing positional depends on its lines.

## How it is read

**Nothing derived is stored.** The bucket -- overdue, today, upcoming -- and the words "Yesterday" or
"2:00 PM" are worked out at read time against the local clock; a file that stored them would be wrong by
morning. The bucket rule is in [the module's document](../modules/organize.md#the-file-shape-and-how-a-reminders-bucket-is-read),
held from both halves by `Tests/fixtures/reminders/buckets.json`.

## Samples and fixtures

`samples/hub/reminders/current/` -- three, for a first run: one with a due date far enough out to read as
upcoming whenever it is copied, one with none, and `D1WK-welcome-to-your-first-day.md`, which ships with
none and is the one file `tkStart` edits after copying -- `**Due:** <today>`, a day, through
`Set-P20CardLine`, in the copy only. So it lands in Today on the day the hub is made. `Tests/fixtures/hub/reminders/current/` -- three plus a
file with no id, and deliberately no `archive/`.
