# Known gaps in ToolKit

What the product does not do, and what you see if you try. If you hit one of these, this list is the
answer, not a bug report. The root [README](../README.md) links here.

Each gap below is one block: its title, which is also its anchor; **What you see**, the behaviour as you
meet it; **Where you meet it**, the document and heading that describe that part of the product, and
whose section links back here; and **Issue**, the GitHub issue that carries it. A gap goes when its issue
closes and the fix is merged.

Each add-on's own document ends with a "Known gaps" section. Every gap it lists is a block here, and
links to it; what that add-on does on purpose sits under that section's "True by design" heading.

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

### Azure DevOps verbs are hidden, not gone

**What you see:** On a machine with no Azure DevOps in use, `Menu`, `Setup`, the New card dialog and
Settings show only what it can use. The Azure DevOps verbs are still registered, though: typed by name,
most of them (`tkMyWork`) answer with their tier sentence, `Dashboard` prints its local view, and
`LogPeerReview` has no tier check and writes its record to the hub. The bridge still runs them, and the
Azure DevOps routes still exist.

**Where you meet it:** [Azure DevOps](modules/ado.md#tiers-what-happens-when-ado-does-not-answer), "Tiers: what happens when ADO does not answer"

**Issue:** [#290](https://github.com/johnfrog76/toolkit/issues/290)

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

### The terminal's standup dates a commit from one repository, the page from every repository of the Space

**What you see:** On a Space that spans several GitHub repositories, the CLI's `Standup` asks only the
Space's one repository for its commit dates, and the Team Agile page asks every repository. A commit
made to another repository of the Space reads undated in the terminal, and is dated and counted on the
page, so the two counts lines can differ.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#what-moved-and-the-window), "What moved, and the window"

**Issue:** [#316](https://github.com/johnfrog76/toolkit/issues/316)

### The foyer's design counts can differ from the Design tab's

**What you see:** A GitHub row in the Studio's foyer counts a product's designs and specs from GitHub's
default branch. The Design tab, where this machine has a ready checkout of that repository, reads the
clone's working tree instead. A design moved in the clone and not yet committed and pushed is in its new
place on the tab and in its old one in the foyer's counts, so the two can differ by a staged move.

**Where you meet it:** [the Studio](modules/studio.md#the-routes), "The routes"

**Issue:** [#431](https://github.com/johnfrog76/toolkit/issues/431)

### Promote files only into the Space you are in

**What you see:** A hub note for another Space shows Promote disabled with "switch to it first".
Promotion opens the thread; moving the note into its product's repository is a commit nothing offers, and
a thread is read, not answered, in the room.

**Where you meet it:** [the Studio](modules/studio.md#known-gaps), "Known gaps"

**Issue:** [#297](https://github.com/johnfrog76/toolkit/issues/297)

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

### A reminder's bucket depends on the machine's time zone

**What you see:** A reminder's time is stored as local time with no offset. A hub synced between two machines in different
time zones can show the same reminder as due on one and as upcoming on the other.

**Where you meet it:** [Organize](modules/organize.md#known-gaps), "Known gaps"

**Issue:** [#374](https://github.com/johnfrog76/toolkit/issues/374)

### A meeting's follow-up does not become a reminder

**What you see:** Team Agile's `Standup -Remind` writes a reminder, but `MeetingAgenda` does not: a follow-up agreed in a
meeting stays a line in the meeting's record until someone types `NewReminder` for it.

**Where you meet it:** [Organize](modules/organize.md#known-gaps), "Known gaps"

**Issue:** [#375](https://github.com/johnfrog76/toolkit/issues/375)

### A reminder that names an archived card does not link to it

**What you see:** A reminder whose reference is the id of a card in `current/` is a link to that card. When the card is
archived, the row names the card and says `(done)`, with no link: the card page reads the active Space's
`current/` only, so the web UI has nowhere to open an archived card.

**Where you meet it:** [Organize](modules/organize.md#known-gaps), "Known gaps"

**Issue:** [#376](https://github.com/johnfrog76/toolkit/issues/376)

### An archived training leaves its quarter's count

**What you see:** The quarter line adds up the trainings in `growth/current/` only. A training moved to `growth/archive/`,
which is what *Archive* in the web UI and `NewGrowth -Close` do, stops counting toward the quarter it was
dated in. The line shows the current quarter only, with no history of earlier ones.

**Where you meet it:** [Growth](modules/growth.md#known-gaps), "Known gaps"

**Issue:** [#377](https://github.com/johnfrog76/toolkit/issues/377)

### An agenda line becomes a card from the terminal only

**What you see:** `NewPrompt -Title "<the line>" -From <record>` makes a card from a meeting's agenda line; the Meetings
page has no action that does. The card names its record in a `**From:**` line, and the record gets no
line back naming the card.

**Where you meet it:** [Communication](modules/communication.md#known-gaps), "Known gaps"

**Issue:** [#378](https://github.com/johnfrog76/toolkit/issues/378)

### Deck voices and your own decks are not made in the Toolkit

**What you see:** A deck is code compiled into the web build, so a deck of your own is a file added to this repository's
tree and cannot be kept in your hub. Nothing in the Toolkit bakes a deck's voice files: they are made
elsewhere and copied in beside the deck, and a slide with no file for a voice does not offer that voice.
The engine's `ShellEmbed` piece is not carried, so a deck cannot embed a shell's output.

**Where you meet it:** [the deck module](modules/deck.md#known-gaps), "Known gaps"

**Issue:** [#379](https://github.com/johnfrog76/toolkit/issues/379)

### A prompt is not started from the Prompts card

**What you see:** A row on the Studio's Prompts card offers Open, with Copy reference and Copy prompt in its menu. There
is no action that starts work from a prompt: the text is copied and carried to a session by hand.

**Where you meet it:** [the Studio](modules/studio.md#known-gaps), "Known gaps"

**Issue:** [#380](https://github.com/johnfrog76/toolkit/issues/380)

### New Space lists the first 1000 repositories

**What you see:** In the New Space dialog, an owner with more than 1000 repositories, or more than 1000 shared with you,
lists the first 1000 and says so. A repository past them is added by typing it as `owner/name`, which
reads it the same way.

**Where you meet it:** [the Studio](modules/studio.md#known-gaps), "Known gaps"

**Issue:** [#381](https://github.com/johnfrog76/toolkit/issues/381)

### New Space adds one existing GitHub repository at a time

**What you see:** The Spaces card's **+** adds one Space each time. It does not add several at once, create a GitHub
repository, or list an Azure DevOps organisation's projects: an Azure DevOps Space is added from the
terminal with `NewSpace <slug> -Address <url>`, then `Connect <slug> -Discover`.

**Where you meet it:** [the Studio](modules/studio.md#known-gaps), "Known gaps"

**Issue:** [#382](https://github.com/johnfrog76/toolkit/issues/382)

### The agent and the CLI each resolve the agentic extension path

**What you see:** Nothing you would see while the two agree. The CLI resolves `agenticExtensionPath` in
`Get-P20AgenticExtensionPath` and the agent resolves it again in `agentic_extension_path()`, and no
shared fixture holds the two to one answer, so a change to one could make the Prompts card and the
terminal read different folders.

**Where you meet it:** [the Studio](modules/studio.md#known-gaps), "Known gaps"

**Issue:** [#383](https://github.com/johnfrog76/toolkit/issues/383)

### A launched session does not report back to the page

**What you see:** `StartWork <n> -Launch` starts a detached session. Its result is its log and, when it gets there, a pull
request on the tracker. The Team Agile page has no list of launched sessions saying which are running
and which are done: you look at the tracker or the log.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#known-gaps), "Known gaps"

**Issue:** [#384](https://github.com/johnfrog76/toolkit/issues/384)

### The bell and Home's tips carry no suggestion

**What you see:** The suggestion, the one derived next move, is drawn on the chair's Next line and in the PM Corner. The
notification bell and the tips on Home do not show it.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#known-gaps), "Known gaps"

**Issue:** [#385](https://github.com/johnfrog76/toolkit/issues/385)

### A reached milestone celebrates once per browser

**What you see:** The mark that says a reached milestone has been celebrated is kept in the browser. Another browser, or
one whose site data was cleared, celebrates the same milestone once more the first time it sees it.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#known-gaps), "Known gaps"

**Issue:** [#386](https://github.com/johnfrog76/toolkit/issues/386)

### The dress guard reads names by their capital

**What you see:** When the model dresses the played standup, a capitalised word that is not in the facts is refused and
the derived prose is shown instead, so a persona with a proper noun of its own ("Dev-Hero") is never
dressed, and an invented name written in lower case is not caught. A group whose own name is a kind noun
("Bugs") with no item of that kind is never dressed either. A refused reply is kept on disk like any
other, so the same facts are not asked again until they change.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#known-gaps), "Known gaps"

**Issue:** [#387](https://github.com/johnfrog76/toolkit/issues/387)

### A Route typed in a terminal reaches the page a minute later

**What you see:** The agent drops its kept tracker reads when a verb runs through the browser, but a `Route` typed in a
terminal never reaches the agent. The Team Agile pages show the change when the kept read's minute runs
out, or at once on the Triage page's Refresh.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#known-gaps), "Known gaps"

**Issue:** [#388](https://github.com/johnfrog76/toolkit/issues/388)

### The played standup is a first cut

**What you see:** The played view draws one tile for each worker label, however many sessions that worker is running. The
week's seat is always ghosted, and the tracker's seat lights only to say the tracker could not be read.
The voice is the browser's own, whatever the machine has; there is no lock-screen play, pause or next;
and the nonsense register's door is not drawn on the stage.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#known-gaps), "Known gaps"

**Issue:** [#389](https://github.com/johnfrog76/toolkit/issues/389)

### A card linked to an unrouted issue is in no slot

**What you see:** A card whose id is an issue's number adds no row of its own to the standup. When that issue is open and
carries no worker label, the issue is in no slot and neither is the card's work: the card's lane is in
the response's `links[]`, and the text says nothing about it. Give the issue a worker label and it
shows.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#known-gaps), "Known gaps"

**Issue:** [#390](https://github.com/johnfrog76/toolkit/issues/390)

### The standup's prose reads no age, pull request or assignee

**What you see:** *Blocked* is only the blockers slot, an open, routed `verify-close` issue waiting on your walk: a
review that has sat for days is not blocked, and a `blocked` label is not read. *Yesterday* is only what
closed in the window: an issue that moved to review since the last standup is not in it.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#known-gaps), "Known gaps"

**Issue:** [#391](https://github.com/johnfrog76/toolkit/issues/391)

### The terminal's standup refuses a Space with several repositories

**What you see:** On a Space with more than one repository, `Standup` in a terminal says so on its `Tracker` line and
shows none of the tracker's items. The Team Agile page reads every repository, merging labels by name
and listing the issues together; it fails the whole read if one repository's read fails, and issue
numbers from two repositories can collide.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#known-gaps), "Known gaps"

**Issue:** [#347](https://github.com/johnfrog76/toolkit/issues/347)

### A failed tracker read is worded differently in the terminal and on the page

**What you see:** When the standup cannot read the tracker (the Space is not on GitHub, the tier is too low, `gh` does not
answer), the terminal and the page each write their own sentence on the `Tracker` line. Only the Azure
DevOps sentence is shared by both.

**Where you meet it:** [Team Agile](modules/solitaire-agile.md#known-gaps), "Known gaps"

**Issue:** [#392](https://github.com/johnfrog76/toolkit/issues/392)

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
([Team Agile](modules/solitaire-agile.md#true-by-design)). Only Team Agile's played view is dressed by the
model; the Work grain, Copy and `Standup -Grain work` carry the derived prose, and the counts line is
read on the page and in the brief, not spoken on the stage
([the agentic layer](modules/solitaire-agile.md#the-agentic-layer)).
