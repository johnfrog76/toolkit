# Changelog

All notable changes to this project are recorded in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
intends to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) from its first
release.

## [Unreleased]

### Added

- `GetPRComments` now works on a GitHub Space: it reads a pull request's inline review comments, its conversation and its reviews' summaries through `gh`, and appends them to the card exactly as it does for Azure DevOps -- safe to re-run, a reviewer's follow-ups included. The card's own `PR URL:` line tells it which repository to read, so it works from the browser with no checkout.

### Changed

- Every list's row menu now uses one vocabulary: the same move has the same word, icon and tooltip on every page, and the link out is always last, reading "Open on GitHub" or "Open on Azure DevOps" behind one icon. A goal's Retire, a reminder's Done and a card's Move to Done now read Archive, a design's two archives read Archive as shipped and Archive as dropped, a card's exposed action opens the card, and Remove cover reads Delete the cover.

### Fixed

- The Reference field in the New Reminder dialog is now as wide as the other fields, instead of sharing a half-width row with Source.
- The Edit Reminder dialog's Source and Reference fields are full width too, like the New Reminder dialog's, and the fields in both reminder dialogs are the same size as the rest of the app's.
- The test suite's check for a raw, unredirected `git`/`gh`/`az` call now catches one written inside a double-quoted string's `$(...)`, a shape it previously missed entirely; the handful of real call sites it found this way now go through the same safe helper as the rest of the CLI.

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
