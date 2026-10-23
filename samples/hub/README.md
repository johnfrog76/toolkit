# Your hub

This folder is where the Toolkit keeps your **cards** -- one Markdown file per piece of work. It is
yours: it is not part of the Toolkit, the Toolkit never updates it, and you can put it under git,
in a synced folder, or nowhere at all.

Start with the card in **Backlog**, *Start here: pull me onto the board* (`Task H3RE`). It is the first
of five tutorial cards on the **Demo** board, and each one is finished by doing the thing it teaches:

| Card | Where it starts | It teaches | It is done when |
|---|---|---|---|
| *Start here: pull me onto the board* (`Task H3RE`) | `demo/backlog/` | a card is planned until you pull it; the board reads the folder | it is in To do: dragged there, or `Move H3RE -To Active` |
| *Open me and tick my boxes* (`Task T6CK`) | `demo/current/` | a card is a document; its bar counts every checkbox in the file | every box is ticked |
| *Find out one thing and write it down* (`Spike F7ND`) | `demo/current/` | a Spike ends in a finding, not code; the file is the record | its one box, "I wrote what I found under Findings", is ticked |
| *Say "look at this"* (`User Story R3VU`) | `demo/current/` | review is a moment you record | it is in Waiting: dragged there, or `Move R3VU -To CodeReview` (a `**Review:**` line) |
| *Drop me on Done* (`Bug D9NE`) | `demo/current/` | a card travels one way; Done is the archive, with the date | it is in `demo/archive/` |

The board is the progress: when the five are done and the finished ones are on Done, the **To do** lane
is empty. The last card ends at the **+**, where your first real card starts.

The rest of Demo is there to look at: a small recipe app, *RecipeBox*, with cards in the other lanes, each
wearing a cover picture (`<space>/assets/`) -- in progress (with a commit, or started by hand), in code
review (it has a pull request) -- finished work in the archive, a couple of 1:1s, a goal and a review. One
card, `Spike K7M2`, has no work item behind it at all: that is what a card you make with the **+** looks
like. (A Demo copied out before the covers shipped has none: `tkUpdate` says so, and `tkCover -Samples`
gives each sample card without a cover its picture -- cards you added or covered yourself are left alone.)
Demo is `local` -- it works from these files and never contacts Azure DevOps.

Beside it is the **GitHub demo**: the same RecipeBox, tracked on a small public GitHub repo. Its cards
link to that repo's issues. It is `local` too until you want it: sign in with `gh` and connect it from
the tip on Home (or `Connect github-demo`), or point it at a repo of your own. And the **Azure demo**
(its folder is `azure-demo/`) is ready for YOUR Azure DevOps organisation: give it the address from its tip on
Home (or `Connect azure-demo -Address https://dev.azure.com/<your-org>`) and sign in with `az login`. None of
this is required.

| Folder | What is in it |
|---|---|
| `demo/backlog/` | cards planned, not yet in play -- the first tutorial card starts here |
| `demo/current/` | cards being worked on |
| `demo/archive/` | finished cards -- a card travels one way, `current/` to `archive/` |
| `github-demo/` | the GitHub demo's cards, the same two folders |
| `azure-demo/` | the Azure demo's cards |
| `manager/` | 1:1 agendas and retros (the Meetings tab) |
| `growth/` | goals, training and talks (the Growth tab) |
| `reviews/` | reviews of a period's work, generated from the cards |
| `resume/` | the skills page |
| `reminders/` | notes to yourself with a due date (the Organize tab) -- one file each, `current/` then `archive/` |
| `design/`, `design/archive/`, `spec/`, `spec/archive/` | designs for RecipeBox (the Studio's **Hub Designs** card): a note still being thought about, one that became a spec, a completed pair and a dropped one. Made with `NewDesign` and `MoveDesign`; each file's `id:` pairs a note with its spec |
| `docs/` | the document the completed spec points at (`> Docs:`), rendered by the markdown viewer |

**To use it for real:** open Settings from your avatar, add your organisation, give it its Azure
DevOps address, and switch to it. Everything here is sample text and belongs to nobody -- delete it
when it has stopped being useful.
