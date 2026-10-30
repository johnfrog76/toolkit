# The communication module

The communication module is where an engineer runs their recurring meetings -- the manager 1:1 first,
and any other series beside it -- and sends a meeting's outcome to Microsoft Teams. It plans each
meeting through its stages (Plan, Prep, Retro, then Close), keeps one file per meeting in the hub, and
posts through the Teams engine, carried whole from the predecessor with its tests. One flag
switches all of it. This document is for anyone working on the module, and it stands alone.

| | |
| --- | --- |
| Flag | `features.communication` — **engineer-scoped**, top-level, holds across orgs |
| CLI | `SendTeams`, `NewMeeting`, `MeetingAgenda` |
| Backend | `agent/communication/` — `manager.py`, `comms.py` |
| Frontend | `web/src/modules/communication/` — export `communicationModule` |
| Hub data | `<promptsRoot>/manager/` — see [`docs/hub/manager.md`](../hub/manager.md) |

## The flag, and its scope

`features.communication` is the **engineer's**, not the org's. It lives in the top-level `features`
block and an org cannot override it, because a 1:1 history spans engagements: switching from an
active org to an archived one must not make this module appear and disappear. Only the ADO core's
own org-scoped keys are read from the active Space.

The engine's own gate reads the merged features map that `load_config()` produces, which is the same
map `/env` serves and the same one the web shell filters modules on.

**Off means absent.** No route, no nav entry, no card, no chunk; no `SendTeams`, `NewMeeting` or
`MeetingAgenda` alias, and nothing in `Menu`. Not hidden, not disabled, not a 403.

## Two gates, and they are not the same thing

This is the part worth reading twice.

| | Gate 1 | Gate 2 |
| --- | --- | --- |
| What it decides | Whether the module exists | Whether a send can happen |
| Where it is | `features.communication` in config | The recipient's webhook variable in the environment |
| Off looks like | 404, no alias, no route | A disabled button naming the variable; `skipped` from the engine |
| Who checks it | The router dependency, the command loader, the registry | `SendTeams` at call time, `/env` ahead of the click, the engine before it posts |

A person with the flag on, 1:1 notes and no webhook configured sees every page and writes notes
perfectly well. Only the send degrades — and it degrades by **saying which variable to set**, not by
failing.

**The webhook URL is never in config.** Config names the variable; the environment holds the URL.
`config.default.json`'s `managerWorkflow.communication.recipients.manager.webhookEnv` is
`TEAMS_WEBHOOK_MANAGER`; a recipient that names no variable falls back to the convention
`TEAMS_WEBHOOK_<KEY>`, and `TEAMS_WEBHOOK_URL` is a catch-all the engine accepts for any recipient.

## Getting a webhook URL

Nothing in Teams says where this lives, so the path, once:

1. In Teams, search **Workflows** and open it, then pick the template **Send webhook alerts to a chat**
   (a person, such as your manager) or **Send webhook alerts to a channel** (a team channel). The
   "from specific people" variants of each work the same way; the URL is what matters. Microsoft's
   own steps: <https://support.microsoft.com/en-us/workflows/send-messages-in-teams-using-incoming-webhooks>.
2. Save the workflow, then copy the URL from its details page.
3. Put it in `.env` in the package root, one variable per recipient (copy `.env.example` first;
   `.env` is gitignored): `TEAMS_WEBHOOK_MANAGER=https://...`. `TEAMS_WEBHOOK_URL` is the catch-all for
   a declared recipient with no variable of its own.
4. **Restart the agent** (`tkWeb -Stop`, then `tkWeb -Dev`). `SendTeams` posts through the running
   agent, and the agent reads `.env` when it starts, so a variable set in a shell does nothing and a
   change needs the restart. With no agent running a send fails (`Could not reach the agent`).
5. Prove it unsent: `tkSendTeams manager 'Hello from the Toolkit' -WhatIf`. The URL is a secret; never
   send from a session to find out.

**A second recipient is declared by hand.** `TEAMS_WEBHOOK_<KEY>` only supplies the variable name for a
recipient that is already declared under `managerWorkflow.communication.recipients`; an undeclared
one is refused (`unknown recipient key 'mom'`). `Config -Set` cannot declare one -- the schema is built
from the shipped keys, where `manager` is the only recipient -- so edit `config.local.json`
(top-level, gitignored) yourself:

