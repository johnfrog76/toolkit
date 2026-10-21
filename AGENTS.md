# Working ADO cards with ToolKit — agent guide

<!--
  SOURCE OF TRUTH. Provider-neutral on purpose.

  This file is the knowledge an agent needs before touching this system. It is
  plain Markdown with no vendor frontmatter so it can be read by any assistant,
  or by a person.

  Provider-specific adapters are GENERATED from this file by
  Scripts/Update-AgentDocs.ps1 -- do not edit them by hand. They are per
  machine and not committed, so no repo test can see one go stale: Update and
  Setup run the generator's -Check, which compares EVERY copy on its own, and
  say so. The Portability suite holds the generator itself.

  Adapters:
    .claude/skills/toolkit-ado/SKILL.md   Claude Code / Claude Agent SDK
                                          (in the checkout AND in ~/.claude)
    .github/copilot-instructions.md       GitHub Copilot
    .cursor/rules/toolkit-ado.mdc         Cursor

  ONE LINE SUMMARY (used as the adapter description, keep it matchable):
  Working an Azure DevOps card end to end with the ToolKit CLI (tk* commands) - scaffolding a prompt file from a work item, threading commits, opening a PR, handling review comments, archiving, and closing. Use whenever the task involves an ADO work item, a prompt file under current/ or archive/, a tk* command, or a PR against an ADO repo.
-->

<!-- markdownlint-disable-next-line MD025 -- the first line is the file's title; this one is the title the generated adapters carry -->
# Working ADO cards with ToolKit

ToolKit is a PowerShell CLI. Commands are `{prefix}{Command}` and the prefix is configurable —
it is `tk` by default. Run `tkMenu` to see the live surface, and `<command> -Help` for any one.

**Commands auto-load.** There is no `Import-Module` step. If a `tk*` command is not recognised,
the fix is `tkInstallAutoload -Force`, not an import line.

## Three halves, and which one you are in

The repo holds three things that share one config and one prompt store:

| Half | What it is | Gate |
| --- | --- | --- |
| **The CLI** | PowerShell, the `tk*` verbs. The whole workflow; nothing else has to be running. | Tier — it degrades rather than failing. See "When ADO is not reachable" |
| **The agent** | FastAPI (`agent/`, port `web.agentPort`). Read routes over the same store, plus the bridge. Start it with `tkAgent`, or both halves with `tkWeb -Dev`. | Per route: tier, a `features.*` flag, or a model key. `GET /api/env` reports all three |
| **The web UI** | React (`web/`, `npm run dev`). A shell that mounts modules. | `features.*` per module, read from `/env`. Off means absent — no route, no nav entry, no card, no data |

The dependency runs one way: the web UI reads through the agent, the agent reads the same config and
store the CLI does, and **nothing in the web half changes a card except through the CLI**, via
`POST /api/cmd/{name}`. That bridge runs the verb in a child `pwsh`, and what it may run is the
CLI's own command table -- so a verb you add is callable from the browser with no backend change,
and one that is not in the table is refused with `status: rejected` rather than reimplemented.

**One toolkit per shell.** The verbs are global aliases, so two checkouts imported into one session
means whichever registered last owns the name. Any run that has to be about a particular tree starts
a fresh shell, limits `PSModulePath` to that package, and imports exactly one manifest by path:

