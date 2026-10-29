# Azure DevOps -- the add-on, end to end

**Azure DevOps is something you plug in.** The product is cards -- files in a hub, a board, a record of
your days -- and it runs with no tracker at all. The Azure DevOps add-on ties a card to a work item and a
pull request, so that work done once is accounted for in two places: the card for the engineer, the
board for the organisation. This document is for anyone working on that add-on, and it stands alone:
everything a person or an agent needs is here or one link away, in the order every add-on's document
follows ([the modules guide](README.md#what-an-add-ons-document-must-contain)).

"We love ADO. We
support ADO. We can turn off ADO and use our cards."

> **A naming trap, first.** Folders called `ado` hold MORE than Azure DevOps: `agent/ado/` and
> `web/src/modules/ado/` also hold the card core (the status route, Daily, the board, the Environment
> card). The name is from when the product was an ADO tool; the rename is roadmap phase 8. **Being in a
> folder called `ado` does not make something part of this add-on** -- the tables below say what is.

## Contents

1. [The switch, and its scope](#the-switch-and-its-scope)
2. [What the add-on owns](#what-the-add-on-owns)
3. [Turning it on](#turning-it-on)
4. [The verbs](#the-verbs)
5. [The routes](#the-routes)
6. [The web UI](#the-web-ui)
7. [What it writes into a card](#what-it-writes-into-a-card)
8. [Tiers: what happens when ADO does not answer](#tiers-what-happens-when-ado-does-not-answer)
9. [The tests](#the-tests)
10. [Known gaps](#known-gaps)

## The switch, and its scope

Two questions, two answers, and they are not the same thing.

**Is THIS ORG connected?** -- `spaces[].status`, per Space, in `hub.json` (or the machine's patch):

| Status | Means | Azure DevOps is |
| --- | --- | --- |
| `active` | the org talks to ADO | probed, and used when it answers |
| `local` | the org works from its cards, by choice | never contacted |
| `archive` | a finished engagement, kept for looking back | never contacted |

**Is ADO part of what this machine SHOWS?** -- derived, one rule in each half
(`Scripts/Test-AdoEnabled.ps1`, `ado_enabled()` in `agent/core/config.py`, held together by
`Tests/fixtures/ado-enabled/table.json`):

```text
ON   when  features.ado is true
     or    features.ado is absent AND the ACTIVE org's status is "active"
           AND its tracker is Azure DevOps ("ado", Scripts/Resolve-Tracker.ps1 / tracker())
OFF  otherwise
```

It follows the org you are in. `features.ado` is the engineer's flag (top-level, `config.local.json`)
and its usual answer is ABSENT; set it to say otherwise. A connected GitHub Space is `active` too, and
its tracker is GitHub, so Azure DevOps reads **off** there -- the inventory's row says why, `follows the
org you are in: <slug>'s tracker is GitHub`, beside `GitHub issues on` -- and a Space that is `active`
with no address is off the same way. It decides what is shown -- `Setup`'s `az` checks, the inventory's
row, `/env`'s `ado` block, the New card dialog's tabs -- and **unregisters nothing**: an ADO verb typed by
name still answers, with its tier sentence ([Known gaps](#known-gaps)). `Menu`'s rows are the TRACKER
verbs, shown wherever there is a tracker to answer them: where Azure DevOps is on, and on a connected
GitHub Space, where they answer through `gh`.
[Configuration](../CONFIGURATION.md#featuresado-is-not-like-the-other-flags) has the long version.

## What the add-on owns

| Half | Azure DevOps's | NOT Azure DevOps's, though it sits beside it |
| --- | --- | --- |
| CLI | twelve verbs and the work-item form of `NewPrompt` (below), the `Scripts/` they run, the tier check | `NewPrompt -Title`, `Archive`, `Billable`, `Status`, `Sync`, `ThreadHash` |
| Agent | `ado/accounting.py` -- `/prs`, `/work-items`, `/dashboard`, `/dashboard/pipelines/{project}`; the identity those filter by | `ado/status.py`, `ado/reporting.py` (Daily, engagement), `ado/pr_comments.py` (reads files), `ado/bridge.py` |
| Web | `MyWork`, `MyPRs`, `Dashboard`, the work-item tab of the New card dialog, *Open on Azure DevOps* and *Create PR* on a card, the repo filter, `ConnectAdoCard` | `Board`, `PromptStatus`, `PromptDetailPage`, `Billing` (Daily), `EnvCard`, `ConfigSettings` |
| A card | the `**ADO Link:**` line, the `PR URL:` line, the review rounds | everything else ([the card](../hub/cards.md)) |

## Turning it on

Nothing to install in the Toolkit. On the machine: the Azure CLI (`az`), signed in (`az login`), with the
`azure-devops` extension. Then one action, in one place:

```powershell
tkConfig -Set spaces.<slug>.org=https://dev.azure.com/<your-org> -Hub
tkConfig -Set spaces.<slug>.status=active -Hub
tkSwitchSpace <slug>
tkSetup                       # states the tier; az problems are said here
```

or in the web UI: the avatar, Settings, the organisation -- its **Tracker address** and **Status**.
Optional per org: `tenant` (when the org is not in your default directory) and `projects` (which
projects the PR, work-item and dashboard reads cover -- `tkConfig -Set "spaces.<slug>.projects=Name/repo; Other/repo2" -Hub`,
the same text in the Settings row, or `tkConnect <slug> -Discover` then `-Projects`).
`email` in `config.local.json` is who "me" is; unset, it falls back to the `az` account.

### The demo Spaces: one per grain

A Space's grain follows its tracker (D-W17), and the toolkit ships one Space per grain to try it on --
each an invitation, none required, each with a tip at the foot of Home (`Config/settings-workflows.json`,
the entries that name a `space`):

| Space | Slug | Ships as | What it is |
| --- | --- | --- | --- |
| **Demo** | `demo` | `local`, no address | the out-of-the-box Space `tkStart` lands in: RecipeBox's cards, no tracker, no login. Its tip: "This is the Demo Space: cards with no tracker. Everything works from the files." |
| **GitHub demo** | `github-demo` | `local`, address `https://github.com/johnfrog76/recipe-box-demo` | the same product tracked on a small PUBLIC repo, declared by `samples/hub/hub.json` (a real address cannot go in `config.default.json`, Portability Clause 2a) with four cards linked to its issues. Its tip, `connect-github`, walks `/connect/github-demo`: sign in with `gh` and keep the demo repo, or give it your own |
| **Azure demo** | `azure-demo` | `local`, no address | "Example" renamed and made honest: the Azure DevOps on-ramp. There is no public Azure DevOps organisation to point at, so it is *ready for yours*: `tkConnect azure-demo -Address https://dev.azure.com/<org>` (or `/connect/azure-demo`) is its one door, writing the address and making it active; then `az login`, said and checked, never run. Until then it is two sample cards in `samples/hub/azure-demo/` and is never probed. Its tip, `connect-azure`: "Set up an Azure DevOps-linked Space. Give the Azure demo your organisation's address and sign in with az." |

**GitHub is offered first wherever a tracker is offered** (the owner's call, D-G16) -- order, not capability: Azure DevOps stays a fully supported tracker, and the connect wizard, the Quick start and the tips name GitHub before it.

**The Azure demo's slug was once `test`, and the old slug still answers.** A machine whose
`hub.json` or `config.local.json` still patches `spaces.test`, or whose `activeSpace` says `test`, reads
it as `azure-demo` -- a nameless hub entry keeps its `promptsFolder`, so a connected Example's cards stay
in `<hub>/test/` -- and `tkSwitchSpace test`, `tkConnect test` and `tkConfig -Set spaces.test.<field>`
take the old slug and say the new one once. The rule and its table are in
[Configuration](../CONFIGURATION.md) ("The Azure demo's slug was `test`"). A machine that set
the old Example's address through `Config` before it became the Azure demo reads `local`: one `tkConnect azure-demo -Address
<url>` makes it active again.

**The GitHub demo ships `local` on purpose.** A cold machine has no `gh` login, and an `active` Space that cannot be
probed reads `unreachable` on the Environment card -- the first thing a new user would see. Local, it is
never probed: the card says `not configured (expected)`, the Board shows its cards, and the connect
wizard's step 1 reads "local until you connect it" with the address already filled in. Saving it
(`tkConnect github-demo -Address https://github.com/johnfrog76/recipe-box-demo`, or **Connect** on the page)
makes it active; step 2 is `gh auth login`, said and checked, never run. The tip retires itself then.

**The repo is seeded once, by its owner**: `samples/seed-recipe-box.ps1` reads
`samples/recipe-box.seed.json` -- four files (a README, a design note, a spec, a docs page), the house
labels, three milestones and a dozen issues -- and writes them through `gh`, skipping anything already
there. No suite runs it and nothing in the toolkit writes to GitHub to set it up. Until it has run, a
connected GitHub demo answers every read with one sentence -- `johnfrog76/recipe-box-demo: gh cannot read
this repository -- it does not exist yet, or it is private to an account this gh login is not` -- in
the card's `reason` line, never an error (`gh_repo_reason` in `agent/ado/accounting.py`).

## The verbs

Twelve verbs are on the add-on's list, `$script:ModuleState.AdoCommands` in `utilities.psm1`, plus ONE FORM of a thirteenth:
`NewPrompt <id>` needs ADO, `NewPrompt -Title` does not, so the verb itself is not on the list. Ten of them
check the tier ONCE, before running, and say what is unavailable and why -- never a silent empty result,
never a raw API error. `Dashboard` has its own Tier 2 view of local cards and repo status, and `LogPeerReview` has no tier check at all.

Eleven of the twelve are in the table below; the twelfth is `LogPeerReview`, a growth verb that logs a review of a colleague's pull request and is org-scoped. Being on the list does one thing: `Menu` leaves its row out where no tracker is shown, and marks it `(unavailable)` at Tier 2 or 3. It is not a tier check on the verb itself.

| Verb | Does | Touches a card? |
| --- | --- | --- |
| `NewPrompt <id>` | scaffolds a card from a work item, with its comments (the `-Title` form needs no ADO and is not part of this add-on); with no `az` token to read the comments it refuses (exit 2, naming `az login`) and writes nothing | creates it |
| `NewItem <title> [-Type]` | creates a work item from the terminal | no |
| `MyWork` | work items assigned to you | no |
| `MyPRs` | your active pull requests across the org | no |
| `Dashboard` | PRs across projects, assigned items with staleness, recent pipeline runs | no |
| `NewPR [<card>]` | the ship-it step: opens the PR, moves the work item to Code Review, comments on it, writes `PR URL:` into the card. Named by id from outside the code repository, the card's `ADO Link` and `## Branch` answer; a project it cannot tell is refused, never guessed; `-WhatIf` calls nothing | writes `PR URL:` |
| `PublishPR [<card>]` | the ship flow's second stage: flips the card's draft pull request to ready (`PATCH` with `{"isDraft":false}`, the token `NewPR` takes). A card with no `PR URL:` line, a pull request already ready and a GitHub pull request (`gh pr ready <url>`) are refused; `-WhatIf` prints the call and sends nothing | writes `PR published: <url>` under `PR URL:`, once |
| `GetPRComments [<pr>]` | fetches review threads and appends them to the card; append-only, safe to re-run | writes `PR URL:` if absent; appends rounds |
| `ReplyPR <pr> <thread> -Reply "..."` | posts a reply to a thread, optionally setting its status, and fills that thread's `Reply:` slot in the card | fills the slot |
| `AddPRReview <pr>` | an AI code review as inline comments; needs `ANTHROPIC_API_KEY`; run it from the PR's own repository | no |
| `CloseItem <id> -Comment "..."` | closes or resolves the work item; `-WhatIf` prints the transition without calling ADO | no |
| `EditItem <id>` | changes what the item says or wears (title, description, sprint, assignee, tags); on a GitHub Space `-Pin` / `-Unpin` are the tracker's own pin (`gh issue pin` / `unpin`, three per repository; a fourth is refused as "GitHub pins three issues per repository; unpin one first"), and on Azure DevOps they are a stated refusal -- a work item has no pin; `-WhatIf` prints the edit | no |

**Two ledgers.** The card is the engineer's record; ADO is the organisation's. `NewPR` posts to both.
**Nothing reconciles them automatically**: `Archive` moves the file and does not touch ADO, so Done here
is not Closed there -- run `CloseItem` too. [The CLI reference](../CLI.md#command-reference) has every
switch.

## The routes

| Route | Tier | Reads |
| --- | --- | --- |
| `GET /api/prs` | 1 | ADO via `az`, filtered by the resolved identity |
| `GET /api/status` | 2+ | the Card model; on a GitHub Space at Tier 1 each card also carries `pinned` -- its issue is in the repository's pinned set, asked once per repo by `gh api graphql` and dropped when `EditItem` runs; at Tier 2, on Azure DevOps and with no tracker `gh` is not asked and `pinned` is false |
| `GET /api/work-items` | 1 | ADO via `az` (WIQL); on a GitHub Space `gh issue list`, with `?state=open\|closed\|all` and `?all=1` as the Issues tab's two agent axes; a gh row carries `pinned`, GitHub's own `isPinned` |
| `GET /api/issue-report`, `GET /api/milestones` | 1, GitHub only | the Stats tab: the report read from the Studio ledger's entry for the Space ([the Studio](studio.md)) -- no `gh` call of its own -- and `gh api .../milestones?state=all` with `reached` derived -- every issue closed and at least one |
| `GET /api/design`, `GET /api/design/{folder}/{name}` | 1, GitHub only | the repo's `design/` and `spec/` via `gh api .../contents` (Studio S2); an owner-grained address is a 400. The list also carries `checkout`: the active Space's `spaceCheckouts.<slug>.path` checked against the repo on every request (`space`, `key`, `path`, `root`, `ready`, `reason`; `agent/core/checkout.py`), which decides whether a row offers `MoveDesign`'s roads ([Studio](studio.md), "The web UI") |
| `GET /api/docs`, `GET /api/docs/{path}`, `GET /api/docs/asset/{path}` | 1, GitHub only | the repo's `README.md` and `docs/` tree, one document (with `issues`, the repository's issues on github.com, or `""` when it has them turned off), one image's bytes -- via `gh api .../contents`, the same gate and cache as `/api/design` (D-S12); an image past the 1 MB the contents route inlines is read from `gh api .../git/blobs/<sha>`, up to 10 MB, and past that is a 413 with a sentence; a document path that is not `README.md` or a `.md` under `docs/`, an image path that is not an image, or any path with a `..` in it, is a 404 before `gh` is asked |
| `GET /api/dashboard` | 1 | ADO via `az`, plus local repo health |
| `GET /api/dashboard/pipelines/{project}` | 1 | ADO via `az` |
| `POST /api/cmd/{name}` | the verb's own | the bridge: runs any verb in the CLI's command table, so the verbs above are callable from the browser with no backend change |

A Tier-1 route on a machine below Tier 1 answers with an empty list and a `reason` when the gap is one
the reader can close (no identity), and with the honest empty otherwise. At Tier 1 the same field says
why an empty list is empty when something failed: an org with no `projects` (the reason names the slug
and `hub.json`), or the first `az` call that failed, as one sentence naming the command and the project
-- a timeout, a missing `az`, stderr, output that is not JSON. A list with rows in it carries no reason. `GET /api/env` serves
`ado: { enabled, explicit }`, the tier, the org's status and the identity. It gates no route.

## The web UI

- **Home, List view** -- *My Work* and *My Pull Requests* (Tier 1), *PR Comments* (Tier 2: it reads files).
  A PR Comments page answers a thread in place: an open thread with no reply in the card gets a
  reply box, **Suggest a reply** drafts one through the agent's model route when `ANTHROPIC_API_KEY`
  is set (the box says so when it is not), and **Post reply** runs `ReplyPR` through the bridge --
  the tracker gets the reply, the card's `Reply:` slot gets it through `Write-CardText`, and the
  page re-reads the card. The agent writes no card here; the native `save` route was retired.
  For an org with no ADO, Home is the board alone and these are absent; `ConnectAdoCard` and the quiet
  line under the board are the way in (`homeViewFor`, [the web README](../../web/README.md#the-board)).
- **The New card dialog** -- a *From a work item* tab beside *New card*, and the default where ADO is
  reachable. Where ADO is not in use there are no tabs at all.
- **On a card** -- an **ado** badge first in its meta line (a GitHub-born card wears **gh**, a custom card
  nothing: the card model's `tracker`, from the card's own link), *Open on Azure DevOps* (last in the menu), *Create PR*, the project tag, and the repo filter (which matches on the
  ADO link, so it hides every unlinked card and SAYS how many). The first two are ABSENT on a card with
  no work item, and on every card while ADO is off; *Create PR* is disabled, with the reason, until the
  card records a commit (`web/src/modules/ado/cardActions.ts`, [the web README](../../web/README.md#the-board)).
- **Design, on a GitHub Space** (Studio S2, D-S11) -- the fourth Home tab, after Issues,
  Board and Stats: the product repo's `design/` and `spec/` folders, read through the tracker
  (`GET /api/design`, `gh api repos/{owner}/{repo}/contents/...`), the note first and the spec beside
  it. A row shows the title (the file's first `#` heading, else its name), the frontmatter
  `description`, the folder, and the thread its `> GitHub:` line names; it opens a reading room at
  `/design/{folder}/{name}` -- the house reading page, the document and then its thread in one viewer.
  Gated by the tracker and Tier 1, nothing else: no flag, and an ADO or local Space has no such tab.
  The address must name a repo; an owner-grained one is refused with a sentence. The filter drawer
  narrows the list by text over the titles and by kind (design note | spec); the header says
  what is set.
- **Docs, on a GitHub Space** (D-S12) -- the fifth Home tab, last: what the product IS, beside
  Design's what it will be. It lands on the repo's `README.md` in the reading room, with everything
  under `docs/` folded above it as the fallback index (`GET /api/docs`, then
  `GET /api/docs/README.md`); one document's room is `/docs/<path>` (`/docs/docs/CLI.md`). The
  README's relative links are the drawers, and ONE resolver in the shared viewer decides where each
  goes (`web/src/shared/docLinks.ts`): a relative link to `README.md` or a `.md` under `docs/` opens
  that document in the room with its `#anchor` kept; a link to a design note or a spec opens the
  Design room; a `#anchor` scrolls, to the id github.com gives the heading; a relative image --
  under `docs/`, beside the README, in a folder of its own, climbing above `docs/` with `../`, or
  written from the repository root as `/assets/x.png` -- comes through `GET /api/docs/asset/<path>`,
  so a private repository's pictures load without a GitHub sign-in in the browser; a path that would
  climb out of the repository is never asked for. An image up to 1 MB comes inline from the contents
  route, a larger one from its blob by sha, and the ceiling is **10 MB**: past it the room shows a
  broken image and the agent answers 413 with the size, because a picture in a document is rarely
  past a few MB and the bytes cross a pipe as base64 -- open that one on GitHub. A `#N` in a
  document's prose opens issue N of the Space's repository in the issue room (`/issue/N`), as does
  a link to that issue's github.com address; a `#N` inside a code span, a code block or a link's own
  text stays text, and so does every `#N` when the repository has its issues turned off (the
  agent's `issues` is `""`). An absolute link, or a relative one to anything else
  (`AGENTS.md`, `VERIFY.md`), leaves in a new tab -- on github.com, saying so on hover. The Design
  room reads its documents through the same resolver, its images included; its `#N` mentions stay
  text. Which paths are docs is the contract's
  (`consts.json` `docs`), so the room never links to a path the agent refuses. Same gate as Design:
  GitHub, Tier 1, an address that names a repo; no flag. The filter drawer narrows the folded `docs/`
  tree -- and only that, never the README -- by text over titles and paths and by folder, the folders
  the tree actually has.
- **The filter drawer** -- ToolKit's card filters wherever cards are drawn; the repo row (the
  org's projects, matched on a card's ADO link) on an Azure DevOps Space only; and on a GitHub Space's
  Issues tab the issue filters -- state, assignee, worked by, kind, severity, milestone -- with search
  over the issue's number, title and labels. The Issues list shows what they are set to in one line. A collapsed drawer is inert: Tab skips it and a screen reader does not read it.
  A card with no ADO repository -- no link, or a GitHub issue link -- belongs to none of those projects and is never hidden by the repo row; only a card whose ADO link names a different project is filtered out.
  `drawerSections` in `homeTabs.ts` decides, per tab; [SCENARIOS](../SCENARIOS.md) has the grid. The
  control is drawn on every tab of a strip: on a tab with no sections (Stats) it is disabled, with
  the tooltip `No filters on this tab`, so the strip never changes height between tabs. Design's kind and
  Docs' folder are the same chip rows (`DocFilterRows.tsx`), declared as the `kind` and `folder` sections.
- **Stats, on a GitHub Space** -- the Issue Report, then **Milestones**, then Deploys. Milestones
  is one row per GitHub milestone: the title, a progress bar (closed of total), the two counts, the due
  date when one is set, and Open on GitHub last in the row. **Reached** is derived, the way a card's
  state is: every issue closed and at least one issue; a reached milestone GitHub still shows open reads
  **reached, not closed** -- the one thing left to do on the tracker -- and a closed one wears its closed
  date. In flight first (most complete at the top), then reached, then empty; one tile row above the list
  (reached, in flight, issues left). Read only: a milestone is made and closed on GitHub.
- **Dashboard** -- a Home card at Tier 1 (not a page of its own): the terminal's morning view --
  pull requests across projects, assigned items with staleness, recent pipeline runs.
- **Settings** -- the org's address, tenant and status; the **Azure DevOps** row (`features.ado`), whose
  switch shows what is in effect when unset.

## What it writes into a card

Four things, and only these ([the card](../hub/cards.md) is the whole model):

| In the card | Written by | Effect |
| --- | --- | --- |
| `**ADO Link:** https://...` in the footer | `NewPrompt <id>` | the card is `linked`; offline it reads `(not linked -- ...)` |
| `PR URL: https://...` | `NewPR`, `GetPRComments` | **the gate into Code Review** -- the line, not the comments |
| `## PR Review Comments`, one block per round | `GetPRComments` | the PR Comments card and page; not state |
| `PR published: https://...`, directly under `PR URL:` | `PublishPR` | a record that the draft was published; not state, and nothing reads it but `PublishPR`, which does not write it twice |

Take all four away and a card is still a card: that is the whole meaning of "plug-in".

## Tiers: what happens when ADO does not answer

| Tier | Means | This add-on |
| --- | --- | --- |
| 1 | `az` present, signed in, ADO reachable, org `active` | everything |
| 2 | repo and git, no ADO -- or an org that is `local` / `archive` | ten verbs say what is unavailable and why, `Dashboard` shows a local view, and `LogPeerReview` (it needs the hub, not a tracker) runs; the Tier-1 routes are empty; **cards, the board, Daily and Sync are unaffected** |
| 3 | repo or git missing | `Menu` and the tests |

An `archive` or a `local` org is never probed, so it cannot FAIL a check. The Environment card and `tkEnv`
name this add-on's row -- **ADO Add-on** in `tkEnv`; in the card, the Space's tracker by name (**Azure DevOps**, **GitHub**), or **Tracker** on a Space with none -- and say, per org status:

| Org | Row says | Badge |
| --- | --- | --- |
| `local` | `not configured (expected)` | **Local**, green |
| `archive` | `not contacted -- archived` | **Archive**, neutral |
| `active` | `connected (<org>)` / `unreachable (<org>)` | **Full**, green / **Offline**, yellow |

Only an `active` org that tried and failed is a warning. **The invariant:** losing the
tracker degrades the workflow; it must never break the record.

On Tier 1, every verb that calls the Azure DevOps API asks `az` for a token first, through one helper
(`Scripts/Get-AdoToken.ps1`), and with one rule: `az` exiting non-zero, or printing no token, is a
stated refusal naming `az login`, before anything is read or written. A 401 or 403 from Azure DevOps
gets the same sign-in advice wherever it is explained. The messages are in [the CLI
reference](../CLI.md#errors), under "Not authenticated" and "Access denied".

## The tests

| Suite | Holds |
| --- | --- |
| `tkTestToolkit -Setup` (`Tests/Test-Setup.ps1`) | the on/off rule over the shared table; `Setup` and `Menu` on machines with and without ADO, `az` taken off the PATH |
| `Tests/test_ado_enabled.py` | the agent's copy of the rule over the SAME table; what `/env` serves |
| `Tests/test_env_org_state.py` | "never asked" is not a failure |
| `Tests/test_identity.py`, `test_env_probe.py` | who "me" is, with `az` stubbed; `/env` neither blocks on the probe nor repeats it |
| `tkTestToolkit -PullRequest -CloseItem -PRComments` | the PR description parser, the transition rule and ADO's error messages, the actionable-thread filter; `-CloseItem` also holds the token helper on both PowerShells -- `az` failing with error text, or printing nothing, is a refusal and never a token |
| `web`: `cliBridge.test.ts`, `homeView.test.ts` | the exact argv each dialog sends; which view of Home an org gets |
| `VERIFY.md` | the verbs that cannot be automated, because they need a real board -- the manual runbook |

**No suite calls Azure DevOps.** `az` is stubbed or absent in every one, by design: a signed-in machine
must not be able to pass a failing assertion.

## Known gaps

- **Hidden, not gone.** With ADO not in use its verbs leave `Menu` but stay registered; the bridge will
  still run them and the routes still exist. Unregistering is phase 8 of
  [`docs/ROADMAP.md`](../ROADMAP.md).

[Known gaps](../KNOWN-GAPS.md) is the list for the whole
product; these are the ones that belong to this add-on.