```json
{ "managerWorkflow": { "communication": { "recipients": {
    "demo_channel": { "type": "channel", "display": "Demo channel" } } } } }
```

`"type"` is `"channel"` **even for a person**: `"chat"` is refused as `unsupported type`, and the shipped
`manager` entry is itself a `"channel"` whose display says "DM via Workflow". Then
`TEAMS_WEBHOOK_DEMO_CHANNEL` is the variable. Both limits are in
[Known gaps](../KNOWN-GAPS.md) until Teams becomes a connection.

## The verbs

**The module is the Meeting Agenda Planner**: the 1:1 is
one meeting it plans. `-Type <series>` on `NewMeeting` and `MeetingAgenda` names another recurring
meeting; its records are `<series>-YYYY-MM-DD.md` with their own carry-forward, and `MeetingAgenda` with no
switch is the quick menu -- every open record, its stage, and the exact next command. With no `-Type`,
every verb and page works on the 1:1.

All three exist only when the flag is on. The prefix below is the default `tk`.

| Verb | Function | Script |
| --- | --- | --- |
| `SendTeams` | `Send-P20TeamsMessage` | `Scripts/Send-TeamsMessage.ps1` |
| `NewMeeting` | `New-P20Meeting` | `Scripts/New-Meeting.ps1` |
| `MeetingAgenda` | `Get-P20MeetingAgenda` | `Scripts/Get-MeetingAgenda.ps1` |

Flags, as verified against each script's `param()` block:

```text
SendTeams      <recipient> <message> [-Session <file>] [-WhatIf] [-AsJson] [-Help]
NewMeeting     [-Date <YYYY-MM-DD>] [-Type <series>] [-Help]
MeetingAgenda  [-Plan] [-Prep] [-Retro] [-Close] [-Date <YYYY-MM-DD>] [-Type <t>] [-DryRun] [-Help]
```

**`SendTeams`** builds the smallest valid message object — the message string as the subject, tone
`broadcast` — and posts it to the running agent's `/api/comms/send`. Running it is the opt-in; there
is no template and no dedup. It checks gate 2 itself, before the POST, so the answer arrives without
a round trip and names the fix. It reads the recipients the way the engine does: the `managerWorkflow`
block from both config files, then the active Space's `communication.recipients` wherever that org is
declared -- the shipped list, the hub's `hub.json`, or this machine's `spaces.<slug>` patch. A recipient nobody declares is left to the engine, whose
`skipped` comes back as a printed "Not sent -- skipped" line, not a throw. `-Session <file>` names the
meeting record the send is for: after an `ok`, `Sent to <recipient>: <date>` goes under its `## Sent`
through `Scripts/Add-SentLine.ps1` -- the same line the web button writes, from the same literal
(`consts.json` `stamps.sent`) -- so a send from a terminal is on the record too. While a test run is in
progress (`env.testRunMarker` set by every runner) neither this script nor the engine posts:

```text
Not sent -- no webhook configured for 'manager'.
Put TEAMS_WEBHOOK_MANAGER=<the recipient's webhook URL> in .env in the package root (copy .env.example).
The agent reads .env when it starts: restart it (tkWeb -Stop, tkWeb -Dev) after a change.
The URL is a secret: it belongs in .env, never in config.
```

That path **exits 0**. An unset variable is a configuration fact, not a failure, and erroring would
make it look like a broken toolkit. A recipient the config does not know is left to the engine,
which has the whole registry and a better message for it. `-WhatIf` becomes the engine's `dryRun`:
every gate runs, the markdown is formatted, and the would-be payload comes back unsent.

