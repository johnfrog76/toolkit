# Changelog

All notable changes to this project are recorded in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
intends to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) from its first
release.

## [Unreleased]

### Added

- CodeQL scans the web and the agent on every push to main, every pull request and weekly.

### Changed

- Creating a training, presentation or goal from the browser now runs the same command the terminal does, so both write the same file; a refusal shows the command's own message in the dialog.

### Fixed

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
- A message the browser shows from a command, such as a refusal in a dialog, no longer begins with the first-run "not set up yet" banner on a machine with no `config.local.json`.

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