```powershell
pwsh -NoProfile -Command "`$env:PSModulePath = (Resolve-Path .); Import-Module ./Prompt20Toolkit/Prompt20Toolkit.psd1 -Force; tkStatus"
```

**`-NoProfile` is not isolation.** Auto-loading reads `$env:PSModulePath`, not the profile, so a
shim installed on the machine still answers for a name this checkout never defined -- and setting
the variable in the *parent* shell does not help, because pwsh puts the user and system module
paths back at startup. It has to be set inside the shell that runs the command. `Test-ExitCodes`
does exactly this for every child process it spawns; without it, a suite can be green by
exercising a different product.

## Three modules, and how they are switched

Crossing the three halves is a second division: an **ADO core that is always on**, and two **opt-in
modules** beside it -- **growth** (trainings, presentations, goals, work reviews, the resume) and
**communication** (manager 1:1s and the Teams engine) -- and **organize**
(reminders, its first surface; `docs/modules/organize.md`), which is both halves like those two. A
further one, **deck**, is **web-only**: a
presentation engine with a launcher card under Growth, with no verbs and no agent
routes -- so "all three halves at once" below is one half for that module. `docs/modules/deck.md`.
A second web-only module, **lounge**, is the ambient room -- the zen temple scene, the
room that asks nothing, nav entry deliberately last; `docs/modules/lounge.md`. **The Studio** is the view across a studio developer's
products -- the foyer, one row per Space, its tab before Team Agile's and the Lounge's -- and it is
**core, not a module** (D-S13): no `features.studio` (a leftover line is ignored, `Config -Set` of it
is refused), its verbs `NewDesign`, `StampDesign`, `MoveDesign`, `NewSpace`, `RetireSpace` and `RemoveSpace` in `config.default.json` `commands` and the
autoload manifest, its agent routes ungated, its web descriptor with no `feature` (its pages still lazy);
`docs/modules/studio.md`. **solitaireAgile** (Team Agile in the web UI) is a
team's rituals with the tracker as the board -- the standup, `Standup` and its route, both halves,
writing nothing; triage -- `Triage`, `GET /api/ritual/triage` and a Triage page; and `Route`, its one write, a real label, assignee or milestone on the tracker through `gh`, and on a card one `**Assigned:**` line; and `StartWork`, the hand-off block a cold agent starts from, which the Team Agile page copies through the bridge; `docs/modules/solitaire-agile.md`.

One flag switches a whole module, in all three halves at once:

```jsonc
// config.local.json -- gitignored, per machine. TOP-LEVEL, never inside a spaces[] entry.
{ "features": { "growth": true, "communication": true } }
```

**A feature flag has a scope, and the default scope is the engineer.** A training you took does not
stop having happened when you switch org, so these hold steady across `activeSpace` and an org cannot
override them. There are two Space-scoped switches. `sprintAwareness`, the ADO core's own flag, describes
one org's board and is read from `spaces[].features` (the older `orgs[]` is still read). And
`spaces[].howIWork` is the Space's answer to "How do you want to work in `<Space>`?" -- asked on a
GitHub Space, derived elsewhere (`team` on Azure DevOps, `alone` with no tracker) -- and it gates one
module: Team Agile is on only where `features.solitaireAgile` is on AND the answer is `agents`, applied once
where the flags are resolved (`Scripts/Resolve-HowIWork.ps1`, `how_i_work()`, one shared table).

**Off means absent.** No verb, no line in `Menu`, no `-Help`, nothing for the bridge to call, no
agent route (**404, not 403**), no nav entry, no page, no card, and nothing fetches the module's
data, **and no bytes**: the web registry imports each module's DESCRIPTOR
statically -- `index.tsx`, small, no component in it -- because it has to read the flag and the route
paths to decide what mounts, and every page, card and header item an opt-in module contributes is a
`lazyPart` (`web/src/shell/lazy.tsx`), a chunk fetched when first drawn. `lazyModules.test.ts` reads
each descriptor's source and refuses a static component import; the smoke's off mode asserts that no
module source was requested. Not hidden, not disabled, not forbidden. One thing that looks like an
exception and is not: the gate is checked **per request**, so flipping a flag in another terminal
needs no restart **of the agent or the web UI**; a shell that is already open keeps the verbs it
registered at import (`docs/CONFIGURATION.md`, "A module flag and an open shell").

The fourteen verbs the modules contribute: `NewGrowth`, `NewWorkReview`, `PublishWorkReview`,
`LogPeerReview`, `UpdateResume` (growth); `SendTeams`, `NewMeeting`, `MeetingAgenda`
(communication); `NewReminder`, `Reminders` (organize); `Standup`, `Triage`, `Route`, `StartWork` (solitaireAgile).
(`NewDesign`, `StampDesign`, `MoveDesign`, `NewSpace`, `RetireSpace` and `RemoveSpace` are the Studio's, and core.) **A module closes its own data.** `Archive` is org-scoped and cannot see a hub-root
sibling like `manager/` or `growth/`, and the answer is not to teach it: it is
`MeetingAgenda -Close`, which moves the session to `manager/archive/` and stamps `**Closed:**` from
the one shared writer, `Scripts/Add-ClosedStamp.ps1` (whose bytes come from
`Scripts/Write-CardText.ps1`, which the session writers use directly). Growth gets the same treatment from its own
side when it needs it. They are **not in the autoload manifest** -- it is generated from the committed
config, where every module flag is off -- so they resolve after `Import-Module`, not in a
profile-less shell. `docs/modules/README.md` is the long version; each module's own end-to-end
document is `docs/modules/<module>.md`.

### The D-CM contract, in three lines

- A module contributes verbs through `Config/<module>.commands.psd1` -- `Feature`, `Commands`
  (a **plain hashtable**, name -> function), optional `Order`, and `Help` in `config.default.json`'s
  `commands.<Name>` shape -- plus a sibling `.ps1` holding one wrapper per row.
- The loader in `utilities.psm1` reads it with **`Import-PowerShellDataFile` and nothing else**, so a
  data file can never run code; it runs **before `Register-PromptAlias`**, so a module verb gets its
  alias, menu line, `-Help` and bridge entry for free.
- A name that collides with an existing command refuses **the whole module**, with the colliding name
  in the warning; a malformed or unreadable file is skipped with its **path** in the warning.

The full contract, including what to do when you add a module, is `docs/modules/README.md`, "How a
module contributes commands (D-CM)".

### Every module registry test mocks every module

`registry.test.tsx`, `registry.growth.test.tsx`, `registry.communication.test.tsx`,
`registry.organize.test.tsx`, `registry.studio.test.tsx` and `registry.lounge.test.tsx` each `jest.mock()` **every** module, including the one under test's siblings. A registry test is
about the registry's filtering, so a stand-in is the right subject -- and the practical reason is
sharp: leaving a sibling's real tree to load pulls in `react-markdown`, which is ESM and which
ts-jest takes only through the `transformIgnorePatterns` allow-list in `web/jest.config.mjs` -- there for
the one suite that renders it for real, `markdownPlugins.test.tsx`, and slow to transform. (React Router 8, ESM only as well, is on the same list; every
suite that routes loads it.) Add a
module and you add a mock line to every one of these files.

### The webhook variables

> **Never send a Teams message from a session.** `SendTeams` and `POST /api/comms/send` post to a
> **real** webhook -- the engine takes whatever is in the environment variable at face value. Use
> `-WhatIf` (or `"dryRun": true` on the body): every gate runs, the markdown is formatted, and the
> payload comes back unsent. A machine that has done this work before may well have a live
> `TEAMS_WEBHOOK_MANAGER` or `TEAMS_WEBHOOK_DEMO_CHANNEL` already exported, so an accidental send is
> one missing flag away. `unset` them in any shell you start for this work. The test runners do it
> for themselves: every `TEAMS_WEBHOOK_*` is removed by pattern for the run and put back after, and
> the run marker (`consts.json` `env.testRunMarker`) makes the engine's POST and `SendTeams` refuse
> while a suite runs -- in the runner's own process tree only, so your shell can still send.

**Four test runners**, one per half plus one for the two together. Run the ones your change touches:

```powershell
tkTestToolkit                 # the CLI -- 44 suites, 7532 assertions on this commit
```

```bash
python3 -m pytest Tests/      # the agent (Windows: python or py -3 -- python3 is the Store stub there)
cd web && npm test            # the shell
cd web && npm run smoke       # both, in a browser -- needs the agent and the dev server up
```

`tkWeb -Dev` is what brings those last two servers up, and `tkWeb -Stop` ends them.

A skip is not a pass. Read the summary line, not the total.

## Opt in by configuration

The shape of the whole product, in three lines:

- **Core workflow always shows.** The ADO core has no flag and never had one; nor, by D-S13,
  does the Studio.
- **Add-ons only by configuration.** Everything else -- the modules, the shortcuts, the model keys,
  the webhooks -- is off until a file or an environment variable says otherwise.
- **The nav category shows its title**, with `not configured` under it when empty.

And one rule the three lines imply: **an opt-in surface is NAMED by the CLI whether or not it is
on.** A machine has to be able to tell you what it is not doing; a feature nobody can see is
indistinguishable from a feature that was never built -- a shipped shortcut nobody has configured
reads as missing. The inventory lives in exactly one place, `Scripts/Get-OptionalSurfaces.ps1`, and the
renderers read it: `{prefix}Menu -All` ends with it, `{prefix}Env` has an "Optional surfaces" block,
and `{prefix}Setup` points at `{prefix}Env`. Three states, and the last two are not the same thing:
`on`, `off` (a default answered, and the answer was no), `not configured` (nothing has been set
anywhere).

| Surface | Key | Where that key lives |
| --- | --- | --- |
| Navigation shortcuts | `aliases.<Name>.path` | `config.local.json` -- `Config -Set aliases.Home.path=<path>` |
| Azure DevOps | `features.ado`, else the active Space's `status` and its tracker | DERIVED (`Scripts/Test-AdoEnabled.ps1`): unset, it follows the org you are in -- on in an `active` org whose address is Azure DevOps (`Scripts/Resolve-Tracker.ps1`), off in a `local` one, and off on a connected GitHub Space, where the row says `<slug>'s tracker is GitHub`. It decides what is SHOWN (Setup's checks, the inventory); nothing is unregistered, and `Menu`'s tracker rows stay on a connected GitHub Space because they answer through `gh`. `docs/modules/ado.md`, "The switch, and its scope" |
| GitHub issues | `tracker.github` | DERIVED: `on` once a Space whose address is `github.com` is `active`, else `not configured`. The address is a Space's, written by `Connect <slug>` (`hub.json`); the shipped GitHub demo has one and is `local` until connected |
| growth module | `features.growth` | `config.local.json`, top-level |
| communication module | `features.communication` | `config.local.json`, top-level |
| deck module | `features.deck` | `config.local.json`, top-level -- web UI only, it adds no verbs |
| lounge module | `features.lounge` | `config.local.json`, top-level -- web UI only, the ambient room; while NOT CONFIGURED, Home's foot carries its discovery tip |
| organize module | `features.organize` | `config.local.json`, top-level -- both halves: `NewReminder`, `Reminders` and the Organize tab |
| Team Agile module | `features.solitaireAgile`, and the Space's `howIWork` | the switch in `config.local.json`, top-level; the answer in `hub.json` -- on only where both say so: `on`, `off` (derived or chosen) or `not configured` (a GitHub Space nobody has answered). Both halves: `Standup`, `Triage`, `Route` and `StartWork`, `GET /api/ritual/standup` and `/triage`, and its tab; writes only what `Route` writes -- a label, an assignee or a milestone on the tracker, and on a card one `**Assigned:**` line |
| Design lifecycle | `design` | DERIVED (`Scripts/Read-DesignTree.ps1`, through `Get-OptionalSurfaces.ps1`): `on` when the repository you stand in has `design/` and every file in the four folders carries an `id:`, `off` with the count when some do not, `not configured` with no `design/` to read, or none with a note in it; the hub's own count in the note. `docs/hub/design.md`, "The CLI names it" |
| Sprint awareness | `spaces[].features.sprintAwareness` | `hub.json` -- a Space-scoped flag (the other Space-scoped switch is `howIWork`, above) |
| Prompt store git sync | `storeSync` | `hub.json`, overridable per machine |
| ADO identity | `email` | `config.local.json`, else `az login` |
| Web UI and agent | `web.agentPort` | `config.local.json`; started with `{prefix}Web -Dev` |
| AI code review | `ANTHROPIC_API_KEY` | the environment -- a secret never goes in a file this tool writes |
| Teams delivery | `TEAMS_WEBHOOK_<RECIPIENT>` | the environment, gate 2 of a send |

