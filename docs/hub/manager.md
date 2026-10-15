# `manager/` — the 1:1 session record

One folder in the hub, one file per meeting, and the file is the record. This document is the
shape's owner: the template writes it (through `NewMeeting`, which the agent's `POST /api/manager`
runs -- the agent creates no session of its own), the agent's `PUT` rewrites it, the
fixture under `Tests/fixtures/hub/manager/` is an example of it, and two test suites assert it. A
change here is a change to all of them at once.

Nothing in this document is specific to a manager 1:1. `MeetingAgenda -Type` generalises the same
lifecycle to any recurring meeting that wants an agenda, a state check and a record afterwards.

## Where it lives

```text
<promptsRoot>/
  manager/
    current/
      YYYY-MM-DD.md                  a 1:1 that is still live
      client-weekly-YYYY-MM-DD.md    another recurring meeting -- a SERIES -- on the same day
    archive/
      YYYY-MM-DD.md                  a session that has stopped carrying forward
```

**The name is the contract's rule** (`consts.json` `regex.sessionName`, read by `NewMeeting`,
`MeetingAgenda` and the agent alike): `[<series>-]YYYY-MM-DD.md`. The **1:1 is the default series** and its
records are named by the date alone. Any other recurring meeting -- a
client weekly, a team sync -- is a series, named with lower-case letters, digits and dashes, and its
records carry that name in front of the date, the way a card carries its type, so two meetings on one day
cannot collide. `-Type <series>` on both verbs, `series` on the agent's create. **Carry-forward is per
series**: a record's `## Carried from` names the last record in the SAME series, so a client weekly never
carries from the 1:1. The heading of a series' record is
`# <series> YYYY-MM-DD`; the 1:1's stays `# YYYY-MM-DD`.

