# Changelog

All notable changes to this project are recorded in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
intends to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) from its first
release.

Entries for the next release also wait as files of their own in [`changelog.d/`](changelog.d/README.md)
until the release folds them in here.

## [Unreleased]

## [1.9.0] - 2026-11-27

### Added

- Staff a seat from the Org tab: Assign on a vacant seat and Change on a staffed one open a dialog that is
  already filled in -- the model, named as it is today ("Opus 5.5"), the session's name, and a team lead's
  Space, with a different role title one click away -- and the owner's Change renames you. A seat that holds an
  older model keeps it unless you choose another. In the terminal, `Staff -Seat <position>.<seat>` does the same, and a save made
  after `org.json` changed underneath it is refused rather than written over.
- An `org.json` seat can carry its own title, the session it is, and whether it holds the merge: the Org tab names a seat by its own title and its model by name ("Opus 5.5"), with the session on hover, and `OrgChart` prints the session. A tree is now named by `title` (an older file's `name` still reads), machines are no longer shown, and `Config/org.schema.json` describes the whole shape.
- A new `Staff` verb starts your org chart from one of the three presets: `Staff -Preset S|M|L` saves the org into your hub's `org.json` with sensible default models in each seat (and your own name on the owner's), as a draft beside the org you already use, and `Staff -Activate <id>` puts a saved org in use. Your hand edits to the file are kept.
- Each saved org on the Org tab now says its state: **Active**, **Draft** (saved, never in use) or **Inactive** (in use before), beside its title in the View dropdown and in the line under the heading; `OrgChart` lists a file's orgs with their states too.
- The Org tab can save an org: on a preset, **Use this org** asks who you are and which models your two VPs use (each answer filled in already) and saves it to your hub, as a draft beside the org you use. A new **Active** dropdown, beside the one that picks what you look at, chooses which saved org is in use, and a line under the heading says when the org shown is a draft or a preview.
- The Org tab has a zoom control over the chart: **Zoom out**, **Zoom in** and **Fit to width**, with the percentage beside them. A large org opens fitted to the page's width, and a zoomed-in chart pans inside its own box instead of stretching the page.
- The Org tab can preview three starting orgs that ship with the toolkit -- Executive Suite (S), Branch Office (M) and Corporate Headquarters (L) -- each drawn as a chart with its short description and how the work flows in it. A preview writes nothing; your `org.json` stays your own.
- The Decks launcher has a third narrated deck, The Prompt Poet Works the Board: a card on an Azure DevOps
  board becomes one prompt and one pull request, told in a basement coffee house. Twelve slides, two voices.

### Changed

- On the Org tab, each office's role opens from a View button beside its title instead of from the whole
  card.

## [1.8.0] - 2026-11-25

### Added

- A sixth role ships in `agentic/org/`, the butler: run weekly as a routine you schedule, it gives every design note and spec with no id its own with `StampDesign` and reports what it stamped, which designs look finished with the evidence and the `MoveDesign` call that would archive them, and what it left and why. It archives nothing itself. The sample hub's `org.json` seats it under the VP of product.
- Four more roles ship in `agentic/org/` beside the intern: the PM, who plans the work and keeps the record; the team lead, who briefs builders and hands on one pull request at a time, made ready; the VP of engineering, who holds the engineering standards and the merge; and the VP of product, who owns scope, voice and the release notes. Each names its neighbours by relationship and carries a section for whoever covers the seat, and the sample hub's `org.json` now names a role for every office.
- The org's roles ship in `agentic/org/`, starting with the intern: a role that assists the seat planning the work by drafting milestones, breakdowns of a too-big story, close-outs with their evidence, a severity for each bug and the shipped designs to archive, and hands every draft to that seat to decide and write. A position in `org.json` can name a shipped role without copying it, and a role of your own in the hub's `agentic/org/` under the same name wins.
- The web UI shows what's new in the version you just updated to: a **What's new** dialog with that release's notes opens the first time you open a new version, and **What's new** in the account menu, after All settings, opens it again whenever you like.

### Changed

- The toolkit's own plan for a set of cards is now called a release everywhere you read it -- `Plan`,
  `Backlog`, the board's Release filter, the card menu's Plan release, the standup's suggestion and PM
  Corner, and the docs -- and "milestone" on its own now always means a GitHub milestone. Nothing in a hub
  needs to change: the card's `**Milestone:**` line, the `milestones/` folder and the `-Milestone` switches
  keep their names and read exactly as before.
- The intern now fetches the tracker's milestones and where each one stands for the team, still writing nothing, and no longer proposes designs to archive: that is the butler's round. Every role now opens by reading its situation -- the Space, the tracker, the open cards, what waits on whom -- before it does its job, and the roles page gives each role a short bio.
- Every page that shows one record now has the same header. Its File line is a short **Copy the file path** or **Copy the file link** button, with the full address in its tooltip and the same width whatever the address; the docs viewer, the 1:1 session page and the issue page carry it, while the design note and a PR's review comments show no line yet.
- A 1:1 session, a growth item, a card's review comments and a reference document are opened by their exact
  file name, so on a disk that ignores letter case, a request that spells the name in other case is now not found.

### Fixed

- On Linux, `Web -Stop`, `-Restart` and `-Status` recognise a `node` dev server on the dev port, so an
  orphaned dev server of this checkout is stopped instead of being called "not a dev server" and left running,
  and a process holding a port is named by its program rather than by its main thread.
- `Web -Dev -Fixture` serves a temporary copy of the fixture hub, removed by `Web -Stop`, so saving a
  setting there no longer changes a file in the checkout; and `Config`, with the settings drawer that reads
  it, now lists the Space the environment override names, as every other command does.
- A real run's counts block is no longer refused by the counts writer when the pytest line ends `(via python3 (PATH))`, so release counts can be written from a run that used the PATH Python.
- The agent's routes that open a hub file by its name take the file from the folder's own listing.

## [1.7.0] - 2026-11-22

### Added

- The System page's Environment card now lists each Teams recipient with where it comes from (Every Space or This Space) and whether its webhook variable is set, when the communication module is on.
- A second Teams recipient is declared with `Config -Set managerWorkflow.communication.recipients.<key>.type`, `.display` and `.webhookEnv` (or under `spaces.<slug>.` for one Space), and `Env` names the recipients declared. A Teams chat is a recipient type of its own, `chat`, posting through its webhook like a channel; an unknown type is refused with the allowed values named.
- `Daily` prints a week's timesheet in the terminal -- this week, `-LastWeek`, or any window with `-Since` and `-Until` -- and the Daily page steps back to any earlier week. A window with one end, or a day that is not `yyyy-MM-dd`, is refused in the same words in both.
- The Studio's Spaces card counts each GitHub product's designs in flight and its specs on the product's row, and says how many of its design files are not stamped with an id.
- Organize has a Reference page beside Reminders: the documents you keep in your hub's reference folder, listed, searchable by their words and readable in the browser.
- A Space can say how many are in its Team Agile standup: `Config -Set spaces.<slug>.features.teamSize=<3|6|9> -Hub`,
  or the settings drawer's "How many are in my standup?" -- the room, the chair counted, nine when unset.
  When the Space has more members than seats, the ones with work sit first, then the idle; the rest are
  out today and say nothing in the work grain, while the detail and the brief still list everyone.
  `Standup -AsJson` carries the room as `team.size` and each worker's `present`.