**This refines "off means absent", it does not contradict it.** The two rules answer different
questions, and the boundary is exact:

- **The menu's category rows, the verbs, `-Help`, the bridge table, the agent routes, the web nav,
  pages, cards and data** are the surface you can USE. A module that is off is absent from every one
  of them -- no row among the commands, no alias, 404 rather than 403. That holds, and 59
  assertions plus a browser smoke test hold it.
- **The inventory** -- the `Opt in by configuration` block at the foot of `Menu -All`, and `Env`'s
  block -- is what EXISTS. A module that is off appears there, as its title and
  `off (Config -Set features.growth=true)`, and nowhere else.

So: naming a surface is not mounting it. If you are adding a gate, add its row to
`Get-OptionalSurfaces.ps1` in the same commit, **and its question to `Config/settings-workflows.json`**
(settings by workflow: every row carries the question it answers, printed first by
`Env` and `Menu -All`, drawn as the drawer's "How do I…" section and the tips on Home; `-Environment`
and `Tests/test_surfaces.py` fail naming the key when a row has no entry or an entry no row), and
where a command refuses for a missing optional setting, the hint names the key and the file the way
`SendTeams`'s gate 2 does.

**One inventory means one resolver, reached the same way from both renderers.** `Menu` and `Env`
read the surfaces' state through the same accessors -- `Get-P20Features`, `Get-P20NavAliases` --
and neither passes its own copy of the answer. They are not in the same scope when they do it:
`Menu` is a verb the user calls, `Env` is a script the module runs, and a module-launched script is
the one shape where a `$script:` read inside a global function resolves somewhere else entirely.
That is a trap, not a detail -- "A `function global:` in `utilities.psm1` cannot read module state
through a `$script:` name" under "Traps worth knowing" has the mechanism, the five idioms that do
not fix it and the one that does. `tkTestToolkit -Environment` runs the wrapper and asserts the two
renderers print one identical block.

## The shape of the work

Every work item has exactly one prompt file, and **that file is the record** — not the chat, not
your memory. What the card said, what was decided, what changed, which commits, which PR.

The five verbs carry most of it:

| Verb | Command |
| --- | --- |
| Create | `tkNewPrompt <id>`, or `tkNewPrompt -Title "..." [-Type Task\|Bug\|UserStory\|Feature\|Spike]` with no ADO -- the card gets a short id of its own (`K7M2`) |
| Ship | `tkNewPR` |
| Review | `tkGetPRComments` |
| Reply | `tkReplyPR <pr> <thread> -Reply "..." -Status fixed` |
| Close | `tkArchive` then `tkCloseItem <id> -Comment "..."` |

`tkStatus` shows every active card and its derived state — that is your ledger.
`tkDashboard` shows the tracker's: PRs across projects, assigned work items with an `Updated`
column that exposes stale cards, and recent pipeline runs. `tkMyWork` and `tkMyPRs` are the
narrower reads. `tkThreadHash` threads commit hashes in.

## State is derived from the file — do not fight it

There is no status field. `tkStatus` re-reads the file every time, in this order:

