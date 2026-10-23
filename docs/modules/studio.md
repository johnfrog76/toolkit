# Studio -- end to end

**The Studio is the studio developer's view across their products, and it is part of the core.** Every
Space is a row in it, and the Studio's first surface is the **foyer** -- the **Spaces** card: one row per Space, filtered by kind, each saying in
one line how that Space stands -- for a GitHub Space its open issues, what closed this week, an open sev1,
the last deploy's state and age; for an Azure DevOps Space or one with only its own cards, its cards --
and each row the way into that Space; its **+** adds a Space -- one of your repositories, or your own cards --
through `NewSpace`. Its second is the **seed drawer**: the hub's `design/` notes, the
designs that belong to no product yet, written by `NewDesign`, each read in a reading room with its thread,
and **promoted** -- its thread opened as an issue labelled `design` -- by `NewItem -FromDesign`. Its third is the
**Prompts** card: the agentic prompts ToolKit ships and the ones your hub adds, each readable, each
marked with who sends it, and **Copy reference** -- ToolKit's filtered to the way you work on the Space. It was specced as
milestone S2b, built as an opt-in module and made core by D-S13.

This document stands alone: everything a person or an agent needs to work on the Studio is here or one
link away. It is no longer an add-on, but it keeps the standard every add-on's document follows
([the modules guide](README.md#what-an-add-ons-document-must-contain)), because a reader looking for the
Studio finds it beside the modules.

**It is never a merged backlog** (D-G11, D-S2). Each product keeps its own issues in its own Space; the
foyer counts them per Space and a row switches you in. Reading two products' issues side by side is
two Spaces, which is the layout doctrine and not a gap.

## Contents

1. [No switch: the Studio is core](#no-switch-the-studio-is-core)
2. [What it owns](#what-it-owns)
3. [The first run](#the-first-run)
4. [The verbs](#the-verbs)
5. [The routes](#the-routes)
6. [The web UI](#the-web-ui)
7. [The file shape, and how a note is read](#the-file-shape-and-how-a-note-is-read)
8. [The tests](#the-tests)
9. [Known gaps](#known-gaps)

## No switch: the Studio is core

**There is no `features.studio`** (D-S13, amending D-S1; the owner: "remove optional configuration
for the Studio tab because it is a studio"). Like the cards, the Studio cannot be turned off: the tab, its
routes and its verbs are there from the first run, on every Space, for everyone. A person learns
the product as a studio from day one.

- The verbs `NewDesign`, `StampDesign`, `MoveDesign`, `NewSpace`, `RetireSpace` and
  `RemoveSpace` are core verbs: `config.default.json`
  `commands` and their wrappers in `utilities.psm1`, so they are in the autoload manifest and answer in a
  profile-less shell, in `Menu` (under **Studio**), `-Help` and the bridge.
- The agent's routes are mounted with no gate.
- The web's descriptor declares no `feature`, so the registry always mounts it. Its pages are still
  `lazyPart`s -- lazy is about bytes, not about being optional -- so nothing past the descriptor is
  fetched until someone opens the tab.
- It is not in the `Opt in by configuration` inventory (`Scripts/Get-OptionalSurfaces.ps1`), the
  settings questions (`Config/settings-workflows.json`) or the Modules card: it is not optional.

**A `features.studio` line left in a machine's `config.local.json`** -- `true` or `false` -- is ignored
by every half and is never an error. **`Config -Set features.studio=...`** (and `-Unset`) is refused,
exit 2, with one sentence: `The Studio is part of the core and has no switch` (the retired-key table in
`Scripts/Get-ConfigSchema.ps1`).

D-S9 still holds for DESIGNS -- a design's thread is a GitHub issue, so Promote refuses on an Azure DevOps
Space -- but it no longer decides who appears in the foyer: every Space has a row.

## What it owns

| Half | The Studio's | Not the Studio's, though it sits beside it |
| --- | --- | --- |
| CLI | `NewDesign`, `StampDesign`, `NewSpace`, `RetireSpace` and `RemoveSpace`: their entries in `config.default.json` `commands` (category `studio`) and their wrappers in `utilities.psm1` (`New-P20DesignNote`, `Set-P20DesignStamp`, `New-P20Space`, `Invoke-P20RetireSpace`, `Remove-P20Space`); `Scripts/New-DesignNote.ps1`; `Scripts/Set-DesignStamp.ps1`; `Scripts/New-Space.ps1`; `Scripts/Retire-Space.ps1`, `Scripts/Remove-Space.ps1` and what both read, `Scripts/Get-SpaceLifecycle.ps1`; `templates/DesignNote.template.md`; the retired `features.studio` row of `Get-P20RetiredConfigKeys` | `Write-CardText.ps1`, `Resolve-HubConfig.ps1` (`Get-P20HubFolder`) -- shared; `Set-ToolkitConfig.ps1`, the one config writer, which `NewSpace`, `RetireSpace` and `RemoveSpace` write every key through (`-Unset spaces.<slug>`, the whole Space, is the half that removing a Space added); `Test-TrackerSignIn.ps1` and `Resolve-Tracker.ps1`, the connect wizard's |
| Agent | `agent/studio/` -- one router, always mounted, `notes.py`, `spaces.py`, `prompts.py` and `ledger.py` (the foyer's one read of every GitHub Space), **reads only** | `GET /api/issue-report`, `GET /api/deploys` and `GET /api/visibility` (`agent/ado/accounting.py`) -- the ADO core's, which grew a `space` argument for the foyer; the ledger reuses their answer shapes, `_github_deploys`, `gh_repo_reason` and the visibility cache (`remember_visibility`), and `graphql_aliases` in `agent/ado/repo_read.py`; `agent/core/disk_cache.py`, where it keeps a Space's ledger; `GET /api/env`, which says which tracker each Space's address names; `GET /api/status`, the core's cards in play, which grew a `space` argument so a non-GitHub row counts its own; `lane_names()` in `agent/core/config.py`, which `/env` now applies to each Space; `parse_doc` in `agent/ado/design.py`, the one reader of a design document's title, description and thread, which the Design tab uses too |
| Web | `web/src/modules/studio/` -- `index.tsx` (`studioModule`, no `feature`), `paths.ts`, `StudioPage.tsx`, `FoyerCard.tsx`, `foyer.ts` (the row's words), `useEnterSpace.ts` (the one switch into a Space, the foyer's row and a note's Space chip both take it), `DesignsCard.tsx`, `DesignNotePage.tsx`, `noteLinks.ts`, `NewSpaceDialog.tsx` and `newSpace.ts` (the + on the Spaces card), `SpaceLifecycleDialog.tsx` (a row's Retire and Remove), `PromptsCard.tsx`, `PromptPage.tsx` and `prompts.ts` (the Prompts card and its reading room), `api.studio.ts` | the switch itself, `POST /api/switch-mode` -- the shell's; `useGetStatusQuery` (`ado/api.ado.ts`); the connect wizard at `/connect/<slug>`; `cliBridge.ts`'s `buildNewDesignParams`, `buildNewSpaceParams` and `buildSpaceLifecycleParams`; `shared/ConfirmDialog` (its `confirmDisabled`); the shared viewer and its link resolver (`shared/docLinks.ts`) |
| Hub | `<promptsRoot>/design/`; read only, `<promptsRoot>/agentic/` (`folders.agentic`) and `agenticExtensionPath` -- your prompts, listed beside ToolKit's | every Space's cards; a product's own `design/` and `spec/`, which live in its repo and are the Design tab's |
| Contract | `consts.json` `studio`: `noteName`, `threadLine`, `threadRegex`, `promptsRoute`, `ledgerRoute` | `stamps.created` -- reused as-is; `agentic/prompts.json`, the index of the shipped prompts (`agentic/README.md`); the ways of working and their words, the How do you want to work? answers in `Config/settings-workflows.json` |

## The first run

Nothing to turn on. From a cold `Start` -- the sample hub copied out, no `gh`, no `az` -- the nav has a
**Studio** tab (after Growth's and Organize's places, before Team Agile's and the Lounge's), and its
**Spaces** card, on **All**, lists the three demo Spaces (all three under **Out of box**): **Azure demo** and **Demo** (no tracker yet -- their cards,
and a line saying what connecting would show) and **GitHub demo** (a GitHub address, `local` until
connected -- a line saying that connected, the row shows its open issues and last deploy). Nothing on the
page reads as an error. The card's **+** adds a Space of your own -- with no `gh` its dialog asks for the
repository as `owner/name`, or offers your own cards. **Hub Designs** lists four designs from the sample hub's own `design/` and `spec/` -- one live note, one
that graduated to a spec, a completed pair and a dropped one, all about RecipeBox -- and says
`No design/ folder yet` only on a hub an older `Start` copied out, whose **+** makes the first note, and the folder with it.

```powershell
tkNewDesign -Title "Board ideas" -Description "What the board could show next"
```

and the note is under the foyer, in **Hub Designs**. Both verbs are in the autoload manifest, so they
answer in a fresh shell like every core verb.

## The verbs

| Verb | Does | Touches a file |
| --- | --- | --- |
| `NewDesign -Title <t> [-Description <text>] [-Space <slug>]` | scaffolds `design/<slug>.md` in the hub from `templates/DesignNote.template.md`: the frontmatter `id` (a fresh UUID v4 -- the design's identity, `consts.json` `design`), `description` (one line, a `"` written as `'`) and `space` (only when given, and it must be a declared Space), the title, the template's headings, `**Created:**`. The name is the title's slug, and always matches `studio.noteName`. Never overwrites | creates one |
| `StampDesign [-Hub] [-WhatIf]` | gives every design note and spec an `id:` in its frontmatter (design lifecycle L1). Walks `design/`, `design/archive/`, `spec/` and `spec/archive/` -- of the git root of the current directory, which it prints first and which must hold `design/`, or with `-Hub` of the hub's folders and a declared Space folder's own -- and for every markdown file with no `id:` adds one, creating the frontmatter block where there is none. A spec takes the **same** id as the note whose file stem it shares (`design/x.md` and `spec/x.spec.md`); if exactly one of the pair already has an id the other takes it, and a pair that disagrees is reported and left alone. Never changes an id that is present, never writes a file it did not change (a second run writes nothing), keeps each file's line endings, skips `README.md`. `-WhatIf` names every file and writes none. Stamps; does not commit | edits the files that need an id |
| `MoveDesign <name\|id> -To Spec\|Archive\|Complete [-Dropped] [-Reason <text>] [-Doc <path>] [-Hub] [-Space <slug>] [-WhatIf]` | the design lifecycle's one verb (L3). Names a design by a file, the stem both files share, or any unique id prefix of four or more; refuses by the state rule, exit 2 and one sentence. **Spec** scaffolds `spec/<stem>.spec.md` from `templates/Spec.template.md` with the note's id, description and thread, the note staying; **Archive** moves the note to `design/archive/` with `**Closed:**` and `**Outcome:** shipped` -- or `dropped` with `-Dropped -Reason`; **Complete** moves spec and note into their archives together, stamps both, writes `> Docs: <path>` into the spec and needs a `-Doc` that exists. Every move appends one dated, self-contained line to the note's `## Journey`, the first move adding the birth line. A repo: the git root named first, `git mv` and `git add`, never a commit, the suggested commit line printed. `-Hub`: the hub's folders, or a declared Space's own with `-Space`, committed under `storeSync: git` the way `Archive` is. Never overwrites; `-WhatIf` writes nothing. The full contract is [the command reference](../CLI.md#the-studio-spaces-and-design-notes) and [the shape](../hub/design.md) | moves one or two files, stamps them, appends to the note; creates one spec |

Every refusal is stated -- `Error:` and a `Hint:`, exit 2, nothing written: no title, a title with no
letter or digit to name the file with, an undeclared `-Space`, a file that already exists.

**`NewSpace`** adds a Space -- the verb the Spaces card's **+** runs:

| Verb | Does | Touches a file |
| --- | --- | --- |
| `NewSpace [<slug>] [-Repo <owner/name>] [-Address <url>] [-Name <text>] [-Discover] [-Owner <owner>] [-AsJson] [-WhatIf]` | `-Repo owner/name` a GitHub Space (`active`), its slug and name proposed from the repository's name (`juggling-engine`, `Juggling Engine`); `<slug> -Address <url>` an Azure DevOps organisation (`active`; its projects are `Connect <slug> -Discover`, named as the next step); `<slug>` alone your own cards (`local`). Every key through `Config`, one in-process call; then `<slug>/current` and `archive` -- a folder already there adopted untouched, its cards counted. `gh` signed in: the repository checked, `PUBLIC` or `PRIVATE` said, then `ARCHIVED` when GitHub has archived it (the status stays `active`) and `READ-ONLY` when you can read it and not write to it; a repository the login cannot see: added anyway, "not visible to this login" with the line `gh` answered; no `gh`: added anyway, "not checked". It never switches: the last line is `SwitchSpace <slug>`. `-Discover` lists your repositories, the ones already Spaces, the GitHub-archived ones and the read-only ones marked (`ARCHIVED`, `READ-ONLY`; `isArchived`, `viewerPermission`, `readOnly` in the JSON), each with its `NewSpace -Repo` line, and names the owners you can choose; `-Discover -Owner <org>` lists an organisation's, `-Owner collaborator` the ones shared with you, and an owner `gh` cannot see is refused, exit 2. A list is read to **1000** repositories -- `gh repo list --limit 1001`, or `gh api user/repos` a page of 100 at a time with `per_page` and `page` as `-f` fields, until a short page or the ceiling; the organisations the same way -- and past 1000 it lists the first 1000 and says there are more (`ceiling`, `more` in the JSON). `-Discover -Repo owner/name` reads one repository before it is added (`gh repo view`, the read the Add makes): its row, visibility and marks; one the login cannot see is a row all the same, its visibility `UNKNOWN` (the contract's `unknown`) and its `note` `not visible to this login: gh answered '...'`, exit 0. `-Repo` with `-Owner` is refused, exit 2. The full contract is [the command reference](../CLI.md#the-studio-spaces-and-design-notes) | `hub.json` (through `Config`); makes one folder |
| `RetireSpace <slug> [-WhatIf]` | the engagement is over, keep the record: `status: archive` through `Config`, a status this machine overrides unset with it. The Space stays declared, its row under **Archive**, its cards where they are and readable, its tracker never asked again; the output names the `Config` line that brings it back. Already archived: said, nothing written | `hub.json` (through `Config`); `config.local.json` only to drop a status override |
| `RemoveSpace <slug> [-Force] [-WhatIf]` | un-declare a Space: its `hub.json` entry and this machine's patch for it go, through `Config`. **Removing never deletes a card**: the folder stays as it was, and the output says where, how many cards (current and archive), and the `NewSpace` line that adopts it back. Refused: the Space you are in, a Space `config.default.json` ships, an undeclared slug. Cards in `current/` ask first, naming the count; a caller that cannot answer needs `-Force`. The full contract is [the command reference](../CLI.md#the-studio-spaces-and-design-notes) | `hub.json` and `config.local.json` (through `Config`); never a folder |

**Promote is `NewItem -FromDesign <note>`** -- the core verb the Backlog uses, with one switch the Studio
adds (spec: "Promote ... `NewItem`, the same verb the Backlog uses"):

| Verb | Does | Touches a file |
| --- | --- | --- |
| `NewItem -FromDesign <note> [-Type ...] [-Tags <a;b>] [-Sprint <m>] [-AssignTo <who>] [-Project <repo>] [-ReadOnly]` | opens an issue in the ACTIVE Space's repo: its title the note's `#` title, its body the note's text without its frontmatter and title, labelled `design` (`consts.json` `studio.promoteLabel`) beside any `-Tags`; then writes `> GitHub: <issue url>` under the note's title (a blank line either side) through `Write-CardText`, an EDIT -- the note keeps its own line endings. `-ReadOnly` prints what it would create and write, and does neither | rewrites one note: inserts one line |

It refuses, stated with exit 2, asking nothing of `gh` and writing nothing, when: `-Title`, `-Description`, `-AcceptanceCriteria` or
`-ReproSteps` is given beside it (the note is the title and body); the name is not a note's; there is no
such note; the note already has a thread (a note is promoted once); the note names a Space you are not in
(`SwitchSpace <it>`, then promote -- its thread belongs in that product's tracker); or the Space you are in
is not GitHub (D-S9: a design's thread is a GitHub issue). The label must exist on the repo, as every
`NewItem` label must.

The foyer's switch is not a verb of the Studio's: it is the one the avatar menu makes.

## The routes

The seed drawer's routes, the + dialog's one, the Prompts card's two and the Spaces card's ledger are the Studio's, mounted with no gate (D-S13):

| Route | Gate | Reads | Writes |
| --- | --- | --- | --- |
| `GET /api/studio/design` | none | the hub's four folders (`folders.design`, `folders.spec`, each with its `archive/`; design lifecycle L2): `designs` grouped by id with the state read from where the files are, `notShown` (a file with no `id:`, or an id two notes share), `structure` (which roots exist) -- the same shape `GET /api/design` answers for a repo, plus `space` and `thread_space` on a hub row; every row's `cards` are every declared Space's cards whose `> Design:` line names its id, read on every request -- and, as before, `items` and `count` (the live notes in `design/`: `name`, `title`, `description`, `space`, `thread`, `thread_number`, `thread_repo`, `thread_space`), `folder`, `specFolder` and `exists`. A hub with no `design/` answers 200, empty, with `exists: false`. The rule is [`docs/hub/design.md`](../hub/design.md), "State" | nothing |
| `GET /api/studio/design/{path}` | none; a path outside the four folders, or a name outside `studio.noteName`, is 404 before anything is read | one document by its hub path -- `design/x.md`, `design/archive/x.md`, `spec/x.spec.md`, `spec/archive/x.spec.md`; a bare name is still the live note -- the note's fields, `path`, `kind`, `archived` and its `body` | nothing |
| `GET /api/studio/design/search?q=` | none; declared before the `{path}` read | **search inside** the hub's four folders, on disk (L2b): the box's words -- every one, any order, case ignored -- over each file's text; `hits`, each the design's `id`, `title`, `state`, the file's `path`, `kind`, `archived` and the first matching `line` (a file with no id is a hit with no state), in road order; `available` is always true here and `note` says it searched the hub as it is right now. `GET /api/design/search?q=` is the repo's twin, through the tracker's code search scoped to each root and asked for text matches: `available: false` with `reason` when `gh` cannot answer, `supported: false` off GitHub, and `note` that code search reads the default branch only and lags a push by minutes | nothing |
| `GET /api/studio/prompts` (`consts.json` `studio.promptsRoute`) | none -- core. A shipped prompt whose `module` in the index is an add-on that is off is **left out**: off means absent. The Space's rows alone sit behind the Design tab's `repo_gate` (GitHub, Tier 1, an address that names one repo) -- a Space it does not pass has none, and the gate's owner-grained **400** is, here, simply no Space rows | `prompts`, each `name`, `ref` (the reading room's address after `/studio/prompts/`: the name, `yours/<name>`, or `space/<name>`), `group` (`toolkit`, `yours` or `space`), `path` (where it lives, `agentic/<name>.prompt.md` or your folder's), `file_path` (the absolute path; for the Space's, the file's address on GitHub); THE RECORD every row carries, wherever it lives -- `title` (the frontmatter's `title`, else the one `#` heading, else the name), `purpose` (the frontmatter's `description`, also served as `description`), `owner` (`toolkit`, `yours`, or the active Space's slug -- worked out from where the file was read, never written in one) and `category` (a shipped prompt's from its index entry, any other's from its frontmatter `category` line, lowercased; `uncategorized` when there is none); from `agentic/prompts.json` its `workflows`, `sender`, `by_hand`, `module` and `drives`; `changed` (the local day of its last commit, one `git log` per folder, else the file's time) and `history` (`https://github.com/<owner>/<repo>/commits/<sha>/<path>` when the folder's clone has a GitHub origin, else `""`), and **no text**: the list carries no `body`, so it stays a few KB however long the prompts are. The whole file is `GET /api/studio/prompts/{ref}`'s `body`, which **Copy prompt** and the reading room read when asked (the card fetches it on the click). YOURS are the `*.prompt.md` files in `agenticExtensionPath` (then `overrides: true` under a shipped name: it runs instead, `Scripts/Resolve-AgenticPrompt.ps1`'s rule) and in the hub's `agentic/`, the extension's copy first when both carry a name; no index entry, so `workflows: []` -- every way of working. THE SPACE'S are the active Space's repository's own `agentic/*.prompt.md`, read as the Design tab reads `design/` -- one GraphQL call for the folder through `agent/ado/repo_read.py`'s `read_folder_rows`, the parsed rows kept on disk by blob sha ([the agent's cache](../CONFIGURATION.md#the-agents-cache)) so an unchanged prompt is never fetched again, and cached in memory per repo for the same TTL (a read gh refuses is logged and not cached); its text is read only by the one-prompt route, through `file_text` (a body kept on disk by its sha). A Space prompt whose text cannot be read is still listed, its row titled by its file name: it exists in the Space, and a reader should see it -- `workflows: []`, `changed` and `history` blank (the folder read carries no commit). And `space`: `{ slug, name, repo, isToolkit }` -- `repo` is `owner/name` when the gate passed, else `""`; `isToolkit` when that repository is this package's own `origin` (case ignored), in which case its folder is the shipped set already and there are no Space rows. And `categories`: `agentic/prompts.json`'s vocabulary in its order, the order the card's category row draws in (`[]` when the index is unreadable) | nothing |
| `GET /api/studio/prompts/{ref}` | none; a name outside `<name>.prompt.md` in the three places, or anything with a path in it, is **404**; a shipped prompt of an add-on that is off is **404** naming the add-on and its flag; `space/<name>` on a Space the gate does not pass, or on ToolKit itself, is **404**; so is a Space prompt whose body cannot be read, the failure logged | one prompt by its `ref`, the same fields | nothing |
| `GET /api/spaces/candidates` | none, and not tier-gated: these are the `gh` account's repositories, wanted most when the Space you are in is local | `NewSpace -Discover -AsJson` through the bridge, `?owner=` as its `-Owner`, `?repo=owner/name` as its `-Repo` (one repository, in place of an owner's list): `available`, `reason`, `account`, `owner` (whose list it is), `owners` (the selector's entries -- `value`, `label`, `kind` -- you, your organisations, then Collaborator; none for `?repo=`), `ceiling` (how many one list is read to, 1000), `more` (the list stopped there) and `repos` -- each `repo`, `owner`, `visibility`, `isArchived`, `viewerPermission`, `readOnly`, `description`, `proposedSlug`, `proposedName`, `space` when it already is one, and `note` when `gh` could not see a typed repository. Never refused: no `gh`, signed out, or a bridge that cannot run answers `available: false` with the sentence | nothing |

`thread_space` is the declared GitHub Space whose repos hold the thread's repo (matched without case), or
`""` -- it says which Space can read the thread for the reading room.

**There is no write route.** A new note, a promotion and a move along the road are the verbs through the bridge:

```text
POST /api/cmd/NewDesign   { "params": ["-Title", "Board ideas", "-Description", "What the board could show next"] }
POST /api/cmd/NewItem     { "params": ["-FromDesign", "board-ideas.md"] }
POST /api/cmd/MoveDesign  { "params": ["board-ideas.md", "-To", "Archive", "-Hub", "-Dropped", "-Reason", "The Lounge already does this"] }
POST /api/cmd/NewSpace    { "params": ["-Slug", "juggling-engine", "-Name", "Juggling Engine", "-Repo", "tester/juggling-engine"] }
POST /api/cmd/RetireSpace { "params": ["acme"] }
POST /api/cmd/RemoveSpace { "params": ["side-notes", "-WhatIf"] }    (the confirm's preview)
POST /api/cmd/RemoveSpace { "params": ["side-notes", "-Force"] }     (once the person has seen it)
```

**The foyer's GitHub rows are one read, `GET /api/studio/ledger`** (`consts.json` `studio.ledgerRoute`,
`agent/studio/ledger.py`), on one rule: list once, fetch a detail when it is asked for, cache the bytes. It
answers `spaces`, every declared GitHub Space by slug, each with `report`, `deploys` and `visibility` in exactly
the shapes `/api/issue-report`, `/api/deploys` and `/api/visibility` answer, so the row's words are unchanged:

- **One `gh api graphql` call for every repository**, one aliased `repository(owner:, name:)` each: its
  `visibility`, its open and closed issue counts, its open issues' labels and milestones (newest-created
  first, as `gh issue list` reads them) and its most recently updated closed issues' `closedAt` -- everything
  the report counts, and the same counts (`Tests/test_ledger.py` feeds both readers one backlog). Chunked at
  twenty repositories a call; a backlog past a hundred open issues reads its next pages, that repository only.
  The query travels in a file (`-F query=@<file>`) and every value as a `-f` field -- never in a URL, never
  an `&` (the Windows trap). A repository GitHub cannot resolve fails alone, with the report's own sentence.
- **The newest runs through `gh run list`, one per repository, in parallel**: GraphQL has no listing of a
  repository's workflow runs across branches, and the row's "last deploy" is the newest run anywhere.
- **No tier probe on the way.** The tier's inputs are the hub, git, the Space's status and whether the tracker
  answers -- and the GraphQL call is the tracker answering. A `local` or `archive` Space is `supported: false`
  with `gh` not asked, as before; only when the call does not answer at all is the tier probed the old way, so
  a signed-out `gh` still reads "not connected yet".
- **Kept on disk per Space** ([the agent's cache](../CONFIGURATION.md#the-agents-cache),
  `ledger-1/<slug>.json`) for 600 s -- the visibility cache's own TTL, read from it -- keyed by the Space's
  repositories and status, so a changed address is a miss. A foyer mounted twice in ten minutes, or after an
  agent restart, reads GitHub once; a Space whose read did not fully answer is not kept. `?refresh=1`, the
  card's Refresh, asks again -- and so does a verb that writes an issue (`NewItem`, `EditItem`, `CloseItem`,
  `Route` through the bridge), for the active Space only. **The pane's `GET /api/issue-report` reads this same entry**
  (`read_space_report`): warm, it makes no `gh` call; cold, it is one ledger read of its Space, and the foyer then
  finds that Space kept. The answer also seeds the visibility cache -- each repository's record, its visibility,
  `hasIssuesEnabled` and `url`, kept in the same file so a disk hit after a restart seeds it again -- so the
  shell's own `/api/visibility` read of the same Space, and the Docs tab, ask nothing.

For every other row the foyer reads the core's `GET /api/status` -- plain for the Space you are in (the
Board's own read), with its `space` argument for any other that is not archived. The three per-Space routes
the GitHub rows used to ask keep their `space` argument, for the pane and the CLI's `Dashboard`:

| Route | Gate | Reads | Writes |
| --- | --- | --- | --- |
| `GET /api/studio/ledger` (`consts.json` `studio.ledgerRoute`) | none -- core; each Space's tier decides whether its tracker is asked, as above. `?refresh=1` goes past the disk cache | one `gh api graphql` call per twenty repositories and one `gh run list` per repository, for every declared GitHub Space whose ledger is not on disk -- none when all are | the agent's cache only |
| `GET /api/issue-report?space=<slug>` | the named Space's tracker is GitHub and the ledger reads it (a `local`/`archive` Space, or a tracker that does not answer, is `supported: false`); an undeclared slug is **404** naming it. `?refresh=1` reads past the kept entry | **the ledger's report for that Space, no `gh` call of its own**: warm, nothing; cold, one ledger read of that Space (the same disk entry the foyer reads) | the agent's cache only, on a cold read |
| `GET /api/deploys?space=<slug>` | the same | `gh run list` per repo, newest first | nothing |
| `GET /api/visibility?space=<slug>` | the named Space's tracker is GitHub, else `supported: false` and no visibility; below Tier 1 `gh` is not asked and the answer is `unknown`; an undeclared slug is **404** | `gh api repos/{owner}/{repo}` -> `visibility`, once per repository, held 600 s in one record with the repository's `has_issues` and `url` (the Docs tab reads the same record) (an unanswered read is not held; `&refresh=1`, the Spaces card's Refresh, drops that Space's repositories' answers and the tier probe's, and asks again): `public`, `private` (gh's `INTERNAL` too) or `unknown` -- `consts.json` `visibility`. A Space of several repositories is `public` when any is, `private` when all are | nothing |
| `GET /api/status` | none -- the active Space's `current/` | the cards in play and their derived state | nothing |
| `GET /api/status?space=<slug>` | none beyond the plain route's: a folder read, no tracker, no tier; an undeclared slug is **404** naming it | that Space's own `<promptsFolder>/current/`, the same card model; its pinned flag is never asked (it is the active Space's tracker's) | nothing |

**The `space` argument is the one new seam** (the spec's trap 1). Absent, both routes read the active
Space exactly as they always did, so the pane is unchanged. Present, the address, status and projects are
taken from that Space's own entry in `spaces[]` -- the same three things the CLI's `Dashboard` reads off
the Space it reports on -- and the tier is probed for that Space. `space_scope()` in
`agent/ado/accounting.py` is the one place that resolves it; `/api/status` takes the Space's folder from the
same lookup (`space_entry()`, which `space_scope()` calls), so an unknown slug is the same 404 on all three.

**`GET /api/issue/{number}?space=<slug>`** is the same seam for a hub note's thread: the issue is read
through the named Space (its address, its repos with `?repo=`, its tier) rather than the active one.
Absent, the active Space's, as always.

**`GET /api/env`** says, for each offered Space in `config.spaces`, which tracker its address names
(`tracker`: `github`, `ado` or `none`, the D-G2 rule), and that Space's lane names as `laneNames` --
`{contract word: display name}`, resolved by `lane_names()` exactly as the active Space's `config.laneNames`
is. The foyer draws a row for every Space it offers, chooses a GitHub row's reads by
`tracker === "github"`, and derives nothing itself.

## The web UI

**Its own tab, `Studio`, at `/studio`**, always there: the nav entry after Growth's and Organize's
places and before Team Agile's and the Lounge's, laid out like any other tab: cards in the shell's grid
at half width.

**The foyer** is the **Spaces** card (titled **Products** until 2026-10-04 -- the word now names one
filter, not the list). One row per Space -- EVERY Space `/env` offers, whatever its tracker (D-S13) -- in
the order `/env` offers them, under one filter:

| The filter | What it is |
| --- | --- |
| The tags | an exposed row across the top of the list, under the header rule: **All \| Products \| Work \| Out of box \| Archive**, opening on **All**, each with its count (a tag whose bucket is empty shows no number) and the chosen one marked. The same `FilterBadge` row the **Reminders** card draws for All / Overdue / Today / Upcoming (the first cut, 2026-10-04, was a header `Select`; the owner, seeing the Reminders card, asked for the tags). The row wraps on a narrow card and keeps its height. No **Hidden** entry: hiding a Space is not built |
| The rule | one Space in exactly one entry besides All, the first that fits (`spaceBucket` in `foyer.ts`): `status: archive` is **Archive** (an archived GitHub Space too); `example: true` is **Out of box** (the shipped demos, the GitHub demo too); a GitHub tracker is **Products**; anything else -- Azure DevOps, or no tracker -- is **Work**. Every bucket is derived from fields the Space already has in `/env` |
| Honest | it lists only what matches -- **Archive** leaves out the Space you are in. Where you are is the nav's Space anchor, not this list |
| The count chip | in the header, the total number of Spaces whatever tag is chosen -- each tag carries its own count |
| Nothing matches | the list's place says so, naming the filter -- `No archived Spaces`, `No product Spaces`, `No work Spaces`, `No out-of-box Spaces` -- with how many are under All; the tag row, the header and the chip keep their boxes |
| Remembered | per browser (`localStorage`, key `studio.spaces.filter`, through `usePersistedValue`, which never throws). A browser that refuses storage, or a stored value the tags do not offer, opens on All. A convenience, not a setting: nothing goes through `Config` |

Each row:

| Part | What it is |
| --- | --- |
| Title | the Space's name; a badge with its kind -- `GitHub`, `Azure DevOps` or `Your own cards` (no tracker); `archived` on an archived Space; `you are here` on the one you are in |
| A GitHub row's line | led by its repository's visibility -- `Public;`, `Private;`, or `Visibility unknown;` when a connected Space's tracker did not answer, never a guess -- the word `shared/visibility.tsx` gives the agent's answer. A GitHub Space not connected yet (not `active`) is not asked and says nothing about it (`readsVisibility` in `foyer.ts`), and neither does an Azure DevOps row or one with no tracker. Then `foyer.ts`'s words: `no open issues` or `4 open`, then `2 closed this week` and `1 sev1 open` when there are any, then `; last deploy 3 days ago, green` (`red`, `cancelled`, `running`) or `; no deploys yet`. A Space whose tracker does not answer -- not connected, or `gh` signed out -- says what connecting would show: `not connected yet -- connect it, and this row shows its open issues and last deploy`. `gh`'s own sentence is shown when it refused |
| Any other row's line | its cards, counted in place: `3 cards in play: 2 Active, 1 Code Review`, under THAT Space's own lane names (`/env`'s `spaces[].laneNames`), or `no cards in play`. The Space you are in reads `/api/status` (the Board's cache); any other reads `/api/status?space=<slug>` -- one read per row, as a GitHub row's are. A read that fails says `Could not read this Space's cards -- the agent did not answer.` on that row only. An archived Space you are not in is not asked, and says `go in to see its cards`. Then, while its tracker cannot answer, what connecting would show: an Azure DevOps Space not yet `active`, `not connected yet -- connect it, and its board's work items come in beside its cards`; a Space with no address, `no tracker -- connect it to a GitHub repo and this row shows its open issues and last deploy`. An archived Space is not taught |
| The one exposed action | **Go into \<name>** -- the switch the avatar menu makes, then Home (on a GitHub Space its Issues). On the Space you are in it is **Open \<name>** and switches nothing. A failed switch says so in the row and changes nothing |
| `...` | **Connect \<name>** -- the connect wizard, `/connect/<slug>` -- on a Space that is neither `active` nor `archive`; then **Retire \<name>** on a Space that is not archived and **Remove \<name>** on any Space but the one you are in (`spaceLifecycleActions` in `foyer.ts`); then **Open on GitHub** or **Open in Azure DevOps**, the Space's address, when it has one, last |
| Retire, Remove | the house confirm (`shared/ConfirmDialog`, `SpaceLifecycleDialog.tsx`): **Are you sure?**, the act named in one sentence -- Retire: it stays a Space, archived, its cards kept and readable; Remove: it is no longer a Space, its folder and every card in it stay in the hub and adding a Space with that folder brings them back -- and under it the verb's own `-WhatIf` lines (`POST /api/cmd/RetireSpace` or `RemoveSpace` with `-WhatIf`): the keys that would go and the folder that stays, its cards counted. **Retire** or **Remove** cannot be pressed until those lines are in; a refused preview (the shipped Azure demo cannot be removed) is said in the verb's words and the button stays shut. Then the verb runs -- a Remove with `-Force`, the count having been shown -- the card says `Retired <Name>. It is under Archive, its cards kept.` or `Removed <Name>. Its folder and every card in it stay in the hub.`, and `/env` is read again. A refusal stays in the dialog. Never on the avatar menu's Space list |
| Empty | `No Spaces yet`, and under it the sentence that says what a Space is -- only when `/env` offers none at all |

**The card's foot +**, drawn as Hub Designs' is (`CreateButton`, named **New Space**), opens the
**New Space** dialog -- the same Fluent dialog the New Design Note uses, its title with a dismiss, Cancel
and the primary action:

| Part | What it is |
| --- | --- |
| What it is | two radios: **A GitHub repository** (first) and **My own cards, no tracker** |
| The repository area | ONE box of fixed height, whatever it holds, so nothing below it moves. At its top, when the verb names owners, an **Owner** selector -- you, your organisations, then **Collaborator** (the repositories shared with you) -- whose choice is `GET /api/spaces/candidates?owner=`; it stays over the spinner and the typed field too. While the list reads, a spinner; then a search box and the repositories as radios -- name, owner, a **Public**/**Private** badge and, for a repository GitHub has archived, an **Archived** one (same outline `subtle` grammar; archived repositories sort last, still addable), and a **Read-only** one where you can read it and not write to it (still addable) -- with the ones already Spaces disabled and marked `already a Space: <name>`. A search that reads as a full `owner/name` (or a pasted GitHub address) and matches nothing listed adds one row, **Add owner/name**, chosen like any other: its proposal is the mirror's. Once the search has rested on it for 400 ms -- one read for a name typed letter by letter -- the row reads that repository, `GET /api/spaces/candidates?repo=`, and says `reading its visibility...` meanwhile; then its **Public**/**Private** badge and **Archived**/**Read-only** chips as a listed row's, `already a Space: <name>` and disabled when it is one, or -- when the `gh` login cannot see it -- **Visibility unknown** and the verb's note, `not visible to this login: gh answered '...' -- it can still be added`. A read that cannot run (the agent, or `gh` signed out) leaves the row addable and says Public or Private is checked when it is added. When the verb says a list stopped at its ceiling (`more`), a note under the list: `The first 1000 are listed. For one past them, type its owner/name in the search.` When `gh` cannot list (absent, signed out, or the agent did not answer) or lists nothing, the same box says why, in the verb's sentence, and offers a plain **Repository** field for `owner/name` (a pasted `https://github.com/...` reads the same). For own cards, a line saying what that is |
| Name and Slug | shown once something is chosen, editable: a listed repository's proposal is the verb's own (`proposedName`, `proposedSlug`); a typed one's and own cards' come from `newSpace.ts`, the mirror held to the verb by `Tests/fixtures/spaces/proposals.json`. For own cards the slug follows the name until you change it. A slug that is not one, or that a Space already has, says so under the field and Add is not offered |
| Add | `POST /api/cmd/NewSpace` with exactly the slug, name and repository shown. Success closes the dialog, the card says `Added <Name>. Its row is in the list; go into it from there.`, and `/env` is read again, so the row is there without a reload. A refusal stays in the dialog, in the verb's words |

One Space per dialog. It does not switch you into the new Space -- its row is the way in.

**How the card loads, refreshes and pages**:

| Part | What it is |
| --- | --- |
| One clean load | every Space's reads -- the one ledger read for every GitHub row, cards for any other -- start at once, for EVERY Space, not just the page you see: they run in parallel, so the first draw costs the slowest row, and a page or filter change never lands on a row that has not been read. Until every row's reads have settled -- answered or failed -- the card shows its own loading state, `Reading the Spaces...`; then it draws the whole list once. No row ever shows a placeholder line, and a failed read still says so on that row only. No timeout. Once drawn, the card never falls back to loading; a Space added later (the **+**) joins the list when its own reads are in |
| Refresh | the shared `RefreshButton`, in the header's right slot, left of the count chip -- where the Environment card has it. It reads every row again: `GET /api/studio/ledger?refresh=1` once for every GitHub Space, past the agent's disk cache (its visibility answers also go into the shell's visibility entry for each Space), and `/api/status` per cards row. The list stays drawn while it reads; the button spins and is disabled |
| Cached for the session | the reads are kept in the store for the session (`SESSION_CACHE` in `shell/api.ts`): a remount, a focus or the clock re-reads nothing -- only Refresh does, or a write that invalidates `Status` (a card moved) or `Env` (a Space added, retired or removed: the ledger is asked again, and the agent reads only the Space it has not kept). The first mount of a session, or a reload, is the agent's disk cache's to answer |
| Paging | five rows a page (`STUDIO_PAGE_SIZE` in `paths.ts`, the one constant all three Studio cards read), the shared `Pagination` in the foot's centre slot, as the Reminders card has it. The filter applies first and the pager pages what it leaves; choosing a tag returns to page 1; the header chip stays the total; the **+** stays in the foot's right slot. One page draws no pager, as on Reminders |

The foyer asks nothing, and stores nothing but the filter's choice in this browser. A populated card carries no helper sentence:
the title, the tags -- `All` and its count already say "these are all your Spaces" -- and the rows
say it, and the foot carries the **+** alone. The empty card is the one place the definition is written: `No Spaces yet`, the sentence "A Space is where you work on one piece of software: your cards on a board, and the tracker's issues, designs and stats beside them once it is connected." under it, and the **+**.

**The Hub Designs** card, under the foyer: the hub's `design/` notes, the house row each. Its header
says what the column is, with a notebook glyph unlike the trackers' marks and the issue icon (the empty
state draws the same one), and its footer says whose they are: `Your private files. Notes that belong to
no product yet.` It reads on open and on its refresh button, like every card. Since the design lifecycle's
reader (L2) the hub keeps the same four folders a product does -- `design/`, `design/archive/`,
`spec/`, `spec/archive/` -- and the card draws **the same groups the Design tab draws**: one list by state in
road order (Design, Spec, Complete, Archived), Complete and Archived collapsed to a count until opened, a row
the design with its state badge and short id, an archived note under Archived with its Closed date and
outcome, and one line under the list counting the files that carry no id, naming `StampDesign -Hub` and
linking **Learn more** to the contract. The grouping is `web/src/modules/ado/DesignGroups.tsx`, drawn once
for both. A note leaves `design/` through the move verb (L3); Promote opens its thread.

| Part | What it is |
| --- | --- |
| A row | the title, and after it the **Space chip** when the note names a Space; the description under it; the state badge (`Design`, `Spec`, `Complete`, `Archived`), the short id (the whole id as its tooltip), the file name and its thread (`#N`) or `no thread yet` on a live note; `Closed <date>` and `shipped` / `dropped` on an archived one, `Docs: <path>` on a Complete one; a sentence under the row when its two files disagree about where the design is; and under it **the cards worked against it** -- `N cards`, then each card's id and state, a click opening the card when it is in the Space you are in and not archived, another Space's card named with its Space in brackets (`web/src/modules/ado/DesignBindings.tsx`, shared with the Design tab's rows). A card names its design with `{cliPrefix}NewPrompt -Design` |
| The Space chip | a note's `space`, drawn as a small button by the Space's name from `/env` (the slug when it has none; the slug is its tooltip), named **Switch to `<Space>`**. It is the foyer row's switch, through the one hook `useEnterSpace.ts`: the avatar menu's switch, then `/`; on the Space you are in it only goes home. No confirmation, as the foyer has none. A failed switch says `Could not switch to <Space>. Nothing changed.` in the row. A note with no Space has no chip and nothing in its place |
| The one exposed action | **Open the note** -- its reading room, `/studio/design/<name>`; an archived note or a spec by its hub path, `/studio/design/design/archive/<name>`, `/studio/design/spec/<name>`; a spec standing alone **Open the spec** |
| Search (L2b) | a box in the header, remembered per browser and kept across a Space switch (the hub is the engineer's): the Design tab's rule -- title, description and id, every word, any order -- narrowing the groups, opening the archive when it matches, the chip counting what is shown, and `No design matches the search.` when nothing does, beside the not-shown line, which stays. With words in the box, **Search inside** runs them over the hub's files on disk (`GET /api/studio/design/search`) on the button only: **Matches inside** above the groups, each hit the design, its state and the matching line, **Open** by its hub path, **Clear** to take the section away, and the note under it saying what was searched |
| `...` | **Open the spec** when the design has one beside its note; the moves the row's road offers (L3): a live note alone **Graduate to a spec**, **Archive as shipped** and **Drop**, a design whose spec is live **Complete**, an archived design none -- each a dialog in the New Design Note's grammar asking only what the road needs (a drop its reason, a completion the docs path), then `MoveDesign -Hub` through the bridge, the refusal kept in the dialog in the verb's words and success said in the card; then **Open the thread on GitHub**, when it has one |
| Paging | five designs a page (`STUDIO_PAGE_SIZE`), the shared `Pagination` in the foot's centre slot, drawn only past one page; the search applies first, the designs then run in the groups' order (Design, Spec, Complete, Archived) and the pager pages that list, so a group continues onto the next page under its heading. A group's count is the whole list's, not the page's. Changing the search returns to page 1; the header chip stays the total; the **+** stays in the foot's right slot. Rows of a collapsed group count toward the pages |
| Footer **+** | **New Design Note**: a title, a sentence, and optionally the Space it is for -- `NewDesign` through the bridge. A refusal stays in the dialog in the verb's words |
| Empty | `No design notes yet` -- your private notes live in the hub's `design/` until they belong to a product. Files with no id and no designs: no empty state, the counted line under the list says why |
| No folder | `No design/ folder yet` -- the agent answered `exists: false`: a hub copied out with none (one an older `Start` copied out; the sample hub carries the four folders). Not a fault and not drawn as one; the **+** writes the first note and makes the folder |

**A note's reading room** is the house's reading page: the back arrow and the title, the `design note`
badge, the Space it is for and its sentence, and ONE `MarkdownViewer` (the frontmatter is not drawn).
Its links go through the one resolver, `shared/docLinks.ts`, with a base of its own (`noteLinks.ts`): a
relative link to a sibling note opens that note's room; anything else is left as written, because a hub
note has no github.com page to fall back on.

**It is a document with a thread.** When the note has a `> GitHub:` line, the header carries the
thread's link (**The thread, #N on GitHub**), and when a declared GitHub Space's repos hold that issue
(the agent's `thread_space`), the thread is READ and follows the note in the same viewer -- `## The
thread: [#N ...]`, the issue's body, its comments and its timeline, drawn exactly as the issue's own
reading room draws them -- so one zoom and one "On this page" cover both. It is read through THAT
Space (`GET /api/issue/{n}?repo=<repo>&space=<slug>`), whichever Space you are in. A thread no declared
Space can read, or one `gh` could not answer for, is linked and not drawn; the note reads as itself.
The composing is written once, `web/src/modules/ado/documentWithThread.ts`, and the Design tab's room
(a repo's `design/` and `spec/`) composes through it too: there is no second viewer and no second
link resolver.

**Promote** is the room's one action while the note has no thread: the header's **Promote** asks first
-- "Open an issue in \<the Space you are in>, labelled design: its title ..., its body the note. The
issue's URL is written back into the note as its thread, and review happens there." -- and runs
`NewItem -FromDesign <name>` through the bridge. Done, the room says the verb's own line and re-reads the
note, which now has its thread. A refusal stays in the dialog in the verb's words. Promote is shown and
explained, never hidden, when it cannot run: on an Azure DevOps or local Space ("a design's thread is a
GitHub issue -- switch to a GitHub Space first"), and on a note for another Space ("this note is for
Toolkit -- switch to it first") -- `promoteBlocked` in `DesignNotePage.tsx`, the verb's own two rules
said before the click. A promoted note has no Promote, only its thread.

**The Prompts** card, beside Hub Designs: the agentic prompts. They are ToolKit's (the package's
`agentic/`) and the hub's (its `agentic/`, and `agenticExtensionPath`), the same on every Space, so they
live in the Studio rather than on one Space's tabs -- for the reason Hub Designs does -- and the active
Space's own, its repository's `agentic/`. Three filters, the house's `FilterBadge` radios the Spaces card
and the Dashboard use -- **ToolKit**, **Your hub**, and the Space's name -- with a category row under
them, each row the house row:

| Part | What it is |
| --- | --- |
| The filter row | three radios, each with its count (a zero draws no number): **ToolKit**, **Your hub**, and **\<Space name\>** -- the third ONLY when the agent's `space` names a repository that is not this package's own origin (`repo` set, `isToolkit: false`; the card decides nothing). ToolKit is active on open; the header chip is the shown count (this row and the category row together); the pager runs over the shown rows; a filter change starts at its first page. Switching Space changes the row with it: a chosen third on a Space that has none reads as ToolKit |
| The category row | under the filter row, the same `FilterBadge` radios: **All** (the source's count), then each category that has at least one prompt in the ACTIVE source, with its count -- the index's vocabulary first, in its order (the agent serves it as the response's `categories`), then any outside it in alphabetical order: a prompt of yours or the Space's that names its own category is drawn as written, and `uncategorized` is one of these. A category with no prompt in the active source is not drawn. The two rows compose -- source AND category -- and the header chip and the pager follow the result; a category change starts at the first page. A choice the active source has no prompt in reads as **All**, the way a stale third filter reads as ToolKit. With no prompt in the source the row is **All** alone, so nothing under it moves. Up to `CATEGORY_TABS_MAX` (`prompts.ts`, eight) categories are tabs; past it the row is meant to become a dropdown, which is not built -- `PromptsCard.test.tsx` fails when `agentic/prompts.json`'s vocabulary outgrows it. An older agent that serves no `categories` draws every category alphabetically |
| A row | ONE record, the same wherever the prompt lives, and nothing else: its **title**, which opens the reading room; its **purpose** under it (the frontmatter's `description`, no line when it has none); then two badges -- its **owner**, in the filter row's words (`ToolKit`, `Your hub`, or the Space's name), and its **category** (`ship`, `review`, `tracker`, `growth`, `meetings`, `rituals`, `design` -- `agentic/README.md`, "The shape of a prompt" -- or whatever a prompt of yours names, `uncategorized` when it names none). Who sends it, its add-on, its ways of working, what it drives, where it lives, when it changed and whether a copy of yours runs instead are the reading room's |
| The one exposed action | **Copy reference** -- the `@` form of the file's path, to paste into an assistant's chat that can read the disk, so it reads the current file: `@agentic/<name>.prompt.md` for ToolKit's (relative to the checkout the chat is open in) and for the Space's (relative to a checkout of its repository, where a chat open there resolves it), `@` plus the absolute path for the hub's (the hub is never inside either tree). Built at the click from the row's `path` and `file_path`, never stored; the card says `Copied the reference to <name>.` |
| `...` | **Copy prompt** (the whole file, for a chat that cannot read the disk -- read through the one-prompt route when clicked, since the list carries no text; the card says `Reading <name>...` while it waits, `Copied <name>.` after, and an error if the read fails), **Open the prompt** (the reading room), then **Its history on GitHub**, the external link last |
| ToolKit, by how you work | only the prompts whose `workflows` (`agentic/prompts.json`) hold the Space's answer to **How do you want to work?** -- `/env`'s `howIWork.answer`, which the agent works out (`how_i_work()`) and the card reads in one place, `spaceWorkflow` in `prompts.ts`: an Azure DevOps Space is `team`, your own cards `alone`, a GitHub Space what it was answered (`alone` until it is). Team Agile's switch does not enter into it. The words are the question's answers in `Config/settings-workflows.json`: `with agents`, `alone`, `on a team in Azure`. None: `None for working <answer>`, with the others line under it. The others are counted in the info tip (`2 more of ToolKit's prompts are for another way of working: ...`), never shown |
| Your hub | every one, whatever the answer -- they carry no index entry. None: `None yet` -- `A <name>.prompt.md in your hub's agentic/ folder is listed here.` |
| The Space's | every `agentic/*.prompt.md` in its repository, whatever the answer, as the agent read them (`group: space`). None: `None in <owner/repo>` -- `A <name>.prompt.md in an agentic/ folder in that repository is listed here.` |
| The info tip | `InfoRegular` in a Fluent `Tooltip`, `relationship="description"`, in the header beside the title -- the shared `InfoTip` (`web/src/shared/InfoTip.tsx`), the shape the Create page's sections draw. It reads the same `promptSets` the list does: `ToolKit's are what the product tells a model: the <n> for working <answer> here.`, the others line when any, `Your hub's are yours, on every machine.`, with a third filter `<Space name>'s are its repository's own: agentic/ in <owner/repo>.`, and `The row under them narrows any of these to one category.` There is no footer sentence and no line under the list |
| Paging | five rows a page (`STUDIO_PAGE_SIZE`), the shared `Pagination` in the foot's centre slot, drawn only past one page, over the shown rows -- the source and the category together |
| An add-on's prompts | absent while the add-on is off (the agent leaves them out): `generate-review` and the two growth prompts with growth, `manager1on1` with communication |

**A prompt's reading room**, `/studio/prompts/<name>` (one of yours `/studio/prompts/yours/<name>`, one of the
Space's `/studio/prompts/space/<name>`), is the house's reading page and holds the detail the row does not:
the back arrow and the title, badges for whose it is (`ToolKit's`, `yours`, `the Space's`), its category and
who sends it (`by hand`, or `sent by ToolKit: <verb or route>` -- `pr-review`'s `AddPRReview`, `pr-suggest`'s
Suggest route), its add-on when not core, the ways of working it is for, what it drives, when it changed
(linked to its history on GitHub when the agent has one; the Space's carry neither), `runs instead of
ToolKit's on this machine` for a copy of yours in `agenticExtensionPath` under a shipped name, the file's address with its copy button (`FilePath` -- for the Space's, the
file's address on GitHub), and ONE `MarkdownViewer` over the whole file. Its header's action is **Copy
prompt**. It is read-only: a prompt is changed in its file. A name the agent does not know says so in the
agent's words.

## The file shape, and how a note is read

[`docs/hub/design.md`](../hub/design.md) is the contract. In short: one note is one file,
`design/<slug>.md`, flat -- a note leaves the drawer by a commit into its product's repo (D-S10), not by
a verb. YAML frontmatter with `description` and, when it names one, `space`; an H1 title; a
`> GitHub: <issue url>` line once it has a thread; the template's headings; `**Created:**`.

**How it is read** -- `read_note` in `agent/studio/notes.py`, through the same `parse_doc` the Design
tab reads a repo's documents with:

| Field | Rule |
| --- | --- |
| title | the first `#` heading after the frontmatter; none, the file name |
| description | the frontmatter's `description:`, quotes stripped; none, `""` |
| space | the frontmatter's `space:`; none, `""` |
| thread | the first line matching `consts.json` `studio.threadRegex`; none, not promoted. Promote writes it, under the title |

A note's only state is whether it has a thread. Nothing is stored about it outside the file.

## The tests

| Suite | Holds |
| --- | --- |
| `Tests/test_studio.py` | `space_scope`: no argument is the active Space; a slug is that Space's own address, status and projects; an undeclared slug is a 404 naming it. The routes asked about a Space you are not in: `/deploys` reads the named Space's repo with its tier probed (`/issue-report` is `test_ledger.py`'s: a `local` Space is `supported: false` with `gh` never asked); an ADO Space is `supported: false` with `gh` never asked; below Tier 1 likewise. `/env`'s spaces each carry their tracker, and their own lane names by contract word. `GET /api/status?space=<slug>`: another Space's cards from its own folder with no tracker asked; no argument, and the active Space named, the active Space's as before; a Space with no cards empty; an undeclared slug 404 naming it. The seed drawer's routes over a scratch copy of the fixture hub: every field, a file that is not a note skipped, no folder answering empty with `exists: false`, a name outside the rule 404, the folder renamed through `hub.json`, the thread-Space rule, and a leftover `features.studio` -- true or false -- changing nothing (D-S13). A hub note's thread read through the Space that holds it, with the active Space an ADO one; no `space`, the active Space's as before. **`NewDesign` typed as a verb** in a fresh `pwsh` with only this package's module (when `pwsh` is on the machine): both verbs resolve, `Menu -All` lists them, `-Help` answers and the bridge has them with no features block and with a leftover `features.studio` of either value; the autoload manifest names both and the studio data file is gone; `Config -Set features.studio=` refused with exit 2, one `Error:`, nothing written; the file from the template, no BOM, LF, the name the contract allows; it never overwrites; `-Space` written and an undeclared one refused; the refusals stated with exit 2; and the agent reading back what the verb wrote, now including the `id:` its frontmatter opens with. **Promote typed as the verb**, `gh` stubbed as a function that writes down every call: one `gh issue create` with the Space's repo, the note's title, the note's body without its frontmatter or title, and the `design` label; the thread line written back under the title, the frontmatter kept, and the agent reading it as the note's thread; a CRLF note kept CRLF; `-ReadOnly` creating and writing nothing; five refusals (promoted, another Space's, no such note, not a note's name, a title beside it) and an ADO Space (D-S9), each exit 2 with nothing created or written |
| `Tests/test_ledger.py` | **The Spaces card's ledger.** One GraphQL call whatever the number of Spaces (1, 3, 8), one more past twenty repositories, a repository two Spaces share asked once, no tier probe when the call answers; a second read inside the TTL, and an agent restart, make no `gh` call; Refresh, an expired entry and a changed address do, the last for that Space only; a read that did not answer is not kept; `local`, `archive`, no hub and a signed-out `gh` are `supported: false`, and a failed call with the tracker there says why; the report equals `_github_issue_report`'s over one backlog (severities, both kind labels, tied milestones, closed this week); a backlog past a page reads its next one; visibility in the contract's words, seeding the visibility cache's one record per repository (visibility, `has_issues`, `url`), again from disk after a restart and at the age it was read, and the REST read filling the same record; no argv a shell would split; the route answering twice with one read; `GET /api/issue-report` from the ledger's entry (no `gh` call warm, one read of that Space cold, then warm for the foyer too, `?refresh=1` reads again, the same report the old route answered over one backlog, the active Space with no argument, a `local` Space unsupported) and a bridge `CloseItem` (not `NewPrompt`) dropping only the active Space's entry |
| `tkTestToolkit -Consts`, `Tests/test_consts.py`, `web/src/shell/consts.test.ts` | the `studio` values, stated from all three halves; the thread pattern never retyped in the agent |
| `tkTestToolkit -HubJson`, `Tests/test_hub_json.py` | `design` is a hub-root folder, and the CLI's and the agent's folder tables agree key for key |
| `Tests/test_stamp_design.py` | **`StampDesign` typed as a verb** in a fresh `pwsh` with only this package's module, in a scratch repository and a scratch hub (when `pwsh` is on the machine): the bridge can call it; `-WhatIf` names all eight files that need an id and writes nothing (bytes and mtimes); the stamp -- an id first in an existing block, a block made where there is none, a spec taking its note's id by stem (a new id and one already there), the archives walked, `README.md` skipped, an id already present byte-identical; a CRLF file stays CRLF on every line and nothing gains a BOM; a second run writes nothing; a pair that disagrees is left alone; the refusals (no repository, no `design/`, `-Hub` with no folders) exit 2 with one `Error:`; `-Hub` stamps the hub root and a declared Space's own folders and no other hub-root folder, and not the repository |
| `web`: `DesignsCard.test.tsx` | the pager (six designs draw it and page 2 shows the sixth, five draw none, the search paging what it leaves and returning to page 1); the header and footer words; the list's rows; the Space chip -- shown only on a note that names a Space, by the Space's display name or its slug, switching on click and landing on `/`, only going home on the Space you are in, and a failed switch said in the row; a row opens its room; the empty drawer; a hub with no `design/` folder said as such, not as a fault; the + sends exactly what was given through `NewDesign`; a refusal stays in the dialog; `buildNewDesignParams`; the reading room and its 404; the document with its thread -- the note first, then the issue and its comments, read through `thread_space`; a thread no Space can read linked and not read; an unreadable thread leaving the note alone; a note's links through the one resolver; Promote's rules as a table (`promoteBlocked`), its argv, the dialog saying what it will do, the bridge call, a refusal kept in the dialog, and no Promote on a promoted note |
| `web`: `foyer.test.ts` | the filter's rule as a table -- one row per kind of Space (a GitHub Space connected and local, an archived GitHub Space is Archive, an archived example is Archive, a local GitHub example is Out of box, `example: false`, ADO, ADO archived, no tracker, an older agent) -- each entry's Spaces in order, the five entries with no Hidden, which stored values are offered, and each empty sentence; the row's words as tables: which Spaces get a row (every one; only `github` reads the tracker; the kind word; nothing re-derived), the issues half (a tracker that does not answer says what connecting shows), the deploy half, the spec's own example line, the cards half (by lane, under the Space's lane names), which non-GitHub rows read their cards (here always, elsewhere unless archived) and a non-GitHub row's whole line (read or not, connected or not, archived, another Space's lane names, an older agent); which rows ask their visibility (a connected GitHub Space only -- not one not connected yet, not archived, not ADO or no tracker), a row not asked leading with nothing, and the one page size, five (`STUDIO_PAGE_SIZE`) |
| `web`: `FoyerCard.test.tsx` | a row for every Space, ADO included; the tracker read only for GitHub rows, each with its own slug; another Space's row counting its cards by its slug under its own lane names, the Space you are in reading the plain `/api/status`, an archived Space you are not in not asked, a failed read said on that row only; a cold first run's three demo Spaces with nothing reading as an error; **Connect** opening the wizard; a row switches and lands on `/`; the Space you are in goes home without a switch; a failed switch says so; only an ADO Space is not an empty room; no Space at all says `No Spaces yet` and what a Space is. The filter: titled Spaces, opening on All with the five tags, each with its count; Products lists the GitHub Spaces and the chip stays the total; Archive leaves out the Space you are in; an empty filter's sentence under the tags, an empty bucket's tag with no number, the tags and chip still there; the choice remembered across a remount; a stored value it does not offer reads as All; a browser that refuses storage still filters. The load, Refresh and pager: the loading state held until every read settles -- an issues, a visibility and another Space's cards read each hold it -- then the whole list; a failed read settles too; no placeholder line ever; Refresh in the header before the chip, reading every row again (visibility through the refresh path) with the list kept drawn and the button busy; five a page with the pager at the foot, the chip the total and the + kept; the filter first and a new tag back to page 1; one page, no pager; a GitHub Space not connected neither asked nor worded, a connected one that did not answer still `Visibility unknown` |
| `Tests/test_new_space.py`, `tkTestToolkit -NewSpace` | **`NewSpace` typed as a verb** in a fresh `pwsh` against a scratch package and hub, `gh` a stand-in function or taken off the PATH: in the command table and the manifest; each form (a repository named from its name, a pasted address, `<slug> -Address` naming the next step, own cards local); every key in `hub.json` through `Config`; the folder made, or adopted with nothing in it changed and its cards counted; no switch, the last line the `SwitchSpace`; `-WhatIf` writing nothing; each refusal exit 2 with one `Error:` and nothing written; without `gh` added and "not checked"; a failed check added anyway; `-Discover` marking the Spaces, and without `gh` saying why; `-Discover -Owner` -- the owners offered (a two- and a one-organisation answer, item by item), an organisation's repositories through `gh repo list <owner>`, the ones shared with you through `gh api user/repos` with the affiliation an `-f` field and no `&` in any argument, `READ-ONLY` marked from `viewerPermission` or REST `permissions`, an owner `gh` cannot see refused exit 2 with one `Error:` and one `Hint:` (and in `-AsJson` `available: false` with the owners kept), and the same lists read by Windows PowerShell 5.1 where it is on the machine; `-Repo` reading the permission with the visibility; the proposals over the shared table, through `-Repo -WhatIf` and through `-Discover -Repo`; `-Discover -Repo` one row through `gh repo view` with no owners asked, a repository the stand-in cannot see a row with `UNKNOWN` and `not visible to this login` (and the Add saying the same, not "not checked"), already a Space marked, `-Repo` with `-Owner` and a `-Repo` that is not `owner/name` refused; paging -- 250 of an owner's listed whole with `--limit 1001` asked, 1200 cut to the first 1000 with `more` said (in the terminal too), 250 shared with you read in three pages each an `-f` field with no `&`, 1250 cut to 1000 after eleven pages -- and 5.1 reading a page list and a stderr `-Discover -Repo`. And `GET /api/spaces/candidates` with the bridge stubbed: the verb's argv, its rows, its own real answer (a list, and a typed repository `gh` cannot see), `?owner=` sent as `-Owner` with `owners` and `readOnly` served, `?repo=` sent as `-Repo` in place of `-Owner` with its `note`, `ceiling` and `more` served (0 and false from an older verb), `gh` absent, a bridge that cannot run -- never an error -- and no POST |
| `tkTestToolkit -NewSpace` (its retire-and-remove section), `tkTestToolkit -Config` (the whole-Space `-Unset`) | **`RetireSpace` and `RemoveSpace` typed as verbs** in the same scratch package and hub: in the command table and the manifest, `-Help` from config; Retire's `-WhatIf` writing nothing, then `status: archive` in `hub.json` through `Config`, still declared with its address, the line that brings it back named, a second run said and nothing written, a status this machine overrides unset with it; Remove's `-WhatIf` naming the key and the folder with its cards counted and writing nothing; cards in `current/` and a caller that cannot answer refused without `-Force`, one `Error:`, nothing written; `-Force` taking the entry out of `hub.json` with **every card in the folder byte-for-byte as it was**, the folder and count said and the `NewSpace` line named -- and that line adopting the three cards back; this machine's patch going with it; every refusal (no slug, undeclared, the Space you are in, the shipped Azure demo) exit 2 with one `Error:` and nothing written. `Config -Unset spaces.<slug> -Hub`: the entry gone, the others and the folder untouched; `-Unset spaces.<slug>` the local patch; an undeclared slug nothing to remove; a shipped Space and the Space you are in refused |
| `web`: `SpaceLifecycleDialog.test.tsx`, `FoyerCard.test.tsx` (the row menu), `foyer.test.ts` (`spaceLifecycleActions`) | a row's `...` offering Retire and Remove with the external link last; Retire not on an archived Space, Remove not on the one you are in; Remove opening the house confirm with the verb's `-WhatIf`, asked once. The confirm: the preview shown before Submit can be pressed, a Remove then run with `-Force` and a Retire with the slug alone, each said on the card; a refused preview said in the verb's words with Submit shut and Cancel working; a refused run kept in the dialog; closed, nothing asked |
| `web`: `NewSpaceDialog.test.tsx`, `newSpace.test.ts` | the + named **New Space**, asking for nothing until pressed; the picker -- owner, Public/Private, an Archived chip with archived repositories last, the Spaces disabled and marked; the Owner selector asking for the chosen owner, kept when an owner's list cannot be read, absent when the agent names none; a Read-only chip, still addable; a full `owner/name` typed into the search as an **Add owner/name** row, and a listed one found instead; that row's own read -- asked once the search rests, not once a letter, and its Public and Read-only said; a repository `gh` cannot see as Visibility unknown with the verb's note, still addable; one already a Space disabled and marked; a read that cannot answer leaving the row addable -- and the note when a list stopped at its ceiling; search; the proposal shown and editable and exactly that sent; success closing, said, and the new row in the list without a reload; a refusal kept in the dialog in the verb's words; the typed `owner/name` when `gh` cannot list and when the agent does not answer; own cards with the slug following the name; a slug the verb would refuse not offered, and why; the repository area one box. The mirror over `Tests/fixtures/spaces/proposals.json`, a pasted address, and `buildNewSpaceParams` |
| `web`: `registry.studio.test.tsx` | core: no flag, mounted whatever `/env` says (a leftover `features.studio` included), its own tab and no card elsewhere, before Team Agile and the Lounge; every registry test mocks every module |
| `Tests/test_studio_prompts.py`, `Tests/test_agentic_index.py` | **The Prompts card's agent half.** Every core prompt listed with the index's marks; the two the tools send not by hand; a row carrying the whole file and its description; an add-on's prompts absent while it is off and its read a 404 naming it, listed when on; a name outside the folder a 404; the hub's `agentic/` listed as yours for every way of working, a non-prompt file skipped, no folder the shipped set alone; an extension folder's copy under a shipped name `overrides` and wins over the hub's; last changed from git in a scratch clone -- a GitHub origin linking the file's history, another origin a day and no link, no clone nothing. The Space's folder through a stubbed `gh` (the `test_design.py` stub shape): listed as `space` with the response naming the Space, a non-prompt file skipped, the reads through `gh api` contents, one of them by `space/<name>`; ToolKit on itself serving `isToolkit` (case ignored) and no space rows with gh never asked; a Space with no folder none and no error; the folder read once for the TTL and a failed read not kept; below Tier 1 or an owner-grained address no repo and no refusal; an Azure Space no repo, active or not. Every shipped row's title and purpose line read from its header. One record on every row from one fixture -- a shipped, two of the hub's and two of the Space's: title (the frontmatter's over the heading, else the file name), purpose, owner (`toolkit`, `yours`, the Space's slug) and category (the index's, the frontmatter's lowercased, `uncategorized`), and the same on a read of one; the response's `categories`, the index's vocabulary in its order. The index held to the folder and to the How do you want to work? answers in `Config/settings-workflows.json`; every prompt to the one header shape (`agentic/README.md`, "The shape of a prompt") and to carrying no history; every entry to a `category` from the index's `categories`, which `agentic/README.md`'s table lists exactly |
| `web`: `PromptsCard.test.tsx`, `scenarios.test.tsx` (the Prompts card, by how you work) | the three radios with their counts, ToolKit active, the chip the active filter's count; each filter's rows (ToolKit's by how you work, the others not shown; every one of yours; every one of the Space's, its Copy reference the `@` path and its room `space/<name>`); the third absent for ToolKit on itself, for a Space with no repository and for an older agent; a stale choice of the third reading as ToolKit; each filter's own empty state; the info tip's words from the same sets, and no Space line without a third filter; the footer and the others line gone; the pager over the active filter's rows, a filter change starting at its first page; the category row -- All and each category in the active source with its count, the vocabulary's order then the rest, a free-form category drawn as written, no badge for an empty one, composition with the source row (the chip the shown count, the source row's counts the source's), a choice the new source lacks reading as All, the pager over the composed result, All alone on an empty source, an older agent's alphabetical order, the tip's sentence, and the shipped vocabulary held under `CATEGORY_TABS_MAX` (six rows draw it and page 2 shows the sixth, five draw none); the Space's answer read from `/env`'s `howIWork`, Team Agile's switch not deciding it, no answer read as `alone`, the drawer's words; the three sets and the others line; each row showing title, purpose, owner and category and nothing else -- none of the index's other fields, no path, no day -- with one exposed action; the owner in the filter row's words; Copy reference copying the `@` path (relative for ToolKit's and the Space's, absolute for the hub's) and Copy prompt in the menu reading the body on click (and only then) and copying the whole file, or saying so when the read fails; the name opening the reading room; an agent that did not answer draws no radios; the room reading by its ref, `yours/<name>` and `space/<name>` included, its Copy, the detail the row left -- category, sender, add-on, what it drives, the day linked to its history, `runs instead` -- and a 404 in the agent's words. The grid over the REAL `agentic/prompts.json` reads the ToolKit filter |
| `web`: `scenarios.test.tsx`, `lazyModules.test.ts` | the grid's core row with the Studio in it; the Spaces card's filter by kind of Space, each kind listed under All and its one entry only; the descriptor imports no component (lazy is about bytes) |
| `web`: the smoke (`npm run smoke`) | off mode: the Studio's nav entry is there with every module off, and no Studio page source is fetched before `/studio` is opened |
| `web`: the smoke's `--studio` mode (`npm run smoke:studio`) | on servers it starts itself over `Tests/fixtures/hub-spaces` (one Space of each kind, and a seed `config.local.json` with a leftover `"features": { "studio": false }`): the Studio tab and the Spaces card there regardless; a module flag set true then false through `PUT /api/config` under the running agent, its nav entry on the next reload and gone on the one after, the leftover line untouched by the writer; the Spaces card's tag counts and the chip's total, each filter's rows, the tags and the header holding their bounding boxes through every filter, the choice kept after a reload, and a new browser context opening on All. Not covered: the New Space dialog in a browser (it needs a `gh` stand-in) |
| `tkTestToolkit -Design`, `Tests/test_design.py` (`TheStateRule`, `TheGrouping`), `Tests/test_studio.py` (the four folders) | **The design lifecycle's reader (L2).** The state rule over the ONE table, `Tests/fixtures/design/states.json`, row for row from both halves -- state, outcome, mismatch and Closed. The CLI's tree reader (`Scripts/Read-DesignTree.ps1`) over a scratch tree: the four folders, grouping by id, a file with no id counted and not shown, two notes with one id a conflict, `README.md` skipped, a CRLF file read the same, the row's words, road order, the structure flags; and the `Design lifecycle` surfaces row -- `not configured` outside a repository or without `design/`, `on` with every file stamped, `off` with the count. The agent's `GET /api/design`: the four folders read in order, `structure`, a README skipped, the grouped shape with every field, a conflict shown as none, an id outside the contract's shape read as none, a note archived before its spec still a Spec, an archived document by its path with `kind`, `archived`, `closed` and `outcome`, a bad path never reaching `gh`. The hub's `GET /api/studio/design`: the same groups over the fixture hub with a spec, an archive and an unstamped file added, `items` and `count` still the live notes, a hub row's `space` and `thread_space`, a document by its hub path and the bare name still the live note, the renamed folder followed, a hub with no `spec/` saying so |
| `web`: `DesignList.test.tsx` (23), `DesignsCard.test.tsx` (the groups), `docFilters.test.tsx`, `docRooms.test.ts` | the Design tab as ONE list grouped by state in road order, Complete and Archived collapsed to a count and opened by their toggle or by a search; a row's title, description, state, short id and thread chip; a Spec row opening the spec with the note in its menu, a note alone its document, an archived row its archive path; the not-shown line counting by reason with the stamp named and Learn more; a mismatch sentence; the empty state that teaches with Learn more to `docs/hub/design.md`; an older agent read as nothing to show; the reading room by an archive path wearing Closed and the outcome. The hub drawer's groups: the same four regions, the archive collapsed, the Space chip and thread kept on a row, the chip counting designs, an archived note opening by its hub path, the stamp named with `-Hub`. The kind filter as what a design HAS, the text over title, description and id; the archive paths in the one room resolver |
| `Tests/test_move_design.py` | **`MoveDesign` typed as a verb** (L3) in a fresh `pwsh` with only this package's module, standing in a scratch repository with an origin remote and, with `-Hub`, against a scratch hub under `storeSync: git` (when `pwsh` is on the machine): the bridge can call it and `-Help` answers; `-WhatIf` names the git root first and writes nothing; `-To Spec` scaffolds the spec from the template (the id, the description, the thread line; LF, no BOM) and writes the journey's birth and Spec lines above `**Created:**`, staged as A and M with no commit and the suggested commit line printed; a note with no thread gets a spec without the line, and a CRLF note keeps every ending; `-To Archive` shipped and dropped (the reason required and written; `**Closed:**` then `**Outcome:**`, the journey above them), staged as D and A; `-To Complete` archives both with `> Docs:` under the spec's title and `**Closed:**` on each, a spec alone completing without a note; every refusal of the spec's table exit 2 with one `Error:` and nothing written (a spec already there, a live spec, an archived note, no `-Doc`, a `-Doc` that is not there, never overwriting, `-Dropped` outside Archive); a design named by id prefix, file or stem, the ambiguous and the unknown and the unstamped refused; `-Hub` committing once under `storeSync: git` with the journey naming "the hub", `-Hub -Space` moving a Space's own folder, `-Space` without `-Hub` and an undeclared Space refused; outside a repository refused |
| `web`: `DesignsCard.test.tsx` (the moves), `cliBridge.test.ts` | the moves a row offers by what it has and where it is; a graduation sending `MoveDesign <name> -To Spec -Hub` and the card saying the verb's line; a drop that cannot be pressed without its reason and sends `-Dropped -Reason`; a completion asking for the docs path and carrying `-Space`; a refusal kept in the dialog; `buildMoveDesignParams` |
| `Tests/test_design.py` (`TheSearch`, the search route), `Tests/test_studio.py` (search inside on disk) | **The library (L2b).** The words rule (every word, any order, case ignored; the first matching line); a repo's search inside through `gh api search/code` with the text-match media type, one call per root scoped by `repo:` and `path:`, hits mapped to the designs the files belong to in road order with a file that carries no id last as a hit with no state, every word having to match, nothing typed asking nothing, `gh` not answering a reason and never an error, the route its own before the document read and `supported: false` off GitHub with `gh` never asked. The hub's: the words over the files on disk across every state and the archives, the matching line, the title from the design, nothing typed empty, and the document read still answering for real names |
| `web`: `DesignList.test.tsx` (search inside, the outcome filter), `DesignsCard.test.tsx` (the search) | the Search inside button only once the box has words, asking with the trimmed words; each hit with its state and line, Open into its room, the note said; a search that cannot run saying why in its row, the agent not answering said as such, Clear taking the section away; the Archived group's outcome chips drawn only when it is open, narrowing its rows, the count as `1 of 3`, the same chip again off, and the Design group untouched by it. The drawer's box narrowing the groups and opening the archive that matches, the no-match line beside the not-shown line, and Search inside asking the hub route and opening a hit by its hub path |

**By hand**, with two GitHub Spaces connected and `gh` signed in: the Studio tab lists both (and every
other Space), each GitHub row's numbers match that Space's own Stats tab, and **Go into** lands on that
Space's Issues. **New Design Note** writes a file the list
shows within one fetch, and the file opens in an editor as the template's headings. **Promote** on it, in
a GitHub Space whose repo has a `design` label, opens an issue whose body is the note and writes the URL
back: the room then shows the note and its thread, and the list shows `#<n>`.

## Known gaps

- **Using a prompt from the tab** (Start work) is after the flip; today the card's action is Copy reference.
- **The agent resolves `agenticExtensionPath` itself** (`agentic_extension_path()` in `agent/core/config.py`),
  mirroring `Get-P20AgenticExtensionPath`; no shared fixture holds the two together yet.

- **No designs-in-flight count and no specs on a row yet.** Those are the foyer's S3 numbers (the spec's
  "S3 -- the foyer"); a row carries the pane's counts today.
- **Promote files into the Space you are in.** A note for another Space says so and asks you to switch;
  the verb does not reach into a Space you are not in, the way every `NewItem` acts on the active Space.
- **Promotion is not the move.** The thread is opened; moving the note into its product's repo
  (`design/` beside `spec/`, D-S10) is a commit, the engineer's or the agent's, and nothing here offers it
  (the spec's open item, "Promotion mechanics").
- **A repo's rows are read-only in the browser, and its search inside sees the default branch only.** The
  hub's rows move through `MoveDesign -Hub` (L3); a repo's designs move only from a terminal standing
  in that repo, because the browser does not know a Space's checkout (the spec's open item 2). A repo's
  Search inside (L2b) is GitHub's code search: it reads the default branch and lags a push by minutes,
  so a design on a branch, or pushed just now, is not found, and the note under the results says so; the hub
  is searched on disk as it is. Until a product is stamped, its tab is a count and the fix named.
- **No comment from the reading room.** The thread is read, not answered: commenting stays on github.com
  until a reply route exists (the S2 bullet left open).
- **One read per GitHub Space, every one, on every visit past the cache.** Five products are ten `gh`
  calls the first time the tab is drawn. Fine for a studio; not built for fifty Spaces. A non-GitHub row
  is one folder read of its own, no `gh`.
- **An archived Space you are not in does not count its cards**: its row says `go in to see its cards`,
  on purpose -- a read per visit for work that is done is not worth it.
- **An archived Space still has a row**, marked `archived`, under All and Archive -- that is what
  retiring it means; removing it is what takes the row away.
- **A retired Space is still on the avatar menu's Space list** -- the switcher's offered rule was not
  changed when retiring was built ([Known gaps](../KNOWN-GAPS.md)).
- **Every Space is read by the one `gh` login.** A second GitHub login (a work account beside a
  personal one) is not built: a repository only the other login can see reads `Visibility unknown` and
  `not visible to this login` in the **Add owner/name** row, and can still be added
  ([Known gaps](../KNOWN-GAPS.md)).
- **A list stops at 1000.** An owner with more repositories than that, or more shared with you, lists
  the first 1000 and says so; one past them is typed as `owner/name`, which reads it the same way.
- **One Space per +.** Several at once, discovering an Azure DevOps organisation's projects from
  the dialog, and creating a GitHub repository are not built; an Azure DevOps Space is added from the
  terminal (`NewSpace <slug> -Address <url>`, then `Connect <slug> -Discover`).
- **The filter is the one arrangement.** No tabs, no order of your own, no drag, no group you make, and no
  Hidden entry until hiding a Space is built -- the filter issue's body, still design.
