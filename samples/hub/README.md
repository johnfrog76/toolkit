# Your hub

This folder is where the Toolkit keeps your **cards** -- one Markdown file per piece of work. It is
yours: it is not part of the Toolkit, the Toolkit never updates it, and you can put it under git,
in a synced folder, or nowhere at all.

Start with the card in **To do**, *Welcome to the Toolkit* (`Task W3KC`): its checkboxes are a tour of
the product, and the bar on the card fills as you tick them.

It arrived with a sample organisation, **Demo**, so there is something to look at: a small recipe
app, *RecipeBox*, with a card in every lane of the board, each wearing a cover picture (`<space>/assets/`) -- just started, in progress (it has a commit),
in code review (it has a pull request) -- finished work in the archive, a couple of 1:1s, a goal and a
review. One card, `Spike K7M2`, has no work item behind it at all: that is what a card you make with the
**+** looks like. (A Demo copied out before the covers shipped has none: `tkUpdate` says so, and
`tkCover -Samples` gives each sample card without a cover its picture -- cards you added or covered yourself
are left alone.) Demo
is `local` -- it works from these files and never contacts Azure DevOps.

Beside it is the **GitHub demo**: the same RecipeBox, tracked on a small public GitHub repo. Its cards
link to that repo's issues. It is `local` too until you want it: sign in with `gh` and connect it from
the tip on Home (or `Connect github-demo`), or point it at a repo of your own. And the **Azure demo**
(its folder is `azure-demo/`) is ready for YOUR Azure DevOps organisation: give it the address from its tip on
Home (or `Connect azure-demo -Address https://dev.azure.com/<your-org>`) and sign in with `az login`. None of
this is required.

| Folder | What is in it |
|---|---|
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