| Condition | State |
| --- | --- |
| File is in `archive/` | Done |
| A line starts `PR URL: https://`, **or** a footer line `**Review:**` | Code Review |
| A line is a bullet with a 7+ char hex hash — `- 80e2168 message`, **or** a footer line `**Started:**` | In Progress |
| none of the above | Active |

The consequences that are easy to get wrong:

- **A commit hash must be its own bullet line.** An inline or comma-separated list is not
  detected and the card will stay Active. Prefer `tkThreadHash` over writing them by hand.
- **`PR URL:` is tested first**, so a card with a PR URL and no commits reads Code Review.
- **Every lane has two writers**: git's token, or a person's. `tkMove <id> -To InProgress`
  writes `**Started:**`, `-To CodeReview` writes `**Review:**`, `-To Done` is `tkArchive`; dropping a card
  on the board runs the same verb. A card with nothing checked in, or no pull request, can still cross the
  board. The rule does not care who wrote the line. `docs/hub/cards.md`.

Editing the file by hand is a legitimate way to correct state. Writing the token *is* the
transition.

## Write into the file as you go

The diagnosis, the decision and why the alternative was rejected go **in the prompt file**, not
only in the reply to the user. A card that says what changed but not why is half a record. Fill
in Described Changes and Implementation Details before `tkNewPR` — the PR description is built
from them.

## Two ledgers

The prompt file is the engineer's record; ADO is the organisation's. One event posts to both:
`tkNewPR` writes `PR URL:` **and** moves the card to Code Review.

**Nothing reconciles them automatically.** `tkArchive` moves the file and does not touch ADO, so
Done locally is not Closed on the board. If the card should be closed, run `tkCloseItem` too.

## Traps worth knowing

- **The prompt file does not live in the tool's repo.** It lives under the configured prompt
  store — check with `tkEnv`. Never create one inside the ToolKit checkout.
- **`tkAddPRReview` must run from the repository the PR belongs to**; it computes the diff
  locally and will stop rather than review nothing.
- **`-WhatIf` on the first of a batch.** `tkCloseItem` supports it and prints the exact
  transition without calling ADO. Worth it before closing a queue of bugs.
- **`tkGetPRComments` is safe to re-run** — it skips threads already in the file. It also writes
  `PR URL:`, so it can move a card to Code Review as a side effect.
- **Reasons are not validated locally.** `tkCloseItem -Reason` passes anything ADO's process
  template accepts — `CannotReproduce`, `AsDesigned`, `Obsolete`, `Duplicate`, and others.
- **The prompt store is not this repo's parent folder.** It is `promptsRoot` in config, and the
  agent resolves it that way too. A hub need not contain the toolkit and need not be a git
  repository.
- **A hub can declare its own orgs**, in an optional `<promptsRoot>/hub.json` read between
  `config.default.json` and `config.local.json` -- so a private org never reaches the committed
  file. It declares orgs, the hub-root folder names and `storeSync`, nothing else. `storeSync`
  is there because whether the store is a git repository is a fact about the hub rather than about
  the machine reading it; a machine still overrides it in `config.local.json`. `docs/CONFIGURATION.md`.
- **Configuration is written by `Config`, and by nothing else.** `{prefix}Config -Set <key>=<value>`
  is the one writer: machine keys to `config.local.json`, orgs and the hub-root folder names to the
  hub's `hub.json`, `config.default.json` refused by name because it is the team's. The schema --
  what may be set, its type, its allowed values -- is derived in `Scripts/Get-ConfigSchema.ps1` from
  the shipped config's own keys plus the hub contract, so there is no second list. `PUT /api/config`
  runs the verb through the bridge, so the web card is a form over it rather than a second
  implementation. Hand-editing the files still works; a second *writer* does not go in.
- **A `function global:` in `utilities.psm1` cannot read module state through a `$script:` name.**
  A global function a module defines runs in the module's session state -- until it is reached from a
  script the module itself launched, which is exactly what every wrapper does
  (`Get-P20Environment` invokes `Scripts/Get-Environment.ps1`, and the script calls back into
  `Get-P20NavAliases` and `Get-P20Features`). In that shape the dynamic scope chain is
  function -> the running .ps1's scope -> module scope, so `$script:X` binds to the **nearest**
  script scope, which is the .ps1's and not the module's, and comes back `$null`; an unqualified
  `$X` walks the same chain and finds whatever that script happened to name. The symptom: `tkEnv`
  reports configured nav shortcuts as `not configured` and an org with
  `sprintAwareness: true` as `off`, while `tkMenu -All` is right about the same data in the same
  session.
  **Five idioms look like the fix and are not** -- all of them fall through to the intervening
  script scope: `$script:X`, unqualified `$X`,
  `& $ExecutionContext.SessionState.Module { $script:X }`,
  `$MyInvocation.MyCommand.Module.SessionState.PSVariable.GetValue('X')`, and
  `$ExecutionContext.SessionState.Module.SessionState.PSVariable.GetValue('X')`. **The one that
  holds** is a closure over a mutable container: one `$script:ModuleState` hashtable at the module's
  top level, and each accessor defined in a narrow `& { $s = $script:ModuleState; Set-Item
  function:global:<Name> -Value { ... $s.Key ... }.GetNewClosure() }` block, so only `$s` is
  captured and a later write through the reference is visible to every accessor. It keeps the
  `param()` block and the switches. The proof, on both PowerShell hosts: a probe script calling the
  accessors directly answers with the real table, and the same probe run through
  `& (Get-Module utilities) { & probe.ps1 }` must answer identically -- with any of the five idioms
  above it answers `$null`. `tkTestToolkit -Environment` is that probe. Two narrower precedents already in the
  tree: `Get-CliPrefix` sidesteps it by reading the exported `$global:P20Config` first, and
  `Get-P20SurfaceStates` carries three constants in a function rather than in three variables.
  **There are ZERO `$script:` reads inside a global function**,
  and `Test-Portability`'s Clause 8 holds it there by AST walk (a grep cannot tell the module body,
  where the read is correct, from a function body, where it is the trap). Every module variable a
  global function reads -- `Config`, `Commands`, `CommandMap`, `AdoCommands`, `DeprecatedAliases`,
  `ShownDeprecationHints`, `SkipNavAliases`, `ModuleCommandsLoaded` -- is a key of
  `$script:ModuleState`, and the six functions that read them (`Get-P20Menu`, `Get-P20MenuMarkdown`,
  `Register-PromptAlias`, `Get-P20CommandMap`, `Get-P20ModuleCommands`, `Write-P20DeprecationHint`) open with
  `$s = Get-P20ModuleState` -- an accessor that IS a closure over the container -- and stay ordinary
  `function global:` bodies. **They are not closures themselves, on purpose**: a `GetNewClosure()`
  body is bound to a NEW dynamic module, so a module-private helper (`function script:Register-P20NavAliases`,
  `Resolve-InvokedCommand`) is not visible from inside it -- make `Register-PromptAlias` a
  closure and the module stops importing. A closure may hold the table; a function that calls
  helpers reads it through the accessor. `tkTestToolkit -Environment` runs all six in both call
  shapes with every name shadowed. A new global function that needs module state adds a key to the
  container and reads it through `Get-P20ModuleState` -- not a `$script:` read, because Clause 8 will
  refuse it, and not a closure of its own if it calls anything private. **A module's command file is
  the same shape**: its wrappers are `function global:` bodies, so the package root is
  `(Get-P20ModuleState).PackageRoot` read inside the function, never a free `$repoRoot` the loader
  happened to set -- `Tests/Test-ModuleCommands.ps1` calls a growth verb from a module-launched script
  with every spelling of the name shadowed.

