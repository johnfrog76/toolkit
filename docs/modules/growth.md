# The growth module

The growth module keeps an engineer's professional development and the career
record it feeds: **trainings**, **presentations** and **goals** as files in the
hub, **work reviews** generated from the cards a period touched, and the
**resume**. It is for the engineer who wants the year-end review and the resume
to come from the record rather than from memory. This document is for anyone
working on the module, and it stands alone.

Opt-in. Off by default in the committed config, and off means absent: no verb,
no menu line, no route, no nav entry, no card. An install that does not want it
cannot tell it is there.

---

## Contents

- [The flag, and why it is the engineer's](#the-flag-and-why-it-is-the-engineers)
- [What the module owns](#what-the-module-owns)
- [The verbs](#the-verbs)
- [The routes](#the-routes)
- [The web UI](#the-web-ui)
- [The file shape](#the-file-shape)
- [Turning it on](#turning-it-on)
- [The tests](#the-tests)
- [Known gaps](#known-gaps)
- [D-CM: how any module contributes commands](#d-cm-how-any-module-contributes-commands)
- [How a review decides what is in it](#how-a-review-decides-what-is-in-it)

---

## The flag, and why it is the engineer's

`features.growth`, at the **top level** of `config.default.json` or
`config.local.json`. Never inside an `spaces[]` entry.

```jsonc
{
  "features": { "growth": true }
}
```

A feature flag has a scope, and the default scope is the person. A training you
took does not stop having happened when you switch org, and a resume is not an
engagement's -- so if this flag lived on an org, Growth would appear and
disappear as you moved between an active engagement and an archived one. The
exception is the ADO core's own flags, which describe one org's board:
`sprintAwareness` is read from `spaces[].features` and is the only one.

One more key lives on the Space, and it is a number rather than a flag:
`spaces[].features.trainingHoursPerQuarter`, the hours of training a Space's
engagement requires each calendar quarter. It is the Space's because a different
client may require nothing, and it is not folded into the merged `features` map
(flags only); see "The quarter line", below.

Both halves answer this the same way and are held to it:

| Half | Implementation |
| --- | --- |
| CLI | `Get-P20Features` in `utilities.psm1` |
| Agent | `ORG_FEATURES` / `effective_features` in `agent/core/config.py` |
| Web UI | `/api/env`'s `features` map, which the agent builds with the above |

`Get-P20Features -CommittedOnly` answers the same question about
`config.default.json` alone. One caller: the autoload alias discovery. See
[Autoload](#autoload).

---

## What the module owns

Three **hub-root** folders -- siblings of the per-org folders, not children of
one, for the same reason the flag is engineer-scoped. These are their default
names; a hub renames any of them in `hub.json`'s `folders`
([Configuration](../CONFIGURATION.md)):

```text
<promptsRoot>/
  growth/current/   trainings, presentations, goals in flight
  growth/archive/   the finished ones
  reviews/<slug-set>/<year>/<start>_<end>/review.md
  resume/resume.md
```

Every path is resolved from `promptsRoot`, never from where the package sits.
`PROMPTS_ROOT` in the environment is an explicit override and wins -- one rule,
one implementation per half: `hub_root()` in `agent/core/config.py`, and
`Get-P20PromptsRoot` in `Scripts/Resolve-HubConfig.ps1`, which the module's
`$global:P20Config.PromptsRoot` is set from and which every growth and
communication script calls instead of reading the config files for itself. The
two halves must not disagree about where the store is.

`pr-comments/` is the one thing this module writes that is **org**-scoped:
reviewing a colleague's PR happens inside one engagement, so `LogPeerReview`
writes under `<promptsRoot>/<promptsFolder>/pr-comments/`.

---

## The verbs

Five, contributed through D-CM from `Config/growth.commands.psd1`. Aliases carry
whatever prefix is configured; `tk` below.

### `tkNewGrowth`

Writes a growth artifact into `growth/current/`.

```text
tkNewGrowth -Close <file>                       # retire: growth/current/ -> growth/archive/, stamped **Closed:**
tkNewGrowth -Title <string> [-Type training|presentation|goal] [-Date YYYY-MM-DD]
            [-DueDate YYYY-MM-DD (required for a training)] [-Provider <string>]
            [-Hours <string>] [-Notes <string>] [-Help]
```

| Flag | Notes |
| --- | --- |
| `-Type` | `training` (default), `presentation`, `goal` |
| `-Title` | required; becomes the filename slug, lowercased and hyphenated, 40 chars |
| `-Date` | today if omitted; the start date for a training, the event date for a talk |
| `-DueDate` | **required for a training**; a goal's end of period; a talk has none |
| `-Provider`, `-Hours` | trainings only. `-Hours` defaults to `TBD` |
| `-Notes` | one line of context: Description / Context & Intent / Why This Matters |

Exits 0 on success and on "already there"; 2 (a stated refusal) on a missing
title, a bad date, a training with no due date, or an unconfigured hub. Script:
`Scripts/New-GrowthItem.ps1`.

**`-Close <file>` retires an item**, from the terminal or the browser: *Archive* on
a `Goals` row (the row vocabulary's word for the move to the archive; it said *Retire*) runs the same verb through the bridge (`POST /api/cmd/NewGrowth`,
argv `buildGrowthCloseParams`) behind the house's one confirm
(`shared/ConfirmDialog`). The item moves to `growth/archive/` and is stamped
`**Closed:**` by the shared writer -- the module closes its own data, since
`Archive` is org-scoped and a hub-root sibling is invisible to it.

**A new item from the browser is the same verb.** The `Goals` card's New Growth
Item dialog runs `POST /api/cmd/NewGrowth` (argv `buildNewGrowthParams`), so the
browser and the terminal write one file with one writer, and opens the new item
by the name on the `FILE:` line the verb prints. A refusal -- a bad date, a
training with no due date -- is the bridge's `status: error`, and the dialog
shows the verb's own sentence. An item already in `growth/current/` is never
written over: the verb answers "Already there", and the dialog shows that and
stays open.

### `tkNewWorkReview`

Writes a review **scaffold** from local history.

```text
tkNewWorkReview -StartDate YYYY-MM-DD -EndDate YYYY-MM-DD [-Slugs "a,b"] [-Help]
```

Scans `<org>/archive/`, `<org>/current/` and hub-root `growth/` for markdown
committed in the window, reads each file's title, sprint and checklist progress,
groups by folder, and writes
`reviews/<slug-set>/<year>/<start>_<end>/review.md`. `-Slugs` is comma-joined;
the output folder is the **sorted** set joined by `+`, so `"b,a"` and `"a,b"`
write to the same place. Omitted, it uses the active Space.

Answers in JSON on stdout -- `{ review, file_path, files_scanned, files_included }`
or `{ error }` -- because the agent parses it. It therefore never prints prose
on the success path and never exits non-zero for a user error.

`PROMPTS_REVIEWS_DIR` redirects the physical write while `file_path` stays the
logical `reviews/...` path. That is how the suite runs it against a scratch hub.
Script: `Scripts/Generate-Review.ps1`.

### `tkPublishWorkReview`

```text
tkPublishWorkReview [-NoPush] [-Preview] [-Help]
```

Stages `reviews/`, commits `chore: update review (YYYY-MM-DD)`, then syncs.
`-NoPush` commits without syncing. `-Preview` emits the pending diff as JSON for
the web UI instead of committing. A commit git refuses (a pre-commit hook, say)
is a stated refusal: git's own first line and a hint that the files are already
written, then exit 2. Script: `Scripts/Update-Review.ps1`.

### `tkUpdateResume`

```text
tkUpdateResume [-NoPush] [-Preview] [-Help]
```

The same three for `resume/`, and the same exit 2 when the commit is refused.
Script: `Scripts/Update-Resume.ps1`.

### `tkLogPeerReview`

```text
tkLogPeerReview <PullRequestId> [-Title <string>] [-Notes <string>] [-Help]
```

Writes `pr-comments/reviewed-YYYY-MM-DD-PR<id>.md` under the active Space. This is
the half of review work that otherwise leaves no trace in your own record: the
PR carries your comments, and nothing else says you spent the afternoon on it.
The year-end review reads these. A missing id or an unusable prompt store is a
stated refusal (exit 2). Script: `Scripts/Write-PeerReviewLog.ps1` --
a script rather than a function body in `utilities.psm1`, so file writing stays
out of the command table's own file and within reach of the suites.

---

## The routes

Mounted by `agent/growth/__init__.py`'s `growth_router()`, which declares the
gate once on the router rather than repeating it per route -- a route added
later is gated by existing.

| Route | Reads / writes | Serves |
| --- | --- | --- |
| `GET /api/growth` | `growth/current/`, and the active Space's `trainingHoursPerQuarter` | Goals card, and the quarter line |
| `GET /api/growth/{filename}` | one file from `growth/current/` | GoalDetailPage |
| `GET /api/resume` | `resume/resume.md`; answers `content`, `last_modified` and the file's absolute `path` | SkillsPage |
| `GET /api/resume-preview` | `UpdateResume -Preview`, via the bridge | SkillsPage |
| `GET /api/reviews` | `reviews/`, scoped to the active Space | ReviewArchive |
| `GET /api/reviews/{folder}` | one `review.md`; answers `title`, `period`, `content` and the file's absolute `path` | ReviewPage (ADO) |
| `GET /api/review-preview` | `PublishWorkReview -Preview`, via the bridge | ReviewPage (ADO) |
| `POST /api/review/generate` | `NewWorkReview`, via the bridge | ReviewArchive |

All Tier 2 or lower: files on disk, no ADO, no network.

**The gate is 404, not 403, and it is checked per request.** Absent, not
forbidden -- "off means absent" is the rule the whole shell is built on, and a
403 says something different: that the route exists and you may not have it. Per
request rather than at mount time because config is re-read on every request
everywhere else in this agent; gating at import would make this the one flag in
the system that needs a restart, while `/env` -- which the web UI gates on --
would already be reporting the new value.

**Writes go through the bridge.** `POST /review/generate`, `/review-preview` and
`/resume-preview` call `bridge._run` with the function from the CLI's own
command table, parameters as argv. There is no second `pwsh -Command` builder
beside the bridge with its own quoting: a comma-separated slug list needs no
hand-added quotes to survive argv.

**`GET /api/engagement/{slug}/skills` is NOT here.** It counts tags across one
org's `archive/` -- card data -- and it already lives in `agent/ado/reporting.py`.
Moving it would buy a tidier folder and a worse boundary. `SkillsSnapshot`
is this module's component and is its only caller. `_scan_reviews` and the two
slug-set readers are in that file too, for the same reason: the engagement
reporting card was their first caller. `agent/growth/reviews.py` imports them
rather than keeping a second copy.

---

## The web UI

`web/src/modules/growth/index.tsx` exports the module:

```ts
id: "growth", feature: "growth"
routes:  /growth, /growth/goals/:filename, /skills
nav:     Growth   (matches /growth* and /skills)
cards:   none
```

and two components by name, `ReviewArchive` and `SkillsSnapshot`, which the ADO
module's archive-mode home imports (`web/src/modules/ado/index.tsx`). A module
may import another module's card; it may not fork one. They are gated there on
the same flag their routes are, so an install without growth shows the two ADO
cards and nothing breaks.

`api.growth.ts` injects the endpoints into the shell's single slice and adds its
tag types -- `Growth`, `Resume`, `Reviews` -- with `enhanceEndpoints`, so the
shell never learns the names of a module's tags. `growthApi.util.invalidateTags`
is what the refresh buttons dispatch; the shell's `api` object does not know
those tags exist.

`GrowthPage` is `ReviewArchive` + `Goals`, under the quarter line when there is one. The 1:1s are the communication
module's ([`communication.md`](communication.md)).

The deck launcher is on this page too, and `GrowthPage` does not know it: the
page renders `useShellSlot("growth")`, and the **deck** module fills that slot with its launcher
when `features.deck` is on. A presentation is a growth item and a deck is what a presentation
produces, so this is where it belongs -- but growth imports nothing from `modules/deck`, and with
the deck flag off the slot is empty and the page is exactly the two cards above
([`deck.md`](deck.md)).

### The quarter line

A quarterly training requirement is the Space's rule, stated once:

```text
tkConfig -Set spaces.<slug>.features.trainingHoursPerQuarter=8 -Hub     # whole hours; -Local for this machine only
```

Unset (the default) means **no requirement, and nothing is shown**: `GET /api/growth` answers
`trainingQuarter: null`, the page draws no line, and the CLI's inventory (`tkEnv`, `tkMenu -All`) lists the
key as `not configured`. Set, the agent adds up the trainings in `growth/current/` and answers

```json
{ "quarter": "Q3 2026", "hours": 6, "required": 8, "daysLeft": 14, "planned": 4 }
```

and the top of `/growth` reads **"Q3: 6 of 8 hours, two weeks left"** (with `, 4 planned` when there are
planned hours). The rules, one each:

- **The quarter is the calendar quarter of today** (Q1 January to March ... Q4 October to December).
  `daysLeft` runs to its last day.
- **A training counts on its END date** -- `due_date`, which is what `_parse_due_date` already reads out of
  `## Date(s)` (the end of a range) or an explicit `## Due Date`. A training with no date, or `TBA`, is
  **not counted**. The quarter's first and last days are inside it.
- **`hours` are the hours of `complete` trainings** and `planned` the hours of `new` and `active` ones,
  so a person sees what is banked and what is booked. `## Hours` is read for its number (`8`, `2.5`,
  `8 hours`); text with none is no hours. Goals and presentations are not training.
- The key is a positive whole number. Zero, a negative, a string or a flag is no requirement.

The line is plain text, not a tile: the Growth page has no StatTile to share a style with.

**ReviewPage stays an ADO card** (spec D-RP (a)) and reads two of the routes
above. Its header is the goal page's: Back, a `Review` badge, the review's own title (its first H1; the
period if it has none) and `FilePath` with the `path` the route returns. The Pending view keeps its
"Pending Review" title and has no single file, so no path. `SkillsPage` wears the same header with a
`Resume` badge, the title "Resume", `FilePath` and, after it, the last-modified stamp. With growth off they are 404 and the page shows "No reviews yet" without
an error -- verified in a browser, not assumed.

---

## The file shape

[docs/hub/growth.md](../hub/growth.md) is the contract, and it is neither
consumer's source. `tkNewGrowth` is its one writer -- the browser's create runs
the same verb through the bridge -- and writes it UTF-8 with no BOM and LF,
through `Write-CardText -New`, because the file is the record and a person opens
it in an editor. The agent's reader is held to it by `Tests/test_growth.py`.

A change to the shape is a breaking change: the verb, the reader's fixtures and
that document change in the same sitting.

**How an item's status is read** -- from the file's own words, never stored beside it:

| Type | Read from | Rule |
| --- | --- | --- |
| Training | the first line under `## Status` | `Not Started` -> **new**; starts `Complet` or `Achiev` -> **complete**; anything else -> **active** |
| Presentation | `- **Delivered**:` in a section whose heading STARTS WITH `## Outcome` | `Yes` -> **complete**; otherwise **active** |
| Goal | `- **Status**:` in a section whose heading STARTS WITH `## Outcome` | the training's three words |

The heading is matched by how it starts on purpose: files outlive their templates, and a talk written up
from an earlier one heads the section `## Outcome` where today's heads it `## Outcome & Follow-Up`.
Matching the current text exactly read a delivered talk as "Active".
Every
row above is pinned, case by case, in `Tests/test_growth_status.py`; the long version is
[`docs/hub/growth.md`](../hub/growth.md).

---

## Turning it on

```jsonc
// config.local.json -- gitignored, per machine
{
  "promptsRoot": "/path/to/your/hub",
  "features": { "growth": true }
}
```

Then, in a fresh shell:

```powershell
Import-Module ./Prompt20Toolkit/Prompt20Toolkit.psd1 -Force
tkMenu -All          # the five verbs appear under Growth and Reviews
tkNewGrowth -Help
```

and for the web half:

```powershell
tkWeb -Dev           # the agent and the dev server
```

`/growth` lists what is in the hub's `growth/current/`, `/skills` renders
`resume/resume.md`, and the Growth nav entry is there. Switch the flag off and
all three are gone, with no restart of anything but the shell (an open shell keeps its verbs until it re-imports: [Configuration](../CONFIGURATION.md), "A module flag and an open shell").

### Autoload

A module verb **is not in the autoload manifest**, which is generated from the
committed config where every module flag is off, so it resolves after
`Import-Module` rather than in a profile-less shell. A flag set only in
`config.local.json` never reaches the manifest: the alias-discovery shell reads
`Get-P20Features -CommittedOnly`. The whole rule is
[Module verbs and autoload](README.md#module-verbs-and-autoload).

---

## The tests

| Suite | What it guards |
| --- | --- |
| `tkTestToolkit -ModuleCommands` | D-CM end to end: off means absent, the prefix is data, help comes from the module's own file, a colliding name refuses the module whole, a malformed or `[ordered]` data file is skipped by path, `Order` decides registration order, a data file cannot run code, and a locally-enabled module stays out of the autoload manifest |
| `tkTestToolkit -Review` | `Generate-Review.ps1` against a scratch git hub: the bare-date regression, what the scan includes and excludes, the scaffold's sections, multi-org slug sets, edge cases, and the publish preview |
| `pytest Tests/test_growth.py` | the routes against the fixture hub, the 404 gate, and the heading reader: an empty provider is `None`, not the writer's `---`, and a file made from the template reads its comments as nothing |
| `pytest Tests/test_reviews_multi_org.py` | a review folder's membership is split-on-`+` SET membership, not a substring search |
| `npm test -- Goals.create` | the New Growth Item dialog runs `NewGrowth` through the bridge with the dialog's fields as argv, opens the file the verb names, and keeps a refusal or an "Already there" in the dialog |
| `npm test -- registry.growth` | the module contributes routes and nav only when the flag is true, and no home cards of its own |
| `pytest Tests/test_growth_status.py` | the status rules in "The file shape", one row per input the rule distinguishes |
| `npm run smoke` | with everything off, no Growth nav, no growth page, no growth data fetched, no page errors |

Each suite's count is in [Testing](../TESTING.md). Two clauses are worth singling out, because each is a bug that would otherwise
be invisible until it mattered:

- **the bare-date regression.** `git log --after=2026-05-11` means "after
  2026-05-11 at the current wall-clock time", so the same scan returned
  different files in the morning and the evening. The script pins
  `T00:00:00` / `T23:59:59` and the suite asserts it still does.
- **substring membership.** A review folder named `first+second` must surface
  for `first` and `second` and nobody else, and `first` must not drag in
  `firstclass`. A substring implementation passes every happy-path example and
  quietly puts one engagement's review in another's list.

---

## Known gaps

| # | Gap | What you see |
| --- | --- | --- |
| GR4 | The quarter line reads `growth/current/` only, shows the current quarter only, and has no history of the last four quarters | A training moved to `growth/archive/` stops counting toward the quarter it was dated in. Nothing archives a growth item from the UI yet |
| GR3 | `ReviewPage` ownership settled as (a): it stays an ADO card and this module serves its routes | `/review` says "No reviews yet" when growth is off. Not an error, and not a bug |

---

## D-CM: how any module contributes commands

Growth contributes its five verbs the way every module does:
`Config/growth.commands.psd1` is the data file (`Feature = 'growth'`, the
`Commands` rows, `Order`, `Help`), and `Config/growth.commands.ps1` holds one
wrapper per row, in the pattern of the core wrappers in `utilities.psm1`:

```powershell
function global:New-P20GrowthItem {
    [CmdletBinding()]
    param([string]$Title, [switch]$Help)
    $inv = Resolve-InvokedCommand $MyInvocation.InvocationName 'NewGrowth'
    if ($Help) { Show-CommandHelp 'NewGrowth'; return }
    & "$repoRoot/Scripts/New-GrowthItem.ps1" @PSBoundParameters
}
```

`$repoRoot` and `$toolkitRoot` both resolve to the package root; the loader sets
`$repoRoot` before dot-sourcing. `Resolve-InvokedCommand` reads the prefix back
off the alias the user actually typed, so nothing names it. The contract -- the
data file's keys, why it is a plain hashtable, what the loader does and in which
order, and how to add a module -- is
[How a module contributes commands (D-CM)](README.md#how-a-module-contributes-commands-d-cm).

## How a review decides what is in it

**A card is in a review when it was open at some point in the window**: `**Created:**` on or before
the end date, and not `**Closed:**` before the start date. The card's own dates decide, not git: a
commit touching a card is not the same as having worked on it -- a reorganisation, a link refresh or
a stamp backfill touches every card it lands on -- and a hub that is not a git repository has no
commits to read.

| | |
| --- | --- |
| **A stamped file** | judged by its dates. A commit that touched it proves nothing, in either direction |
| **A file with no `**Created:**`** | falls back to git -- "touched in the window" -- so nothing a hub's history could find is lost. `growth/` items and pre-move history at the hub root come this way |
| **Completed or Active** | as of the **end of the window**, not as of today. A card open all through May and archived in June is *active* in a May review, though it sits in `archive/` now |
| **The bullet** | says what happened inside the window: `opened 05-04, closed 05-15`. Nothing, for dates outside it |
| **Dotfiles** | never work items. An editor's stray `.US-316614-....prompt.md` was once listed as completed work |
| **The JSON** | `selected_by_stamps` and `selected_by_git`, counted over the items that are in the review |

Cards written before the stamps existed get them from `Scripts/Backfill-CardStamps.ps1`
([The CLI](../CLI.md#the-two-dates-a-card-carries-and-the-cards-that-never-got-them)), which also
dates the plain `.md` plans and explorations an org's `archive/` holds, since a review lists those
as work too.

The Review suite holds both paths: its unstamped fixture cards go through git, and a stamped hub
runs twice -- as a repository whose history is deliberately misleading, and with no git at all --
with the same bullets word for word.
