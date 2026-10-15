# docs/

The Toolkit's manual, one drawer per subject. The root [README](../README.md) is the front door and
carries the map; each file here owns one subject, and a change to that subject changes that file in
the same commit (`AGENTS.md`, "Documentation is part of the change").

| File | Owns |
| --- | --- |
| [`QUICKSTART.md`](QUICKSTART.md) | Requirements, install, the first run (`tkStart`: the sample hub, the Welcome card, the tour banner), a first card, the web UI up |
| [`CONFIGURATION.md`](CONFIGURATION.md) | `tkConfig`, the three config files, `consts.json`, the hub's `hub.json` |
| [`CLI.md`](CLI.md) | The prefix, the workflow and its state, the command reference, tiers, errors, the log, AI review, the agentic workflows |
| [`TESTING.md`](TESTING.md) | The four runners, the suites and their counts, and the counts line a full run prints |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | How the three halves fit, the agent and the web UI in overview, and the repo layout; the detail is `agent/README.md` and `web/README.md` |
| [`KNOWN-GAPS.md`](KNOWN-GAPS.md) | The known gaps: what the product does not do yet, what you see if you try, and the issue that carries each |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | **The contributor's first page**: set up the three halves, run the suites, the refusal contract, the documentation rule, how a pull request is reviewed, and the rules a change meets |
| [`modules/`](modules/README.md) | The ADO core, the Studio (core too, no switch) and the opt-in modules -- growth, communication, organize, solitaireAgile, deck, lounge -- and D-CM, then one end-to-end document per add-on: [`ado.md`](modules/ado.md), [`growth.md`](modules/growth.md), [`communication.md`](modules/communication.md), [`organize.md`](modules/organize.md), [`studio.md`](modules/studio.md), [`solitaire-agile.md`](modules/solitaire-agile.md), [`deck.md`](modules/deck.md), [`lounge.md`](modules/lounge.md) |
| [`hub/`](hub/README.md) | **The data model.** What is in a hub and which document owns each file's shape: [the card](hub/cards.md), [growth items](hub/growth.md), [1:1 sessions](hub/manager.md), [reminders](hub/reminders.md) |
| [`images/`](images/README.md) | Screenshots and a GIF of the board, for a document that wants one, each taken from the sample hub on a scratch first run -- its README says how each was made |

## Assets

- `logo.txt` — the ToolKit mark as ASCII, rendered in a fenced block at the top of
  the README. ASCII rather than SVG or a bitmap: a CLI's logo should survive a
  terminal, it cannot be broken by a missing font, and it diffs as text.

  The construction matches the original drawing — the two `o`s of "Tool" are the
  eyes, so only the smile is drawn.
- `logo-faces-preview.html` — a standalone page that draws the mark's face variants
  side by side, the sketch the Face picker on `/system` (`web/src/shared/faces.ts`)
  was chosen from. Open it in a browser; nothing links to it and nothing builds it.
  It stays out of `web/public/`, where Vite would copy it into every build and the
  Docker image for no reader.
