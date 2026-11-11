# Known gaps in ToolKit

What the product does not do, and what you see if you try. If you hit one of these, this list is the
answer, not a bug report. The root [README](../README.md) links here.

Each gap below is one block: its title, which is also its anchor; **What you see**, the behaviour as you
meet it; **Where you meet it**, the document and heading that describe that part of the product, and
whose section links back here; and **Issue**, the GitHub issue that carries it. A gap goes when its issue
closes and the fix is merged.

## Known gaps

### Create PR on Azure DevOps needs the branch pushed

**What you see:** On an Azure DevOps board, *Create PR* in the browser runs in the Toolkit's own folder,
not in a clone of the card's repository. It takes the project from the card's ADO Link and the source
branch from its `## Branch` section, so the branch must already be pushed. On a GitHub board *Create PR*
finds the repository's clone on this machine and works from it, an unpushed branch included.

**Where you meet it:** [Azure DevOps](modules/ado.md#the-web-ui), "The web UI"

**Issue:** [#285](https://github.com/johnfrog76/toolkit/issues/285)

### A meeting row draws its actions side by side

**What you see:** A complete meeting's row on the Meetings card shows Close, Edit / send and View details
side by side, and every other meeting row shows Edit / send and View details. Everywhere else a row has
one exposed action and the rest in its `...` menu
([One grammar for dialogs and row actions](../web/README.md#one-grammar-for-dialogs-and-row-actions)).

**Where you meet it:** [Communication](modules/communication.md#close-from-the-browser), "Close, from the browser"

**Issue:** [#287](https://github.com/johnfrog76/toolkit/issues/287)

### A repository's designs move only through a named checkout

**What you see:** The Design tab moves a product's design only where `spaceCheckouts.<slug>.path` names a
clone of its repository
([Configuration](CONFIGURATION.md#spacecheckoutsslugpath----a-spaces-checkout-on-this-machine)); without
one, the tab's foot names the setting. The move is staged in the clone and never committed, and the tab
reads GitHub, so the row keeps its old place until the engineer commits and pushes; choosing the road
again meanwhile is refused by the verb, in its words. A repository's **Search inside** is GitHub's code
search: the default branch only, minutes behind a push, and rate-limited. The note under the results says
so, and a search that cannot run says why in its row.

**Where you meet it:** [the Studio](modules/studio.md#known-gaps), "Known gaps"

**Issue:** [#288](https://github.com/johnfrog76/toolkit/issues/288)

### `Config -Set` cannot declare a Teams recipient

**What you see:** `tkConfig -Set managerWorkflow.communication.recipients.<key>.display=...` answers
`Unknown setting`: `managerWorkflow` is the team's block in `config.default.json`, and `Config` never
writes it. A second recipient is hand-edited into `config.local.json`, and its `"type"` must be
`"channel"` even for a person: `"chat"` is refused as `unsupported type`, and `"person"` as
`DM deferred`.

**Where you meet it:** [Communication](modules/communication.md#getting-a-webhook-url), "Getting a webhook URL"

**Issue:** [#289](https://github.com/johnfrog76/toolkit/issues/289)

### Azure DevOps verbs are hidden, not gone

**What you see:** On a machine with no Azure DevOps in use, `Menu`, `Setup`, the New card dialog and
Settings show only what it can use. The Azure DevOps verbs are still registered, though: typed by name,
most of them (`tkMyWork`) answer with their tier sentence, `Dashboard` prints its local view, and
`LogPeerReview` has no tier check and writes its record to the hub. The bridge still runs them, and the
Azure DevOps routes still exist.

**Where you meet it:** [Azure DevOps](modules/ado.md#tiers-what-happens-when-ado-does-not-answer), "Tiers: what happens when ADO does not answer"

**Issue:** [#290](https://github.com/johnfrog76/toolkit/issues/290)

### Daily reads two weeks, in the browser only

**What you see:** Daily offers this week and last week, in the browser. A timesheet three weeks late has
no page, and no CLI verb prints a week.

**Where you meet it:** [CLI](CLI.md#the-third-line-billable), "The third line: Billable"

**Issue:** [#291](https://github.com/johnfrog76/toolkit/issues/291)

### The Docs tab reads one repository, and only reads

**What you see:** The filter drawer narrows the `docs/` tree by title and path; there is no search inside
the documents' text, and none across other repositories' docs. A document is not edited in the room: a
change is a commit in its repository. An image past the 10 MB the asset route serves is a broken image in
the room (the agent answers 413 and says so); it opens on GitHub.

**Where you meet it:** [web README](../web/README.md#the-shells-frame), "The shell's frame"

**Issue:** [#292](https://github.com/johnfrog76/toolkit/issues/292)

### The standup's decide and look queues are empty

**What you see:** On every Space, Team Agile's standup fills only the `walk` queue. `decide` and `look`
are always empty, because no label is named for them.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#known-gaps), "Known gaps"

**Issue:** [#293](https://github.com/johnfrog76/toolkit/issues/293)

### What moved is counted from the cards

**What you see:** An issue with no card never reads `started`: the issue read carries no time its work
began, so it is closed or in progress, and only a card's `**Started:**` (else `**Created:**`) day can say
`started`. A card's commit count is every hash it threads, not only the ones inside the `-Since` window --
a bullet has no date -- so a card worked over weeks counts all of them the day it closes.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#what-moved-and-the-window), "What moved, and the window"

**Issue:** [#294](https://github.com/johnfrog76/toolkit/issues/294)

### The suggestion hands off, it does not launch

**What you see:** The chair's Next line suggests one next move, and for a crew-sized item its command is
`StartWork <n>` -- the block, carried by hand. `StartWork <n> -Launch` starts a session from a terminal,
and the hand-off box offers **Launch** where `/env` says the launch is on
([the launch](modules/solitaire-agile.md#the-launch-the-block-handed-to-a-session)), but the Next line's
command does not carry `-Launch`.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#the-suggestion-one-next-move-derived), "The suggestion: one next move, derived"

**Issue:** [#295](https://github.com/johnfrog76/toolkit/issues/295)

### The foyer counts no designs or specs

**What you see:** A GitHub row in the Studio's foyer says how a product's ledger stands and its last
deploy, with no count of the designs in flight or of the specs.

**Where you meet it:** [the Studio](modules/studio.md#known-gaps), "Known gaps"

**Issue:** [#296](https://github.com/johnfrog76/toolkit/issues/296)

### Promote files only into the Space you are in

**What you see:** A hub note for another Space shows Promote disabled with "switch to it first".
Promotion opens the thread; moving the note into its product's repository is a commit nothing offers, and
a thread is read, not answered, in the room.

**Where you meet it:** [the Studio](modules/studio.md#known-gaps), "Known gaps"

**Issue:** [#297](https://github.com/johnfrog76/toolkit/issues/297)

### A retired Space stays on the Space list

**What you see:** `RetireSpace` sets `status: archive`: the Spaces card files the Space under Archive and
nothing asks its tracker, but the avatar menu's Space switcher still offers it. The rule for what the
switcher offers (`Select-OfferedSpaces.ps1`, `offered_spaces`) hides only the dismissed demos. To take a
Space off every list, `RemoveSpace` it: the folder and its cards stay.

**Where you meet it:** [the Studio](modules/studio.md#known-gaps), "Known gaps"

**Issue:** [#298](https://github.com/johnfrog76/toolkit/issues/298)

### Every Space is read by one gh login

**What you see:** New Space, the Spaces card and every GitHub read ask `gh` as whoever it is signed in
as. A repository only another login can see reads `Visibility unknown` and `not visible to this login` in
New Space's **Add owner/name** row, and can still be added; switching accounts is `gh auth switch`, in a
terminal, for every Space at once.

**Where you meet it:** [the Studio](modules/studio.md#known-gaps), "Known gaps"

**Issue:** [#299](https://github.com/johnfrog76/toolkit/issues/299)

### Docker does not reach the agent on native Linux

**What you see:** The Docker image is for Docker Desktop (macOS, Windows), whose VM gives
`host.docker.internal` a resolution that reaches the agent's loopback-only bind. A native Linux Docker
Engine resolves it to the bridge gateway instead, a different network namespace from the host's loopback,
so the container cannot reach the agent -- by Docker's own networking model. On native Linux, run
`tkWeb -Dev` instead of Docker. There is no opt-in, non-default bind address for this case.

**Where you meet it:** [Architecture](ARCHITECTURE.md#the-web-ui-is-served-to-the-same-machine), "The web UI is served to the same machine"

**Issue:** [#300](https://github.com/johnfrog76/toolkit/issues/300), with [#11](https://github.com/johnfrog76/toolkit/issues/11) as its history

### A milestone's order is not drawn

**What you see:** `Plan <id> -Rank` keeps the order in `milestones/<slug>.md`, the CLI and the agent read
it the same way, and `Backlog` and `GET /api/backlog` serve it as a table, but no page shows it: Team
Agile's Milestones tab lists a milestone's issues without the order, and the order is not mirrored into a
GitHub milestone's description. A card that is archived leaves a stale line in the file until a person
deletes it.

**Where you meet it:** [Milestones](hub/milestones.md#not-yet), "Not yet"

**Issue:** [#301](https://github.com/johnfrog76/toolkit/issues/301)

### A webhook set after the agent started is not seen

**What you see:** `SendTeams` posts through the running agent, and the agent reads `TEAMS_WEBHOOK_*` from
the environment it was started with: the module loads `.env` in the package root into the shell at
import, and `tkAgent` or `tkWeb -Dev` hands that shell's environment to the agent at launch. A variable
exported before the agent starts is seen; one exported after it started, or in another terminal, or a
change to `.env`, is not seen until the agent restarts (`tkWeb -Stop`, then `tkWeb -Dev`). `SendTeams`
checks the typing shell's own environment first, so with the variable set nowhere "Not sent -- no webhook
configured" names it; with it set in that shell and not in the agent's, the agent's skip reason comes
back instead.

**Where you meet it:** [Communication](modules/communication.md#two-gates-and-they-are-not-the-same-thing), "Two gates, and they are not the same thing"

**Issue:** [#302](https://github.com/johnfrog76/toolkit/issues/302)

### A reply to a conversation comment reads back as its own thread

**What you see:** GitHub has no reply to a conversation-tab comment or a review's summary, so `ReplyPR`
posts a new comment on the pull request that opens with a link to the one it answers. The card's `Reply:`
slot is filled under the original thread, but the next `GetPRComments` reads that new comment as one more
top-level conversation thread, not as a follow-up in the thread it answered. An inline review thread is
not affected: its reply is a real reply and comes back inside it.

**Where you meet it:** [CLI](CLI.md#answering-on-a-github-board), "Answering on a GitHub board"

**Issue:** [#304](https://github.com/johnfrog76/toolkit/issues/304)

### Most CLI suites run their verbs on PowerShell 7 under 5.1

**What you see:** 16 of 52 CLI suites start every child in the host they run in. The rest start `pwsh`
by name, so a run of the CLI suites in Windows PowerShell 5.1 proves their own code on 5.1 but the verbs
they type on PowerShell 7, and a defect only 5.1 shows can pass there; Clause 22 of
`Tests/Test-Portability.ps1` lists them and holds this count to its list. The `ps51` CI job runs every
suite in 5.1, so it proves every suite's own code there and the verbs of those 16.

**Where you meet it:** [Testing](TESTING.md#in-ci), "In CI"

**Issue:** [#271](https://github.com/johnfrog76/toolkit/issues/271)

### The web UI is on TypeScript 6

**What you see:** The web UI pins TypeScript 6.0, and `npm outdated` in `web/` lists `typescript` against
7. In the releases the lock file installs, ts-jest and typescript-eslint declare peer ranges that end
before 7, so with 7 installed `npm ci` refuses with ERESOLVE. It moves when both widen, or when the suites
leave ts-jest, which is a decision of its own.

**Where you meet it:** [web README](../web/README.md#stack), "Stack"

**Issue:** [#305](https://github.com/johnfrog76/toolkit/issues/305)

### Milestones appear on two pages

**What you see:** a GitHub Space's milestones appear on the Stats tab's Milestones card and on Team Agile's
Milestones tab. Both build their rows from the same reader and order and word them by the same rules, so they
agree. But each page has its own route and cache and draws its own row, so for a moment the two can show a
different read, and a milestone can look different in each place.

**Where you meet it:** [Scenarios](SCENARIOS.md#stats-on-a-github-space), "Stats, on a GitHub Space", and
[Team Agile](modules/solitaire-agile.md#milestones-the-tab-and-the-award), "Milestones: the tab and the award"

**Issue:** [#321](https://github.com/johnfrog76/toolkit/issues/321)

### The plan's weekly usage is typed, not read

**What you see:** `Burn`'s weekly burndown shows only the readings someone typed with
`Burn -Reading general=<n>,premium=<n>`, copied from Claude's usage page. Nothing reads the plan's
percentages automatically, because nothing documented carries them per bucket. With no reading this week,
`Burn` says how to record one, and a reading older than `burn.cacheHours` says its renewal is due.

**Where you meet it:** [Usage](hub/usage.md#not-yet), "Not yet"

**Issue:** [#320](https://github.com/johnfrog76/toolkit/issues/320)

## True by design

Some things are true by design rather than by omission, and are not on that list. The deck narration
route (`POST /narrate`) is not served by this agent ([the agent overview](ARCHITECTURE.md#the-agent)). The
`Sync` test suite skips rather than passes when the store has no pre-commit hook ([Testing](TESTING.md)).
A growth or communication route returning 404 with its flag **off** is the design working, not a missing
route ([the modules guide](modules/README.md)). Teams recipients are read from two blocks:
`managerWorkflow.communication.recipients`, the same in every Space, and the active Space's
`communication.recipients`, so switching Space changes only the second
([Communication](modules/communication.md#envs-communication-block)). Team Agile's standup does not read
an Azure DevOps board: on an Azure DevOps Space it prints the ritual with "Azure DevOps is the human team's board ..." on its
Tracker line, because that board's standup is the one the team holds
([Team Agile](modules/solitaire-agile.md#known-gaps)). Only Team Agile's played view is dressed by the
model; the Work grain, Copy and `Standup -Grain work` carry the derived prose, and the counts line is
read on the page and in the brief, not spoken on the stage
([the agentic layer](modules/solitaire-agile.md#the-agentic-layer)).
