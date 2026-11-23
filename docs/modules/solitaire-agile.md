# Team Agile -- the add-on, end to end

> **Three names, on purpose**: **Team Agile** is what the person sees -- the
> tab, the menu heading, the settings question. **`solitaireAgile`** is the module's id and flag, the
> engine's name, and it stays in every identifier, path and key. The **Ritual Engine** is the
> generator inside it that turns the tracker into a ceremony.

**Team Agile is a team's own rituals, with the real tracker as the board and a cast that is not
people.** The engineer is the bottleneck, not the agents, and the one thing this add-on exists to show
is **what is waiting on the human**. Its first ritual is the **standup**: the human's queue at the top,
then one block per worker -- Fable, Opus, Sonnet, whatever the Space's labels route to -- with
yesterday, today and blockers, each line a real issue with its number, or two made-up items when a worker has nothing on the tracker -- what the day held around the
work ("Fought the VPN and certificates most of the day; I'm in now."), never anything the tracker would show. The generator is the **Ritual Engine**. The contract is
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
7. [The loop, as a drive-through](#the-loop-as-a-drive-through)
8. [StartWork: the hand-off block](#startwork-the-hand-off-block)
9. [The team size: who is in the room](#the-team-size-who-is-in-the-room)
10. [The suggestion: one next move, derived](#the-suggestion-one-next-move-derived)
11. [The PM Corner: the line, the chevron, the confetti](#the-pm-corner-the-line-the-chevron-the-confetti)
12. [Milestones: the tab and the award](#milestones-the-tab-and-the-award)
13. [The file shape, and how a standup is read](#the-file-shape-and-how-a-standup-is-read)
14. [The tests](#the-tests)
15. [Known gaps](#known-gaps)

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
`Standup`, `Triage`, `Route`, `StartWork` or `OrgChart` verb, no row in `Menu`, no `-Help`, no bridge entry, no route (**404, not
403**, its detail naming whichever is off), no tab, no nav entry, nothing fetched and no bytes. The one
thing visible is its NAME, in the `Opt in by configuration` block of `Menu -All` and `Env`, under the
question "How do you want to work in \<Space>?": `Team Agile module  on (chosen: with agents in <slug>)`,
`off (derived: on a team in Azure ...)`, `off (derived: alone ...)`, `off (chosen: alone in <slug>)`, or
`not configured` for a GitHub Space nobody has answered -- each with the line that changes it.

**The org chart rides this switch, and that has a consequence worth saying plainly.** `OrgChart`
([`docs/hub/org.md`](../hub/org.md)) reads one hub file, `org.json`, which is the engineer's and sits at the
hub root -- but the view of it is Team Agile's, so in a Space where Team Agile is off (the switch is off, or the Space is
answered `alone`, or it is on Azure DevOps or has no tracker) there is **no `OrgChart` verb**, even with a
valid `org.json` in the hub. That is the module rule working, not a missing file: to see the chart from a
Space, answer it `agents`. The file is not hidden by it -- the inventory's `Org chart` row names it under the
question "Who sits in which seat in my org?", `off` with its reason where Team Agile is off, `not configured`
with no file, `on` with the tree's name and its seats, and `off` with the sentence when the file is there and fails its checks.

A third key rides on top, also the Space's: `spaces[].features.suggestions`, the off switch for
[the suggestion](#the-suggestion-one-next-move-derived). Unset is on wherever Team Agile is on; `false`
turns the chair's `Next:` line back to `Next: nothing is waiting on you.` It gates no verb and no route --
it only decides whether the standup carries a suggestion -- and its inventory row, `Suggestions`, says
`not configured` (on by default), `on`, or `off` (switched off, or Team Agile off in that Space), with
the line that changes it.

A fourth, the Space's too, is a number: `spaces[].features.teamSize`, **How many are in my standup in
\<Space>?** -- 3, 6 or 9, the room's windows with the chair counted, unset 9
([the team size](#the-team-size-who-is-in-the-room)). It gates nothing either: it is how many people
are in the room -- who of the Space's members are present today, and how many invented cast members
fill the seats they leave -- and so who speaks in the round. Its inventory row, `Team size`, rides
Team Agile as `Suggestions` does: `off` with `rides Team Agile, which is off in <slug>` where Team Agile is
off in that Space (the switch off, or the Space's answer not `agents`); where it is on, `on` with the
number, or `not configured` while it is unset (the room is then nine) -- each with the line that
changes it; `Config -Set spaces.<slug>.features.teamSize=<3|6|9> -Hub` is the one writer, and refuses any
other number by name.

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
| CLI | `Config/solitaireAgile.commands.psd1` + `.ps1` (five wrappers); `Scripts/Get-OrgChart.ps1` (the `OrgChart` verb: the hub, the file, the text or the response) and `Scripts/Read-OrgChart.ps1` (its one reader, which the inventory row and the suite use too); `Scripts/Start-Work.ps1` (the hand-off block: the id through `Resolve-P20CardArgument`, else the Space's issue; the Space's note or its `howIWork` sentence, `Get-P20HowIWorkSentence` in `Scripts/Resolve-HowIWork.ps1`; the kind's prompt); `Scripts/Get-Standup.ps1` (the verb: which Space, which source, the two `gh` reads or the card read, the printing); `Scripts/Standup-Rules.ps1` (the issues, cards and joined fills and the rendering, pure; the source rule; the card reader); `Scripts/Suggest-Rules.ps1` (the suggestion: the nearest milestone, the rule, the joined list as its items, the switch, pure); `Scripts/Resolve-TeamSize.ps1` (the room's size, a Space's `features.teamSize` read the one way, shared with the inventory row); `Scripts/Get-Triage.ps1` and `Scripts/Triage-Rules.ps1` (triage's read, and its grouping and text, pure); `Scripts/Set-Route.ps1` (the one write: one `gh issue edit` per switch); `Scripts/Ritual-Common.ps1` (the skeleton the three verb scripts share -- which Space, and the two-reads-to-`@{ ok; value }` gh layer Standup and Triage call; Route keeps its own gh-call shape but shares the Space resolution); the inventory row (from the psd1) and its question in `Config/settings-workflows.json`; the menu heading `Team Agile` (category `rituals`) | `Scripts/Resolve-Tracker.ps1` -- which repo a GitHub Space means, shared with every GitHub verb; the card rules a standup reads cards through -- `Resolve-CardName.ps1` (the id), `Get-PromptFileStatus.ps1` (the state, and `Test-P20CardBillable`) |
| Agent | `agent/solitaire/standup.py` and `triage.py` -- one gated router, with `suggest.py` the suggestion's rule beside them, `GET /api/ritual/standup` and `GET /api/ritual/triage`, **reads only**; `org.py`, `GET /api/ritual/org`, the org chart's reader (a mirror of `Read-OrgChart.ps1`) on the same router, which reads the hub's `org.json` and no tracker; a triage answer reaches the tracker only as `POST /api/cmd/Route`, the bridge | `space_scope` in `agent/ado/accounting.py`, the `?space=` rule `/issue-report` uses; `card_id` and the state rule in `agent/core/parsers.py` |
| Web | `web/src/modules/solitaireAgile/` -- the descriptor, the Standup \| Triage strip (`RitualPage.tsx`), the standup page, the Triage page, the hand-off's copy box (`StartWorkBox.tsx`, a `lazyPart`), the suggestion's dismiss (`suggestDismiss.ts`), and `stage/`: the cast's scenes, drawn in the refined cast (`cast.tsx`, `refined.tsx`), the room (`seats.ts`), the empty desk (`RefinedDesk.tsx`, its eight drinks and their deal in `EmptyDesk.tsx`), the generated deck and the played route | the shell; the deck engine (`web/src/modules/deck/engine/`) and its second resolver `GeneratedDeckHost.tsx`, which the played view borrows |
| Data | `Config/ceremonies.json` (the standup's slots, queue kinds, registers and `kinds` -- the bug and feature kinds a dressed sentence may count by; triage's three question slots, its severities `sev1`-`sev3`, its `deepWaterLabel` and the words of its text) and `Config/standup-vocabulary.json` (`phrasebook`, `nothing`, `nothingToday`, `excuses`, `fakeWork`, and `verbs`, the standup register's words offered to the model), read by both halves, never typed in code (D-SA2) | the model profile, `agent/core/model.py` (`ai.model`, `ANTHROPIC_API_KEY`), which the dress calls through and the PR review and the notes tidy-up share |
| Contract | `consts.json` `org.file`, the org chart's file name (read by all three halves), and `org.rolesFolder`, the roles folder a position's prompt is looked up in (`agentic/org/`, the CLI and the agent), and `rituals.orgRoute`; `consts.json` `rituals`: the route, `triageRoute`, the two data files, `workerLabelPrefix`, `walkLabel`, `labelWidth`, every fixed word of the text (the suggestion's among them, `rituals.text.suggest*`, with `rituals.suggestShapes` and `rituals.suggestExclusions`); `consts.json` `features.spaceScoped`'s `suggestions` and `teamSize`; `consts.json` `rituals.teamSizes` (3, 6, 9) and `rituals.teamSizeDefault` (9); `consts.json` `startWork.text`: the hand-off block's head line and three section headings | -- |
| Configuration | `config.default.json` `startWork.prompts`: which `agentic/` prompt the hand-off carries for each kind, set with `Config -Set startWork.prompts.<kind>=<path>` | the prompts themselves, `agentic/`, which are the package's -- the org's roles among them, `agentic/org/` ([the roles](../../agentic/org/README.md)): the intern, which drafts milestones, breakdowns, close-outs and severities for the seat it assists, is listed in the Studio only where Team Agile is on |
| Hub | nothing -- no verb writes to the hub; `Route` writes to the TRACKER; a local Space's standup READS its `current/` and `archive/`; `StartWork` READS a card in `current/` and the Space's `agentic/how-we-work.md` when it has one -- the Studio's `HowWeWork` writes it; `OrgChart` READS `org.json` at the hub root and, to check a `prompt`, the hub's `agentic/org/`, the hub's agentic folder and the toolkit's `agentic/org/`, in that order ([where a position's prompt is found](../hub/org.md#where-a-positions-prompt-is-found)) -- nothing writes either from here ([`org.json`](../hub/org.md)) | the cards, which are the card verbs' |

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
| `Standup [-Space <slug>] [-AsJson] [-Brief] [-Grain <detail\|work\|brief>] [-Since <yyyy-MM-dd>] [-Remind <HH:mm>] [-Days <Mon,Tue,...>] [-Walk]` | prints today's standup for the Space you are in, or the declared Space `-Space` names, read without switching into it. `-AsJson` prints the response the agent serves, `text`, `work` and `brief` included -- the bridge's shape and the parity test's. `-Brief` prints only the chair's reading (below) and, being a read, does not re-arm the reminder. `-Grain` picks the register of detail ([the work grain](#the-work-grain)): `detail`, the default, is the text as it always printed; `work` is the ritual's grain, spoken as standup prose ([the prose](#the-prose)); `brief` is `-Brief`. A word that is not a grain, or `-Brief` with another grain, is a stated refusal (exit 2). `-Since <yyyy-MM-dd>` widens yesterday back to that day ([what moved](#what-moved-and-the-window)) -- not `-Days`, which is the reminder's cadence; a day that is not one, or is after today, or `-Since` with `-Remind`, is a stated refusal. With nothing waiting on you, the brief's last line is [the suggestion](#the-suggestion-one-next-move-derived), and `-AsJson` carries every candidate as `suggestions` and the first as `suggestion`. The work grain is the round of the room, as many people as the Space's team size says: the workers present today, the engineer first, then the invented cast members that fill the seats left ([the team size](#the-team-size-who-is-in-the-room)); `detail` and `brief` keep every worker and never an invented one, and `-AsJson` carries each worker's `present`, each speaker's `cast` and the room's `team.size` | none |
| `Triage [-Space <slug>] [-AsJson]` | prints the Space's open issues grouped by milestone -- no milestone first, then most open first -- each milestone under its context line, each issue one line: number, title, who has it ([who](#who-takes-it)) -- `me`, `@<login>`, its worker (its size), or `nobody` -- severity or `--`, `deep-water` marked. `-AsJson` is the route's shape | none |
| `Route <n\|id> [-Size <label>] [-Assign <me\|size>] [-Milestone <title>] [-Severity <sev>] [-DeepWater] [-Space <slug>] [-WhatIf]` | answers triage's questions for issue `<n>`: **one `gh issue edit` per switch given**, in that order. `-Assign` says who takes it ([who](#who-takes-it)); on a card with no issue behind it, `-Assign` is the one switch: `-Assign me` writes the card's `**Assigned:** me` line, and `-Assign <size>` writes (or rewrites) its one `**Agent:**` line with the size's current model id. `-WhatIf` prints every write and makes none | none for an issue -- it writes the tracker; a card's `**Assigned:**` or `**Agent:**` line |
| `StartWork <id> [-Clip] [-Prompt <path>] [-Space <slug>] [-Launch] [-WhatIf]` | prints the hand-off block for a card in `current/`, or for the Space's GitHub issue `<id>` when no card carries it ([below](#startwork-the-hand-off-block)). `-Clip` puts it on the clipboard and says so in one line; `-Prompt` carries another prompt for this call. `-Launch` hands the same block to a session in a new worktree of the Space's repository, the model from the item's size, and returns with its PID and log ([-Launch](#the-launch-the-block-handed-to-a-session)); `-WhatIf` prints what a launch would run | none -- it reads. With `-Launch`, in the repository you stand in: a worktree under `.claude/worktrees/`, three `*.log` files in its git folder (`git rev-parse --git-path startwork`, never the working tree), and `/.claude/worktrees/` added to its local exclude file unless a rule already ignores it |
| `OrgChart [-Tree <id>] [-AsJson]` | prints the org as a tree from the hub's `org.json`, one line per seat -- `Position · model [space] (machine)`, indented by level; a vacant seat says `vacant`, the owner's line shows the person, a position with no seats is a pool shown once with its default-model text. `-Tree` prints another tree of the file by id; `-AsJson` prints the response the agent serves at `GET /api/ritual/org`, less the two prompt fields only the agent adds ([the shape](../hub/org.md#the-response)). The file is checked whole first, and a failing one is refused with the sentence ([what is checked](../hub/org.md#what-is-checked)); no hub configured and no `org.json` are refused too, all exit 2. A read like `StartWork`'s | no -- one file in, nothing written |

**The walk list** (`Standup -Walk`). The PC's morning as one printout: the standup's title line, then
one block per open `verify-close` issue by number, each the line the standup prints (`  Walk       #<n> <title>`) <!-- markdownlint-disable-line MD038 -- the span shows the printed line with its indent, which is the point -->
with, indented under it, the Gate 12 row of `VERIFY.md` (read from the package root) whose text names that
issue as `#<n>` -- verbatim and wrapped as the file wraps it, because it is written for a person -- or the line
`  no VERIFY row -- close on the issue's own words`. An empty list prints the title and `Nothing is waiting on you.`; <!-- markdownlint-disable-line MD038 -- the span shows the printed line with its indent, which is the point -->
a tracker that does not answer prints the `Tracker` line, exit 0. `-AsJson` carries `walk[]` of `number`,
`title`, `url`, `verifyRow` (null when no row names it) and nothing else of the standup. `-Walk` is a read, not
attending: it does not re-arm the reminder, and `-Walk -Remind` is a stated refusal (exit 2). It writes nothing.

Two `gh` reads on the Space's ONE repo (the same rule every GitHub verb uses -- a repo-grained address,
or exactly one repo in the Space's projects), and, while [the suggestion](#the-suggestion-one-next-move-derived)
is on, a third, `gh api user -q .login` -- who "me" is, best effort, the read Triage makes:

```text
gh label list --repo <repo> --limit <n> --json name,description
gh issue list --repo <repo> --state all --limit <n> --json number,title,state,labels,closedAt,url,milestone,body,createdAt,assignees
```

`<n>` is `consts.json` `ghReads` (`labels`, `allIssues` for the standup, `openIssues` for Triage), read by
the CLI and the agent alike.

`milestone` and `body` are the work grain's: an item groups by its milestone, else by the design card
its body names. `createdAt` and `assignees` are the suggestion's: an item's age, and who has it.

**Triage's reads**: `gh label list` as above, then `gh issue list --repo <repo> --state open --limit <n>
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
`local` one -- there is no issue to write, so `Route <id> -Assign me|<size>` writes ONE footer line
through `Set-P20CardLine` and `Write-CardText` -- the card's own line endings kept, an unchanged card not
written -- and nothing else. **`me` is the person**: `**Assigned:** me` (`consts.json` `stamps.assigned`),
above `**Created:**`. **A size is the model**: `**Agent:** <id>` (`stamps.agent`), under the Assigned line
when there is one, else above `**Created:**`, where `<id>` is the size's current id in the model map
(`Config/models.json`'s `current` block, `Get-P20ModelForSize`): a size is a family alias, not an id. The
Agent line means who is working it, or did. Route writes it at the hand-off; the lead rewrites it whenever
the work changes hands, and confirms it at sign-off ([cards](../hub/cards.md#the-agent-line)). A card
holds one Agent line, so a second `-Assign <size>` rewrites it, and the Assigned line is left as it is.
Route still refuses a size that has no `current` entry, exit 2, naming the map. The card is found the way every verb finds one (`Resolve-P20CardArgument`:
an id is never a partial name; a partial name from the bridge is refused). Its sizes are the repo's worker
labels on a connected GitHub Space (the list `-Size` reads), and there is no second list (D-AR10): in a
Space with no connected GitHub repository there are no worker labels to read, so a card there takes
`-Assign me` alone and `-Assign <size>` is a stated refusal saying so. A card takes `-Assign` alone; any other switch
is a stated refusal. `-WhatIf` prints the line it would write. Both halves read the lines back --
`card_assigned`, `Get-P20CardAssigned` and `card_agent`, `Get-P20CardAgent` -- as the card model's
`assigned` and `agent` ([cards](../hub/cards.md)). A card routed before this rule may carry a size on its
Assigned line; that is legacy.

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

**The `Tracker` line is one sentence in both halves.** Every reason a tracker read can fail has a key
under `consts.json` `rituals.text`, and the terminal and the page write the line from it, so
`Standup` and the Team Agile page (and `Triage` and its page) say the same thing for the same
failure. The CLI words it in `Scripts/Ritual-Common.ps1` (`Format-P20TrackerReason`), the agent in
`agent/solitaire/tracker.py` (`tracker_reason`). `Tests/fixtures/rituals/tracker-reasons.json` holds
both to one table, a row per reason, and each suite drives its own `gh` reader with the row's failure.

| Reason | Key | The `Tracker` line | Which half |
| --- | --- | --- | --- |
| An Azure DevOps Space | `adoTracker` | Azure DevOps is the human team's board, and its standup is the one the team holds; ... | both |
| The Space is not on GitHub | `trackerNotGitHub` | This Space's tracker is not GitHub -- triage reads a GitHub Space's issues. | both (triage, and the Releases tab; the standup reads such a Space's cards instead) |
| A local or archive Space | `trackerNotAsked` | This Space is local, so its tracker is not asked. | the CLI's `Triage` (the agent's tier check answers for it) |
| The tier is below 1 | `trackerTier` | The tracker is not reachable from here (tier 2). | the agent (the CLI does not probe the tier) |
| No repository | `trackerNoRepo` | This GitHub Space names no repository -- give its address a repository, or add one to its projects. | both |
| Several repositories | `trackerManyRepos` | Issue numbers are per-repository, and this board has 2: widgets, gadgets. | the CLI (the agent reads every repository) |
| `gh` is not installed | `trackerGhMissing` | gh is not installed, so the tracker was not asked. | both |
| `gh` failed or did not finish | `trackerGhNoAnswer` | gh did not answer for acme/widgets: HTTP 401: Bad credentials (...) | both; the error is gh's first stderr line, else what stopped the read (the agent names the exception, the CLI gives its message) |
| `gh` failed and said nothing | `trackerGhSilent` | gh did not answer for acme/widgets | both |
| The repository is not there for this login | `trackerRepoUnreadable` | gh cannot read acme/widgets -- it does not exist yet, or it is private to an account this gh login is not | both: gh's first stderr line holds a `ghReads.repoMissing` word |
| `gh` answered something that is not JSON | `trackerNotJson` | gh answered for acme/widgets with something that is not JSON | both |
| The reader itself raised | `trackerReadFailed` | The tracker read failed: ValueError: boom | the agent |

The rules for when a read is refused are not changed by the sentences: the agent still probes the
tier before it asks `gh`, so on a machine whose `gh` is not signed in the page can say the tier
sentence where the terminal says `gh`'s own refusal.

## The routes

| Route | Gate | Reads | Writes |
| --- | --- | --- | --- |
| `GET /api/ritual/standup?space=<slug>&since=<yyyy-MM-dd>&refresh=1` | `features.solitaireAgile` per request, with the active Space's answer applied (**404** unless the switch is on and the Space you are in works with agents; the detail names which is off); `space` scoped like `/api/issue-report` (an undeclared slug 404); `since` widens yesterday's window as `Standup -Since` does, and a `since` that is not a day, or is after today, is a **422** naming it; `refresh=1` reads the tracker again past the kept read ([below](#one-tracker-read-kept-a-minute)) | the same two `gh` reads as `Standup` (the issues with `milestone`, `body` and `createdAt`), and `gh api user` while the suggestion is on, through the same data files, kept a minute -- or, for a local Space, its cards. | nothing |
| `GET /api/ritual/triage?space=<slug>&refresh=1` | the same | `gh label list`, `gh issue list --state open` with `milestone` and `assignees`, and `gh api user` (who "me" is, best effort), kept a minute and shared with the standup | nothing |
| `GET /api/ritual/milestones?space=<slug>&refresh=1` | the same | one `gh api --method GET repos/{owner}/{repo}/milestones -f state=all -F per_page=100` per repo -- the ado core's own reader -- kept a minute ([Milestones](#milestones-the-tab-and-the-award)) | nothing |
| `GET /api/ritual/org?tree=<id>` | the same -- **404** where the module is off, the detail naming which is off. No `space`: the file is the engineer's | `org.json` at the hub root and, for each position's `prompt`, that prompt in the hub's agentic folder (`promptTitle`, `promptRef`, through the Studio's one prompt record). A missing file is 404 `missing` (or `no-hub`), an invalid one 409 with its `kind`, an unknown `tree` 422 ([the response and its answers](../hub/org.md#the-response)) | nothing |
| `POST /api/cmd/Route` | the bridge: `Route` is in the CLI's command table only while the flag resolves on -- the switch on and the Space answered `agents` | -- | what `Route` writes, and nothing else |
| `POST /api/cmd/StartWork` | the bridge, the same way: off, the call is `rejected`; a stated refusal is `status: error` with the verb's sentence | the card (or `gh issue view`), the Space's note or answer, the prompt | nothing -- with `-Launch`, what the launch writes, in the repository the agent runs in |
| `GET /api/env`, `startWorkLaunch` | none -- a top-level boolean of the shell's one round trip | whether `claude` is on the agent's PATH (D-AR13) | nothing |

No route of this module's builds the hand-off block (D-AR6): the CLI is its one implementation, and the
bridge is how the page asks for it.

### One tracker read, kept a minute

Each `gh` answer the two routes read -- a repo's labels, its issues in a state, the signed-in login, the
standup's dates read ([What moved, and the window](#what-moved-and-the-window)) -- is
kept in the agent's memory for 60 seconds (`READ_TTL_SECONDS` in `agent/solitaire/tracker.py`, the design
list's `LIST_TTL_SECONDS`), and the standup and triage share them. A second GET inside the minute -- the
standup re-mounted after attending, the Triage page opened after the standup -- starts no subprocess.
Triage's open issues are served from the standup's all-states read while that read is fresh and complete
(fewer rows than its limit, so every issue is in it; the limits are `ISSUE_LIMIT_OPEN` and `ISSUE_LIMIT_ALL` in `agent/core/config.py`, which `_gh_issues` builds its `--limit` from and `tracker.py` imports): the open ones, in `gh`'s order, to the open read's
limit, without the bodies triage does not ask for -- the rows `gh issue list --state open` would answer.
A failed read is never kept.

Three things read again: `?refresh=1` -- the Triage page's Refresh sends it; the standup page has no
Refresh, and its route takes the same parameter --, the minute running out, and any verb run through the
bridge (`POST /api/cmd/{name}`), because a `Route` moves a label and the next read has to see it. Nothing
about the answer changes: the same reads, made fewer times. Measured on the studio Space (18 open issues):
the standup's second GET 2.4 s and three `gh` calls before, under 0.01 s and none after; triage after the
standup 1.8 s and three calls before, none after.

The response is the spec's ("The M0 build contract"): `ceremony`, `register` (`real`), `asOf`, `since`, `space`,
`source` (`issues`, `cards`, or `none` when `tracker.ok` is false), `tracker` (`ok`, `reason`, and `workerLabels`: how many worker labels the tracker answered, 0 where none was read), `chair`
(`open`, `close`, and `walked` -- the walk items closed inside the window, by number, what the chair's
turn says it walked), `team` (`size`: the room's windows, the chair included -- the Space's `features.teamSize`
as [the team size](#the-team-size-who-is-in-the-room) reads it, 9 when unset), `queue` (`walk`, `decide`, `look`), `workers` (the record: EVERY labelled worker in label order, then on a GitHub or a local Space the engineer -- the card tile, always there --, each `label`, `name`, `yesterday`,
`today`, `blockers`, `empty`, `excuse` -- the empty worker's status sentence, the first of `status`, kept for a reader that knows only this field; the name is historical --, `status`, the empty worker's two made-up items `[yesterday, today]`, `[]` for a worker with something to say, and `present`, whether it is in the room today), `work` (the work grain: `queue` -- each kind's groups --,
`workers` -- the round, in seat order: the PRESENT members, the engineer first, then the invented cast members that fill the seats left, each `label`, `name`, the three slots' groups, `cast` (true for an invented member) and `prose`, its turn: `turnOpen`, its
sentences (for a slot it has nothing in, that slot's fixed line -- or, for yesterday, the open items it worked
inside the window; an idle worker's two made-up items), `proseBlockersNone` when nothing blocks it, `turnClose` --,
`queueProse`, the queue's sentences, `chairProse`, the chair's own turn (in the same frame and its
own first person -- a yesterday, a today, `No blockers.` -- never the queue's sentences again; empty
when no tracker answered), and `text`, the prose; a group is `name`, `by`, `count`, `refs`,
`phrase`), `spoken` (the dress, [the agentic layer](#the-agentic-layer): `model`, `workers` -- each
`label` and `prose`, the worker's sentences as the stage says them --, `dressed`, `refused`; null when no
model answered, and the agent's alone: `Standup -AsJson` has no such key, because the CLI calls no
model), `text` and `brief` (the chair's reading), and `counts` -- what moved in the window
([below](#what-moved-and-the-window)): `workers`, each `label`, `name`, `closed`, `started`, `inProgress`,
`commits`, and `total`, the same with `label` and `name` `""`; `suggestions` and `suggestion`
([the suggestion](#the-suggestion-one-next-move-derived)) -- every candidate in the rule's order and the
first, each `ref`, `number`, `id`, `kind` (`issue` or `card`), `shape`, `sentence`, `command` and `line`;
`[]` and null with the Space's switch off; `corner` ([the PM Corner](#the-pm-corner-the-line-the-chevron-the-confetti)),
null with it off; and `agenda` ([the page](#the-page)), `moved` and `waiting`, the agent's alone like
`spoken`. Every item has seven keys -- `number`, `id`,
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
`@consts` -- and opens on **the Agenda**, the response's `agenda` as two lanes of tiles ([the page](#the-page)).
The three tabs after it show the response's `text` verbatim: the first line (the ceremony and its date) as the
card's header, every line after it in a monospace block with its padding and line breaks kept, and each
`#<n>` the response names (the walk queue and every worker's three slots) linked to that issue's `url`.
Header, a line break and body are `text` byte for byte, and the page test says so. The tab strip is
**Agenda | Detail | Work | Brief**: Agenda first and the default, then the three grains
([the work grain](#the-work-grain)). The tab is remembered per browser (`usePersistedValue`, key
`p20.solitaireAgile.tab`), and so is the last grain read (key `p20.solitaireAgile.grain`, `Detail` the
default): Work shows `work.text`, Brief shows `brief` as the body (and drops the small brief above it),
each verbatim; a response from an agent that predates `work` shows Detail for it. Beside Play, **Copy**
(Daily's pattern: `copyText`, "Copied!" for a moment) puts the grain on the clipboard exactly as the
response gives it -- the grain on screen, or, on the Agenda, the last grain read (`text` in a fresh
browser): the same text Copy carried before the Agenda existed. The text and the brief are drawn on the
three text tabs only, never on the Agenda. When nothing waits and the Space's switch is on, the brief's last line is [the suggestion](#the-suggestion-one-next-move-derived), drawn as a row of its own with its action and a dismiss -- under the brief on the text tabs, and on the Agenda as its first line after the sentence, above the lanes. At the head of the page, above the card, sits [the PM Corner](#the-pm-corner-the-line-the-chevron-the-confetti): one line, its chevron, and, when a milestone is reached, a link to the Releases tab. The other thing
to click is **Play**, quiet, in the header (V1, below), and beside it **Team size**, the door to the room's size: it opens the settings drawer at the **How many are in my standup in \<Space>?** entry's own anchor (`spaces.<slug>.features.teamSize`, [the team size](#the-team-size-who-is-in-the-room)) -- the drawer is the one writer, so the page has no control of its own. An issue's popover names the worker it is routed to by the plate that worker wears on the stage today, `PERSONA (label)`, or the worker's own `plate` when the response gives one (`StandupPage.workerChip`, the stage's own deal), and names none for a worker out today. With `tracker.ok` false the page still draws the ritual -- the chair's lines and the
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

**Releases** is the third page, at `/solitaire-agile/releases`, and the strip reads **Standup | Triage |
Releases**. The tab was named Milestones until it was renamed, and its old address, `/solitaire-agile/milestones`,
redirects to the new one so a bookmark still lands on it. Until tag-based releases are built it still shows the
Space's GitHub milestones, and says so: the panel's subtitle and every row read "GitHub milestone". It is
[its own section](#milestones-the-tab-and-the-award): one row per GitHub milestone with its bar, and the
award dialog -- the one place the module throws confetti.

**Org** is the fourth page, at `/solitaire-agile/org`, and the strip reads **Standup | Triage | Releases |
Org**. It is a chunk of its own, fetched when the tab is first opened, and like its siblings it is there only
where Team Agile is on. It reads `GET /api/ritual/org` (`rituals.orgRoute`; [the response](../hub/org.md#the-response))
and draws the tree it is given, in the refined cast: one office a position, a row a level from the owner down,
each position centred over the ones that report to it, joined by lines. The office walls are coloured by level,
the cast-skin mock's five colours (owner, the VPs, the PM, the leads, the builders; a deeper level takes the
builders'). Each seat is a card -- a bust in the office's door and a plate under it, `POSITION · model`, with
where the seat is (`toolkit on mini`, `on laptop`) when the file says. A position with several seats, the team
lead's, is a row of cards in one office; a position with no seats is a pool, one wider card with a few faces,
`POSITION · pool` and its default-model line; the owner's seat is a person, `Owner · <name>`, with no model. A
staffed seat is in colour; a vacant one reads `POSITION · vacant` and has an empty desk in its door
(`stage/EmptyDesk.tsx`, the desk the standup's room drew before it took the refined cast)
-- the chair pushed back, the desk and a steaming mug, on the level's wall dimmed -- the size of a staffed card,
its mug picked from the seat's id so the same seat always has the same one. Over an office with a prompt is the prompt's title (`promptTitle`),
and the office is a link to the prompt in the Studio's reading room (`promptPath(promptRef)`); the owner, the
pool and a prompt the room does not list are not links. The faces are the web's choice, never the file's:
`orgChart.ts` maps a position's id to its faces, as the mock staffs it, and a position it does not name takes
its level's. With no `org.json` the page says `No org chart yet` and the agent's sentence; a file that fails its
checks (409) is said plainly too, `The org chart could not be read` and its sentence; a tree the file does not have (422, `unknown-tree`) is said plainly in
the page's own words, `That org chart is not in the file` and `The chart asked for is not one of the trees in the
hub's org.json. Nothing was drawn.`, decided by the kind and never the agent's sentence, which is the
terminal's (the page asks for no tree today, so it meets this only if that changes); no answer is `Could not read the org chart`, the one state drawn as an error: the error tone is kept for the agent being away or failing, and a thing to know about the file is not one. The page chooses no
tree, draws no `active` state and writes nothing. `OrgPage.test.tsx` and `orgChart.test.ts` draw the shared
table's charts (`Tests/fixtures/org/charts/`).

### The page

The Team Agile page opens on **the Agenda**: the standup's two questions -- what moved, and what is
waiting on you -- as tiles you can act on. Under the tab strip, one sentence says what it is:

> Here you can see the work items you can in fact kick off now, with the Work it now button.

Beside it, a **Cards | List** toggle, remembered per browser (`usePersistedValue`, key
`p20.solitaireAgile.agendaView`), cards the default. Under the sentence, when the chair has one, comes
[the suggestion](#the-suggestion-one-next-move-derived)'s row -- the same row the text tabs draw, the
line verbatim, its action and its dismiss. It is the Agenda's first line, above the lanes, and it is
where a pick that no lane carries is named: an unrouted issue, with its `route it?` and **Open Triage**.
The brief's other lines (they say "closed yesterday") stay on the text tabs. Under it, two lanes:

- **Since `<day>`** -- the standup's own window, its first day the long way (`Since Friday 23
  October`, from the response's `since`): what moved in it, the issues closed and the cards archived, as
  the board draws Done. Its tiles carry **no action**.
- **Waiting on you** (`rituals.text.queueHeading`, the brief's own phrase): a card in `current/` that is
  Active (nothing started) or in Code Review, and an open issue that is routed -- someone has it, by the
  [who](#who-takes-it) rule, and it is not someone else's -- or on the walk. The
  [suggestion's](#the-suggestion-one-next-move-derived) order, so the top tile is the pick when the pick
  can be started; an unrouted pick is not on the lanes -- the suggestion row above them names it --
  and the top tile is then the first candidate that can be started. Then what that rule sets aside as
  waiting or in flight. Each tile carries **one** button: **Work it now**, which opens the same
  hand-off box `StartWork` builds ([StartWork](#startwork-the-hand-off-block)), or, on a tile waiting on a
  review or a merge (Code Review, or the walk), **Review it** -- the card's page, or the issue on the
  tracker when there is no card.

**Readiness is not a flag.** A card is on the Agenda because it is in `current/` -- pulled from
`backlog/` by `Move -To Active` or by its first commit -- or because its issue is routed on the tracker.
A `backlog/` card never appears. A card **In Progress** is in somebody's hands, not waiting, and is not
on the Agenda at all: the board is where its lane means something.

**A tile looks like a board card and is the Agenda's own.** It borrows the board's pieces --
`BoardCover` (`web/src/modules/ado/CardCover.tsx`), and `CardName` and `CardProgress`
(`web/src/modules/ado/CardFace.tsx`), the same pieces the board's tile now draws with -- but not the
board's tile, which carries the lane drag and the action menu. An issue with no card is the same tile with
no cover and no progress, so cards and issues stand side by side from one renderer. Each tile is the
cover, the title (a card's opens its page), the ref (`#<n>` opens the issue popover; a card's id its own
surface), the progress, the one button or none, and **one line of fact with a long date** -- no lane
badge, and no relative day: no "yesterday", no "today".

| The tile | Its fact line | Dated from |
| --- | --- | --- |
| an issue that closed in the window | `Closed Saturday 24 October` | its `closedAt`, in the standup's own offset |
| a card archived in the window | `Archived Saturday 24 October` | its `**Closed:**` day |
| a card in Code Review (or an issue whose card is) | `In review since Thursday 22 October` | the card's `**Review:**` day; with none (a `PR URL:` line alone), `In review` |
| an Active card (or an issue whose card is) | `Active since Friday 23 October` | the card's `**Created:**` day |
| an open issue with no card | `Open since Tuesday 20 October` | its `createdAt` |

**The list** is the same two groups as compact rows -- the ref, the title, the fact line and the same
one button -- for those who like it.

**The agent derives it; the page draws it.** `agenda` in the response is `moved` and `waiting`, each a
list of tiles: `ref`, `number`, `id`, `kind` (`issue` or `card`), `title`, `url`, `path`, `file` (the
card's filename while it is in `current/`, what the card page opens; `""` otherwise), `lane` (`consts.json`
`status`, `""` for an issue with no card), `day` (`yyyy-MM-dd`, `""` when the record has none), `review`,
`cover`, `checked`, `total` and `progress` -- `agent/solitaire/agenda.py`, over the same read the text is
rendered from, no second `gh` call and no second folder walk. It is the agent's alone, like `spoken`:
the CLI's `Standup` prints text, and `Standup -AsJson` has no such key. The page re-derives no lane; it
words the fact (`web/src/modules/solitaireAgile/agenda.ts`). With the tracker not answering, both lanes
are empty and say so (`Nothing moved.`, `Nothing is waiting on you.`).

### The played view

**Play** opens `/deck/ritual/standup` from any of the page's tabs, the Agenda's included: the same standup, read from the same route (RTK's cache, so
nothing is fetched twice), played on **the stage** -- the Wasteland's Remote Standup, its nine tiles in
their composition, every time (D-TA17). The route is this module's,
chromeless like any deck, and it plays **with `features.deck` off**: the page, the stage and the deck
engine are one lazy chunk fetched when Play is pressed.

- **The atoms, by copy.** `stage/cast.tsx` carries the Remote Standup's `ZoomTile`, the two
  bubbles (below), the nine webcam scenes and the keyframes from a private repository, the way the trailer came over
  -- with no dependency on that repo, and without the cast's bios, dossiers and lines: every word a tile
  says is the Ritual Engine's. **The drawings are the refined cast's.** Each of the nine people is the bust
  `shared/refinedFaces.tsx` draws for the same id, the one the Org page and the landing page draw, so the
  team lead is one drawing on every tab. The props in a window -- the desk and its mugs, the terminal, the
  monitors, the flask, the treadmill and its console, the raised hand, the beanbag -- are drawn by the same
  rules (`stage/refined.tsx`): soft shapes, no outlines, one shade on the right side, light from the top left
  and one soft drop shadow, on the window's tint lit the same way. A bust stands in the box the stage has
  always given one (`Bust`), so each head is where `HEADS` says it is and the bubble's placement is unchanged;
  a readout that is text (the desk motor's, the terminal, the roadmap's) sits clear of the face. Under `prefers-reduced-motion: reduce` the stage is still: no tile pops,
  no steam rises, the speech bubble is simply there, and the thought cloud does not float.
- **Bubbles** (`stage/cast.tsx`, `stage/geometry.ts`). Two surfaces on one white ground. The **speech
  bubble** is open for the speaking tile, its tail at the speaker's FACE -- the head position each scene
  has (`HEADS` in `stage/geometry.ts`, marked in the tile as `tile-<seat>-face`; an empty desk has none).
  It is placed by the stage's own rule, not by the popover engine, because the rule is about what it must
  keep off: a bubble may lie over another window's background or props, but **never over any face** --
  another member's, the chair's or its own speaker's -- **nor any plate** (the name at every window's
  bottom left), nor its own window's `...` button. The stage measures the grid of windows (the title
  row is not part of it), every face (`faceBox`, the head and the top of the shoulders around its anchor)
  and every plate, and `placeBubble` tries the sides in order -- above the face, then beside it (after,
  before), then below -- sliding along each to clear the keep-out areas, inside the grid with an 8px
  margin (`BUBBLE_MARGIN`); when no side is clean it takes the side with the least overlap. The tail sits on the edge that faces the
  speaker, at the head. The bubble is laid out unseen until it is placed, and placed again when the
  stage changes size. The played stage is drawn for desktop browsers: from 576px wide up it is laid
  out at its own size, never scaled, and the bubble placement is not held at phone width, where the deck
  engine shrinks the whole stage with a transform. `stage/geometry.test.ts` holds the rule as a table over the nine windows and a
  short and a long turn at the stage's usual size: every row clean. The bubble is small: as wide as its
  lines need, up to 260px and never wider than its window (`SPEECH_MAX_WIDTH`), its text 0.6rem, and it
  shows a turn's **first four lines**, the last ending in an ellipsis (`SPEECH_MAX_LINES`), no scrollbar.
  The voice (the slide's Say lines) says the whole turn.
  The **copy panel** beside the stage (the deck engine's right-hand column, what the stage leaves) does not repeat them: it is the
  speaker's character -- the title, the persona and the motto, the Wasteland's own words carried in
  `CAST` -- and, on a worker's slide, the worker's label, the one real noun. The motto is who the
  character is, never a status, so nothing on the slide claims work the tracker did not say.
  The **thought bubble** is unchanged: the same surface as a cloud with the dotted trail, opened by the
  tile's `...` button (a real button, so click, Enter and Space), closed by Escape and by the deck
  advancing (a thought is keyed by its slide, though its window is not). It lists the detail behind the sentence -- each
  slot with its items, each `#n` an issue popover -- on a member with work and on the chair with a
  queue; an idle member and an empty desk have none. The speech bubble's place keeps off its own
  window's button.
  The voice reads the slide's notes, never either bubble, so narration and duration are unchanged.
- **The room stays mounted for the round.** Every slide carries one `contentKey` (the deck engine's opt-in,
  `docs/modules/deck.md`, "Audiobook decks"), so the engine keeps the stage from slide to slide, and the
  windows are keyed by cast id alone. A window is one DOM node for the whole round: it plays its entrance
  (`rs-pop`) once, when the room first loads, and its steam, bob and smoke are never restarted. When the
  speaker changes, only the windows of whoever stops and starts change -- the frame, the called mark, the
  bubble. A speech bubble and a thought are keyed by their slide, so each bubble arrives with its own
  entrance (`rs-bubble`) even when one window speaks on two slides running, and is measured and placed for
  that slide alone.
- **Who is talking** (`stage/cast.tsx` `ZoomTile`, `stage/standupDeck.tsx` `Tile`). A tile has one of
  four looks, and **every window is in full colour** on every slide: nothing on the stage is black and white
  and nothing is dimmed, so a look is a frame, a mark or a dot, never a filter. One tile is framed, ever.
  **Speaking** -- its bubble is open (`data-speaking="true"`,
  `data-look="speaking"`): a 3px outline in the active theme's brand primary (`outlineOffset: -3px`, so
  the grid does not move; its own `stage-frame` element over the tile, because an outline on the tile itself is
  painted under the picture), and the green name-dot. **Called** -- on a call slide, the member the chair
  has just named (`data-look="called"`): its green dot, and the **called mark** -- a 3px
  dashed ring in the speaker's green, inset 7px from the window's edge (`stage-called-mark`) -- but no
  frame and no bubble. The mark is what tells the called window apart, on any tint; the slide has one
  window framed and one marked, and you see who is about to
  answer. **Named** -- a face
  that is there and not speaking: the chair and every other present member (`data-look="named"`): its green
  dot, the signal light, and neither frame nor mark. **An empty desk** -- a grey
  dot, never lit (`data-look="ghost"`, the look's name from when it was dimmed): the drink on the desk is
  what says nobody is there. The frame's colour is the stage's own green, `pf.green` -- the colour of the register badge at the top right and of the speaker's name-dot -- handed to the tiles as the CSS variable `--sa-speaker`. It is never a theme's brand token: the room is the engine's default dark whatever the app wears, and the frame is the same on every theme. There is no pulse, so reduced motion has none to
  still.
- **The room** (`stage/seats.ts`). Nine windows, always (`ROOM_WINDOWS`; `MEMBER_SEATS` is the room less
  the chair's window). The windows, their plates, the chair's window, the windows three labels keep and
  the engineer's are the shared room, `consts.json` `rituals.room`, which the stage reads and never
  types: the terminal's `Standup` and the agent seat the same room from it
  ([the team size](#the-team-size-who-is-in-the-room)). The chair keeps its own window, `CHAIR · PM`. The
  other eight are the member windows, in grid order -- `DEV-HERO`, `OPS-DEV`, `MINIMALIST`, `NEW HIRE`,
  `AI VIBEMANCER`, `ULTRAWIDE OVERLORD`, `QA ALCHEMIST`, `DESIGNER`. The stage seats **the round** the
  response carries (`work.workers`): the engineer first, the labelled workers with work, the labelled
  workers with nothing routed, then the invented cast members that fill the seats the size still counts,
  and they speak in that order whichever window each sits in. A member is plated `PERSONA (label)`, or by
  the worker's own `plate` when the response gives one (a member a card names whose family keeps no window:
  `GROK`); an
  invented cast member sits in the window its cast id names and wears its persona alone, `OPS-DEV`. A
  window is a member's own when its label keeps it (`KEPT_WINDOWS`: `fable` sits in `DEV-HERO`'s window,
  `opus` in `AI VIBEMANCER`'s, `sonnet` in `MINIMALIST`'s) or is itself a cast id, so a persona and its
  tagline never change with who else is in the room. The engineer -- the member the Space's own slug
  names, where cards fill the standup -- takes the engineer's window when no member owns it. Every other
  seated member takes the free windows in grid order, the engineer first and then the labels in the
  response's order. A window whose owner is in the response but out today stays empty, so no other face
  takes it and nobody moves when that member is back; only when the free windows run out does a member
  take such a window, so nobody seated is ever dropped. A kept window whose label the Space does not have
  is an ordinary window. No window is a role, and a face does not change window because its work changed.
  A response with no work grain, or whose round does not account for exactly its present workers (an
  agent that predates the room), is seated by its record: the workers it marks `present` -- every worker
  from an agent that predates `present` -- in its order, capped at the room. **Every other window is an empty desk** (`stage/RefinedDesk.tsx`): a
  flat-backed chair pushed back, a shut laptop and a steaming drink on that window's tint, in full colour --
  the room's light is off, which is a wash in the drawing and no filter -- plated `EMPTY DESK`, never lit,
  never a bubble, never a slide. The drinks are the eight the stage has always had (`stage/EmptyDesk.tsx`
  `MUG_LOOKS`: classic, tall, enamel, straw, espresso, stripes, heart, teabag), and the steam moves as it
  always has. The desks in one room each get a different mug, dealt by
  `dealMugLooks(day, desks)` in window order, `day` the standup's day of the year (1-based, from `asOf`'s
  own date, as the fill counts it), so the same day always deals the same mugs. An absent worker is silent
  and unseen: no window, no line, no name. The web never reads the team-size setting: a Space sized three
  draws two speakers and six desks because the response's round has two. Grid order, top row first:
  `DEV-HERO`, `OPS-DEV`, `MINIMALIST`; `NEW HIRE`, `AI VIBEMANCER`, `ULTRAWIDE OVERLORD`; `QA ALCHEMIST`,
  the chair, `DESIGNER`.
- **The script** (`stage/standupDeck.tsx`). The round of the room, in this order: the **board** (the
  plate is the standup's first line; the chair reads what is waiting on you, or -- the tracker's alarm --
  the tracker's reason; no other window lights for it), the **chair** opening with its phrasebook line,
  then for each present member in seat order **the call** -- the chair says the member's name and a full
  stop (`Fable.`, from the worker's name), the member's window named, listening -- and **the turn** -- the
  member's window lit and speaking --, then **the chair's own status**, last, and the chair's phrasebook
  **close**. The call is a slide of its own because a slide has one speaker: the chair speaks it, and the
  member answers on the next. Every slide carries the ritual's plate and **`REGISTER · REAL`** (D-TA13).
  The deck plays at the **work grain**, spoken as prose: a bubble is one line a SENTENCE, and the voice
  one `Say` line a sentence -- `Good morning.`, `Yesterday I closed two in Team Agile (#<n>, #<n>).`,
  `No blockers.`, `That's it for me.` -- read as written from the response's `work.queueProse`, each work
  row's `prose`, the member's turn in the frame the text says it in, and `work.chairProse`, the chair's
  own turn -- or, for a worker the model dressed, that worker's `spoken` sentences: the stage reads
  `spoken` when present and `work` otherwise ([the agentic layer](#the-agentic-layer)) -- so the
  engine's narration and its length estimate work as for any deck; an empty slot says nothing, an empty
  queue is `Nothing is waiting on you.` **A member with nothing gives status too** (D-TA11, as it now
  reads: the mug is a window with nobody in it, and an idle member keeps their face): its turn is its two
  made-up items, yesterday then today, in the same frame, so the stage says what `Standup -Grain work`
  prints. The chair's status from an agent that predates `work.chairProse` is the board again, as the
  stage closed before; with the tracker down its turn is empty, as the text prints none, and the chair
  has the board, the open and the close. An idle member from an agent whose `prose` has no turn for it
  says its made-up items as they came (the pair, or the one sentence of an agent older still), and a
  response without `work` plays one `Say` line a slot, item by item. **No face is silent**: every window
  that draws a face has a slide where it speaks. The narrator reads a slide's title before its lines, so
  a call and a turn carry no title: the call is heard as the chair saying `Fable.` and nothing else, and
  the turn after it begins `Good morning.` -- the name is said once. Slide ids are
  `standup-<date>-<part>` -- `queue`, `chair-open`, `call-<label>`, `<label>`, `chair-status`,
  `chair-close` -- and survive a rebuild.
- **Audiobook mode, at any width.** The deck sets the engine's `audiobook` hint (docs/modules/deck.md,
  "Audiobook decks") and its host opens it in Audiobook mode, narrating, on the viewer's bar, with
  **previous and next either side of the play ring**, so a tile can be skipped without leaving the
  mode; the gear's **Voice** sheet turns it to Paging and back, for as long as the room is open.
- **The voice.** No clip can exist for a sentence the tracker wrote this morning, so the browser's
  `speechSynthesis` reads each slide's title and `Say` lines (D-TA7's fallback, V1's only voice); with no
  speech API the slide lives for its estimated read time and moves on, silently.
- **Mute**. The viewer's bar's sound button (at any width, at the bar's right end) -- and the
  **Voice** sheet's Narration switch, which is the same setting,
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
counts; under a wider window a worker's closes are `<n> closed`, not "closed yesterday"); then one line about
what the brief could not read, chosen by the tracker, never by who is in the room (it takes "no worker labels" from the tracker's own count, `tracker.workerLabels`, not from who is seated, so a member a card seats does not hide it): on a GitHub Space with worker
labels, the in-flight sentence while the running state is unbuilt, because every routed issue reads as open; on one
with none, `No worker labels in this Space.`, after the engineer's line, since nothing is routed for the sentence to
describe (the engineer is always a member, so the list is never empty); and "Next", the rule -- the kind
with the most items (ties go to the ceremony's queue order) and who they wait on. With nothing waiting,
"Next" is [the suggestion](#the-suggestion-one-next-move-derived) where there is one, else
`Next: nothing is waiting on you.` A GitHub Space's
walks are `verify-close` issues, so they wait on "the PC"; a local Space's cards in Code Review wait
on "you", and say neither "all on the PC" nor "none in flight". A joined GitHub Space reads as a
GitHub Space, except that a card on its walk puts the walks on "you" (and drops "all on the PC"), its
card tile says no "none in flight", and its `Check` lines follow the workers. With the tracker not
answering, the brief is the one `Tracker` line.

## The loop, as a drive-through

The whole module is a drive-through, and that is the shortest way to explain it. You pull up to the
menu board, give your order at the speaker, the ticket goes to the kitchen, the kitchen cooks without
you, and you collect at the window. Each piece is a verb or a page:

| The drive-through | Team Agile |
| --- | --- |
| The menu board: what the house serves, what is waiting | the standup and triage: `Standup`, `Triage`, their routes and tabs |
| The speaker: you give your order | `Route`: a label, a size, an assignee on the issue. That is the ticket |
| The ticket, carried to the kitchen | `StartWork`: the block, the card and the prompt, handed to a cold agent. The page's Start button is the speaker: it copies the block through the bridge, or starts the session where [the launch](#the-launch-the-block-handed-to-a-session) is on |
| The kitchen, cooking without you | the launched session, in a worktree of the Space's repository, on the machine running the agent |
| The window: you drive up and collect | the pull request. The card moves to Code Review when its PR URL lands, and the tracker carries the rest |

So pressing Start on the page is not a second workflow beside the verbs. It is the speaker on the same
lane. What the picture also shows is the piece the lane does not have yet: nobody calls your number. The
session is detached, its result is a log and a pull request, and the page does not say that an order is
up; you find out by looking. That window screen, one line per order, cooking or ready, is a
[known gap](#known-gaps).

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

**Section one, how we work.** The Space's own note, `<promptsFolder>/agentic/how-we-work.md` in the hub
(`consts.json` `startWork.howWeWorkNote`), when it has one -- the heading then names that path
(`widgets/agentic/how-we-work.md`). The Studio's `HowWeWork <slug>` writes it for a Space worked with
agents ([the hub's `agentic/`](../hub/README.md#how-we-work----a-spaces-agentic)); a `how-we-work.md` a
person put at the Space's folder root, where this section looked before that verb existed, is still read
when the written one is not there. Until a Space has one, it is ONE sentence derived
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

**The page.** On the standup's [Agenda](#the-page), every tile waiting on you to start it -- an issue or
a card -- carries **Work it now**. It opens the copy box (`StartWorkBox.tsx`, a `lazyPart`: its chunk is
fetched the first time a tile asks), which makes **one** `POST /api/cmd/StartWork` with the item's number or id and shows the
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

### The launch: the block, handed to a session

`StartWork <id> -Launch` is the secondary action (D-AR12): the same block, handed to a session that
starts the work where it gets done -- a worktree of the Space's own repository, which is the shape a
crew builder is given. Run it from a clone of that repository:

```text
> tkStartWork 4 -Launch
Launched Issue #4 on sonnet: PID 48213.
  worktree: /src/widgets/.claude/worktrees/startwork-4-20261021-142807
  log:      /src/widgets/.git/startwork/startwork-4-20261021-142807.log
```

It checks, in this order, and each check that fails is a stated refusal (`Error:`, `Hint:`, exit 2) that
starts nothing:

1. **The repository you stand in is the Space's**: `git rev-parse --show-toplevel` answers, and its
   `origin` (https or ssh) names the same `owner/repo` as the Space's GitHub address. A Space with no
   GitHub address has nowhere to launch.
2. **`claude` is on the PATH** -- the optional surface `startWorkLaunch` below. The hint says the block
   works without it.
3. **The item has a crew size**, read the way the rituals read who has it ([who](#who-takes-it)): an
   issue's labels; a card's worker -- its `**Agent:**` line's family, else its `**Assigned:**` line -- else a size in its `Tags:`, else -- for a card whose id
   is an issue number, which `Route` sizes on the tracker -- that issue's labels. The size label IS the
   model on the command line: `sonnet` or `opus`. **Never a Fable builder**: `fable` is the owner's own
   seat (D-AR10, `rituals.suggestOwnerSeat`) and is refused, as are an item assigned to you (`me`), an item
   with no size, and a size with no model; the hint is to route it (`Route <id> -Assign sonnet`) or work
   it yourself from the block.
4. **`git worktree add --detach .claude/worktrees/startwork-<ref>-<stamp>`** succeeds (a repository with no
   commit has nothing to check out).

Then it writes the block to `startwork-<ref>-<stamp>.block.log` **in the repository's own git folder**
-- `git rev-parse --git-path startwork`, so `.git/startwork/` in a clone and `.git/worktrees/<name>/startwork/`
from a linked worktree -- and starts `claude --print --model <size> --output-format stream-json --verbose`
in the worktree **with that file as its stdin**: `claude --print` reads its prompt there, and a prompt of
many lines does not cross a joined command line whole on any host. Its output goes to
`startwork-<ref>-<stamp>.log` and its stderr to `.err.log` beside the block. None of the three is ever in
the working tree, whatever the repository's own `.gitignore` says: the block is the card whole and the log
is the session's stream, and the repository is any product's. **The block is removed once the session has
it open**: on macOS and Linux the launcher's session leader unlinks it right after opening it, so the
session reads every byte through its descriptor; on Windows the launcher removes it as soon as Windows
allows, and where a running session still holds it, the launch says so and the next launch removes it
after that session ends. A launch that fails to start removes it at once. The worktrees folder is kept
out of `git status` by one line, `/.claude/worktrees/`, added to the repository's LOCAL exclude file
(`git rev-parse --git-path info/exclude`, never the committed `.gitignore`) unless a rule already ignores
it. It prints the PID, the worktree and the log, and **returns without waiting**. `-WhatIf` runs every
check and prints the exclude line it would add, the worktree add, the block file, the exact `claude`
command and the log, and adds, writes and starts nothing. `StartWork` without `-Launch` writes nothing
anywhere, as before. `-Clip` with `-Launch`,
and `-WhatIf` without it, are refused. The session's environment is the shell's, minus any
`TEAMS_WEBHOOK_*`: a session never sends.

**The launcher is `Scripts/Start-Detached.ps1`'s `Start-DetachedProcess`, and nothing else**, because a
session is a long-lived child: started any other way on Windows it inherits the caller's pipes, and
`pwsh -c 'tkStartWork <id> -Launch' | cat` would wait for the session to end ([the command reference,
"Both launchers return, including through a pipe"](../CLI.md#the-other-two-halves)). Through it, the
call returns as soon as the session has started -- on every host.

**`startWorkLaunch`, the optional surface** (D-AR13). DERIVED, like the Teams webhook's row: `on` where
`claude` is on the PATH, `not configured` otherwise, named by `tkEnv` and `tkMenu -All` as **StartWork
launch** with its question, "Can it start the work in a session for me?". `GET /api/env` carries the
same answer as a top-level boolean, `startWorkLaunch`, so the page offers a launch only where it would
work; the copy box works either way. The standup's delegate suggestion reads the same answer
([the suggestion](#the-suggestion-one-next-move-derived)): where the launch is on, its Next line ends in
`StartWork <n> -Launch`.

**Proving it.** `tkTestToolkit -StartWork` builds scratch clones (the Space's, with a commit; another
repository's; the Space's with no commit) and puts a stub `claude` first on the PATH: `-WhatIf` and its
output; the model from each place a size is read; every refusal above, `fable` on a card and on an issue
and no size among them, each leaving no worktree and no log. Off Windows it launches for real: read
through a pipe, the verb returns while the stub session lives on, and the log's first message is the
block `StartWork` prints, whole. What only Windows or a real `claude` can show is in `VERIFY.md`, Gate 12
("StartWork -Launch").

## The team size: who is in the room

The standup is a room of nine windows, the Zoom grid, and the chair (the PM) always has one. The
Space says how many people are in it: `spaces[].features.teamSize`, one of **3, 6 or 9**
(`consts.json` `rituals.teamSizes`), the chair counted. Unset, or any value that is not one of the
three (a hand-edited 4, a string, a fraction), reads **9** (`rituals.teamSizeDefault`).

**The size is the team.** A size of 9 is nine people in the room and no empty desk; every seat the
size counts is filled, and the empty desks are only the windows past it -- `9 - size`: 0, 3 or 6.
The seats after the chair's are filled in this order, until the size is reached:

1. **the engineer** -- you, the card tile, named for the Space. Always, with or without work;
2. **the labelled workers with work** -- anything in yesterday, today or blockers, which is to say
   `empty` is false -- in label order;
3. **the labelled workers with nothing routed**, in label order;
4. **invented cast members**, in the cast's grid order.

**The engineer and a labelled worker are told apart by what they are, not by their label.** A Space
whose slug is also one of its tracker's worker labels (a Space called `opus` on a repository with an
`opus` label) has two members that share a name: the engineer, and the worker that label routes to.
Both sit and both report, at every size with a seat for each, under the same name they wear today. The
fill keys a member by its kind and its label together, in both halves, so the second of the pair never
reads as absent. The stage does the same: the engineer is the record's last member of that name, the
card tile, and each keeps its own window.
The brief reads each member's counts by the member's place in the record, not by its name, so two
members of one name each report their own cards started and commits.

Whoever is past the size is **absent** today, and nobody reports for them. So four workers with work
and a size of 3 seat the chair and two of them, and an idle engineer still sits ahead of three working
labels. Work first loses the least among the labels: absence falls on the idle before anyone with
something to report.

**An invented cast member fills a seat nobody takes.** It is one of the stage's own cast: its label is
its cast id (`ops-dev`), its name the plate (`OPS-DEV`), and it is marked `cast: true`. It has no work,
so its turn is two made-up items, as an idle member's is. It is in the **round** only -- never in the
record, so the detail, the brief and the counts never name it.

### Where the room's members come from

**Planned work stays with its label; once a card exists, the card decides.** An open issue with a worker
label and no card is routed work not yet started: it stays with the label's worker, as their item for
today, and a worker label seats its worker as it always has, idle or not. A card -- one joined to an issue,
or one of its own -- is reported by the member its agent names, by the one reader of a card's agent
([the card](../hub/cards.md#how-a-cards-agent-is-worked-out)) in the shipped order: its `**Agent:**` line,
else an older card's `**Assigned:** <size>` (a size, in any case, reads as that family's current model, a team's own
worker such as `backend` as written), else the `Co-Authored-By` trailers of the commits its bullets name
-- read in [the dates read](#what-moved-and-the-window), on a connected GitHub Space only
([A card's commit trailers are read from GitHub only](../KNOWN-GAPS.md#a-cards-commit-trailers-are-read-from-github-only)) -- else nobody,
and the engineer reports it. The worker label is never passed: a card on a `sonnet`-labelled issue whose
commits credit Opus is Opus's to report, and one that names nobody is the engineer's.

| Who the card names | Who reports it |
| --- | --- |
| a family a worker label routes to (`opus` and the `opus` label, compared ignoring case) | that labelled worker |
| any other family (`grok`), or an id the map does not know (`acme-coder-1`), or a worker name (`backend`) | a member of its own, labelled with it, named with its first letter in capitals (`Grok`, `Backend`) -- an id the map does not know is named as written (`acme-coder-1`) |
| nobody | the engineer |

**The members are derived from the cards.** The room's members are the labelled workers, as before,
plus one member for each family the cards in play name that no worker label routes to: two ids of one
family (`claude-opus-5`, `claude-opus-5-5`) are one `opus` member, and each card keeps its exact id. A
member that is not a labelled worker exists only while a card in play names it. The record is the
labelled workers and those members in label order, then the engineer; seating is the rule below,
unchanged. A member a card names sits in its family's kept window when it has one; any other is dealt
the next free window and wears its family in capitals on its plate (`GROK`, `ACME-CODER-1`, `BACKEND`):
the worker row's `plate`, `""` for everyone else, which the agent serves, `Standup -AsJson` prints and
the stage shows.

One rule per half: `New-P20StandupCardRoute`, `Get-P20StandupCardMember`, `New-P20StandupCardMember`
and `Get-P20StandupMemberTiles` in `Scripts/Standup-Rules.ps1`; `_CardMembers`, `card_member` and
`_member_tiles` in `agent/solitaire/standup.py`. Held by `standup-team.json`'s cases below: a card with an
Agent line, one whose agent comes only from its trailers, one with neither, one whose issue is labelled
for another model, a labelled issue with no card, a family with no kept window, an unknown id, two cards of
one family, and an older card's Assigned size and Assigned `backend`.

**The cast is shared data**, `consts.json` `rituals.room`: `windows`, the nine windows in grid order,
each a cast `id` and the `plate` its persona wears; `chair`, the cast id whose window is the chair's
(`pm`); `kept`, the windows three labels keep (`fable` `dev-hero`, `opus` `vibemancer`, `sonnet`
`minimalist`); and `engineer`, the engineer's window (`dev-hero`). Who sits where:

- A window is a member's **own** when its label is a key of `kept`, or is itself a member window's cast
  id (a label `qa` sits in `qa`). A seated member sits in its own window; an absent one keeps it empty,
  so nobody moves when it is back.
- **The engineer** takes `rituals.room.engineer` unless a member of the record owns that window: a
  label's kept window wins over the engineer's.
- Everyone else is dealt the free windows in grid order -- the engineer first, then the labels in label
  order -- and takes a window an absent member keeps only when the free ones run out.
- An invented member sits in the window its cast id names, so it skips a window anyone has taken or
  keeps.

### The room's rules

These hold whatever else changes in the fill, the lines or the art. Each is asserted from both halves
over every `room` row and every case of `Tests/fixtures/rituals/standup-team.json` -- `tkTestToolkit
-Rituals` and `Tests/test_rituals.py` (`TheRoomsRules`) -- by one helper named for the rule.

1. **The standup always runs**, even on a day with no work: the `idle-room`, `idle-room-3` and
   `idle-room-6` cases are such a day at 9, 3 and 6, and each still has every turn and the chair's.
2. **The size picked is the size seen**: the round's members and the chair are exactly 3, 6 or 9
   (`assert_the_size_seen_is_the_size_picked`, `$ruleSizeSeen`).
3. **Everyone speaks, every day**: members with work report it, and an idle member's turn is its two
   made-up items, never trimmed, checked in the rendered work grain (`assert_everyone_speaks`, `$ruleEveryoneSpeaks`).
4. **The empty desks are only the windows past the size**: 0 at 9, 3 at 6, 6 at 3
   (`assert_the_desks_are_past_the_size`, `$ruleDesks`).
5. **The engineer's seat is the owner's**: whenever the fill has an engineer it sits first in the
   round, never invented, under the Space's name (`assert_the_engineer_sits`, `$ruleEngineer`).

The engineer in a room with no labels, at each size:

| Size | In the room | Empty desks |
| --- | --- | --- |
| 3 | the chair; the engineer; one invented cast member (`OPS-DEV`) | 6 |
| 6 | the chair; the engineer; four invented cast members | 3 |
| 9 | the chair; the engineer; seven invented cast members | 0 |

**The record is not the round.** The fill keeps EVERY member of the record on the response -- the
labelled workers in label order, then the engineer -- and marks each `present: true|false`; the
response carries the room as `team: { size }`. Then:

| Reads | Who |
| --- | --- |
| **The round** -- the work grain (`Standup -Grain work`, `work.workers`, `work.text`), the dress | the room: the seated members, then the invented cast members; an absent member has no line, not even its name |
| **The record** -- the detail grain (`text`), the brief's count lines (`counts`, `brief`), the Agenda | every labelled worker and the engineer, present or not; never an invented member |

**The turns go in seat order**: the engineer, the labelled workers with work, the labelled workers with
nothing routed, the invented cast members, and the chair last.

The record reads as it always has, with one row more: on a GitHub Space the engineer is always in it.
With no card in play it is idle, and its rows are the made-up `Status` pair an idle labelled worker
has; the brief says `<Space>: nothing today.`

An absent member is silent in this build: nothing in the round names the absence. The two made-up
items are picked by place, `(d + i) mod len`: `i` is a member's place in the record (the labels in
label order, then the engineer), present or not, so changing the size never changes what a member
says; the invented members take the places after the record's last, and the chair's own made-up
yesterday the place after theirs. A full idle room -- eight members with nothing to say -- is sixteen
different lines on any day of the year, and the chair's is none of them. One rule per half:
`Get-P20StandupRoomSeats` and `Set-P20StandupRoom` (`Scripts/Standup-Rules.ps1`, with
`Get-P20TeamSize` in `Scripts/Resolve-TeamSize.ps1`) and `room_seats`, `seat_room` and `team_size` in
`agent/solitaire/standup.py`; **one table**, `Tests/fixtures/rituals/standup-team.json` -- its `sizes`
(a stored value in, the room out), its `seats` (labels only: who sits), its `room` rows (who sits, the
window each speaker sits in, and the desks left) and twenty cases end to end with their detail, work and
brief goldens, `standup-team-<case>*.txt` -- the ten of the team size, and the ten of
[where the members come from](#where-the-rooms-members-come-from), each with every worker's `plate`, what the
one reader says of each card (`agents`) and each member's window (`windows`). The `room` rows carry every seat, and the stage is the
table's third reader: `stage/seats.test.ts` gives each row to the stage as the response would carry it
and holds every speaker to the window the row names.

**The stage seats the same room.** The played view draws the round: the engineer and the labelled
workers in their windows, each invented cast member in its own, and an empty desk only in the windows
past the size -- none at nine, three at six, six at three
([the played view](#the-played-view)).

The setting is written by `Config -Set spaces.<slug>.features.teamSize=<3|6|9> -Hub`, which refuses any
other number by name (exit 2), and asked in the settings drawer as **How many are in my standup in
\<Space>?**, four radios -- live on a GitHub Space, where Team Agile's standup runs --, each a pick
through `PUT /api/config` ([`docs/CONFIGURATION.md`](../CONFIGURATION.md)): **Default (9)** first,
checked while the size is unset, then 3, 6 and 9. Default is `Config -Unset
spaces.<slug>.features.teamSize -Hub`, the way back to unset; the 9 is `consts.json`
`rituals.teamSizeDefault`. The drawer's Configuration section offers the same: its row for the setting,
labelled by the same question, is a select of **Default (9)**, 3, 6 and 9. The web never reads the
setting for the standup: the response says the size and who is present, and the stage draws that.

## The suggestion: one next move, derived

The chair's reading ends on one next move, never invented: a real item, the rule that chose it, and the
command that acts on it, so anyone reading the rule reproduces the pick by hand (D-AR7 to D-AR9 of the
agent-in-the-room spec). It replaces ONLY the `Next: nothing is waiting on you.` line, and only when
nothing waits -- "Waiting on you" is the chair's obligation and stays first; the suggestion is an offer.

```text
Next: #141 is opus-sized and well defined -- send it to the crew? (tkStartWork 141)
```

**Signing in is not a suggestion here.** A signed-out Azure DevOps Space does not make signing in the chair's
next move, because Team Agile cannot be on in one: an Azure DevOps Space's answer to "How do you want to
work?" is `team`, derived and locked, and the module is on only where the answer is `agents`
([the switch](#the-switch-and-its-scope)). The sign-in is said where it can be: the shell's
"Sign in to Azure DevOps" strip, with the command to copy ([`ado.md`](ado.md#signing-in)).

**The input** is the open work of the Space as the standup joins it: an open issue is one item, and a
card in `current/` whose id is that issue's number adds its lane (Active without one); a card with an id
of its own is its own item; a not-billable card is an item that is excluded first. An issue's severity and
size are its labels (the triage ceremony's `sev1`-`sev3`, the worker labels), who has it is the triage rule
([who](#who-takes-it): its first assignee -- `me` when that is the signed-in `gh` user, `@<login>` otherwise
-- else its size; the standup asks `gh api user` once per call, the read Triage makes, and only while the
suggestion is on), its milestone and due date are the tracker's, its age is
`createdAt`. A card's severity and size are on its `Tags:` line, who has it is its worker -- its `**Agent:**`
line's family, else its `**Assigned:**` line -- (else its size), its milestone is its `**Milestone:**` line read WHOLE -- or, on a card with none, its
`**Sprint:**` line, as every card read before the two were separate -- and its age is its `**Created:**` day
([cards](../hub/cards.md#what-the-suggestion-reads)). A milestone's open count is its billable items, once
per id.

**The exclusions, in order** (`consts.json` `rituals.suggestExclusions`): not billable; waiting on you --
on the queue (a `verify-close` issue, a card in Code Review); in flight -- In Progress or Code Review;
theirs -- an issue assigned to someone who is not you (`@<login>`; when `gh` cannot say who you are, every
assignee is someone else, so a suggestion is never someone else's work); dismissed on this surface in this
session.

**The order**: severity (`sev1`, `sev2`, `sev3`, then none); then the **nearest milestone** -- the open
milestone with the fewest open items, a tie by the earlier due date (a milestone with no due date after
every one with one), then the title, ordinal; an item with no milestone after every item with one; then
age, the oldest created day first; a tie by the id, ordinal. The nearest milestone is one function a half
(`Get-P20NearestMilestones`, `nearest_milestones`) over the table's `nearest` rows, so the order of its
three keys is one sentence here and one row there: to put the due date first, change this sentence and
that row together.

**The sentence**, by how you work in the Space and who has the item (`rituals.text.suggest*`):

| How you work | Who | Shape | Sentence | Command |
| --- | --- | --- | --- | --- |
| `alone`, or `agents` with it yours: `me`, or sized `fable` -- the owner's own seat, never the crew (D-AR10; `rituals.suggestOwnerSeat`) | -- | start | `23A3 is the last open card in milestone B -- start it?` | `StartWork 23A3` |
| `agents` | a crew size, and the item has a milestone | delegate | `#4 is sonnet-sized and well defined -- send it to the crew?` | `StartWork 4`; `StartWork 4 -Launch` where [the launch](#the-launch-the-block-handed-to-a-session) is on (`rituals.text.suggestCommandLaunch`) |
| `agents` | a crew size, and no milestone | place | `#5 is sonnet-sized but has no milestone -- place it?` | `Route 5 -Milestone <title>` on an issue; `Plan K7M2 -Milestone <title>` on a card, which writes its `**Milestone:**` line |
| `agents` | nobody | route | `#4 is the oldest open sev2 in milestone B and nobody has it -- route it?` | `Route 4 -Assign <me\|size>` |
| any | nothing left after the exclusions | -- | `Next: nothing is waiting on you.` (today's line) | -- |

The launch is an input of the rule, not something it looks up: `suggest(items, how, dismissed, launch)` in the
agent and `Select-P20Suggestion -Launch` in the CLI take it, so the rule stays pure and the table's rows carry
a `launch` field. The caller asks the one question `/env` and the inventory ask -- `start_work_launch()`
(`agent/core/config.py`) and `Test-P20StartWorkLaunch` (`Scripts/Test-StartWorkLaunch.ps1`, which the
inventory's row reads too): `claude` on the PATH. Only the delegate shape changes; the start, place and
route commands are the same with it on.

"Well defined" is not a judgement: a size label and a milestone. The reason clause is one of three
shapes: `the last open <card|issue> in milestone <m>` when the item's milestone has one open item (it),
`the oldest open <sev|card|issue> in milestone <m>` when it has more, and `the oldest open
<sev|card|issue>` with no milestone -- the severity when the item has one, else its noun. The chair's
line is `Next: <sentence> (<prefix><command>)`.

**Where it shows.** `Standup -Brief` (and every brief the standup carries), and the Team Agile page's
chair's reading, which draws the line as a row of its own: the line verbatim, its action -- **Work
it now**, the same words as the Agenda's tiles, opens [the hand-off box](#startwork-the-hand-off-block) for a start or a delegation, **Open
Triage** for a route or a place -- and a dismiss. The dismiss is per surface, per item, per session: the page keeps
the dismissed refs in `localStorage` (`p20.solitaireAgile.suggest.dismissed`, under a session id kept in
`sessionStorage`), every read and write wrapped so a browser that refuses storage still draws the line
and holds a dismiss for the page's life; the next candidate's line takes the dismissed one's place, and
with none left the line is today's. The CLI has no dismiss -- a line in a terminal is already gone.
[The PM Corner](#the-pm-corner-the-line-the-chevron-the-confetti) is the second surface, and reads the same
pick inside the nearest milestone. [The Agenda](#the-page) draws the same row as its first line, above its lanes,
and orders its **Waiting on you** lane by the same rule, so the top tile is the pick when the pick can be
started; an unrouted pick is named only by the row.

**The switch** is `spaces[].features.suggestions` ([the switch](#the-switch-and-its-scope)). Off, or on
an Azure DevOps Space, or with the tracker not answering, the standup carries no suggestion and the
chair's line is today's.

`Tests/fixtures/suggestion/table.json` is the one table, asserted from `tkTestToolkit -Rituals` against
`Scripts/Suggest-Rules.ps1` and from `Tests/test_rituals.py` against `agent/solitaire/suggest.py`: the
nearest milestone, every shape the rule distinguishes, the delegation with the launch off and on (a `sev1` beats a nearer milestone; two in one
milestone pick the older; one left beats three left; no milestone sorts last; a crew-sized item on an
`agents` Space is a delegation and a `fable`-sized one a start; a sized item with no milestone is placed in
one; an unrouted item is a route; in flight, not billable, waiting-on-you and someone else's excluded; the empty Space; a dismissed item yields the next), the switch, and three chair's readings
end to end whose goldens (`suggestion-<case>.brief.txt`) `Tests/regenerate_joined_goldens.py` writes.

## The PM Corner: the line, the chevron, the confetti

One derived line at the head of the Team Agile page, and the last line of `Standup -Brief`: where the
Space is going, how much is left, and the one item to start (AR-4 of the agent-in-the-room spec; D-AR11,
D-AR14). It is the suggestion's second surface -- the same switch, the same read and the same pick -- so
nothing in it is a second rule.

```text
Corner: 3 more issues to get milestone B - start #5 now > (tkStartWork 5)
```

**The milestone is the destination** (D-AR11). An issue names it on the tracker; a card names it on its
`**Milestone:**` line -- or, with none, its `**Sprint:**` line
([cards](../hub/cards.md#milestone-and-sprint-two-lines)) -- read WHOLE through the one card reader each half has -- never the card model's
`sprint`, which cuts the value to eighteen characters for the board, so a long title would split one
milestone into two ([cards](../hub/cards.md#what-the-suggestion-reads)).

**The line**, in order (`consts.json` `rituals.text.corner*`, shapes `rituals.cornerShapes`):

| Shape | When | Line |
| --- | --- | --- |
| `reached` | an item that names a milestone closed in the standup's window -- an issue's `closedAt`, an archived card's `**Closed:**` day, the window `Standup -Since` widens -- and nothing open names it any more; the latest close first, then the title | `milestone B reached` -- and, on the page, `: see Releases` |
| `oneLeft` | the nearest milestone among the suggestion's candidates has one open item | `one more card 23A3 to get milestone B - start it now` -- `card` or `issue` by the pick |
| `manyLeft` | it has more | `3 more cards to get milestone B - start 23A3 now` -- `cards`, `issues`, or `items` for a mix |
| `nothingInReach` | no candidate names a milestone | `no milestone in reach - place a card with Route or on its Sprint line` |

The nearest milestone is the suggestion's own (`Get-P20NearestMilestones`, `nearest_milestones` -- fewest
open, then the earlier due date, then the title), taken over the suggestion's candidates, and the id is the
suggestion's first candidate inside it. The remaining count is the joined list's open count for that
milestone: its open issues plus the open cards that name it (the one card reader), **once per id** -- a card
that tracks an issue is that issue's row. An item in flight still counts toward what is left; it is never
the pick, because the suggestion excludes it.

**The command** is `StartWork <arg>`, and the suggestion's choice where the suggestion has one to make:
a pick the suggestion would send to the crew -- the delegate shape, on a Space that works with `agents` --
names `StartWork <arg> -Launch` where [the launch](#the-launch-the-block-handed-to-a-session) is on
(`rituals.text.suggestCommandLaunch`), exactly as the Next line does. So when the two lines share a pick,
they name one command for it:

```text
Next: #5 is opus-sized and well defined -- send it to the crew? (tkStartWork 5 -Launch)
Corner: 3 more issues to get milestone B - start #5 now > (tkStartWork 5 -Launch)
```

Every other shape -- a start on a Space worked `alone`, an item that is yours, one nobody has sized --
keeps the plain `StartWork <arg>`, with the launch on or off. How the Space works and the launch are
inputs of the rule, as they are of the suggestion's: `corner(items, closed, how, launch)` in the agent and
`Get-P20CornerLine -HowIWork -Launch` in the CLI, handed the same two answers the suggestion was
(`start_work_launch()`, `Test-P20StartWorkLaunch`). Neither changes the milestone, the pick or the count.

**The brief** prints `Corner: <line> > (<prefix><command>)` when the line has a pick, else
`Corner: <line>`, as its LAST line, after the Next line -- its own line, never in place of another.

**The route** is the standup's own: `GET /api/ritual/standup` carries `corner` -- `shape`, `milestone`,
`remaining`, `ref`, `number`, `id`, `kind`, `noun`, `line`, `command` (unprefixed, `""` with no pick) and
`brief` (the brief's line) -- and `Standup -AsJson` the same. There is no `/api/ritual/corner`: the line is
derived from the read the standup already makes, so a second route would be a second read of the same
issues. Null with the switch off, on an Azure DevOps Space, or with the tracker not answering.

**On the page** the Corner is a `lazyPart` (`PmCorner.tsx`) drawn at the head of the Team Agile page,
above the standup's card: the line verbatim, and, when it names a pick, the chevron (`>`,
`rituals.text.cornerChevron`; its accessible name is `Work it now: <ref>`, the Agenda tiles' words), which opens [the hand-off box](#startwork-the-hand-off-block) -- the same
`POST /api/cmd/StartWork` every **Work it now** makes. Where the launch exists (`/env`'s
`startWorkLaunch`, true -- the name is `consts.json` `startWork.launchEnvFlag`), the box offers a second button, **Launch**, which sends the same verb with
`-Launch`; absent or false -- every agent today -- the box has one button. The brief below stops above the
Corner's line, because the Corner is drawn at the head; **Copy** still copies the brief exactly as the agent
rendered it.

**The Corner does not celebrate.** It used to throw confetti over the page when its line read reached,
and confetti with nothing around it to say why read as a glitch. Now a reached line ends in
`: see Releases`, a link to the Releases tab, and the award dialog there is the module's one
celebration ([Milestones: the tab and the award](#milestones-the-tab-and-the-award)). The line itself --
the agent's, and the brief's last line -- is unchanged.

`Tests/fixtures/rituals/corner.json` is the one table, asserted from `tkTestToolkit -Rituals` against
`Scripts/Corner-Rules.ps1` and from `Tests/test_rituals.py` against `agent/solitaire/corner.py`: its rows
start from the raw read (gh's issues, and each card as its file's lines), so the join, the window and the
whole `**Sprint:**` line are exercised -- one left, several left, reached by an issue and by a card, closed
before the window, closed in it with one still open, nothing in reach, a card and its issue counted once, a
card and an issue in one milestone whose title is longer than twenty characters, in flight counted but not
picked, the pick inside the nearest milestone rather than the suggestion's own, and a delegation with the
launch off and on beside the two that stay a plain start with it on (a Space worked alone, an item nobody
has sized); and four chair's readings end to end -- one with the launch on, where the Next line and the
Corner end in the same `-Launch` -- whose goldens (`corner-<case>.brief.txt`) `Tests/regenerate_joined_goldens.py` writes.

## Milestones: the tab and the award

Where the work is going, and the one place Team Agile celebrates getting there. The Releases tab (named Milestones until it was renamed; the route, the reader and the
section's anchor keep the older name) is the
module's third page, after Standup and Triage, under the same one nav entry; off, it is absent like the
rest -- no route, no strip entry, nothing fetched, and `GET /api/ritual/milestones` a **404**.

**The read.** `GET /api/ritual/milestones?space=<slug>&refresh=1` (`consts.json` `rituals.milestonesRoute`,
`agent/solitaire/milestones.py`) answers `ceremony` (`milestones`), `space`, `tracker` (`ok`, `reason`) and
`milestones`. Each row is the ado core's own milestone -- the shape `GET /api/milestones` serves the Stats
tab's Milestones card, from the same reader (`accounting.github_milestone_rows`): `title`, `number`, `repo`,
`url`, GitHub's `state`, its `open` and `closed` counts, `due`, `closed_at`, `created_at` and `updated_at`
(days, `""` when unset) and `reached`. There is no second milestone rule: `reached` is the core's
`milestone_reached` -- **every issue closed, and at least one issue**, whatever GitHub's own state says. So
a milestone closed on GitHub with an issue reopened in it is not reached, and one nobody closed on GitHub
is. The tab reads no card: a card's milestone line feeds the suggestion and the PM Corner above, through
the one card reader, and never these counts, which are the tracker's own. What the route adds is Team Agile's shape around it: the module's gate, `?space=`, the tracker state
the ceremonies answer with (any repo that fails fails the read, with its reason, never a raise), and the
kept read -- one `gh` call per repo a minute ([above](#one-tracker-read-kept-a-minute)), read again on
`?refresh=1` or after a verb through the bridge. The query travels as `-f`/`-F` fields, never in the URL.

**A milestone with no issues is never reached.** 0 of 0 is not an achievement: an empty milestone reads
`no issues yet`, open or closed on the tracker, and is never awarded.

**The tab.** The panel is headed **Releases**, and its subtitle and every row say
`GitHub milestone`, so it never claims to be derived from anything else. The empty state reads
`No GitHub milestones yet`: GitHub milestones are made on the tracker, and each one shows here with its
progress. One row per GitHub milestone, in the Stats card's order (`ado/milestones.ts`: in flight, most
complete first; then reached, the one GitHub still shows open first; then empty): the title and a state
badge, a bar of closed over total -- the tracker's own two numbers, `5 of 8 closed` under it --, the due date
where there is one, `closed on the tracker` where GitHub has closed it, and the milestone's link on GitHub.
The state is one of four words: `open`, `reached`, `awarded` (a reached milestone whose award this browser
has shown) and `no issues yet`.

**The award.** When a milestone is reached and the person next opens the tab, a dialog opens for it:
`Congratulations: <title> reached!`, one line of what it took -- `12 issues closed, 1 October 2026 to
24 October 2026.`, from the day it was made to the day it was reached (GitHub's close, else its last
change: the last issue closing) --, a gold trophy, and the confetti, once, over the whole app as it opens.
Close it and the tab is there with that milestone marked `awarded`. A visit owes **one** dialog: when
several reached milestones are waiting (a browser that first looks at a Space with a backlog), it names all
of them, oldest reached first, the order the work was done in -- `Congratulations: A, B and C reached!` (`A`
for one, `A and B` for two) -- with each milestone's own line of what it took under it, and one burst of
confetti. Nothing is awarded unseen, and nothing is shown twice. The decision is taken once, when the tab first reads its list: a milestone reached while you watch is
awarded on your next visit.

It fires **once per Space and milestone per browser**. The mark is `celebrate.ts`'s -- `localStorage`, every
read and write wrapped, a refusal held in the page's memory -- under its own key,
`p20.solitaireAgile.milestones.awarded`, each id `<space slug>:<repository>#<milestone number>`, built and
read by `awardKey` in `award.ts` alone (a title can be renamed on the tracker, and two repositories can share
one). A mark written as `<space slug>:<milestone title>` by an earlier version is still read as awarded. The
marks are set before the dialog's first paint -- the shown one and the backlog behind it -- so closing it by
the button, Escape or leaving, a revisit, or a refetch of the list never shows it again. The mark is this
browser's, kept per site address: a dev server on another port, or `127.0.0.1` where it was `localhost`, is a
fresh store and shows the award again. (The PM
Corner's old confetti mark, `p20.solitaireAgile.corner.reached`, is no longer read: nobody has seen an
award yet.) Under `prefers-reduced-motion` the dialog opens and nothing rains.

**The confetti** (D-AR14) belongs to the whole app, and it is mounted once: `shell/ConfettiProvider.tsx`
wraps the app near its root (`shell/main.tsx`) and draws the burst there, over the whole viewport, outside
every page's and dialog's tree -- on a layer of its own just above Fluent's portals (`CONFETTI_LAYER` in `shell/layers.ts`), so it
falls over an open dialog and its backdrop, and never takes a click. A caller does not mount anything -- it throws, through the `useConfetti()`
hook (`hooks/useConfetti.ts`), which returns `throwConfetti()`. One call is one burst; a call while a burst
is still raining is absorbed into it; under `prefers-reduced-motion` a call does nothing. The burst is still
one wrapper over the `react-confetti` package, `shared/Confetti.tsx` -- the viewport's size, `recycle` off, a
burst that rains out in a few seconds -- and the award dialog (`AwardDialog.tsx`) is the one caller, throwing
once when it opens. Tests hold all three: the package is imported by the wrapper alone, the wrapper is
mounted by the provider alone, and the dialog is the one file that calls the hook. No bytes until something
throws: the wrapper and the package are the provider's `lazyPart`, fetched with the first burst, so with Team
Agile off -- nothing to throw -- and under reduced motion, they are never fetched. The provider itself is a
context and a counter, shell code with no package behind it.

**The picture is a gold trophy**, `Trophy.tsx`: an inline SVG -- a cup with two handles, a stem and a plinth --
in the 200 px box, no raster and no package, with `A gold trophy` as its accessible name. It is the gold
podium trophy the studio drew for its bowling decks, ported as a picture of its own in the studio's geometry
and golds; the golds are named once in the file and are the same in every theme, and the deep gold outlines the
cup and the plinth so the shape still reads on a dark dialog. `AWARD_PICTURE` in `AwardDialog.tsx` names it.

`Tests/fixtures/rituals/milestones.json` is the one table: gh's own rows in (open with and without a due
date, every issue closed while GitHub shows it open, every issue closed and closed on GitHub, closed on
GitHub with an issue still open, empty open and empty closed) and the route's rows out, asserted from
`Tests/test_ritual_milestones.py` and drawn by `MilestonesPage.test.tsx`.

Known gap: [Milestones appear on two pages](../KNOWN-GAPS.md#milestones-appear-on-two-pages).

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
a card's `**Assigned:**` or `**Agent:**` footer line ([who](#who-takes-it); [cards](../hub/cards.md)); a standup reads the cards'
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
| empty | a worker with all three slots empty has two made-up items, `status: [yesterday, today]`: `nothing[(d + i) mod len]` and `nothingToday[(d + i) mod len2]`, `d` the day of the year of `asOf` (1-based), `i` the worker's position (0-based) -- so two idle workers on one day say different lines, and the same day always reads the same. `excuse` is the first of the two; the detail text shows both, one `Status` row each (`text.mug`; the key's name is historical), yesterday's then today's, as a slot repeats its label for each item. At the work grain the worker says both, yesterday then today, in the frame every turn is said in, then `No blockers.` ([the prose](#the-prose)); a worker with work in any slot says only its real slots, never a made-up item beside a real one. `nothing` is the yesterday form, written `Yesterday I ...` ("Yesterday I cleaned up my local branches and my disk."), `nothingToday` the intent form ("Today I'll tidy the cables under my desk."); the two lengths share no factor (a test says so), so the pair does not repeat in step, and no sentence is in both families. A line of either is a whole sentence, first person and plausible, about the day around the work (the environment, tools, hardware, the desk, learning, meetings, admin), and claims NO TRACKER WORK: never a pull request, review, merge, commit, bug, fix to code, card, issue, ticket, deploy, test run or release. Both suites refuse a line that names one, by one word list (`Tests/fixtures/rituals/standup-nothing-banned.json`) |
| the chair | opens on `phrasebook[d mod len]`, closes on `phrasebook[(d + 1) mod len]`; `walked` is every issue with `verify-close`, worker or none, CLOSED with `closedAt` in `[since, asOf]`, by number -- what the human walked, and the chair's real yesterday ([the prose](#the-prose)) |
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
  Status     "Yesterday I took a course module on the cloud platform."
  Status     "Today I'll set up the password manager on my phone."

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
| an open issue with no card, given its worker label or assigned in the window | `started` | `#171 (started) Read the timeline` -- an issue alone has no commits |
| an issue with no card, otherwise | `closed` or `inProgress` | no parenthesis |

**Began** is the card's `**Started:**` day (`Move -To InProgress` writes it), else its `**Created:**` day
-- the card's own footer, read with its lane. A card decides its issue's start: its footer is the job
record, so an issue whose card began before the window stays in progress whatever its timeline says.
**An issue with no card began** when its timeline first says so: the earliest of a worker label being
added and the issue being assigned (a label that routes to no worker does not count), read in the dates
read below. It is `started` when that falls in the window, else in progress. Where the dates read was
not made or did not answer, an issue alone is closed or in progress, as it was before the read existed.

**The dates read.** On a GitHub Space the standup makes one more read after the issues: one `gh api
graphql` call per repo, with the query in a file and the owner and name as fields. It asks two things at
once, as aliased fields: for each hash the standup counts, the commit it names
(`object(expression: "<hash>")` -- an abbreviated hash resolves, and its `authoredDate` is read), and for
each open issue with no card that reads in progress, its labelled and assigned events
(`timelineItems(itemTypes: [LABELED_EVENT, ASSIGNED_EVENT], first: 50)`). It is asked for what the fill
counted and nothing else, so a Space with no card and no lone routed issue makes no call. One call holds
at most 50 aliases; a standup that needs more makes one call per 50. The agent asks every repo of the
Space for every hash (a card does not say which repo it was committed to) and each issue of its own repo;
the CLI reads its one repo. The answer is kept for the minute like every other read
([One tracker read, kept a minute](#one-tracker-read-kept-a-minute)). An Azure DevOps Space and a cards
Space make no dates read, and their counts are what they were.

**The trailers ride the same call.** The standup also reads the `Co-Authored-By` trailers of the commits a
card names, for the reader of a card's agent ([the card](../hub/cards.md), "How a card's agent is worked
out"). It asks only for the cards the fill places that have no `**Agent:**` line -- a card in a slot, and
each card joined to an issue in the read (the open issues and the ones closed in the window), never the
whole archive -- their bullets' hashes, distinct by seven characters (`Get-P20StandupTrailerAsks`,
`trailer_asks`). Each is one more alias in the same query, after the commits and the issues:
`t<i>: object(expression: "<hash>") { ... on Commit { oid authoredDate message } }`. A hash asked for its
date and its trailers is asked once, as a `t` alias, which dates it too; the 50-alias limit counts them
all; with no such hash the query is the one above, unchanged. The parse returns `messages`, a resolved
hash's first seven characters, lower case, to its message -- the shape the reader takes -- and skips a
hash GitHub could not resolve. A standup with trailers to read and no date to ask still makes the call,
and fills again with the messages alone: with no date asked, every bullet counts. A failed read keeps today's standup. The
messages are held beside the commit dates and passed to the joined fill, where a card with no Agent line
and no Assigned worker is reported by the model its commits credit
([where the room's members come from](#where-the-rooms-members-come-from)).

**Commits** are the card's `- <hash>` bullets -- the same lines that put it In Progress
(`regex.commitBullet`, the lane rule's own pattern, which captures the hash), so counting them is no
new read and no second pattern. A hash is compared by its first seven characters, lowercase: a short and a full hash of one commit
are one. A card with no bullets counts none; an issue with no card counts none; a not-billable card is
not a row and adds nothing to one, its commits included.

**Only commits authored in the window count.** A bullet has no date, so the date is the repository's:
the dates read gives each hash its `authoredDate`, and a hash counts when that falls in `[since, asOf]`.
Authored, not committed: a rebase resets the committer date and leaves the authored one, the clock Daily
already bills by. A card worked over three weeks counts only the commits of the window on the day it
closes. A hash the read cannot date -- not in the repository, ambiguous, or naming something that is not
that commit -- is **undated**: not counted, and never guessed, but said after the commits on the counts
line, `5 commits (2 undated)` (`rituals.text.countsUndated`; `undated` in each count). Where no dates read
was made -- a cards Space, or a dates read that failed -- every bullet counts, as it did before the read.

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
`Since Thursday 1 October 2026: 2 closed, 2 started, 2 in progress, 5 commits.`, or with hashes the
dates read could not date, `... 3 commits (2 undated).` The counts are the
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
`begun` and `commits`, as `read_cards` / `Get-P20StandupCards` read them. The dates read's cases carry
`commitDates` and `issueStarts`: `commits-window` (commits before the window and after `asOf` dropped,
undated ones said), `issue-labelled-in-window` (an issue alone reads `started`),
`issue-assigned-before-window` (in progress, and a card's own start winning over its issue's timeline)
and `dates-not-read` (the same cards with no dates read: every bullet counts).
`Tests/fixtures/rituals/standup-dates.json` holds the query, line for line, and the parse of an answer
into the two maps: an abbreviated hash, a missing object, an oid that is not the hash, a label that routes
to no worker, the earliest of a label and an assignment, and a timeline with neither.

Known gap: [The terminal's standup dates a commit from one repository, the page from every repository of the Space](../KNOWN-GAPS.md#the-terminals-standup-dates-a-commit-from-one-repository-the-page-from-every-repository-of-the-space).

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
| its id is the number of an issue in the read | **ONE row, the issue's** -- title, labels, milestone and slot are the tracker's, placed as the issues fill places them. **Who reports it is the card's**: the member its agent names, else the engineer ([where the members come from](#where-the-rooms-members-come-from)), never the issue's worker label. The card adds what only it knows: its lane (`links[]`: `number`, `id`, `lane`, `path`; the lane read the way `Status` reads it, Done in `archive/`) |
| ... archived, and the issue is open | the issue's row, and one `Check` line: `#<n> <title> -- the card is archived, but the issue is still open.` (`rituals.text.checkCardArchived`) |
| ... in `current/`, and the issue is closed | the issue's row, and one `Check` line: `#<n> <title> -- the issue is closed, but the card is not archived.` (`rituals.text.checkIssueClosed`) |
| ... the issue is open with no worker label, so the issues fill gives it no slot at all | the card -- when it is itself in `current/` -- is **its own row**, reported by the member its agent names or **under you**, in the slot its lane maps to, exactly as a card of its own is (the next row): named by its id, `Today  160 Fix the loader with no route` for a card in progress, and on the walk too in Code Review. It is one row, never two, and the link is still in `links[]`. A routed issue's card is unaffected: it follows its issue |
| an id of its own, or a number the read has no issue for | **its own row**, reported by the member its agent names, else **under you**: one tile labelled with the Space's slug and named for it, in the slot its lane maps to ([the cards alone](#the-cards-alone)), after the worker tiles. The tile is the engineer and is always there: with no card to say it is idle, as a labelled worker with nothing routed is. Its Code Review cards follow the issues on the walk |
| not billable | nothing |

**When the two disagree, it is said, and nothing is written.** The `Check` lines (`checks[]`, by issue
number) come after the worker tiles in every grain -- the detail as rows under the `Check` label, the
work grain and the brief as `Check: <sentence>` lines -- and `Route` stays the one write, to the
tracker. Rounds share an id (`-r1`, `-r2`): the one in `current/` is the card, else the archived one closed
last, so an earlier round is never "archived while the issue is open". With no card in play the joined
standup is the issues' alone, byte for byte; with the tracker not answering it is the `Tracker` line and
no card. Daily is unchanged. The texts of a standup change only where a card is in play: an issue with no
card reads as it did.

```text
  Check      #142 Port the cast atoms -- the card is archived, but the issue is still open.
  Check      #143 Rename the slug -- the issue is closed, but the card is not archived.
```

`Tests/fixtures/rituals/standup-joined.json` holds the shapes -- a linked card and an open issue, a linked
card archived while its issue is open, an issue closed while its card is in `current/`, a card in progress
whose open issue has no worker label (with its detail, work and brief goldens), a card of its own,
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

**The engineer, and whoever the cards name.** A local Space has no worker labels, so a card is reported by
the member its agent names -- its `**Agent:**` line, else an older card's Assigned worker; no trailers,
since nothing here reads the tracker -- else by the engineer
([where the members come from](#where-the-rooms-members-come-from)). With no card naming anyone the standup
has one tile, the engineer's: labelled with the Space's slug and named with its display name (the slug
when it has none). `blockers` is always
empty -- a card carries no walk label -- and a day with nothing in either slot is two made-up items
(the same two made-up items, picked by the tile's position among the workers -- the first, so `nothing[d mod len]` and `nothingToday[d mod len2]`). The engineer takes the first seat, and invented cast members fill the others the Space's size counts ([the team size](#the-team-size-who-is-in-the-room)). Within a slot, cards are in file-name order. **The text
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
| 2 | the design card its body names: a `> GitHub:` thread of up to nine digits (`rituals.workThreadRegex`), named by that issue's head when the read has it, else `#<n>`; else a `design/<note>.md` (`rituals.workDesignRegex`), its stem title-cased (`team-agile` is `Team Agile`) | `design` |
| 3 | a card's type, from its heading (`# Task 139: ...` is `Task`) -- a card's row only | `type` |
| 4 | what is left in the slot, by the titles' common stem: each title's head (`rituals.workHeadRegex` -- a one-word tag like `Bug:` dropped, cut at ` -- ` or `: `); heads that share their first two words or more group under the words they all share (`Design lifecycle L1: ...` and `Design lifecycle L2: ...` are `Design lifecycle`), a trailing small word (`rituals.workSmallWordRegex`: `the`, `of`) not counted; a head alone names itself | `stem` <!-- markdownlint-disable-line MD038 -- the span shows a separator with the spaces the pattern cuts at --> |

Groups with the same name, ignoring case, are one group, named as first seen -- so a milestone and a
design card both called Team Agile are one. Most items first; a tie keeps the slot's order. A group's
phrase is `rituals.text.work<Slot>` for the slot's first group (`{name}, {n} closed` for yesterday,
`{name}, {n}` for today, `{name}, {n} to walk` for blockers and the walk queue) and `workGroup`
(`{name}, {n}`) for the rest; `{n}` is `rituals.numberWords[n]`, digits past twelve. The queue's kinds
are grouped the same way. The phrase is the group's data; what the work text SAYS is the groups spoken
as prose ([the prose](#the-prose)). It keeps the long form's frame -- the title, the chair's
lines, the `Tracker` line when nothing answered -- with one line for the queue, one turn per worker
PRESENT today ([the team size](#the-team-size-who-is-in-the-room): an absent worker has no line) and
the chair's own turn last; an empty slot beside a filled one says its fixed line, and a worker with
nothing at all says its two made-up items ([the prose](#the-prose), "The round of the room"). This table's
`friday` case, in a room of nine:

```text
Standup -- Friday 2 October 2026
"Can we not adjust scope."

Waiting on you to walk #<n>, Verify the Studio tab draws on the PC. Also to walk one in Phase 6: #<n>, Verify the clock fix on Windows. Also to walk #<n>, Verify the clock on Windows.

Fable: Good morning. Yesterday I closed two in Design lifecycle (#<n>, #<n>). I also closed #<n>, Rename the slug. Today I'm on two in Team Agile (#<n>, #<n>). I'm also on two more: #<n> and Design lifecycle L3. Blocked on #<n>, Verify the Studio tab draws on the PC. That's it for me.
Opus: Good morning. Yesterday I closed three in Team Agile (#<n>, #<n>, #<n>). I also closed one in the Studio: #<n>, Count the foyer rows. Today I'm on two in Team Agile (#<n>, #<n>). No blockers. That's it for me.
Sonnet: Good morning. Yesterday I took a course module on the cloud platform. Today I'll set up the password manager on my phone. No blockers. That's it for me.

Good morning. Yesterday I watched a couple of React tutorials to get my head into the new stack. Today I'll walk #<n>, #<n> and #<n>. No blockers. That's it for me.

"Let's circle back."
```

The room here is nine, so five invented cast members speak between Sonnet and the chair, each with two
made-up items of its own ([the team size](#the-team-size-who-is-in-the-room)); their lines are left out above.

**The grain is configurable** (`rituals.grains`: `detail`, `work`, `brief`): `Standup -Grain <grain>`
in the terminal (`detail` the default, `brief` the same as `-Brief`), a per-browser setting on the page
(detail the default), and the played view always plays at `work`. The response carries the grouped
form as `work` beside `text` and `brief`; `standup-work-<case>.txt` are the goldens of its text, and
`standup-team-<case>.work.txt` the goldens of a round with an absent worker. A model
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
| close | a worker with something to say and no blockers | `proseBlockersNone`, "No blockers." |
| unsaid | a worker with something to say and nothing yesterday | `proseYesterdayWorked`, "Yesterday I worked on {refs}." -- the open items it worked inside the window, named as the chair names its walks; past `proseFoldNames` (4) `proseYesterdayWorkedMany`, "Yesterday I worked on {n} items."; with none, `proseYesterdayNone`, "Yesterday I picked up where I left off." |
| unsaid | a worker with something to say and nothing today | `proseTodayNone`, "Today I'll pick up the next item from the board." |
| turn | every speaker's status, a worker's or the chair's | `turnOpen`, "Good morning.", before its sentences; `turnClose`, "That's it for me.", after them |

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
in no worker's line. Every noun, number and clause is the tracker's; every other word is the contract's.

**The round of the room.** Everyone there gives status, in one frame: `Good morning.`, what they did
yesterday, what they will do today, `No blockers.` (or what blocks them), `That's it for me.` Every
member's turn has a yesterday and a today, and the rule is three lines:

- **Real facts where there are any.** A slot with work in it says that work, in the sentences above.
- **A fixed honest line where a slot has none beside a real one.** Nothing today beside a real
  yesterday (it closed something, nothing is in flight) says `Today I'll pick up the next item from the
  board.` Nothing yesterday beside real work says, first, a real fact the fill already holds, if there is
  one: the open items of that member's (today's and the blockers') whose work began inside the window --
  their motion is `started`: a card's `**Started:**` day, else its `**Created:**` day, or on a GitHub
  Space an issue's timeline -- or whose card threads a commit authored inside it, which is known only
  where the dates were read ([what moved, and the window](#what-moved-and-the-window)): `Yesterday I
  worked on #<n>.`, the refs named as the chair names its walks and counted past `proseFoldNames`
  (`Yesterday I worked on five items.`). With no such fact it says `Yesterday I picked up where I left
  off.` An issue merely in progress today is not a yesterday, and a commit nobody dated is not one
  either. A member whose only items are blockers has neither a yesterday nor a today, so it says both
  lines, beside its real blocker.
- **The made-up lists only for a member with nothing at all.** A member with nothing in any slot fills
  yesterday and today with its two made-up items (`status`: `nothing`, then `nothingToday`, which is
  written `Today I'll ...`); no other member ever says one.

`standup-prose.json` holds it from both suites: its `unsaid` table (`prose_unsaid`,
`Get-P20StandupProseUnsaid`), its `itemWorked` table (the real-yesterday fact, `item_worked`,
`Test-P20StandupItemWorked`), and the cases `one-slot` (blockers only, yesterday only, today only),
`worked` (a card's start, a dated commit beside an undated one and one outside the window, five
timelines) and `cards-worked` (a card's start beside commits nobody dated):

```text
Standup -- Friday 2 October 2026
"Can we not adjust scope."

Waiting on you to walk one in Phase 6: #<n>, Verify the export on the PC.

Fable: Good morning. Yesterday I picked up where I left off. Today I'll pick up the next item from the board. Blocked on one in Phase 6: #<n>, Verify the export on the PC. That's it for me.
Opus: Good morning. Yesterday I closed #<n>, Rename the export. Today I'll pick up the next item from the board. No blockers. That's it for me.
Sonnet: Good morning. Yesterday I picked up where I left off. Today I'm on Phase 7: #<n>, Trim the menu. No blockers. That's it for me.

Good morning. Yesterday I watched a couple of React tutorials to get my head into the new stack. Today I'll walk #<n>. No blockers. That's it for me.

"Let's circle back."
```

The room here is nine, so five invented cast members speak between Sonnet and the chair, each with two
made-up items of its own ([the team size](#the-team-size-who-is-in-the-room)); their lines are left out above.

Each speaker's line opens with its name: the chair
calls each member by name, in seat order -- the engineer, the labelled workers with work, the idle
ones, then the invented cast members ([the team size](#the-team-size-who-is-in-the-room)) -- and the
member answers. The chair gives its own status
LAST, in the same frame and in its own first person, and never says the board's sentences again: the
opening line has already read the queue (D-TA6), so the chair says what it did and what it will do.
Its **yesterday** is what you walked: the issues carrying `verify-close` that were CLOSED inside the
window (`chair.walked`, the issues read the fill already holds -- no other call),
`Yesterday I walked #<n> and #<n>.` (`text.chairYesterday`, the refs joined as a name list; past `proseFoldNames` of them
the count, `Yesterday I did five walks.`). With nothing walked it is a made-up line, `nothing[(d + n)
mod len]`, `n` the number of members -- the record's and the invented cast members' -- so the place
after the last, and it is never a member's line that day. A cards Space has no walk to close (its walk is a card in Code Review), so its chair's yesterday is
always the made-up line. Its **today** is what waits, kind by kind in the ceremony's order:
`Today I'll walk #<n> and #<n>, and decide #<n>.` (`text.chairToday` over `text.chair<Kind>`, each
kind's refs in its groups' order, the clauses joined by `chairClauseSeparator` and the last by
`chairClauseLast`; past `proseFoldNames` refs a kind is counted, `do seven walks`), or with nothing
waiting `Today I'll keep the board moving.` Then `No blockers.` and `That's it for me.` The chair's
words never say "you". The chair's turn has no name before it, as its opening and closing lines have none. The response carries the
sentences -- `work.queueProse`, each work row's `prose` (the turn) and `work.chairProse` -- and
`work.text` is them: one line for the queue (or `Nothing is waiting on you.`), one a worker, then the
chair's turn:

```text
Standup -- Friday 2 October 2026
"Can we not adjust scope."

Waiting on you to walk two in Phase 6 (#<n>, #<n>). Also to walk #<n>, Verify the Studio tab draws on the PC.

Fable: Good morning. Yesterday I picked up where I left off. Today I'm on the Studio: #<n>, the archived-repository mark. I'm also on #<n>, Rename the slug. Blocked on #<n>, Verify the Studio tab draws on the PC. That's it for me.
Opus: Good morning. Yesterday I closed two in Team Agile (#<n>, #<n>). I also closed one in the Studio: #<n>, Count the foyer rows. Today I'm on two in Team Agile (#<n>, #<n>). No blockers. That's it for me.
Sonnet: Good morning. Yesterday I took a course module on the cloud platform. Today I'll set up the password manager on my phone. No blockers. That's it for me.

Good morning. Yesterday I watched a couple of React tutorials to get my head into the new stack. Today I'll walk #<n>, #<n> and #<n>. No blockers. That's it for me.

"Let's circle back."
```

The room here is nine, so five invented cast members speak between Sonnet and the chair, each with two
made-up items of its own ([the team size](#the-team-size-who-is-in-the-room)); their lines are left out above.

`Standup -Grain work` prints it, the page's Work grain shows it (each `#<n>` linked, as in the detail
text), and the played view speaks each sentence as a `Say` line. `standup-prose.json`'s `sentences`
table pins every shape row for row -- one item named or bare, several, the first group and the rest, each
slot and the walk queue, a count past twelve, a clause found by its head -- its `chairYesterday` and
`chairToday` tables the chair's two sentences, row for row (none walked, one, two, `proseFoldNames` and
one past it; each queue kind, several kinds, a crowd counted), its `unsaid` and `itemWorked` tables
the fixed lines and the real-yesterday fact -- and its nine cases (`friday`, `quiet`, `no-tracker`, `cards`,
`eight-groups`, `walked`, `one-slot`, `worked`, `cards-worked`) the sentences, the chair's turn and the goldens
`standup-prose-<case>.txt`: closed and in review (a walk; a card in Code Review), a blocked item, a
queue item routed to nobody, a worker with nothing to say, a slot with nothing beside one with
something, a queue with nothing, walk items closed in the window (`walked`, the one case whose chair has a
real yesterday), and a yesterday said from work begun or committed in the window (`worked`, `cards-worked`).

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
"unblocked") -- the only family it is shown: never `fakeWork`, `excuses`, `nothing`, `nothingToday` or `phrasebook`, and a test says
so. Not dressed: the queue's sentences and the chair's turn (the chair's, not a worker's first person), the
turn's frame (`Good morning.`, `No blockers.`, `That's it for me.`), a slot's fixed line and the
yesterday said from work in the window (no group speaks them), an idle worker's made-up items. A
fact's `id` is the worker's label and the sentence's place in its turn (`opus/1`; place 0 is the opener).

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
object of id to sentence is every sentence refused. **A sentence is re-dressed only when its facts
change.** The reply is kept by a hash of the model id, the register and the facts -- each sentence's
prose among them -- in memory (sixty-four standups) and on disk in the agent's cache (`core/disk_cache.py`,
under `standup-dress-1/`), so the same facts are dressed once, an agent restart asks nothing it has asked
before, and a changed fact or a changed `ai.model` asks again. The guard runs on a kept reply exactly as on a
fresh one: a kept sentence the guard now refuses is the prose. A decline or a failed call is not kept. The model's words are never pinned by a test; the guard and the prompt are the contract, and no
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
| The queue's sentences, the chair's turn, the turn's frame, a slot's fixed line, an idle worker's made-up items | the prose, always | they are never sent to the model |

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
| `tkTestToolkit -Rituals` | every case of `Tests/fixtures/rituals/standup.json` and of `standup-cards.json` (the cards alone: the one worker's slots and the walk queue by card id, the source and title tables, the card reader over real folders, a not-billable card nowhere) and of `standup-joined.json` (the two sources joined: every shape's walk, each worker's slots by ref, the `Check` lines and the links, the together case's detail, work and brief goldens and their JSON round trip, no card in play reading as the issues alone, the tracker down, rounds of one id; what moved: each item's motion and commits, the counts per worker and in total, the counts and window cases' goldens, the window rule and the hash rule in words) -- `since`, the day of the year, the chair's two lines, the queue, each worker's slots by number, `empty` and the two made-up items (`status`, and `excuse` its first, by the tables' `nothingIndex` and `nothingTodayIndex`) -- and the rendered text against `standup-<name>.txt` and the chair's reading against `standup-<name>.brief.txt`, byte for byte, with `Standup -Brief` typed in a fresh shell printing that reading alone and `-AsJson` carrying it; the same object read back from JSON rendering the same text; no `fakeWork` line in any case; no `nothing` or `nothingToday` line holding a word of `standup-nothing-banned.json` (#451, the same list both suites read), each family more than one line with none twice, no sentence in both, and their lengths sharing no factor; `-AsJson` carrying an idle worker's `status` pair; off is no verb, no function, no bridge entry and no `Menu -All` line; **`Standup` typed in a fresh shell** with only this package's manifest and `gh` stubbed as a function answering the friday case: the text the rule renders for now, the queue, the blocks, the window, `-AsJson` round-tripping to the same text, `gh` failing and an ADO Space each a `Tracker` line with exit 0 (ADO's the contract's sentence; every row of `tracker-reasons.json`, the same rows the agent asserts, its line from its key and from the reader that words it), a local Space filling from its scratch cards line for line with `source: cards` in `-AsJson`, the GitHub Space with `source: both` and, with scratch cards in its folder, the joined standup line for line (a card of its own under the Space's tile, a `Check` line for a card whose issue is closed, a not-billable card nowhere, the hub untouched), an undeclared `-Space` a stated refusal, `-Since` widening yesterday (an issue closed a month ago said, closed; the brief's counts line naming the day) and a day after today, a word that is not a day and `-Since -Remind` each a stated refusal, `-Help`, and the hub untouched; the work grain over `standup-work.json`, the same rows `Tests/test_rituals.py` asserts -- every group (name, `by`, count, refs, phrase) of the queue and of each worker's slots, the `heads`, `keys`, `types` and `counts` tables, `standup-work-<case>.txt` byte for byte and again after a JSON round trip, `Get-P20StandupGrainText`; the prose over `standup-prose.json`, the same rows the agent asserts -- every `sentences` row, each case's queue sentences, each worker's turn in order, the chair's own turn (`chair`), in its own voice -- every `chairYesterday` and `chairToday` row, `chair.walked`, never a queue sentence again and never "you" -- and each idle worker's turn (its two made-up items in the frame), `standup-prose-<case>.txt` byte for byte and again after a JSON round trip; the dress guard over `standup-dress.json`, the same rows the agent asserts -- every row's reason, every group's prose sentence passing its own guard, every guard of `rituals.dressGuards` with a row, the `verbs` family and the two `kinds`, and the reply that names a ref the group lacks keeping the prose for that group; and typed, `Standup -Grain work` printing the rule's work text for now and `-AsJson` carrying it, `-Grain detail` the standup as it always printed, `-Grain brief` the same as `-Brief`, and a word that is not a grain or `-Brief -Grain work` a stated refusal |
| `Tests/test_rituals.py` | the agent's issues, cards and joined fills and the rendering over the same three tables and goldens (the joined goldens also against `Tests/regenerate_joined_goldens.py`'s output); every `nothing` and `nothingToday` line against `standup-nothing-banned.json` (#451) -- no tracker word, more than one line, none twice -- no sentence in both families, their lengths sharing no factor, and the pick by position in the issues fill and the cards tile alike; the work grain over `standup-work.json` -- every group of the queue and of each worker's slots, the `heads`, `keys`, `types` and `counts` tables, `standup-work-<case>.txt` byte for byte, the JSON round trip, the work grain's own phrases; the prose over `standup-prose.json` -- every `sentences` row, each case's queue and worker sentences, the chair's own turn and its `chairYesterday` and `chairToday` rows (never a queue sentence again, never "you", `chair.walked`), every turn in the frame and an idle worker's turn its two made-up items, `standup-prose-<case>.txt` byte for byte, the JSON round trip, the prose's own sentences, no word that is not the contract's or the tracker's; the dress over `standup-dress.json` -- every row, every guard with a row, the rows its issue asked for (a ref the group lacks refused, "20g of protein" kept), the reply that names one, and around it with the model STUBBED: the facts are the workers' group sentences and nothing else, the kinds counted from labels and a card's type, the prompt offering the `verbs` and no other family (`nothing` and `nothingToday` included), a model that answers dressed and guarded, the same groups dressed once, no key / a failing model / a reply that is not JSON all the prose, nothing to dress asking nothing; the route with no key answering `spoken: null` and `work` unchanged, and with a stubbed model `spoken` beside `work` with `text`, `brief` and the register untouched; the route asking `gh` for `milestone`, `body` and `createdAt` and answering `work`; the Agenda (`TheAgenda`) -- what moved once each and dated in the standup's offset, waiting as Active cards, Code Review and routed issues and never In Progress, not billable, unrouted, someone else's or in `backlog/`, a card's face and file, the suggestion's pick first, nothing with no tracker, a cards Space its cards -- and the route carrying `agenda` with every tile's fields; `read_cards` over real folders (with each card's type, body and billable, and its `begun` day and commit hashes); what moved over `standup-joined.json` -- each item's motion and commits, the counts, the counts line opening the brief, the window rule, the hash rule; the route's `?since=` widening the window and a `since` that is not a day before today a 422 naming it; a local Space's route filling from its cards with no `gh` call; a GitHub Space's route joining its cards to its issues (`checks`, `links`, a card of its own on the Space's tile, a not-billable card nowhere, the hub unwritten); an ADO Space's `adoTracker` reason; why the tracker was not read over `tracker-reasons.json` -- every tracker key with a row, each row's line from its key, the `gh` reader over a stubbed `run_read` for every `gh` row and a missing `gh`, and the checks before `gh` (not GitHub, the tier, no repository, a reader that raised); 404 off; one tracker read per minute (QP33): two standups, two triages, and triage after the standup each one read, Refresh and a verb through the bridge reading again, a failed read not kept, an all-states read at its limit not answering for triage, the kept limits the reader's; the dress kept by its facts -- identical facts with no model call, across a restart from disk, a changed fact or model asked again, the guard run on a kept reply |
| `tkTestToolkit -Rituals`, `Tests/test_rituals.py` -- the PM Corner | `Tests/fixtures/rituals/corner.json` from both halves: every row from the raw read through each half's card reader, the join and the window (shape, milestone, remaining, pick, noun, line, command), every shape of `rituals.cornerShapes` reached by a row, the long milestone read whole (and the card model's `sprint` not it), the launch rows (a delegation's command with it off and on, differing in nothing else), and the four `briefs` cases end to end -- `corner-<case>.brief.txt` byte for byte, the Corner the last line, its command the suggestion's where the two share a delegated pick, again after a JSON round trip; typed, `Standup -Brief` ending on the Corner's line; the agent's route carrying `corner` (its fields, a shape of the contract, the brief's last line), none with the Space's switch off and none on an Azure DevOps Space |
| `web/src/modules/solitaireAgile/PmCorner.test.tsx`, `celebrate.test.ts` | the Corner: the line verbatim, the chevron opening the hand-off for the pick (a card by its id), no chevron for reached or nothing in reach; reached ending in `: see Releases`, a link that goes to the tab; NO confetti -- not on first sight, not on the transition to reached, nothing marked; the mark held in memory when storage throws |
| `Tests/test_ritual_milestones.py` | `GET /api/ritual/milestones` over `Tests/fixtures/rituals/milestones.json`: gh's rows in and the route's out, `reached` by shape (open, every issue closed with GitHub open and closed, closed on GitHub with one open, empty open and closed -- never reached), due dates with and without, the bar the tracker's numbers; the `gh` argv with fields and no `&` or `?`; one read a minute and `?refresh=1` reading again; no space the active one, an ADO Space and tier below 1 a tracker reason with `gh` never asked, `gh` failing a reason and not kept, an unknown Space a 404 naming it, the hub unwritten; 404 off |
| `web/src/modules/solitaireAgile/MilestonesPage.test.tsx`, `RitualPage.test.tsx` | the tab over the same table: the Stats card's order, each bar's value the tracker's closed over total, the due date where there is one, the state words; the award rule as a table (every milestone's state, marked and not -- an empty one never awarded); the award: the first reached with no mark opens its dialog with the title, the line and the gold trophy by its accessible name (the only drawing in the box), one burst at the app's root and NOT inside the dialog, closing it opening the next, then both `awarded` and marked, a new visit no dialog and no burst; leaving mid-award never shows that one again; another Space's milestone its own; reduced motion the dialog and no rain; no tracker, no milestones, the agent away; and the confetti's one caller -- no file but `AwardDialog.tsx` imports `Confetti.tsx`, none but it imports `react-confetti`. The strip: three tabs, each an address; `registry.solitaireAgile.test.tsx` holds the old `/milestones` address redirecting to `/releases`. Dialog queries are awaited and by role, as a screen reader reaches them; a query that says there is no dialog passes `hidden: true`, so it means none in the tree at all |
| `web/src/shell/ConfettiProvider.test.tsx`, and `MilestonesPage.test.tsx`'s "one mount, one hook, one caller" | the root's burst: a throw draws one, a throw while it rains is absorbed, the next throw after it ends is a fresh burst, reduced motion draws nothing, and with no provider the hook is a no-op; the package imported by `shared/Confetti.tsx` alone, the wrapper mounted (as a lazy part) by `shell/ConfettiProvider.tsx` alone, the provider mounted once in `shell/main.tsx`, and `AwardDialog.tsx` the one file that calls `useConfetti()` |
| `tkTestToolkit -Triage` | every case of `Tests/fixtures/rituals/triage.json` -- the groups in order, each group's counts, context and numbers, each issue's worker, size, who, severity and deep-water, the sizes -- and the text against `triage-<name>.txt` byte for byte, again after a JSON round trip; the who rule; `Tests/fixtures/parsers/assigned-lines.json` through `Get-P20CardAssigned`; off is no `Triage`, no `Route`, no `-Assign`, no bridge entry; `Triage` typed with `gh` stubbed (who: `me`, `@<login>`, `nobody`); **`Route` typed with `gh` stubbed as a function that writes down every call**: the exact `gh issue edit` argv for each switch, alone and all four in order, `-Assign me` (`--add-assignee @me`, and under `-WhatIf` printed and not made), `-Assign <size>` the `-Size` write byte for byte, `-WhatIf` writing nothing, the two moves printed, every refusal exit 2 with one `Error:` block and no write, the hub untouched; `-Assign` on a card -- the `**Assigned:**` line above `**Created:**`, LF and CRLF kept, no BOM, an unchanged card not written, the sizes from the repo, a local Space's card taking `-Assign me` alone, and its refusals (a size with no repository to read labels from among them) |
| `tkTestToolkit -Rituals`, `Tests/test_rituals.py` -- the suggestion | who "me" is (the viewer's assignee `me` and a candidate, another's `@<login>` excluded `theirs`, no viewer every assignee theirs; the route asking `gh api user` once with the suggestion on, never with it off); `Tests/fixtures/suggestion/table.json` from both halves: every `nearest` row (the order and the nearest), every `rows` row (the candidates in order, the pick, its shape, sentence and command, each excluded ref with the first exclusion it met), every shape and every exclusion of the contract reached by a row, every `switch` row, and the three `briefs` cases end to end -- the joined fill, the suggestion attached, the candidates, the pick and `suggestion-<case>.brief.txt` byte for byte (with something waiting the Next line is the queue's; switched off it is today's), again after a JSON round trip; the card reader's milestone (whole), Created day, Tags and Assigned, and `Tests/fixtures/parsers/card-milestone.json` through both halves' readers; typed, `Standup -AsJson` carrying the rule's candidates with each line naming the prefixed command, the brief's Next line staying the queue's while walks wait, and `spaces.<slug>.features.suggestions=false` in the hub leaving no candidate; the agent's route carrying `suggestions` (the fields, the order, the line) and none with the Space's switch off |
| `tkTestToolkit -Rituals`, `Tests/test_rituals.py` -- the team size | `Tests/fixtures/rituals/standup-team.json` from both halves: every `sizes` row (a stored `teamSize` read as the room -- 3, 6 and 9 themselves, unset, another number, a string, a boolean and a fraction 9 -- and whether it was set), the sizes and the default the contract's, every `seats` row (labels only -- who sits: fewer members than seats, the work-first order with an idle member earlier in label order absent while a working one later sits, the first idle taking a seat the working leave, more members with work than seats, nine in the full grid, a room of six, none), and every `room` row -- who sits, each speaker's window and the desks left: the three walk rows (no labels, the engineer with work, at 3, 6 and 9), no labels with an idle engineer at each size, two and one members short of the size and exactly the size, working and idle labels together, an idle engineer ahead of three working labels, more workers with work than the size, a kept window an invented member skips, a kept window beating the engineer's, a label that is a cast id, an absent label keeping its window, a family with no kept window dealt the next free one, and a fill with no engineer -- with every seat the size counts filled, the desks the windows past it, and no window or label shared; [the room's rules](#the-rooms-rules) over every `room` row and every case, one helper each -- the size seen is the size picked, everyone speaks in the rendered work grain (an idle member its made-up pair), the desks only the windows past the size, the engineer first under the Space's name -- and a day with no work a case at every size; the ten cases end to end -- `team.size`, every worker of the record kept with its `empty` and `present`, the round the seated in seat order then the invented cast members, the counts every worker and never an invented one, an invented member named in the work and in neither the detail nor the brief, and the detail, work and brief against `standup-team-<case>*.txt` byte for byte, the work again after a JSON round trip; the ten cases of where the members come from -- each worker's `plate`, the one reader's answer for each card and its source, and each member's window by the room's own rule; a full idle room never repeating a made-up line on any day of a year, the chair's among them; an absent worker's made-up items unmoved by the size; the cards fill seating the engineer and filling the room; typed, `spaces.<slug>.features.teamSize=3` in the hub giving `team.size` 3, every worker kept, two present and the round those two -- the engineer, then the first worker with work --, and no `teamSize` the room of nine with everyone present and the invented filling the seats left; the agent's route carrying `team`, each worker's `present` and each speaker's `cast` -- in a room of three the engineer and Fable in `work`, Opus and Sonnet absent from it and kept in `text` and the brief |
| `Tests/test_triage.py` | the agent's grouping, who and text over the same table and goldens, the goldens the regeneration script's; the route's `gh` calls (with `assignees`, then `gh api user`); a viewer `gh` cannot name; ADO and tier below 1 a `Tracker` line; 404 off |
| `tkTestToolkit -StartWork` | the hand-off block, typed in a fresh shell over a scratch hub built from `Tests/fixtures/start-work/`: off is no verb and no bridge entry; `StartWork 23A3` is `expected-card.md` byte for byte, and so is the card in CRLF, the id in lower case and the full filename; `39` never assembles `Task139`; a `how-we-work.md` switches section one's heading to its path -- `agentic/how-we-work.md`, which `HowWeWork` writes, over one at the Space's folder root, which is still read alone; issue 41, which no card carries, is `expected-issue.md` with one `gh issue view`; `-Prompt` absolute and package-relative; a partial name named in a terminal and refused for a non-interactive caller; and every refusal exit 2 with one `Error:` block and the hub untouched -- no row for the kind (naming `startWork.prompts.Meeting`), a row whose file is missing, a `-Prompt` that is no file, no id, nothing matching, an archived card, a closed issue, a pull request, an Azure DevOps Space, an undeclared `-Space`. And `-Launch`, from scratch clones with a stub `claude` first on the PATH: `-WhatIf` prints the worktree add, the block file, the exact command and the log and leaves nothing; the model from the `**Assigned:**` line, the Tags, an issue's label and the issue behind a numbered card; `fable` on a card and on an issue, no size, `me`, a size with no model, no git repository, another repository's origin, a failed worktree add, no `claude`, `-Clip` with `-Launch` and `-WhatIf` alone each refused with nothing started; off Windows the launch itself, read through a pipe -- back while the stub lives on, and the log's first message the block, whole |
| `tkTestToolkit -OrgChart` | the org chart: the reader over `Tests/fixtures/org/table.json` (a case per row of [what is checked](../hub/org.md#what-is-checked) and per way a valid file reads, which `Tests/test_org.py` holds the agent's reader to as well), `OrgChart` typed in a fresh shell over a scratch copy of `samples/hub` (off is no verb, the text and `-AsJson` against the table, every refusal exit 2 writing nothing), the `Org chart` inventory row's four states, and `samples/hub/org.json` valid |
| `Tests/test_org.py` | `GET /api/ritual/org` and the agent's reader over the same `Tests/fixtures/org/table.json`: every case read by the reader and through the route -- the chart as JSON, key order aside, once the route's `promptTitle` and `promptRef` are taken off; each failure's `kind`, its sentence and its status (404 `missing` and `no-hub`, 409 for an invalid file, 422 for an unknown `tree`); the reader alone (a byte order mark, `NaN`, a number as an id, exact key names, a seat with both a model and a person, a very deep tree, siblings in file order); the prompt fields (front matter, heading, file name, none, a file the room does not list, the extension folder's copy, a renamed agentic folder, the same title as the Studio's row); the gate (the switch off, the Space answered `alone`: 404 and the file never read); nothing written to the hub; the sample hub |
| `Tests/test_bridge.py`, "StartWorkThroughTheBridge" | `StartWork` in the bridge's table with Team Agile on and `rejected` with it off; through the bridge, `expected-card.md` byte for byte; a refusal `status: error` with the verb's sentence |
| `web/src/modules/solitaireAgile/StartWorkBox.test.tsx` | the copy box: one `StartWork` call, `expected-card.md` shown verbatim with its head as the title, Copy copying exactly the block, a refusal shown as the verb's sentence with no Copy, the agent away said so; no **Launch** while `/env` does not say `startWorkLaunch` is true, and with it, one more `StartWork` call with `-Launch` and what it printed or refused with |
| `tkTestToolkit -Consts`, `Tests/test_consts.py`, `web/src/shell/consts.test.ts` | the `startWork.text` headings; the `rituals` values (`triageRoute`, `milestonesRoute`, `grains`, `numberWords`, the four `work*Regex` patterns, the `work*` phrases and the `prose*` words among them, the dress's `dressGuards` and four `dress*Regex` patterns, and what moved's `motions`, the `itemMotion`, `motion*`, `commit*` and `counts*` words, and the room's `teamSizes` and `teamSizeDefault`), stated from all three halves; the turn's `turnOpen` and `turnClose`; `{n} to walk`, `No blockers.`, `Good morning.`, `That's it for me.` and `Yesterday I closed` never retyped in the CLI's scripts or the agent; `Waiting on you`, `nothing in flight` and `Routed to` never retyped in the CLI's scripts |
| `web/src/modules/solitaireAgile/StandupPage.test.tsx` | the page over the shared fixture and goldens (above); the Agenda -- a fresh page on it with its one sentence and no text, the two lanes and their headings (`Since Thursday 1 October`, `Waiting on you`), no action on what moved, one button a waiting tile with the suggestion's pick first, the suggestion row the first line after the sentence and above the lanes with no brief (a dismiss bringing an unrouted pick and its Open Triage), no Yesterday or Today word and no lane badge, each tile's fact and long date, a card's cover and progress and an issue's neither, **Work it now** one `StartWork` call with the number (a card by its id) and none before it is pressed, **Review it** a card's page or the walked issue, the cards / list toggle remembered with the list the same groups and buttons, **Copy and Play carrying exactly the text they carried before**, **Team size** beside them opening the drawer at the team-size entry's anchor, the worker chip reading the stage's deal (`PERSONA (label)`, none for a worker out today) (`standup-friday.txt` read from disk, and a stored Work or Brief grain), the tab remembered, an agent with no `agenda` both lanes empty; the counts line the first line at the top of the page, and an item's motion in the text; the grain: three tabs from `rituals.grains` after the Agenda, Detail the grain by default, Work showing `work.text` (`standup-prose-friday.txt`, the prose) verbatim and Copy copying it, Brief the brief as the body once, the choice remembered by the browser, a stored word that is not a grain read as Detail; the chair's suggestion over `suggestion-suggested.brief.txt` -- the Next line as its own row, its **Work it now** (the tiles' label) making one `StartWork` call with the number, a dismiss yielding the next (a route's action Open Triage) and holding for the session, none left the line today's, another session nothing dismissed, a browser that refuses storage still drawing it, the Brief grain showing it once, no row while something waits or with the switch off; the PM Corner over `corner-many-left.brief.txt` and `corner-reached.brief.txt` -- at the head of the page, the brief below stopping above its line while the suggestion still stands, the chevron one `StartWork` call, the Brief grain without the Corner's line and Copy the brief as it came, reached one burst and a fresh draw none, no Corner when the response has none |
| `web/src/modules/solitaireAgile/stage/geometry.test.ts` | where a speech bubble goes: over the nine windows at the stage's usual size, every face, plate and the speaker's button modelled from `HEADS`, a short and a long turn for each window placed clean -- no face, no plate, no button, inside the grid with its margin --, the side and size each one takes as a table, a short turn above the speaker wherever the window over it leaves room, the sides tried in order and a bubble slid along a side to clear a keep-out, nothing found when every side is blocked and the least overlap the last resort, the tail at the face |
| `web/src/modules/solitaireAgile/stage/seats.test.ts` | the stage as the third reader of `Tests/fixtures/rituals/standup-team.json`: the stage's windows, chair and kept windows are `consts.json` `rituals.room`'s, and the cast's drawings are the room's windows in the same order under the same plates; every `room` row given to the stage as the response carries it -- the record with who is present, the round in turn order -- seats each speaker in the window the row names, leaves the row's desks, and plates a member `PERSONA (label)` and an invented cast member its persona alone; every end-to-end case's round in turn order with each invented member in its own window and no window shared, and each member in the window its case names wearing the worker's own `plate` when the response gives one (`GROK`), else `PERSONA (label)`; a response with no work grain, or whose round names a stranger or leaves a present member out, seated by its record |
| `web/src/modules/solitaireAgile/stage/standupDeck.test.tsx` | the room: nine windows (`ROOM_WINDOWS`, the cast's count and the largest `rituals.teamSizes`), the eight member windows in cast order, the day of the year as the fill counts it (every `standup.json` case's `dayOfYear`), a kept label (`KEPT_WINDOWS`) in its own persona's window whatever its case or order and every other label by position in the free windows, a kept label out today leaving its window empty so no face moves, a kept window the Space has no label for dealt like any other, eight present never dropped (the windows absent kept labels left taken last), the desks' mugs `dealMugLooks` in window order, a face not moving when its work changes, only the present seated and an older agent's everyone capped at the room; the deck from the shared fixture's `friday` and `no-tracker` cases: the round in order with its ids (the board, the open, a call and a turn per member, the chair's status, the close), the call the member's name with its window called -- in colour, unframed -- and heard once (no title read before it, none before the turn), the board lighting the chair alone, the plates (`CHAIR · PM`, `PERSONA (label)`, `EMPTY DESK`) and no role word on any slide, an idle member keeping its face and saying its pair, never async, nine windows and the register on every slide, reduced motion; the copy panel the speaker's character -- title, persona with the label, motto; the four looks -- every window in full colour on every slide (no picture and no plate filtered, nothing greyed or dimmed), one framed speaker a slide, the called member marked, every other face named, every desk an empty desk with the drink the day dealt it and the grey dot, never lit, with no face anchor, bubble or thought; every face the refined cast's bust for its window's cast id; the round through the engine's own `SlideRenderer` -- one content key on every slide, every window the same DOM node from slide to slide with no entrance replayed, the new speaker framed with a bubble and the old one neither, a new bubble with its entrance when one window speaks twice running, a thought not left open, and nothing finite on the stage but the two entrances; the called mark on the called window and on no other; the bubble laid out unseen until placed, at main's size (up to 260px, never wider than its window, four lines), and the faces and plates it keeps off marked on the stage; the thought bubble's button and placement as they were;  at the work grain over `standup-prose.json`: the queue's sentences, each turn as the agent wrote it, the chair's own status last and never the board again, the tracker down leaving the chair no status; dressed, from `standup-dress.json`'s reply: a dressed worker's sentences, an undressed one's prose, `spoken: null` the prose, the board, calls, chair's status and an idle member never dressed; **no silent face** -- every face has a slide where it speaks and every desk none, with a mug of its own, over the owner's demo room (the chair, two members with tracker work, three idle each with its own pair, three desks), a Space with no worker labels on the issues (the chair alone, eight desks) and on its cards (the engineer's tile a member), `standup-team.json`'s `absent` case (two members, six desks, the absent never named), ten labels marked present by the fill and from an older agent (eight sit), and a response with no `work` |
| `web/src/modules/solitaireAgile/stage/RefinedDesk.test.tsx` | the room's empty desk in the refined cast: every drink the deal can hand it drawn, each differently and with no outline on its body; the flat-backed chair; full colour on the window's tint with no filter that greys or dims; two desks sharing no ids; one picture to a screen reader; the steam on the clocks and under the rule it has always had, still drawn when stilled (`stage/EmptyDesk.test.tsx` holds the deal and the Org page's desk) |
| `web/src/modules/solitaireAgile/stage/StandupPlay.test.tsx`, `web/src/modules/deck/engine/DeckPlayer.audiobook.test.tsx`, `web/src/modules/deck/GeneratedDeckHost.mute.test.tsx` | the mute, the played route's loading, error and Audiobook states; the audiobook hint at desktop width with prev and next either side of the ring, the browser voice, and a deck without the hint untouched |
| `tkTestToolkit -Environment`, `Tests/test_surfaces.py` | its inventory row has its question; the Space's answer over `Tests/fixtures/how-i-work/table.json` -- every row and every gate row -- and, typed in a fresh shell with the switch on, a GitHub Space answered with agents (`on`, `Standup` a verb), one nobody answered (`not configured`), an Azure DevOps Space and one with no tracker (`off`, derived, no verb), each with the line that changes it, and the question naming the Space |
| `Tests/test_how_i_work.py` | the agent's half of the same table; `load_config` serving the gated flag and `howIWork` with the switch as set, Space by Space, a local patch answering too, and the routes' 404 naming the answer or the switch |
| `tkTestToolkit -Config` | `spaces.<slug>.howIWork=agents -Hub` lands on the Space's hub entry and nowhere else; `team` and an unknown answer are stated refusals naming `alone` and `agents`; `-Unset` takes it off; `spaces.<slug>.features.suggestions=false -Hub` lands on the Space's features as a boolean and nowhere else; `spaces.<slug>.features.teamSize=3 -Hub` lands there as the number 3 and nowhere else, 4, 0, 12 and `nine` are stated refusals naming `3, 6, 9` that leave the stored size as it was, and `-Unset` takes it off |
| `tkTestToolkit -Environment` -- the suggestion's row and the team size's | the `Suggestions` row's three states: Team Agile on and nothing set `not configured`, set true `on`, set false `off`, Team Agile off `off` -- each with the line that changes it; the `Team size` row: Team Agile off `off` whatever is stored, saying it rides Team Agile; Team Agile on, unset `not configured` (nine in the room), 3 and 6 `on` with the number, a stored 4 `not configured` saying it is not a size -- each with `spaces.<slug>.features.teamSize=<3\|6\|9> -Hub`; every inventory row with its question, both renderers one block |
| `web/src/shell/HowDoI.test.tsx`, `registry.solitaireAgile.test.tsx`, `web/src/shell/scenarios.test.tsx` | How do you want to work in \<Space>?: the three radios in their words, by tracker -- GitHub two live and Azure disabled with its reason, Azure DevOps and no tracker selected and locked with theirs; a pick writing `spaces.<slug>.howIWork` with `-Hub` through the one writer; the Saving state -- the pick at once, `Saving…`, `aria-busy`, the others locked, all gone on success; a refusal reverting; the line when the switch is off; only `With agents` mounts the tab. How many are in my standup in \<Space>?: four radios, Default (9) first and checked while the size is unset, then 3, 6 and 9, a stored size checked, a pick writing `spaces.<slug>.features.teamSize` with `-Hub` and asking for no how-we-work note, Default unsetting it with `-Hub` (6 then Default round-trips), and on Azure DevOps every size disabled with its reason; `settingsWorkflows.test.ts` holds its answers to `rituals.teamSizes` |
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

Each of these is a block on [Known gaps](../KNOWN-GAPS.md), with its issue:

- **Nobody calls your number.** A launched session is detached: its result is its log and, when it gets
  there, a pull request on the tracker. The page has no window screen, one line per order saying cooking
  or ready ([the drive-through](#the-loop-as-a-drive-through)); you look at the tracker or the log
  ([A launched session does not report back to the page](../KNOWN-GAPS.md#a-launched-session-does-not-report-back-to-the-page)).
- **The bell and Home's tips do not suggest yet.** They are the suggestion's later surfaces, behind the
  same switch; the chair's line and [the PM Corner](#the-pm-corner-the-line-the-chevron-the-confetti) are the two built
  ([The bell and Home's tips carry no suggestion](../KNOWN-GAPS.md#the-bell-and-homes-tips-carry-no-suggestion)).
- **The celebration's mark is per browser.** Another browser, or one whose site data was cleared, celebrates a
  reached milestone once more on first sight
  ([A reached milestone celebrates once per browser](../KNOWN-GAPS.md#a-reached-milestone-celebrates-once-per-browser)).
- **The guard reads names by their capital**. A capitalised word that is not in the facts is
  refused, so a persona's proper noun ("Dev-Hero") sends the prose instead, and an invented name written
  in lower case is not caught; numbers, refs and kind counts are checked exactly. A group whose own name is
  a kind noun ("Bugs") with no item of that kind can never be dressed -- its prose fails the kind guard too
  ([The dress guard reads names by their capital](../KNOWN-GAPS.md#the-dress-guard-reads-names-by-their-capital)).
- **The dress is remembered by its facts, on disk**: a reply the guard refused is kept like any other,
  so the same facts are not re-asked until they change. Nothing prunes the folder -- one small file per
  set of facts the model was asked about, in the agent's cache, which may be deleted whenever you like
  ([The dress guard reads names by their capital](../KNOWN-GAPS.md#the-dress-guard-reads-names-by-their-capital)).
- **A `Route` typed in a terminal is not seen at once.** The agent forgets its kept tracker reads when a
  verb runs through the bridge, but a verb typed in a terminal never reaches it: the pages show the change
  when the minute runs out, or at once on the Triage page's Refresh
  ([A Route typed in a terminal reaches the page a minute later](../KNOWN-GAPS.md#a-route-typed-in-a-terminal-reaches-the-page-a-minute-later)).
- **The played view is a first cut.** One tile a worker label: "a worker is many" (`QA DEV (Opus 1)`)
  waits on the agent half knowing its running instances. The faces are the deck series' cast, dealt by
  position; a cast of their own is later. No neural voice (V2's `/narrate`); the browser's
  voice is whatever the machine has, and an authored fifteen seconds a tile is not imposed -- a slide
  lasts as long as its lines take to read, plus the engine's dwell. No Media Session (lock-screen play,
  pause, next). The nonsense register's door is not drawn on the stage. An absent member is not named
  aloud: the chair does not yet say who is out today
  ([The played standup is a first cut](../KNOWN-GAPS.md#the-played-standup-is-a-first-cut)).
- **The prose reads no age, no pull request and no assignee**. The issue's grammar names more
  facts than the read carries: "blocked" also means a review older than N days, and "yesterday" also
  items that moved to review since the last standup. Nothing new is read from the tracker, and the read
  has no time an issue entered review and no age, so *blocked* is the blockers slot (an open, routed
  `verify-close` issue -- waiting on your walk), *yesterday* is the closed-in-the-window slot, and a
  `blocked` label is not read. A clause is the title's head as written -- not lower-cased, so a title
  that starts with a capital keeps it (`#<n>, Rename the slug`)
  ([The standup's prose reads no age, pull request or assignee](../KNOWN-GAPS.md#the-standups-prose-reads-no-age-pull-request-or-assignee)).
- **The dates read is GitHub's, and the CLI's covers one repo.** Commit dates and issue timelines come
  from a GitHub repository ([what moved](#what-moved-and-the-window)); a cards Space, an Azure DevOps
  Space, or a dates read that failed counts every bullet and reads an issue alone as `in progress`. A
  timeline is read to its first 50 labelled and assigned events. On a Space of several repos the terminal
  and the page can date different commits ([The terminal's standup dates a commit from one repository, the page from every repository of the Space](../KNOWN-GAPS.md#the-terminals-standup-dates-a-commit-from-one-repository-the-page-from-every-repository-of-the-space)).
- **A card's trailers are read on a connected GitHub Space only.** The co-author trailers that say which
  model a card's commits credit ride the standup's dates read, so a cards Space, an Azure DevOps Space or a
  dates read that failed reads a card's Agent line and its Assigned worker alone, and a card that names
  neither is the engineer's. Nothing is read from a local checkout
  ([A card's commit trailers are read from GitHub only](../KNOWN-GAPS.md#a-cards-commit-trailers-are-read-from-github-only),
  [#503](https://github.com/johnfrog76/toolkit/issues/503)).
- **`decide` and `look` are always empty.** Their labels are an open item of the spec; only `walk` is
  filled ([The standup's decide and look queues are empty](../KNOWN-GAPS.md#the-standups-decide-and-look-queues-are-empty)).
- **One repo per Space.** A Space spanning several repos says so on its `Tracker` line rather than
  merging them
  ([The terminal's standup refuses a Space with several repositories](../KNOWN-GAPS.md#the-terminals-standup-refuses-a-space-with-several-repositories)).
- **Several repos in one Space.** The verb says so on its `Tracker` line; the route merges labels by name
  and concatenates issues, and fails the whole read if any repo's read fails. Issue numbers from two
  repos could collide. Both are M0 choices; one rule belongs in the contract
  ([The terminal's standup refuses a Space with several repositories](../KNOWN-GAPS.md#the-terminals-standup-refuses-a-space-with-several-repositories)).

### True by design

These are how the rituals read, on purpose, and are not on that list:

- **A launch is proved on macOS here, and walked on Windows.** The pipe returning on Windows PowerShell
  5.1, the model a real `claude` runs, and a real session's first message being the block are `VERIFY.md`
  rows (Gate 12, "StartWork -Launch"); the suite's launch half runs off Windows only.
- **The Corner's milestones in reach are the suggestion's candidates.** A milestone whose every open item is
  in flight, waiting on you or someone else's has nothing to start, and the Corner moves on to the next
  milestone with something to start, or reads `no milestone in reach`.
- **Reached lasts the standup's window.** `milestone B reached` reads while the last close is inside
  yesterday's window (or the one `-Since` widens); after it, the line moves on to the next milestone.
- **Only the played view is dressed** (why, and what the reader sees when it is off, under
  [the agentic layer](#the-agentic-layer), "Where the dressed text shows"). `spoken` is the agent's and the stage's: `Standup -Grain work`
  and the page's Work grain show the prose, Copy copies it, and the queue's sentences, the chair's turn, the turn's
  frame, a slot's fixed line and an idle worker's made-up items are never sent to the model. The decline when no key is set is written to the usage
  log, not into the response -- `spoken: null` says only that nothing was dressed, and `GET /api/env`'s
  `anthropicConfigured` says whether a key is there.
- **Triage's milestones are the Space you are in.** The page's picker reads `GET /api/milestones`, which
  is the active Space's; the page itself asks about the active Space too, so the two agree. Neither takes
  another Space's slug, because a ritual reads the Space you are in, as every other page does.
- **Not on Azure DevOps, by design.** An ADO Space answers `rituals.text.adoTracker` on its `Tracker`
  line (D-TA19: ADO is the human team's board, and its standup is the one the team holds). A local Space
  fills from its cards.
- **The work grain's nouns are the tracker's own words**. A design note is named from its file stem
  (`team-agile.md` is `Team Agile`), not from its heading, which the read does not fetch; a
  `> GitHub:` thread outside the read (closed long ago, another repo) is named `#<n>`; a card's type
  noun is as its heading spells it (`Bug, two closed`, not "two bugs"); and the common stem is lexical --
  two titles that mean the same work but start with different words are two groups. The prose
  says these nouns as they are: `#<n>` for a thread the read does not hold (`I'm also on two more:
  #<n> and Design lifecycle L3.`), `one in Bug` for a card's type.
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
- **Only the issue read's rows are candidates.** The suggestion reads the standup's read, capped like it:
  the same `consts.json` `ghReads` numbers in the CLI and the agent, so the terminal and the page suggest from the same issues.
- **The reads are capped, and alike.** Both halves read up to `consts.json` `ghReads` -- 500 open
  issues, 500 issues in every state and 500 labels, one number per read, read by the CLI's scripts and the
  agent. A repo past a cap loses its oldest issues from that read in both halves, and neither says so.
