# Changelog

All notable changes to this project are recorded in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
intends to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) from its first
release.

## [Unreleased]

### Fixed

- The agent no longer fails to start, or answers 500 on every route, when `config.local.json` has a typo; it falls back to the defaults and `/env` names the broken file.
- Saving a meeting from the browser on Windows no longer rewrites the whole session file with CRLF
  line endings; a save keeps the ending the file already has.

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
