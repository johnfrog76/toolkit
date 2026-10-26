# Scenarios -- what each configuration shows, and the test that holds it

The grid of what each configuration shows -- Space status, tier, tracker, every module on or off --
and, beside each expectation, the test that holds it. Every row is an expectation a person can check
with their eyes, and beside it the test that checks it without eyes. Read it to know what a machine
should show, or when a tab, a nav entry or a card appears where it should not.
When a cell changes on purpose, change it here and in the test in the same commit; when a cell reads
wrong, the row says which suite should have caught it (AGENTS.md, "When something READS wrong").

## The axes

A machine is in exactly one cell of each axis at a time:

| Axis | Values | Where it is decided |
| --- | --- | --- |
| **Space status** | `active`, `local`, `archive` | `spaces[].status` in `hub.json` / config; `Start` makes a `local` one |
| **Tier** | 1 (the tracker answers), 2 (the tracker's CLI is there but not signed in or unreachable), 3 (no tracker CLI at all) | the agent's probe, `GET /api/env` -- `Tests/test_tier_parity.py` holds the CLI and the agent to one table |
| **Tracker** | `github`, `ado`, `none` | derived from the active Space's address (`Scripts/Resolve-Tracker.ps1`, `agent/ado/tracker.py`) |
| **Azure DevOps shown** | on, off | DERIVED: `features.ado` if set, else the status AND the tracker -- on only in an `active` Space whose address is Azure DevOps, so a connected GitHub Space reads off with its tracker named -- **the one shared table**, `Tests/fixtures/ado-enabled/table.json`, read by `tkTestToolkit -Setup` and `Tests/test_ado_enabled.py` |
| **Modules** | `growth`, `communication`, `deck`, `organize`, `solitaireAgile`, `lounge`, each on / off / not configured | top-level `features` in `config.local.json`; the engineer's, never an org's (`Tests/test_features.py`). The Studio is not on this axis: it is core (D-S13), and a `features.studio` left in a config is ignored |
| **Sprint awareness** | on, off | `spaces[].features.sprintAwareness` -- a Space-scoped flag |
| **Suggestions** | on (unset, or true), off | `spaces[].features.suggestions` -- a Space-scoped switch riding Team Agile: where Team Agile is on, unset is on; `false` takes the suggestion out of the standup -- the `switch` rows of `Tests/fixtures/suggestion/table.json`, read by `tkTestToolkit -Rituals` and `Tests/test_rituals.py` |
| **How you work here** | `agents`, `alone`, `team` | `spaces[].howIWork` -- the other Space-scoped switch: asked on a GitHub Space (`alone` until answered), derived elsewhere (`team` on Azure DevOps, `alone` with no tracker). Team Agile is on only where its switch is on AND the answer is `agents` -- **the one shared table**, `Tests/fixtures/how-i-work/table.json`, read by `tkTestToolkit -Environment` and `Tests/test_how_i_work.py` |

**Off means absent** (AGENTS.md): a module that is off contributes no verb, no route (404, not 403),
no nav entry, no card and fetches nothing -- and is still NAMED by the inventory (`tkMenu -All`,
`tkEnv`, the System page's Modules card), because a machine has to be able to say what it is not
doing. `off` and `not configured` are different answers there; everywhere else they are the same.

## The web half -- `web/src/shell/scenarios.test.tsx`

The executable form of this section: the REAL module registry, one row per configuration, and what
you see. Turning a module on or off in a row is one flag, which is exactly what the settings drawer
writes. The suite runs in `cd web && npm test`.

### Home's strip, by status, tracker and tier

| Space | Tracker | Tier | Home reads | Why |
| --- | --- | --- | --- | --- |
| active | github | 1 | **Issues \| Board \| Stats \| Design \| Docs** | the gh strip; no Focus, no Actions on gh soil. The Board's cards wear "Pinned on GitHub" and sort first in their lane when their issue is pinned. Design (Studio S2, D-S11; the lifecycle's reader L2) reads the repo's `design/`, `design/archive/`, `spec/` and `spec/archive/` through `gh` and draws one list grouped by state -- Design, Spec, Complete, Archived, the last two collapsed to a count -- a repo with none of the folders taught what they give, files with no id counted under the list; Docs (D-S12), last, lands on the repo's `README.md` with its `docs/` tree folded above it, through the same seam and gate. An ADO or local Space has neither tab |
| active | github | 2 | Board alone | `gh` signed out: the files, nothing asked -- no Design, no Docs |
| active | ado | 1 | **Focus \| Board \| Sprint \| Actions** | the full Home |
| active | ado | 2 | Focus \| Board | no Actions without ADO answering; Sprint only with sprint awareness on |
| active | ado | 2, sprint awareness on | Focus \| Board \| Sprint | Sprint Velocity reads the file cache |
| active | ado | 3 | Focus \| Board | no `az` at all: the files, and the board of them |
| local (Demo) | none | any | **Board** alone -- one tab, no strip | the list is the ADO worklist; without ADO it is the same cards drawn worse (the owner's call). The demo Spaces' tips are at the foot (below) |
| archive | any | any | Focus alone, the retrospective cards; **no Daily** in the nav | nothing is in flight, so no board and no timesheet |
| env not loaded | -- | -- | Focus alone | nothing guessed |

The plan behind it, cell by cell, is `web/src/modules/ado/homeTabs.test.ts` (which card is on which
tab); the strip's order and addresses are `web/src/shell/registry.test.tsx`.

### Stats, on a GitHub Space

| Space | Tier | Stats holds | Why |
| --- | --- | --- | --- |
| github | 1 | **Issue Report, Milestones, Deploys** | the ledger counted, where it is going (one row per milestone, "reached" derived -- every issue closed and at least one -- and "reached, not closed" when GitHub still shows it open), and the last runs |
| github | 2 | no Stats tab | nothing is asked of `gh`, so no milestone is fetched |
| ado, local, archive | any | no Milestones card | the route answers `supported: false` and the plan never names the card: off means absent |

`scenarios.test.tsx`, "Stats on a GitHub Space"; the ordering and the sentence are
`web/src/modules/ado/MilestonesCard.test.tsx`, the rule `Tests/test_milestones.py`.

### The filter drawer, by tab

| Space | Tab | The drawer holds | Why |
| --- | --- | --- | --- |
| ado | Focus, Board | search; ToolKit's card rows (type, tracker link, lane); the repo row (a card with no ADO repository stays in view under it) | as it always was: every row reaches a card or My Work there |
| github | **Issues** | search ("Issue number, title or label"); **the issue filters** -- state, assignee, worked by, kind, severity, milestone | the chips live in ONE place; the list says what they are set to in one line under its header |
| github | Board | search; ToolKit's card rows -- **no repo row** | the repo row matches a card's ADO link, so it is ADO furniture on gh soil |
| local | Board | search; ToolKit's card rows | the files, and the board of them |
| github | **Design** | search over the title, description and id; **kind** (design note, spec) (L2); with words in the box, **Search inside** on the tab's header runs them over the documents' text through the tracker's code search, on the button only (L2b) -- and the Archived group's **outcome** chips, shipped / dropped / nothing said | the list grows with every design; the kind is what a design HAS -- a spec, or a note alone -- and a search opens the collapsed Complete and Archived groups that have a match; search inside says its reason in a row when it cannot run, and that it reads the default branch only |
| github | **Docs** | search over titles and paths; **folder** -- the folders the tree actually has (`docs/`, `docs/hub/`, ...) | narrows the FOLDED `docs/` tree only; the README and its Documentation table are untouched, so the landing page's index is unchanged |
| github | Stats | **the slot, disabled** -- tooltip `No filters on this tab` | filters nothing, by design: a reader of Stats wants the whole picture |
| ado | Sprint, Actions | **the slot, disabled** -- the same tooltip | no section reaches a card there -- yet: a section is one name in `drawerSections` |

The strip's **toolbar slot is on every tab** of a strip: the same filter control, in the same place
and at the same height, enabled where the tab has sections and disabled (still a tab stop, with its tooltip)
where it has none, so nothing on the page moves when a tab is switched. A Space with no strip -- the
local Demo's Board, an archived Space -- has no slot to keep level, and draws it only where a drawer has
something in it. `web/src/modules/ado/routes.slot.test.tsx` renders the GitHub strip on all five tabs.

`scenarios.test.tsx`, "the filter drawer holds what reaches the tab"; the table itself is
`web/src/modules/ado/homeTabs.test.ts` ("drawerSections"); Design's and Docs' filters are
`web/src/modules/ado/docFilters.test.tsx`.

**After a Space switch the drawer is clear**: search, repo, state, type, link and skill tag are back
at their defaults, and Design's and Docs' remembered filters are cleared with them -- a filter chosen in one
Space never narrows the next. The Spaces card's filter and Reminders' are not about one Space and
stay. The reset is the filters slice answering the successful switch (`web/src/shell/filtersSlice.test.tsx`).

### System's cards

Environment, Modules, Log -- and **Test Health at Tier 1 and 2 only** (it reads the test history the
file cache holds). Four cards on a connected machine, three on a Tier 3 one. Never the Face card: it
lives in the Lounge (spec D-L24). Never a Space switcher: the avatar menu is the one place.

### The nav, by module

Home is not a tab: it is the **Space anchor**, one pill at the left after the wordmark --
a home icon and the Space's display name (the slug where it declares none; `Home` with no Space at
all), its tooltip `name · slug · address`. It is the Home entry: it goes Home and is the active entry
there. A thin rule follows it, then the tabs below -- "this Space | yours". Every row of the grid
names the anchor `Home`; the shell test is `web/src/shell/SpaceAnchor.test.tsx`.

The header carries no visibility badge (the owner's call: the header stays as clean as possible). A Space's
`Public` / `Private` is on its row of the Studio's Spaces card, and a write to a public repository says so:

A write says so. The surfaces that write to the tracker carry one line, `This repository is public`,
when the Space's repository is -- said, never asked (`ActionDialog.titles.test.tsx`, `IssueDetailPage.test.tsx`):

| Where | Public | Private, unknown, or not GitHub |
| --- | --- | --- |
| the dialog's **New GitHub Issue**, **Close issue** and pull request doors | the line, above the result | nothing |
| the dialog's card door (**New ToolKit Card**, **Card from a GitHub Issue**) | nothing -- it writes to the hub. The New ToolKit Card door carries a picture field (C2): a visible drop zone with Choose a file and paste, and a checkbox for a snap that shows what is wrong (the before); the card page has the same zone in the cover's box until a cover lands, then Replace cover, Add before and Remove cover in its header | nothing |
| the issue room (severity, Close, Pin) | the line, under the issue's address | nothing |

| Modules on | Nav reads | Why |
| --- | --- | --- |
| none | [Space] \| System · Daily · Studio | the core -- the Studio is in it from the first run, with no flag (D-S13); Daily hides on an archived Space |
| growth | + Growth, before the Studio | |
| communication | + Meetings | -- unless Organize is on too: then Organize's tab carries the meetings and Meetings hides |
| deck | + Decks | -- unless Growth is on too: then the deck launcher sits under Growth and Decks hides |
| organize | + Organize, before the Studio | |
| a leftover `features.studio`, `true` or `false` | nothing changes | the Studio has no switch (D-S13); the line is ignored and is never an error |
| solitaireAgile | + Team Agile, after the Studio and before the Lounge's place -- **on a GitHub Space answered With agents** | today's standup (M0). The switch is the engineer's, the answer the Space's: on an Azure DevOps Space, a Space with no tracker, or a GitHub Space answered Alone (or not yet), the agent serves the flag off and there is no tab -- the "How do I…" table below. An active GitHub Space fills from its issues and its cards, joined on the id; a local one from its cards |
| lounge | + Lounge, **last** | you look up from the work, so the room stands apart |
| all six | [Space] \| System · Daily · Growth · Organize · Studio · Team Agile · Lounge | Meetings and Decks are carried, not lost |

The add-ons are the ENGINEER's, so the same nav shows on Demo (local) and on a GitHub space; only
Home's strip differs there -- and Team Agile, which the Space's answer gates: Demo has no tracker,
so it is absent there. A flag answered `false` reads exactly as one never set.

### A card's menu, by the Organize flag (`scenarios.test.tsx`; the dialog is `Board.remind.test.tsx`)

The board's card and the list's row draw one action model (`cardActions.ts`), so this holds for both:

| Organize | A card's `...` ends with |
| --- | --- |
| off, or not configured | **Open the card** -- no reminder item, and nothing of Organize is fetched |
| on | **Remind me about this**: Organize's New Reminder dialog, the card's title as what and its id as the ref (`docs/modules/organize.md`, "The web UI") |

### The board's lanes, by a card's status (`scenarios.test.tsx`; the rule is `legalMoves.ts`)

Five lanes, in this order, and a card is drawn in the lane its served `status` names. Backlog is first:
a new card is planned there (`NewPrompt` writes `backlog/` unless told `-Now`), and `/api/status` reads
`backlog/` beside `current/`. Done is a drop target, not a list. A drop, or the card's **Move to** item,
runs `Move` through the bridge -- the same verb for every lane (`docs/hub/cards.md`, "State is derived,
never stored"):

| A card's status | Its lane | It may be moved to | Refused, and why |
| --- | --- | --- | --- |
| Backlog | **Backlog**, first | Active, In Progress, Code Review, Done -- each pulls it into `current/` first | -- |
| Active | Active | **Backlog** (nothing is threaded), In Progress, Code Review, Done | -- |
| In Progress | In Progress | Code Review, Done | Backlog: *Threaded work is in play, not backlog.* Active: *A card travels one way.* |
| Code Review | Code Review | Done | Backlog: *Threaded work is in play, not backlog.* Active, In Progress: one way |
| Done | not drawn (Done is `archive/`) | nothing | every lane: one way |

The Studio's foyer counts a row's cards **in play** and says the planned ones after the count, never in
it: `1 card in play: 1 Active; 2 in Backlog`.

### The Demo board on a fresh Start (`scenarios.test.tsx`; the agent's half is `Tests/test_first_run.py`, the CLI's `Tests/Test-Start.ps1`)

A fresh `Start` lands on Demo's Board. Its lanes carry Demo's own names (`laneNames` in
`samples/hub/hub.json`: To do, Doing, Waiting, Done -- none for Backlog, so it keeps the contract's word),
and five tutorial cards are the first run's *do*, each finished by a move the board already allows. The
RecipeBox samples sit in the other lanes, so the To do lane holds the tutorial and nothing else, and
empties as it is walked (`docs/QUICKSTART.md`, "The first run: one command"):

| Card | A fresh Start draws it in | It is done when | The move |
| --- | --- | --- | --- |
| *Start here: pull me onto the board* (`Task H3RE`) | **Backlog** (`demo/backlog/`), alone | it is in To do | drag to To do -- `Move -To Active`, the file to `current/` |
| *Open me and tick my boxes* (`Task T6CK`) | **To do** | its bar is full (every box ticked) | then Done |
| *Find out one thing and write it down* (`Spike F7ND`) | **To do** | its one box, "I wrote what I found under Findings", is ticked | then Done |
| *Say "look at this"* (`User Story R3VU`) | **To do** | it is in **Waiting** | drag to Waiting -- `Move -To CodeReview`, a `**Review:**` line |
| *Drop me on Done* (`Bug D9NE`) | **To do** | it is in `archive/` | drop on Done -- `Archive` |

Walked to the end, Backlog and To do are empty; the last card ends at the **+**.

### The board's Active column, by the WIP limit (`scenarios.test.tsx`; the render is `Board.inPlay.test.tsx`)

`limits.inPlay` is one number on this machine (`Config -Set limits.inPlay=5`), served once by `/api/env`
as `config.inPlayLimit`. The Active column's head carries the count of cards **in play** -- every lane of
`current/`, never the Backlog and never Done -- and goes amber (Fluent's warning badge) past the number.
It is a line the board says and never a gate: nothing is refused, no drop is blocked, no card is hidden,
and the count ignores the board's filters. `Status` opens with the same line (`docs/CLI.md`).

| `limits.inPlay` | Cards in play | The Active column's head |
| --- | --- | --- |
| unset (or below 1) | any | no line at all |
| 5 | 4 | `in play 4`, quiet |
| 5 | 5 | `in play 5`, quiet |
| 5 | 7 | `in play 7 of 5`, **amber** |

### The settings drawer's "How do I…" (settings by workflow; `HowDoI.test.tsx`)

| Opened | What the section shows |
| --- | --- |
| from the avatar menu, no anchor | unfolded: every question, the CLI's state word as a chip (`on` / `off` / `not configured`), Change or Set it up where the entry has a key, nothing on a sentence |
| at an anchor (a Change link, a tip, the Connect card) | FOLDED to its heading, so the drawer lands on the key's row; one click unfolds it |
| the agent's inventory did not answer (no PowerShell) | the questions and sentences, no chips, one line saying the states are the CLI's |

**How do you want to work in `<Space>`?** is the one question that is also asked, and the answer is
the SPACE's: three radios under its sentence -- *With agents*, *Alone*, *On a team in Azure*, each with
its one sentence -- and the Space's tracker says which can be picked. A choice the Space cannot make is
disabled with one sentence saying why, never hidden. A pick writes `spaces.<slug>.howIWork` through
`PUT /api/config` -> `Config -Set -Hub`; Team Agile's own switch is the row's **Change**
(`scenarios.test.tsx`, "How do you want to work in `<Space>`?: the tracker says which answers there are, and
the tab follows"; the radios themselves in `HowDoI.test.tsx`). With the switch on:

| The Space | Checked | Can be picked | The sentence under the radios | A pick writes | Team Agile tab |
| --- | --- | --- | --- | --- | --- |
| GitHub, nobody has answered | Alone | With agents, Alone | On a team in Azure is an Azure DevOps Space's answer; this Space's tracker is GitHub. | `spaces.<slug>.howIWork=<answer> -Hub` | absent |
| GitHub, With agents | With agents | With agents, Alone | the same | the same | there, after the Studio |
| GitHub, Alone | Alone | With agents, Alone | the same | the same | absent |
| Azure DevOps | On a team in Azure | none -- locked | Their board holds the rituals; Team Agile is off here. | nothing | absent |
| no tracker (your own cards) | Alone | none -- locked | Connect a tracker to unlock working with agents. | nothing | absent |

The Saving state: a pick is checked at once, the other answers lock, a tiny **Saving…** spinner
stands beside the group and the group is `aria-busy` until `Config -Set` answers -- about three seconds
through the bridge. On success the spinner goes; a refusal puts the pick back and shows the CLI's sentence
under the radios. With *With agents* chosen and Team Agile's own switch off, one more line says the answer
waits for the switch.

### The Studio's Prompts card, by how you work (`scenarios.test.tsx`, "the Studio's Prompts card, by how you work"; the card in `PromptsCard.test.tsx`)

The card is core, on every Space, and it is three filters (the house's `FilterBadge` radios). Its **ToolKit**
filter is the Space's set out of `agentic/prompts.json`, by the active Space's answer to **How do you want to
work?** -- `/env`'s `howIWork`, the agent's `how_i_work()`, which the web reads and never re-derives; **Your
hub** is every prompt in the hub's `agentic/` and `agenticExtensionPath`, whatever the answer; the third,
named for the Space, is its repository's own `agentic/`, read by the agent through `gh`. The prompts an add-on
ships are absent while it is off (`Tests/test_studio_prompts.py`); the rows below are the core's.

| The Space | `howIWork` | ToolKit shows | Counted in the info tip |
| --- | --- | --- | --- |
| a GitHub Space nobody has answered for, or answered **Alone**; your own cards | `alone` | `build`, `new-issue`, `pr-review`, `pr-suggest` | 5 more, for working on a team in Azure |
| a GitHub Space answered **With agents** | `agents` | `build`, `new-issue`, `pr-review`, `pr-suggest` | 5 more, for working on a team in Azure |
| an Azure DevOps Space, connected or not | `team` | `ado-comments`, `build`, `new-bug`, `new-user-story`, `pr-publish`, `pr-review`, `pr-ship`, `pr-suggest` | 1 more (`new-issue`), for working with agents and alone |

Team Agile's switch does not change the set: a GitHub Space answered **Alone** with the switch on still shows
the `alone` set. The ways of working and their words are the question's answers in
`Config/settings-workflows.json`, so the card says `with agents`, `alone`, `on a team in Azure` as the drawer does.

The third filter is drawn from the agent's one answer, the response's `space` (`PromptsCard.test.tsx`):

| The active Space | `space` | The filter row |
| --- | --- | --- |
| a GitHub Space whose address names a repository that is not this package | `repo` set, `isToolkit: false` | **ToolKit**, **Your hub**, **\<Space name\>** -- the third's rows are that repository's `agentic/*.prompt.md`, and its empty state says that is what it would list |
| ToolKit connected to itself (the Space's repository is the package's own origin) | `repo` set, `isToolkit: true` | **ToolKit**, **Your hub** -- its folder is the first filter already |
| an Azure DevOps Space, a Space with no address, an owner-grained address, or a machine below Tier 1 | `repo: ""` | **ToolKit**, **Your hub** |
| an older agent that sends no `space` | absent | **ToolKit**, **Your hub** |

Switching Space changes the filter with it: a chosen third filter on a Space that has none reads as ToolKit.

### The avatar menu's Space entry, by count (the two rows here, the detail in `AvatarMenu.test.tsx`)

The threshold is one constant, `SPACE_QUICK_MENU_THRESHOLD` (8) in `web/src/shell/SpaceQuickMenu.tsx`.

| Spaces listed | The Space entry opens | Why |
| --- | --- | --- |
| 2 to 8 (at the threshold) | the plain submenu: one radio row per Space, in declaration order, the active one checked | a dropdown holds this many |
| 9 or more (past it) | a quick menu: a focused box, then the active Space first (checked) and the rest in declaration order, capped at 8, and **View all** at the foot. Typing narrows by name or slug; Enter or a click switches through the same call; **View all** lists every Space in the same scrolling box; `No Space matches '<text>'` when nothing does; Escape returns to the Space entry | past about eight a dropdown cannot hold them; the switcher people know from GitHub's branch picker and Slack's workspace list |

### The connect wizard, `/connect/<slug>` (settings by workflow W2; `ConnectPage.test.tsx`, `tkTestToolkit -Connect`)

| The Space | What the wizard says on step 1 | Step 3 writes | Step 4 |
| --- | --- | --- | --- |
| no address | "works from your cards alone -- a whole shape, not a missing step"; steps 2-4 wait | -- | -- |
| `https://github.com/<owner>` | "a GitHub owner -- pick the one repo this Space is" | `-Repo owner/name` -- the address becomes repo-grained | "milestones, not sprints" |
| `https://github.com/<owner>/<repo>` | "one GitHub repo" | already done | "milestones, not sprints" |
| `https://dev.azure.com/<org>` | "an Azure DevOps organisation, projects inside it"; the Space is active | `-Projects` (the ticked projects, first repo each) | the sprint switch |
| an address, but `local` -- the GitHub demo as shipped | the address, "local until you connect it"; step 1 not done; the button reads **Connect** and saves the same address, which makes it active | -- | -- |
| a shipped demo Space (the Azure demo, `azure-demo`, as shipped: no address) | any of the above, plus step 5: your slug, Make it mine | -- | -- |

### The demo Spaces' tips, at the foot of Home (`settingsWorkflows.test.ts`, "the demo Spaces' tips")

They rotate first, `connect-github` first of all, then `connect-azure`, then the Demo's; the discovery
tips (a module not configured) follow. The old "switch to Example" tip is gone: `connect-azure` says it.

| Machine | Tips the demo Spaces add | Retired by |
| --- | --- | --- |
| `tkStart`, in Demo | `connect-github` (Try it: `/connect/github-demo`), `connect-azure` (Try it: `/connect/azure-demo`), then the Demo's own: "This is the Demo Space: cards with no tracker." | connecting each demo; leaving Demo |
| in the GitHub demo or the Azure demo, still `local` | its own connect tip (and the other's); the generic "connect a board" tip stands aside there | connecting it |
| a demo connected (`active`) | none from it | -- |
| **Hide Demo** on | none: a Space the list leaves out is not declared | turning it off |
| a hub without the demos | none; the drawer's "How do I connect…" questions walk the Space you are in | -- |
| a local Space of your own | the generic "connect a board to a GitHub repo or an Azure DevOps organization" (Try it: `/connect/<slug>`) | connecting it |

### The Studio's foyer (core, always there; `web/src/modules/studio/FoyerCard.test.tsx`, `foyer.test.ts`)

The foyer is the **Spaces** card. Every Space `/env` offers has a row (D-S13), with a badge naming its
kind -- `GitHub`, `Azure DevOps`, `Your own cards`.

| Spaces offered | The foyer shows |
| --- | --- |
| none at all | `No Spaces yet`, "A Space is where you work on one piece of software: your cards on a board, and the tracker's issues, designs and stats beside them once it is connected." under it, and the **+** at the foot |
| a cold `Start` (the three demo Spaces, no `gh`, no `az`) | Azure demo, Demo and GitHub demo, each with a line that teaches; nothing reads as an error |
| GitHub Spaces, connected, `gh` signed in | one row each: `Public; 4 open, 2 closed this week, 1 sev1 open; last deploy 3 days ago, green`; the Space you are in marked `you are here` |
| ...its repository public | the line leads `Public;` |
| ...its repository private, or `INTERNAL` | the line leads `Private;` |
| ...the tracker did not answer its visibility (below Tier 1, `gh` signed out, a failed read) | the line leads `Visibility unknown;` -- said, never guessed or left out |
| a GitHub Space that is not connected yet (`local`) | `not connected yet -- connect it, and this row shows its open issues and last deploy` -- no visibility word: it was not asked |
| a connected GitHub Space with `gh` signed out | `Visibility unknown; not connected yet -- connect it, and this row shows its open issues and last deploy` |
| an Azure DevOps Space or one with no address, the one you are in | no visibility word (the rule is not asked there); its cards from `/api/status`: `3 cards in play: 2 Active, 1 Code Review` under the Space's lane names (or `no cards in play`) |
| an Azure DevOps Space or one with no address, another one | the same, counted in place from `/api/status?space=<slug>` under THAT Space's lane names; a read that fails says `Could not read this Space's cards -- the agent did not answer.` on that row only |
| ...archived, and not the one you are in | `go in to see its cards` -- not asked |
| ...and its tracker cannot answer | `; not connected yet -- connect it, and its board's work items come in beside its cards` (ADO, not `active`), or `; no tracker -- connect it to a GitHub repo and this row shows its open issues and last deploy` (no address) |
| an archived Space | its row, marked `archived`, with no connect teaching |
| any of these, while the reads are out | the card's own `Reading the Spaces...`, then the whole list at once -- never a row with a placeholder line |
| more than five after the filter | five a page, the pager at the foot's centre; the chip still the total |

**The card's filter**: one exposed row of tags above the list, the Reminders card's -- **All | Products | Work | Out of box | Archive**
-- each with its count (none for an empty bucket), opening on **All**, remembered per browser. One Space is in exactly one entry besides All, by the first
rule that fits (`spaceBucket` in `foyer.ts`; the executable rows are `scenarios.test.tsx`, "the Spaces
card's filter, by kind of Space"):

| A Space that is... | Is listed under |
| --- | --- |
| archived (`status: archive`), whatever its tracker | All, Archive |
| a shipped demo (`example: true`), the GitHub demo included | All, Out of box |
| a GitHub Space of your own | All, Products |
| an Azure DevOps Space, or your own cards with no tracker | All, Work |

The filter is honest: it lists only what matches, so **Archive** leaves out the Space you are in (the
nav's Space anchor still says where you are). The header's count chip is the total number of Spaces. A
filter that matches nothing says so under the tags -- `No archived Spaces`, `No product Spaces`,
`No work Spaces`, `No out-of-box Spaces` -- and the tags, the header and the chip stay where they were.

The card's foot carries a **+** in every configuration -- with or without `gh`, on any Space: the
New Space dialog, your repositories when `gh` can list them and an `owner/name` field when it cannot,
or your own cards (`NewSpaceDialog.test.tsx`).

A row's one action is **Go into \<name>**: the avatar menu's switch, then that Space's Home (on GitHub, its
Issues). A Space that is neither `active` nor `archive` has **Connect \<name>** in its `...`, the wizard at
`/connect/<slug>`. The end of a Space's life is in the same `...` (`scenarios.test.tsx`, "Retire and
Remove in a Space's row menu"; the confirm is `SpaceLifecycleDialog.test.tsx`), never on the avatar menu's
Space list:

| A Space that is... | Its `...` offers |
| --- | --- |
| another Space, not archived | **Retire \<name>** and **Remove \<name>** |
| the Space you are in, not archived | **Retire \<name>** only -- a Space is not removed from under you |
| archived, and not the one you are in | **Remove \<name>** only |
| archived, and the one you are in | neither |

Each opens the house confirm with the verb's own `-WhatIf` under the question -- for a Remove, the folder
that stays and its cards counted -- and the shipped Azure demo's Remove is refused there in the verb's
words. Under the
foyer, **Hub Designs**: the hub's `design/` notes, a note that names a Space carrying a chip that switches into it; a note with a thread that a declared GitHub Space can read
opens as the note and then its thread, in one viewer, whichever Space you are in
(`DesignsCard.test.tsx`). A hub with no `design/` folder -- one an older `Start` copied out; the sample hub
now carries the four folders -- says `No design/ folder yet`, not an error, and its + makes the folder.
`Tests/test_studio.py` holds the agent's half: the `space` argument on `/issue-report` and `/deploys`; `Tests/test_ledger.py` the one read every GitHub row now comes from, `GET /api/studio/ledger`.

### Team Agile's standup (on; `web/src/modules/solitaireAgile/StandupPage.test.tsx`)

Showing the standup is attending it: the page posts once to the attend route, which re-arms the `standup`
reminder when one is set (nothing with Organize off). With both flags on, the settings drawer carries a
Team Agile section (the reminder: a time and the days), saved through `POST /api/cmd/Standup`.

| The route answers | The page shows |
| --- | --- |
| the tracker read (`tracker.ok` true), a fresh browser | **the Agenda**, the first tab of **Agenda \| Detail \| Work \| Brief**: its one sentence (`Here you can see the work items you can in fact kick off now, with the Work it now button.`), a **Cards \| List** toggle (cards; remembered), and two lanes from the response's `agenda` -- **Since `<day>`** (`Since Friday 23 October`: the issues closed and the cards archived in the window, no action) and **Waiting on you** (Active and Code Review cards and routed open issues, the suggestion's pick first, each with ONE button: **Work it now**, the hand-off box, or **Review it** on what waits on a review). No In Progress card, no `backlog/` card, no lane badge, no Yesterday or Today: each tile is the board's cover, title and progress and one fact with a long date (`Active since Friday 23 October`, `In review since ...`, `Closed Saturday 24 October`, `Archived ...`). No text and no brief on it; **Copy** carries the text it carried before (the last grain read, `text` in a fresh browser) and **Play** plays the same standup (`scenarios.test.tsx`, "the Agenda") |
| the same, on Detail, Work or Brief | the standup's first line as the card's header, every line after it verbatim in a monospace block; each `#<n>` the response names links to its issue, and each item says what moved after its number where it adds to the slot (`(started)`, `(started, 2 commits)`, `(2 commits)`). Above it, the chair's reading -- the `brief`, one small line each -- opens on the counts line, `Since <day>: ...`, so the velocity is at the top of the page. Besides the numbers: **Copy** (the grain on screen, exactly; "Copied!" for a moment) and **Play**, quiet, in the header. The Agenda's **Work it now** opens the hand-off block in a copy box -- one `POST /api/cmd/StartWork`, the block verbatim, one **Copy**; a refusal shows the verb's sentence |
| the tracker and the cards read, joined (`source: both`, a GitHub Space) | the same page: each `#<n>` links to its issue, a card of its own shows its id with no link, and a `Check` line (a card and its issue disagreeing) is text like any other line |
| a suggestion, the Space's switch on (unset or true), and nothing waiting on you | the chair's reading's last line is the suggestion, drawn as its own row: the line verbatim (`Next: #141 is opus-sized and well defined -- send it to the crew? (tkStartWork 141)`), its action -- **Start work** (the hand-off box) for a start or a delegation, **Open Triage** for a route -- and a dismiss. A dismiss shows the next candidate's line, and with none left today's `Next: nothing is waiting on you.`; it holds for the session, per item, in this browser only (`scenarios.test.tsx`, "the chair's suggestion") |
| something waiting on you, or `spaces.<slug>.features.suggestions=false` | no suggestion row: the brief as it came, its Next line the queue's (`Next: the walk -- 1 on the PC.`) or today's |
| the suggestion on (the PM Corner) | at the head of the page, above the card, the Corner's line verbatim (`3 more issues to get milestone B - start #5 now`) and its chevron, which opens the same hand-off box as **Start work**; the brief below stops above the Corner's line; with the switch off, on an Azure DevOps Space or with the tracker down, no Corner (`scenarios.test.tsx`, "the PM Corner") |
| a milestone reached in the window | the Corner reads `milestone B reached: see Milestones`, no chevron; the link opens the Milestones tab. The standup never throws confetti |
| no tracker (`tracker.ok` false) | the same page: the chair's two lines and the `Tracker` line with the reason -- the ritual happens anyway; no links; Play |
| nothing (the agent is away) | `Could not read today's standup` -- an error, never an empty standup; no Play |

**Play** opens `/deck/ritual/standup`, the same standup played on the Remote Standup's stage
(`docs/modules/solitaire-agile.md`, "The played view"): Team Agile's route, chromeless, there with
`features.deck` off and absent with `features.solitaireAgile` off whatever the deck flag says
(`scenarios.test.tsx`, "the played standup follows Team Agile's flag"). What it plays is held by
`stage/standupDeck.test.tsx` and `stage/StandupPlay.test.tsx`. On the joined source the stage reads an
item as the page does: an issue is `#<n>` (spoken `issue <n>`), linked; a card of its own is its id
(spoken `card <id>`), with no link (`scenarios.test.tsx`, "the played standup names an issue").

The text is the shared fixture's golden (`Tests/fixtures/rituals/`), the same bytes the CLI's
`Standup` and `Tests/test_rituals.py` assert.

### Team Agile's triage (on; `web/src/modules/solitaireAgile/TriagePage.test.tsx`)

The tab carries a **Standup | Triage** strip, each an address (`/solitaire-agile`, `/solitaire-agile/triage`);
the nav keeps ONE Team Agile entry, lit on both, and Triage has the chrome (`scenarios.test.tsx`, "Triage
is a page under Team Agile's one nav entry"; `RitualPage.test.tsx`).

| `GET /api/ritual/triage` answers | The page shows |
| --- | --- |
| open issues (`tracker.ok` true) | ONE issue, the group with no milestone first; above it its milestone's context line ("No milestone -- 2 open, 2 routed, 0 unrouted" -- routed is someone has it); under its title who has it, then its severity ("me · sev2", "@octo-crew · no severity", "Sonnet · no severity", "nobody · sev3"); under it the three questions -- Milestone (the OPEN milestones from `/api/milestones`), Severity (`sev1`-`sev3`), Size (**me** first -- `Route <n> -Assign me`, pressed when the issue is yours -- then the repo's worker labels, then `deep-water`). Each answer is one `POST /api/cmd/Route`; **Next** skips; "n of N" in the header |
| `deep-water` chosen | its two moves, in a row that was always there: **Assign Fable** (`Route <n> -Size fable -DeepWater`) and **Split**, which opens the new-issue dialog with the issue as its parent (`NewItem -Parent <n>`: each piece a sub-issue) |
| the verb refuses | its sentence, in the status line under the questions; nothing moved |
| past the last issue | `That was every open issue`, with Start again |
| no open issue | `Nothing is open to triage` |
| no tracker (`tracker.ok` false) | `Triage reads a GitHub Space`, with the reason; no questions |
| nothing (the agent is away) | `Could not read the open issues` -- an error |

Nothing moves between issues: the title is one line, the deep-water row is always laid out, and the
status line is a fixed three lines.

### Team Agile's milestones (on; `web/src/modules/solitaireAgile/MilestonesPage.test.tsx`)

The strip reads **Standup | Triage | Milestones**; Milestones is `/solitaire-agile/milestones`, under the ONE
Team Agile entry, with the chrome, and absent with the flag off (`scenarios.test.tsx`, "Milestones: a page
under Team Agile's one entry").

| `GET /api/ritual/milestones` answers | The page shows |
| --- | --- |
| milestones, none reached and not yet awarded | one row each, in flight first: the title, its state (`open`, `awarded`, `no issues yet`), a bar of closed over total with `5 of 8 closed` under it, `due <day>` where there is one, `closed on the tracker` where GitHub closed it, and its GitHub link; no dialog, no confetti |
| a reached milestone this browser has not awarded | the award dialog over the tab: `Congratulations: <title> reached!`, `12 issues closed, 1 October 2026 to 24 October 2026.`, the picture (the Team Agile wordmark, a stand-in), and confetti once inside it -- nothing rains under reduced motion. Close: the next one waiting, else the tab with it `awarded` |
| the same, a later visit (the browser's mark set) | the tab, the milestone `awarded`, no dialog, no confetti |
| a milestone with no issues | `no issues yet`, open or closed on GitHub; never reached, never awarded |
| no tracker (`tracker.ok` false) | `Could not read the milestones`, with the reason |
| no milestones | `No milestones yet` |
| nothing (the agent is away) | `Could not read the milestones` -- an error |

### The Lounge (on)

Face, Go, Words, Tic-tac-toe -- four cards, two by two; one action, Skins; no numerals, no inputs.
`web/src/modules/lounge/Lounge.test.tsx` and its siblings.

## The CLI half -- `tkTestToolkit`

`-Environment` step 5 holds settings by workflow's parity against the real resolver: every inventory
row has a question, every entry names a row, `promptsRoot` is first, and `Env` prints the question
before the row.

| Scenario | What you see | Suite |
| --- | --- | --- |
| Azure DevOps shown / hidden, every status × flag | `tkMenu` lists the ADO verbs or lists what is left as Cards; `tkSetup` states the tier; the inventory names Azure DevOps `off (features.ado ...)` when hidden | `-Setup`, over the shared table |
| a module on / off | its verbs resolve after `Import-Module` or are not recognised; `tkMenu -All` names it `on` / `off (Config -Set features.x=true)` / `not configured`; `-Help` exists or does not | `-ModuleCommands`, `-Menu`, `-Environment` |
| the two renderers agree | `tkMenu -All`'s foot and `tkEnv`'s block print one identical inventory | `-Environment` |
| a tracker verb, per Space | prints `In <Space> (<tracker>)` before it acts; refuses an id that belongs to the other tracker | `-Setup` |

## The agent half -- `python3 -m pytest Tests/` (Windows: `python` or `py -3`)

| Scenario | What you see | Test |
| --- | --- | --- |
| a module's route with the flag off | **404**, not 403; no data read | `test_growth.py` (`test_every_read_route_is_404`), `test_reminders.py`, `test_manager.py` |
| the pane's routes asked about another Space (`?space=<slug>`) | that Space's repos and tier; an ADO one `supported: false`; an undeclared slug **404** | `test_studio.py` |
| a Space's repository visibility (`/visibility`) | `public`, `private` (`INTERNAL` too) or `unknown`, once per repository and held; an ADO Space or no tracker `supported: false` with `gh` never asked; below Tier 1 `unknown`, `gh` not asked | `test_visibility.py` |
| the flag's scope | an engineer flag holds across every org and an org cannot override it; the one org flag switches with the org | `test_features.py` |
| the tier | the CLI's and the agent's tier rules are one table | `test_tier_parity.py` |
| Azure DevOps shown | the shared table, from the Python side | `test_ado_enabled.py` |
| `/env`'s org state | active / local / archive, and what identity means under each | `test_env_org_state.py` |

## In a browser -- `cd web && npm run smoke`

`--modules=off` (the default) and `--modules=on` drive the real pages against a running stack: the
off run asserts no Growth or Meetings nav entry, no growth page, no 1:1 page and **no module data
requested**; the on run asserts the entries, the pages and that the data was asked for. Organize is
read from `/env` in-page. The Lounge's on-run check is still owed (deferred on the M1 card).

### The walk, when the grid changes

For a change that touches the strip, the nav or System, walk this once with a fresh `tkWeb -Dev`;
it takes five minutes and needs no data:

1. On an ADO Space, Tier 1: the anchor at the left reads the Space's name and is lit; Home reads Focus | Board | Sprint | Actions; System has four cards, and the anchor takes you back.
2. Switch to Demo from the avatar menu: the anchor's face changes with it; Home is the Board alone, no strip; the demo Spaces' tips at the foot.
3. Switch to a GitHub Space: Issues | Board | Stats | Design | Docs; Home lands on the Issues, Design lists the repo's designs grouped by state, and Docs opens on the README -- a link in it to `docs/` opens that document in the same room.
4. Settings, Modules: turn each add-on off and on. The nav entry leaves and returns at once, with no
   reload; the Modules card on System says `on` / `off` as you go; Lounge on shows four cards.
5. With the Lounge on, wear a skin from its dialog: every page, the face picker and the charts take
   the skin's palette; pick a theme from the avatar menu and the skin comes off.