- Team Agile has a new `OrgChart` verb that prints your org as a tree -- the positions, who each reports to, and which model or person sits in each seat -- from an `org.json` file at the top of your hub; `OrgChart -AsJson` prints it as data, and `samples/hub/org.json` is one to copy.
- The agent serves the org chart at `GET /api/ritual/org` (where Team Agile is on), with each position's prompt title and a reference that opens it in the Studio's reading room; `?tree=<id>` asks for another tree of the file.
- Team Agile has an Org tab beside Standup, Triage and Releases that draws your org chart as offices, one card a seat with the model or person in it, or an empty desk and its mug where nobody sits; click an office to read its role prompt in the Studio.
- A card can name the model that works it: one `**Agent:** <model id>` line beside `**Assigned:**`,
  meaning who is working it, or did, read on every tracker and served as the card's `agent`.
  `Route <id> -Assign <size>` writes it at the hand-off with the size's current model id, and refuses
  a size with no `current` entry; the lead rewrites it whenever the work changes hands, and confirms it
  at sign-off. `Route <id> -Assign me` still writes `**Assigned:** me`, the person.
  `Config/models.json` maps each id to its provider, family and display name, so an id the map does
  not know is shown as written and never guessed at.
- On a Mac, `Test -Isolated` gives a test run its own home, temp folder, PowerShell caches and test history, so two full runs can start at once without crashing each other; add `-Keep` to keep the run's folder for reading afterwards.
- `Test` warns in its summary when an installed Python package is below the floor in the agent's requirements files, or is not the pinned version, and names the line that fixes it; `Env` shows the same as its `Python packages` line. The run itself is unchanged.
- On an Azure DevOps Space where `az` is installed but not signed in, the web app now shows a short "Sign in to Azure DevOps" strip with the command to copy (`az login --allow-no-subscriptions`) and a **Check again** button, and `Setup`, `Env` and `Connect` name the same command; the app never signs in for you.
- `Burn -Reading general=43,premium=54` records your plan's weekly usage as Claude's usage page shows it, one bucket or several, and `Burn` now opens with a weekly burndown: each bucket's latest reading, how far it is ahead of or behind an even pace to the reset, and when the reading was taken and renews (`Config -Set burn.cacheHours=<n>`, 4 hours by default). Readings are kept in the hub, one file per week per machine, and `Burn -AsJson` and the agent's `GET /api/usage/burn` carry the burndown too.

### Changed

- The CLI test runner now prints `<Suite> -- started <time>` before each suite, so a cancelled run's log shows which suite stalled.
- The Studio tab's Spaces, Hub Designs and Prompts cards now show every row at one height, with the title on one line, up to two lines of description, and the badges and file details on a fixed bottom line; the full text shows on hover and on keyboard focus, and the top cards are short enough that both fit, with the start of Prompts, on a laptop screen.
- Where a Space's checkout is configured, the Design tab reads that clone: a design you move from the browser changes its row at once, before anything is committed, and Search inside finds text on the clone's branch.
- On a GitHub Space the standup counts only the commits authored inside its window, says how many it could not date (`7 commits (2 undated)`), and marks an issue with no card `started` when it got its worker label or an assignee in the window.
- The standup's Next line now ends in `StartWork <n> -Launch` when it suggests sending an item to the crew on a machine where Claude Code is installed, so the line names the command that starts the session.
- Active Cards, My Work and GitHub Issues, the Log, Decks and the Studio's three lists are drawn one
  way: every entry is the same height with a plain title, one **Open** button and the rest in its
  `...` menu, long text is cut with an ellipsis and has no tooltip, each list is one fixed height
  beside its neighbours with a page sized to fit it, and the pager sits in the foot and reads
  `Page 2 of 5`, with the arrow keys paging while it has focus. Active Cards shows a card's
  checklist progress on its bottom line, a Decks entry opens from **Open the deck** instead of a click
  anywhere on it, the Log's type, period and search sit in its header, and a hub design's docs and the
  cards worked against it open from its menu.
- Hub Designs' outcome chips under **Archived** read like its state chips: each shows how many
  archived designs it holds, a chosen one is drawn the same way, and the two rows of chips have a
  small space between them.
- A list never cuts off its last entry: the number of entries on a page follows the room the list
  really has, so a message or a second row of chips over the list takes an entry's place while it
  shows. In Hub Designs, **Search inside** lists what it found as entries of the same list, a page
  at a time, with a **Designs** chip to go back.
- Team Agile's Milestones tab is now named Releases, at `/solitaire-agile/releases`, and says that each row is a GitHub milestone; the old `/solitaire-agile/milestones` address still lands on it.
- On the Studio tab, every Spaces, Hub Designs and Prompts row now shows one action, Open, with everything else in the ... menu, and its title is plain text rather than a link.
- Hub Designs filters by state with the same chip row as Prompts and Spaces, with counts, and its helper sentence moves into an info icon beside the title.
- `ReplyPR -Status` with a word that is not a thread status now stops with one sentence naming the six it takes, before anything is posted. The verb and the PR Comments page read the same list.
- A page's panels sit in rows you can select in the browser's developer tools, each with its own gap
  and the panels it holds: two side by side in a wide window, stacked in a narrow one. Nothing on a
  page moves.