- **A test suite that declares `param([switch]$Help)` cannot use `$help` as a variable.** PowerShell
  variables are case-insensitive, so `$help = Import-PowerShellDataFile ...` is an assignment to the
  typed switch and throws `Cannot convert ... to SwitchParameter` at that line. Name the thing
  `$usage`, `$data`, anything that is not a parameter of the file.
- **A function defined in a script does not survive the module being re-imported.** A script the
  module launches runs under the module; `Import-Module -Force` resets the module's function table,
  and a helper the script defined above that line is "not recognized" below it. Local VARIABLES
  survive -- hold the helper as a scriptblock (`$openWeb = { ... }`, `& $openWeb`). `Start` and
  `Update` both re-import mid-script.
- **"The hub resolved" is not "a hub was configured".** With no `promptsRoot` anywhere, the module
  falls back to the package's parent folder -- which exists on every machine. A check for "does this
  machine have a hub" must ask whether someone SAID where it is (`PROMPTS_ROOT`, or `promptsRoot` in
  a config file), as `Scripts/Start-Toolkit.ps1` does.
- **A suite that runs a script directly does not test the verb.** A suite that drives
  `Move-PromptToArchive.ps1` with a stubbed `Get-PromptFolders` stays green while `Archive` typed as a
  verb can look in `<hub>/<org>/` and see no cards at all -- as it does when the module's own
  `Get-PromptFolders` reads the folder names through a `$script:` name (the trap above). Every workflow verb needs at least one
  assertion that imports the module in a fresh shell and types the verb.
- **On Windows the agent runs `gh` through the shell, so a `&` in a query string is cmd's, not `gh`'s.**
  A query put in the URL (`...?q=...&per_page=50`)
  fails on Windows: everything after the `&` is a second command. A query travels as `gh api -f`
  / `-F` fields (`agent/ado/design.py`), and `Tests/test_design.py`'s stub asserts that no `&` reaches the
  argv -- which is the only way a suite with `gh` stubbed can catch it.
- **Windows PowerShell 5.1 turns a redirected native stderr under `Stop` into a throw.** `gh x 2>&1` or `2>$null` in a script
  running with `$ErrorActionPreference = 'Stop'` throws a NativeCommandError on the first stderr line, before `$LASTEXITCODE` can be
  read, so the verb prints gh's sentence through the generic block instead of its own answer; pwsh 7 reads it as text, so
  a run under pwsh 7 alone is green either way. `Invoke-P20TrackerRead` (`Scripts/Invoke-TrackerRead.ps1`, dot-sourced) is the one way a
  script calls `gh`, `az` or `git`: it returns `Code`, `Lines`, `Out` and `Err`, and a raw `gh ... 2>&1` in a script is the bug --
  `Test-Portability`'s Clause 15 fails naming the line. Its allow-list only shrinks: three ritual and helper files by reason, and `Sync-Prompts.ps1` at entry level -- only its two deliberate output-passthrough lines (the pull and the push) are allowed, so any other raw `git` call in that file is a hit.
