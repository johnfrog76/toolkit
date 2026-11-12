# Usage -- the day's Claude Code record

`Burn -Log` reads Claude Code's own session files on this machine and writes what they say the day
used: one record per local day per machine, in the hub. It is a ledger of tokens, kept beside the work
those tokens bought, so a later reader can set the two side by side. `Burn` alone reads them back, with
this machine's session files, as **today and this week** -- in the terminal, and on the System page's
**Claude Code burn** tile ([Today and this week](#today-and-this-week)). And `Burn -Reading` records the
plan's own weekly percentages, typed from Claude's usage page, which `Burn` opens with as **the weekly
burndown** ([The weekly burndown](#the-weekly-burndown)).

## Where

`<promptsRoot>/usage/<yyyy-mm-dd>-<machine>.json` -- a hub-root sibling, the engineer's and not an
org's, like `growth/` and `reminders/`. The folder name is a default (`folders.usage`, renamed in
`hub.json` like the others: [Configuration](../CONFIGURATION.md#the-hub-declares-its-orgs)), resolved by
`Get-P20HubFolder` and `hub_folder()`.

`<yyyy-mm-dd>` is the LOCAL day logged, `-Date`'s, today by default. `<machine>` is the machine's short
host name -- the part before any dot, anything but letters, digits, `-` and `_` turned into `-` -- the same
name the usage log, `usage.<machine>.log`, is kept under. Two machines that used Claude Code the same day
write two files, so a synced hub never has two machines writing one file.

## One record

The day [`Tests/fixtures/usage/day.json`](../../Tests/fixtures/usage/day.json) describes -- two sessions,
a response written as two lines, a subagent's transcript, four models of which one has no price -- is
written as exactly [`Tests/fixtures/usage/record.json`](../../Tests/fixtures/usage/record.json), byte for
byte. Shortened:

```json
{
  "usage": 1,
  "date": "2026-07-15",
  "machine": "build-box",
  "timezone": "America/Los_Angeles",
  "utcOffset": "-07:00",
  "source": "claude-code-session-files",
  "totals": {
    "input": 1610, "output": 3210, "thinking": 300,
    "cacheWrite5m": 2000, "cacheWrite1h": 10000, "cacheRead": 150000,
    "messages": 4, "costUsdDerived": 0.17011
  },
  "byModel": [ { "model": "claude-haiku-5-5", "input": 100, "...": "the same fields" } ],
  "bySession": [
    { "session": "11111111-aaaa-4aaa-8aaa-000000000001", "project": "demo",
      "models": ["claude-opus-5-5", "claude-sonnet-5-5"], "...": "the same fields",
      "firstAt": "2026-07-15T16:00:00.000Z", "lastAt": "2026-07-15T16:05:00.000Z" }
  ],
  "unpriced": ["claude-mystery-9"],
  "cost": { "derived": true, "currency": "USD", "priceTableAsOf": "2026-10-06",
            "note": "list prices; not the plan's allocation",
            "priceNotes": [ { "model": "claude-haiku-5-5", "note": "priced at its lower rate card, ..." } ] }
}
```

| Field | What it is |
| --- | --- |
| `usage` | the shape's version, `1`. A reader that meets a larger number reads what it knows |
| `date` | the local day the record covers |
| `machine` | the short host name, as above |
| `timezone`, `utcOffset` | the machine's time zone, and its offset from UTC at the day's start: what "local day" meant when it was written |
| `source` | where the numbers came from: `claude-code-session-files` |
| `totals` | the day's sums. `input`, `output`, `cacheRead`; `cacheWrite5m` and `cacheWrite1h`, the cache writes by lifetime; `thinking`, the part of `output` that was thinking -- a breakdown, already inside `output`; `messages`, the API responses counted; `costUsdDerived` |
| `byModel` | one row per model id, the same fields, sorted by model id |
| `bySession` | one row per session: its id, its `project`, the `models` it used, the same fields, and `firstAt` / `lastAt` -- its first and last response of the day, in UTC. Sorted by `firstAt`, then id |
| `unpriced` | the model ids the price table has no row for. Their tokens are in every sum; their cost is `null` |
| `cost` | that `costUsdDerived` is DERIVED, in what currency, and from which table; `priceNotes`, one `{model, note}` for each counted model whose price row carries a note -- today, Haiku's, which says it is priced at its lower rate card -- sorted by model, `[]` when none does |

Every array is sorted and no field records when the verb ran, so **a second run over the same session
files writes the same bytes**: a hub kept in git sees no change.

## Where the numbers come from

Claude Code keeps one transcript per session, a JSON line per event:

```text
<Claude Code's folder>/projects/<project folder>/<session id>.jsonl
<Claude Code's folder>/projects/<project folder>/<session id>/subagents/agent-<id>.jsonl
```

`<Claude Code's folder>` is `CLAUDE_CONFIG_DIR` when that is set -- Claude Code's own variable for moving
it -- and `~/.claude` otherwise. Nothing else in a project folder is read: not `tool-results/`, not a file
that is not `.jsonl`.

- **Only an assistant line with a `message.usage` counts.** A user line, a summary, a line whose model is
  `<synthetic>` (Claude Code's own placeholder, not a response) is not one.
- **One response, counted once.** Claude Code writes one API response as several lines, one per content
  block, and each repeats the response's usage -- counting lines counts a response up to four times. A
  response is its `message.id` (its `requestId` when there is none), and each of its numbers is the
  LARGEST any of its lines carries: a streamed response's early lines carry a partial output count, and a
  transcript replayed after a resume can carry a copy with zeros.
- **A response belongs to the local day of its earliest line**, its `timestamp` read as UTC and turned into
  this machine's local time. A session that runs past midnight is split there.
- **A subagent counts to its parent.** A subagent's transcript carries the parent's `sessionId`, so its
  responses are in the parent's `bySession` row.
- **Cache writes by lifetime.** `usage.cache_creation` splits a write into its five-minute and one-hour
  parts. A line without that breakdown has all of `cache_creation_input_tokens` counted as five-minute.
- **A line that is not JSON is skipped**, counted, and said on the console -- never fatal. A transcript is
  being written while it is read.
- **A file last written before the day began is not opened.** It cannot hold a line from the day, and the
  transcripts run to tens of megabytes.

**Read-only.** Every file is opened for reading only, shared with the session that may be writing it;
nothing in Claude Code's folder is created, changed or touched. A machine without the folder writes
nothing and says so, exit 0 -- and the inventory row **Claude Code usage** (`tkEnv`, `tkMenu -All`) says
`not configured` there, `on` where the folder is.

## The cost is derived

`costUsdDerived` is arithmetic over ONE table, [`Config/claude-prices.json`](../../Config/claude-prices.json):
each model's list price in USD per million tokens for input, output and cache reads, and the two cache-write
multipliers of the input price -- 1.25 for the five-minute lifetime, 2 for the one-hour. `thinking` is inside
`output` and is not priced twice. The record names the table's date (`cost.priceTableAsOf`) because a
price changes and a record does not.

A model id the table has no row for is matched to the longest id it starts with followed by a hyphen, so a
dated snapshot of a priced model takes that model's price. One with no match is counted, listed under
`unpriced`, and its cost is `null`; a session's and the day's cost are the priced models' sum, and `null`
only when none of their models is priced.

It is **list price, not what anyone paid**, and never a share of a plan's allocation: a subscription is
not billed per token, and nothing here knows what a plan allows.

**Haiku is priced at its lower rate card.** Its list price has two cards by prompt length -- one for prompts
up to 100K tokens, a higher one past that -- and the table carries only the lower. Nothing here prices by
prompt length; instead the price row carries a `note`, and every cost read from that row repeats it
(`cost.priceNotes`): the record, `Burn`'s console and `-AsJson`, and the web tile all say so.

## What it never carries

A path, the home folder, or a user name. A project folder's name spells the home path out
(`-Users-alex-Repos-demo`), so:

- a session's **`project`** is the last segment of its earliest response's `cwd` -- `/Users/alex/Repos/my-web-app`
  is `my-web-app` -- or, with no `cwd`, the last dash-separated segment of the project folder's name; a
  `cwd` or a folder that IS a home folder is `~`;
- a **session** is its id; the **machine** is its short host name.

`Tests/Test-Burn.ps1` holds every record it writes to that: no `/Users/`, `/home/`, `C:\`, `\Users\`, home
folder or user name anywhere but the `machine` line.

## Written once a day, replaced on a re-run

A record is regenerated whole from the session files each time: run `Burn -Log` again the same day and it
**replaces** that day's file -- never a second file, never an append. It is the one hub file the tool
overwrites, because it is a reading of other files rather than a record of an event, and the reading
grows through the day. It is written through `Write-CardText -New`: UTF-8, no BOM, LF.

## Held by

`tkTestToolkit -Burn`: the windows and the week boundary over
[`Tests/fixtures/usage/week.json`](../../Tests/fixtures/usage/week.json) -- under Friday 05:00, Monday 09:00
and Sunday 00:00: a record dated the week's first day the week before's, this machine's lines split at the
week's start, this machine's own record never read, and the values `burn.weekStarts` takes and refuses -- and
`Burn` and `Burn -AsJson` typed at a fixed `-At`, with `burn.weekStarts` set through `Config`; the
burndown's rule over [`Tests/fixtures/usage/burndown.json`](../../Tests/fixtures/usage/burndown.json), what
`-Reading` accepts and `burn.cacheHours`' range, and `Burn -Reading` typed -- the week's record started and
appended, another machine's readings merged, last week's not counted, the refusals writing nothing,
`burn.cacheHours` set through `Config`; whether there are session files over
[`Tests/fixtures/usage/projects-root.json`](../../Tests/fixtures/usage/projects-root.json), the table
`Tests/test_usage_burn.py` holds the agent's `claudeUsage` to as well, with the route's hour-long cache. And
the rule over the table [`Tests/fixtures/usage/cases.json`](../../Tests/fixtures/usage/cases.json)
-- an empty day, two models, a session across midnight, one response's lines counted once, a subagent's
transcript, an unpriced model, a dated snapshot, a malformed line, no cache breakdown, a file untouched
since before the day, the project names -- typed as the verb in a fresh shell, with every line's time built
from the day's local midnight so the suite reads the same in any timezone; the record above byte for byte; a
re-run's bytes; no path or name in any record; and every file under the projects folders unchanged.

## Today and this week

`Burn` with no switch is the current burn, and `Burn -AsJson` the same answer as one JSON object:

```powershell
tkBurn           # today and this week, on the console
tkBurn -AsJson   # the same, as JSON -- what the agent serves
tkBurn -At '2026-11-06 04:59'   # as it stood then: that moment's today and week
```

- **Today** runs from local midnight to now; **this week** from the latest **week start** to now -- the
  `burn.weekStarts` setting, **Friday 05:00 local by default**, when the allocation resets. A plan that
  resets at another time says so once: `tkConfig -Set burn.weekStarts="Monday 09:00"`
  ([Configuration](../CONFIGURATION.md#burnweekstarts----when-the-burns-week-starts)). Every rule below
  reads the week's start from it; "Friday 05:00" in the examples is the default.
- **Two readings meet in it.** THIS machine is read from its session files, live, by the same rules as the
  record. Every OTHER machine is read from the day records it logged into the hub's `usage/` -- so another
  machine is only as current as its last `Burn -Log`. This machine's own records in `usage/` are never read
  here, so nothing is counted twice. A file in `usage/` that is not a record is skipped and counted.
- **The week boundary.** This machine's own lines are read by timestamp and **split at the week's start
  exactly** -- Friday 05:00 by default. A day record cannot be split, so **another machine's day record counts
  toward the week it starts in**: a record starts at 00:00 on its date (read on this machine's calendar), so
  with the default **a record dated Friday counts toward the week that ENDS that Friday at 05:00, not the one
  that begins then** -- and under `Monday 09:00`, a Monday-dated record is the week before's the same way. A
  week that starts at 00:00 takes its own day's record. One consequence worth knowing: on the week's first day
  after its start time, another machine's record for that day is in **today** and not in **this week** -- it
  belongs to the week that just ended.
- **The same blocks.** Each window has `totals`, `byModel` (tokens by model and a derived cost each) and
  `unpriced` in the record's own field shapes, and `machines`: one row per machine counted, its `source`
  (`session-files` for this one, `usage-records` for another, with the `days` it logged), its messages and
  its derived cost. Every model is priced from the table as it is now, so one answer is one table's
  arithmetic; `cost` is the record's block, `priceNotes` included. No plan percentage in either window:
  the only percentages in the answer are the burndown's, and those are typed
  ([The weekly burndown](#the-weekly-burndown)).
- **When it stops being right.** `nextBoundaryAt` is the sooner of the next local midnight and the next week
  start -- after it, the windows themselves are different. `weekStarts` names the setting it was read under
  (`Friday 05:00 local`), `asOf` when it was read; `sessionFiles` and `hub` say whether there were session
  files here and a `usage/` folder to read.
- **`-At <yyyy-mm-dd HH:mm>`** reads the burn as it stood at a past local time: that moment's today and week,
  and nothing after it -- no line later than it, no record dated after its day. A time to come is refused.
- A machine with no session files adds nothing and says so; with no hub, only this machine is read.
  `-Date` belongs to `-Log`, and `-AsJson` and `-At` to the read: `Burn -Date ...`, `Burn -Log -AsJson` and
  `Burn -Log -At ...` refuse, exit 2. So does a `burn.weekStarts` the verb cannot read, naming the key and the
  file it is read from.

**In the web UI** it is the **Claude Code burn** tile on the System page: today and this week, a small table
by model, which machines were counted, the price notes, and when it was read. It is drawn only where `/env`'s
`claudeUsage` is true -- the **Claude Code usage** inventory row's rule, Claude Code's projects folder on the
agent's machine -- and absent otherwise, with nothing fetched. Facts only: no colour and no word says good or
bad. The figures are the CLI's by construction: `GET /api/usage/burn` runs `Burn -AsJson` through the bridge
([Architecture](../ARCHITECTURE.md)) and keeps the answer on the agent's disk for an hour, never past its
`nextBoundaryAt`; the browser keeps it for the session and never polls. **Refresh** asks again with
`refresh=1`, past the agent's hour.

## The weekly burndown

How much of this week's plan is used, in each of the plan's buckets, and whether the week is ahead of or
behind an even pace. **Every number in it is a reading someone typed.** Claude Code's session files hold
tokens, not the plan's allowance, and the percentages Claude's usage page shows are on no file on this
machine; a percentage worked out from tokens or from the derived cost would be a made-up number, so
nothing here estimates one.

```powershell
tkBurn -Reading general=43,premium=54                 # now, as the usage page shows it
tkBurn -Reading premium=54 -At '2026-11-10 09:10'     # one bucket, read earlier
tkBurn                                                # opens with the burndown
```

```text
  Weekly burndown, claude plan -- resets Fri 13 Nov 05:00 (2d 16h left)
      General           #########...........   43%   behind pace by 17 (pace 60% at Tue 09:10)
      Premium (Fable)   ############........   58%   behind pace by 4 (pace 62% at Tue 12:30)
      *cached as of Tue 10 Nov 12:30 - renews Tue 10 Nov 16:30 (burn.cacheHours 4)
      Typed readings, never estimated; pace is an even line from 0% at the week's start to 100% at the reset.
```

### A reading

`-Reading` takes `bucket=percent`, one bucket or several, comma-separated (`general=43,premium=54`, quoted
or not). **A bucket** is a key of `burn.buckets` in `config.default.json` -- `general` (General) and
`premium` (Premium (Fable)) by default, matched ignoring case -- because a plan's buckets are the plan's:
a second plan is new configuration, not new code. `burn.buckets` and `burn.product` (`claude`) are the
team's configuration, like `workItemTypes`, and not a `Config -Set` row. **A percent** is a whole number
from 0 to 100, as the usage page shows it; a trailing `%` is allowed. **One bucket alone is a reading**:
typing `premium=54` leaves General's latest reading as it was. `-At <yyyy-mm-dd HH:mm>` says when it was
read, a past local time; without it, now. Refused, exit 2, with nothing written: a bucket the plan does not
have, one typed twice, a percent that is not a whole number from 0 to 100, no hub, and `-Reading` with
`-Log`, `-Date` or `-AsJson`.

### Where it is kept

`<promptsRoot>/usage/readings/<yyyy-mm-dd>-<machine>.json` -- beside the day records, in a subfolder
(`readings`, `consts.json` `usage.readingsFolder`) so the day-record reader, which reads `usage/*.json`
and nothing below, never meets one. **One file per week per machine**: `<yyyy-mm-dd>` is the local date the
week starts on (`burn.weekStarts`), `<machine>` the short host name as above. Per machine, so two machines
never write one synced file; the week's readings are every machine's files for that week, merged by time.

```json
{
  "readings": 1,
  "product": "claude",
  "source": "typed",
  "machine": "build-box",
  "weekStart": "2026-11-06T13:00:00.000Z",
  "weekStarts": "Friday 05:00 local",
  "entries": [
    { "at": "2026-11-10T17:10:00.000Z", "buckets": { "general": 43, "premium": 54 } },
    { "at": "2026-11-11T16:00:00.000Z", "buckets": { "premium": 60 } }
  ]
}
```

| Field | What it is |
| --- | --- |
| `readings` | the shape's version, `1` |
| `product` | whose plan: `burn.product`, `claude` |
| `source` | `typed`: a person read it off the usage page. A supported reader, if Claude Code ever offers one, would be a second writer of the same record with its own `source` |
| `machine` | where it was typed |
| `weekStart`, `weekStarts` | the week's first instant, in UTC, and the setting it was worked out under |
| `entries` | one per reading, in time order: `at`, when it was read (UTC), and `buckets`, only the buckets typed |

A reading is **appended**: the file is read, the entry added, the entries sorted by time and the whole
written through `Write-CardText` -- `-New` when the week's first reading creates it (UTF-8, no BOM, LF), as
an edit after. Unlike a day record it is a record of events, so a reading is never replaced; to take one
back, edit the file. A file there that is not a readings record is refused rather than overwritten.

### The rule

[`Tests/fixtures/usage/burndown.json`](../../Tests/fixtures/usage/burndown.json) is the table, one row per
case: no reading, one bucket typed, behind, ahead, on pace, the rounding, two readings across machines,
stale, the renewal's exact moment, a reading from before the reset, one after now, one at the week's first
instant. `Get-P20Burndown` (`Scripts/Read-BurnReadings.ps1`) is the CLI's, and the web asserts the same
table where it draws the burndown.

- **The week** is `burn.weekStarts`'s -- Friday 05:00 local by default, the reset -- to the next week start.
  A reading counts toward the week holding its time: at or after the week's start, before the reset, and
  not after now (with `-At`, not after then). **A new week starts empty** at the reset.
- **Per bucket, the latest reading that names it** counts, from any machine. Two at the same instant go to
  the machine whose name sorts last.
- **Pace** is a straight line from 0% at the week's start to 100% at the reset, in real time (UTC
  instants, so a week across a clock change is 167 or 169 hours). It is read **at the reading's own time**,
  not at now: the gap is a fact about the reading, and an old reading is not counted against a clock that
  has moved on since. `pace = floor(elapsed / week length x 100 + 0.5)`, a whole percent rounded half up.
- **The gap** is `percent - pace`, whole points: more than zero is **ahead of pace by** it, less is **behind
  pace by** it, zero is **on pace**. Behind is capacity that resets unused if nothing changes. It is a gap,
  not a judgement: no colour and no word says good or bad.
- **The cache line.** `cachedAt` is the latest reading the burndown uses; `renewsAt` is `cachedAt` plus
  `burn.cacheHours` (4 by default; [Configuration](../CONFIGURATION.md#burncachehours----how-long-a-reading-is-current));
  `due` is whether now is at or past `renewsAt`. Due is a fact, not an error: the reading is still shown,
  and the line says `renewal due since` instead of `renews`.
- **No reading this week**: every bucket's percent, pace and gap are `null`, `cachedAt` and `renewsAt` are
  `null`, and `Burn` says how to record one.

### In the answer

`Burn -AsJson` carries it as `burndown`, and so does `GET /api/usage/burn`:

| Field | What it is |
| --- | --- |
| `product`, `source` | `burn.product`, and `typed` |
| `weekFrom`, `resetsAt` | the week's start and its reset, UTC |
| `cacheHours`, `cachedAt`, `renewsAt`, `due` | the cache line, as above |
| `buckets` | one row per `burn.buckets` entry, in config order: `key`, `label`, `percent`, `readingAt`, `machine`, `pace`, `gap` -- the last five `null` with no reading |
| `readings` | every reading this week up to now, in time order -- `at`, `machine`, `buckets` -- for a line through the week |

`skipped.readings` counts a readings file or entry that could not be read. The agent keeps the answer as it
keeps the burn's, and a new reading is a miss at once: it fingerprints the readings folder, and never serves
a kept answer past its `renewsAt` ([Today and this week](#today-and-this-week)).

## Not yet

No record is written unless someone runs `Burn -Log`: nothing schedules it, so another machine's share of
today is as old as its last log. The ratio of the burn to the work it bought, and a weekly chart, are later
work on the records this logs.

The weekly burndown is in the terminal and in `GET /api/usage/burn`'s answer; the System page does not
draw it yet.

Known gap: [The plan's weekly usage is typed, not read](../KNOWN-GAPS.md#the-plans-weekly-usage-is-typed-not-read).
