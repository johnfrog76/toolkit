# The modules

The Toolkit is a **core that is always on** -- cards, the board, Daily and the Studio -- and **add-ons
beside it** that a machine switches on by configuration: Azure DevOps, and six opt-in modules, **growth**,
**communication**, **organize**, **solitaireAgile**, **deck** and **lounge**. This document is the contract every module
follows: how a module is switched, what "off means absent" covers in all three halves, and how a module
contributes commands (D-CM). Each add-on's end-to-end document is beside this file --
[`ado.md`](ado.md), [`growth.md`](growth.md), [`communication.md`](communication.md),
[`organize.md`](organize.md), [`solitaire-agile.md`](solitaire-agile.md), [`deck.md`](deck.md) and [`lounge.md`](lounge.md), each written to
[stand alone](#what-an-add-ons-document-must-contain) -- and the shapes they write into the hub are
under [`../hub/`](../hub/). The Studio's document, [`studio.md`](studio.md), stays beside them to the same
standard although the Studio is core (D-S13): it has no switch. The root [README](../../README.md) is the map of the other documents.

Growth, communication, organize and Team Agile are both halves: verbs, agent routes and web
pages. **Organize** holds reminders, its first surface, and the Organize tab, where Meetings lives while it
is on. **Team Agile** is a team's rituals with the tracker as the board: the standup, filled from the
Space's GitHub issues, opening on what is waiting on you. Two
modules are web-only -- they add no verbs and no agent routes: **deck**, the Connected Deck engine, a
launcher card on the Growth page and two decks (the Trailer, and Introducing ToolKit, which the
first-run banner on Home offers), and **lounge**, the ambient room. [`deck.md`](deck.md) and
[`lounge.md`](lounge.md) are their short documents.

## What an add-on's document must contain

**Each add-on is documented as if it stood alone.** Someone -- a person, or an agent
with no memory of how this was built -- should be able to open ONE file and work on that add-on: know how
it is switched, what it owns, what it writes, how its state is read, and how to tell it is still right.
These documents are what a new contributor is handed, so a gap in one is a defect, not a nicety.

| Add-on | Its document | The shape of its files |
| --- | --- | --- |
| Azure DevOps | [`ado.md`](ado.md) | what it adds to [a card](../hub/cards.md) |
| Growth | [`growth.md`](growth.md) | [`../hub/growth.md`](../hub/growth.md) |
| Communication | [`communication.md`](communication.md) | [`../hub/manager.md`](../hub/manager.md) |
| Deck | [`deck.md`](deck.md) -- short: it is web-only and points at Connected Deck | none -- it writes nothing to the hub |
| Organize | [`organize.md`](organize.md) -- reminders, its first surface | [`../hub/reminders.md`](../hub/reminders.md) |
| Studio (core, no switch) | [`studio.md`](studio.md) -- the foyer, one row per Space, and the hub's design notes | [`../hub/design.md`](../hub/design.md) |
| Team Agile | [`solitaire-agile.md`](solitaire-agile.md) -- the Ritual Engine's standup, filled from the tracker's worker labels, and triage, answered with `Route` | none of its own; `Route -Assign` writes a card's `**Assigned:**` line ([`../hub/cards.md`](../hub/cards.md)); the ceremonies keep no state |
| Lounge | [`lounge.md`](lounge.md) -- web-only: a tab in the GUI's clothes with two small games, and the Skins dialog that dresses the whole product | none -- it writes nothing to the hub; its state (a Go board, a word ring, the worn skin) is per browser |

The core -- cards, the board, Daily and the Studio -- is not an add-on and has no switch; its data model is
[`../hub/README.md`](../hub/README.md) and [`../hub/cards.md`](../hub/cards.md).

**Every add-on's document answers these, under these headings or their plain equivalents, in this order:**

1. **The switch, and its scope** -- the key, which file it lives in, whose it is (the engineer's, or one
   org's), and what it is when nobody has set it.
2. **What it owns** -- in each half, and what sits beside it that it does NOT own. Folder names lie
   (`agent/ado/` holds the card core); this section is where that is said.
3. **Turning it on** -- the exact lines, and how to check it worked.
4. **The verbs** -- each one, what it does, and whether it touches a file.
5. **The routes** -- each one, its gate, what it reads and what it writes.
6. **The web UI** -- pages, cards, nav, and what is absent when the add-on is off.
7. **The file shape** -- what it writes into the hub, or a link to the `docs/hub/` document that owns it;
   and **how status is read from the file**, rule by rule, because that is what regresses.
8. **The tests** -- which suite holds which promise, and what no suite can (the manual runbook).
9. **Known gaps** -- this add-on's, each with its issue.

A document may end with an optional **History** section after the nine: a few dated bullets for the
changes a maintainer needs to know about (a rename, a rule people's files were written against). The
body stays in the present tense.

It may link out for depth -- the CLI reference for a switch, the spec for a decision -- but a reader must
never NEED the link to know what the add-on is, what it touches and how to verify it. When an add-on
changes, its document changes in the same commit (AGENTS.md, "Documentation is part of the change").

The model, in plain words. A module is:

| | One of these | Read by |
| --- | --- | --- |
| one **flag** | a key in the top-level `features` block | `Get-P20Features` (CLI), `effective_features` (agent), `/env`'s `features` map (web UI) |
| one **command file** | `Config/<module>.commands.psd1` plus a sibling `.ps1` of wrappers | the loader in `utilities.psm1`, before `Register-PromptAlias` |
| one **router** | a package under `agent/<module>/` exporting one `APIRouter` | `agent/app.py`, which mounts it |
| one **registry export** | one `ToolkitModule` object | `web/src/shell/registry.ts` |

**Off means absent.** With the flag off there is no verb, no line in `tkMenu`, no `-Help`, no entry
in the bridge's command table, no agent route, no nav entry, no page, no card, and nothing asks the
agent for the module's data. It is not hidden, not disabled, and **not a 403** -- a 403 would say
the route exists and you may not have it. With the flags off, `/api/growth`, `/api/manager`,
`/api/resume`, `/api/reviews`, `/api/review-preview`, `/api/resume-preview`, `/api/reminders`,
`POST /api/comms/send` and `POST /api/rewrite` all return **404**; `tkMenu -All` names none of the
module verbs among its commands; and `npm run smoke` checks "no Growth nav entry", "no Meetings nav
entry", "no growth data was requested" and "no 1:1 data was requested". The other half is
`npm run smoke -- --modules=on`, against an agent started with the flags on.
[Testing](../TESTING.md) has the runners and their counts.

**The gate is checked per request, not at mount time.** Config is re-read on every request
everywhere else in this agent, so gating at import would make a module flag the one thing in the
system that needs a restart -- while `/env`, which the web UI gates on, would already be reporting
the new value. Flip a flag in another terminal and the next fetch has it -- the agent's and the web UI's;
a shell that is already open keeps the verbs it registered at import
([Configuration](../CONFIGURATION.md), "A module flag and an open shell").

**And absent means no bytes**. `web/src/shell/registry.ts` imports each
module's DESCRIPTOR statically -- `index.tsx`, which names the flag and the route paths and imports no
component -- and every page, card and header item an opt-in module contributes is a `lazyPart`
(`web/src/shell/lazy.tsx`): a dynamic import Vite splits into its own chunk, fetched when first drawn.
A module you add follows the same shape: keep `index.tsx` to the descriptor, wrap each part in
`lazyPart(() => import("./Part"), (m) => m.Part)`, and `lazyModules.test.ts` will tell you if a static
component import creeps back in. The smoke test's off mode asserts that no module source was requested.

**The flag is the engineer's.** `features.growth` and `features.communication` live in the
**top-level** `features` block of `config.default.json` or `config.local.json` -- never inside an
`spaces[]` entry -- and an org cannot override them. A training you took does not stop having
happened when you switch org, and a 1:1 history spans engagements, so a module that flickered as
you moved between an active engagement and an archived one would be wrong. The exceptions are the
ADO core's own flags, which describe one org's board: `sprintAwareness` is the only one. The
rule, and where each half reads it, is
[Flags have a scope](../ARCHITECTURE.md#the-shell-owns-the-chrome-a-module-owns-the-rest) in [the web UI overview](../ARCHITECTURE.md#the-web-ui);
`Tests/test_features.py` pins it.

Turning one on, on this machine:

```jsonc
// config.local.json at the repo root -- gitignored, per machine
{
  "promptsRoot": "/path/to/your/hub",
  "features": { "growth": true, "communication": true }
}
```

```powershell
pwsh -NoProfile -Command "Import-Module ./Prompt20Toolkit/Prompt20Toolkit.psd1 -Force; tkMenu -All"
```

## Growth

Professional development and the career record it feeds: trainings, presentations and goals, the
generated work reviews, and the resume.

| | |
| --- | --- |
| Flag | `features.growth` -- top-level, engineer-scoped |
| Verbs | `NewGrowth`, `NewWorkReview`, `PublishWorkReview`, `WorkReview`, `LogPeerReview`, `UpdateResume`. Each answers `-Help`; flags are in [the command reference](../CLI.md#the-opt-in-modules-verbs) |
| Agent | `agent/growth/` -- `growth.py`, `reviews.py`, `resume.py`, behind one gated router |
| Web UI | `web/src/modules/growth/index.tsx`, export `growthModule` |
| Hub folders | `growth/current/`, `growth/archive/`, `reviews/<slug-set>/<year>/<start>_<end>/review.md`, `resume/resume.md` -- and [`docs/hub/growth.md`](../hub/growth.md) is the file-shape contract both the CLI and the agent are held to |
| Everything else | [`docs/modules/growth.md`](growth.md) |

Its three folders are **hub-root siblings** of the per-org folders, not children of one, for the
same reason the flag is the engineer's -- resolved through the same `PROMPTS_ROOT`-first rule every
module follows (`Get-P20PromptsRoot` / `hub_root()`). The one thing it writes that **is**
org-scoped is `LogPeerReview`'s output, in the active Space's `pr-comments/`. Its nine routes are all
Tier 2 or lower and all 404 with the flag off; two of them (`GET /api/reviews/{folder}`,
`GET /api/review-preview`) are read by `ReviewPage`, which **stays an ADO card** (decision D-RP
(a)) rather than moving here. [`docs/modules/growth.md`](growth.md) has the routes table, the pages,
the fixtures and the D-CM registration in full.

## Communication

Manager 1:1s and the Teams engine. Unusual among the modules in that most of it is not a design
exercise: the engine is carried whole from the predecessor, where it ran in production, with its
tests. The module decides where it surfaces and what gates it.

| | |
| --- | --- |
| Flag | `features.communication` -- top-level, engineer-scoped |
| Verbs | `SendTeams`, `NewMeeting`, `MeetingAgenda`. Each answers `-Help`; flags are in [the command reference](../CLI.md#the-opt-in-modules-verbs) |
| Agent | `agent/communication/` -- `manager.py` (the routes) and `comms.py` (the engine, carried whole with its 21 tests) |
| Web UI | `web/src/modules/communication/index.tsx`, export `communicationModule` |
| Hub folder | `manager/current/` and `manager/archive/`, a hub-root sibling -- [`docs/hub/manager.md`](../hub/manager.md) is the session-file contract |
| Everything else | [`docs/modules/communication.md`](communication.md) |

**Two gates, and they are not the same thing.** Gate 1 is `features.communication`: off means 404,
no alias, no route, no nav. Gate 2 is the recipient's webhook variable, in the environment, checked
independently at send time -- off there looks like a **visible, disabled** send button naming the
variable, never a failure (`SendTeams` exits 0 and says which variable to set). A person with the
flag on and no webhook sees every page and writes notes perfectly well; only the send degrades. The
webhook URL itself is never in config -- config names the variable, the environment holds the URL.

> **`POST /api/comms/send` and `SendTeams` post for real.** Exercise the path with `-WhatIf` or
> `"dryRun": true`: every gate runs and the payload comes back unsent (AGENTS.md, "The webhook
> variables"). Two of the module's six routes -- `POST`/`PUT /manager` -- are the only writes in the
> whole API that do not go through the CLI, because they save a form someone is typing into;
> [`docs/modules/communication.md`](communication.md#the-backend) says why that is not a second
> implementation to drift from, and has the full route and page tables, the `/env` shape, and the
> fixtures.

## Organize

Where the things a person keeps in order live; reminders is its first surface. Both halves or neither.

| | |
| --- | --- |
| Flag | `features.organize` -- top-level, engineer-scoped |
| Verbs | `NewReminder`, `Reminders` (`-Snooze`, `-Due`, `-NoDue`, `-Title`, `-Source`, `-Ref`, `-Archive`, `-All`). Each answers `-Help`; flags are in [the command reference](../CLI.md#the-opt-in-modules-verbs) |
| Agent | `agent/organize/` -- `reminders.py`, one gated router, `GET /api/reminders`, **reads only** |
| Web UI | `web/src/modules/organize/index.tsx`, export `organizeModule` -- the `Organize` tab at `/organize`: the Meetings card through the `organize` slot when communication is on, then the Reminders card |
| Hub folder | `reminders/current/` and `reminders/archive/`, a hub-root sibling -- [`docs/hub/reminders.md`](../hub/reminders.md) is the file contract |
| Everything else | [`docs/modules/organize.md`](organize.md) |

Every write -- snooze, done, the quick add -- is one of the two verbs through `POST /api/cmd/{name}`.

## Studio -- core, not a module

The studio developer's view across their products. **It is part of the
core, from the first run** (D-S13), so it is NOT a module: no flag, no D-CM data file, no row in the
inventory. It is listed here because it was one until 2026-10-04 and a reader looks for it beside the
others. The foyer is one row per Space -- every Space, whatever its tracker -- and never a merged backlog
(D-G11, D-S2).

| | |
| --- | --- |
| Flag | none. A `features.studio` left in `config.local.json` is ignored; `Config -Set features.studio=...` is refused, exit 2, "The Studio is part of the core and has no switch" |
| Verbs | `NewDesign`, `StampDesign`, `MoveDesign`, `NewSpace`, `RetireSpace`, `RemoveSpace` and `HowWeWork` -- core verbs in `config.default.json` `commands`, wrappers in `utilities.psm1`, in the autoload manifest. Flags are in [the command reference](../CLI.md#the-studio-spaces-and-design-notes). Promote is the core `NewItem -FromDesign <note>` |
| Agent | `agent/studio/` -- `notes.py` and `spaces.py`, one router mounted with no gate, `GET /api/studio/design` (the hub's four folders grouped by id and state, L2) and `/api/studio/design/{path}`, and `GET /api/spaces/candidates` (the + dialog's picker: `NewSpace -Discover -AsJson` through the bridge), **reads only**. The foyer reads `GET /api/issue-report` and `GET /api/deploys` (which take a `space` argument for it) and `GET /api/status` |
| Web UI | `web/src/modules/studio/index.tsx`, export `studioModule`, no `feature` -- the `Studio` tab at `/studio`, after Growth's and Organize's places and before Team Agile's and the Lounge's: the foyer, then the Designs. Its pages are still lazy parts |
| Hub folder | `design/` and `spec/`, hub-root siblings, each with an `archive/` -- the same four folders a product's repo keeps (design lifecycle L2, D-DL12); [`docs/hub/design.md`](../hub/design.md) is the file contract and the state rule. A hub with none is told so, not refused. And in a Space's own folder, `agentic/how-we-work.md`, which `HowWeWork` writes once for a Space worked with agents ([the hub's map](../hub/README.md#how-we-work----a-spaces-agentic)) |
| Everything else | [`docs/modules/studio.md`](studio.md) |

A row is the switch into its Space, the same one the avatar menu makes.

## Team Agile

A team's own rituals, with the real tracker as the board and a cast that is not people
(M0). Its first ritual is the standup: what is waiting on you,
then one block per worker label. Its second is triage (V1): the open issues by milestone, and
`Route`, its one write -- a label, an assignee or a milestone on the tracker through `gh`, or who takes a
card with no issue behind it, as that card's one `**Assigned:**` line. Both halves or neither; it keeps
no file of its own in the hub.

| | |
| --- | --- |
| Flag | `features.solitaireAgile` -- top-level, engineer-scoped; on only where the Space you are in answers `agents` to "How do you want to work in \<Space>?" (`spaces[].howIWork` -- asked on a GitHub Space, derived elsewhere) |
| Verbs | `Standup` (`-Space`, `-AsJson`); `Triage` (`-Space`, `-AsJson`), the open issues by milestone; `Route` (`-Size`, `-Assign`, `-Milestone`, `-Severity`, `-DeepWater`, `-Space`, `-WhatIf`), the module's one write -- labels, an assignee and a milestone on the tracker, or a card's `**Assigned:**` line; `StartWork <id>` (`-Clip`, `-Prompt`, `-Space`, `-Launch`, `-WhatIf`), the hand-off block a cold agent starts from, writing nothing -- or, with `-Launch`, handed to a session in a new worktree of the Space's repository. Each answers `-Help`; flags are in [the command reference](../CLI.md#the-opt-in-modules-verbs) |
| Agent | `agent/solitaire/` -- `standup.py`, `triage.py` and `milestones.py`, one gated router, `GET /api/ritual/standup`, `GET /api/ritual/triage` and `GET /api/ritual/milestones`, **reads only**; `Route` runs through the bridge |
| Web UI | `web/src/modules/solitaireAgile/` -- the Team Agile tab, after the Studio's and before the Lounge's: the standup's text, its issue numbers linked; each list row's **Start work** opens the hand-off block in a copy box, through `POST /api/cmd/StartWork` |
| Data | `Config/ceremonies.json` and `Config/standup-vocabulary.json`, read by both halves; `consts.json` `rituals` |
| Everything else | [`docs/modules/solitaire-agile.md`](solitaire-agile.md) |

The worker is the tracker's own label -- its description says `Routed to <Name> -- ...` -- never a list in
code; the human's queue is every open issue labelled `verify-close`.

## How a module contributes commands (D-CM)

This is the reference description, and it is the same for every module that is not the ADO core.

**Two files, in `Config/`.** `<module>.commands.psd1` is a PowerShell **data** file with four keys:

```powershell
@{
    Feature  = 'growth'                         # the TOP-LEVEL features key
    Commands = @{ 'NewGrowth' = 'New-P20GrowthItem' }   # CommandMap rows: name -> FUNCTION
    Order    = @('NewGrowth')                   # optional: menu / registration order
    Help     = @{ 'NewGrowth' = @{ category = 'growth'; description = '...'
                                   usage = '{cliPrefix}NewGrowth -Title <t> ...'
                                   examples = @('{cliPrefix}NewGrowth -Title ''Intro'' -Hours 2') } }
}
```

`Commands` is a **plain hashtable, with no `[ordered]` cast**, and that is the point rather than a
limitation. The loader reads the file with `Import-PowerShellDataFile` **and nothing else**, which
will not evaluate an expression -- a cast included -- to build a data file. A file any module can
drop into `Config/` must not be able to run code when the CLI starts. A hashtable has no order, so
`Order` carries the one thing the cast was there for: names left out of it follow the listed ones,
and a name in `Order` that is not in `Commands` is a warning naming it and nothing else.

The values are **functions, never prefixed aliases** -- the prefix is data and more than one can be
registered at once. `Help` has exactly the shape `config.default.json`'s `commands.<Name>` entries
use, and it is merged into the in-memory table `Show-CommandHelp` reads, so **a module's help never
touches `config.default.json`**, which stays the ADO core's. `{cliPrefix}` is expanded at render
time, so the same entry reads correctly under any prefix and under two at once.

A help entry has five keys, and the last two are optional: `category`, `description`, `usage`,
`examples`, plus **`switches`** (a map of switch name to one line) and **`notes`** (free text under
the examples). `Web` and `Agent` carry both, because they are the verbs with real switch surface, and
a script's comment-based help is not where `-Help` looks.
Two more tokens are expanded alongside `{cliPrefix}`: **`{agentPort}`** and **`{devPort}`**, read
from `web.agentPort` and `web/vite.config.ts`, so a URL in a help line is right on a machine that
moved the port. The `Menu` suite asserts that every switch the script declares is described, that
nothing is described that it does not declare, and that `docs/CLI.md`'s row for the verb names the
same switches.

`<module>.commands.ps1` is the sibling: one `global:` wrapper function per row, the same pattern as
the core wrappers in `utilities.psm1` -- resolve the invoked name, answer `-Help`, splat
`@PSBoundParameters` at the script in `Scripts/`. The loader sets `$repoRoot` before dot-sourcing it.

**What the loader does**, in `utilities.psm1`, **before `Register-PromptAlias`**, for each
`Config/*.commands.psd1` in name order:

1. read it with `Import-PowerShellDataFile`. Unreadable, or missing `Feature` or `Commands`: warn
   **with the path** and skip the module;
2. if `(Get-P20Features).<Feature>` is not `$true`: do nothing at all -- no row, no alias, no help,
   no menu line;
3. if any name in `Commands` is already in `$script:ModuleState.CommandMap`: warn with the colliding name and
   skip **the whole module**. A core command is never overwritten, and a half-merged module is worse
   than an unloaded one;
4. if the sibling `.ps1` is missing: warn and skip;
5. dot-source the `.ps1`, append the rows to `$script:ModuleState.CommandMap` in `Order`, and merge `Help` into
   the in-memory table.

A wrapper in the `.ps1` is a `function global:` body, so it finds the package root with
`(Get-P20ModuleState).PackageRoot` read inside the function (or from its own `$PSScriptRoot`, as
the other modules' files do), never from a free name the loader set: reached from a script the
module launched, a free name resolves against that script (AGENTS.md, "Traps worth knowing").

Running before `Register-PromptAlias` is the whole point: the aliases are generated from the table,
so a module verb gets its prefixed alias, its menu line and its **bridge entry** for free.
`Get-P20CommandMap` reads the same table at call time and the agent's `POST /api/cmd/{name}` derives
its allowlist from that and nothing else -- so a module verb is callable from the browser with no
backend change. `Get-P20ModuleCommands` reports which modules contributed what, as JSON; with
growth and communication on it answers
`{"communication":["SendTeams","NewMeeting","MeetingAgenda"],"growth":["NewGrowth","NewWorkReview","PublishWorkReview","LogPeerReview","UpdateResume"]}`.
Its two readers are the `ModuleCommands` suite and `Test-Menu`'s
orphan check, which compares registered aliases against `config.default.json` and would otherwise
flag every module verb as an orphan on a machine that has a module switched on.

**Adding a module** is four steps, and none of them is an edit to `utilities.psm1`, the bridge, or
`config.default.json`'s `commands` block: write the two `Config/` files, put the scripts in
`Scripts/`, and set `features.<name>` -- in `config.local.json` to try it, in `config.default.json`
to ship it on.

### Module verbs and autoload

**A module verb is not in the autoload manifest.** `Prompt20Toolkit/Prompt20Toolkit.psd1` is
committed and shared between machines, and it is generated from the **committed** config, where
every module flag is off, so none of the module verbs appears in it. A module verb therefore
resolves after `Import-Module`, not in a profile-less shell -- unless a fork turns the flag on in
`config.default.json` itself, which is the statement that the verb belongs on every machine, and
then it is in the manifest as soon as the manifest is regenerated.

A flag set only in one machine's `config.local.json` must **never** reach that file, or the drift
check goes red on whichever machine did not last run the generator. Personal nav aliases carry the
same hazard and share the fix: the alias-discovery shell sets `PROMPTS_TOOLKIT_NO_NAV_ALIASES=1`, and
the loader reads `Get-P20Features -CommittedOnly` when it sees it. With `features.growth` true in
`config.local.json`, regenerating the manifest produces a byte-identical file, and `Test-Autoload`
passes either way.