- In-page tabs (Home's views, Team Agile's ceremonies and the Standup's tabs) and a panel's filter
  chips have even space above and below them.
- Test Health pages its suites like the Log, so the two panels on the System page are the same height,
  and the System page's card pager reads Page 1 of 2, centred under the panels.
- Cards in every list sit 8 px apart, and the line of tags, ids and dates under a card's description
  has the same room whether the description runs to one line or two.
- Every list panel is one height, tall enough for four Studio cards a page under a row of filter chips.
  Panels side by side line up whatever they hold.
- Filter chips take your theme's link and tab colour when selected, so they follow dark and light and each of the themes, rows that group by colour use colours that sit with each theme's palette, and the Design tab's outcome chips now show how many designs each one holds.
- On the System page's Environment card, a Teams recipient with no webhook now reads "Webhook not set" in a neutral tone, and "Sending off on this server" where the server was started for review or testing. Each row says what it does (for example "Your manager: Teams direct message") under the title "Teams messages", a person recipient asks for no webhook, and how to set one up is in the row's info icon. The manager session's send button gives the same two phrases as its reason.
- On the Growth page, Reviews and Goals are drawn like every other list: the two panels and Decks
  are one height, every entry is the same height with long text cut by an ellipsis, each has one
  **Open** button and the rest in its `...` menu, and the pager in the foot shows as many entries as
  fit. Goals' statuses and Reviews' kinds are chips over the list, Reviews narrows to one Space from
  a select in its header, and how reviews work is behind the info icon beside the title.
- Reminders and Meetings are drawn the same way: one height, entries of one height, chips with
  counts over the list, and the pager in the foot. A reminder that names a card you are working on
  opens it from **Open the card** in its `...` menu instead of a link in the entry. A meeting opens
  from **Open the meeting**; **Edit or send**, and **Archive** on a complete session, are in its
  `...` menu, where three unnamed icon buttons were.
- The System page groups its cards under in-page tabs, Overview and Agents, the same tab row Home uses, in place of the pager.
- In Team Agile's standup, a worker with nothing on the tracker now gives a real status about the day
  around the work -- setting up, learning, meetings -- and two idle workers on the same day say
  different things.
- In Team Agile's standup, the work grain goes round the room: each worker gives status in one frame
  ("Good morning. Yesterday I closed ... Today I'm on ... No blockers. That's it for me."), and every
  turn has a yesterday and a today: a slot with nothing beside one with something says a fixed, honest
  line -- "Today I'll pick up the next item from the board.", or "Yesterday I worked on #414." for work
  begun or committed in the window, else "Yesterday I picked up where I left off." -- and only a worker
  with nothing at all on the tracker says a made-up yesterday and today about the day around the work
  ("Yesterday I ... Today I'll ...") in the same frame; and the chair gives its own status last in its
  own words -- "Yesterday I walked #407." when a walk closed in the window, then "Today I'll walk #416
  and #417." or "Today I'll keep the board moving." The detail grain shows an idle worker's two items
  on two `Status` rows instead of one `Mug` row.
- Team Agile's played standup is the round of the room: nine windows, the chair and each member in the
  room today in a face of their own, plated with their label, and an empty desk with a steaming mug, a
  different one each, in every other window. The chair opens the board, calls each member by name -- the
  called window lights up in colour with a dashed ring -- the member answers -- a member with nothing on the tracker keeps their face and says their made-up
  yesterday and today -- and the chair gives its own status before it closes. Team size, beside Play,
  opens the settings at "How many are in my standup?". The voice says each name once. The speech bubble keeps its
  size and shows a turn's first lines, and never lies over a face or a name plate.
- A Space's team size is now how many people are in its standup: every seat it counts is filled, by you, your labelled workers, then invented cast members who report made-up status, and the empty desks are only the windows past the size. On a GitHub Space you are always in the standup, with a status row even on a day with no card in play, and you take the first turn of `Standup -Grain work`.
- The played standup on the Team Agile page seats the whole room the Space's team size counts: you first, your labelled workers, then invented cast members, each in a window of its own, so a room of nine has no empty desk, a room of six has three and a room of three has six.
- Every text file in the Toolkit checks out with LF line endings on Windows too, and a new hub made by `Start` gets a `.gitattributes` that does the same for your cards.
- The standup's room is drawn in the refined cast, the one the Org page and the landing page use: the nine
  members, the PM on the treadmill, the eight drinks on the empty desks and each window's props. Every window
  is now in full colour. The speaker is told apart by its frame, the called window by its dashed ring and an
  empty desk by the drink on it. What is said, where everyone sits and how the room moves are unchanged.
- Existing standups change where a card is in play: a card is reported by the agent its `**Agent:**`
  line names, else an older card's `**Assigned:**` worker, else the model its commits credit, else
  you. An issue with no card stays with its label's worker, and every model a card names gets a seat.
- The third-party notices list the agent's Python packages at the versions and licenses the requirements now allow,
  including `anthropic`, which moved from MIT to Apache-2.0 at 2.0; the list is regenerated with one command and
  checked against the requirements' minimum versions.
- In the settings drawer, every setting with a few allowed values is a dropdown, the standup's size
  included, and every one you may leave unset opens on **Default**, which takes it back to unset --
  **Default (9)** for how many are in your standup, plain **Default** for how you work in a Space.
- The standup's size reads as its question in the settings drawer's Configuration section -- "How
  many are in my standup in Acme?" for a Space called Acme -- and the question's radios gain
  **Default (9)**, first and chosen while the size is unset.
- The landing page's three people are drawn in ToolKit's new refined style.

### Fixed

- On a large GitHub repository, Team Agile's standup, triage list and suggestion in the browser now read the same issues and labels as `Standup` and `Triage` in the terminal.
- Small badges that were white on white in the light theme -- a prompt's category on the Studio tab, Archived and Read-only in the new Space dialog, Closed on a design's page -- are now readable, and a check stops the combination coming back.
- A Space you have retired no longer appears in the Space switcher unless you are in it; it stays under Archive on the Spaces card and `SwitchSpace <slug>` still reaches it.
- On a GitHub Space, PR Comments now offers only the statuses GitHub keeps (fixed, closed and active), and a suggested reply no longer picks one that is refused.
- On GitHub, `GetPRComments` reads `ReplyPR`'s answer to a conversation comment or a review summary back into the thread it answers, instead of as a new thread.
- A test run made in a git worktree now reaches the System page's Test Health card: each machine keeps its test
  history in one folder outside every checkout (on macOS `~/Library/Application Support/ToolKit/TestHistory`), each
  record names the checkout and commit it ran from, and the first look after upgrading still shows your last run.
- A Space on Azure DevOps now finds its clone on your machine, so the moves and checks that need one (`MoveDesign -Space`, the `-Doc` check) work there as they do on GitHub.
- Importing the ToolKit module no longer contacts GitHub or Azure DevOps: the startup line says only what is known without the network, and the tier is worked out the first time a command needs it.
- `Burn` and the System page's burn tile now price Claude Fable 5.2 and Claude Haiku 4.5, and when a model has no price yet the cost itself reads "$X derived, not counting claude-new-1" instead of leaving the gap to a footnote.
- Private and Visibility unknown badges in the New Space dialog, and the source badge of a setting that is not set on the Settings card, are now readable in the light theme instead of white on white.
- When a Space's tracker is not GitHub, Team Agile's Releases tab now says "the Releases tab" in its explanation, not the old "Milestones tab".
- A Space on Azure DevOps finds its clone when the clone's ssh remote is written as a URL
  (`ssh://git@ssh.dev.azure.com/v3/<org>/<project>/<repo>`), not only in the form the clone dialog gives.
- When the standup or triage cannot read the tracker, the `Tracker` line in the terminal and on the Team Agile page now says the same sentence for the same failure, and a missing repository says how to name one.
- Under Windows PowerShell 5.1, a Space's checkout or a hub whose folder path has a space in it and ends in a
  backslash (`C:\My Repos\product\`) is found: it no longer reads as not a clone, or as not a git repository.
- The PM Corner now offers `StartWork <n> -Launch` wherever the standup's Next line does, so the two lines of a brief name the same command for the same item.
- Typed in Windows PowerShell 5.1, `TestToolkit` now runs the test suites in 5.1; it used to run them in PowerShell 7 whichever shell it was typed in.
- The System page's headings now follow one another in order, so a screen reader moving by headings no longer meets a skipped level.
- On the standup's stage, the ops window's terminal sits behind him like a call's background, so it never covers his face. Its heartbeat is now a soft shift of the text between green and white, where the whole panel used to fade over him every beat; with reduced motion on there is no beat at all.
- Changing the team size (or any other setting) now updates the Team Agile standup straight away, without a hard refresh.
- The agent's tests no longer call a real `az` or `gh` on a machine that is signed in: both are kept out of reach
  for the run, and a test that calls either without standing in for it fails, naming the command.
- The standup's windows no longer replay their entrance each time the speaker changes: the room enters once,
  and after that only the windows of whoever stops and starts speaking change.
- A `Test -Isolated` run that was stopped no longer leaves its run folder in `/tmp`: Ctrl+C clears it, and the next `-Isolated` run removes the folders a killed run left more than a day ago, naming each one. A folder kept with `-Keep`, and the folder of a run still going, are never removed. A folder kept by an earlier version has no marker; touch `.p20-kept` inside it to keep it.
- `tkStandup -Grain brief` on a GitHub Space with no worker labels now ends its list of members with "No worker labels in this Space." after the engineer's line, where it had said routed issues read as open when none are routed.
- The standup seats both the engineer and a worker when a Space's slug is the same word as one of its
  tracker's worker labels, so neither goes without a turn in `tkStandup`
  or a window of their own on the standup's stage.
- `tkWeb -Stop` and `-Restart` now stop only a dev server that belongs to the checkout they run from, and name any other `node` on the dev port as another checkout's instead of stopping it; the Web test suite no longer stops a real dev server on 5174.
- The System page's Log card keeps its title, Dismiss Errors, refresh and the count together in the header, with the type, period and search filters in a row above the chart and six entries to a page.
- The standup's brief reports each member's own cards started and commits when a Space's slug is also one of its worker labels, instead of crediting both members with the same counts.
- The standup's brief says a Space has no worker labels from the tracker's own count, even when a card seats a member.
- The hub's growth document says how a work review picks its files: a stamped file by its `**Created:**`
  and `**Closed:**` dates, and git only for a file with no `**Created:**`.
- The web UI's README says how its tests load `react-markdown`: through the `transformIgnorePatterns`
  allow-list in `web/jest.config.mjs`, not by being unable to.
- The documentation no longer promises that `tkWeb -Stop` recognises a `node` dev server on Linux, where it
  does not yet; it lists every key `tkConfig -Set` accepts, the lane names and the deck and first-run keys
  among them; and it counts the suites whose verbs run on Windows PowerShell 5.1 the same way twice.
- Clearing a Space setting in the settings drawer now removes it when the hub holds the value; before, the save reported success and changed nothing.
- The settings drawer opens with its settings already loaded, and a link to a setting lands on it the first time, however slowly the list arrives.

## [1.6.0] - 2026-11-09

### Added

- `Burn` now shows your current Claude Code burn: today, and this week from when the allocation resets -- Friday 05:00 by default, or another day and time with `Config -Set burn.weekStarts="Monday 09:00"` -- this machine's session files read live, plus the day records your other machines logged with `Burn -Log` -- as tokens by model and a cost marked as derived, never a share of your plan. `Burn -AsJson` gives the same as JSON, `Burn -At <time>` the burn as it stood at a past moment, and the System page has a **Claude Code burn** tile with the same figures, kept for an hour, with a Refresh; it appears only on a machine that has Claude Code session files. Haiku is priced at its lower rate card, and every cost says so.
- `Burn -Log` writes the day's Claude Code usage on this machine into your hub as one small file, `usage/<date>-<machine>.json`: tokens by model and by session, read from Claude Code's own session files without changing them, and a cost worked out from list prices and marked as derived -- never a share of your plan. Run it again the same day and it replaces that day's file; `-Date` logs a past day. The record holds no paths and no user names, and `tkEnv` says whether this machine has Claude Code session files to read.
- A milestone now has an order you keep: `Plan <id> -Rank top|up|down|<n>` moves a card within its milestone, and `Plan <id> -Milestone <title>` adds the card at the bottom of that milestone's order, which lives in one small file per milestone, `milestones/<slug>.md` beside `current/`. Moving a card edits one line of that file and never the card. On an Azure DevOps Space the board keeps the order, so `-Rank` refuses there and points at `MyWork`.
- A card can be in a milestone and a sprint at once: `Plan <id> -Milestone <title>` now writes its own `**Milestone:**` line and the new `Plan <id> -Sprint <title>` writes `**Sprint:**`, each leaving the other as it was. A card written before keeps the milestone its `**Sprint:**` line named -- except a card from Azure DevOps, whose `**Sprint:**` line is the board's iteration path and is never read as a milestone. `Plan -Remove` still takes the card out of both; `-Remove -Only Milestone` or `-Only Sprint` takes it out of one.
- The new `Tag <id> <tag>[,<tag>] [-Remove]` adds tags to a card's `Tags:` line, or takes them off; a tag the card already carries is not added twice, and a call that changes nothing writes nothing.
- A card's row menu, on the list and the board, offers **Plan milestone**, **Plan sprint** and **Tag**, and the board filters by milestone and by tag beside its sprint filter.
- A design that has reached a spec can now be dropped: `MoveDesign <id> -To Archive -Dropped -Reason <text>` archives the spec and its note together, stamps both as dropped, and the Design tab lists it under Archived with its reason (and offers **Archive as dropped** on a design with a live spec). Without `-Dropped`, a live spec still has to be completed.
- `Land <id>` ends a card once its pull request is merged: it records the merge commit on the card (`- <hash> #<n> squash-merged to main <date>`), closes the issue or work item behind it with a comment naming the commit, and archives the card. An open or unmerged pull request is refused with nothing written, a step already done is skipped so running it again is safe, and `-WhatIf` shows the three writes without making them. On the board and the list, every Code Review card offers **Land**; if its pull request has not merged yet, the confirm says so and nothing changes.
- `NewPrompt -Title ... -From <meeting>` makes a card from an agenda line and records the meeting it came from in a `**From:**` line -- the record's name, such as `2026-10-28` for the 1:1 or `client-weekly-2026-10-28` for a series; a meeting record that does not exist writes no card.
- A deck in the Decks card now opens a page of its own, showing its summary, state, tags, slide count, running time and where its file lives, with **Play** to present it. The page's **Archive** puts the deck away on this machine only (the `deck.archived` setting): it leaves the Decks list for an **archived** filter, and the deck itself is not changed.
- A goal can be marked complete from the Growth page: **Complete** on its row or on its own page writes the goal's Status line as Achieved and changes nothing else in the file, and the goal's page now offers **Archive** too. In the terminal it is `NewGrowth -Complete <file>`, and `-WhatIf` names the file and writes nothing.
- A product's designs can be moved from the Design tab: name where the Space's repository is cloned on this machine (`Config -Set spaceCheckouts.<slug>.path=<folder>`, or This Space's checkout in Settings) and each design's menu offers Graduate to a spec, Archive and Complete, staging the move in that clone for you to commit. Without one, the tab names the setting. `MoveDesign -Space <slug>` does the same from any folder.
- When your hub's store sync is git, the System page's Environment card has **Sync the hub**, which pulls and pushes and shows the sync command's own answer, and says how far the hub is ahead of or behind its remote, with the time it last checked; the Spaces, Hub Designs, Reminders and Reviews cards say so in a line at their foot while the hub is out of step.
- `ReplyPR` and `AddPRReview` now work on a GitHub Space. `ReplyPR` replies inside an inline review thread (or, for a conversation comment, posts a new comment that links to it), and `-Status fixed` or `closed` resolves the thread while `active` reopens it; `byDesign`, `pending` and `wontFix` have no GitHub equivalent and are refused before anything is posted. `AddPRReview` reads the diff from GitHub, so it needs no checkout, and posts its findings as one review with inline comments; a finding on a line the diff does not show goes in the review's text. Both print the public-repository line before they write.
- `GetPRComments` now works on a GitHub Space: it reads a pull request's inline review comments, its conversation and its reviews' summaries through `gh`, and appends them to the card exactly as it does for Azure DevOps -- safe to re-run, a reviewer's follow-ups included. The card's own `PR URL:` line tells it which repository to read, so it works from the browser with no checkout.
- A work review's row on the Reviews card now offers **Archive** and **Delete**, and the new `WorkReview` command does the same from the terminal: Archive moves the review under `reviews/archive/` with a closed date in its `review.md`, Delete removes a draft for good after asking, and the list's new **Archived** filter shows the reviews you put away. A review's row also no longer shows its raw `orgs: [...]` line as its summary.
- `NewPrompt -Title ... -Description <text>` fills a new card's Context or Summary with that text instead of leaving it `(TBD)`; the New ToolKit Card dialog has a matching description field.
- `Backlog` prints the cards waiting in a Space's backlog as one table, ranked by each milestone's
  order, with the milestone's cards already in play shown in their place, and `-Milestone`, `-Tag`
  and `-Type` to narrow it. The agent serves the same rows at `GET /api/backlog`. On an Azure DevOps
  Space it says the backlog is in Azure DevOps and points at `MyWork`.

### Changed

- The milestone award shows a gold trophy instead of the ToolKit logo, and its confetti now falls over the whole app rather than inside the dialog.
- On an Azure DevOps Space the board now draws four lanes, with no Backlog lane, and `NewPrompt` writes a new card straight to `current/` so it is in play when it is made; the board's footer names the first lane the Space has. A local or GitHub Space keeps its five lanes and its backlog. A card already in the backlog on an Azure DevOps Space is drawn in Active, so nothing goes missing.
- **Create PR** from the browser now works from the card's own code checkout when one is on this machine (a clone of the board's GitHub repository at `<wsRoot>/<repo>` or a nav shortcut's path): the repository comes from that checkout, a card with no `## Branch` uses the checkout's branch when it is the card's, and a branch that was never pushed is refused with the exact `git push` to run in that checkout. With no checkout found, it reads the card as before.
- Completing a hub-kept design (`MoveDesign -Hub -Space`) also finds the Space's repository at `<wsRoot>/<repo>`.
- Every list's row menu now uses one vocabulary: the same move has the same word, icon and tooltip on every page, and the link out is always last, reading "Open on GitHub" or "Open on Azure DevOps" behind one icon. A goal's Retire, a reminder's Done and a card's Move to Done now read Archive, a design's two archives read Archive as shipped and Archive as dropped, a card's exposed action opens the card, and Remove cover reads Delete the cover.
- The deck player has two bars now. Watching a deck, the bar keeps Exit on the left, the arrows around the slide counter in the middle -- or around a play ring in Audiobook, where the deck reads itself aloud and turns its own slides -- and settings, fullscreen and the sound on the right, at every width. The gear opens a short Voice sheet with Narration, the mode (Paging or Audiobook) and the voice, on a phone too, and a deck you switch to Audiobook opens that way next time in the same browser. Presenting with `?present=1` shows Exit, the arrows, the counter, the speaker notes and fullscreen, and the deck window stays silent; a phone always gets the viewer's bar.
- `Test` and the CI check fail the web half when Jest force-exits a worker because a test left a timer or a handle open, and the failure says to run `npx jest --runInBand --detectOpenHandles` to find it.
- A changelog entry for the next release is now a file of its own under `changelog.d/`, named `<id>.<kind>.md`, so pull requests built side by side no longer conflict on `CHANGELOG.md`; the release folds the folder into `## [Unreleased]` with `Scripts/Fold-Changelog.ps1`. Entries already under `## [Unreleased]` stay where they are.
- On Windows, the agent now runs `gh` directly rather than through the command shell.
- The local agent now accepts requests only from its own pages and the origins you configure, and picture uploads are limited as they arrive.
- A shortcut's name must now be a plain name: a letter, then letters, digits, `-` or `_` (a command prefix has its own, narrower rule, below). `Config -Set` refuses anything else, and a name already in your file is skipped with a warning naming it: rename it in `config.local.json` to keep it.
- A `commandPrefix` is a letter, then letters or digits, and `Config` now refuses a dash or an underscore in one. A shell with such a prefix used to register no commands at all, so nothing that worked is lost: it now starts with the shipped `tk` prefix and a warning naming the setting.
- `Land` and `PublishPR` read the pull request from your Space's own tracker: a card's `PR URL:` line that names another organisation is refused, with the reason.

### Fixed

- On the Docs page, a README's dark-mode logo written as a `<picture>` with a `<source srcset>` now shows instead of a broken image, because the `<source>`'s images are read from the repository the way an `<img>` already was.
- `Sync` no longer stops with a conflict when one machine has archived a card and another has created a new one in `current/`: the pull no longer treats the archive as `current/` being renamed, so both cards land where they belong, an edit made meanwhile to the archived card follows it into `archive/`, and the sync goes through.
- `npm ci` in `web/` no longer asks about install scripts: the decision for each dependency that has one is recorded in `web/package.json`, so approving one locally no longer leaves a change in your working tree. If you approved `@parcel/watcher` or `unrs-resolver` yourself, discard that edit to `web/package.json` before you pull.
- A full `npm test` in `web/` on a busy machine no longer fails a test because a dialog took more than a second to appear; the web tests now wait up to 5 seconds for an element.
- The web half's Markdown lint now runs on `re2js` 2.8.7, which fixes a regular-expression denial of service in 2.8.6.
- The web UI's tests no longer fail now and then with `Test suite failed to run` while every test passes: `web/package.json` now asks for Node 24.22.0 or later, and `npm ci` on an older Node warns. Run `nvm install 24 && nvm alias default 24` to move up.
- The Reference field in the New Reminder dialog is now as wide as the other fields, instead of sharing a half-width row with Source.
- The Edit Reminder dialog's Source and Reference fields are full width too, like the New Reminder dialog's, and the fields in both reminder dialogs are the same size as the rest of the app's.
- `Move`, `Plan`, `Billable`, `Cover` and `Archive` given the full file path of a card in your hub now work on that card in whichever Space it belongs to, instead of refusing with "No card matching" when a different Space is active.
- The New ToolKit Card dialog no longer claims a custom card "is in play as soon as it is made" -- it now says the card starts in the Backlog, which is where `NewPrompt` actually puts it unless `-Now` is given.
- A design note or spec written with a `## Title` section, its title on the next line, is now listed under that title on the Design tab instead of its file name, and a note whose only level-one heading is a sentence deep in the body is listed by its file name instead of that sentence.
- Completing a design that a Space keeps in the hub (`MoveDesign -Hub -Space <slug> -To Complete -Doc <path>`, or the Move dialog) now looks for the document in the Space's own repository instead of the hub, so it no longer refuses every such spec; with no clone of that repository on the machine, the path is accepted as written and a note says so.
- The test suite's check for a raw, unredirected `git`/`gh`/`az` call now catches one written inside a double-quoted string's `$(...)`, a shape it previously missed entirely; the handful of real call sites it found this way now go through the same safe helper as the rest of the CLI.
- `Sync` (and the System page's Sync the hub) now states a failed pull or push once, instead of printing its own warning and then a generic exit-code block on top.
- A card whose `Tags:` line separates its tags with semicolons (`Tags: enhancement; sev3`), as a card made from an Azure DevOps work item or a GitHub issue is written, now reads them as separate tags, so the board's Tag filter finds it by either tag, the standup's suggestion sees its severity, and `Tag <id> sev3 -Remove` takes one off. `Tag` still writes commas.
- `NewPrompt -OutputFolder backlog` (or `current`, or `archive`) now writes the card into the active Space's folder of that name, the one `NewPrompt` uses by default, instead of a folder of that name at the root of your prompt store, where no Space looks and the board never showed it. A path such as `<space>/backlog` and an absolute path work as before, and with no Space active a bare name still means the store's own folder.
- A deck's text beside its picture no longer runs past the right edge of the window; at 1440 wide the played standup's lines were cut off mid-sentence.
- In the Docker image, refreshing the Lounge, or opening a link to it, draws the room again. It used to send the browser to a port nothing answered on.
- With the growth module off, the Space summary no longer shows a Reviews tile that could only read 0.
- `Land` on a card still in `backlog/` now commits the card's whole move, so the hub is left clean instead of holding an uncommitted deletion from `backlog/`.
- `Env` leaves the exit code at 0 when run outside a git repository, so a script that checks it no longer reads a failure that did not happen.
- Test Health groups the digits in large counts (`12,661/12,661`) in its tiles, its suite rows and its chart, and the chart's axis no longer cuts off five-digit labels.
- A verb the agent runs that passes its timeout now ends everything it started, and a change to how you work in a Space reaches the web UI's commands with no restart.
- On Windows PowerShell 5.1, `NewPR` and `MeetingAgenda` no longer garble the accented letters and dashes in a card or a session they update, a hub in a folder whose name has an accent is found, and `Route -Assign` takes a size. In a Windows terminal, a review comment `GetPRComments` fetches keeps its punctuation.
- On Windows PowerShell 5.1, a work item, a pull request, a comment or a reply with an accent or a dash in it reaches Azure DevOps as you wrote it, and an AI code review of a diff holding one no longer fails: every request body is now sent as UTF-8.
- When a Space's Azure DevOps address carries a user name and password, the refusal that stops the token being sent no longer prints them.
- `Land` takes a card's ID or filename in the active Space and refuses a path, so it can no longer close this Space's issue for another Space's card. On a GitHub Space it refuses a `PR URL:` line from another repository, and reads the issue number from a card's link only when the link is one of the Space's repositories. `Plan` keeps a milestone's order by the card's own Space's tracker. `PublishPR` no longer reads a token on a GitHub Space, and an Azure DevOps token is sent only to the Space's `https://` address.
- `Dashboard` shows its local view below Tier 1 instead of a full view of empty answers, and counts recent errors from the log the toolkit actually writes. `SwitchSpace` matches a Space's name exactly and refuses a name two Spaces share, where a shared name or a `*` could leave the active Space unreadable.
- One issue with a very long number in its text can no longer stop the standup: the number is read as no thread, and the standup goes on.
- `NewWorkReview` no longer writes over a review someone has edited or written up when a date range is run twice, from the terminal or the web; an untouched scaffold is still written again with fresh history. `NewPrompt` and `GetPRComments` no longer risk replacing a card when its name reads like a date or a path holds `[`.
- A hub, a package or a home folder whose name holds `[` or `]` now works: before, the Spaces in its `hub.json` went unknown, `Status` found no cards and `Archive` could not move one.
- A second `LogPeerReview` of the same pull request on the same day adds its notes to the record instead of replacing the first one's.
- `GetPRComments` keeps one side record per pull request and repository, so the same PR number in two repositories no longer collides, and a second fetch the same day adds to the record instead of replacing it.
- `GetPRComments` now says plainly that it wrote nothing when the card it would add to cannot be read, instead of a generic error.
- `StartWork -Launch` no longer leaves the card's text in the repository it launches from: the hand-off block and the session's logs go in the repository's own git folder, the block is removed once the session has read it, and the session's worktree stays out of `git status`.
- `Sync` no longer commits and pushes a hub that is in the middle of a rebase, merge or cherry-pick, where it could publish conflict markers inside cards, and it no longer reports success when its auto-commit was refused: both are now stated refusals that leave the hub as it was.
- `ThreadHash` fills a review reply's `[commit]` with the newest commit it adds, so a second review round names the fix instead of the branch's first commit, and it leaves the placeholder, and says so, when there is no new commit to name.
- A tracker verb no longer reports success when `gh` or `az` is missing or cannot be started: `EditItem`, `CloseItem`, `NewPR`'s issue comment and `MyPRs` now say so instead of printing a result for a call that never ran. `MyWork` and `Dashboard` on Azure DevOps, and `Dashboard` and `MyPRs` on GitHub, read their answers the same way.

## [1.5.0] - 2026-10-26

### Added

- Team Agile has a **Milestones** tab: every milestone of your tracker with a progress bar and its due date, and when one is reached a dialog congratulates you the next time you open the tab -- the confetti now lives there, once per milestone, and the standup's corner line links to it instead of celebrating.

### Changed

- The Team Agile standup page now opens on an **Agenda**: what moved since the last standup, and what is waiting on you as cards you can act on -- **Work it now** opens the hand-off, **Review it** opens what waits on a review -- with a cards or list view; the text moves to the Detail, Work and Brief tabs, and Copy and Play carry the same text as before.
- ToolKit's own accent is now rose and wine, on the landing page and as the wordmark's default colour: the logo's face, the call to action and the way-of-working dots there all take it.

### Fixed

- Every theme in the web UI wears its own accent again -- Atlantis its cyan, Basement its amber, Office its teal -- instead of the product's rose, and looks exactly as it did in 1.4.0.
- Team Agile's award dialog opens once, naming every milestone reached since the last one, with one burst of confetti; a revisit, a reload or a late refetch never opens it again.
- On the Team Agile Agenda, the id button on each card is readable in every theme; it was too faint in Seaglass and Aurora.

## [1.4.0] - 2026-10-24

### Added

- A fresh `tkStart` now teaches the board by using it: five tutorial cards on the Demo board -- pull one out of Backlog, tick a card's boxes, write down a finding, ask for a review, drop a card on Done -- each finished by doing what it says, until the To do lane is empty and the last card points you at the **+** for your first real card. They replace the single Welcome card; a hub you already have is not changed.
- `tkHowWeWork <slug>` writes a page for a Space you work with agents -- the seats, the loop, and the hand-off, relay and stand-in rules, as roles rather than models or machines -- into that Space's `agentic/how-we-work.md` in your hub, once and never over your edits. `tkStartWork` hands it to every session as "How we work", the Studio's Prompts card lists it, and the verb prints the one line to paste into your repository's `AGENTS.md`. Choosing **With agents** in Settings writes it for you when the Space has none yet.

### Fixed

- A test run is no longer thrown off by a shell's active-Space or prompts-root override: `tkTest`, `tkTestToolkit` and the agent's pytest run take `P20_ACTIVE_SPACE` and `PROMPTS_ROOT` out of the run and put them back after.
- `tkTest` finds the test venv's pytest by itself (a `.venv` in the package, then `~/.venv-toolkit`, then the PATH's Python), names the Python it used, and says `NOT AVAILABLE` rather than `not run` when none has pytest.

## [1.3.0] - 2026-10-22

### Changed

- Opening the Design tab on a repository with a large design archive takes seconds, not minutes: the notes are listed in one request instead of one per file, and what was read is kept between restarts so an unchanged note is never fetched again. The design search box also finds a design by its file name.
- The Docs tab opens in a second: a repository's README and `docs/` folders are listed in one request, however deeply they nest, instead of one per folder.
- The Studio's Spaces card opens in about a second with many GitHub Spaces instead of starting several `gh` calls per Space on every visit: every Space's issues, last deploy and visibility are read in one request, and kept for ten minutes so opening the card again, or after restarting the agent, asks GitHub nothing until you press Refresh.
- The Stats tab's issue report reads from the same kept copy as the Studio's Spaces card instead of listing every repository's issues again: opening it a second time within ten minutes asks GitHub nothing, and closing, editing or filing an issue from ToolKit refreshes it.
- The Team Agile standup and Triage pages open at once the second time: the tracker is read once a minute for both, and the standup's sentences are re-worded by the model only when what they say changes, even across an agent restart. Refresh on the Triage page still reads the tracker again.
- Many GitHub Spaces under one owner no longer each start their own reachability check when a page loads cold: the Studio and the per-Space pages ask GitHub once per owner, not once per Space.

## [1.2.0] - 2026-10-22

### Added

- A WIP limit: `Config -Set limits.inPlay=5` makes `Status` open with how many cards are in play (`in play: 4`, or `in play: 7 of 5` past the number) and turns the board's Active column amber past it. It is a line, never a gate -- nothing refuses and nothing is hidden -- and unset means no line.
- On a GitHub Space the standup now says the cards being worked as well as the issues, and adds a `Check` line where a card and its issue disagree.
- A card linked to an issue with no worker label now shows on the standup under you, in the slot its own lane maps to, instead of being invisible because the issue itself got no slot.
- The standup says what moved: an item says when it started in the window and how many commits its card carries, and the brief opens on a counts line -- closed, started, in progress and commits, per worker and in total.
- `Standup -Since <yyyy-MM-dd>` (and `?since=` on the standup route) reports over a window of days instead of only yesterday, and counts everything that closed in it.
- A new `StartWork <id>` command (Team Agile) assembles everything a fresh agent needs to pick up a card or an issue -- how you work in the Space, the card whole, and the prompt for its kind -- in one paste-ready block, and each row of the standup's list on the Team Agile page opens it in a copy box.
- The app's Home now links the published landing page from its foot.
- A backlog of cards: plan a card for later. A Space now has a `backlog/` folder beside `current/` and `archive/`, its cards read as **Backlog**, `Status` lists them after the cards in play as a count and their names, and the board draws Backlog as its first column. `Move <id> -To Active` pulls a planned card into play, `Move <id> -To Backlog` parks a card with nothing threaded, and `Archive` retires one from either folder.
- Triage now shows who has each item -- you, another assignee, a crew size, or nobody -- and `Route -Assign me` takes an issue yourself (or `Route -Assign <size>` routes it to the crew); a card with no issue behind it records who takes it as an `**Assigned:**` line, and the Triage page offers **me** beside the sizes.
- When nothing is waiting on you, the standup's chair's reading (`Standup -Brief`, and the Team Agile page) now ends on one suggested next move -- the item, the rule that chose it, and the command that acts on it -- instead of "nothing is waiting on you"; the page lets you dismiss it for the session, and `Config -Set spaces.<slug>.features.suggestions=false -Hub` turns it off for a Space.
- The Team Agile page now opens on one line for the milestone in reach -- how many items are left and which one to start, with a chevron that opens the hand-off box -- and throws confetti once when a milestone is reached; `Standup -Brief` ends on the same line.
- A new `Plan <id> -Milestone "<title>"` command writes the write side of a card's `**Sprint:**` line -- the board's sprint filter already read it, but only a hand edit could set one; `Plan <id> -Remove` takes a card out of its sprint. Works on a card in `current/` or `backlog/`, never touches the tracker, and never pulls a planned card into play.
- `StartWork <id> -Launch` (Team Agile) starts the work for you: from a clone of the Space's repository, with Claude Code installed, it opens a fresh worktree and starts a session on the hand-off block there with the model the item's size names (sonnet or opus -- never fable, the owner's own seat), prints its PID and log, and returns at once; `-WhatIf` shows what it would run, and `tkEnv` names it as **StartWork launch**.

### Changed

- A new card is planned, not in play: `NewPrompt` (and the web's New card) writes it to the Space's `backlog/`, and its first `ThreadHash`, its `NewPR` or `Move -To Active` pulls it into `current/` -- so the make-branch-commit-thread flow is typed exactly as before. `NewPrompt -Now` writes straight to `current/`, as it used to.
- `StartWork` on a planned card says it is in the backlog and names `Move <id> -To Active`, rather than starting it for you.
- A card marked not billable (`Billable -No`) is now left off the standup as well as off Daily.

### Fixed

- The played standup now names a card by its id (and reads it as "card 2HNU") instead of `#null`, and its overflow list no longer links cards.
- On macOS and Linux, the agent's and the web server's logs now keep filling after `tkAgent` or `tkWeb -Dev` returns; they used to stop at the startup lines.
- The docs now say plainly that the Docker image only reaches the agent on Docker Desktop (macOS, Windows); on native Linux Docker Engine the container cannot reach a loopback-bound agent, and `tkWeb -Dev` is the way to run there instead.

## [1.1.0] - 2026-10-18

### Added

- CodeQL scans the web and the agent on every push to main, every pull request and weekly.

### Changed

- Creating a training, presentation or goal from the browser now runs the same command the terminal does, so both write the same file; a refusal shows the command's own message in the dialog.

### Fixed

- `ThreadHash` now takes a card id like every other card verb, as well as a filename, a partial name or a path.
- An empty `config.local.json` no longer stops `Log -Ack` from acknowledging errors or `SwitchSpace` from switching Space.
- `UpdateResume`, `PublishWorkReview` and `LogPeerReview` now state a refusal once, with git's own sentence and a hint where a commit fails, and exit 2; a commit git refused used to print a second, generic error block on top of it.
- Running the tests from the web UI's Test Health card no longer fails every refusal case.
- Resetting the menu's usage scores, switching Space and acknowledging logged errors no longer write a byte-order mark into `config.local.json` under Windows PowerShell; all three now save through the same writer as `Config`, so the file comes out the same on every host.
- A refusal from `Log`, `ThreadHash`, `InstallAutoload` or `SwitchSpace` is now written to the usage log and reported to the browser as an error instead of success, and `SwitchSpace` of a Space that does not exist refuses with the Spaces it knows (exit 2) instead of reporting success.
- Play with narration in a deck's notes window now plays the baked voice clips instead of failing.
- A new usage log no longer starts with a byte-order mark, so its first line reads the same as every other and the same on every host.
- Archiving a card that comes back for a second round now stops with git's own message and exit 2 if git refuses the commit that renames the earlier archived copy to `-r1`, instead of leaving that rename staged and saying nothing.
- Moving a design in the hub, or attaching a cover or before picture, now reports a commit git refuses as an error (exit 2) with git's own message and says the files are already written, instead of a warning that reads as success.
- The Environment badge no longer calls a Space with no tracker an Azure DevOps one.
- Archiving a card that was created and archived with no commit in between now commits the move instead of silently leaving it uncommitted, and a commit git refuses is reported as an error (exit 2) with git's own message instead of a warning.
- Attaching a cover or a before picture from the browser no longer leaves a copy of the image in the system temp folder for good; it is removed once the card has the picture, and stale ones are cleared when the agent starts.
- A tab or a line break in a logged work item title or error message no longer splits the usage log entry into a forged second entry or shifts its columns; both log writers now write it as a space.
- The agent no longer fails to start, or answers 500 on every route, when `config.local.json` has a typo; it falls back to the defaults and `/env` names the broken file.
- Saving a meeting from the browser on Windows no longer rewrites the whole session file with CRLF
  line endings; a save keeps the ending the file already has.
- A collapsed filter drawer no longer keeps its search box and chips in the Tab order or in what a screen reader reads.
- Screen readers now announce the name of each field in the create and action dialogs (Work Item ID, Reason, Comment and the rest) instead of its placeholder text.
- NewPrompt on an Azure DevOps work item now stops with a message pointing at `az login` when no token is available to read the work item's comments, instead of quietly writing a card without them.
- A screen reader now announces the web UI's success and error messages as they appear, and names the "Loading toolkit..." spinner on first load.
- Every Azure DevOps verb now stops with a message pointing at `az login` when `az` cannot give a token, before calling Azure DevOps (CloseItem and NewItem used to send az's error text as the token), and GetPRComments and AddPRReview give the same sign-in advice for a 401 as for a 403.
- Every page now has one top-level heading for screen-reader navigation, and the loading spinners inside buttons are named.
- Opening a pull request on a GitHub Space from Windows PowerShell 5.1 now says why it refused, for example that the branch is not on GitHub yet, instead of printing a raw error.
- When the communication module cannot describe itself, the agent's environment report now logs a warning saying why instead of silently leaving the module out.
- Fetching pull request comments now writes them into the card whose id is the linked work item, never into another card whose name merely contains that number.
- The pull request comments record GetPRComments leaves in pr-comments/ is now written with the same bytes on every host: UTF-8 with no byte-order mark and LF line endings.
- A one-on-one session file whose Stage heading is followed by a comment now reads its stage correctly instead of showing the comment as the stage.
- The scripts behind Connect, EditItem, MyPRs, InstallAutoload, Agent and Web, run on their own without the module, now keep their stated reason when they refuse, as every other script does; they printed the error and then lost the reason.
- `NewPR` run from a folder that is not a repository now says so in its own words on Windows PowerShell 5.1 even when the calling shell stops on errors, instead of printing a raw error from the version control tool.
- Syncing the hub from Windows PowerShell 5.1 under a caller that stops on errors no longer throws on git's own status line; a status read git refuses is now a stated refusal (exit 2) instead of being read as a dirty hub.
- A message the browser shows from a command, such as a refusal in a dialog, no longer begins with the first-run "not set up yet" banner on a machine with no `config.local.json`.
- On Windows PowerShell 5.1 the verbs that read git (`Status`, `Dashboard`, `ThreadHash`, `Archive`, `MoveDesign`, `GetPRComments`, `AddPRReview`, `UpdateResume`, `UpdateReview`, `Update` and `Backfill`) no longer stop on git's first stderr line when the calling shell stops on errors, so a git refusal reads the same as on PowerShell 7.

## [1.0.0] - 2026-10-15

The first release. Everything below is what 1.0.0 is.

### Added

- **The CLI**, PowerShell 7 and Windows PowerShell 5.1: the five verbs that carry a card from a work
  item or an issue to a pull request, through review, to the archive; Status, Dashboard, MyWork and
  the rest of the surface under one configurable prefix; cards with no tracker at all.
- **The agent**, FastAPI: read routes over the same store, `/api/env` for what is on, and the one
  bridge that runs a CLI verb for the browser, so nothing in the web half changes a card except
  through the CLI.
- **The web UI**, React and Fluent: the Studio shell, the board, Daily, the tracker's tabs, and each
  module that is on. Off means absent: no route, no tab, no bytes.
- **Spaces**: one piece of software and how you work on it, from local files alone or connected to
  GitHub Issues or Azure DevOps; switching Space rescopes every card, query and tool.
- **The Studio**: every Space in one foyer, the design notes and specs beside their products, and
  the prompts ToolKit sends to a model shown so a person can read every word.
- **How you work is up to you**: the one question, asked where it has two honest answers, and
  Team Agile, the standup and triage over a repository's issues for a person orchestrating agents.
- **The add-ons**, each off until configuration turns it on: Azure DevOps, growth, communication,
  organize, deck and the lounge.
- **The deck engine and the commercial**, Introducing ToolKit, narrated in two synthetic voices.
- **The landing page**, built from the repository and deployed by a workflow to GitHub Pages.
- **One byte contract for a card**, one place for the magic strings the three halves share, and the
  refusal contract: a command that refuses says why once.
- **The suites**: the CLI's forty-three, the agent's and the web's, read in CI on Ubuntu and on
  Windows PowerShell 5.1 with the browser smoke; the documentation linted; the licenses of every
  dependency, font, picture and clip recorded.
- A security policy, a trust model in the architecture overview, a code of conduct, issue forms, a
  pull request template, and Dependabot for npm, pip and GitHub Actions.

### Removed

- **Design notes and specs leave the product tree**; `design/` and `spec/` hold a README each, saying
  what the folders carry when a product keeps its own there. A tree whose folders hold nothing but a
  README reads `not configured` on the `design` row, not `on` with no designs.