**`manager` is a default, not a constant.** The hub declares its hub-root folder names in
`<promptsRoot>/hub.json`'s `folders` block, and both consumers resolve this one through a single
accessor -- `hub_folder("manager")` in the agent, `Get-P20HubFolder -Name manager` in the CLI. Omit
the key and it stays `manager/`. [Configuration](../CONFIGURATION.md#the-hub-declares-its-orgs) has the manifest.

`manager/` is a **sibling of the per-org folders, not nested inside one**. A 1:1 history spans
engagements the way a career record does — it must not reset when the active Space does. This is also
why the `manager` recipient lives in a top-level `managerWorkflow` block rather than on an org.

Filenames are date-first so the folder sorts chronologically and a session's identity is its date.
That identity spans both folders: one date is one session, whether it is open in `current/` or
closed in `archive/`, and every writer on both sides checks the pair rather than one of them.
A file in `current/` whose name is not a date is not a session, and nothing reads it.

## The stages

A session moves through three before it becomes a record. Which one it is in lives in the file's
own `## Stage` heading — **derived from the file, stored nowhere else**, the same rule the prompt
cards follow.

| Stage | Value | When | What comes out |
| --- | --- | --- | --- |
| **Plan** | `draft` | One to two days before | A scan-ready agenda you can read in sixty seconds |
| **Prep** | `prep` | The same morning | A state check. Not about content — about how you are walking in |
| **Retro** | `retro` | Within thirty minutes after | Summary, commitments, carry-forward, self-assessment |

Prep has no agent pass on purpose: the questions are the whole of it, and an assistant adds nothing
to answering them honestly.

## The file

Eight headings, always all eight, in this order. A section that holds only a parenthesised
placeholder is read as empty everywhere — so a freshly scaffolded session does not pre-fill a form
with its own instructions, and does not list itself as having content it does not have.

```markdown
# 2026-01-22

## Stage
prep

## Carried from 2026-01-08
Reporting rewrite is unscheduled; agreed to raise it again with a date attached.

## Since Last Session
Queue timeouts are fixed and deployed. Started the reporting spike.

## Unresolved / Forward
The spike needs a decision before it becomes a project by accident.

## Agenda
- **Work**
  - Queue timeouts
    - fixed, deployed, no recurrence in two weeks
- **Alignment**
  - Where does the reporting rewrite sit against next quarter's delivery?
- **Forward**
  - Interested in owning the data side of this end to end.

## Prep
(populated at the Prep stage)

## Retro
(populated by the Retro pass)

## Sent
(nothing sent yet)
```

| Heading | Owner | Notes |
| --- | --- | --- |
| `## Stage` | the CLI and the agent | `draft` / `prep` / `retro`. The only place state lives |
| `## Carried from <date>` | the scaffold (the date, once); the Plan pass (the body) | The date is **in the heading**, which is what makes the thread traceable by eye and how the draft pass finds the prior session. Filled when the session is created and never rewritten; every reader checks it ([below](#which-session-a-record-carries-from)) |
| `## Since Last Session` | you | Raw notes. Nobody tidies these but you |
| `## Unresolved / Forward` | you | Still open, plus one thing beyond the current sprint |
| `## Agenda` | the Plan pass | Two-level outline. A save from the notes form never overwrites it |
| `## Prep` | you | State check. Optional, and nothing else reads it |
| `## Retro` | you, then the Retro pass | Your raw notes go in; the pass replaces them with the structured version |
| `## Sent` | the send | `Sent to <recipient>: <ISO date>`, one line per send -- written by the web button and by `tkSendTeams -Session <file>`, from one literal (`consts.json` `stamps.sent`) |

**Why `## Sent` exists.** When the retro summary goes to your manager, the file records that it
happened. Not a tracker, not the web UI's state — the file, because that is the premise everything
else here rests on: if it is not in the file, it did not happen. And it is read as well as written:
the web UI's send button disables itself on a line here, naming the date, and the
assistant's pass (`agentic/manager1on1.prompt.md`, step 5) stops on one — so the two paths that can
send cannot both send. Both post the same thing, the `## Agenda` section.

### The bytes it is written with

A session gets the same contract a card gets, through the same writer --
`Write-CardText` in `Scripts/Write-CardText.ps1`, dot-sourced by `New-Meeting.ps1`,
`Get-MeetingAgenda.ps1` and the `**Closed:**` stamp alike:

- **UTF-8, never a BOM**, whichever verb touched the file last -- so on a hub with `storeSync: git` a
  close shows up as one added line rather than as a whole-file diff.
- **LF, because a session is a file the tool creates.** Both scaffolds (`NewMeeting`, which the web's
  create also runs, and `MeetingAgenda -Plan`) call the writer with `-New`,
  which normalises CRLF to LF. The template is not copied byte for byte: on a Windows clone, where
  `* text=auto` plus `core.autocrlf=true` checks `templates/ManagerSession.template.md` out CRLF, that
  would write CRLF sessions beside the Mac's LF ones in the same hub.
  A stage change is an EDIT: it rewrites the whole file and keeps the terminator it finds, so a
  session you edited on Windows stays CRLF.

Asserted on first bytes by `tkTestToolkit -NewMeeting` and `-MeetingAgenda`, including that
`-Close` changes exactly one line of the file. [The CLI](../CLI.md#the-bytes-a-card-is-written-with), "The bytes a card is written
with", is the general rule.

## Which session a record carries from

A record carries forward from **the latest earlier record in its own series**, across `current/` and
`archive/` together: the 1:1 from the last 1:1 before it, a client weekly from the last client weekly.
`NewMeeting` (and `MeetingAgenda -Plan`, when it scaffolds) writes that date into
`## Carried from <date>` -- or `(none)` for the first record in a series -- **once**, when the session
is created.

So the heading can go wrong after the fact: a session added later for an earlier date sits between
the two, or someone edits the heading by hand. **Every reader checks it and says so; none rewrites
it.** The heading is the record, and a hand edit may have been on purpose -- the person corrects it,
or carries forward from the one they meant. The check has four answers:

| Verdict | When | What a reader says |
| --- | --- | --- |
| `ok` | The heading names the latest earlier record in the series, or `(none)` when there is none | Nothing |
| `stale` | It names an earlier record in the series, or `(none)`, and a later earlier one exists -- the session was created out of order, or the heading was edited back | `Carried from <named>, but the latest earlier session in this series is <date>.` |
| `missing` | It names no earlier record in this series: a date with no file in either folder, a date in another series, a date not before this session, or text that is not a date | `Carried from <named>, which is not an earlier session in this series; ...` |
| `absent` | The session has no `## Carried from` heading | `This session has no '## Carried from' heading, and ...` |

Each sentence ends by naming the latest earlier date (or saying there is none) and that the heading
was not rewritten. A file in either folder whose name is not a record (`notes.md`) is not a session
and counts for nothing; whitespace around the date is not part of it; the heading is matched
ignoring case and read from an LF or a CRLF line.

| Reader | Where it says so |
| --- | --- |
| `NewMeeting`, and `MeetingAgenda -Plan` when it creates the session | A `Check:` line naming the LATER record the new one now sits in front of -- its heading is the one that just went stale |
| `MeetingAgenda -Date <d>` (the status), and the quick menu with no date | A `Check:` line under the session. The status also prints the body under the heading the file actually has, rather than under a date it recomputed |
| `MeetingAgenda -Plan` on an existing session | A `Check:` line beside the carry-forward it prints, which is the latest earlier session's retro |
| `GET /api/manager/{filename}` and the `PUT`'s answer | `carried_from` (what the heading names), `carried_from_expected`, `carried_from_verdict` and `carried_from_note` -- the sentence, `""` when the heading is right |
| [`agentic/manager1on1.prompt.md`](../../agentic/manager1on1.prompt.md), step 3 | Checks the same thing before the draft pass, says so naming both dates, and asks which session to carry forward from |

The rule is implemented twice -- `Resolve-P20CarriedFrom` in `Scripts/Resolve-CarriedFrom.ps1` for the
CLI, `carried_from_check` in `agent/communication/manager.py` for the agent -- and held together by one
shared table, `Tests/fixtures/carried-from/table.json`, one row per shape the rule distinguishes,
asserted row for row from `Tests/Test-MeetingAgenda.ps1` and `Tests/test_manager.py`.

## The commands

```powershell
tkNewMeeting                        # scaffold today's session from the template
tkNewMeeting -Date 2026-06-12       # scaffold a specific date

tkMeetingAgenda                     # status of today's session
tkMeetingAgenda -Plan               # create it and stage it for the agenda pass
tkMeetingAgenda -Prep               # the same-morning state check
tkMeetingAgenda -Retro              # stage it for the post-meeting pass
tkMeetingAgenda -Date 2026-06-12 -Plan
tkMeetingAgenda -Type skip-level    # any recurring meeting, not only a 1:1
```

The prefix is `tk` by default and is configurable; substitute yours. All three verbs only exist
when `features.communication` is on.

`NewMeeting` and `MeetingAgenda -Plan` both scaffold. The difference is that `-Plan` also stamps the
stage and prints the carry-forward from the prior session -- the latest earlier record IN THE SAME
SERIES, found as `<series>-<date>.md` (the 1:1 as `<date>.md`) in `current/` and then `archive/` --
so it is the one to reach for when you
are actually starting a session rather than pre-creating a file.

Neither ever overwrites an existing session: the file accumulates a whole meeting's record and
re-scaffolding it would throw that away.

**The agent logic is one shipped prompt**,
[`agentic/manager1on1.prompt.md`](../../agentic/manager1on1.prompt.md), which reads the session file
and works out its own pass from what is in it. No prompt is read out of the hub.

## The web UI

With the flag on, the `Meetings` nav entry lists every session and can scaffold one; the detail page
renders what the agent wrote; the session page is the notes form, the stage ahead (`Prep`, `Retro`
-- the same `MeetingAgenda -Prep` / `-Retro` the terminal runs, through the bridge) and
the send; and a complete session is closed from the row, the detail page or the session page,
through the same `MeetingAgenda -Close`. See [`docs/modules/communication.md`](../modules/communication.md).

## Archiving

`MeetingAgenda -Date <YYYY-MM-DD> -Close` when the record has stopped carrying forward. It moves the
file from `current/` to `archive/`, creates `archive/` if it is not there, and stamps
`**Closed:** YYYY-MM-DD` — the same stamp `Archive` writes and the one the engagement timeline reads.
Running it twice is a report, not an error.

It is a switch on `MeetingAgenda` rather than a use of `Archive`, and that is not an oversight:
`Archive` is org-scoped — it moves a prompt card out of the **active org's** `current/` — and
`manager/` is a sibling of the org folders, so it would not find a session if it tried. The module
closes its own data and `Archive` stays org-scoped.

It is also a separate switch from `-Retro`. `-Retro` is a stage stamp, run within thirty minutes of
the meeting and before the notes exist; it is re-runnable and leaves the file open because the
record is still being written. `-Close` is the later, one-way event. Folding one into the other
would archive a session mid-sentence.

## What reads these files

| Reader | What it takes |
| --- | --- |
| `GET /api/manager` | Every session, with its stage and a one-line summary |
| `GET /api/manager/{filename}` | One session, split into the sections the form owns and the raw content, with `folder` -- `current` or `archive` -- because this route serves a closed session and `PUT` refuses one, and the `## Carried from` check ([Which session a record carries from](#which-session-a-record-carries-from)) |
| `agentic/manager1on1.prompt.md` | The whole file, and it decides its own pass from the contents |
| The retro send | The `## Agenda` section, and nothing else — never the self-assessment |
