# Organize -- the add-on, end to end

**Organize is where the things a person keeps in order live.** Its first surface is **reminders**: a
note to yourself with a due date, kept as one file in your hub, grouped overdue / today / upcoming,
snoozed or marked done. Reminders is Organize's first surface, not its definition -- a later planning
surface joins it under the same switch, so the key a machine has written never has to be renamed.

This document stands alone: everything a person or an agent needs to work on Organize is here or one
link away. It follows the standard every add-on's document follows
([the modules guide](README.md#what-an-add-ons-document-must-contain)).

**It reminds one person -- you.** It does not send, post, email or notify. It shows what you owe
yourself when the card is on screen, and that is the whole of it. Delivery to someone else is a later
door with its terms already written (two gates, the URL never in config, `-WhatIf` by default); it does
not arrive without an issue of its own.

## Contents

1. [The switch, and its scope](#the-switch-and-its-scope)
2. [What it owns](#what-it-owns)
3. [Turning it on](#turning-it-on)
4. [The verbs](#the-verbs)
5. [The routes](#the-routes)
6. [The web UI](#the-web-ui)
7. [The file shape, and how a reminder's bucket is read](#the-file-shape-and-how-a-reminders-bucket-is-read)
8. [The tests](#the-tests)
9. [Known gaps](#known-gaps)

## The switch, and its scope

`features.organize`, top-level in `config.local.json`, **the engineer's** -- no org can override it.
Unset means off. What you owe yourself on Thursday does not stop being owed because you switched to an
archived org, and the data is org-agnostic too: a flag that holds across orgs, over data that holds
across orgs.

**Both halves or neither.** On means the two verbs AND the Organize tab. Off means no `NewReminder`, no
`Reminders`, no row in `Menu`, no `-Help`, no bridge entry, no route (**404, not 403**), no nav entry, no
page, no card and nothing fetched. There is no web-only mode (that is `deck`'s shape, not this one's).
The one thing visible when it is off is its NAME, in the `Opt in by configuration` block of `Menu -All`
and `Env`: `Organize module  off`.

## What it owns

| Half | Organize's | Not Organize's, though it sits beside it |
| --- | --- | --- |
| CLI | `Config/organize.commands.psd1` + `.ps1` (two wrappers); `Scripts/New-Reminder.ps1`, `Scripts/Get-Reminders.ps1`, `Scripts/Reminder-Rules.ps1` (the bucket, snooze and due rules) | `Resolve-CardName.ps1` (the id rule it reuses), `Set-CardLine.ps1`, `Add-ClosedStamp.ps1`, `Write-CardText.ps1` -- shared writers it calls |
| Agent | `agent/organize/` -- one gated router, `reminders.py`, **reads only** | the bridge, which carries its writes |
| Web | `web/src/modules/organize/` -- `index.tsx` (`organizeModule`), `RemindersCard.tsx`, `NewReminderDialog.tsx`, `reminderEntry.ts`, `ReminderBell.tsx`, `useOverdueReminders.ts`, `api.organize.ts`, `paths.ts` | `web/src/utility/dates.ts`, the shared Luxon time helper it was the first user of; `cliBridge.ts`'s four reminder builders; the ADO module's `useRemindAbout.tsx`, the card menu's door into the dialog, and `ado/paths.ts`, the card page's address a resolved ref links to |
| Hub | `<promptsRoot>/reminders/current/` and `reminders/archive/` | nothing else: it reads no other module's folder |
| Contract | `consts.json`: `stamps.due` / `.source` / `.ref`, `regex.dueLine`, `reminders.buckets`, `reminders.snooze` | `stamps.created`, `stamps.closed`, `regex.cardId` -- reused as-is |

**A module closes its own data.** `Archive` is the card verb, org-scoped, and cannot see `reminders/`;
it is not taught to. A reminder is archived by its own verb, `Reminders <id> -Archive`.

## Turning it on

```powershell
tkConfig -Set features.organize=true
tkMenu -All            # an "Organize" group: tkNewReminder, tkReminders
tkNewReminder -Title "Review sprint goals" -Due tomorrow
tkReminders            # the ledger
```

or in the web UI: the avatar, Settings, the Organize module's switch. `tkStart` turns it on with the
other modules, and the sample hub carries three reminders -- one of them, *Welcome to your first
day*, ships with no due date and is stamped `**Due:** <today>` on the COPY by `tkStart`, so Today is not
empty on day one. The module's verbs are not in the autoload
manifest (it is generated from the committed config, where every module is off), so they answer once
any `tk*` command has loaded the module.

## The verbs

Two verbs carrying switches, `MeetingAgenda`'s shape. Every write a browser makes is one of these
through `POST /api/cmd/{name}`.

| Verb | Does | Touches a file |
| --- | --- | --- |
| `NewReminder -Title <t> [-Due <when>] [-Source <tag>] [-Ref <ref>]` | creates `reminders/current/<ID>-<slug>.md` with a fresh short id (`K7M2`), unique across `current/` and `archive/`. `-Due` takes `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM` (a space for the `T` is accepted), or a snooze word. `-Source` defaults to `manual`. Never overwrites | creates one |
| `Reminders [-All]` | the ledger: every open reminder grouped overdue / today / upcoming, soonest first, undated last; `-All` adds the archived | no |
| `Reminders <id> -Snooze 1h\|tomorrow\|nextweek` | rewrites `**Due:**` and **nothing else** -- same id, same file, same origin | rewrites one line |
| `Reminders <id> [-Due <when> \| -NoDue] [-Title <t>] [-Source <tag>] [-Ref <ref>]` | **corrects the entry.** Each switch rewrites its own line and nothing else, and any may go together: `-Due` takes what `NewReminder -Due` takes (so `-Snooze <word>` is a shortcut for `-Due <word>`), `-NoDue` removes the line, `-Title` rewrites the `#` heading, an empty `-Ref` removes the ref. **The filename keeps its slug** -- the id is the identity. Every value is checked before anything is written; the same values again are `[=] Unchanged`, exit 0, nothing written | rewrites the lines it names |
| `Reminders <id> -Archive` | moves the file to `reminders/archive/` and stamps `**Closed:**` after the move. A second `-Archive` is a report, not an error | moves one |

**What a snooze means**, and the shared table holds it: `1h` is an hour from **now**, not from the old due
time; `tomorrow` is tomorrow at 09:00; `nextweek` is the next Monday at 09:00, never today even on a
Monday.

`<id>` is read by the ONE id rule (`Resolve-P20CardArgument`): an argument shaped like an id matches
that id only, never as a substring (`9` does not find `K7M9`), and a partial name is refused rather than
guessed at. Every refusal is stated -- `Error:` and a `Hint:`, exit 2, one block: no title, a due that
is not a date, a snooze word the contract does not list, an id nothing carries, a switch with no id, an
id with no switch, snooze and archive together; and for an edit, an empty title or source, edit and
archive together, `-Snooze` with `-Due`, `-Due` with `-NoDue`. A refused edit writes nothing.

**A module may write reminders, through these verbs and only these.** Team Agile's `Standup -Remind`
writes one with source `standup` and its cadence on the `**Ref:**` line, and re-arms it by attending
(`docs/modules/solitaire-agile.md`, "The reminder to attend"). No module writes a reminder file itself;
the source tag is how the ledger tells whose a reminder is.

## The routes

| Route | Gate | Reads | Writes |
| --- | --- | --- | --- |
| `GET /api/reminders` | `features.organize`, per request; 404 when off | `reminders/current/` -- the folder the hub names | nothing |

It answers `{ count, buckets: {overdue, today, upcoming}, items: [...], asOf }`. Each item is `id`,
`filename`, `title`, `due` exactly as stored, `bucket` (derived), `source`, `ref`, `created`, and `card`
-- the card the ref names, or `null` ([A ref that names a card](#a-ref-that-names-a-card)) -- sorted by
bucket then soonest due, undated last. A hub that has never had a reminder answers empty, not an error.
A file in the folder whose name carries no id is not a reminder and is skipped.

**There is no write route.** Snooze, Done and the quick add go through the bridge:

```text
POST /api/cmd/Reminders    { "params": ["-Id", "K7M2", "-Snooze", "1h"] }
POST /api/cmd/Reminders    { "params": ["-Id", "K7M2", "-Archive"] }
POST /api/cmd/NewReminder  { "params": ["-Title", "Review sprint goals", "-Due", "2026-09-24T14:00"] }
```

so the refusal contract applies unchanged (a stated refusal is `status: error` with its sentence) and
there is no second writer to get the byte contract wrong.

## The web UI

**Its own tab, `Organize`, at `/organize`** -- laid out like any other tab, cards in the shell's grid
at half width. **Meetings first, then Reminders** ("meetings and reminders live in
`/organize`"): the page renders the registry's `organize` SLOT and then its own Reminders card. Meetings
is the communication module's card and arrives through that slot; this module imports nothing of it,
so with `communication` off the page is Reminders alone. With organize on, communication hides its own
`Meetings` tab and `/communication` redirects here; with organize off, Meetings keeps its own tab --
the deck launcher's shape under Growth. Each card fetches its own data from the store; the
page only places them. Organize contributes no card to any other page -- its one item on a card's menu
is below, under [Remind me about this](#remind-me-about-this).

**The header bell** is the one thing it puts outside its tab, through the registry's `headerItems`: a
soft grey bell left of the avatar, 1rem from it, on every page. Asleep -- Fluent's bell with a "zz",
`AlertSnoozeRegular`, no badge -- when nothing is past due; awake -- `AlertRegular` with a count badge --
when something is. A Fluent `appearance="transparent"` button -- no background, no border -- and both states stay grey
under the pointer too: `transparent` alone paints the icon brand on hover, so the bell holds it grey. Its name and tooltip are the state in
words: `No past-due reminders`, `2 past-due reminders`, and `Checking reminders` / `Could not check
reminders` (asleep, no badge) before the first answer or when the agent is away. A click opens this tab
with the Reminders card on **Overdue**, where Snooze and Done are; the bell lists nothing itself.

The count is `useOverdueReminders()` (`useOverdueReminders.ts`), a selector over the SAME
`GET /api/reminders` the card reads -- no second route, no second cache entry, so a Snooze or Done on the
card moves the bell at once. It polls every minute, because a reminder becomes overdue with no write to
invalidate anything. The bucket is still the agent's.

The Reminders card:

| Part | What it is |
| --- | --- |
| Header | the title, a refresh, and the count badge (open reminders) |
| Chip row | `All` / `Overdue` / `Today` / `Upcoming`, each with its count -- a filter over ONE list, remembered per browser |
| A row | the bucket badge, the source tag, the ref, the title, and the due date in words -- `Today 2:00 PM`, `Yesterday`, `Mon 28 Sep 9:00 AM`, `No due date`. A ref the agent resolved to a card in `current/` is a link to the card's page reading `<id> <title>`; one resolved to an archived card reads `<id> <title> (done)`, named and not linked, because the card page reads `current/` only; any other ref stays in the tag as written, `ado 41` ([A ref that names a card](#a-ref-that-names-a-card)) |
| Row actions | the house row (`shared/CardActions`): **Done**, which archives, is the one exposed action; the `...` menu (`Actions for <title>`) holds **Snooze: In an hour** / **Snooze: Tomorrow, 9:00 AM** / **Snooze: Next Monday, 9:00 AM**, then **Edit**, which corrects the entry. A snooze is one choice away |
| Edit | the reminder's title, due date, optional time, source and ref, filled in, the source and the ref each a full-width field of its own (the date and its time stay side by side). An emptied ref is sent as an empty `-Ref`, which removes the line. A date and a separate time rather than one date-time input, because a reminder due on a DAY has no time and one input would have to invent one (`reminderEntry.ts` splits and joins). Save is off until something changed, and sends only what changed (`buildReminderEditParams`); an emptied date is `-NoDue`. A refusal stays in the dialog in the verb's words |
| Footer | the pager (five a page), and **+**, the quick add: what, an optional due (local date and time), an optional source and an optional ref, each a full-width field of its own. The dialog is `NewReminderDialog.tsx`, the one place the web creates a reminder |

The due date in words comes from `web/src/utility/dates.ts`, the Luxon-backed time utility: local zone,
never `toISOString`. The bucket is never worked out in the browser -- it is the agent's.

### Remind me about this

A card's `...` menu -- on the Board and on the list, which draw ONE action model (`cardActions.ts`) --
ends with **Remind me about this** while Organize is on. It opens the same New Reminder dialog, with the
card's name as what and its id as the ref, so the reminder links back to the card the moment it is
listed. The write is `NewReminder` through the bridge like every other; the board or the list says
`Reminder added about <name>. It is on the Organize tab.`

**Off means absent, and no bytes.** The item is in the menu only when `/env` says `features.organize`
is on; with it off the menu ends at **Open the card**. The ADO module reaches the dialog through a
`lazyPart` (`web/src/modules/ado/useRemindAbout.tsx`), drawn only after a person chose the item, so a
machine with Organize off never fetches any of Organize's code from a card.

**A card does not show that it has a reminder.** Decided, not left out: it would be a second read
over `reminders/` from the ADO module's side -- on every board poll, for every card -- to say something
the Organize tab and the bell already say, and the reminder links to the card rather than the other
way round. If it is ever wanted, the agent's resolver is the piece to reuse; it is not built.

## The file shape, and how a reminder's bucket is read

[`docs/hub/reminders.md`](../hub/reminders.md) is the contract, both halves are held to it. In short:
one reminder is one file, `reminders/current/<ID>-<slug>.md`, an H1 title and the house footer --
`**Due:**`, `**Source:**`, `**Ref:**`, `**Created:**`, and after archiving `**Closed:**`. Open versus done
is the FOLDER. **Nothing derived is stored**: the bucket is worked out at read time against the local
clock.

**The bucket rule**, implemented twice -- `Get-P20ReminderBucket` in `Scripts/Reminder-Rules.ps1` and
`reminder_bucket` in `agent/organize/reminders.py` -- and held to one table,
`Tests/fixtures/reminders/buckets.json`, asserted from both suites:

| Due | Bucket |
| --- | --- |
| none | upcoming |
| a date before today | overdue |
| today's date, no time | today -- a date is due at the END of its day |
| a later date | upcoming |
| a time whose minute has passed | overdue |
| a time later today, or this very minute | today |
| a time on a later day (midnight included) | upcoming |

Times are **local, with no offset**. That is the simplest honest answer for one engineer's hub.

### A ref that names a card

`**Ref:**` is free text, and stays free text: the file shape does not change, and a ref that is prose
(`daily at 09:00`, a meeting's date, `41 and the review`) keeps working as the tag it always was. The
agent reads one more thing from it, at read time and never stored:

| The ref | `card` on the item |
| --- | --- |
| the WHOLE ref has a card id's shape (`consts.json` `regex.cardId`: `214`, `K7M2`), and a card in the **active Space's** `current/` or `archive/` carries that id | `{ id, title, folder, file }` -- the id as the one id rule reads it (`0214` is `214`), what the work is called, `current` or `archive`, and the card's filename |
| the same, with that id in both folders | the one in `current/` -- a card that came back is the one being worked |
| an id no card in the active Space carries, a card in another Space, a ref with a prefix (`Task214`) or anything else around the id | `null` -- plain text |
| no ref | `null` |

The id is read by `card_id()` (`agent/core/parsers.py`), the mirror of `Resolve-CardName.ps1` -- never a
private pattern -- and the Space is read only when some ref has an id's shape. The CLI has no resolver:
`Reminders` prints the ref as written, and nothing in the CLI needs more. The web turns `card` into a
link ([The web UI](#the-web-ui)).

## The tests

| Suite | Holds |
| --- | --- |
| `tkTestToolkit -Reminders` (`Tests/Test-Reminders.ps1`) | every row of the shared table (bucket and snooze); what `-Due` accepts; off means no verb and no bridge entry; both verbs typed in a fresh shell against a scratch package and hub -- create, the ledger, snooze (the Due line and nothing else, a CRLF file kept CRLF), edit (each switch its own line, the filename kept, `-NoDue` and back, `-Source` with `-Ref`, an empty `-Ref` removing it, the same values again writing nothing), archive with its stamp, a second archive as a report; fifteen stated refusals, and a refused edit writing nothing; created bytes (no BOM, LF) |
| `Tests/test_reminders.py` | the same table from the agent's side; the route over the fixture hub against a fixed clock; a file with no id skipped; a hub with no `reminders/` answering empty; the folder renamed through `hub.json`; off is 404; a ref resolved -- a number, a number with a leading zero, a lettered id, an archived card, `current/` over `archive/` -- and not resolved: prose, an id no card carries, a card in another Space, no ref |
| `tkTestToolkit -Consts`, `Tests/test_consts.py`, `web/src/shell/consts.test.ts` | its six contract values, stated from all three halves; `**Due:**` never retyped in the CLI or the agent |
| `tkTestToolkit -HubJson`, `Tests/test_hub_json.py` | `reminders` is a hub-root folder, and the CLI's and the agent's folder tables agree key for key |
| `web`: `registry.organize.test.tsx`, `registry.communication.test.tsx` | its flag, nothing when off, its own tab and no card elsewhere; Meetings fills the `organize` slot and hides its own tab only when organize is on; every registry test mocks all five modules |
| `web`: `ReminderBell.test.tsx` | the overdue slice of an answer (checking, unknown, a count, the last answer kept when a poll fails); the label in every state; asleep with no badge at zero or unknown, awake with the count, a click handed off; the registry test holds that the bell is the header's one organize item and absent when off |
| `web`: `cliBridge.test.ts` | the exact argv of the four reminder builders -- an edit sends only what changed, an emptied due as `-NoDue`, an emptied ref as an empty `-Ref`, nothing changed as `null`; a new reminder's ref as `-Ref` |
| `web`: `reminderEntry.test.ts` | a stored due split into date and time and joined back unchanged; a day keeps no invented time |
| `web`: `RemindersCard.test.tsx` | a ref resolved to a card in `current/` drawn as a link to the card's page, one resolved to an archived card named and not linked, a plain ref (and an older agent's answer with no `card`) as the tag it was; the Ref field in the New dialog sent as `-Ref` and as wide as its sibling inputs, and in the Edit dialog filled in and in the same column as What, an emptied one sent as an empty `-Ref`; every input in both dialogs at the default size, like the app's other dialogs |
| `web`: `Board.remind.test.tsx`, `cardActions.test.ts`, `scenarios.test.tsx` | **Remind me about this** absent from a card's menu with Organize off and last with it on; chosen, the dialog filled with the card's name and id, and `NewReminder` sent with `-Ref` |
| `web`: `utility/dates.test.ts` | the local day at 23:30 west of UTC (where the UTC date is tomorrow), and every due label |

**By hand**, against a scratch hub through the real agent and bridge: the chips filter, Snooze ->
Tomorrow rewrites the file's Due line, Done archives and stamps, the + adds a reminder. With both
modules on, `/communication` lands on `/organize`, which shows Meetings then Reminders and no Meetings
tab; with organize off, the Meetings tab is back, `/api/reminders` is 404, and `/organize` says it
belongs to a module that is off.

## Known gaps

- **A hub synced across two time zones** puts a reminder in different buckets on each machine, because
  times are stored local with no offset. Named on purpose, not fixed.
- **No recurrence.** Out of scope.
- **No delivery.** It reminds you, on screen. Reminding someone else is a later issue with its own gate.
- **Nothing drops a reminder in from another module yet.** A meeting's follow-up becoming a reminder
  (`MeetingAgenda` calling `NewReminder`, a no-op when organize is off) is the one link between two
  modules, and it waits for its own small issue.
- **A ref to an archived card is named, not linked.** The card page reads the active Space's `current/`
  only, so there is nowhere in the web UI to open an archived card; the row says `(done)` instead.
- **A card does not say it has a reminder.** Decided against for now -- see
  [Remind me about this](#remind-me-about-this).
- **No reminder detail page.** A reminder is one line; its file is in the hub.
