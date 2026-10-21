# Team Agile -- the add-on, end to end

> **Three names, on purpose**: **Team Agile** is what the person sees -- the
> tab, the menu heading, the settings question. **`solitaireAgile`** is the module's id and flag, the
> engine's name, and it stays in every identifier, path and key. The **Ritual Engine** is the
> generator inside it that turns the tracker into a ceremony.

**Team Agile is a team's own rituals, with the real tracker as the board and a cast that is not
people.** The engineer is the bottleneck, not the agents, and the one thing this add-on exists to show
is **what is waiting on the human**. Its first ritual is the **standup**: the human's queue at the top,
then one block per worker -- Fable, Opus, Sonnet, whatever the Space's labels route to -- with
yesterday, today and blockers, each line a real issue with its number, or the mug and one status sentence ("Nothing on the board for me. All green, no blockers.") when a
worker has nothing. The generator is the **Ritual Engine**. The contract is
[the file shape, and how a standup is read](#the-file-shape-and-how-a-standup-is-read), below.

Its second ritual, and its **first write**, is **triage** (V1;
D-TA2 to D-TA5): the open issues grouped by milestone, the ones in **no** milestone first because nobody
has placed them, and for each issue three questions -- which milestone, how severe, which size. The
size **is** the worker label (D-TA3: `sonnet` small, `opus` medium, `fable` with `deep-water` large), and
every answer is one `Route` -- a real label or milestone written on the tracker through `gh`, never a
file here.

Its third move is the **hand-off** (AR-1 of the agent in the room): `StartWork <id>` prints ONE
markdown block -- how we work in this Space, the card (or the issue) and the prompt for its kind -- so a
fresh agent in your editor starts the work with no further briefing. The Team Agile page shows the
same block in a copy box. It reads three things that already exist and writes none of them
([StartWork: the hand-off block](#startwork-the-hand-off-block)).

This document stands alone: everything a person or an agent needs to work on Team Agile is here or
one link away. It follows the standard every add-on's document follows
([the modules guide](README.md#what-an-add-ons-document-must-contain)).

**The ceremonies keep no state** (D-TA2). A standup or a triage is derived from what the tracker says
now; nothing here has a store of its own -- not a ritual log, not the time of the last standup, not a
triage answer (an answer IS the label it wrote). **The ritual happens
anyway** (principle 3): no tracker, a fresh install, a day with nothing in flight -- it still fires, and
says why its slots are empty.

## Contents

1. [The switch, and its scope](#the-switch-and-its-scope)
2. [What it owns](#what-it-owns)
3. [Turning it on](#turning-it-on)
4. [The verbs](#the-verbs)
5. [The routes](#the-routes)
6. [The web UI](#the-web-ui)
7. [StartWork: the hand-off block](#startwork-the-hand-off-block)
8. [The file shape, and how a standup is read](#the-file-shape-and-how-a-standup-is-read)
9. [The tests](#the-tests)
10. [Known gaps](#known-gaps)

## The switch, and its scope

Two keys, two scopes. The SWITCH is `features.solitaireAgile`, top-level in `config.local.json`,
**the engineer's** -- no Space can set it, and unset means off. The ANSWER is the Space's:
`spaces[].howIWork`, **How do you want to work in \<Space>?** Team Agile is on only where the switch is on
**and** the Space you are in answers `agents`. The tracker the Space's address names says which answers
there are: a GitHub Space is asked (*With agents* or *Alone*, Alone until someone answers); an Azure DevOps
Space is *On a team in Azure* -- their board holds the rituals, so Team Agile is off there -- and a Space
with no tracker is *Alone*; both derived, never asked. One rule per half, `Scripts/Resolve-HowIWork.ps1`
and `how_i_work()` in `agent/core/config.py`, one table, `Tests/fixtures/how-i-work/table.json`, applied
where the flags are resolved, so every half reads one answer
([`docs/CONFIGURATION.md`](../CONFIGURATION.md#spaceshowiwork----how-you-work-in-this-space)). Switching
Space re-evaluates it -- per request in the agent and the web UI, at `SwitchSpace`'s re-import in a shell.
The word on the flag is the working id; the owner locks it with the tab's name (the spec's open items).

**Off means absent**, in every half -- switched off, or on in a Space that does not work with agents: no
`Standup`, `Triage` or `Route` verb, no row in `Menu`, no `-Help`, no bridge entry, no route (**404, not
403**, its detail naming whichever is off), no tab, no nav entry, nothing fetched and no bytes. The one
thing visible is its NAME, in the `Opt in by configuration` block of `Menu -All` and `Env`, under the
question "How do you want to work in \<Space>?": `Team Agile module  on (chosen: with agents in <slug>)`,
`off (derived: on a team in Azure ...)`, `off (derived: alone ...)`, `off (chosen: alone in <slug>)`, or
`not configured` for a GitHub Space nobody has answered -- each with the line that changes it.

## Why a GitHub Space

Team Agile reads a GitHub Space and says so on its `Tracker` line for any other. That is the shape, not
a gap. "ADO is human orchestration and GitHub Issues lends itself to agent
orchestration -- acknowledge this fact and embrace it." An Azure DevOps Space is a human team's board:
the organisation's sprints, its ceremonies, its people, and the card is the engineer's own record inside
it. The standup there is the one the humans hold in their own room, and this product serves that team
with the card, the 1:1 and the Teams message (the communication module). A GitHub Space is where the
tracker can be the team: the routing labels are the roster, the agents work in worktrees, a lead merges,
and the rituals tell that process back. Team Agile is that Space's feature by nature. The design card
holds the decision (D-TA19) and the reasoning behind it. A LOCAL Space -- no
tracker address, or one whose status is `local` -- has a standup over its CARDS, with the engineer as
its one worker, and an active GitHub Space reads its cards beside its issues, joined on the id
([the two sources, joined](#the-two-sources-joined)); an Azure DevOps Space still does not, and its
`Tracker` line says why.

## What it owns

| Half | Team Agile's | Not Team Agile's, though it sits beside it |
| --- | --- | --- |
| CLI | `Config/solitaireAgile.commands.psd1` + `.ps1` (four wrappers); `Scripts/Start-Work.ps1` (the hand-off block: the id through `Resolve-P20CardArgument`, else the Space's issue; the Space's note or its `howIWork` sentence, `Get-P20HowIWorkSentence` in `Scripts/Resolve-HowIWork.ps1`; the kind's prompt); `Scripts/Get-Standup.ps1` (the verb: which Space, which source, the two `gh` reads or the card read, the printing); `Scripts/Standup-Rules.ps1` (the issues, cards and joined fills and the rendering, pure; the source rule; the card reader); `Scripts/Get-Triage.ps1` and `Scripts/Triage-Rules.ps1` (triage's read, and its grouping and text, pure); `Scripts/Set-Route.ps1` (the one write: one `gh issue edit` per switch); `Scripts/Ritual-Common.ps1` (the skeleton the three verb scripts share -- which Space, and the two-reads-to-`@{ ok; value }` gh layer Standup and Triage call; Route keeps its own gh-call shape but shares the Space resolution); the inventory row (from the psd1) and its question in `Config/settings-workflows.json`; the menu heading `Team Agile` (category `rituals`) | `Scripts/Resolve-Tracker.ps1` -- which repo a GitHub Space means, shared with every GitHub verb; the card rules a standup reads cards through -- `Resolve-CardName.ps1` (the id), `Get-PromptFileStatus.ps1` (the state, and `Test-P20CardBillable`) |
| Agent | `agent/solitaire/standup.py` and `triage.py` -- one gated router, `GET /api/ritual/standup` and `GET /api/ritual/triage`, **reads only**; a triage answer reaches the tracker only as `POST /api/cmd/Route`, the bridge | `space_scope` in `agent/ado/accounting.py`, the `?space=` rule `/issue-report` uses; `card_id` and the state rule in `agent/core/parsers.py` |
| Web | `web/src/modules/solitaireAgile/` -- the descriptor, the Standup \| Triage strip (`RitualPage.tsx`), the standup page, the Triage page, the hand-off's copy box (`StartWorkBox.tsx`, a `lazyPart`), and `stage/`: the cast atoms (by copy), the seats, the generated deck and the played route | the shell; the deck engine (`web/src/modules/deck/engine/`) and its second resolver `GeneratedDeckHost.tsx`, which the played view borrows |
| Data | `Config/ceremonies.json` (the standup's slots, queue kinds, registers and `kinds` -- the bug and feature kinds a dressed sentence may count by; triage's three question slots, its severities `sev1`-`sev3`, its `deepWaterLabel` and the words of its text) and `Config/standup-vocabulary.json` (`phrasebook`, `nothing`, `excuses`, `fakeWork`, and `verbs`, the standup register's words offered to the model), read by both halves, never typed in code (D-SA2) | the model profile, `agent/core/model.py` (`ai.model`, `ANTHROPIC_API_KEY`), which the dress calls through and the PR review and the notes tidy-up share |
| Contract | `consts.json` `rituals`: the route, `triageRoute`, the two data files, `workerLabelPrefix`, `walkLabel`, `labelWidth`, every fixed word of the text; `consts.json` `startWork.text`: the hand-off block's head line and three section headings | -- |
| Configuration | `config.default.json` `startWork.prompts`: which `agentic/` prompt the hand-off carries for each kind, set with `Config -Set startWork.prompts.<kind>=<path>` | the prompts themselves, `agentic/`, which are the package's |
| Hub | nothing -- no verb writes to the hub; `Route` writes to the TRACKER; a local Space's standup READS its `current/` and `archive/`; `StartWork` READS a card in `current/` and the Space's `how-we-work.md` when it has one | the cards, which are the card verbs' |

The cast is the tracker's labels, not a list in code: **a worker is a label whose description starts
`Routed to`** (`rituals.workerLabelPrefix`), and the worker's name is the text after it up to ` -- `.
`Routed to Opus -- the crash-through volume` is Opus. The walk label is `verify-close`.

## Turning it on

```powershell
tkConfig -Set features.solitaireAgile=true
tkConfig -Set spaces.<slug>.howIWork=agents -Hub   # a GitHub Space: work it with agents
tkMenu -All            # Team Agile lists tkStandup; the Opt in block reads: Team Agile module  on (chosen: with agents in <slug>)
tkStandup
tkTriage               # the open issues by milestone, unplaced first
tkRoute 140 -Size opus -Severity sev2 -WhatIf
```

Or in the web UI: the Settings drawer's "How do I…" section asks **How do you want to work in \<Space>?**
 with three radios, each with its sentence -- *With agents* (Team Agile on for this Space: the
standup and triage over the repository's issues), *Alone* (no background rituals: solo coding, or a course
in your own codebase), *On a team in Azure*. On a GitHub Space the first two can be picked and a pick runs
`Config -Set spaces.<slug>.howIWork=<answer> -Hub` through the bridge (`PUT /api/config`): *With agents*
and the tab appears, *Alone* and it goes. On an Azure DevOps Space *On a team in Azure* is checked and
locked ("Their board holds the rituals; Team Agile is off here."); with no tracker *Alone* is
("Connect a tracker to unlock working with agents."). A choice the Space cannot make is drawn disabled
with its reason, never hidden. The pick shows at once -- a tiny **Saving…** spinner beside the group, the
other answers locked, the group `aria-busy` -- for the seconds `Config -Set` takes through the bridge, and a
refusal puts it back with the CLI's sentence. The row's **Change** goes to the switch itself; with
*With agents* chosen and the switch off, a line under the radios says the answer waits for it.

The standup reads the Space you are in. It needs a GitHub Space (`tkConnect <slug> -Address
https://github.com/<owner>/<repo>`) and `gh` signed in, and labels whose descriptions route to a worker:

```bash
gh label create opus --description "Routed to Opus -- the crash-through volume"
```

The module's verbs are not in the autoload manifest (it is generated from the committed config, where
every module is off), so it answers once any `tk*` command has loaded the module.

## The verbs

| Verb | Does | Touches a file |
| --- | --- | --- |
| `Standup [-Space <slug>] [-AsJson] [-Brief] [-Grain <detail\|work\|brief>] [-Since <yyyy-MM-dd>] [-Remind <HH:mm>] [-Days <Mon,Tue,...>] [-Walk]` | prints today's standup for the Space you are in, or the declared Space `-Space` names, read without switching into it. `-AsJson` prints the response the agent serves, `text`, `work` and `brief` included -- the bridge's shape and the parity test's. `-Brief` prints only the chair's reading (below) and, being a read, does not re-arm the reminder. `-Grain` picks the register of detail ([the work grain](#the-work-grain)): `detail`, the default, is the text as it always printed; `work` is the ritual's grain, spoken as standup prose ([the prose](#the-prose)); `brief` is `-Brief`. A word that is not a grain, or `-Brief` with another grain, is a stated refusal (exit 2). `-Since <yyyy-MM-dd>` widens yesterday back to that day ([what moved](#what-moved-and-the-window)) -- not `-Days`, which is the reminder's cadence; a day that is not one, or is after today, or `-Since` with `-Remind`, is a stated refusal | none |
| `Triage [-Space <slug>] [-AsJson]` | prints the Space's open issues grouped by milestone -- no milestone first, then most open first -- each milestone under its context line, each issue one line: number, title, who has it ([who](#who-takes-it)) -- `me`, `@<login>`, its worker (its size), or `nobody` -- severity or `--`, `deep-water` marked. `-AsJson` is the route's shape | none |
| `Route <n\|id> [-Size <label>] [-Assign <me\|size>] [-Milestone <title>] [-Severity <sev>] [-DeepWater] [-Space <slug>] [-WhatIf]` | answers triage's questions for issue `<n>`: **one `gh issue edit` per switch given**, in that order. `-Assign` says who takes it ([who](#who-takes-it)); on a card with no issue behind it, `-Assign` is the one switch and writes the card's `**Assigned:**` line. `-WhatIf` prints every write and makes none | none for an issue -- it writes the tracker; a card's `**Assigned:**` line |
| `StartWork <id> [-Clip] [-Prompt <path>] [-Space <slug>]` | prints the hand-off block for a card in `current/`, or for the Space's GitHub issue `<id>` when no card carries it ([below](#startwork-the-hand-off-block)). `-Clip` puts it on the clipboard and says so in one line; `-Prompt` carries another prompt for this call | none -- it reads |

**The walk list** (`Standup -Walk`). The PC's morning as one printout: the standup's title line, then
one block per open `verify-close` issue by number, each the line the standup prints (`  Walk       #<n> <title>`) <!-- markdownlint-disable-line MD038 -- the span shows the printed line with its indent, which is the point -->
with, indented under it, the Gate 12 row of `VERIFY.md` (read from the package root) whose text names that
issue as `#<n>` -- verbatim and wrapped as the file wraps it, because it is written for a person -- or the line
`  no VERIFY row -- close on the issue's own words`. An empty list prints the title and `Nothing is waiting on you.`; <!-- markdownlint-disable-line MD038 -- the span shows the printed line with its indent, which is the point -->
a tracker that does not answer prints the `Tracker` line, exit 0. `-AsJson` carries `walk[]` of `number`,
`title`, `url`, `verifyRow` (null when no row names it) and nothing else of the standup. `-Walk` is a read, not
attending: it does not re-arm the reminder, and `-Walk -Remind` is a stated refusal (exit 2). It writes nothing.

Two `gh` reads on the Space's ONE repo (the same rule every GitHub verb uses -- a repo-grained address,
or exactly one repo in the Space's projects):

```text
gh label list --repo <repo> --limit 500 --json name,description
gh issue list --repo <repo> --state all --limit 500 --json number,title,state,labels,closedAt,url,milestone,body
```

`milestone` and `body` are the work grain's: an item groups by its milestone, else by the design card
its body names.

**Triage's reads**: `gh label list` as above, then `gh issue list --repo <repo> --state open --limit 500
--json number,title,state,labels,assignees,milestone,url`, then `gh api user -q .login` -- who "me" is,
best effort: when `gh` cannot say, an issue assigned to you reads `@<login>` and the triage still answers.
**Route's writes**, each its own call, nothing else:

```text
-Size opus          gh issue edit <n> --repo <repo> --add-label opus --remove-label fable,sonnet
-Assign me          gh issue edit <n> --repo <repo> --add-assignee @me
-Milestone "<t>"    gh issue edit <n> --repo <repo> --milestone "<t>"
-Severity sev2      gh issue edit <n> --repo <repo> --add-label sev2 --remove-label sev1,sev3
-DeepWater          gh issue edit <n> --repo <repo> --add-label deep-water
```

The sizes are the repo's worker labels, read with `gh label list` before a `-Size` write; the milestone is
one of the repo's OPEN milestones (`gh api repos/<repo>/milestones -f state=open`), matched ignoring case
and written with the tracker's spelling; the severities and `deep-water` are `Config/ceremonies.json`'s.
**Deep water gets two moves** (D-TA4) -- assign Fable or split into sized children, the parent kept open.
`-DeepWater` adds the label and nothing more; Route prints the two moves as its hint
(`Route <n> -Size fable`, or split: `NewItem -Parent <n> -Title <text>` once per piece), and makes neither.
A split piece is a **sub-issue** of the deep-water issue: `NewItem -Parent <n>` on a GitHub Space creates
the issue, then adds it through GitHub's sub-issues route (`POST repos/<repo>/issues/<n>/sub_issues`,
by the new issue's id); where GitHub refuses that route on the repository, it appends a `- [ ] #<new>`
task-list line to the parent's body instead, and says which it did. The parent is read first, so a wrong
number creates nothing ([`NewItem`](../CLI.md#command-reference)).

### Who takes it

Who takes an item is the tracker's own field where it has one (D-AR10). On a GitHub issue a **person** is
the assignee -- `Route <n> -Assign me` runs `gh issue edit <n> --add-assignee @me` -- and the **crew** is
the worker label `-Size` already writes, so `-Assign <size>` IS the `-Size` write, byte for byte (D-TA3:
the label is the size). `fable` is the owner's own seat, never a crew builder; it is a size like the others
here. `-Assign` and `-Size` that name different sizes are a stated refusal.

On a **card** -- a card with an id of its own (`K7M2`), or any card in a Space with no tracker or a
`local` one -- there is no issue to write, so `Route <id> -Assign me|<size>` writes ONE footer line,
`**Assigned:** me` or `**Assigned:** <size>` (`consts.json` `stamps.assigned`), through `Set-P20CardLine`
and `Write-CardText` -- above `**Created:**`, the card's own line endings kept, an unchanged card not
written -- and nothing else. The card is found the way every verb finds one (`Resolve-P20CardArgument`:
an id is never a partial name; a partial name from the bridge is refused). Its sizes are the repo's worker
labels on a connected GitHub Space (the list `-Size` reads), and there is no second list (D-AR10): in a
Space with no connected GitHub repository there are no worker labels to read, so a card there takes
`-Assign me` alone and `-Assign <size>` is a stated refusal saying so. A card takes `-Assign` alone; any other switch
is a stated refusal. `-WhatIf` prints the line it would write. Both halves read the line back --
`card_assigned`, `Get-P20CardAssigned` -- as the card model's `assigned`
([cards](../hub/cards.md)).

Triage says who has each issue, one rule a half (`Get-P20TriageWho`, `who()`): its first assignee --
`me` (`consts.json` `rituals.assignMe`) when that is the signed-in `gh` user, `@<login>` otherwise -- else
its size, else nobody. A group's `routed` counts the items someone has: an assignee or a worker label.

An Azure DevOps Space is untouched: `Route -Assign` there is the same "not GitHub" refusal as every other
switch, card or issue.

**Route refuses** (`Error:`, `Hint:`, exit 2, nothing written): no number (or, with `-Assign`, no card
id); no switch; a severity that is not `sev1`-`sev3`; an undeclared `-Space`; a Space that is not GitHub,
or is `local` or `archive` (for an issue); a repo that is ambiguous; `gh` missing; a size that is not a
worker label on the repo (the hint lists them); `-Assign` and `-Size` that disagree; a milestone that is
not open there (the hint lists them); a `gh` write that fails (the hint names the writes before it); on a
card, any switch but `-Assign`, a value that is neither `me` nor a size (the hint lists them), a size where there is no connected GitHub
repository to read worker labels from, or an id no
card in `current/` carries. The reads that check an answer run under `-WhatIf` too, so a refusal is the
same with or without it.

After those reads and before the first write -- `-WhatIf` included -- Route asks the repository's
visibility once (`gh api repos/<owner>/<name>`) and, when it is public, prints `[!] This repository is
public` ([CLI](../CLI.md), "A write to a public repository says so"). It asks nothing.

A Space with no address, or a `local` or `archive` one, makes no `gh` call at all: it reads its own
`current/` and `archive/` in the hub ([the two sources, joined](#the-two-sources-joined)). An active
GitHub Space makes its two `gh` reads and reads those folders too.

**Not answering is not a refusal.** An Azure DevOps Space (`rituals.text.adoTracker`: "Azure DevOps is
the human team's board, ...", D-TA19), a Space whose repo is ambiguous, `gh` missing, or `gh` failing --
each prints the standup with the chair's two lines and the reason on its `Tracker` line, and exits 0.
The one stated refusal (`Error:`, `Hint:`, exit 2) is a `-Space` nobody declared.
`Triage` behaves the same: its title, then a `Tracker` line saying why.

## The routes

| Route | Gate | Reads | Writes |
| --- | --- | --- | --- |
| `GET /api/ritual/standup?space=<slug>&since=<yyyy-MM-dd>` | `features.solitaireAgile` per request, with the active Space's answer applied (**404** unless the switch is on and the Space you are in works with agents; the detail names which is off); `space` scoped like `/api/issue-report` (an undeclared slug 404); `since` widens yesterday's window as `Standup -Since` does, and a `since` that is not a day, or is after today, is a **422** naming it | the same two `gh` reads (the issues with `milestone` and `body`), through the same data files -- or, for a local Space, its cards | nothing |
| `GET /api/ritual/triage?space=<slug>` | the same | `gh label list`, `gh issue list --state open` with `milestone` and `assignees`, and `gh api user` (who "me" is, best effort) | nothing |
| `POST /api/cmd/Route` | the bridge: `Route` is in the CLI's command table only while the flag resolves on -- the switch on and the Space answered `agents` | -- | what `Route` writes, and nothing else |
| `POST /api/cmd/StartWork` | the bridge, the same way: off, the call is `rejected`; a stated refusal is `status: error` with the verb's sentence | the card (or `gh issue view`), the Space's note or answer, the prompt | nothing |

No route of this module's builds the hand-off block (D-AR6): the CLI is its one implementation, and the
bridge is how the page asks for it.

The response is the spec's ("The M0 build contract"): `ceremony`, `register` (`real`), `asOf`, `since`, `space`,
`source` (`issues`, `cards`, or `none` when `tracker.ok` is false), `tracker` (`ok`, `reason`), `chair`
(`open`, `close`), `queue` (`walk`, `decide`, `look`), `workers` (each `label`, `name`, `yesterday`,
`today`, `blockers`, `empty`, `excuse` -- the empty worker's status sentence; the name is historical), `work` (the work grain: `queue` -- each kind's groups --,
`workers` -- each `label`, `name`, the three slots' groups and `prose`, its sentences --,
`queueProse`, the queue's sentences, and `text`, the prose; a group is `name`, `by`, `count`, `refs`,
`phrase`), `spoken` (the dress, [the agentic layer](#the-agentic-layer): `model`, `workers` -- each
`label` and `prose`, the worker's sentences as the stage says them --, `dressed`, `refused`; null when no
model answered, and the agent's alone: `Standup -AsJson` has no such key, because the CLI calls no
model), `text` and `brief` (the chair's reading), and `counts` -- what moved in the window
([below](#what-moved-and-the-window)): `workers`, each `label`, `name`, `closed`, `started`, `inProgress`,
`commits`, and `total`, the same with `label` and `name` `""`. Every item has seven keys -- `number`, `id`,
`title`, `url`, `path`, `motion` (`closed`, `started` or `inProgress`, `consts.json` `rituals.motions`) and
`commits` (a walk item also `worker`): an issue's `id` is null and its `path` `""`; a card's `number`
is null and its `url` `""`. `tracker.ok` false still answers 200 with the ritual. `Standup -AsJson`
prints the same shape.

Triage's response: `ceremony` (`triage`), `space`, `tracker` (`ok`, `reason`), `slots` (the three
questions, from `ceremonies.json`), `severities`, `deepWaterLabel`, `sizes` (each `label` and `name` --
the repo's worker labels), `groups` (each `milestone` -- `""` for none -- `open`, `routed`, `unrouted`,
`context`, `issues`, each issue `number`, `title`, `url`, `worker`, `size`, `assignee` (the first
assignee's login, `""` for none), `who` (`me`, `@<login>`, the size, or `""` -- nobody), `severity`,
`deepWater`) and `text`. `Triage -AsJson` prints the same shape.

## The web UI

`web/src/modules/solitaireAgile/` adds a **Team Agile** tab at `/solitaire-agile`, after the Studio's
and before the Lounge's, while `features.solitaireAgile` is on. Off: no route, no nav entry, nothing fetched
and no bytes -- the descriptor imports no component (the page is a `lazyPart`), and the smoke's off mode
asserts that no module source and no `/api/ritual` request was made. The page reads
`GET /api/ritual/standup?space=<active Space>` -- the route from `consts.json` `rituals.route`, through
`@consts` -- and shows the response's `text` verbatim: the first line (the ceremony and its date) as the
card's header, every line after it in a monospace block with its padding and line breaks kept, and each
`#<n>` the response names (the walk queue and every worker's three slots) linked to that issue's `url`.
Header, a line break and body are `text` byte for byte, and the page test says so. Above the prose, a
small **Detail | Work | Brief** tab strip picks the grain ([the work grain](#the-work-grain)),
remembered per browser (`usePersistedValue`, key `p20.solitaireAgile.grain`), `Detail` the default: Work
shows `work.text`, Brief shows `brief` as the body (and drops the small brief above it), each verbatim; a
response from an agent that predates `work` shows Detail for it. Beside Play, **Copy** (Daily's pattern: `copyText`, "Copied!" for a moment) puts the grain on screen -- `text` at Detail -- on the clipboard exactly as the response gives it. Under the prose a quiet **Show as list** / **Hide list** toggle (collapsed by default, constant box) opens the same items as rows read from the response's structured fields, nothing re-fetched: the queue's items first (kind, number linked to `url`, title, worker), then each worker's (slot, number, title, worker); a card shows its id and no link. Each row ends in a quiet **Start work**, which opens the hand-off block's copy box for that item ([StartWork: the hand-off block](#startwork-the-hand-off-block)). The other thing
to click is **Play**, quiet, in the header (V1, below). With `tracker.ok` false the page still draws the ritual -- the chair's lines and the
`Tracker` reason -- and when the agent does not answer it says so as an error, never as an empty standup.
`StandupPage.test.tsx` builds the response from `Tests/fixtures/rituals/standup.json` and asserts the
page's text against the same golden files the CLI and the agent assert; `registry.solitaireAgile.test.tsx`
holds the gate and the nav order.

**Triage** is the tab's second page, at `/solitaire-agile/triage`. The tab keeps ONE nav entry,
lit on both pages, and carries a **Standup | Triage** strip of in-page tabs, each an address
(`RitualPage.tsx`, Home's shape; the standup page is drawn inside it unchanged). The page reads
`GET /api/ritual/triage?space=<active Space>` (`rituals.triageRoute`) and asks about **one issue at a
time**, in the read's order -- the group with no milestone first. The order is taken once, from the first
read, so an answer that moves an issue to another milestone does not change which issue is in front of
you. Above the issue, its milestone's context line ("No milestone -- 2 open, 2 routed, 0 unrouted");
the issue's number and title link to it; under them, what it already carries -- who has it first (`me`,
`@<login>`, the worker's name, or `nobody`; [who](#who-takes-it)), then its severity -- and the three
questions:

- **Milestone** -- a picker of the Space's OPEN milestones, from `GET /api/milestones`.
- **Severity** -- `sev1`, `sev2`, `sev3` (the read's `severities`).
- **Size** -- **me** first (`Route <n> -Assign me`: you become the assignee; pressed when the issue is
  already yours), then the repo's worker labels by name (the read's `sizes`), then `deep-water`. Choosing
  deep water shows its two moves (D-TA4): **Assign Fable** (`Route <n> -Size fable -DeepWater`) and
  **Split**, which opens the new-issue dialog (the same door as **New GitHub Issue**) with this issue
  filled in as its **Parent issue**. Each create there is one `POST /api/cmd/NewItem` with `-Parent <n>`,
  and the dialog shows the verb's answer -- `Linked: #<new> is a sub-issue of #<n>`, or the task-list
  line it used instead. It keeps the parent after a create, so the next piece has it too. Split writes
  nothing itself, and the dialog and its reads are mounted only while it is open.

Each answer is ONE `POST /api/cmd/Route`, its argv from `buildRouteParams` in `cliBridge.ts`; the
verb's answer, or its refusal in its own words, shows in a status line under the questions. **Next**
skips. Nothing moves between issues or while an answer is in flight: the title is one line, the
deep-water row is always laid out and only shown, and the status line is a fixed box. With no tracker
the page says `Triage reads a GitHub Space` and the reason, and asks nothing. `TriagePage.test.tsx`
builds the read from `Tests/fixtures/rituals/triage.json` and asserts the queue, the context line and
the exact argv of every answer; `RitualPage.test.tsx` holds the strip.

### The played view

**Play** opens `/deck/ritual/standup`: the same standup, read from the same route (RTK's cache, so
nothing is fetched twice), played on **the stage** -- the Wasteland's Remote Standup, its nine tiles in
their composition, every time (D-TA17). The route is this module's,
chromeless like any deck, and it plays **with `features.deck` off**: the page, the stage and the deck
engine are one lazy chunk fetched when Play is pressed.

- **The atoms, by copy.** `stage/cast.tsx` carries the Remote Standup's `Person`, `ZoomTile`, the two
  bubbles (below), `Mug`, the nine webcam scenes and the keyframes from a private repository, the way the trailer came over
  -- with no dependency on that repo, and without the cast's bios, dossiers and lines: every word a tile
  says is the Ritual Engine's. Under `prefers-reduced-motion: reduce` the stage is still: no tile pops,
  no steam rises, the speech bubble is simply there, and the thought cloud does not float.
- **Bubbles** (`stage/cast.tsx`). One Fluent `Popover` surface in two shapes, `inline` in its tile
  and placed by the engine (`positioning`, `withArrow`, no fixed offset -- it flips and shifts, as the
  issue popover does). The **speech bubble** is open for the speaking (lit) tile, its tail at the
  speaker's FACE: the engine points it at a small anchor element over the head of the tile's
  scene (`tile-<seat>-face`, a head position per scene in `standupDeck.tsx`; the rim of the mug on a mug
  tile), `above` and centred on it, never at the tile's box -- so it does not hang off a corner or land
  on a neighbour. A top-row tile has no room above, so it falls to `below` with the tail still at the
  face, and the stage is the overflow boundary, so it is held inside the grid rather than shifted
  sideways. The surface itself does not clip (its tail is drawn outside it). The text shows at most
  **four lines** and ends the last in an ellipsis: a fixed CSS line clamp on the text element
  (`SPEECH_MAX_LINES`), no scrollbar, "because it is real" -- four lines always fit below the face, so the
  bubble never covers the speaker. Nothing is lost: the voice (the slide's Say lines) and the thought
  cloud still carry every line. It carries that tile's slot lines -- the sentence the voice reads.
  The **copy panel** beside the stage (the deck engine's right 40%) does not repeat them: it is the
  speaker's character -- the title, the persona and the motto, the Wasteland's own words carried in
  `CAST` -- and, on a worker's slide, the worker's label, the one real noun. The motto is who the
  character is, never a status, so nothing on the slide claims work the tracker did not say.
  The **thought bubble** is the same surface as a cloud with the dotted trail: the tile's `...` button
  (a real button, so click, Enter and Space) opens it, Escape closes it, and so does the deck advancing
  (a slide's tiles are keyed by the slide). It lists the detail behind the sentence -- each slot with
  its items, each `#n` an issue popover -- on a worker's tile and the queue's chair; a mug has none.
  The voice reads the slide's notes, never either bubble, so narration and duration are unchanged.
- **Who is talking** (`stage/cast.tsx` `ZoomTile`, `stage/standupDeck.tsx` `Tile`). A tile has one of
  three looks, and one tile is in colour, ever. **Speaking** -- its bubble is open (`data-speaking="true"`,
  `data-look="speaking"`): colour, a 3px outline in the active theme's brand primary (`outlineOffset: -3px`, so
  the grid does not move; its own `stage-frame` element over the tile, because an outline on the tile itself is
  painted under the picture), and the green name-dot. **Named** -- lit with no bubble (the queue slides' Walk,
  Decide and Look seats, and the Tracker's when it is down; `data-look="named"`): black and white at full
  brightness, the green dot kept (the filter is on the picture layer, not the dot) -- the dot is the signal
  light, colour is the speaker's alone. **Everyone else** -- the ghost, as before: grayscale, dimmed, a grey
  dot (`data-look="ghost"`). The frame's colour is the stage's own green, `pf.green` -- the colour of the register badge at the top right and of the speaker's name-dot -- handed to the tiles as the CSS variable `--sa-speaker`. It is never a theme's brand token: the room is the engine's default dark whatever the app wears, and the frame is the same on every theme. There is no pulse, so reduced motion has none to
  still.
- **The seats** (`stage/seats.ts`, the card's table). Nine, always: **Fable** in `TEAM LEAD · DEV-HERO
  (fable)`, **Opus** in `AI VIBEMANCER (opus)`, **Sonnet** in `MINIMALIST (sonnet)`, the chair in
  `CHAIR · PM`, the queue's three kinds in `WALK · QA ALCHEMIST`, `DECIDE · NEW HIRE` and `LOOK ·
  DESIGNER`, and the two reads in `TRACKER · OPS-DEV` and `THE WEEK · ULTRAWIDE OVERLORD`. A worker
  label with no seat kept for it takes a free worker seat; past three it does not sit, and the chair's
  closing line names who is also standing. A seat with no one, or nothing, today is the ghosted tile with
  its plate; the tracker's seat lights only when the tracker could not be read.
  The three personas prefer the labels `fable`, `opus` and `sonnet` because the sample team is a model crew;
  the engine reads workers from any tracker label carrying the worker prefix, so another team's labels take the seats in label order.
- **The script** (`stage/standupDeck.tsx`). Three slide kinds, in this order: the **queue** (the plate
  is the standup's first line; the chair reads what is waiting on you, or the tracker's reason), the
  **chair** opening with its phrasebook line, **one slide per seated worker** in seat order (the tile
  lit, the others ghosted, its bubble the three slots -- or, for a worker with nothing, the **mug** where
  the face would be and its status sentence, D-TA11, which reports async: the bubble's first line is `My async status:` and the Say line opens with the same words -- the stage's own reading of a tile with no person in it, so the CLI's text, which has no tiles, still prints the mug row as it did), the chair closing, and the **queue again**
  (D-TA6). Every slide carries the ritual's plate and **`REGISTER · REAL`** (D-TA13). The deck plays at
  the **work grain**, spoken as prose: a bubble is one line a SENTENCE, and the voice one
  `Say` line a sentence -- `Yesterday I closed two in Team Agile (#<n>, #<n>).`, `Nothing blocked.` --
  read as written from the response's `work.queueProse` and each work row's `prose` -- or, for a worker
  the model dressed, that worker's `spoken` sentences: the stage reads `spoken` when present and
  `work` otherwise ([the agentic layer](#the-agentic-layer)) -- so the engine's
  narration and its length estimate work as for any deck; an empty slot says nothing, an empty queue
  is `Nothing is waiting on you.` A response without `work` (an older agent) plays one `Say` line a
  slot, item by item. Slide ids are
  `standup-<date>-<seat>` and survive a rebuild.
- **Suitcase on the desktop.** The deck sets the engine's `audiobook` hint (docs/modules/deck.md,
  "Audiobook decks"): it opens in Suitcase Mode, narrating, at any width, with **prev and next either
  side of the transport**, so a tile can be skipped without leaving the mode.
- **The voice.** No clip can exist for a sentence the tracker wrote this morning, so the browser's
  `speechSynthesis` reads each slide's title and `Say` lines (D-TA7's fallback, V1's only voice); with no
  speech API the slide lives for its estimated read time and moves on, silently.
- **Mute**. A speaker button in the player's bar (at any width, beside the transport),
  `aria-pressed` when muted, tooltip "Mute narration" / "Unmute narration". Muted, `speechSynthesis` is
  handed nothing -- not even `cancel()` -- and no clip is requested; the bubbles are unchanged and each
  slide keeps the clock it has with no speech API (read time plus the dwell), so the deck still
  advances. The choice is remembered per browser (`localStorage` key `toolkit-narration-muted`,
  `NARRATION_MUTED_STORAGE_KEY`; `"1"` muted) and read before the first slide, so a muted player never
  speaks on open; a browser that refuses storage plays unmuted and mutes for the session. The default is
  unmuted. The standup never calls `/narrate` (no clip resolves for it), so there is no neural voice to
  fetch lazily: muting spares only the browser's voice.

### The chair's reading

`Standup -Brief` prints a few lines and nothing else, and the agent's response carries the same
string as `brief`; the page shows it above the prose as small lines, and Copy still copies `text`
only. No model: every sentence is a count or a derived fact, the fixed words are `consts.json`
`rituals.text` (the `brief*` keys), and `Format-P20StandupBrief` / `render_brief` are held to the
goldens `standup-<case>.brief.txt` (an `expected.brief` entry per case, in both fixtures).

```text
Since Thursday 1 October 2026: 2 closed, 2 in progress.
Waiting on you: 2 walks, all on the PC.
Fable: 1 closed yesterday, 1 open, none in flight, 1 blocker.
Opus: 1 closed yesterday, 1 open, none in flight, no blockers.
Sonnet: nothing today.
In flight is not yet known: every routed issue reads as open.
Next: the walks -- 2 on the PC.
```

**The counts line opens it**: the window's first day and what moved in it, in total
([what moved](#what-moved-and-the-window)) -- `Since <day>: <n> closed, <n> started, <n> in progress, <n>
commits.`, a part said only when it is not zero, `nothing moved` when all are. Then one line per queue kind
that has items ("Nothing is waiting on you." when none); one line per worker
(open is today plus blockers; an empty worker is "nothing today"; a worker whose open items began in the
window adds `<n> started`, and one whose cards thread commits adds `<n> commits` -- the per-worker
counts; under a wider window a worker's closes are `<n> closed`, not "closed yesterday"); the in-flight sentence while the
running state is unbuilt, because every routed issue reads as open; and "Next", the rule -- the kind
with the most items (ties go to the ceremony's queue order) and who they wait on. A GitHub Space's
walks are `verify-close` issues, so they wait on "the PC"; a local Space's cards in Code Review wait
on "you", and say neither "all on the PC" nor "none in flight". A joined GitHub Space reads as a
GitHub Space, except that a card on its walk puts the walks on "you" (and drops "all on the PC"), its
card tile says no "none in flight", and its `Check` lines follow the workers. With the tracker not
answering, the brief is the one `Tracker` line.

## StartWork: the hand-off block

Three moves make the loop: triage the backlog, make the issues, start the work. The first two are
`Triage`/`Route` and `NewItem`; the third is `StartWork`. It prints **one markdown block** a fresh agent
in your editor can start from without a question -- how we work in this Space, the work, and the prompt
for its kind -- each under a heading that names the file it came from, so the agent can re-read the
original:

```markdown
# Start work: Task 23A3 -- Route the remaining raw git calls

## How we work in Widgets (hub.json: spaces[widgets].howIWork = agents)
You work with agents here: the repository's GitHub issues are the backlog, ...

## The work: Task 23A3 (widgets/current/Task23A3-route-the-remaining-raw-git-calls.prompt.md)
<the card's text, whole>

## The prompt (agentic/build.prompt.md)
<the prompt's text, whole>
```

**Nothing before it and nothing after it** on stdout, LF-joined, so `tkStartWork 23A3 | pbcopy` (or
`| clip` on Windows) and `> file` carry exactly the block; `-Clip` does the copy itself and prints one
line. The head line and the three heading shapes are the contract's, `consts.json` `startWork.text`
(`head`, `howWeWork`, `work`, `prompt`) -- the CLI types them, the copy box finds the block's title by
the head line's shape. It writes nothing anywhere.

**The input** is resolved the one way every verb resolves one, `Resolve-P20CardArgument`
(`Scripts/Resolve-CardName.ps1`): a card in the Space's `current/`, an id matching that id only
(`StartWork 39` never assembles `Task139-...`), a filename, or -- in a terminal -- a partial name, which
is named on a line of its own before the block. Then, for a work-item number no card in `current/`
carries, the Space's GitHub issue of that number (`gh issue view <n> --json
number,title,state,labels,milestone,body,url` on the Space's one repo). Refused, each with `Error:`,
`Hint:` and exit 2: no id; an id or a name that matches nothing; a card in `archive/` (it is Done -- a
fresh `NewPrompt` brings the work back); a card in `backlog/` (it is planned, not in play -- the hint
names `Move <id> -To Active`, because starting is the person's decision); a closed issue; a number that is a pull request; an Azure DevOps
Space (its board holds the rituals); a local Space or one with no tracker, asked for a number no card
carries; an undeclared `-Space`; and, for a non-interactive caller such as the bridge, a partial name.

**Section one, how we work.** The Space's own note, `<promptsFolder>/how-we-work.md` in the hub, when it
has one -- the heading then names that path (`widgets/how-we-work.md`). Until a Space has one (none does
yet: the first-run work that writes the team's files is a later milestone), it is ONE sentence derived
from `spaces[].howIWork` through the same table that gates the module (`Scripts/Resolve-HowIWork.ps1`,
`Get-P20HowIWorkSentence`), and the heading names the key and its answer,
`hub.json: spaces[<slug>].howIWork = <answer>`. A section that said "not written yet" would be a block
that fails its own purpose, so it always assembles.

**Section two, the work.** A card goes in **whole, as written** -- read the way `Status` reads it, never
from a parsed model -- so its commit bullets, its `PR URL:` line and its footer stamps (`**Sprint:**`
uncut, however long the milestone's title) travel with it. The one transform is the terminator rule:
CRLF reads as LF, so a card written on Windows gives the same block as one written on a Mac. Its heading
names the card's path relative to the hub. An issue's heading names its URL, and its text is rendered as a
card renders what came from the tracker: `# Issue #<n>: <title>`, `Tags:` (the labels, joined by a semicolon and a space),
`**Sprint:**` (the milestone), then the body.

**Section three, the prompt**, chosen by the item's kind from `config.default.json` `startWork.prompts`
-- configuration, not contract, because a team's prompts are its own (D-AR4). The kind is the card's
type, read from its filename by the `workItemTypes` table (its key with the spaces removed: `Bug`, `Task`,
`UserStory`, `Feature`, `Spike`), or `issue`. A path is relative to the Toolkit package, or absolute; an
`agentic/<name>` row goes through the one prompt lookup, so a tuned copy in `agenticExtensionPath` wins
here as everywhere. The shipped rows hand every kind to `agentic/build.prompt.md`: read the card under
**The work**, take its branch from current main, do what it says, thread each commit with `tkThreadHash`,
fill Summary, Described Changes and Implementation Details as you go, and when the code is ready run
`pr-ship`. Not `new-bug` or `new-user-story`, which create an item and a card the item being started
already has; not `pr-ship` itself, which assumes the code is done. No `design` row ships, because no
design prompt does. A team changes a row with
`tkConfig -Set startWork.prompts.Bug=agentic/<name>.prompt.md`, and adds a kind the same way
(`startWork.prompts.Meeting=...`); `-Prompt <path>` carries another prompt for one call. A kind with no
row, or a row whose file is not there, is a stated refusal naming `startWork.prompts.<kind>`.

**The page.** On the standup's **Show as list**, every row -- an issue or a card -- ends in a quiet
**Start work**. It opens the copy box (`StartWorkBox.tsx`, a `lazyPart`: its chunk is fetched the first
time a row asks), which makes **one** `POST /api/cmd/StartWork` with the item's number or id and shows the
block verbatim in a monospace region, the block's own head as the dialog's title, and one button,
**Copy**. A refusal shows the sentence the verb stated and nothing else; an agent that does not answer
says so. No agent runs in the browser (D-AR1): the block is text you carry to your editor.

**Proving it.** `Tests/fixtures/start-work/` holds a Space's answer, a card (with commit bullets, a
`PR URL:` line and footer stamps), an issue's `gh` answer and the two expected blocks byte for byte, each
up to the prompt's heading: the prompt section is the shipped `agentic/build.prompt.md` itself, appended by
every reader, so the golden and the prompt cannot drift. `tkTestToolkit -StartWork` types the verb in a fresh shell against them -- the card in LF and again
in CRLF -- and `Tests/test_bridge.py` runs it through `POST /api/cmd/StartWork` and compares the same
file. Whether a cold agent really starts without a question is a person's judgement, so it is a gate row
in `VERIFY.md`, "The cold-agent walk".

## The reminder to attend

D-TA15: the one ask-shaped thing the feature has is Organize's bell, and it is opt-in twice -- Organize's
flag, then `Standup -Remind <HH:mm> [-Days Mon,Tue,...]`. The switch writes ONE Organize reminder through
Organize's own verbs (`NewReminder`; a second `-Remind` rewrites it through `Reminders <id> -Due -Ref`,
never a second file): title `Standup`, source `standup`, the cadence on its `**Ref:**` line (`09:00
Mon-Fri`), due at the first time in the cadence still ahead. **Attending re-arms it**: when `Standup` runs,
or the page shows the standup (it posts once to `POST /api/ritual/standup/attend`, which runs the same two
Organize verbs through the bridge), today's reminder is archived and the next working day's in the cadence
is written -- once a day; Friday's next is Monday's. Organize grows no recurrence, no file and no config
key: the reminder IS the state. Archiving it in Organize stops the cycle, since attending only re-arms an
open one. Without `features.organize` the switch is a stated refusal naming the key; the attend route
answers 200 with `action: "off"`. The drawer's Team Agile section (`StandupRemindSettings`, anchor
`standup.remind`) sets the same thing through `POST /api/cmd/Standup`; the Team Agile question in
`Config/settings-workflows.json` names it in its sentence -- the inventory and the questions are one to
one, so the reminder is not a surface of its own. The cadence rule is one shared table, `Tests/fixtures/rituals/remind.json`,
held by `tkTestToolkit -StandupRemind` and `Tests/test_standup_remind.py`; `GET /api/ritual/standup/remind`
reads the reminder's state for the drawer. `docs/modules/organize.md` names the `standup` source.

## The file shape, and how a standup is read

Team Agile keeps no file of its own in the hub, so it has no file shape of its own -- its one hub write is
a card's `**Assigned:**` footer line ([who](#who-takes-it); [cards](../hub/cards.md)); a standup reads the cards'
([the two sources, joined](#the-two-sources-joined)). What regresses is the **slot rule**, and it is
read the same in both halves (`Scripts/Standup-Rules.ps1`, `agent/solitaire/standup.py`), held by one table:

| Rule | Reading |
| --- | --- |
| the window | `since` is local midnight at the start of the previous WORKING day (Mon-Fri) relative to `asOf`, in `asOf`'s offset: Friday's is Thursday; Monday's, Saturday's and Sunday's are Friday. No timestamp is kept (D-SA3). **Or a wider one**: `Standup -Since <yyyy-MM-dd>` (`?since=`) moves it back to that day's local midnight, in `asOf`'s offset -- yesterday's lower bound only; today and the blockers are what is open now ([what moved](#what-moved-and-the-window)) |
| a worker | a label whose description starts with `workerLabelPrefix`; the name is after it, up to ` -- `, trimmed. Ordered by label name. An issue's worker is its FIRST such label |
| yesterday | closed, with the worker label, `closedAt` in `[since, asOf]` |
| today | open, with the worker label and NOT `verify-close` |
| blockers | open, with the worker label AND `verify-close`; rendered with `(verify-close)` (with a leading space) after the title |
| the queue | `walk` is every open issue with `verify-close`, worker or none, by number; `decide` and `look` are empty in M0 |
| nowhere | an open issue with neither a worker label nor `verify-close` |
| empty | a worker with all three slots empty shows `Mug` and one status sentence: `nothing[(d + i) mod len]`, `d` the day of the year of `asOf`, `i` the worker's position |
| the chair | opens on `phrasebook[d mod len]`, closes on `phrasebook[(d + 1) mod len]` |
| no fake work | the real register never reads `fakeWork` (D-SA5), nor `excuses` (the nonsense register's, since the empty worker reports status) |
| what moved | each slot item's `motion`: `closed` in yesterday; in today and the blockers, `started` when its card began in the window, else `in progress`; and `commits`, its card's distinct hashes ([below](#what-moved-and-the-window)) |
| the counts | per worker and in total, each item by its motion and the distinct commits its cards thread -- a hash once however many cards thread it; the brief's first line |

**The text**, LF-joined, every fixed word from `consts.json` `rituals.text`, slot labels padded to
`labelWidth` (9) then two spaces:

```text
Standup -- Friday 2 October 2026
"Can we not adjust scope."

Waiting on you
  Walk       #<n> Verify the Studio tab draws on the PC
  Walk       #<n> Verify the clock fix on Windows

Fable
  Yesterday  #<n> Port the cast atoms
  Today      nothing in flight
  Blockers   #<n> Verify the Studio tab draws on the PC (verify-close)
Opus
  Yesterday  #<n> Rename the slug
  Today      #<n> Build the foyer counts
  Blockers   no blockers
Sonnet
  Mug        "Nothing on the board for me. All green, no blockers."

"Let's circle back."
```

With no tracker, a `Tracker` line replaces both the queue and the blocks; with no worker labels,
`No worker labels in this Space.` replaces the blocks. The date is `dddd d MMMM yyyy` in the invariant
culture. The golden files in `Tests/fixtures/rituals/` are the law where this sketch and they disagree.

### What moved, and the window

A line naming `#155` should say whether it was closed or only started, and the standup should say how
much moved -- a sense of velocity, derived, nothing stored. **Every slot item carries a motion** (`motion`
in the response, which the counts sum), and **its line says what that adds to its slot**, after the ref
(`rituals.text.itemMotion`, `{ref} ({motion}) {title}`): `started`, and its card's commits when it has
any. `closed` under Yesterday and `in progress` under Today or Blockers are what the slot's label
already says, so a line does not repeat them:

| The item | Its motion | Its line |
| --- | --- | --- |
| in yesterday (an issue closed, a card archived, in the window) | `closed` | `#153 Close the books`, or with commits `#153 (2 commits) Close the books` |
| in today or the blockers, its card -- its own, or the card an issue's number names -- began in the window | `started` | `#151 (started) Count the commits`, or `#151 (started, 2 commits) ...` |
| in today or the blockers, otherwise | `inProgress` | `#154 Read the label`, or `#152 (1 commit) Fold the window` |
| an issue with no card | `closed` or `inProgress`, never `started` | no parenthesis: an issue alone has no commits |

**Began** is the card's `**Started:**` day (`Move -To InProgress` writes it), else its `**Created:**` day
-- the card's own footer, read with its lane. An issue alone cannot say `started`: the read
(`number,title,state,labels,closedAt,url,milestone,body`) carries no time its work began -- not when a
worker label was added, not whether a branch exists -- and finding out is a timeline read per issue that
the standup does not make. So an issue with no card is closed or in progress, said plainly; a team whose
work runs on cards gets the three words from the cards.

**Commits** are the card's `- <hash>` bullets -- the same lines that put it In Progress
(`regex.commitBullet`, the lane rule's own pattern, which captures the hash), so counting them is no
new read and no second pattern. A hash is compared by its first seven characters, lowercase: a short and a full hash of one commit
are one. A card with no bullets counts none; an issue with no card counts none; a not-billable card is
not a row and adds nothing to one, its commits included. A card's commits are all it threads, not only
the window's: a bullet has no date.

```text
Fable
  Yesterday  #153 (2 commits) Close the books
  Today      #154 Read the label
Opus
  Today      #151 (started, 2 commits) Count the commits
  Today      #152 (1 commit) Fold the window
```

**The counts** (`counts` in the response) sum the slots per worker and in total -- closed, started, in
progress and commits -- and **a hash is counted once however many cards thread it**, per worker and in
the total. The brief opens on the total ([the chair's reading](#the-chairs-reading)):
`Since Thursday 1 October 2026: 2 closed, 2 started, 2 in progress, 5 commits.` The counts are the
page's, at the top -- the brief sits above every grain -- and not the stage's: the played view speaks
the work grain, one sentence a group, and the dress guard holds every number a sentence says to the
group's own; a velocity line there would be a number the group does not carry.

**A window, not only yesterday.** `Standup -Since <yyyy-MM-dd>` (`?since=` on the route) moves
yesterday's lower bound back to that day: every issue closed and every card archived since then is
listed, once -- an issue and the card joined to it are one row -- and the counts sum the window. Today and
the blockers are unchanged by it: they are what is open now. The slot keeps its label (`Yesterday`); the
counts line names the day, and a worker's brief line says `<n> closed` rather than "closed yesterday".
The default stays the previous working day (D-SA3). `-Days` is not this: it is the reminder's cadence.

`Tests/fixtures/rituals/standup-joined.json` holds it: the `counts` case (each motion, commits per item,
a hash two cards thread counted once), `not-billable-counts` (a not-billable card absent from the
counts) and `window-three-days` (a three-day window with a close on each day, listed and counted once, and a
close the day before the window not), with `expected.motions` and `expected.counts`; card rows carry
`begun` and `commits`, as `read_cards` / `Get-P20StandupCards` read them.

### The two sources, joined

**Issues and cards**. Both are records of work done: the card is the job record, the tracker the
product record. A GitHub Space that is `active` reads BOTH -- its issues, and the CARDS in its own
`current/` and `archive/` in the hub -- joined on the id. A Space with no tracker address, or one whose
status is `local` or `archive`, has only its cards, so the ritual happens whatever the board is made
of. Which source a Space gets is one pure rule of its address and status (`Get-P20StandupSource` in
`Scripts/Standup-Rules.ps1`, `standup_source` in `agent/solitaire/standup.py`):

| The Space | Source | What you see |
| --- | --- | --- |
| GitHub, `active` | `both` | the standup above, joined with the Space's cards ([below](#the-join)) |
| no address (any status), or GitHub `local` / `archive` | `cards` | the cards' standup ([below](#the-cards-alone)) |
| Azure DevOps (any status) | `none` | the chair's lines and `Tracker  Azure DevOps is the human team's board, ...` (`rituals.text.adoTracker`, D-TA19) -- no card is read |

The module itself is on only in a Space answered *With agents* -- a GitHub Space -- so the cards
source is what a GitHub Space that is still `local` reads, and what `-Space <slug>` (or `?space=`) reads
for a Space with no address while you stand in one that works with agents. A Space with no tracker, as the
Space you are in, answers *Alone* and has no standup of its own. `"issues"` is what the issues fill says
on its own; no Space chooses it any more, and an agent that predates the join still answers it.

**Which cards a standup mentions.** Every card in play, unless it is checked not billable: a card that
says `**Billable:** no` (`stamps.billable`, written by `Billable -No`) is not a standup row and adds
nothing to one -- the rule Daily applies, read by the same reader (`card_billable` in
`agent/core/parsers.py`, `Test-P20CardBillable` in `Scripts/Get-PromptFileStatus.ps1`). No line means
billable.

#### The join

The join is keyed on the card's id, by the one id rule (`Resolve-CardName.ps1`, `card_id()`): a tracker
number, or an id of the card's own.

| The card | In the standup |
| --- | --- |
| its id is the number of an issue in the read | **ONE row, the issue's** -- title, labels, worker, milestone and slot are the tracker's, placed as the issues fill places them, and the card never overrides them. The card adds what only it knows: its lane (`links[]`: `number`, `id`, `lane`, `path`; the lane read the way `Status` reads it, Done in `archive/`) |
| ... archived, and the issue is open | the issue's row, and one `Check` line: `#<n> <title> -- the card is archived, but the issue is still open.` (`rituals.text.checkCardArchived`) |
| ... in `current/`, and the issue is closed | the issue's row, and one `Check` line: `#<n> <title> -- the issue is closed, but the card is not archived.` (`rituals.text.checkIssueClosed`) |
| ... the issue has no worker label, so the issues fill gives it no slot at all | the issue's row stands (never duplicated), but the card -- when it is itself in `current/` -- also joins the under-you tile, in the slot its own lane maps to: the same fallback an unlinked card already takes, so the link is not invisible for want of a route |
| an id of its own, or a number the read has no issue for | **its own row, under you**: one tile labelled with the Space's slug and named for it, in the slot its lane maps to ([the cards alone](#the-cards-alone)), after the worker tiles -- and only when it has something to say; its Code Review cards follow the issues on the walk |
| not billable | nothing |

**When the two disagree, it is said, and nothing is written.** The `Check` lines (`checks[]`, by issue
number) come after the worker tiles in every grain -- the detail as rows under the `Check` label, the
work grain and the brief as `Check: <sentence>` lines -- and `Route` stays the one write, to the
tracker. Rounds share an id (`-r1`, `-r2`): the one in `current/` is the card, else the archived one closed
last, so an earlier round is never "archived while the issue is open". With no card in play the joined
standup is the issues' alone, byte for byte; with the tracker not answering it is the `Tracker` line and
no card. Daily is unchanged.

```text
  Check      #142 Port the cast atoms -- the card is archived, but the issue is still open.
  Check      #143 Rename the slug -- the issue is closed, but the card is not archived.
```

`Tests/fixtures/rituals/standup-joined.json` holds the shapes -- a linked card and an open issue, a linked
card archived while its issue is open, an issue closed while its card is in `current/`, a card of its own,
an issue alone, a not-billable card -- and all of them on one day, and the three of
[what moved](#what-moved-and-the-window). Its goldens (`standup-joined-<case>.txt`, `.work.txt`, `.brief.txt`) --
and `standup.json`'s and `standup-cards.json`'s -- are generated by
`python3 Tests/regenerate_joined_goldens.py` (Windows: `py -3`; `--check` to compare) and never typed. Both suites assert
every row.

#### The cards alone

A card's state is the card rules' own ([`docs/hub/cards.md`](../hub/cards.md#state-is-derived-never-stored)),
read the way `Status` reads it, and it maps to a slot like this:

| The card | Slot |
| --- | --- |
| in `archive/`, its `**Closed:**` day in `[since, asOf]` (compared as days) | **yesterday** |
| in `current/`, In Progress | **today** |
| in `current/`, Code Review | **today**, AND the walk queue -- the local form of "what waits on you" |
| in `current/`, Active | nowhere -- not started |
| in `archive/` with no `**Closed:**` line, or closed before `since` | nowhere |
| a file the one id rule finds no id in (a dated PR-comment record, a note) | not a card; skipped |
| a card that says `**Billable:** no` | nowhere -- not a standup row |

**One worker.** A local Space has one worker, the engineer, so the standup has one tile: labelled with
the Space's slug and named with its display name (the slug when it has none). `blockers` is always
empty -- a card carries no walk label -- and a day with nothing in either slot is the mug and its status sentence
(`nothing[d mod len]`, the first worker's pick). Within a slot, cards are in file-name order. **The text
is the same rendering**, with the card's id (what `Get-P20CardId` returns: `K7M2`, `139` -- the id every
verb takes) where an issue has `#<number>`, and no link:

```text
Standup -- Friday 2 October 2026
"Can we not adjust scope."

Waiting on you
  Walk       139 Write the docs
  Walk       144 Read the board

Widgets
  Yesterday  198 Fix the export
  Yesterday  Q3R9 Photo import
  Today      K7M2 Wire the board
  Today      139 Write the docs
  Today      144 Read the board
  Blockers   no blockers

"Let's circle back."
```

A card's title is its heading's: the part after the first colon when the part before it ends with the
card's id (`# Task 139: Write the docs` is `Write the docs`), else the whole heading, else the filename.
`Tests/fixtures/rituals/standup-cards.json` holds the mapping, the source rule and the title rule as
tables, with `standup-cards-<name>.txt` beside it; both suites assert every row.

### The work grain

**Two views, two registers of detail** (D-TA20). The text above is the
ledger: every item, every number, every link -- right for exploring, and nobody can give or hear a
standup like that. The ritual speaks at the grain of the WORK: each worker's slot items are grouped by
what they belong to, and each group is one phrase with the count behind it. Sixteen issues become a
few sentences. No model groups anything: every noun is a milestone's title, a design card's name, a
card's type or the titles' own words, and every count is derived (the real register's rule). The rule
is one, in both halves (`Group-P20StandupWork` and `Format-P20StandupWork` in `Scripts/Standup-Rules.ps1`,
`group_work` and `render_work` in `agent/solitaire/standup.py`), held by `Tests/fixtures/rituals/standup-work.json`:

| Step | An item belongs to | `by` |
| --- | --- | --- |
| 1 | its milestone's title | `milestone` |
| 2 | the design card its body names: a `> GitHub:` thread (`rituals.workThreadRegex`), named by that issue's head when the read has it, else `#<n>`; else a `design/<note>.md` (`rituals.workDesignRegex`), its stem title-cased (`team-agile` is `Team Agile`) | `design` |
| 3 | a card's type, from its heading (`# Task 139: ...` is `Task`) -- a card's row only | `type` |
| 4 | what is left in the slot, by the titles' common stem: each title's head (`rituals.workHeadRegex` -- a one-word tag like `Bug:` dropped, cut at ` -- ` or `: `); heads that share their first two words or more group under the words they all share (`Design lifecycle L1: ...` and `Design lifecycle L2: ...` are `Design lifecycle`), a trailing small word (`rituals.workSmallWordRegex`: `the`, `of`) not counted; a head alone names itself | `stem` <!-- markdownlint-disable-line MD038 -- the span shows a separator with the spaces the pattern cuts at --> |

Groups with the same name, ignoring case, are one group, named as first seen -- so a milestone and a
design card both called Team Agile are one. Most items first; a tie keeps the slot's order. A group's
phrase is `rituals.text.work<Slot>` for the slot's first group (`{name}, {n} closed` for yesterday,
`{name}, {n}` for today, `{name}, {n} to walk` for blockers and the walk queue) and `workGroup`
(`{name}, {n}`) for the rest; `{n}` is `rituals.numberWords[n]`, digits past twelve. The queue's kinds
are grouped the same way. The phrase is the group's data; what the work text SAYS is the groups spoken
as prose ([the prose](#the-prose)). It keeps the long form's frame -- the title, the chair's
lines, the `Tracker` line when nothing answered -- with one line for the queue and one per worker; an
empty slot says nothing, an empty worker is its status sentence. This table's `friday` case:

```text
Standup -- Friday 2 October 2026
"Can we not adjust scope."

Waiting on you to walk #<n>, Verify the Studio tab draws on the PC. Also to walk one in Phase 6: #<n>, Verify the clock fix on Windows. Also to walk #<n>, Verify the clock on Windows.

Fable: Yesterday I closed two in Design lifecycle (#<n>, #<n>). I also closed #<n>, Rename the slug. Today I'm on two in Team Agile (#<n>, #<n>). I'm also on two more: #<n> and Design lifecycle L3. Blocked on #<n>, Verify the Studio tab draws on the PC.
Opus: Yesterday I closed three in Team Agile (#<n>, #<n>, #<n>). I also closed one in the Studio: #<n>, Count the foyer rows. Today I'm on two in Team Agile (#<n>, #<n>). Nothing blocked.
Sonnet: "Nothing on the board for me. All green, no blockers."

"Let's circle back."
```

**The grain is configurable** (`rituals.grains`: `detail`, `work`, `brief`): `Standup -Grain <grain>`
in the terminal (`detail` the default, `brief` the same as `-Brief`), a per-browser setting on the page
(detail the default), and the played view always plays at `work`. The response carries the grouped
form as `work` beside `text` and `brief`; `standup-work-<case>.txt` are the goldens of its text. A model
may DRESS a worker's sentence for the stage, never add to it ([the agentic layer](#the-agentic-layer)).

**Triage's rule**, read the same in both halves (`Scripts/Triage-Rules.ps1`, `agent/solitaire/triage.py`),
held by `Tests/fixtures/rituals/triage.json`:

| Rule | Reading |
| --- | --- |
| which issues | the OPEN ones; a closed issue in the read is read past |
| the groups | by milestone title; the group with NO milestone first (when it has any), then the milestones by open count, most first, a tie by title (ordinal) |
| inside a group | by number |
| worker, size | the issue's FIRST worker label (the standup's rule); the label is the size, the name is the worker |
| severity | the first of the issue's labels, in its own order, that `ceremonies.json` names a severity |
| deep water | the issue carries `deepWaterLabel` |
| routed | carries a worker label; `unrouted` is `open - routed` |

```text
Triage -- toolkit

No milestone -- 2 open, 1 routed, 1 unrouted
  #<n> Split the drawer  (--, sev2)
  #<n> Port the cast atoms  (Opus, sev3)

Phase 6: ledgers -- 3 open, 2 routed, 1 unrouted
  #<n> Re-plumb the bridge  (Fable, sev1, deep-water)
  #<n> Ledger counts  (--, --)
```

No open issue prints `Nothing is open.`; no tracker prints the standup's `Tracker` line. The words are
`ceremonies.json`'s `triage.text`; the goldens `triage-<name>.txt` are the law.

### The prose

**Standup language from the issues' facts** (the spec's D-SA10). "what is said
going around the room is not proper standup language and needs standup prose generated from the issues".
The work grain fixes the GRAIN; the prose fixes the REGISTER. After the grouping, a sentence step speaks
each group as one standup sentence -- a grammar over the groups, no model. One rule in both halves
(`Get-P20StandupProseSentence` in `Scripts/Standup-Rules.ps1`, `prose_sentence` in
`agent/solitaire/standup.py`), held by `Tests/fixtures/rituals/standup-prose.json`. A sentence is
`rituals.text.proseSentence` (`{lead} {body}.`):

| Part | Which | Words (`rituals.text`) |
| --- | --- | --- |
| lead | a slot's (or queue kind's) first group | `proseYesterday` "Yesterday I closed", `proseToday` "Today I'm on", `proseBlockers` "Blocked on", `proseWalk` "Waiting on you to walk" (`proseDecide`, `proseLook` beside it) |
| lead | every group after it | the same key with `Also`: "I also closed", "I'm also on", "Also blocked on", "Also to walk" |
| body | a group of one whose name IS its item's clause (a stem group, mostly) | `proseBare`: `{item}` -- `#<n>, Rename the slug` |
| body | a group of one | `prose<Slot>One`, else `proseOne`: `{n} in {name}: {item}` -- `one in the Studio: #<n>, Count the foyer rows`; today's is `proseTodayOne`, `{name}: {item}` -- `the Studio: #<n>, the archived-repository mark` |
| body | a group of more | `prose<Slot>Many`, else `proseMany`: `{n} in {name} ({refs})` -- `two in Team Agile (#<n>, #<n>)` |
| item | the one item of a group of one | `proseItem`: `{ref}, {clause}` -- the ref (`#<n>`, or a card's id) and the title TRIMMED TO ITS CLAUSE: its head by `rituals.workHeadRegex` (a one-word tag dropped, cut at ` -- ` or `: `), as written <!-- markdownlint-disable-line MD038 -- the span shows a separator with the spaces the pattern cuts at --> |
| refs | a group of more | its refs in the slot's order, joined by `proseRefSeparator` (`, `) <!-- markdownlint-disable-line MD038 -- the span shows a separator with the spaces the pattern cuts at --> |
| fold | today's groups after the first, when there are two or more | ONE sentence, not one a group: the `Also` lead and `proseTodayFold`, `{n} more: {names}` -- `two more: #<n> and Design lifecycle L3`; `{n}` the number of groups, `{names}` their names joined by `proseNameSeparator` (`, `), the last by `proseNameLast` (` and `), and no ref <!-- markdownlint-disable-line MD038 -- the spans show separators with their spaces --> |
| fold | past `rituals.proseFoldNames` (4) of them | `proseTodayFoldCount`, `{n} more designs` -- `I'm also on seven more designs.` |
| close | a worker with something to say and no blockers | `proseBlockersNone`, "Nothing blocked." |

**The also-ons fold** (D-SA9: a group and a count, never a list). A worker on eight things
today would otherwise say "I'm also on ..." seven times, and the bubble outgrows its tile. So today's
first group is said as above -- `Today I'm on #<n>, flights.` -- and everything after it is one
sentence: `I'm also on three more: workflow settings, the Studio and card family marks.`, or past four,
`I'm also on seven more designs.` The folded sentence carries no issue numbers; the thought bubble, which
lists the detail behind the sentence, keeps every one. Only a slot with a `prose<Slot>Fold` template
folds, and only `today` has one: yesterday's closes, the blockers and the queue are said a group a
sentence. A dressed stage is handed the folded sentence as one sentence (its facts: the names it says,
the count of its groups, no ref of its own) and holds it to the same guard; nothing else in the dress
changes. `standup-prose.json`'s `folds` table pins the edges -- one, two, four and five groups after the
first, eight in all, digits past twelve, a group named by a thread (`#<n>`), and the slots that never
fold -- and its `eight-groups` case is the worker it was written for.

`{n}` is `rituals.numberWords`, digits past twelve; a name is compared with its clause ignoring case.
Placeholders are filled in one pass, so a title that contains `{n}` is said as written. The queue's
sentences are its kinds' in the ceremony's order, and a queue item routed to nobody is spoken there and
in no worker's line. A worker with nothing in any slot says no sentence of its own: it is its status (`nothing`). Every noun,
number and clause is the tracker's; every other word is the contract's. The response carries the
sentences -- `work.queueProse` and each work row's `prose` -- and `work.text` is them, one line for the
queue (or `Nothing is waiting on you.`) and one a worker:

```text
Standup -- Friday 2 October 2026
"Can we not adjust scope."

Waiting on you to walk two in Phase 6 (#<n>, #<n>). Also to walk #<n>, Verify the Studio tab draws on the PC.

Fable: Today I'm on the Studio: #<n>, the archived-repository mark. I'm also on #<n>, Rename the slug. Blocked on #<n>, Verify the Studio tab draws on the PC.
Opus: Yesterday I closed two in Team Agile (#<n>, #<n>). I also closed one in the Studio: #<n>, Count the foyer rows. Today I'm on two in Team Agile (#<n>, #<n>). Nothing blocked.
Sonnet: "Nothing on the board for me. All green, no blockers."

"Let's circle back."
```

`Standup -Grain work` prints it, the page's Work grain shows it (each `#<n>` linked, as in the detail
text), and the played view speaks each sentence as a `Say` line. `standup-prose.json`'s `sentences`
table pins every shape row for row -- one item named or bare, several, the first group and the rest, each
slot and the walk queue, a count past twelve, a clause found by its head -- and its four cases (`friday`,
`quiet`, `no-tracker`, `cards`) the sentences and the goldens `standup-prose-<case>.txt`: closed and in
review (a walk; a card in Code Review), a blocked item, a queue item routed to nobody, a worker with
nothing to say, a slot with nothing, a queue with nothing.

### The agentic layer

**A model dresses the prose, and may never add a fact** (D-SA11). "use proper stand up language -- 'wire-up', 'plumbing for',
'smashed 10 bugs'." The prose above is the FLOOR and the fallback; in the agent only, after the read,
`dress_standup` (`agent/solitaire/standup.py`) hands each worker sentence that speaks a group to the model
-- through the provider profile every model call uses (`agent/core/model.py`: the model is `ai.model`,
the key `ANTHROPIC_API_KEY` from the environment) -- and gets one sentence back per group, in the first
person, in the register's words. Each one is held by **the guard**; the first check it fails is the
reason the prose sentence is said instead. Nothing else changes: `text`, `brief` and `work` (its `text`
included) are byte for byte what they were, the register stays `real` -- dressed facts are still facts --
and the response gains `spoken` beside `work`, which the played view reads when present.

What the model is given, per sentence (`dress_facts`): an `id`, the worker's name, the slot, the prose
sentence (`floor`), the group's `name`, `count` and `refs`, each ref's title, and `kinds` -- how many of
the group's items are bugs or features: an issue is of a kind when it carries the kind's label, a card when
its type is the kind's type (`Config/ceremonies.json` `standup.kinds`: `bug`/`Bug` is bugs,
`enhancement`/`Feature` is features). Its vocabulary is the `verbs` family of
`Config/standup-vocabulary.json` ("wired up", "plumbing for", "smashed", "landed", "chased",
"unblocked") -- the only family it is shown: never `fakeWork`, `excuses`, `nothing` or `phrasebook`, and a test says
so. Not dressed: the queue's sentences (the chair's, not a worker's first person), "Nothing blocked.", a
mug's status sentence.

**The guard** -- `dress_guard` in the agent, `Test-P20StandupDress` in `Scripts/Standup-Rules.ps1`, one
rule held by `Tests/fixtures/rituals/standup-dress.json` from both suites. The checks are `consts.json`
`rituals.dressGuards`, in the order they run:

| Guard | Refuses a sentence that |
| --- | --- |
| `empty` | is blank, or more than one line |
| `ref-added` | says a ref (`dressRefRegex`: an issue's `#n`, or a card-id-shaped word like `K7M2`) that is not one of the group's -- `and #<n>` |
| `ref-dropped` | leaves out a ref of the group |
| `number` | says a number (`dressNumberRegex`, or a `numberWords` word) that is not the count, a kind count, or a number in the facts' own words ("Phase 6") -- "four" for three |
| `count-dropped` | is about a group of two or more and does not say its count |
| `kind` | says a kind ("bug", "features") the group has none of, or after a number that is not that kind's count -- "smashed three bugs" when one of the three is a bug |
| `name-dropped` | leaves out the group's name (a group of one named by its own clause may re-say the clause) |
| `name` | says a capitalised word (`dressNameRegex`) that is not sentence-initial, not the first person's `I` (`dressPronounRegex`), and not a word of the facts -- an invented milestone or card |

The line between WORK and COLOUR is the issue's (the owner's comment: "ate 20g of protein and smashed 10
bugs"): anything that names work -- a number, a ref, a name, a kind count -- must be in the facts; the
persona's colour is not checked, because a number glued to a unit (`20g`) is no number and a lowercase
word is no name. `Ate 20g of protein, then I wired up three in Team Agile (#<n>, #<n>, #<n>).` stands.

**When no model answers, the prose stands -- never silence.** No key (or no SDK): the profile's stated
decline (`No model key: set ANTHROPIC_API_KEY ...`, the sentence the 412s of the other model routes
carry) is written to the usage log as `INFO`, `spoken` is null, and the stage speaks `work`. A model that
fails, or takes longer than 30 seconds, is a `WARN` line and the same null. A reply that is not a JSON
object of id to sentence is every sentence refused. The reply is kept in memory by a hash of the facts
and the model id, so the same groups are dressed once (sixty-four standups kept); a refusal is not
kept. The model's words are never pinned by a test; the guard and the prompt are the contract, and no
test calls a model -- the route's tests stub it unavailable by default.

The gate is the house's: `features.solitaireAgile` (the route) and the key. No new switch and no new
surface: the key's row in the `Opt in by configuration` inventory (`ANTHROPIC_API_KEY`, "AI code review")
names the dressed standup among what the key turns on. The CLI never calls a model: `Standup -Grain work`
prints the prose, and the guard is in the CLI so the contract is held from both halves.

**Where the dressed text shows, and why only there**. The dress is the played view's alone, on
purpose. The guard checks a single worker sentence against the facts of the one group it speaks; it has no
rule for a whole standup. So `spoken` holds only those sentences, and everything that carries the standup as
a document keeps the derived prose, which is true by construction:

| Surface | Reads | Why |
| --- | --- | --- |
| The played view (the stage) | `spoken` for a worker the model dressed, else `work` | a sentence is heard once, in the register, and a refused one costs nothing |
| The page's Work grain, Copy, `Standup -Grain work` | `work` (the prose), never `spoken` | they are the record a person pastes or a script reads, so they must be the same words on every machine, key or not; the CLI calls no model |
| The queue's sentences, "Nothing blocked.", a mug's status sentence | the prose, always | they are never sent to the model |

What turns the dress off, and what the reader sees then. In each case the stage speaks the prose, and the
standup is complete and correct; nothing on screen says a dress was skipped.

- **No model key** (or no SDK): `spoken` is null for the whole standup. The reason, the profile's decline
  sentence, goes to the usage log as `INFO` and nowhere else; `GET /api/env`'s `anthropicConfigured` is the
  one place the response side says whether a key is there. A model that fails or takes over 30 seconds is the
  same null, with a `WARN` line.
- **The guard refuses a group's sentence**: only that group falls back to the prose, and the others in the
  same standup stay dressed. `spoken.refused` counts them, but the stage does not show the count, so a played
  standup can mix dressed and plain sentences.
- **A persona's proper noun**: the `name` guard reads a name by its capital, so a capitalised word that is
  not in the facts ("Dev-Hero") is refused as an invented name and that group is said as prose. Lower-case
  colour ("ate 20g of protein") passes.

## The tests

| Suite | Holds |
| --- | --- |
| `tkTestToolkit -Rituals` | every case of `Tests/fixtures/rituals/standup.json` and of `standup-cards.json` (the cards alone: the one worker's slots and the walk queue by card id, the source and title tables, the card reader over real folders, a not-billable card nowhere) and of `standup-joined.json` (the two sources joined: every shape's walk, each worker's slots by ref, the `Check` lines and the links, the together case's detail, work and brief goldens and their JSON round trip, no card in play reading as the issues alone, the tracker down, rounds of one id; what moved: each item's motion and commits, the counts per worker and in total, the counts and window cases' goldens, the window rule and the hash rule in words) -- `since`, the day of the year, the chair's two lines, the queue, each worker's slots by number, `empty` and the status sentence -- and the rendered text against `standup-<name>.txt` and the chair's reading against `standup-<name>.brief.txt`, byte for byte, with `Standup -Brief` typed in a fresh shell printing that reading alone and `-AsJson` carrying it; the same object read back from JSON rendering the same text; no `fakeWork` line in any case; off is no verb, no function, no bridge entry and no `Menu -All` line; **`Standup` typed in a fresh shell** with only this package's manifest and `gh` stubbed as a function answering the friday case: the text the rule renders for now, the queue, the blocks, the window, `-AsJson` round-tripping to the same text, `gh` failing and an ADO Space each a `Tracker` line with exit 0 (ADO's the contract's sentence), a local Space filling from its scratch cards line for line with `source: cards` in `-AsJson`, the GitHub Space with `source: both` and, with scratch cards in its folder, the joined standup line for line (a card of its own under the Space's tile, a `Check` line for a card whose issue is closed, a not-billable card nowhere, the hub untouched), an undeclared `-Space` a stated refusal, `-Since` widening yesterday (an issue closed a month ago said, closed; the brief's counts line naming the day) and a day after today, a word that is not a day and `-Since -Remind` each a stated refusal, `-Help`, and the hub untouched; the work grain over `standup-work.json`, the same rows `Tests/test_rituals.py` asserts -- every group (name, `by`, count, refs, phrase) of the queue and of each worker's slots, the `heads`, `keys`, `types` and `counts` tables, `standup-work-<case>.txt` byte for byte and again after a JSON round trip, `Get-P20StandupGrainText`; the prose over `standup-prose.json`, the same rows the agent asserts -- every `sentences` row, each case's queue sentences and each worker's in order, `standup-prose-<case>.txt` byte for byte and again after a JSON round trip; the dress guard over `standup-dress.json`, the same rows the agent asserts -- every row's reason, every group's prose sentence passing its own guard, every guard of `rituals.dressGuards` with a row, the `verbs` family and the two `kinds`, and the reply that names a ref the group lacks keeping the prose for that group; and typed, `Standup -Grain work` printing the rule's work text for now and `-AsJson` carrying it, `-Grain detail` the standup as it always printed, `-Grain brief` the same as `-Brief`, and a word that is not a grain or `-Brief -Grain work` a stated refusal |
| `Tests/test_rituals.py` | the agent's issues, cards and joined fills and the rendering over the same three tables and goldens (the joined goldens also against `Tests/regenerate_joined_goldens.py`'s output); the work grain over `standup-work.json` -- every group of the queue and of each worker's slots, the `heads`, `keys`, `types` and `counts` tables, `standup-work-<case>.txt` byte for byte, the JSON round trip, the work grain's own phrases; the prose over `standup-prose.json` -- every `sentences` row, each case's queue and worker sentences, `standup-prose-<case>.txt` byte for byte, the JSON round trip, the prose's own sentences, no word that is not the contract's or the tracker's; the dress over `standup-dress.json` -- every row, every guard with a row, the rows its issue asked for (a ref the group lacks refused, "20g of protein" kept), the reply that names one, and around it with the model STUBBED: the facts are the workers' group sentences and nothing else, the kinds counted from labels and a card's type, the prompt offering the `verbs` and no other family, a model that answers dressed and guarded, the same groups dressed once, no key / a failing model / a reply that is not JSON all the prose, nothing to dress asking nothing; the route with no key answering `spoken: null` and `work` unchanged, and with a stubbed model `spoken` beside `work` with `text`, `brief` and the register untouched; the route asking `gh` for `milestone` and `body` and answering `work`; `read_cards` over real folders (with each card's type, body and billable, and its `begun` day and commit hashes); what moved over `standup-joined.json` -- each item's motion and commits, the counts, the counts line opening the brief, the window rule, the hash rule; the route's `?since=` widening the window and a `since` that is not a day before today a 422 naming it; a local Space's route filling from its cards with no `gh` call; a GitHub Space's route joining its cards to its issues (`checks`, `links`, a card of its own on the Space's tile, a not-billable card nowhere, the hub unwritten); an ADO Space's `adoTracker` reason; 404 off |
| `tkTestToolkit -Triage` | every case of `Tests/fixtures/rituals/triage.json` -- the groups in order, each group's counts, context and numbers, each issue's worker, size, who, severity and deep-water, the sizes -- and the text against `triage-<name>.txt` byte for byte, again after a JSON round trip; the who rule; `Tests/fixtures/parsers/assigned-lines.json` through `Get-P20CardAssigned`; off is no `Triage`, no `Route`, no `-Assign`, no bridge entry; `Triage` typed with `gh` stubbed (who: `me`, `@<login>`, `nobody`); **`Route` typed with `gh` stubbed as a function that writes down every call**: the exact `gh issue edit` argv for each switch, alone and all four in order, `-Assign me` (`--add-assignee @me`, and under `-WhatIf` printed and not made), `-Assign <size>` the `-Size` write byte for byte, `-WhatIf` writing nothing, the two moves printed, every refusal exit 2 with one `Error:` block and no write, the hub untouched; `-Assign` on a card -- the `**Assigned:**` line above `**Created:**`, LF and CRLF kept, no BOM, an unchanged card not written, the sizes from the repo, a local Space's card taking `-Assign me` alone, and its refusals (a size with no repository to read labels from among them) |
| `Tests/test_triage.py` | the agent's grouping, who and text over the same table and goldens, the goldens the regeneration script's; the route's `gh` calls (with `assignees`, then `gh api user`); a viewer `gh` cannot name; ADO and tier below 1 a `Tracker` line; 404 off |
| `tkTestToolkit -StartWork` | the hand-off block, typed in a fresh shell over a scratch hub built from `Tests/fixtures/start-work/`: off is no verb and no bridge entry; `StartWork 23A3` is `expected-card.md` byte for byte, and so is the card in CRLF, the id in lower case and the full filename; `39` never assembles `Task139`; a `how-we-work.md` switches section one's heading to its path; issue 41, which no card carries, is `expected-issue.md` with one `gh issue view`; `-Prompt` absolute and package-relative; a partial name named in a terminal and refused for a non-interactive caller; and every refusal exit 2 with one `Error:` block and the hub untouched -- no row for the kind (naming `startWork.prompts.Meeting`), a row whose file is missing, a `-Prompt` that is no file, no id, nothing matching, an archived card, a closed issue, a pull request, an Azure DevOps Space, an undeclared `-Space` |
| `Tests/test_bridge.py`, "StartWorkThroughTheBridge" | `StartWork` in the bridge's table with Team Agile on and `rejected` with it off; through the bridge, `expected-card.md` byte for byte; a refusal `status: error` with the verb's sentence |
| `web/src/modules/solitaireAgile/StartWorkBox.test.tsx` | the copy box: one `StartWork` call, `expected-card.md` shown verbatim with its head as the title, Copy copying exactly the block, a refusal shown as the verb's sentence with no Copy, the agent away said so |
| `tkTestToolkit -Consts`, `Tests/test_consts.py`, `web/src/shell/consts.test.ts` | the `startWork.text` headings; the `rituals` values (`triageRoute`, `grains`, `numberWords`, the four `work*Regex` patterns, the `work*` phrases and the `prose*` words among them, the dress's `dressGuards` and four `dress*Regex` patterns, and what moved's `motions`, the `itemMotion`, `motion*`, `commit*` and `counts*` words), stated from all three halves; `{n} to walk`, `Nothing blocked.` and `Yesterday I closed` never retyped in the CLI's scripts or the agent; `Waiting on you`, `nothing in flight` and `Routed to` never retyped in the CLI's scripts |
| `web/src/modules/solitaireAgile/StandupPage.test.tsx` | the page over the shared fixture and goldens (above); a list row's **Start work** making one `StartWork` call with the issue's number (a card's row by its id), and none before a row asks; the counts line the first line at the top of the page, and an item's motion in the text; the grain: three tabs from `rituals.grains`, Detail by default, Work showing `work.text` (`standup-prose-friday.txt`, the prose) verbatim and Copy copying it, Brief the brief as the body once, the choice remembered by the browser, a stored word that is not a grain read as Detail |
| `web/src/modules/solitaireAgile/stage/standupDeck.test.tsx` | at the work grain, spoken as prose over `standup-prose.json`'s `friday`: the queue's sentences as one Say line each, Opus's and Fable's sentences as the agent wrote them with nothing for an empty slot, an empty queue the contract's sentence, the mug unchanged, the tracker's line whatever `work` says; dressed, from `standup-dress.json`'s reply: a worker in `spoken` speaking and showing its spoken sentences, a worker not in it its prose, `spoken: null` the prose, the queue and the mug never dressed, the slide ids unchanged; and the played deck built from the shared fixture's `friday` and `no-tracker` cases: the slides in order with their ids, the plates, the Say lines, the mug on Sonnet, nine tiles and the register on every slide, reduced motion; the deal of workers onto seats |
| `web/src/modules/solitaireAgile/stage/StandupPlay.test.tsx`, `web/src/modules/deck/engine/DeckPlayer.audiobook.test.tsx`, `web/src/modules/deck/GeneratedDeckHost.mute.test.tsx` | the mute, the played route's loading, error and Suitcase states; the audiobook hint at desktop width with prev and next, the browser voice, and a deck without the hint untouched |
| `tkTestToolkit -Environment`, `Tests/test_surfaces.py` | its inventory row has its question; the Space's answer over `Tests/fixtures/how-i-work/table.json` -- every row and every gate row -- and, typed in a fresh shell with the switch on, a GitHub Space answered with agents (`on`, `Standup` a verb), one nobody answered (`not configured`), an Azure DevOps Space and one with no tracker (`off`, derived, no verb), each with the line that changes it, and the question naming the Space |
| `Tests/test_how_i_work.py` | the agent's half of the same table; `load_config` serving the gated flag and `howIWork` with the switch as set, Space by Space, a local patch answering too, and the routes' 404 naming the answer or the switch |
| `tkTestToolkit -Config` | `spaces.<slug>.howIWork=agents -Hub` lands on the Space's hub entry and nowhere else; `team` and an unknown answer are stated refusals naming `alone` and `agents`; `-Unset` takes it off |
| `web/src/shell/HowDoI.test.tsx`, `registry.solitaireAgile.test.tsx`, `web/src/shell/scenarios.test.tsx` | How do you want to work in \<Space>?: the three radios in their words, by tracker -- GitHub two live and Azure disabled with its reason, Azure DevOps and no tracker selected and locked with theirs; a pick writing `spaces.<slug>.howIWork` with `-Hub` through the one writer; the Saving state -- the pick at once, `Saving…`, `aria-busy`, the others locked, all gone on success; a refusal reverting; the line when the switch is off; only `With agents` mounts the tab |
| `tkTestToolkit -Menu` | each verb's description, category and three-places switch parity -- the module's verbs held by the same script / wrapper / usage check as the core's, whether or not the flag is on |

**By hand**, in a GitHub Space answered with agents whose repo has worker labels: `tkStandup` lists every open `verify-close`
issue under `Waiting on you`, each worker label as a block, and an issue closed this morning under
Yesterday; `tkStandup -AsJson` parses and its `text` is the same lines; with the flag off, or in a Space
answered alone, `tkStandup` is not a command. From there, a Space with no tracker (`tkStandup -Space demo`
on the sample hub): `tkStandup` names the Space as
the one tile, a card in Code Review under `Waiting on you` and `Today`, and a card archived today under
`Yesterday`.
not a command. `tkTriage` shows the issues in no milestone first; `tkRoute <n> -Size opus -WhatIf`
prints one `gh issue edit` and changes nothing (VERIFY.md, Gate 12, "Triage and Route, against a real
repository", is the real write).

## Known gaps

- **Only the played view is dressed** (why, and what the reader sees when it is off, under
  [the agentic layer](#the-agentic-layer), "Where the dressed text shows"). `spoken` is the agent's and the stage's: `Standup -Grain work`
  and the page's Work grain show the prose, Copy copies it, and the queue's sentences, "Nothing blocked."
  and a mug's status sentence are never sent to the model. The decline when no key is set is written to the usage
  log, not into the response -- `spoken: null` says only that nothing was dressed, and `GET /api/env`'s
  `anthropicConfigured` says whether a key is there.
- **The guard reads names by their capital**. A capitalised word that is not in the facts is
  refused, so a persona's proper noun ("Dev-Hero") sends the prose instead, and an invented name written
  in lower case is not caught; numbers, refs and kind counts are checked exactly. A group whose own name is
  a kind noun ("Bugs") with no item of that kind can never be dressed -- its prose fails the kind guard too.
- **The dress is remembered in memory**: sixty-four standups by a hash of the facts, so an agent
  restart asks again, and a reply the guard refused is kept like any other (the same groups are not
  re-asked until they change).
- **Triage's milestones are the Space you are in.** The page's picker reads `GET /api/milestones`, which
  is the active Space's; the page itself asks about the active Space too, so the two agree, but neither
  takes another Space's slug yet.
- **The played view is a first cut.** One tile a worker label: "a worker is many" (`QA DEV (Opus 1)`)
  waits on the agent half knowing its running instances. The week's seat is always ghosted, and the
  tracker's lights only to say it could not be read. No neural voice (V2's `/narrate`); the browser's
  voice is whatever the machine has, and an authored fifteen seconds a tile is not imposed -- a slide
  lasts as long as its lines take to read, plus the engine's dwell. No Media Session (lock-screen play,
  pause, next). The nonsense register's door is not drawn on the stage.
- **Not on Azure DevOps, by design.** An ADO Space answers `rituals.text.adoTracker` on its `Tracker`
  line (D-TA19: ADO is the human team's board, and its standup is the one the team holds). A local Space
  fills from its cards.
- **A linked card follows its issue, even to nowhere.** A card whose id is an issue's number adds no
  row of its own ([the join](#the-join)), so when that issue is open and no worker label routes it, the
  issue is in no slot and neither is the card's work: the card's lane is in `links[]`, but the text says
  nothing. Give the issue a worker label and it shows.
- **The work grain's nouns are the tracker's own words**. A design note is named from its file stem
  (`team-agile.md` is `Team Agile`), not from its heading, which the read does not fetch; a
  `> GitHub:` thread outside the read (closed long ago, another repo) is named `#<n>`; a card's type
  noun is as its heading spells it (`Bug, two closed`, not "two bugs"); and the common stem is lexical --
  two titles that mean the same work but start with different words are two groups. The prose
  says these nouns as they are: `#<n>` for a thread the read does not hold (`I'm also on two more:
  #<n> and Design lifecycle L3.`), `one in Bug` for a card's type.
- **The prose reads no age, no pull request and no assignee**. The issue's grammar names more
  facts than the read carries: "blocked" also means a review older than N days, and "yesterday" also
  items that moved to review since the last standup. Nothing new is read from the tracker, and the read
  has no time an issue entered review and no age, so *blocked* is the blockers slot (an open, routed
  `verify-close` issue -- waiting on your walk), *yesterday* is the closed-in-the-window slot, and a
  `blocked` label is not read. A clause is the title's head as written -- not lower-cased, so a title
  that starts with a capital keeps it (`#<n>, Rename the slug`).
- **An issue alone never says `started`.** The issue read carries no time its work began, so an issue
  with no card is `closed` or `in progress` ([what moved](#what-moved-and-the-window)); `started` needs a
  card. A card's commits are every bullet it carries, not only the window's -- a bullet has no date -- so
  a card worked over weeks counts all of them the day it closes.
- **The counts are not spoken on the stage.** The counts line is the page's and the brief's: the played
  view speaks the work grain, whose dress guard holds every number to its group's own, so velocity is
  read, not heard.
- **A window keeps the slot's name.** Under `-Since` the `Yesterday` slot holds the whole window; the
  counts line names its first day, the brief says `<n> closed`, and the detail and work grains still say
  `Yesterday`.
- **A card has no worker but the engineer.** A local Space's standup is one tile; a card's type is not a
  worker, and a card cannot be a blocker (there is no walk label on a card).
- **The card read is every file in `archive/`.** Each archived card is read for its `**Closed:**` day on
  every standup; a hub with thousands of archived cards pays for it.
- **`decide` and `look` are always empty.** Their labels are an open item of the spec; only `walk` is
  filled.
- **One repo per Space.** A Space spanning several repos says so on its `Tracker` line rather than
  merging them.
- **500 issues and 500 labels.** Both reads are capped at 500; a repo past that loses its oldest
  issues from the read.
- **No reminder yet.** `Standup -Remind` and Organize's bell are V1.
- **A live refusal reads differently in the two halves.** The fixture pins the `Tracker` line only for
  the reason it is GIVEN; the sentence each half writes for a live failure -- a Space that is not GitHub,
  a tier below 1, `gh` not answering -- is its own. The Azure DevOps sentence is now the contract's
  (`rituals.text.adoTracker`, both halves); the rest are not yet, and if they should match they get a key
  in `consts.json` `rituals` the same way.
- **Several repos in one Space.** The verb says so on its `Tracker` line; the route merges labels by name
  and concatenates issues, and fails the whole read if any repo's read fails. Issue numbers from two
  repos could collide. Both are M0 choices; one rule belongs in the contract.