- **On Windows a child inherits every inheritable handle its launcher holds, not only the std ones.** Windows
  PowerShell 5.1 keeps a second inheritable copy of its stdout (the .NET Framework's, at startup), so clearing
  `GetStdHandle`'s is not enough and `powershell -c tkAgent | ...` waits for the agent. A long-lived
  child starts through `Scripts/Start-Detached.ps1`, which keeps every pipe but stdin from crossing.
- **`samples/hub` is read-only and is never used in place.** `Start` copies it out. A hub inside the
  package dirties the Toolkit's tree the first time a box is ticked, and `Update` refuses a dirty tree.

## The refusal contract

A command that refuses says why **once**. The exit code is what carries that across the boundary
between a script in `Scripts/` and the wrapper in `utilities.psm1` that ran it:

- **`exit 2` is a stated refusal.** The script has already called `Write-CliError`, so it has
  already printed `Error:` and a `Hint:`. The wrapper prints **nothing** on top of it, logs `ERR`
  with the **stated reason** rather than "exit code 2", and leaves `$LASTEXITCODE` at `2` so a
  caller that checks the code still sees the failure.
- **Any other non-zero exit is a failure that said nothing**, and only that one gets the generic
  `Error: exit code <n>` block with the hint that points at `{prefix}Log -Errors`.
- **A script that throws** (a terminating error it did not catch) gets one block with the error's
  own message, and `$LASTEXITCODE = 2` -- never the `0` the guard reset it to, which would print
  `Error:` and report success.
- **`exit 0` is success**, and nothing else is.

So: if you write `Write-CliError`, exit **2**. If you exit non-zero without writing one, the
wrapper will explain on your behalf -- and its explanation is worse than yours, which is the whole
reason for the split. Every wrapper goes through one guard, `Invoke-ToolkitScript`; a refusal the
wrapper itself states goes through `Write-WrapperRefusal`. Neither is reimplemented per verb.

**A switch you add to a script goes in three places, not one:** the script's `param()`, the wrapper's
`param()` in `utilities.psm1`, and the verb's `usage` in `config.default.json`. The wrapper forwards
`$PSBoundParameters`, so one the wrapper does not declare is rejected by the binder before the script
runs -- and a binding error sets no `$LASTEXITCODE`, so the call reports success having done nothing.
`tkTestToolkit -Menu` checks all three against each other for every script-backed verb, in every
direction: usage -> wrapper, wrapper -> script, and script -> usage and wrapper (without the last,
a verb can advertise `[-Help]` while taking eight parameters). A positional
parameter is named by a `<placeholder>`; `usage` is the list, and a `switches` block, where a verb has
one, describes exactly that list. The only exemptions are composition parameters nobody types, named
per verb in the test (`-Reuse`, `Env -Quiet`, `InstallAutoload -ModuleRoot`/`-CopyOnly`).

One consequence worth knowing: `agent/ado/bridge.ps1` exits on whether the **function** threw, not
on `$LASTEXITCODE`, so a verb that catches its own failure and returns cleanly would report
`success` to the browser. The guard therefore re-raises a stated refusal -- unreported -- when
`TOOLKIT_QUIET_STARTUP` marks a non-interactive caller, and `POST /api/cmd/{name}` answers
`status: error` with the stated sentence. In a terminal it is never re-raised: there the exit code
is readable, and a raw error record is exactly what this contract removes.

## One place for magic strings

The rule: all magic strings in a single spot where practical. A folder name
(`current/`, `archive/`, `pr-comments/`), a stamp (`**Closed:**`), a route prefix, a port, a
feature key, a status value belongs in one named constant each half reads -- not retyped at
every use. When you touch a literal that already appears elsewhere, lift it into the half's
constants (`agent/core/config.py` for the agent, `web/src/shell/` for the web UI, the top of
`utilities.psm1` for the CLI) and make the callers read it. A repeated literal is a drift bug
waiting for its second copy to be edited alone.

**And one more rule, for the literals that cross a half.** A per-half constant stops a string
being retyped *inside* one half. It does nothing about the ones that are a contract *between*
them -- `**Closed:**` is typed in PowerShell, Python and TypeScript alike, and the commit-bullet
regex exists twice on purpose. Those go in **`consts.json`** at the package root, read by all
three: `ConvertFrom-Json` through `Scripts/Get-Consts.ps1` (5.1-safe, no `-AsHashtable`, loaded
once in `utilities.psm1` and dot-sourceable by a standalone script), `json.load` in
`agent/core/consts.py`, a build-time `import` through the `@consts` alias in
`web/src/shell/consts.ts`. Regexes travel as **strings** and each half compiles its own, in the
subset .NET, Python and JS agree on.

The boundary is the test of it: **does more than one half type this string?** If not, it stays
where it is -- a help sentence, a UI label, a log message and an anchor the CLI both writes and
reads are one half's business. And `consts.json` is not a second source of truth beside
`config.default.json`, which keeps `workItemTypes`, `commands` and `orgs`: those are
CONFIGURATION, which a team may change, while these are the CONTRACT, which nobody may change
alone. Templates keep their literal text -- they are documents a person reads, not parsers.

Three suites hold it, one per side: `tkTestToolkit -Consts`, `Tests/test_consts.py` and
`web/src/shell/consts.test.ts`. Each states the value it resolved for every key, so a value that
stops agreeing fails somewhere; each also greps its own half for the distinctive literals, so a
new copy cannot be typed quietly. Adding a key means adding it in all three, on purpose.

## One byte contract for a card

A card is a file in the user's own store, so it has to come out the same on every host. One
writer, `Write-CardText` in `Scripts/Write-CardText.ps1`: **UTF-8 with no BOM**, through
`[System.IO.File]::WriteAllText` -- never `Set-Content -Encoding UTF8`, which emits a BOM under
Windows PowerShell 5.1 and not under 7. A file the tool **creates** is **LF** -- pass **`-New`**,
which normalises CRLF to LF in the writer and nowhere else; a file it **edits** keeps the terminator
the file already has, so it passes no `-New` -- and the writer reads the file's bytes to decide, so a
caller never works out the ending itself. `Add-Content` and `Set-Content` on a card are how a CRLF card
gets one bare-LF line, and the tool uses neither. If you add a path that creates a hub file, it calls
this function with `-New`: writing your own `WriteAllText` breaks the create half
on Windows, where `* text=auto` plus `core.autocrlf=true` hands every template and every
here-string to the writer as CRLF. Every reader tolerates both endings, and both sides assert it
(`tkTestToolkit -Archive`, `Tests/test_parsers.py`). `docs/CLI.md`, "The bytes a card is written
with", is the long version.

## One place for a card's links back into the package

A card carries two relative paths into the Toolkit tree: the `> Template:` line and the
`ado-comments workflow` line. The hub is a separate tree, synced across machines whose clones sit
in different places, so a hop computed once at write time is wrong the first time either end moves. One file
owns them, `Scripts/Repair-CardLinks.ps1`: `New-P20TemplateLine` and `New-P20WorkflowLine` **build**
the two lines and are the only things that do, and `Repair-P20CardLinks` **rewrites** them from the
card's current folder. `Archive` refreshes the card it moves (and `-Relink` a whole hub), `Sync`
refreshes after a pull and before the push. `Resolve-P20PackageLink` stays the one thing that knows
how to express the hop -- and where there is none to express (the hub and the package on different
drives, or a network share) it returns its `-Fallback`, so a card keeps the file's NAME and never a
drive letter; a line that already holds a machine path is rebuilt like any other. This is the one
thing that knows which links exist. The pass is idempotent and does not write an unchanged card. If you add a third link, add it here -- and write
`{cliPrefix}`, never the machine's registered prefix, into anything a card keeps.

## `current/` is protected: a card travels one way

**Nothing overwrites a card that is being worked on.** A card accumulates context -- the diagnosis,
the commit bullets, the PR URL, the review rounds -- and that context is the product. So:

- `NewPrompt <id>` for a card already in `current/` **returns that card**: its path, exit 0, nothing
  written, and no ADO call. It is not a refusal, and there is no switch that overwrites. To start a
  card over, a person moves or deletes the file, on purpose.
- A card leaves `current/` one way, through `Archive`. If the work comes back, `NewPrompt` scaffolds
  a fresh card and `Archive` keeps every round: `-r1`, `-r2`, `-r3`. Nothing in `archive/` is
  overwritten either.
- **The web UI has no second implementation to get this wrong.** It creates a card only through
  `POST /api/cmd/NewPrompt`, which runs the same script. Keep it that way: a native route that
  writes into `current/` is a second writer, and the rule would then have to be re-proved there.
- Every other creator follows the same shape -- `NewGrowth`, `NewMeeting`, and the agent's two native
  creates (409) refuse an existing file. A new verb that creates a file checks first.
- Verbs that *add* to a card (`ThreadHash`, `GetPRComments`, `NewPR`) append or fill a slot through
  `Write-CardText`. They never rebuild the file from a template.

## An id is not a substring

EVERY verb reads ids out of card filenames with ONE rule, `Scripts/Resolve-CardName.ps1`: an optional
type prefix from `workItemTypes` (matched ignoring case), the id, then the dash that starts the slug.
**An id is a string**: a work item number (`141`), or the four-character id of a card with no work
item (`K7M2` -- at least one letter and one digit, uppercase, matched case-sensitively so a lowercase
slug can never read as one). The shape is `regex.cardId` in `consts.json`, mirrored by `card_id()` in
`agent/core/parsers.py` and held to it by one shared table, `Tests/fixtures/parsers/card-ids.json`.
`Get-P20CardId` returns a STRING -- test `Test-P20IsWorkItemId` before doing arithmetic, because
`"99" -gt "100"` is true -- and `Resolve-P20CardArgument` is the one way a verb turns what a person
typed into a card. Do not write a private id regex: a second one knows a different
subset of the prefixes. An argument with the shape of an id is an ID and matches that id only -- a
substring match would move and commit `Task139-...` for `Archive 39`.
A non-digit argument may still
match one card by partial name, but the target is named before the move, and refused outright for a
non-interactive caller.

## Read the issues before diagnosing

**GitHub Issues is the backlog, and it is searched before anything that looks like a bug is
investigated** (`gh issue list --state all --search "<words>"`). An issue is dated, sourced and
pinned to a commit; a known one is not re-investigated, it is worked or left alone.
`docs/KNOWN-GAPS.md`, "Known gaps", is the short reader-facing list; the issue
list is the backlog behind it, and a gap row and an issue may name each other.

All three halves file there. A defect in `web/` or `agent/`, or in the growth or communication
module, is this repo's -- there is no per-half tracker.

**A public repository is a stage.** An issue, a pull request description or a comment written into a PUBLIC repository is read
by strangers, so it is written for them: no internal template, no names and dates, no private
repository, no machine path, none of this project's shorthand. Check before writing
(`gh repo view <owner>/<repo> --json visibility`); `agentic/new-issue.prompt.md`, "On stage: a
public repository", has the shape. This repository's own issues use the template and labels in that
same prompt, described next.

**Log a new one with `agentic/new-issue.prompt.md`.** A bug or improvement gets a GitHub issue
before it gets a fix, and ONLY an issue -- no local file. `docs/CONTRIBUTING.md`, "Start with an issue", has the triage rule and
the lifecycle; the prompt has the template and the label vocabulary. A fix's commit says
`Refs #N` and changes the documentation in the same commit; the issue is closed through the verb
(`tkCloseItem <n> -Comment "..."` from a Space whose tracker is this repository) with a comment naming
the commit and any `VERIFY.md` row. **Who closes: the person who merges, at merge**, so "closed" means
merged and pushed, and a defect found afterwards is a NEW issue, never a reopen. The one exception is a
fix the host that built it cannot prove: it gets its `VERIFY.md` row (next paragraph), the issue is
labelled `verify-close` and left open, and it closes once the row is walked on the other host. No file
is moved on a fix. A defect a verification run finds is filed as an issue rather than fixed where it
was found, and triaged on the machine that built the thing. With no
`gh`, the finding is written on the card being worked and filed when the tracker answers.

**A fix its own host cannot confirm leaves its check in `VERIFY.md`.** A change proved on one host
leaves its row for the other. Anything only another machine (or a real org, or a browser) can prove --
a Windows path, Windows PowerShell 5.1, a second machine's Sync, a behaviour that looks the same on the
building host either way -- gets a row in `VERIFY.md` under Gate 12 (Windows install and test),
"Rows added by a fix", in the SAME commit as the fix: the command, what you should see, the issue it
closes. The issue's closing comment points at that row. "The other machine confirms" written only in
chat, or only in an issue nobody reopens, is a check no future session will find.

## When something READS wrong, ask what it read before

A status, a badge, a count, a date -- anything the product WORKS OUT from a file -- is a rule, and
people's files were written against the rule as it read before. It must not regress: a change keeps
reading what the files already say. So when one reads wrong:

1. **Read the file.** It is the record, and it is usually right: a talk that reads "Active" may well say `Delivered: Yes`.
2. **Find the rule, in BOTH halves** if both implement it -- and check they agree. When they disagree, that is
   the bug: a `## PR Review Comments` heading read as Code Review by the agent and not by the CLI.
3. **Compare it with the rule as it read before** -- `git log -p` on the code that implements it, and
   the templates the file was written from. A rewrite that tidies a loop into a helper is how a heading
   stops matching: the old code took any heading that STARTED with the word, the new one wants the
   current template's exact text.
   **Files outlive their templates** -- a reader accepts what earlier templates wrote.
4. **Run the rule over the REAL hub**, read-only, and count what is wrong. One file in thirteen is a
   different bug from thirteen in thirteen, and the issue should say which.
5. **Pin it with a table**, not a case: every input the rule distinguishes, one row each
   (`Tests/test_growth_status.py`, `Tests/fixtures/ado-enabled/table.json`). A rule both halves implement
   gets a SHARED fixture asserted from both suites -- parity only holds for the shapes a fixture has.
6. **Say in the issue why nothing caught it.** There is always a reason, and it is usually a missing row.

The rules themselves are written down where a reader starts: a card's in `docs/hub/cards.md`, a growth
item's in `docs/hub/growth.md`, a session's in `docs/hub/manager.md`, the add-ons' in `docs/modules/`.

## Documentation is part of the change

**The documentation changes in the same commit as any verb, route, path or rule.** Not a follow-up
commit, not a TODO. A document that describes something the code no longer does is a defect of the
same severity as a failing test, and it is the one defect the tests cannot catch.

**A module verb may be written with its prefix.** `Test-Menu`'s documentation-parity check -- it reads
the root README and every document under `docs/` that can name a command -- fails on any backticked
`{prefix}Verb` that is not a known name. A module verb is unregistered whenever its flag is off, which
the committed config always is, so the check also reads every `Config/*.commands.psd1` `Commands` key:
a module verb is a known name whether or not its flag is on, and documenting `tkNewGrowth` is right. It keeps its teeth: a name in no data file, no alias and no config entry is still
stale.

**The root README is the front door, not the manual.** It is the map over `docs/`, and each subject
has one owner. It is the commercial: what the product is, the three halves, the five verbs, the quick start
and the Documentation table, in about a hundred lines, with nothing dated in it.
`tkTestToolkit -DocCounts` fails it past 120 lines, on a build-history phrase (`Since 20`, `as of
step`, `built 20`) or on a relative link that does not resolve.

| A change to... | ...changes |
| --- | --- |
| requirements, install, autoload, the first-run path | `docs/QUICKSTART.md` |
| a config key, `tkConfig`, `consts.json`, `hub.json` | `docs/CONFIGURATION.md` |
| a verb, a switch, the workflow, state, tiers, an error message, the log | `docs/CLI.md` -- `Test-Menu` reads its command-reference rows |
| a suite, a count, a runner | `docs/TESTING.md` (and `VERIFY.md`'s Gate 4, "The suite") |
| what a configuration SHOWS -- a tab, a nav entry, a card, by status, tier, tracker or flag | `docs/SCENARIOS.md`, and its executable form `web/src/shell/scenarios.test.tsx` -- a cell and its row change in the same commit |
| how the halves fit: routes in overview, `/env`, the bridge, the shell, the repo layout | `docs/ARCHITECTURE.md` |
| an add-on's switch, verbs, routes or pages (Azure DevOps included); D-CM | `docs/modules/README.md`, and that add-on's own `docs/modules/<module>.md` -- each written to STAND ALONE, to the nine headings the guide lists |
| what a file in the hub carries, or how a field or a status is read from it | `docs/hub/` -- `README.md` is the map, `cards.md` is the card |
| the rules a contribution meets | `docs/CONTRIBUTING.md` |
| a design that is going to be built: its contract, decisions, acceptance | the maintainer's hub, where the design is worked; a contributor opens an issue and the discussion lives there. A product that keeps its own notes and specs in its tree uses `design/` and `spec/` as `docs/hub/design.md` describes |
| a seam left open | `docs/KNOWN-GAPS.md`, "Known gaps" |

Two more, and the boundary is real: `web/README.md` and `agent/README.md` are the detail for their
own half, and `docs/ARCHITECTURE.md` is the overview of both. Say a thing once, in the document that
owns it, and link to it from the others. Do not grow the root README back: a new subject gets a
section in the document that owns it, or a new file under `docs/` and a row in the root README's
Documentation table. Cite a document by **file and heading**, never by a section number -- a number
moves when a document is split and a heading does not.

A fourth place, and the same rule: **a module's end-to-end document is `docs/modules/<module>.md`**,
written by whoever built it, and the shape a module writes into the hub is `docs/hub/<folder>.md`.
**The data model starts at `docs/hub/README.md`** -- the map of the hub -- and the card itself, the core
of it, is `docs/hub/cards.md`: the filename, the heading, the parsed tokens, the footer lines, the derived
state and the model the agent serves. A change to what a card carries, or to how a field is read, changes
that document in the same commit -- and a rule that both halves implement gets a SHARED FIXTURE asserted
from both suites, because parity only holds for the shapes a fixture has.
The READMEs summarise and link; they do not restate. A change to a module's verbs, routes, pages or
file shape changes that document in the same commit.

**Known gaps are written down, and kept where a reader will trip over them** --
`docs/KNOWN-GAPS.md`, "Known gaps", one click from the README. Something stubbed, mounted-without-its-data, or specified-
but-unbuilt goes on that list with what you see when you hit it. Anything a reader could mistake for
a bug is either fixed or listed.

## A release is a tag on main

Main is the release line. There is no release branch: a card merges to main through its own pull
request, and a release is a moment on main that a tag names. The version is semantic,
MAJOR.MINOR.PATCH, and the question that picks the number is what a user with a hub full of cards from
the last version would have to do: touch their files or their config, **major**; nothing, and they
find the new thing when they go looking, **minor**; nothing, and something stopped being broken,
**patch**.

What every change does: **a change a user would notice adds one line under `## [Unreleased]` in
`CHANGELOG.md`, in the same commit**, under `### Added`, `### Changed`, `### Fixed` or `### Removed`
(Keep a Changelog). Written for the user who reads release notes, not for this project: what they
can now do, or what stopped going wrong, in a sentence. A fix nobody would notice adds nothing.

What a release does, in one small pull request on main: rename `## [Unreleased]` to `## [x.y.z] - YYYY-MM-DD`
and open a fresh empty `## [Unreleased]` above it; set the same version in the three places that state
it, `Prompt20Toolkit/Prompt20Toolkit.psd1` (`ModuleVersion`), `consts.json` (`version`) and
`web/package.json` (`version`); merge; then push the tag, `git tag vx.y.z && git push origin vx.y.z`.
`.github/workflows/release.yml` makes the GitHub Release from the changelog section with that
version and refuses a tag that has none, so a release never ships with empty notes. Only the owner
tags; an agent never does.

## Conventions come from the corpus, not from taste

Prompt filenames and branch names follow house style, and the style is **evidence, not
preference**. Bugs file bare (`137-title`), Tasks as `Task139-title`, User Stories as
`US-144-title`, Features as `Feat-402-title`. Story branches carry a third segment
(`user/144/slug`) where everything else uses two (`user/137-slug`).

Those look inconsistent and are not defects — they are the convention of the card archive the tool was built
against, roughly 180 cards. **Before normalising anything that looks untidy, read the hub's `archive/`
and count.** A convention with a year of
files behind it outranks a tidier one with none. If a team genuinely wants different conventions,
they are config (`workItemTypes`), not code.

The same rule applies to scope: what a command is *for* is settled by how it is used, not by what
its name suggests.

## When ADO is not reachable

The tool degrades rather than failing: `tkNewPrompt -Title`, `tkArchive`, `tkStatus`, `tkSync`,
`tkMenu` and the tests work with no `az` at all -- `-Title` is the offline form of the creating
verb, and it writes the same file the ADO form does with the board's fields marked `(not linked)`. ADO commands say what is unavailable and why. A machine without the
tracker still produces and maintains prompt files — losing the tracker must not break the record.