**`NewMeeting`** scaffolds one session from `templates/ManagerSession.template.md` — which ships
with the toolkit, not with the hub. It never overwrites, and **"already exists" means either
folder**: a date whose session is in `current/` is reported and left alone, and one already closed
into `archive/` is **refused** (exit 2), naming the archived path. A session's identity is its date
([`docs/hub/manager.md`](../hub/manager.md)), so scaffolding a blank one beside a closed record
would put two files under one identity — which `MeetingAgenda -Close` could then protect but not
resolve. It fills `## Carried from <date>` with the latest earlier record in the series, and when
the new date is EARLIER than a record already there, it prints a `Check:` line naming that later
record: its heading still names what came before, and is now stale. It says so and rewrites
nothing ([Which session a record carries from](../hub/manager.md#which-session-a-record-carries-from)).

**`MeetingAgenda`** is the stage driver.
Without a flag it reports status. With one it stamps `## Stage` and prints what that stage needs
from you, pointing at [`agentic/manager1on1.prompt.md`](../../agentic/manager1on1.prompt.md) for
Plan and Retro. Prep points at nothing: it is a state check, not a writing pass.

Its status, its quick menu and `-Plan` read the session's `## Carried from` heading and check that
it still names the latest earlier record in the series. When it does not -- a session added out of
order, a heading edited by hand, or one naming a session that is not there -- they print a `Check:`
line with both dates and change nothing. `-Plan` also prints the carry-forward from the series' own
latest earlier record (`<series>-<date>.md`, the 1:1's `<date>.md`), looked up in `current/` and then
`archive/`; a series never carries from the 1:1. The status prints the body under the heading the file
has. The rule and its four verdicts are
[Which session a record carries from](../hub/manager.md#which-session-a-record-carries-from).

`-Close` is the fourth flag and the only one that is not a stage. It retires the session: the file
moves from `manager/current/` to `manager/archive/` (created if absent) and gets
`**Closed:** YYYY-MM-DD` stamped into it, from the same implementation `Archive` uses -- one writer
for a literal `agent/ado/reporting.py` parses. A second `-Close` is a report, not an error, and
`-DryRun` names both halves of what it would do without writing. This is the module closing its own
data: `Archive` stays org-scoped and cannot see a hub-root sibling, and growth closes its own items
from its own side.

### An agenda line becomes a card

There is no verb for it: it is the core's own `tkNewPrompt -Title "<the line>" [-Type <t>] -From <record>`,
the one place this module's records reach into the board. `<record>` is the meeting record's file name as
`MeetingAgenda` writes it -- `2026-10-28` for the 1:1, `client-weekly-2026-10-28` for a series, `.md` or
not -- looked for in the meeting folder's `current/` and `archive/` (the folder's name is the hub's,
`hub.json` `folders.manager`). The card is an ordinary card with one more footer line, `**From:** <record>`,
which the agent serves as the card model's `from_record`
([the footer](../hub/cards.md#3-the-footer----one-fact-per-line)). A record that is not there is a stated
refusal and no card is written; a card that already exists is returned as it is, with no line added. The
switch is core and works whether this module's flag is on or off: the record is a file in the hub either way.

### How the verbs get registered

`Config/communication.commands.psd1` is the module's contribution to the CLI surface — a `Commands`
map of verb name to function and a `Help` table in exactly the shape `config.default.json`'s
`commands.<Name>` entries use. `Config/communication.commands.ps1` holds the three wrappers.

The loader merges both into the CLI's command table **only when the top-level
`features.communication` is true**. A wrapper's `-Help` renders from the merged help table, so a
module verb gets `-Help` for free and reads identically to a core one.

`Commands` is a plain hashtable and `Order` carries the sequence: `Import-PowerShellDataFile` refuses
a type cast such as `[ordered]` (*"Cannot generate a PowerShell object for a ScriptBlock evaluating
dynamic expressions"*), and the loader reads with nothing else on purpose. The whole contract is
[How a module contributes commands (D-CM)](README.md#how-a-module-contributes-commands-d-cm).

## The backend

| Route | Reads / writes | Notes |
| --- | --- | --- |
| `GET /manager` | `manager/{current,archive}/` | Every session, newest first |
| `GET /manager/{f}` | one session | Split into the sections the form owns, plus the raw content, and the `## Carried from` check: `carried_from`, `carried_from_expected`, `carried_from_verdict`, and `carried_from_note` -- the sentence to show, `""` when the heading is right. `PUT` answers with the same four. Read, never rewritten |
| `POST /manager` | runs `NewMeeting` through the bridge, then reads the file it wrote | `{date, series}` only -- notes are an edit, through `PUT`, and a body with more is 422. 409 rather than overwrite, for a session in `current/` **or** already closed into `archive/`; 400 on a date that is not one; 503 naming the verb when the module is not in the CLI's table. The verb is the one writer of a new session |
| `PUT /manager/{f}` | rewrites one session | **The only PUT in the API** |
| `POST /comms/send` | outbound webhook | A thin wrapper over the engine |
| `POST /rewrite` | a model | Tidies a raw notes textarea. Declines with a reason when there is no key |
| `POST /cmd/MeetingAgenda` | the bridge | Not this module's route -- the CLI bridge, with this module's verb in the argv. The web's **Close** and its stage buttons are `-Date <d> [-Type <series>] -<Plan\|Prep\|Retro\|Close>`, built by `buildMeetingAgendaParams` in `web/src/modules/ado/cliBridge.ts` and pinned by `cliBridge.test.ts`; a stated refusal (exit 2) comes back as `status: error` and is the page's message |

The whole router carries a dependency that raises 404 when the flag is off — a dependency rather
than a conditional mount, so the answer is re-read per request and a flag flipped in another
terminal does not need a restart of the agent or the web UI (an open shell is another matter: [Configuration](../CONFIGURATION.md), "A module flag and an open shell"). `/env` gains a `communication` block, and only when the flag is on.

**Why `POST`/`PUT` here rather than through the CLI bridge.** The rest of the app has one write
path, and it is the CLI. These two bend it, for a stated reason: they save a form someone is typing
into, and round-tripping keystrokes through a PowerShell process start would make the editor
unusable. There is no second implementation to drift from — `_build_session_file` is the only thing
on either side that writes a session. Closing a session does **not** bend it: the file move and the
`**Closed:**` stamp are `MeetingAgenda -Close`, and the web's Close button runs that verb through
the bridge rather than reimplementing either half.

**What a save will not do.** `PUT` reads back everything the notes form does not own — the agenda,
the prep, the carry-forward heading and body, the stage, the Sent lines — and writes them again
unchanged. A save from the notes form cannot delete an agenda.

`append_sent` is the one addition to the request shape: one line to add under `## Sent`. It is
appended server-side so the caller never has to read the file back in order to add to it.

### `/env`'s `communication` block

```json
{
  "postRetroSummary": true,
  "retroChannel": "manager",
  "recipients": [
    {
      "key": "manager",
      "display": "My Manager (DM via Workflow)",
      "type": "channel",
      "scope": "managerWorkflow",
      "webhookEnv": "TEAMS_WEBHOOK_MANAGER",
      "configured": false
    }
  ]
}
```

`configured` is gate 2, answered before the click. `scope` says which config block the entry came
from, which is gap C7 answered by rendering rather than by moving: the `manager` recipient is
top-level and every other recipient is the active Space's, and that difference is *why* switching org
changes one list and not the other. A UI that flattened the two could not explain it.

`core/env.py` does not import this module. It asks a module that is **switched on** to describe
itself, lazily and inside the flag check, so a checkout without the module still serves `/env`.

## The frontend

Export: **`communicationModule`** from `web/src/modules/communication/index.tsx`.

| Route | Renders |
| --- | --- |
| `/communication` | `OneOnOne` — the one-card landing page the `Meetings` nav points at. A complete session's row offers **Close**. **With `features.organize` on it redirects to `/organize`**, where the same card sits beside Reminders |
| `/communication/1on1/:filename` | `ManagerDetailPage` — read view, with an `Edit / send` button to the session page, and **Close** on a complete session; under the title, the agent's `carried_from_note` as a quiet line when `carried_from_verdict` is `stale`, `missing` or `absent`, and nothing when it is `ok` or an older agent sends none |
| `/communication/sessions/new` | `ManagerSessionPage` — scaffold and edit |
| `/communication/sessions/:filename` | `ManagerSessionPage` — edit, the stage ahead (Plan / Prep / Retro through the bridge), Close on a complete session, and the send. Reached from `Edit / send` on a meeting row and on the read view |
| `/growth/1on1/:filename` | redirect, filename forwarded |
| `/growth/sessions/new` | redirect |
| `/growth/sessions/:filename` | redirect, filename forwarded |

**On the Organize tab, when there is one** ("meetings and reminders live in
`/organize`"). With `features.organize` on, the Meetings card is contributed to the Organize page through
the registry's `organize` slot (`slotCards.organize`), the `Meetings` nav entry hides itself
(`hidden: features.organize`), and `/communication` redirects to `/organize`. The Organize page imports
nothing of this module; it renders the slot, Meetings first, then its own Reminders card. The detail and
session pages keep their `/communication/...` paths. With organize off, nothing here changes: the card
keeps its own page and tab. This is the deck launcher's shape under Growth, and the two flags stay two:
communication also owns the Teams engine.

Nav: one entry, `Meetings`, active for anything under `/communication`. **No home cards and no system
cards** — a 1:1 workflow is something you go to, and the home page is for what needs doing today.

**The three `/growth/` routes are redirects.** Those are the addresses these pages had while 1:1s were
part of the growth module, and a URL the growth module does not serve must not file them. The
redirects keep every bookmark working, and two of them are components rather than plain `<Navigate>`
entries because a redirect cannot forward a route parameter for you.

Route paths live in `paths.ts`, one place, per the repo's magic-string rule. They appear in four
files, and without the one place a move of the prefix means finding every `navigate()` call by hand.

`api.communication.ts` injects the endpoints into the shell's single slice and adds the `Manager`
tag type with `enhanceEndpoints`. `/env`'s communication block is typed here, not on the shell's
`EnvStatus`, for the same reason: it is this module's vocabulary.

### Close, from the browser

A session at Retro reads "Complete — close it to move it to the archive", and beside it, on the
Meetings card's row and in the read view's header, a **Close** button, so the last step of the flow
needs no terminal either. It is `CloseMeetingButton` in `CloseMeeting.tsx`, and it is the one action on
these pages behind a confirm, because it moves a file -- the house's one confirm, `shared/ConfirmDialog`
("Are you sure?", the act named, Cancel and Submit; a refusal stays in it). The confirm runs `POST /api/cmd/MeetingAgenda`
with `-Date <date> [-Type <series>] -Close` — the argv is `buildMeetingAgendaParams` in
`web/src/modules/ado/cliBridge.ts`, pinned by `cliBridge.test.ts` — through
`useRunMeetingAgendaMutation`, which invalidates the `Manager` tag so the list and the page re-read
the file from `archive/`. Nothing in the browser decides how a session closes: the verb does, in a
child `pwsh`, and the page shows what it said. A stated refusal — the record already has a closed
copy in `archive/`, exit 2 — is `status: error` with the sentence in `error`, and the dialog stays
open showing it; an agent that cannot be reached is said to have moved nothing.

Only a **complete** session offers it — one whose stage is Retro, in `current/`. That is the page's
rule, not the script's: `-Close` closes whatever stage the record is in. A closed session's row and
header read "Closed" and offer nothing. The stage list the rule reads is `stages.ts`, one place for
the three keys and labels both pages read.

The `--modules=on` smoke asserts the button's **presence** on exactly one of the three fixture
sessions and never presses it: a press moves a file in the committed fixture hub.

### Advancing a stage, from the browser

The session page offers **one** button for the stage ahead — `Prep` at draft, `Retro` at prep,
nothing after Retro but Close, and `Plan` for a file whose `## Stage` is blank or unknown (the stamp
is what is missing; `-Plan` on an existing file only stamps it). The rule is `nextStageAction` in
`stages.ts`, read from the script: `-Plan` creates a missing file and stamps `draft`, `-Prep` and
`-Retro` need the file and stamp their word, and a closed session gets no button because `archive/`
is the record. The button **saves the notes first** (the `PUT`), then runs
`POST /api/cmd/MeetingAgenda` with `-Date <date> [-Type <series>] -<Stage>` — a stamp re-reads the
file, and a stamp over unsaved notes would put the form a step behind the file it edits. The
mutation invalidates `Manager`, so the badge and the form follow the file. A save that fails stamps
nothing and says so; a verb that refuses is the row's message in its own words.

So a session made in the browser reaches Retro, and its send, in the browser.

### The send button

On `ManagerSessionPage`. Its rule is a pure function, `sendButtonState` in `sendButton.ts`, because
there is no other way to check it — the alternative to asserting the rule is pressing a button that
posts to a real webhook.

| State | When |
| --- | --- |
| **absent** | `postRetroSummary` is false -- the workflow does not include a send, so there is nothing to explain -- or the session is closed (`folder: "archive"` on the detail): `PUT` writes only `current/`, so a send from there is one the file could never record |
| **disabled** | The stage is not Retro, the recipient has no webhook, `## Sent` already records a send (the line names the date), or the Agenda holds only its placeholder. Every reason that holds is on the line below it, the recipient's first -- so the variable is named from the moment the page opens, not revealed at Retro when it is needed |
| **enabled** | Retro stage, recipient configured, an Agenda with content, nothing under `## Sent` |

A click posts `{caller: "ManagerSessionPage", recipient: <retroChannel>, subject: <session title>,
sections: [{heading: "Agenda", body: <the Agenda section>}], tone: "personal"}` and renders the
engine's outcome inline — all six statuses, because `disabled` and `skipped` are answers rather than
failures.

**What it carries is the Agenda section and nothing else.** The Retro holds a self-assessment, which
is private reflection rather than a manager-facing note; a send that took "the session" would post
it the first time someone wrote one.

**On `ok` it writes back**: `Sent to manager: <ISO date>` appended under `## Sent` through the PUT.
The file records that it happened — not this component's state and not a tracker. That is the same
premise the whole store rests on — and the button reads the section back, so a send
recorded by anyone, this button, `SendTeams -Session` or an assistant following
`agentic/manager1on1.prompt.md`, disables it. The send and the write-back are two requests and are
reported as two: the send's outcome first, and a `PUT` that fails after an `ok` as
`sent; could not record it`, with the line to add by hand -- so a message that reached the manager
never reads `error`. The prompt's send is the same Agenda section, so the two paths post one message.

## The file shape, and how a session's state is read

One file per meeting, `<promptsRoot>/manager/current/YYYY-MM-DD.md`, and
[`docs/hub/manager.md`](../hub/manager.md) owns its shape. Two things are READ from it, and neither is
stored anywhere else:

| What | Read from | Values |
| --- | --- | --- |
| The stage | the first line under the file's own `## Stage` heading | `draft` / `prep` / `retro` -- written by `MeetingAgenda -Plan` / `-Prep` / `-Retro` and by the agent's save |
| Live or closed | the FOLDER (`current/` or `archive/`) together with a `**Closed:** YYYY-MM-DD` stamp -- every writer checks the pair, not one of them | `MeetingAgenda -Close` moves the file and stamps it, through the one shared stamp writer |

A send is recorded as a line under `## Sent`, which a save never loses. The module writes nothing else
into the hub, and nothing at all into an org's cards.

## Fixtures

`Tests/fixtures/hub/manager/current/` holds one session per stage — `2026-01-08.md` (draft — a session `NewMeeting` just scaffolded, before `-Plan` has run),
`2026-01-22.md` (Prep), `2026-02-05.md` (Retro) — in the shape `docs/hub/manager.md` documents. The
fixture is what makes that document testable rather than aspirational. The content is neutral by
design: a reporting decision and a queue timeout, nobody's name, no employer.

There is no `archive/` in the fixture, on purpose: a hub without one must still serve `GET /manager`.

## Running it live

```bash
# config.local.json at the repo root -- gitignored, per machine.
# The flag is TOP-LEVEL, never on an org.
{
  "promptsRoot": "Tests/fixtures/hub",
  "activeSpace": "test",
  "features": { "communication": true }
}
```

```bash
python3 -m uvicorn agent.app:app --port 4100      # Windows: python or py -3
curl -s localhost:4100/api/manager
curl -s localhost:4100/api/env | python3 -c "import json,sys; print(json.load(sys.stdin)['communication'])"
```

With `TEAMS_WEBHOOK_MANAGER` unset, `/env` reports the recipient unconfigured and names the
variable; set it to anything and `configured` flips to true. **`/api/comms/send` posts for real** —
the engine takes whatever is in that variable at face value. Use `-WhatIf` from the CLI, or
`"dryRun": true` on the body, to exercise the path without sending.

## Tests

| Suite | What it guards |
| --- | --- |
| `Tests/test_comms_format.py` | The engine, carried with every assertion unchanged: tone formatting, the Adaptive Card envelope, recipient resolution, the master switch, validation, dry run and fail-soft failure. This file is the evidence the engine did not change behaviour while it moved packages |
| `Tests/test_manager.py` | The routes against a copy of the fixture hub — list, read, create, save — plus the module gate and the two overwrite gates (a session in `current/`, and one already closed into `archive/`): off is a 404 that writes nothing, and `/env` reports the recipient unconfigured with its variable's name, then configured once it is set. Also that a save never deletes an agenda, never moves the stage, and never loses a Sent line; and every row of the shared `Tests/fixtures/carried-from/table.json` read through `carried_from_check`, with the detail reporting a session added out of order and leaving its file as it was |
| `Tests/Test-SendTeams.ps1` | Gate 2 reported rather than raised, the `TEAMS_WEBHOOK_<KEY>` fallback, the catch-all variable, and the wrapper. Every case runs in a sandbox with its own config and an agent port nothing listens on |
| `Tests/Test-NewMeeting.ps1` | The eight headings by name, the prior session found across folders and out of order, an existing session reported rather than overwritten — with its hand-written content asserted still there — and a date already closed into `archive/` refused, with nothing scaffolded beside the record. A session created out of order names the later record whose heading it made stale, and leaves that record alone |
| `Tests/Test-MeetingAgenda.ps1` | The stage lifecycle, read back out of the file rather than out of the command's output, and `-Close` end to end: the move, the `**Closed:**` stamp, `archive/` created when absent, a second run idempotent, and `-DryRun` writing nothing — plus the duplicate case, where a session sits in `current/` and a closed one in `archive/` for the same date and `-Close` refuses rather than reporting success. Plus two absence tests: the help names none of the three retired hub prompts, and the retro does not suggest the org-scoped `Archive` verb — it names `-Close` instead. And every row of the shared `Tests/fixtures/carried-from/table.json` read through `Resolve-P20CarriedFrom`, then the `Check:` line end to end -- status, quick menu, `-Plan` -- with the session's bytes unchanged |
| `web/.../stages.test.ts` | The three stages in one place: the file's word, the badge's label, what comes next, complete only at the last -- and the one switch the session page offers: the stage ahead, `Plan` for a blank stage, nothing for a closed session |
| `web/.../ManagerDetailPage.test.tsx` | The read view's Carried-from line: the agent's sentence drawn for `stale`, `missing` and `absent`, and nothing for `ok` or when the fields are absent |
| `web/.../cliBridge.test.ts` (three of its cases) | `MeetingAgenda`'s argv: `-Date`, `-Type` only for a series that is not the 1:1, then the one switch spelt the script's way |
| `web/.../sendButton.test.ts` | The send button's three states, including that it is absent rather than disabled when the workflow has no send, and that what goes out is the Agenda and never the self-assessment |
| `web/.../registry.communication.test.tsx` | The registry contract from this module's side: off contributes no route, nav or card; on contributes exactly these seven routes |
| `npm run smoke -- --modules=on` | In a browser: lists the three fixture sessions, reads their stages, finds the retro session's send button disabled and naming its variable, reaches the session page through `Edit / send`, and finds Close on exactly one session without pressing it |

The three PowerShell suites are registered in `Tests/Test-Toolkit.ps1` (`-SendTeams`, `-NewMeeting`, `-MeetingAgenda`) and run in the full `tkTestToolkit` pass; they can also be run directly. Each suite's count is in [Testing](../TESTING.md).

## Known gaps

| # | Gap |
| --- | --- |
| — | C7: `managerWorkflow` is top-level while every other recipient lives on an org. Answered by rendering both honestly (`scope` in `/env`) rather than by moving one. A config wizard has to show both |
| — | Prep has no agent pass: the shipped prompt has two passes (Plan and Retro), not three |
| — | An agenda line becomes a card from the terminal only (`NewPrompt -From`): the Meetings page has no "make a card" action on an agenda line, which belongs to the record's reading room, not yet built |
| — | A card made from an agenda line names its record; the record does not name the card. Whether the agenda gets a line back (`-> card K7M2`) is undecided |
| — | `Timer` is module-local. If a second module ever wants one, that is the moment to promote it to `shared/` |
| — | `/rewrite` keeps its own copy of the Messages API call rather than sharing the ADO module's. Deliberate — a module reaching into a sibling for a helper is how two modules stop being separable — but it is thirty duplicated lines |
