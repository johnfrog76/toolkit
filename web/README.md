# The web UI

The Toolkit in a browser: a React + Fluent UI front end that shows your cards, the board, the
tracker's issues and whichever add-ons are on, and changes nothing except by running a CLI verb
through the agent. It is built in two parts: a **shell** that owns the chrome, and **modules** that
own everything else -- `ado`, the always-on core, `studio`, core too and with no flag
(D-S13), and the opt-in `growth`, `communication`, `organize` and
`solitaireAgile`, plus the web-only `deck` and `lounge`, each switched by its `features.*` flag.

This is one of the Toolkit's three halves. It reads through the agent (`../agent/`, port
4100) and nothing else: no file access, no `az`, no direct ADO call.
[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md#the-web-ui) is the short version of this file; this
one is the detail. The root [`README.md`](../README.md) is the map of every document.

## Quick start

```bash
npm ci
npx playwright install chromium   # once per machine, and only for `npm run smoke`
npm run dev          # http://localhost:5174 -- or the next free port, which Vite prints
```

`tkWeb -Dev` does both of those in one command and **opens the browser** when a person typed it;
`npm run dev` here is the half without the launcher. `tkWeb -NoBrowser` (or a `CI` variable, or a
redirected stdout) skips the opening and prints the URL instead -- see the `Web` row in [the command reference](../docs/CLI.md#command-reference).

The agent must already be running, because `vite.config.ts` proxies `/api` to it -- on
`web.agentPort`, 4100 as shipped -- and every card in the app is a query against it:

```bash
cd .. && python3 -m uvicorn agent.app:app --port 4100   # Windows: python or py -3
```

Without it, the shell hangs on `Loading toolkit...` -- that spinner is the `/env` gate, and `/env`
is what the whole registry is filtered on.

## Scripts

What each `npm run` script does:

| Script | Runs | Notes |
| --- | --- | --- |
| `npm run dev` | `vite` | Port 5174, HMR, `/api` proxied to the agent on `web.agentPort` -- `P20_AGENT_PORT` when `tkWeb -Dev` set it, else read from the two config files |
| `npm run build` | `vite build` | Output to `dist/client` -- **not** `dist`. The agent serves that exact path in production. It asks for **no** configuration: the `/api` proxy is the dev server's, so `vite.config.ts` resolves `web.agentPort` for `command === "serve"` only, and the image can build without a config file |
| `npm run build:landing` | `vite build --mode landing` | The landing page alone, to `dist/landing` with `index.html` as its page -- see [The landing page](#the-landing-page). It reads `README.md` and `THIRD-PARTY-NOTICES.md` from the package root, which is why `npm run build` leaves it out |
| `npm run preview` | `vite preview` | Serve the build locally; `vite preview --mode landing` serves the landing page's |
| `npm run lint` | `eslint src` | 0 errors, 0 warnings on this commit, and a warning is a finding too ([Contributing, "Lint"](../docs/CONTRIBUTING.md#lint)). State that follows a prop or a query is adjusted while rendering, not in an effect -- `hooks/useUserRefetch.ts` is the shared case, the Refresh button's spinner; the one effect that mirrors an external system (`PresenterNotes`' audio) carries a disable with its reason |
| `npm run lint:fix` | `eslint src --fix` | |
| `npm run type-check` | `tsc --noEmit` | Clean on this commit |
| `npm run format` | `prettier --write src` | |
| `npm run format:check` | `prettier --check src` | |
| `npm test` | `node tests/viteconfig.mjs && jest` | The build contract first -- 4 checks, no browser -- then the shell's suites |
| `npm run test:config` | `node tests/viteconfig.mjs` | `vite.config.ts` alone: a build declares no `/api` proxy, serving resolves one and prefers `P20_AGENT_PORT`, and the dev port stays a literal the PowerShell readers find |
| `npm run test:watch` | `jest --watch` | |
| `npm run smoke` | `node tests/smoke.mjs` | Playwright, flags off. Needs `npx playwright install chromium` once, and two servers -- see below |
| `npm run smoke:modules` | `node tests/smoke.mjs --modules=on` | The same, with both module flags on |
| `npm run smoke:mobile` | `node tests/smoke.mjs --viewport=mobile` | The same at 430x932 -- see "A second axis" below |
| `npm run smoke:landing` | `node tests/smokeLanding.mjs` | The built landing page: its links, the banner at 390 px and at 1280x640. Builds the page and serves it itself; no agent, no dev server, no network |
| `npm run smoke:studio` | `node tests/smoke.mjs --studio` | The Studio's contract, on servers it starts and stops itself -- see "A mode with its own servers" below |
| `npm run smoke:matrix` | `node tests/smoke.mjs --matrix` | Each module flag alone, the flip, fresh and storage-refusing contexts, on its own servers too |
| `npm run smoke:a11y` | `node tests/smoke.mjs --a11y` | axe on every page the registry mounts, flags off and on, `seaglass` and `aurora`, on its own servers; lists findings by impact and fails on any serious or critical one |
| `npm run smoke:first-run` | `node tests/smoke.mjs --first-run` | The first run's first move: on a copy of `samples/hub`, the first tutorial card dragged from Backlog to To do and the moved file read back, on its own servers |
| (flag) `--shots=<dir>` | | One PNG per route per viewport, under the gitignored `web/shots/` |

`npm run build` does **not** run the tests or the type-check. Run `npm run type-check && npm run
lint && npm test` yourself; nothing in this package does it for you.

## Layout

```text
web/
├── vite.config.ts        dev server on 5174, /api -> the agent on web.agentPort (P20_AGENT_PORT,
│                        else the two config files), outDir dist/client, and the @consts
│                        alias -> ../consts.json (the contract file); --mode landing builds the
│                        landing page instead
├── landing.html          the landing page's entry -- the second entry, see "The landing page"
├── jest.config.mjs       ts-jest + jsdom, matches src/**/*.test.ts(x)
├── Dockerfile            build the SPA, serve it from nginx -- context is the PACKAGE ROOT,
│                        because the bundle inlines ../consts.json
├── nginx.conf.template   static + /api -> host.docker.internal:${P20_AGENT_PORT}, substituted
│                        by the nginx image's entrypoint at container start
├── docker-compose.yml    127.0.0.1:5174 -> container 5173; passes P20_AGENT_PORT in
├── tests/smoke.mjs       Playwright, two modes (23 checks off / 30 on), raw `playwright` not @playwright/test
├── tests/smokeStudio.mjs   its --studio cases; smokeStack.mjs starts the servers that mode owns
├── tests/smokeMatrix.mjs   its --matrix cases, on the same kind of servers
├── tests/smokeA11y.mjs     its --a11y audit, on the same kind of servers
├── tests/smokeFirstRun.mjs  its --first-run drag, on the same kind of servers and a copy of samples/hub
├── tests/jest.setup.cjs   jest setupFiles: Node's TextEncoder/TextDecoder for jsdom, which React Router 8 needs
├── tests/routeModules.jest.cjs  jest only: a stub for react-router's one file that reads import.meta
└── src/
    ├── shell/            the composition root -- owns chrome, owns no decisions
    │   ├── App.tsx         theme, nav, the /env gate, Home's tabs, System's pager, the <Routes> table
    │   ├── SpaceAnchor.tsx the Space pill at the left of the nav, which IS the Home entry
    │   ├── SettingsDrawer.tsx  the one settings surface; the avatar in the nav bar opens it
    │   ├── main.tsx        Provider + BrowserRouter + App
    │   ├── themeList.ts    the named themes, as plain data -- adding one is adding a record
    │   ├── theme.ts        a named theme made into a Fluent theme (the accent ramp), and the noise overlay
    │   ├── ThemePicker.tsx the first section of the settings drawer
    │   ├── store.ts        one Redux store: the api slice and the filters slice
    │   ├── filtersSlice.ts the filter drawer's six values; a successful Space switch clears them, and the Docs and Design filters with them
    │   ├── api.ts          createApi, and exactly two endpoints: /env and /switch-mode
    │   ├── registry.ts     ToolkitModule, CardContext, and the four functions that read them
    │   ├── registry.test.tsx
    │   └── cards.tsx       ShellContext: the card pages and the filter tuple, passed down
    ├── modules/ado/      the ADO prompt-engineering module -- always on, no flag
    │   ├── index.tsx       the ToolkitModule export: routes, nav, homeCards, systemCards
    │   ├── routes.tsx      AdoHome and AdoSystem -- what sits around the shell's card grid
    │   ├── api.ado.ts      the module's endpoints, injected into the shell's slice; tag types Status, PrComments, Config, Billing, Issues, Issue
    │   └── *.tsx           every card and detail page (see "The module's surface")
    ├── modules/growth/    opt-in, features.growth
    │   ├── index.tsx       export growthModule, plus ReviewArchive and SkillsSnapshot by name
    │   ├── api.growth.ts   tag types Growth, Resume, Reviews
    │   └── GrowthPage, Goals, GoalDetailPage, SkillsPage, ReviewArchive, SkillsSnapshot
    ├── modules/communication/   opt-in, features.communication
    │   ├── index.tsx       export communicationModule, the four routes and three redirects
    │   ├── paths.ts        every route path of this module, in one place
    │   ├── api.communication.ts   tag type Manager, and /env's communication block typed here
    │   ├── sendButton.ts   the send button's rule, as a pure function
    │   └── OneOnOne, ManagerDetailPage, ManagerSessionPage, Timer
    ├── modules/organize/   opt-in, features.organize -- the Organize tab
    │   ├── index.tsx       export organizeModule: one route, one nav entry, the header bell, no cards elsewhere
    │   ├── paths.ts        the module's route path, and the router state that opens a bucket
    │   ├── ReminderBell    the header bell: asleep (zz) or awake with the past-due count
    │   ├── useOverdueReminders  the past-due slice of the reminders read, polled each minute
    │   ├── api.organize.ts tag type Reminders; GET /api/reminders and the two verbs via the bridge
    │   ├── reminderEntry   a stored due split into the Edit dialog's date and time, and joined back
    │   └── RemindersCard   bucket chips, snooze menu, edit, done, the quick add
    ├── modules/solitaireAgile/   opt-in, features.solitaireAgile -- today's standup, read and played, and triage
    │   ├── index.tsx       export solitaireAgileModule: four routes (the standup, triage, milestones, the played view, chromeless), one nav entry, no cards elsewhere
    │   ├── paths.ts        the module's route paths and the played deck's id
    │   ├── api.solitaireAgile.ts   GET /api/ritual/standup, /triage and /milestones ?space=<slug>, read through @consts; POST /api/cmd/Route
    │   ├── RitualPage      the Standup | Triage | Milestones strip, each tab an address, and the page under it
    │   ├── StandupPage     Agenda first, then the agent's text verbatim on Detail | Work | Brief: line one the header, the rest monospace, #<n> linked; Copy and Play in the header
    │   ├── AgendaLanes     the Agenda: Since <day> and Waiting on you, tiles from the board's face pieces (or rows), one button a waiting tile
    │   ├── agenda.ts       the Agenda's words: the long day, the lane heading, each tile's one fact
    │   ├── TriagePage      one open issue at a time, unplaced first: milestone, severity, size; each answer one Route
    │   ├── MilestonesPage  one row per milestone, its bar the tracker's numbers; the award queue (award.ts)
    │   ├── AwardDialog     the award -- congratulations, what it took, the picture -- and Confetti's one caller
    │   └── stage/          the played view: one lazy chunk with the deck engine
    │       ├── cast.tsx        the Remote Standup's atoms, by copy from the Wasteland (no bios); reduced motion stills them
    │       ├── seats.ts        the nine seats, the plates (role · persona (label)), the deal of workers onto seats
    │       ├── standupDeck.tsx the standup response -> an audiobook Deck: queue, chair, a tile a worker, chair, queue
    │       └── StandupPlay     /deck/ritual/standup: the resolver, handed to the deck engine's GeneratedDeckHost
    ├── landing/          the landing page: no router, no store, no agent (see "The landing page")
    │   ├── main.tsx        the entry: the page, or the commercial playing
    │   ├── words.ts        the page's words, read from README.md and THIRD-PARTY-NOTICES.md
    │   ├── Landing.tsx     the five bands, drawn from the words
    │   ├── Commercial.tsx  the deck's poster and player, the app's own engine and clips
    │   └── people.ts       band 3's three lines -- empty, and the band held, until they are written
    ├── shared/           reusable UI: PageCard, Pagination, FilterBadge, listRowStyles (the house list row), MarkdownViewer, ImageDropZone (one picture in: drop, paste, or a file; C2),
    │                     StatusMessage (a live region: role=status, role=alert for an error), StatTile (the one way a card counts), CardActions,
    │                     ConfirmDialog and CreateButton (one grammar for acting), ToolKitLogo over Wordmark (the SVG mark, its outlines in wordmarkPaths.ts),
    │                     usePersistedState, faces, health,
│                     thinScrollbar (the one themed scrollbar -- spread it, never retype it), ...
    ├── hooks/            reusable logic: useWornTheme (and the store's useCurrentTheme), usePagination, useFacePref,
    │                     chartPalette, useUserRefetch
    └── utility/          formatters: abbreviate, and dates -- the ONE place the clock is read
                          (Luxon: local day, days ago, next weekday, last month, due in words,
                          timeAgo, formatDate); never toISOString for a day -- a test greps for it
```

`shared/` and `hooks/` are not the ADO module's. They are the shell's common ground, and a second
module will use them as they are.

## The `ToolkitModule` interface

One export per module, in `src/shell/registry.ts`:

```ts
export interface ToolkitModule {
  id: "ado" | "growth" | "communication" | "deck" | "organize" | "studio" | "solitaireAgile" | "lounge";
  /** absent = always on (core) */
  feature?: keyof NonNullable<EnvStatus["features"]>;
  /** mounted verbatim; chromeless?: true hides nav */
  routes: RouteObject[];
  nav?: NavEntry[];
  homeCards?: (ctx: CardContext) => ReactElement[];
  systemCards?: (ctx: CardContext) => ReactElement[];
  headerItems?: (ctx: CardContext) => ReactElement[];
  // ...and settingsSections, settingsLinks, slotCards, chromeless: see registry.ts
}
```

| Field | What it does |
| --- | --- |
| `id` | The module's name, from a closed union. The union is the list of modules the Toolkit plans to have, so adding one is a deliberate edit here rather than a string appearing somewhere |
| `feature` | The `features.*` key in `/env`'s merged map that switches this module on. The default scope is the engineer: a top-level flag holds across orgs; only the ADO core's org-scoped keys (`sprintAwareness`) come from the active Space. **Absent means always on** -- that is the ADO module. |
| `routes` | `RouteObject[]`, mounted verbatim by the shell. The shell reads `path` and `element` and nothing else; it does not wrap, guard or rename them |
| `nav` | Nav-bar entries. Each carries its own `match(path)` predicate, so a module decides when its own entry looks active -- the shell does no path parsing on a module's behalf |
| `homeCards` | Builds this module's cards for `/`, given the shared `CardContext`. The shell concatenates every active module's output in module order and pages it four at a time |
| `systemCards` | The same for `/system` |
| `headerItems` | Small keyed controls for the header, left of the avatar and 1rem from it, on every page -- a signal worth seeing wherever you are. Organize's reminder bell is the one there is |

Two additions to the shape the spec sketched, both forced by real content:

**`NavEntry.hidden?: (ctx: CardContext) => boolean`.** One nav entry is conditional -- Daily, which
an archived org has nothing left to bill -- and that had to be said somewhere. A predicate on the
entry keeps `nav` a plain array instead of turning the whole field into a function of context.

**`feature?: keyof NonNullable<EnvStatus["features"]>`.** `features` is optional on `EnvStatus`,
because `/env` may not send it; `keyof` over an optional property is not a usable key type, so
`NonNullable` is what makes the field mean "a key of the features map" rather than "a string".

`CardContext` is the tuple the shell hands every card builder: `env`, `filterValue`, `stateFilter`,
`stateOptions`, `activeRepo`, `activeSkillTag` and its setter -- the values `App.tsx` holds, read
from one place rather than captured by each builder.

### The registry array is the list of modules

```ts
export const modules: ToolkitModule[] = [adoModule, growthModule, communicationModule, deckModule, organizeModule, studioModule, solitaireAgileModule, loungeModule];
```

That array is the whole list, and its order is the order cards and nav entries come out in. What
the first two opt-in modules put into it (deck, organize and lounge are below the table):

| | `growthModule` | `communicationModule` |
| --- | --- | --- |
| `feature` | `"growth"` | `"communication"` |
| `routes` | `/growth`, `/growth/goals/:filename`, `/skills` | `/communication`, `/communication/1on1/:filename`, `/communication/sessions/new`, `/communication/sessions/:filename`, plus three redirects |
| `nav` | one entry, **Growth**, matching `/growth*` and `/skills` | one entry, **Meetings**, matching `/communication*` |
| `homeCards` | none | none |
| `systemCards` | none | none |
| tag types, via `enhanceEndpoints` | `Growth`, `Resume`, `Reviews` | `Manager` |

Growth contributes no cards of its own and still gets two onto a home page: it exports
`ReviewArchive` and `SkillsSnapshot` **by name**, and the ADO module's archive-mode home imports
them. A module may import another module's card; it may not fork one. The import is what the
registry gates, so an install without growth renders that branch's two ADO cards and nothing breaks.

Communication contributes no cards at all, on purpose -- a 1:1 workflow is something you go to, and
the home page is for what needs doing today.

The other modules each have a document that owns their detail:

- **deck** (`features.deck`, [`../docs/modules/deck.md`](../docs/modules/deck.md)) -- the player at
  `/deck/:deckId` and its notes window, both `chromeless`; a **Decks** nav entry that is `hidden` while
  growth is on, because the launcher then goes into growth's slot as a card; and the first-run banner in Home's `home-banner` slot (`HOME_BANNER_SLOT`, `shell/slots.ts`), asked for
  only while `/env` says `firstRunWelcome`.
- **organize** (`features.organize`, [`../docs/modules/organize.md`](../docs/modules/organize.md)) --
  `/organize` and an **Organize** nav entry. The page renders an `organize` slot, which communication
  fills with its Meetings card; communication's own **Meetings** nav entry is `hidden` while organize
  is on.
- **studio** (core, no flag -- D-S13; [`../docs/modules/studio.md`](../docs/modules/studio.md)) -- `/studio` and a
  **Studio** nav entry, always there, before Team Agile's and the Lounge's: the foyer, one row per Space
  `/env` offers -- a GitHub row (by `config.spaces[].tracker`) read through `?space=<slug>` on the pane's
  own routes, any other row its cards counted in place from `/api/status` (`?space=<slug>` for a Space you
  are not in, under that Space's own `laneNames`; an archived one is not asked); a row switches in. The
  card is titled **Spaces**, with one filter in its header -- All, Products, Work, Out of box, Archive,
  derived by `spaceBucket` in `foyer.ts` and remembered per browser. Its foot **+** opens the New
  Space dialog (`NewSpaceDialog.tsx`): your repositories from `GET /api/spaces/candidates`, or a typed
  `owner/name`, or your own cards; Add is `POST /api/cmd/NewSpace`, and `/env` is read again so the row
  appears. A row's `...` holds **Retire** and **Remove** (`SpaceLifecycleDialog.tsx`): the house
  confirm showing the verb's own `-WhatIf`, then `POST /api/cmd/RetireSpace` or `RemoveSpace -Force`.
  Its pages are still lazy parts.
- **solitaireAgile** (`features.solitaireAgile`, served on only where the active Space answers `agents`;
  [`docs/modules/solitaire-agile.md`](../docs/modules/solitaire-agile.md)) -- `/solitaire-agile`
  and a **Team Agile** nav entry after the Studio's and before the Lounge's. Today's standup opens on its
  **Agenda** -- what moved since the last standup, and what is waiting on you as tiles built from the
  board's card face, each waiting one with **Work it now** or **Review it** -- and its Detail, Work and
  Brief tabs show the agent's `text` verbatim, its first line as the card's header and the rest in a
  monospace block, each `#<n>` the response names linked to its issue. Under the tab, a Standup | Triage
  strip: Triage (`/solitaire-agile/triage`) asks the open issues one at a time -- milestone,
  severity, size -- and each answer is the CLI's `Route` through `POST /api/cmd/Route`.
- **lounge** (`features.lounge`, [`../docs/modules/lounge.md`](../docs/modules/lounge.md)) -- web-only,
  like deck: `/lounge` and a **Lounge** nav entry, last by module order, and no cards anywhere else.

`slotCards` is how a module fills another's page without importing it, and the slot's name is the
whole contract between the two.

Each module also adds its own tag types to the shell's single slice with `enhanceEndpoints`, so the
shell never learns the names of a module's tags. `growthApi.util.invalidateTags` is what growth's
refresh buttons dispatch; the shell's `api` object does not know those tags exist.

### Off means absent

The rule the whole design exists for. `activeModules()` filters the list by
`env.features[module.feature]`; a module that does not survive that filter contributes **no route,
no nav entry, no card**, and nothing fetches its data. Not hidden, not disabled, not a 403.
`registry.test.tsx` asserts each half directly, and the smoke test proves the data half from
outside the app: visiting `/growth` with `features.growth` false, nothing requests `/api/growth`,
`/api/reviews`, `/api/resume` or `/api/review-preview`.

**And it means no bytes.**
`registry.ts` imports each module's DESCRIPTOR statically: `index.tsx`, which names the id, the flag,
the route paths and the nav entry and imports no component. Every page, card and header item an
opt-in module contributes is a `lazyPart` (`src/shell/lazy.tsx`): a dynamic `import()` Vite splits into
a chunk of its own, behind a Suspense boundary that belongs to the part rather than to the shell, so
a card still loading shows its own small spinner in its own place. The deck module drew the shape
first; growth, communication, organize, the Studio, Team Agile and the Lounge follow it, and the ADO core stays in the first
load on purpose -- it is always on. The Studio is always on too, and lazy anyway: lazy is about bytes,
not about being optional. `lazyModules.test.ts` reads each descriptor's source and refuses a
static import from its own folder that is not `paths`; `lazy.test.tsx` holds the fallback-then-content
order. The smoke test's off mode asserts that no module SOURCE was requested, and its on mode that
drawing `/growth` is what fetches growth's parts.

### Every registry test mocks every module

`src/shell/registry.test.tsx` and the six per-module registry tests --
`src/modules/growth/registry.growth.test.tsx`,
`src/modules/communication/registry.communication.test.tsx`,
`src/modules/organize/registry.organize.test.tsx`, `src/modules/studio/registry.studio.test.tsx`,
`src/modules/solitaireAgile/registry.solitaireAgile.test.tsx` and
`src/modules/lounge/registry.lounge.test.tsx`
-- each `jest.mock()` **every** module, including the siblings of whichever one they are about, and
including that module's own page components.

That is not tidiness. A registry test is about the registry's *filtering*, so a one-line stand-in
(`{ id: "growth", feature: "growth", routes: [] }`) is the correct subject. And the practical reason
is sharp: a sibling's real tree left to load pulls in `react-markdown` -- ESM, which ts-jest cannot
take -- so the suite goes red for a reason that has nothing to do with the registry.

**Adding a module means adding a mock line to every one of these files.**

## How a module injects its endpoints

There is **one** Redux store and **one** `createApi`. The shell owns the slice and the two
endpoints every module is gated on; a module adds its own:

```ts
const adoApi = api.enhanceEndpoints({ addTagTypes: ["Status", "PrComments", "Config", "Billing", "Issues", "Issue"] });
export const adoEndpoints = adoApi.injectEndpoints({ endpoints: (builder) => ({ ... }) });
```

`enhanceEndpoints` is how a module adds tag types to a slice it did not create. Declaring `Status`
and `PrComments` on the shell's `createApi` would put every module's vocabulary in the shell, which
is the thing being avoided. A module that is switched off is never imported, so its endpoints, its
cache entries and its tags do not exist -- not "exist but go unused".

**A write names what it changed, and the store refetches** (in the owner's words, "if I close
issue it should update the store"). The tracker's reads carry tags -- `Issues` on the work-items
list and the Issue Report, `Issue` by number on a reading room -- and the three verbs that change
them invalidate them: `NewItem` the list and the report; `EditItem` and `CloseItem` those plus the
one issue they touched (`CloseItem` also `Status`, since a linked card reads its state from the
ledger). So the Issues tab, the report and an open reading room are never a reload behind the
ledger, and no page calls `refetch()` by hand after a write. `api.ado.tags.test.ts` pins it at the slice, over a stubbed `fetch`, by counting what the
store asked for again.

## How a card changes something

Reads are native agent routes, one per card. **Writes are not.** Nothing in this half changes a
prompt file or an ADO work item itself -- every mutation is `POST /api/cmd/{name}`, which runs the
Toolkit's own PowerShell function. There is one write path, and it is the CLI.

`{name}` is a key of the CLI's `$script:CommandMap` -- `NewItem`, `CloseItem`, `Archive`,
`NewPrompt`, `GetPRComments`, `NewPR`, `ReplyPR`, `Log`, `TestToolkit`. Not a `tk*` alias: the
bridge is prefix-agnostic, so a command added to the CLI is reachable from here with no backend
edit.

**One write does not post to `/cmd` and is not an exception.** The Configuration card puts to
`PUT /api/config`, and the agent runs `Config` through the same bridge on its behalf -- a
typed body is a better shape for a form than a raw argv array, and the argv it becomes is pinned on
both sides (`buildConfigEdit` here, `build_params` there). It still ends in the CLI.

### The argv rule

The body is `{ "params": ["...", "..."] }` and those strings reach PowerShell **as argv** -- one
array element is one argument. A value with spaces or punctuation is a single element, unquoted:

```jsonc
{ "params": ["-Type", "Bug", "-Title", "Fix the upload timeout"] }   // four arguments
{ "params": ["-Type Bug -Title \"Fix the upload timeout\""] }        // wrong -- one argument
```

Quoting and escaping are the bridge's problem, not the browser's. Pre-joining a command string is
exactly what the retired native routes did server-side, and it is what this rule exists to stop
reappearing on the client.

### The four statuses

The reply is always `CommandResponse`, and `status` is one of four. They are not two:

| `status` | What happened |
| --- | --- |
| `success` | The command ran and exited 0. `output` is its stdout |
| `error` | The command ran and failed. `error` says how, and `output` may still hold what it printed first -- the CLI's own `[!]` line usually lives there |
| `rejected` | The bridge refused before running anything: not a `CommandMap` key, or a gate said no |
| `timeout` | It ran and was cut off at the command's timeout |

`commandResultMessage` in `modules/ado/cliBridge.ts` is the one place that turns any of the four
into text; both dialogs render through it, so a refusal is never shown as a failure.

### The worked example: the two dialogs

`CreatePrompt` (the card) and `ActionDialog` (the modal) offer the same four actions, and two of
them create or close ADO work items. Both mutations post to `cmd/NewItem` and `cmd/CloseItem`;
there is no native route for either (History, below).

What the dialog collects becomes argv in `cliBridge.ts`, and **the script's `param()` block is the
contract** -- flags spelled and ordered as `Scripts/New-AdoItem.ps1` and `Scripts/Close-WorkItem.ps1`
declare them, nothing invented:

```text
New ADO Item  ->  -Type UserStory -Title <t> [-Description] [-Project] [-Parent] [-Sprint]
                  [-Priority] [-Points] [-AcceptanceCriteria] [-ReproSteps] [-Tags]
Resolve       ->  <id> -Comment <text> [-Reason <r>]
```

Three things the builders do on purpose:

- **A blank field is omitted, not sent empty.** `-Parent 0` and `-Priority 0` are the script's own
  "unset" values; restating them says nothing.
- **`-Reason` is omitted when there is none to state.** `Close-WorkItem.ps1` branches on whether
  `-Reason` was *bound*, not on its value, so sending the default `Fixed` would ask ADO to close a
  User Story with a reason its process need not accept. Unsent means Fixed for a Bug and Completed
  for everything else. `ActionDialog` knows the work item's type and so sends nothing for a non-Bug,
  which is what its read-only "Completed" field promises; `CreatePrompt`'s tab is typed by hand and
  has no type to go on, so it sends whatever the reason dropdown shows.
- **Two parameters have no UI and are never sent.** `-AssignTo` is left to the script's
  `Resolve-P20Identity` (the configured identity -- what the dialog means by "me"), and `-ReadOnly`,
  a dry run, has no control.

The communication module's one bridge call is built here too: `buildMeetingAgendaParams` is
`-Date <date> [-Type <series>] -<Plan|Prep|Retro|Close>` for `Scripts/Get-MeetingAgenda.ps1`, with
`-Type` sent only for a series that is not the 1:1 (the script's default). `CloseMeeting.tsx` runs
the `Close` form behind a confirm, because it moves a file; a stated refusal is the dialog's
message.

**Closing asks first.** Resolve is the one tab a person may regret -- the item
leaves every list -- so it is not a generic form: the title names the act and the item ("Close
issue #N", "Resolve work item #N" on ADO), one sentence says what happens and what does not (the
thread stays, it can be reopened), and the button is named for the act rather than "Submit". That
button opens `shared/ConfirmDialog` -- the owner's sketch: "Are you sure?", the act named once more
("Close issue #N."), Cancel (secondary) and Submit (primary), the house dismiss top right -- and
only Submit runs the verb. `ActionDialog.resolve.test.tsx` holds it: Cancel and the dismiss run
nothing, Submit runs it once. `ConfirmDialog` is the shared shape for any act worth a second
thought, and the only one: the list's and the board's archive, a growth item's Archive and a goal's Complete, and a
meeting's Close all ask through it (see "One grammar for dialogs and row actions").

`cliBridge.test.ts` asserts the exact array for each, so a flag renamed in either `.ps1` fails a
Jest run rather than an `az` call. It stays the cheapest check with the bridge real: a Jest run costs nothing and does not need ADO, whereas proving the same thing end to end
needs a live agent and a Tier-1 machine.

### One grammar for dialogs and row actions

An audit of the dialogs and the row actions, from the owner's acceptance testing ("New card dialog
flow card actions etc"), converged on this:

- **A row: one exposed action, the menu for the rest.** `shared/CardActions` draws the exposed action
  as a flat button and EVERY other action in the `...` menu -- even when there is only one, so every
  row reads the same. The exposed action goes somewhere in the app (Open the card, Open the issue, Open
  the goal, Open the review, Open the resume); where the tracker has no page of ours for the thing -- an
  ADO work item or PR -- it is the tracker's page; a reminder has no page, so it is the act it exists
  for, **Archive**. The external link is LAST in the menu, behind a divider. The trigger's name is
  `Actions for <the row's title>`. Every word, icon and tooltip comes from one vocabulary --
  [One vocabulary for row actions](#one-vocabulary-for-row-actions).
- **A card that makes something has one +.** `shared/CreateButton`: the footer's subtle **+**, its
  tooltip and accessible name at once, and its words are the title of the dialog it opens -- New
  Growth Item, New 1:1, New Reminder, Generate Review, New ADO Item or **New GitHub Issue** on a gh
  space. The Cards list's + is **New card**, because its
  dialog has doors and every default door makes a card; Home's floating + is **Create**, for the same
  dialog on every tab.
- **A form dialog**: the title names the thing (title case), the house dismiss (`DialogDismiss`) top
  right, **Cancel** (secondary) and one primary: **Submit** to create, **Save** to edit, **Generate**
  for the review scaffolds. A refusal stays in the dialog in the verb's words.
- **An act worth a second thought**: `shared/ConfirmDialog` and nothing else -- "Are you sure?", the act
  named with one sentence of what follows (`archiveWhat` in `modules/ado/confirmWords.tsx` is the
  archive's, shared by the list and the board), Cancel and Submit. `busy` holds both buttons while the
  verb runs; `message` shows a stated refusal in place, and the dialog stays open.

`CardActions.test.tsx`, `ConfirmDialog.test.tsx`, `RetireGoal.test.tsx` and `MyWork.test.tsx` pin it.

### One vocabulary for row actions

The same move reads the same on every page: one word, one icon, one tooltip. `shared/CardActions.tsx`
defines each standard move once, in `ROW`, and every row's menu in the product builds its actions from
those entries -- `ROW.archive.action({ onClick })`, `ROW.external.action({ detail: "GitHub", href })`.
`CardAction.move` is required, so an action typed by hand does not compile. A detail, where the move
takes one, follows the word: **Open the note**, **Archive as shipped**, **Move to In Progress**,
**Copy reference**, **Open on Azure DevOps**.

| Move | Word | Icon | Tooltip |
| --- | --- | --- | --- |
| `open` | Open *the thing* | `DocumentTextRegular` | Open {detail} here, in ToolKit -- inside the product, never another site |
| `archive` | Archive *(as what, where there are two)* | `ArchiveRegular` | Move it to the archive, stamped closed |
| `complete` | Complete | `CheckmarkRegular` | Mark it complete |
| `delete` | Delete *the thing* | `DeleteRegular` | Delete {detail} for good |
| `move` | Move to *where* | `ArrowRightRegular` | Move it to {detail} |
| `copy` | Copy *what* | `CopyRegular` | Copy the {detail} to the clipboard |
| `external` | Open on *the system's name* | `OpenRegular` | Open it on {detail}, outside ToolKit |

Where each one is drawn: **Open** -- the card (list and board), an issue, a design's note, spec,
document and thread, a goal, a review, the resume, a prompt, the Space you are in. **Archive** -- a
goal (it said Retire), a reminder (it said Done; the verb is `Reminders <id> -Archive`), a card's Done
lane (**Archive (move to Done)**), and a hub design, **Archive as shipped** and **Archive as dropped**
(it said Drop). **Complete** -- a hub design's spec, and a goal that is not complete yet (row and page). **Delete** -- a card's cover (it said Remove
cover; the picture is deleted). **Move to** -- a card's lanes. **Copy** -- a prompt's reference and
text. **Open on** -- every row's link out, whatever it said before (Open in ADO, Open in Azure
DevOps, Open the thread on GitHub, Its history on GitHub). The verbs behind the menus keep their
names: a goal's Archive still runs `NewGrowth -Close`, and its Complete runs `NewGrowth -Complete`.

**The order is one rule.** The row's one exposed action first, the record's own moves next, the external
link last. The last is the component's: an action built from `ROW.external` is drawn at the end of the
menu behind a divider whatever order it was given in. Where the record has no page in ToolKit -- an
Azure DevOps work item, a pull request -- the external link IS the exposed action, and the menu does
not repeat it.

**A module's own moves** are declared once, in a `defineRowMoves("<record>", { ... })` table beside the
row that draws them, and listed here. Two kinds, both named:

- **A move on one kind of record only** keeps its own word and icon (snoozing a reminder, graduating a
  design).
- **A move that is a different thing** keeps its different word even where it sounds like a vocabulary
  move, and says why in `differentMove`: retiring a Space writes its `status: archive` through
  `Config` and moves no file, so it is not an archive; removing a Space un-declares it and deletes
  nothing, so it is not a delete; closing an issue or resolving a work item happens on the tracker, and
  nothing in ToolKit completes.

| Move | Word | Icon | Kind | Where |
| --- | --- | --- | --- | --- |
| `card.createPr` | Create PR | `ArrowUploadRegular` | one record | a card, list and board |
| `card.markNotBillable` | Mark not billable | `MoneyRegular` | one record | a card |
| `card.makeBillable` | Make billable again | `MoneyRegular` | one record | a card |
| `card.remind` | Remind me about this | `AlertRegular` | one record | a card, while organize is on |
| `cover.replace` | Replace cover | `ImageEditRegular` | one record | a card's cover, on its page |
| `cover.addBefore` | Add before | `ImageAddRegular` | one record | a card's cover |
| `cover.replaceBefore` | Replace before | `ImageAddRegular` | one record | a card's cover |
| `pr.fetchComments` | Fetch PR comments | `CommentRegular` | one record | My PRs |
| `issue.makeCard` | Make a card | `DocumentAddRegular` | one record | the Issues tab |
| `issue.close` | Close issue | `CheckmarkCircleRegular` | different move: it closes the issue on GitHub | the Issues tab |
| `issue.resolve` | Resolve Work Item | `CheckmarkCircleRegular` | different move: it resolves the work item on Azure DevOps | the Issues tab |
| `issue.pin` | Pin on *the tracker* | `PinRegular` | one record | the Issues tab |
| `issue.unpin` | Unpin | `PinOffRegular` | one record | the Issues tab |
| `reminder.snooze` | Snooze: *when* | `SnoozeRegular` | one record | Reminders |
| `reminder.edit` | Edit | `EditRegular` | one record | Reminders |
| `resume.generate` | Generate resume scaffold | `AddRegular` | one record | the resume |
| `resume.howItWorks` | How resume updates work | `InfoRegular` | one record | the resume |
| `design.graduate` | Graduate to a spec | `HatGraduationRegular` | one record | a hub design (Studio) |
| `design.promote` | Promote | `ShareRegular` | one record | a design note's page |
| `space.enter` | Go into *the Space* | `ArrowEnterRegular` | one record | the Studio's Spaces |
| `space.connect` | Connect *the Space* | `LinkRegular` | one record | the Studio's Spaces |
| `space.retire` | Retire *the Space* | `HistoryRegular` | different move: a status written through `Config`, no file moved | the Studio's Spaces |
| `space.remove` | Remove *the Space* | `SubtractCircleRegular` | different move: un-declared, nothing deleted | the Studio's Spaces |

Completing a goal is not on this list yet: a goal's row offers Open and Archive today.

**Adding to it.** A new standard move is an entry in `ROW`, a synonym list in `ROW_SYNONYMS` and a row in
the first table. A module's new move is an entry in its `defineRowMoves` table and a row in the second.
`shared/rowVocabulary.test.ts` reads every source file under `src/` and fails on an action typed by
hand; on an own move whose word is a vocabulary word, or a synonym of one (Retire, Drop, Done, Remove,
View...) without `differentMove`; on an own move wearing a vocabulary icon; on one word on two records'
tables (it belongs in the vocabulary); and on either table here disagreeing with the source. It also
runs itself over rows written wrong on purpose, so the check cannot quietly stop checking.

### Every sentence says where you are and what you are looking at

A string pass over the whole UI, in the owner's words "where are they and what are they looking at".
One test per rendered sentence: does it name the PLACE (which Space,
which tracker, which tab) and the THING (cards or issues, file or ledger)? A string that answers
with a word its tracker does not own -- "work item" or "Azure DevOps" on a gh space -- is a D-G13
defect, not a style question. What the pass settled, beside the intro lines and doors it followed:

- **The Issues tab speaks its tracker in every state.** Not set up, failed, empty, filtered: GitHub and
  issues on a gh space, Azure DevOps and ADO work items on an ADO one. The gh header with the
  assignee chip on **me** reads **Issues assigned to me**; an empty closed view says **No closed
  GitHub issues**. The row's pickup is **Make a card** on both.
- **The single dialog's pickup title names the card and its source**: **Card from a GitHub Issue**,
  **Card from an ADO Work Item**.
- **Stats' intro line names what it counts** -- "The repo's GitHub issues, counted"; the Issue Report's spinner is "Counting the GitHub issues...", not "the ledger".
- **Deploys says "No GitHub Actions runs yet"** in the house empty state.
- **The board's repo-filter note** says "no GitHub issue ... the GitHub link" on a gh space.
- **The card list is Active Cards**, the word the UI uses for a card everywhere else; the CLI's `Daily`
  dashboard keeps its own heading.
- **The settings and system surfaces.** The Environment card names the hub and its cards
  (**Hub folder**, **Hub is writable**, **Hub git history**, **Settings files**, **Cards in this Space**), and its tracker row wears the Space's tracker
  (**GitHub**, **Azure DevOps**, or **Tracker** on a Space with none);
  its badge's sentence names the tracker too ("this Space's GitHub answered", never "az CLI, and ADO" on gh;
  `envBadge.ts`, shared with the Build card). The drawer's Configuration says "the Space you are working
  in", not "the active org"; the Space's address is the **Tracker address**, its status hint names both trackers, and sprint awareness speaks of a
  team with no sprints, not "a board with no iterations"; the add/archive row says **Archive Space** and
  its boxes say what goes in them; the restart note names **Agent port** and **Allowed page addresses**,
  not their keys. Test Health is **Test Health**, its foot says "in the X Space", and its empty lines say what is missing. The first-run banner's close button is
  named for what it hides. Read and passed as they stand: the avatar menu (Theme, Space, Settings and
  its links), the drawer's title, the Log card -- named for the `Log` verb it shows -- and the banner's
  **Get Started** (the owner's copy; the slide it sits on names the deck).

`MyWork.test.tsx` holds the Issues tab's states as a table, tracker by state, and asserts no ADO word on
gh soil; `ActionDialog.titles.test.tsx` holds the dialog's titles door by door; `envBadge.test.ts` holds the
Environment card's words by tracker, and `configLabels.test.ts` the Space's address and status.

## The settings drawer

**The connect wizard is a page, `/connect/:slug`** (`src/modules/ado/ConnectPage.tsx`, settings by workflow W2,
D-W12 to D-W17): four steps, each named as whose it is, over ONE verb -- `Connect <slug> -AsJson` reports the
steps and each step is the same verb with one switch through the bridge (`getConnectState` is a POST used as a
query, `connectStep` a mutation that invalidates the report, `/env` and the inventory). Step 1 says the grain: an
Azure DevOps Space is an organisation with projects inside it, a GitHub Space is one repo, no address is your
cards alone. Step 2 shows `az login` / `gh auth login` and a Check again button, never a sign-in of its own.
Step 3 lists what the address holds and writes `-Projects` (ADO) or `-Repo` (GitHub). Step 4 is the sprint
switch. A shipped demo Space's page (the Azure demo, the GitHub demo) adds Make it mine (D-W15); one that
shipped with an address and is still local (the GitHub demo) says so on step 1 and its button reads
Connect. The How do I rows, the Connect card and the connect tips (`connect-github`, `connect-azure`, the
generic one on a local Space of your own) all land here, and the drawer closes when the address changes (App.tsx). `ConnectPage.test.tsx` holds it.

**It opens with "How do I…"** (`src/shell/HowDoI.tsx`, settings by workflow), then the theme, then the
granular keys -- a descent, and the theme is the divider on purpose (D-W18; the owner: "I like you use theme as
natural divider between workflows and granular settings"): every question of
`Config/settings-workflows.json` -- imported through the `@workflows` alias, the `@consts` shape -- as a
row with the CLI's state word (`on` / `off` / `not configured`, from `GET /api/surfaces`, never
re-derived here), one sentence, and the door: **Change** opens the drawer at the entry's anchor with
the active Space filled in (`spaces.{slug}.org`), **Set it up** is a journey's door (its own page when it has one -- the connect
wizard above -- else the drawer at the journey's first key), and a sentence has no button. The tooltip
carries the key and the CLI line. The section FOLDS when the drawer opened at an anchor (D-W11), so a
deep link lands on its row; the fold is a button. The tips at the foot of Home draw from the same
list: an entry with a `tip` is offered while every surface it names reads `not configured`
(`tippableEntries`, `src/shell/settingsWorkflows.ts`). `HowDoI.test.tsx` and
`settingsWorkflows.test.ts` hold it; `tkTestToolkit -Environment` holds the other half of the parity.

**The avatar in the nav bar opens it.** `src/shell/SettingsDrawer.tsx` is the Toolkit's one settings
surface: a Fluent `OverlayDrawer` on the right at every width, so the same component reads as a
drawer on a tablet and as a blade on a desktop. The model is the wasteland's settings drawer, taken
as written wherever the reasoning carries:

- a scrim click or Escape closes it -- a settings panel never traps you;
- body scroll is locked while it is open, restoring whatever value was there. It is the real fix
  for the scrollbar-width sliver a fixed drawer otherwise leaves at its edge;
- the surface is the page's own two layers (flat base, translucent gradient) plus a left border,
  so it reads as the same room sliding open rather than a lighter panel pasted over it;
- 460px, never wider than the viewport. The wasteland's 320px holds a switch and a sentence; this
  one has to hold a label, a source badge and a control on one row.

The avatar is a real button -- focusable, `aria-label="Settings"`, `aria-expanded`, a ring while
the drawer is open -- and closing hands focus back to it (`useRestoreFocusTarget` in `App.tsx`,
`useRestoreFocusSource` in the drawer). Without that pair Escape drops focus on `<body>`.

It is a frame, not a settings framework: each section keeps owning its own storage, and this is
only where they surface.

**The Face card is NOT in it, on purpose.** The drawer holds what you *configure*; the faces are for
fun, and `FacePicker` is drawn by the Lounge (spec D-L24).

## Intro text

**A line that explains a page is `Body1` (14px) with `spacingVerticalL spacingHorizontalS` of padding
-- 1rem and 0.5rem.** The owner's rule: "the general rule is Body1 for these intro texts or
14px and same padding." Three lines are this: the one above the board's lanes (`Board.tsx`,
`barText`), the one under Home's tabs (`routes.tsx`, `explain`, one per tab), and the one at the foot
of a local org's Home (`connectLine`, which becomes the tips row).

Fluent's `Link` draws at 14px whatever the sentence around it does, so a `Caption1` intro line puts
two sizes on one row. **The size comes from the typography component, never from a number** -- `Body1`, not
`fontSize: "14px"` -- and the padding from the spacing tokens, which are exactly those values.

`Caption1` (12px) keeps the jobs it is good at: a label under a heading, a card's metadata, a pager's
words, a lane's one-line hint (indented `spacingHorizontalL` under its lane title, so it reads as a
sentence about the lane rather than a second heading).

## Themes

A theme is like a Face: not a setting to get right but a mood to pick. So there is a **flat list of
named themes**, each dark or light, and **no "Auto"** -- you choose by where you are sitting, not by
what the operating system says. (A browser that has never chosen follows the system, until it does.)

| Dark | | Light | |
| --- | --- | --- | --- |
| **Atlantis** | glass -- blue into teal | **Seaglass** | glass -- teal into lilac (the original light) |
| **Aurora** | glass -- violet and green (the original dark) | **Sunny** | glass -- warm cream |
| **Basement** | flat -- charcoal, one amber lamp | **Office** | flat -- paper, one teal accent |

Two **kinds**, because both are wanted. *Glass* is translucent cards over a gradient and paper grain.
*Flat* is opaque cards on a plain page: functional, classic, right for a projector. Every card in the
app is `colorNeutralBackgroundAlpha` (`shared/PageCard.tsx`), so that one token is the whole
difference -- no component knows which kind it is in.

**Every theme keeps its own accent.** Atlantis's cyan, Basement's amber lamp, Office's teal: the
accent is part of the mood, and a theme is its page, its grain, its cards and its accent together.
The product's own accent (rose, below) is worn in exactly two places, the landing page and the
wordmark's default blob, and by no theme.

- **`shell/themeList.ts`** is the themes as data: name, mode, kind, page colour and gradient, grain,
  the logo's colour, the card, five accent colours. It imports nothing from Fluent, because
  `useCurrentTheme` reads it and that hook is pulled into vite-node by the deck voice-bake.
  **Adding a theme is adding a record**, and checking three things by eye: white on the primary
  button (a test holds it to AA), links on a card, and the logo's word over its face. A fourth is
  held by number: `brand.foreground2` is a brand tint badge's text, and `themeList.test.ts` holds it
  to AA on the ramp's tint background in every theme. The same file snapshots every named theme --
  its record and the whole Fluent theme made of it -- against `shell/fixtures/themes-93d9d88.json`,
  the themes as they were in 1.4.0, so a theme changes only on purpose (regenerate the fixture and
  say so in the commit).
- **`shell/theme.ts`** makes a record into a Fluent theme. Fluent derives some forty tokens from a
  sixteen-step brand ramp; overriding the five obvious ones left the rest Fluent's blue, so the ramp
  is generated from the theme's accent (`brandRamp`) and the five are set on top.
- **`shared/accent.ts`** is the product's accent, and the one place it is typed. One key colour,
  `ACCENT_KEY` (rose, `#c0285e`), is the ramp's 80, and `accentRamp` generates the other fifteen
  steps from it, dark at 10 and light at 160, in OKLCH -- no step is edited by hand; wine is its
  deep end. Where it shows reads the ramp by mode (`ACCENT_STEPS`); the landing page and the
  wordmark's default wear the dark steps: the face is the 40 (wine), the dots and links the 110, the
  call to action the key, its text the page's own ink chosen by `readableOn` (4.63:1). Change
  `ACCENT_KEY` and the landing page and the default wordmark change together, and nothing else;
  `accent.test.ts` holds the ramp's shape, that every landing accent property follows the key (it
  builds the page's properties from a cyan ramp and checks each), that no app theme wears a step of
  the ramp, and that no ramp hex is typed anywhere else in `src/`. The app's own logo wears the
  worn theme's `logo`, not this.
- **`shell/ThemePicker.tsx`** is the first section of the settings drawer -- the shell's own, above
  the modules'. **Choosing is the preview**: it applies at once and there is nothing to save. A theme
  is this browser's preference (`localStorage["toolkit-theme"]`, the theme's id), never config, so
  it is outside the drawer's batched Save and never reports "unsaved". A browser that refuses
  storage (a private window with site data blocked) still takes the choice: it holds for the
  session and is gone on reload. The old values `dark` and
  `light` still mean Aurora and Seaglass.
- `useWornTheme()` is what a chart, a face, a card -- ANY consumer -- reads: `theme` (`"dark" |
  "light"`), `active` (the theme record actually on screen: the chosen theme, or the worn skin's own
  record while a grant is on) and `setThemeId`. `useCurrentTheme()` is the store's own hook, the
  chosen theme with no skin over it; only the ThemePicker, the avatar menu and `useWornTheme` call
  it, and `hooks/useWornTheme.test.ts` fails any other caller -- the skin owns the palette
  everywhere (D-L22; the face picker under a skin was the first drift). The deck stage is
  always dark and asks for its theme by name.

## The shell's frame

- **Landmarks.** `<header>`, `<nav aria-label="Main">`, `<main id="main">`, and a **Skip to content**
  link that is the first Tab stop on every page.
- **One element per nav item**: a Fluent `Button as="a"` with `aria-current="page"` -- one tab stop,
  not a `Button` inside a `Link`. A plain click routes in place; a modified click
  opens a tab, as a link should.
- **Home is the Space anchor, not a tab**: `SpaceAnchor.tsx` draws the core module's first
  nav entry (`moduleNavSplit` in the registry) as one pill after the wordmark -- a home icon and the
  Space's display name, else its slug, else `Home` -- that goes Home and wears the tabs' active
  treatment there, with `name · slug · address` in its tooltip and the face truncated on a phone. A
  1px rule in the theme's stroke follows it, then the engineer's tabs; the data model still lists Home.
- **A title per page**, from the nav entry that owns the path: `Daily · ToolKit`. A path with no
  entry is just `ToolKit`.
- **The header holds what is true on every page** -- brand, org, nav, you; no pager. System's pager is under its cards, with words ("Cards, page
  1 of 3"), from `pager` on the shell context. Home has no pager: it has named tabs (below).
- **Home is named tabs -- Focus | Board | Sprint | Actions** on an Azure DevOps Space, and on a
  GitHub space the strip wears that tracker's words and its own order: **Issues | Board | Stats |
  Design | Docs** (Sprint is an ADO word; the issues come first because the board ceremony is optional on a
  GitHub space, so the issues are what the space is for). `HOME_TABS` in the registry is the
  list, and `homeTabLabel` and `homeTabOrder` decide the word and the order; ids never change. A home
  card belongs to ONE tab, by declaration: `homeTabs` on `ToolkitModule` (cards with no tab, from
  `homeCards`, land on Focus), grouped by `moduleHomeTabs` in the tracker's order, and the ADO
  module's membership is `homeTabPlan` in `modules/ado/homeTabs.ts` -- data, pinned by a
  tier-by-status table; a gh space plans status on the Board, the issue list on Issues and the Report
  on Stats, and no ADO card or word crosses in; its Board tab always draws the BOARD, and there is no
  list view on gh (`homeViewFor`, beside the `local` rule: the list reads worse than the board).
  **Each tab is an address** -- `/`, `/board`, `/backlog`, `/sprint`, `/actions`, `/design`, `/docs` -- so a
  tab can be linked and Back walks between them; there is no memory of the last tab. **`/` is the
  strip's first tab**: on a GitHub space Home lands on the Issues, and the Board keeps `/board`;
  everywhere else `/` is Focus.
- **The Issues tab reads the whole ledger**: three chip groups -- in the filter
  drawer, see the next bullet -- three controls, never one -- **state** `[all issues] [open] [closed]`, **assignee**
  `[assigned to all] [me]`, and **worked by** `[all] [opus] [fable] [sonnet]`. State and assignee are
  asked of the agent (`GET /api/work-items?state=&all=`, the path from `issueAxes.ts`); worked by
  filters the answered list. The default is open, assigned to all -- and **closed or all issues is the opt-in** that pulls the closed ones. Each choice is
  remembered per browser (`useSharedPersistedValue`, keys `ado.issues.state|assignee|worker`). The worker
  chips are the worker labels the list carries -- the agent reads a worker from a label whose
  description starts `Routed to`, so a fourth is a label away -- with opus, fable, sonnet first in that
  order; a remembered worker the list no longer carries reads as all. Every row wears its worker's
  label and, when closed, `closed <date>`; closed rows sort after open ones, newest-closed first, and
  open the reading room like any other. `MyWork.test.tsx`, "the Issues tab's chip groups".
- **The filter drawer carries the Issues filters.** In the owner's words: *"there is no reason why
  GitHub issues tags and filters not live in here -- we cannot have ADO and Issues in the same space and
  so it is conditional logic."* The drawer is built of SECTIONS, and `drawerSections(env, tab)` in
  `homeTabs.ts` names them per tab by the drawer's own rule one level down -- a section shows only where
  it reaches a card: **search** on any filterable tab; **cards** (ToolKit's type, tracker-link and lane
  rows) wherever cards are drawn, on every tracker; **ado** (the org's projects, the repo row -- it
  matches a card's ADO link) on an Azure DevOps Space only, so the GitHub Board never shows it; and
  **issues** on a GitHub Space's Issues tab: `IssueFilterRows.tsx`, the Issues tab's chip groups (state,
  assignee, worked by) and GitHub's labels as rows (kind, severity, milestone). The Issues tab's drawer holds no card row, since none reaches an issue.
  **One place for the chips**: the list does not draw them; it says what the drawer is set to in one
  line under its header (`issueFilterSummary`: `open issues · assigned to all · sev2`), above an empty
  list too, so a filter that hid everything is named where it bites and undone in the drawer. The
  choices are held once for both readers (`useIssueChoices`, over `useSharedPersistedValue` -- the
  per-browser value that tells every holder of its key when it changes), so kind, sev and milestone are
  remembered per browser like the chips. **Search includes the Issues**: on that tab the box reads
  "Issue number, title or label", a number is that issue only (`12`, with or without its `#`, never 112 -- an id is not a
  substring), and words match the title, the labels, the worker and the milestone in any order
  (`issueMatches`). The shell's lane and repo filters are card filters with no control on the Issues
  tab, so they do not reach the GitHub list: a lane chosen on the Board cannot silently empty the
  Issues. Stats, Design and Docs have no section yet -- a section for them is a name in `drawerSections` and
  a branch in `FilterDrawer`. `homeTabs.test.ts` ("drawerSections"), `FilterDrawer.test.tsx`,
  `MyWork.test.tsx` ("the Issues filters, in the drawer").
- **An issue can be pinned -- the tracker's own pin.** The row reads `pinned` from
  `GET /api/work-items` (GitHub's `isPinned`), so a pin set on github.com or on the other machine shows
  here, and "stays pinned" needs no store of ours. Pinned rows sort first **within what the chips
  show** (`pinnedFirst` in `issueAxes.ts`, applied after the filters: a pinned issue routed to Opus is
  not under Sonnet). A pinned row wears a pin and **Pinned on GitHub** where a closed row wears its
  date -- the tracker's NAME from `trackerName` (`TrackerBadge.tsx`), never a literal, so a second
  tracker with a pin would say its own. The row's menu reads **Pin on GitHub** or **Unpin**, before the
  external link, through `POST /api/cmd/EditItem` (`-Pin` / `-Unpin`, `buildEditWorkItemParams`), which
  invalidates the list; a closed issue still pinned keeps its Unpin. A refusal -- GitHub's fourth pin
  among them -- is the verb's own sentence in the card's toast slot; nothing in the row moves or grows
  while the write runs, the refetch is what moves it. The reading room says **Pinned on GitHub** beside
  the state and carries the same Pin / Unpin in its header controls. An ADO row has no pin.
  `MyWork.test.tsx`, "a pinned issue"; `IssueDetailPage.test.tsx`.
- **A card whose issue is pinned says so on the Board.** The agent serves `pinned`
  on the card (`GET /api/status`, GitHub Space at Tier 1 only); the Board's card face wears the pin and
  **Pinned on GitHub** (the name from `trackerName()`) in its meta line, so the card keeps its box, and
  `byLane` puts pinned cards first within a lane, each group in the order it had. Read only: Pin and
  Unpin stay on the Issues row and the reading room, and an `EditItem` that pins or unpins
  invalidates the `Status` tag so the cards refetch. A pinned issue with no card stays on the Issues
  tab. `Board.pinned.test.tsx`, `api.ado.tags.test.ts`.
- **The Board's and the Design tab's intro sentences name what they are.** The Board says
  "ToolKit cards move by themselves: ..." on every Space and, on a tracker Space, ends with where a card
  comes from ("An issue gets a card from the Issues tab: Make a card."; Azure DevOps: "A work item gets a
  card from the Focus tab: Make a card."). A GitHub Space's intro lines are functions of the tracker's
  name (`ghExplain.ts`), so the Design and Docs lines' "GitHub" is read from the Space, not typed.
- **Stats has a Milestones card on a GitHub Space**: `MilestonesCard.tsx`, beside
  the Issue Report and before Deploys in `homeTabPlan`'s GitHub branch at Tier 1, so an ADO or local
  Space never mounts it and nothing fetches `GET /api/milestones` there. One `StatTiles` row -- reached,
  in flight, issues left, the shared `StatTile` -- then one row per milestone: title, a Fluent
  `ProgressBar` (closed of total), the two counts, the due date, the state words, and Open on GitHub
  last. The rules are pure, in `milestones.ts`: `orderMilestones` (in flight most complete first, then
  reached -- still open on GitHub first, then newest closed -- then empty) and `milestoneStateWords`
  ("reached, not closed", `closed <date>`). No milestones is the shared empty state, saying they are
  made on GitHub. It reads the `Issues` tag, so a close or an edit through the bridge refetches it.
  `MilestonesCard.test.tsx` pins the order, the tiles and the sentence against this repo's own seven.
- **A GitHub Space has a Design tab** (Studio S2, D-S11): `design` in `HOME_TABS`, filled
  only by `homeTabPlan`'s GitHub branch at Tier 1, so an ADO or local Space never shows it -- no flag,
  it is the core's tab. `DesignList.tsx` lists `GET /api/design` in the agent's order, the repo's
  `design/` then `spec/`: each row the house row (title as text, **Open the document** exposed, the menu
  holding *Open the thread* when the file names one and then *Open on GitHub*), with the frontmatter
  description, the folder and the thread's `#n`. `/design/:folder/:name` is `DesignDocPage.tsx`, the
  house reading page -- `PageCard`, `BackButton`, compact header controls and ONE `MarkdownViewer`
  holding the document and then its thread (`designDocument`, reusing the issue page's
  `issueDocument` over `GET /api/issue/{n}`). The thread is read only when it lives in the Space's own
  repo -- the issue route resolves its repo among the Space's, so another repo's would be the wrong
  issue -- and is linked from the header either way. `DesignList.test.tsx` pins both. The room hands
  the viewer the document's place in the repo (`repoLinkBase`), so a spec's link to its design note
  opens the note here -- the same resolver the Docs tab uses, below.
- **A card and its design, both ways** (the Toolkit card's C3; `DesignBindings.tsx`). The card page
  draws the card's `design` -- the agent's parse of its `> Design:` line, the id resolved -- as a chip under
  the file path: the short id and the title, the design's state badge when the agent read it, and a click
  into the design's reading room (`/studio/design/<path>` for a hub design, `/design/<folder>/<name>` for a
  repo's). Unresolved, it is the line as last written: the short id and the title, a GitHub link opening
  github.com, the tooltip saying it was not read. A hand-written `> Spec:` line shows its title and its words,
  with no id. Every design row -- the Design tab's and Hub Designs' -- ends with `BoundCards`: `N cards`, each
  card's id and state, a click opening the card when it is in the Space you are in and not archived,
  another Space's named with its slug in brackets. Nothing reads the line here; the agent serves it parsed.
  `DesignBindings.test.tsx` pins the rooms, the words, the chip and the cards.
- **A GitHub Space has a Docs tab, last** (D-S12): `docs` in `HOME_TABS`, filled by
  `homeTabPlan`'s GitHub branch at Tier 1 beside Design -- the same gate, so Tier 2, an ADO and a
  local Space never show it. `DocsLanding.tsx` is the tab: the house detail page -- `PageCard`, the
  README's title and the repo on the left, Refresh then **Open on GitHub** last on the right, ONE
  `MarkdownViewer` holding `README.md` -- with everything under `docs/` folded above the text
  (`DocsTree`, a `<details>`, closed, so nothing moves until it is asked for). `/docs/*` is
  `DocsDocPage.tsx`, one document's room, its repo path after the prefix (`/docs/docs/CLI.md`); the
  same frame with `BackButton`. Between documents the room keeps the one it has until the next
  arrives, then swaps the text in place -- no spinner, no jump -- and starts at the top unless the
  address carries an anchor.
- **Where a link in a repo's document goes is decided ONCE**, in `shared/docLinks.ts`, used by
  the shared viewer's `a` and `img` (`shared/DocLink.tsx`). A page that mounts the viewer for a repo
  file passes `links` -- a `DocLinkBase`: the document's own repo path and three answers about a repo
  path (`roomFor`, `assetFor`, `outside`), built by `repoLinkBase` in `modules/ado/docRooms.ts`.
  Then: a relative `.md` link with a room opens it in the app, its `#anchor` kept (`room`); a
  `#anchor` scrolls this page (`anchor`); an absolute link leaves in a new tab, as ever, and so does
  a relative link to a repo file with no room (`AGENTS.md`, `VERIFY.md`) -- on github.com, with a
  hover title that says it is not one of the documents this room reads (`out`). A relative image is
  served from `/api/docs/asset/<path>` wherever the repository keeps it (a root path `/x.png` is
  the repository root; one that climbs out of the repository is never asked for), and from
  github.com's raw view only when the path rule refuses its name. Given `issues` (the agent's
  `DocDetail.issues`), the base also opens an issue of the repository in its room
  (`issueRoomPath`), and the viewer adds `remarkIssueLinks` (`shared/issueLinks.ts`, through
  `markdownPluginsWithIssues`) so a `#N` in the prose is that link -- never inside a code span, a
  code block or a link's own text. Which paths are docs is the contract's (`consts.json` `docs`, `DOCS` in
  `shell/consts.ts`), held to the agent's rule by the shared table `Tests/fixtures/docs/paths.json`.
  With `links` given, every heading wears the id **github.com** gives it (`githubSlug`,
  `headingIdsOf` in `prepareMarkdown.ts`: punctuation dropped, spaces to hyphens, a repeat `-1`), so
  the anchors the docs were written with land; a card keeps the house's ids. With no `links` -- a
  card, an issue -- a link behaves as it always did, except that a `#anchor` now scrolls instead of
  opening a tab. `docLinks.test.ts`, `DocLink.test.tsx`, `docRooms.test.ts`, `DocsLanding.test.tsx`
  and `prepareMarkdown.test.ts` ("GitHub's heading ids") pin it.
- **An issue gets the reading room**: on a gh space an Issues row's one exposed action,
  **Open the issue**, goes to `/issue/:num` (repo hint riding along). The row is the house row:
  the title is text, not a link, and the menu holds Make a card, Close issue, the pin
  (Pin on GitHub / Unpin) and then Open on GitHub -- consistency over the shortcut a linked title would be. An ADO row, with no
  reading room, still exposes Open in ADO. The page shows the body, the thread under it, then
  the timeline's high signal (commits, the linked PR, cross-refs) from `GET /api/issue/{number}`. **It is the
  house reading page, not a page of its own**: `PageCard`, `BackButton` and the title
  (badges and the issue's link under it, through `FilePath`, the line every detail page carries) on
  the left, every control on the right and compact as the 1:1 page's are -- severity, then Close
  issue, Pin / Unpin and Open on GitHub as icons with a title, Make a card the one with words, Refresh last -- and ONE `MarkdownViewer` holding body, thread and timeline as one document
  (`issueDocument`), so the page has one zoom, one "On this page" top right, one Top. Read, then act, one place: Make a card and
  Close issue open the same ActionDialog the rows use, so the bridge stays the one writer; Open on
  GitHub stays the escape hatch, never the requirement. An ADO space never links in -- the route answers
  `supported: false` and the page says so. **An empty tab is absent**, and **fewer than two tabs is no strip**: an
  archived org's retrospective is all Focus, a `local` org has only the Board (Sprint follows Azure DevOps),
  and an address for a tab Home lacks goes to `/`. Under the strip, each tab has one line saying what it
  is for; on Focus the line ends with **New card**, which is also in Active Cards' footer. The
  filter drawer shows only on a tab that holds a card it reaches (`homeTabs.ts`'s
  `drawerSections(...).length > 0`, over the same plan that decides which
  cards are on the tab) -- Focus,
  ordinarily, and on a GitHub space also Issues, since that is where My Work lives there; Sprint and
  Actions hold no card the drawer's filters change, so it is absent, not merely inert.
- **The tab names the page; the page says what it holds.** The Daily tab's page is `/daily` and is
  headed "Daily Activity" -- the page is a record of activity, not a day; `/billing` redirects to
  it. The subtitle carries the one rule true of every hub -- the cards'
  dates decide -- and the sentence under the week (`billingNote`) carries what is conditional on the
  week that was built: whether git enriched it, and which cards were left off. A CLI instruction in
  the GUI uses the machine's prefix (`env.cliPrefix`).

## The avatar menu, and arriving at a setting

The avatar is "me and my settings": a menu (`shell/AvatarMenu.tsx`) rather than one long drawer to
hunt through -- in the owner's words, *"find a way to get the user there when they want to make a change."*

- **What changes often happens in the menu** and never opens the drawer: **Theme** (a submenu that
  stays open, so you can try one after another with the page changing behind it) and
  **Space** (shown when there is more than one). Up to `SPACE_QUICK_MENU_THRESHOLD` (8, in
  `shell/SpaceQuickMenu.tsx`) Spaces it is a plain submenu; past it, the same entry opens a **quick
  menu** -- the searchable switcher of GitHub's branch picker and Slack's workspace list. The
  box takes the focus and narrows by display name or slug (case-insensitive, anywhere in it); with
  nothing typed it shows the active Space first, checked, then the rest in declaration order, capped
  at the threshold, and **View all** at the foot lists every Space in the same box. Up/Down move the
  highlight, Enter or a click switches through the same call as the submenu, Escape closes it and
  hands focus back to the Space entry. The panel's width and the list's height are fixed (the list
  scrolls), so nothing moves as you type, and an empty result says `No Space matches '<text>'` in the
  list's place. It is ARIA's combobox-with-listbox: the box keeps the focus and points at the
  highlighted row with `aria-activedescendant`. No recency: the order is the config's.
- **Everything else is a destination.** A module lists places in its settings a person might want to
  go -- `settingsLinks: () => [{ label, anchor }]` on `ToolkitModule`, gated by its flag like
  everything else -- and its section marks the matching element `data-settings-anchor="<anchor>"`.
  The shell names no setting. The ADO core lists *This organisation*, *Modules* and *Shortcuts*;
  every row is also marked with its own config key.
- **`useOpenSettings()`** (from `shell/cards`) gives any page that REPORTS a setting the way to the
  place that changes it: `openSettings(anchor?)`. The Environment card's rows use it -- Identity to
  your email, Hub folder to the hub folder setting, a module's row to its switch. "That page is switched off" uses it to land on
  that module's switch. The drawer scrolls the place to the top, puts focus in its first control,
  and washes it with the accent for a moment (`prefers-reduced-motion` respected). Rows come from a
  query, so it looks for the place for three seconds and then stays quietly at the top: an anchor
  nobody marks is not an error.
- The unsaved dot and count stay on the avatar, and Escape from the drawer returns focus to it.

## What the shell says for itself

Two sentences no module can say, both in `src/shell/ShellStates.tsx`, where a blank page would
otherwise be.

Before either, the first load draws `src/shell/BootSpinner.tsx`: a progressbar named "Loading toolkit...", so
a screen reader says what the page is waiting for.

**The agent is not there.** The shell polls `GET /api/health` -- every 15s, every 4s while it fails.
If `/env` has never loaded, the routes are replaced by one panel: what is wrong, the command that
fixes it, and "this page fills in by itself", which it does, with no reload. If the agent is lost
mid-session, a banner sits over the last-known page and says nothing can be saved. The command is
`{prefix}Agent`, and the prefix is the last `cliPrefix` that `/env` served, remembered in
`localStorage` -- config comes from the agent, which is the thing that is down. A browser that never
heard one names the verb and points at the quick start. **A card must still tell a failed load from
an empty answer**: Daily said "No billing activity found" for a week it had not read.

**There is no such page.** A `path="*"` route. `dormantOwner()` in the registry hands back the
switched-off module that owns the path, so a bookmark to `/growth` with growth off says "That page is
switched off" and opens Settings, and a stray address says "There is no page here". The shell still
names no module.

## The board

`modules/ado/Board.tsx`. The same cards as the list, arranged by where they ARE -- in the owner's words, "cards
are prompts, and agile lanes are a better view for how multiple items flow for human development."

- **Where it lives.** The Board is a TAB of Home (the owner: "remove the toggle ... instead
  have in-page tabs: Focus | Board | Sprint | Actions"). **Focus** is the list -- "local cards and prompts",
  the card grid Home has always been -- and **Board** is the same cards as lanes; each is an address
  (`/`, `/board`), so a tab can be bookmarked, demoed or landed on, and nothing is remembered per
  browser: the address says which. The component knows nothing about where it is
  mounted ("a component that is just a route -- if it doesn't feel right, we move it"), so moving it is
  `AdoHome` and one line of the route table. **One view at a time:** on the Board tab Home shows the
  lanes and NOTHING else -- not the lanes above the worklists. The owner: "you toggle views, ADO
  or sprint lanes -- seeing both [is] too much ... users have limited ability to track things -- RAM."
  No layout, setting or split mode may put the two on screen together.
- **Which tabs a space has is the tab plan's business** (`homeTabPlan`, `modules/ado/homeTabs.ts`), and
  it carries the `homeViewFor` rule: an org with no Azure DevOps has one view, and it
  is the board -- the owner: "if you don't have ADO do you even need to see the other view -- no."
  The list is the ADO worklist; without ADO it is the same cards drawn worse, beside a PR-comments
  card that can never fill. So a `local` space plans the Board alone (one tab, no strip), a GitHub space
  Issues | Board | Stats, a connected ADO space Focus | Board | Sprint | Actions, and an archived space
  its retrospective cards with no board, since nothing is in flight. Under a board-only Home the foot's
  tip carries the connect invitation -- its CTA opens Settings at the org, and plugging ADO in is what
  brings Focus. Because the board can be the ONLY view, **New card** is on the board's bar too.
- **The foot of every Home tab is the tips row** -- `shared/Tips.tsx`, in all orgs: a 24px brand-colored lightbulb,
  a **Tips:** label (`Body1Strong`), one sentence (`Body1`), and one CTA drawn as a link that DOES the
  thing (never a help page; optional, for a tip whose instruction is the sentence). Not a container:
  no card, no border, no fill -- the icon is the anchor, so the line stays peripheral enough to live
  there forever. There is no off switch, on purpose. Each tip's condition is a synchronous read of `/env`, and a tip retires by DOING --
  make a second board and the boards tip has nothing to say; nothing is written anywhere. With several
  eligible, one shows per visit and the next visit shows the next (decided once per mount, advanced
  once per session, nothing persisted -- a refetch cannot re-roll the line). Nothing shows at the foot
  until the first-run banner has been answered, and the gate is the SLOT being empty, not
  `firstRunWelcome` -- with deck off no banner ever renders or clears the flag, and the tips must not
  wait on it.
- **Lanes are the derived states** -- Active, In Progress, Code Review, Done -- from the contract's status
  vocabulary (`legalMoves.ts` `LANES`). Nothing is written to a card to put it in a lane. At the minimum
  deliverable there is no planning and no backlog (D-C12).
- **It owns no server state -- it is RTK Query's.** It reads the SAME cache entry the list reads
  (`getStatus`), so the two cannot disagree and opening the board costs no second fetch (measured: 0). It
  polls that entry while mounted (`pollingInterval` 15s, `skipPollingIfUnfocused`), because the point of
  the board is that cards move BY THEMSELVES and a board that needs a reload to notice is a poster. Its
  one write is the existing `archivePrompt` mutation, whose `invalidatesTags: ["Status"]` refetches.
  **No optimistic update and no local copy of a card**: state is derived from the file, so a card moves
  when the file says it has, and a refusal leaves it exactly where it was, with the CLI's own sentence.
- **One move a person makes**: drop a card on Done, or **Move to Done** from the card's menu -- confirm, then
  `Archive` through the bridge. `legalMoves(state)` is one pure function that drives BOTH the drop target
  and the menu, so they cannot disagree; the other lanes are not targets and say why ("Entered by a
  commit, not by hand"). HTML5 drag and drop, no new dependency. The menu is mandatory: a board that only
  works by dragging is closed to a keyboard and to a touch screen. The outcome is announced (`aria-live`).
- **One set of predicates** (`promptFilters.ts`), lifted out of `PromptStatus.tsx` and used by the list and
  the board, plus a Sprint filter on the board. A card with no ADO link cannot match the repo filter, so
  the board SAYS how many it hid rather than letting them vanish.
- **Finding a card that is not code work.** The one box is dual entry -- an exact card id first, then a
  substring of the file, the title or the link -- and the **words typed in any order**, so `angular
  signals` finds "Signals in Angular"; no typo tolerance, because on a 250-file corpus a loose match mostly
  produces false hits. Its placeholder says what it matches (`Card id, title or file`), not Azure DevOps's `Work Item ID`. A **type row** -- one badge per
  configured type in config's order, then any type a card names that config does not, then **Untyped** for
  a card whose heading names no configured type -- **counted from the cards on screen** (`typeRowOf`, over
  the same `/api/status` the list reads), never from config. Type is a coarse cut, not a way to find one
  card: the measured payoff is "hide the half that are Bugs". Untyped is its own badge and inside All; only
  an active badge ever hides a card. A **linkedness row** -- **All / Linked / Custom** --
  answers the question a mixed Space raises: which cards have a tracker's ledger behind them? It reads the
  card model's `linked` (the agent's one tracker-link rule; the web parses no link) and never asks WHICH
  tracker. It is drawn only in a MIXED Space: where every card is custom -- every `local` Space -- or every
  card is linked, it would be one badge equal to All and one at 0, so it is absent, unless a Linked or
  Custom filter is still active, which keeps the way back (`showLinkRow`; D-C15). Its sibling answers "which is which": **a card badges its tracker** -- **gh** or **ado**,
  first in the list row's meta line and on the board's card face, and nothing on a custom card. The agent
  serves the card model's `tracker` (the tracker rule over the card's OWN link, never the Space's
  address), and `TrackerBadge.tsx` is the one chip for it -- the Issues tab's rows wear the same one. And
  **the repo row's rule is stated**: it appears only when the org
  declares projects -- an Azure DevOps org -- and `unlinkedHiddenByRepo` keeps saying how many cards it hid.
  Left alone on purpose: the repo row's counts count configuration, and the
  state row mixes two vocabularies.
- **A second write, and it is not a move**: a card's menu also offers **Mark not billable** / **Make billable
  again** -- `setBillable`, a form over the CLI's `Billable` verb, shared with the Home list through
  `useBillableToggle`. It invalidates `Status` AND `Billing`, so the mark on the card and the week on Daily
  both come from the refetch; `archivePrompt` invalidates `Billing` too, because a Closed stamp is a day on
  Daily. A card says **Not billable** only when it is the exception.
- **Azure DevOps is something you plug in.** `/env` serves `ado: { enabled, explicit }` -- derived by the agent
  (`features.ado`, else the status of the org you are in) and never re-derived here. Where it is not in use
  the New card dialog has no source tabs at all, only "what is it called"; an agent too old to say reads as
  in use. In Settings the flag is labelled **Azure DevOps**, and because
  its usual answer is UNSET the switch shows what is in effect -- "off -- following this organisation" --
  rather than a bare "off" beside a tracker that is plainly working (`FieldRow`'s `effective`).
  [`../docs/modules/ado.md`](../docs/modules/ado.md) is the add-on end to end.
- **A person may move a card to any lane ahead of it, and the drop writes the line.** Every lane has
  two writers: git's token, and a person's. `legalMoves(state)` is every lane AHEAD of the
  card; dropping on In Progress or Code Review runs the `Move` verb through the bridge (`moveCard`,
  `buildMoveParams`), which writes `**Started:**` or `**Review:**` into the file, and the refetch moves the
  card; dropping on Done still asks first and archives. Lanes behind a card are not targets ("a card
  travels one way"), and `laneHint(lane)` under each heading says who puts a card there. No optimistic
  update: the file is the record, and the board is one more thing that writes a line.
- **One action model for a card, in both views.** What a card offers is ONE pure
  function, `cardActions(card, { adoEnabled, cliPrefix, laneLabel })` in `modules/ado/cardActions.ts`, which
  names each answer's move from the vocabulary, and ONE renderer, `CardActionMenu.tsx`, which gives each
  answer a handler and hands it to `shared/CardActions`. The Home list's row and the board's card both draw it, so they cannot offer
  different things; the board keeps no `Menu` of its own. It answers on three axes -- the card's
  kind (`linked`), its state (the lane, `pr_url`, `commits`) and whether Azure DevOps is in use (`/env`
  `ado.enabled`) -- with the rule `sendButton.ts` draws: **absent** when the action cannot apply to this
  card at all, **disabled with a reason** (`CardAction.whyNot`, drawn as the menu item's `secondaryContent`
  and in the exposed button's tooltip) when it applies but not yet. The primary is *Open the card*. The
  menu: *Move to* each lane ahead (from `legalMoves`; the lanes behind are present, disabled, "A card
  travels one way."), *Archive (move to Done)* -- which asks first, in both views -- then *Create PR*, the
  billable toggle, *Remind me about this* while organize is on, and last *Open on GitHub* or *Open on
  Azure DevOps*, absent on a card with no work item and whenever ADO is off. **Create PR** is
  absent with ADO off, on a card with no work item and on a Done card; disabled while the file records no
  commit bullet ("thread them with `{prefix}ThreadHash` first" -- `commits` is served by the agent, and a
  `**Started:**` line is not a commit) or when a `PR URL:` is already there; otherwise it opens the Create
  PR dialog on its `pr` tab, where the work item id is TYPED -- the deliberate step, not pre-filled. The list's move writes through the same `moveCard` mutation as a drop on the board: no
  optimistic update, and a refusal is the verb's own sentence in the row's `StatusMessage`.
  `cardActions.test.ts` is the table -- one row per kind x state x ADO on/off.
- **The lanes are called what the org calls them.** `useLaneLabel()` maps a contract word to the org's
  display name from `/env` `config.laneNames` (`laneLabel`, pure and tested); the headings, the menu, the
  list's status badge and the filter's chips all print it, and the contract word is still what is
  compared. Demo reads To do / Doing / Waiting / Done; an org that says nothing reads the contract's words.
- **The tab row spans the centre block, flush both ends.** Home's row above the cards (`viewBar`: flex,
  space-between) has the tabs at its left edge, level with the cards below. **New card
  follows the explain text** on both rows: on the board, after the sprint filter, at the row's end; the
  text wraps inside itself so the buttons keep the row. The System page keeps its pager under the grid.
- **The board owns the height; a lane scrolls inside itself.** The owner: "they all expand to fill the
  space; if I have 20 cards in a single lane each lane has overflow-y." The lanes grid is
  `clamp(360px, 100vh - 290px, 1100px)` tall with `align-items: stretch`, so every lane is the same height
  whatever it holds; the lane head and its one-line rule stay put, and only the card list (`laneCards`,
  `flex: 1 1 auto; min-height: 0; overflow-y: auto`) scrolls. Measured with 20 cards in Active: the page is
  exactly the viewport tall on a laptop, the lanes 610px, the list scrolling; on a phone the lanes are 554px.
  One busy lane does not make the page as tall as its longest column, and there is no pagination.
- Empty lanes use `EmptyState`; under ~1000px the lanes scroll sideways INSIDE the board and the page
  never overflows; tokens only, checked in Seaglass and Basement.
- **A lane's scrollbar is the app's scrollbar.** Both scrolls -- a lane's cards and the lanes sideways --
  spread `shared/thinScrollbar.ts`, the same fragment `PageCard`, `StatusMessage` and `TestHealth` use.
  The lane keeps `paddingRight: 2px`: the styled bar is a classic one that takes its 6px
  beside the padding, so the gap between a card's edge and the bar is unchanged.

## Making a card from the browser

The **+** on Home is **New card**. Its dialog (`modules/ado/ActionDialog.tsx`, the `create` tab) has two
sources: **New card** -- what it is called, and what kind of thing it is -- and **From a work item**, as
before. "New card" is the default wherever there is no ADO to ask (`spaceStatus` is not `active`, or the
tier is not 1), which includes the Demo org a first run opens on.

It goes through the bridge like every other change: `buildNewCardParams` (`cliBridge.ts`) builds
`-Title <text> -Type <name>` for `POST /api/cmd/NewPrompt`. **The id is never sent.** It comes from the
CLI's one id engine, so a card made here and a card made in a terminal come out of the same rule
([`../docs/hub/cards.md`](../docs/hub/cards.md), "The filename"). The types offered are `/env.cardTypes` -- the configured type names,
a team's own included -- never a hardcoded list. The new card appears on Home without a reload because
the mutation invalidates `Status`.

## A card is a model, not a title

`PromptInfo` (`modules/ado/api.ado.ts`) is the Card model ([`../docs/hub/cards.md`](../docs/hub/cards.md), "The model, as the agent serves it"), as
`/api/status` serves it: `id`, `type`, `name`, `linked`, beside the derived `status` and `progress`.
**Nothing in the web parses a filename or a heading to find a card's id or type** -- the agent does it
once, by the same rule the CLI uses. Home shows a card as its name, then `Type id` ("Spike K7M2",
"Bug 141"); the file name is the tooltip, because it is a fact about storage. The text filter finds a
card by its exact id. A card with no work item looks exactly like one with: you never see the word
"custom".

## Reading a card

**Every file page shows the file's absolute path, with a click to copy** -- `shared/FilePath.tsx`, on the
card page, the growth item page, the 1:1 session page, the review page and the Resume page alike -- and an issue, whose record is
not a hub file, wears the same line with its GitHub link (`what="issue link"`). The owner: "the most useful is
every detail view has the file where it lives, so I can share the path with an agent easily." The path
is what the agent resolved to read the file (`path` on each detail response), so it is the agent's
machine's path -- normally this one; an older agent sends none and the line is absent. The copy itself is
`shared/copyText.ts`, lifted out of Daily's Copy Day so every copy in the app is the same copy.
On Daily Activity the outcome is also **announced**: the button's label flips to
"Copied!" for two seconds, but a label change on the control just pressed is not read aloud, so one
visually hidden `role="status"` live region says "Copied Tuesday to the clipboard." after every
copy on the page. And an empty day carries no count badge -- a "0" read as a number to check rather
than as nothing.

`src/shared/prepareMarkdown.ts` runs before every markdown render (`MarkdownViewer`, `MarkdownBlock`).
A card is written for a person AND an agent, and three things in it are not for the page: HTML
comments (template instructions; they no longer print since raw HTML is parsed, but the pass stays so a
comment cannot cut a list, and it leaves comments inside code alone), YAML front matter
(CommonMark reads it as a heading; it is lifted out and shown as one quiet line), and consecutive
`**Label:** value` lines (one paragraph to CommonMark; each gets a hard break). It is a view: the
file is never changed, and code fences and inline code are left exactly as written.

**Simple HTML reads as it does on GitHub.** Every `ReactMarkdown` call spreads ONE configuration,
`src/shared/markdownPlugins.ts`: `remark-gfm`, then `rehype-raw` (parse the HTML) and `rehype-sanitize`
(a schema built from GitHub's own default, adding `align` on `p`, `div`, `h1`-`h6`, `img`, `td`, `th`,
`width`/`height`/`alt` on `img`, and `details`/`summary`). Nothing that executes survives -- no
`script`, `style` or `iframe`, no `on*` handler, no `javascript:` URL. `alignRules` in the same file
makes `align="center"|"right"` actually align under our CSS. A raw `<img>` and `<a>` arrive at the
viewer's `components` map like markdown's, so image resolution and link handling apply to them
too. A new `ReactMarkdown` takes the same spread; it keeps no plugin list of its own. A task-list
item's checkbox (GFM's bare `<input type="checkbox" disabled>`) is named by the item's own words in
`MarkdownViewer`'s `li` -- tight list or loose, a nested item's words left to it.
`markdownPlugins.test.tsx` renders the real pipeline: `jest.config.mjs`'s `transformIgnorePatterns`
lets ts-jest compile exactly the markdown stack's ESM packages and React Router 8's (registry tests still mock every module).

`MarkdownViewer` is the page a card is READ on:

- **A centred column of 72 characters**, so a wide card does not leave a third of itself empty with
  the zoom control floating in it.
- **"On this page"** in that third, for a card with three or more headings: sticky, the section
  being read marked in the accent, a click scrolls there and moves focus to the heading. Under
  1100px it folds into a `<details>` above the text. It lists **h2 and h3**: an h3 is
  drawn indented under its h2, in the same font, quieter, and the marker lights both the section
  and the part of it the reader is in. An h3 with no h2 above it is listed at the top level, so a
  file that starts at level three still gets a menu; h4 and below stay out -- a list is a menu, not
  an outline. `headingsOf()` (in `prepareMarkdown.ts`) gives each heading its `level`, its `line`
  and an id from its words, with `-2`, `-3` on a repeat (five review rounds each headed
  `### Response`); the h2 and h3 renderers take the id by the heading's line, so the list and the
  element agree even when the words do not differ. Sticky works because `PageCard` is
  `overflow: clip`, not Fluent's `hidden` -- `hidden` makes the card a scroll container that never
  scrolls, and sticky never sticks inside one.
- **100% is the comfortable size.** The scale is built in (`BASE_SCALE`), so the control means what
  it says. The choice is remembered
  (`toolkit-reading-zoom`).
- **The title is said once.** `titleAbove` drops the card's opening h1 when the page header already
  shows exactly that; the header's title is then the page's `h1`. A card whose h1 says something
  else keeps it.
- `components` is memoised. A new object is a new component TYPE per tag, so an unmemoised one would
  remount the whole card on every re-render -- and drop the focus a contents link had just given a
  heading.

## The deck module's surface

`modules/deck/` is **web-only**, like the Lounge: no verbs, no agent routes.
[`docs/modules/deck.md`](../docs/modules/deck.md) is its short document, and it points at Connected
Deck's README for the engine itself. What matters to the shell:

| | |
| --- | --- |
| `feature` | `"deck"` |
| `routes` | `/deck/:deckId`, `/deck/:deckId/notes`, `/decks` -- every element is `lazy`, so no deck code is in the first load |
| `nav` | one entry, **Decks**, and it is `hidden` while growth is on |
| `slotCards.growth` | the launcher card. **This is how it appears under the Growth tab**: `GrowthPage` renders `useShellSlot("growth")` and imports nothing from `modules/deck`. One module on another's page, neither importing the other |
| `slotCards["home-banner"]` | the first-run banner: Introducing ToolKit's first slide IS the banner (the Wasteland's home hero without the carousel), with **Get Started** bottom right and a label-less close **x** top right -- only while `/env`'s `config.firstRunWelcome` is true. Home (`modules/ado/routes.tsx`) renders `useShellSlot(HOME_BANNER_SLOT)` above its tabs; the name is `shell/slots.ts`, a file that imports nothing, because a module that read it from `registry.ts` would read it before the registry had run. `homeBanner.test.tsx` holds the gate |
| `chromeless` | `/deck/*` -- the shell draws no nav bar, no padding and no background around a deck. `isChromeless` only counts a module that is ON, so a flagged-off module cannot strip the chrome |

With growth off nobody renders the `growth` slot, which is why the module carries a tab of its own:
a flag that shows nothing when it is on was the defect this module was filed over.

**Two resolvers, one engine.** `DeckHost.tsx` finds a hand-written deck by the route's id in the
static `DECKS` list; `GeneratedDeckHost.tsx` plays a deck another module BUILT from data and handed
over as a resolution (deck, loading, error) -- Team Agile's played standup, at its own route
`/deck/ritual/standup`, which is that module's and works with `features.deck` off. Nothing is ever
pushed into `DECKS`. Both share `DeckRoom.tsx`. A built deck sets `audiobook` on the `Deck` type:
Suitcase Mode at any width, prev and next kept beside the transport, and the browser's
`speechSynthesis` reading a slide that has no clip (`engine/useSpeechNarration.ts`); a deck without
the hint is untouched (`DeckPlayer.audiobook.test.tsx`).

`modules/deck/engine/` is carried code -- 25 files from the predecessor repo -- and is excluded from
nothing: it is type-checked, linted, scanned by Portability and its 79 tests run with the rest.
`bakedVoices.ts` finds a deck's audio with `import.meta.glob`, which is why `src/vite-env.d.ts`
exists; the files sit under `src/`, not `public/`, so the build ships each once.

## The landing page

The page a visitor who has installed nothing reaches: the README's first screen with the commercial
playing, served by GitHub Pages and built from this repository. Its design note names
the shape: five bands, built from the repository.

**A second entry, not a page of the app.** `web/landing.html` loads `src/landing/main.tsx` and
nothing else of the shell: no router, no store, no agent, no `/env`, no module registry, so no
`features.*` flag applies to it (the deck module's switch gates the app's Decks tab and nothing
here). It imports the deck engine, the commercial and its baked clips as source. `npm run
build:landing` (`vite build --mode landing`) builds it on its own, to `dist/landing/`: relative asset
addresses, because Pages serves it from a subpath; no `public/`; and the entry's page renamed to
`index.html` once written. The app's `npm run build` is unchanged and never reads it.

**The page, top to bottom**, in the family's shape (the house's other public front pages: a dark
ground, one accent, one call to action). The accent is the product's (`shared/accent.ts`, under
"Themes") -- the landing page is one of the two places it shows, the app's themes keeping their own
-- worn as the dark mode wears it: wine behind the wordmark, rose on the call to action, the pale
rose for the bullets' dots and the links. `Landing.tsx` sets them on the page as custom properties
(`landingAccent`), so `landing.css` types none of them.

| Band | What it holds |
| --- | --- |
| The banner | The wordmark (`src/shared/Wordmark.tsx`: one SVG, the letters and the face as outlines so no font is asked for and every machine draws the same bytes; colours, size and the face are its arguments; named `ToolKit` for a screen reader), the offering, three bullets, the call to action **Play Introducing ToolKit**, and at right the many faces of ToolKit: every face the app's logo can wear as a grid of twelve small wordmarks, the blobs cycling through the palette (`src/landing/Faces.tsx`), with one line under them |
| The three ways | Under an eyebrow, each way of working in turn: its heading and copy on one side, one of the cast in their Zoom window on the other, delivering one line from a bubble; the sides alternate. `src/landing/people.ts` says who stands for which way and their line; the window and the figure come from the stage's cast source, parked |
| Quick start | A real heading over the five lines, coloured the way a terminal would colour them (verb, flags, strings, the comment after `#`; `src/landing/Code.tsx`) on the page's own ground, with Nimbus, the Azure Butler from the commercial's second window, standing beside the shell at about its height (`src/landing/Butler.tsx`, drawn by the deck's own exported function) |
| The footer | The repository, the documents, and the narration disclosure |

**The page's own words.** `src/landing/copy.ts` holds every word on the page, written for a visitor
and kept apart from the README on purpose: the README is the front door on GitHub and this is the
front door on the web, each crafted for its reader, and nothing reads the README at build (the design
note, D-LP1 as revised). The footer's links are `<repository>/blob/HEAD/<path>`, with the repository
named once in the copy, so the export's `repo-name` rule renames them.

**The commercial.** The banner's call to action plays it. Pressed, the deck plays over the whole window in its own room, in
audience mode with its baked voices and narration on (the press is the gesture a browser asks for
before it plays sound); its **Exit**, or Escape, brings the page back with focus on the call to action. The
player is `DeckPlayer` as `DeckHost.tsx` hands it over; because its controller pages and exits
through a router, it sits in an in-memory one holding the page and the deck, and the address bar is
never touched.

**Phone first.** Everything stacks at phone width; the banner's two columns start at 900px and each
way's two at 768px, the deck module's `md`. The page is dark in both system themes, as the family's
pages are; colours are tokens on `:root`.

**Deployed by `.github/workflows/pages.yml`**, on the Actions tab's button only until the repository is
public ([docs/TESTING.md](../docs/TESTING.md), "In CI").

`src/landing/landing.test.tsx` holds the page to its copy: the documents as files that exist, the
repository a GitHub address, five quick-start lines each a command with its comment, the people one
per way and each a member of the cast; and the page drawing exactly those words: the banner with the
many faces and their line, the call to action and its focus return, each way under the eyebrow with
its person and their line, quick start character for character with the butler, the footer's links in
order. It renders `Landing` without the player, so the suite loads no deck.

## Creating a card never overwrites one

`CreatePrompt` and `ActionDialog` create a prompt file one way: `POST /api/cmd/NewPrompt`, which runs
the CLI's own script. So the CLI's rule is the web UI's rule with no code here at all -- a card
already in `current/` comes back as `status: success` with `Card <id> is already in current/ --
nothing was written, and ADO was not contacted.` and its path in `output`, which the dialogs already
render -- proven through the real bridge: the card byte-identical, no commit in the hub. **Do not
add a native route that writes into `current/`.** It would be a second writer, and
"don't overwrite context while we are adding context" would have to be proved again for it
([AGENTS.md](../AGENTS.md), "`current/` is protected").

## The two hooks the shell calls through the registry

`App.tsx` calls two RTK Query hooks -- `useGetWorkItemsQuery`, `useGetStatusQuery` -- to derive
`CardContext.stateOptions`, the union of work-item and prompt states the filter dropdown offers.
It needs them while building that context during its own render, before any module route has
mounted, so there is no module code running yet to derive the list from. Removing them needs the
context built later or lazily, a change to the shell's render order rather than a rename. The ADO
core is always in the first load, so this does not hold back the opt-in modules' lazy parts.

The shell reaches for the two hooks through one door: `App.tsx` does not import them from
`modules/ado/api.ado` directly. `registry.ts` re-exports them --

```ts
// registry.ts
export { useGetWorkItemsQuery, useGetStatusQuery } from "../modules/ado/api.ado";
```

-- and `App.tsx` imports them from `"./registry"`, beside `activeModules`, `moduleCards` and the
rest. "The registry is the only import path from the shell into a module" holds literally: it
imports `adoModule` (which is what the registry importing modules IS) and it is the one place that
names `modules/ado/api.ado`. The re-export is still a special case -- the ADO module is the only
one the shell reaches into this way, and only for these two hooks -- but it is a documented,
single-door one rather than a second door the shell opened for itself.

## The module's surface

Routes: `/`, `/system`, `/pr-comments/:filename`, `/prompts/:filename`, `/review`,
`/review/:folder`, `/daily` (`/billing` redirects to it). Nav: Home, System, Daily -- Daily hidden when
`spaceStatus === "archive"`.

`/pr-comments/:filename` answers a thread in place: an open thread with no reply in the card
gets a reply box; **Suggest a reply** calls the agent's `suggest` route (offered only when `/env`
says `anthropicConfigured`; otherwise the box names the variable) and fills the draft and the status
from the recommendation; **Post reply** is `ReplyPR` through `runCommand`, the one writer of the
card's `Reply:` slot, and the page re-reads the card. The page calls no native save route -- there is
none -- and `PRCommentsDetail.reply.test.tsx` holds all of it.

The home cards have three branches, one per org status (`homeTabPlan` in `modules/ado/homeTabs.ts`
also places each on a Home tab, and plans a GitHub Space's cards -- see "The shell's frame"). Which
cards a tier and an org status produce is settled behaviour carried from the predecessor, with a
year of use behind it.

| Branch | Cards |
| --- | --- |
| `archive` | `EngagementSummary`, `WorkBreakdown`, and -- when growth is on -- growth's `ReviewArchive` and `SkillsSnapshot`: a module may import another module's card, it may not fork one |
| `local` | `PRCommentsList`, `PromptStatus`, and `SprintVelocity` if `features.sprintAwareness` |
| active | Tier-gated: `PRCommentsList` (Tier ≤ 2), `MyPRs` (Tier 1), `PromptStatus` (always), `MyWork`, `EngagementSummary`, `WorkBreakdown`, `Dashboard`, `PromptActions` (all Tier 1), plus `SprintVelocity` on its flag |

`systemCards`: `EnvCard`, `ModulesCard`, `ToolkitLog`, `TestHealth` (Tier ≤ 2) -- four (the owner: "system tab four and lounge tab four"). `EnvCard` is the machine's story, its checks and the footer's metadata; `ModulesCard` names every add-on, on, off or not configured, with a Change link to its flag -- the CLI's `Opt in by configuration` block in web form. There is no
Space dropdown here: the avatar menu is the one place a Space is switched. `settingRows.tsx` is the
row grammar both cards share. `FacePicker` is drawn by the Lounge (spec D-L24) and nowhere else.
Configuration is a section of [the settings drawer](#the-settings-drawer), not a card.

Every card picks its own page size as a local constant, and nothing relates that number to the
height the grid gives the card -- grid children stretch, so a card beside a taller neighbour is as
tall as the neighbour. The Log's `PAGE_SIZE` is ten, tuned against Environment beside
it at desktop width, and the comment beside the constant says so; if the pair drifts, the next step
is to let the rows fill the space the grid gave the card, not another constant.

The Log's chart and Health's read the same way: oldest day on the left, straight
segments or bars for daily counts -- a spline through four daily points invents a dip no day had.
The agent serves entries newest first, and the chart's days are sorted in `logChart.ts` whatever
order they arrive in. The Log's badge is a count of what matches the filters, and reads
`latest 500` when the agent's answer was cut at `LOG_LATEST` (`api.ado.ts`, the number the query
asks for) and nothing narrows it, so a cap is never dressed as a count. Environment's
uptime goes through `shared/uptime.ts` (`4d 9h`).

### The Configuration section, and what it does not do

`ConfigSettings` is the Configuration section of [the settings drawer](#the-settings-drawer). It is
`EnvCard`'s pair: `EnvCard` reports what the machine resolved and this changes it, so a missing
`email` is named and fixed in the browser, rather than showing no pull requests with nothing to say
why and a text editor and an agent restart as the fix.

It writes nothing itself. Every save is `PUT /api/config`, which runs the CLI's `Config` verb
through the bridge, so the rules about what may be set, which file it lands in and what a legal
value is live in one place -- `Scripts/Get-ConfigSchema.ps1` -- and this section only renders them:

- **Three groups, because three files.** Machine keys (`config.local.json`), the active Space's
  fields (the hub's `hub.json`, labelled as such), and the two org **actions**: add, which takes a
  slug and lets the CLI fill in what an org must carry, and archive, which sets `status: archive`
  -- the value the shell already renders as the retrospective view. Nothing deletes an org.
- **A source badge per row** -- `default`, `hub`, `local`, `env` or `unset` -- from
  `GET /api/config`.
- **A row is a name, a sentence, a control, and the key.** The name and the sentence are this
  half's own words, in `src/modules/ado/configLabels.ts`, keyed by SCHEMA key (`spaces.<slug>.status`
  names that field for every org): "Your work email", and what it does for you, in sight -- not the
  raw key with its help behind an (i). The schema's help (`GET /api/config/schema`, cached for the
  life of the agent) is the CLI's voice -- "-Hub", "SwitchSpace" -- and is what a key nobody has named
  yet falls back to, under its own name: a new config key is never hidden, only plain. The key
  itself sits under the control as a caption, because it is what `Config -Set` takes. Every control
  is named by its label and described by its sentence (`aria-labelledby`, `aria-describedby`).
- **The control comes from the schema's type**: a text input, a toggle for a boolean, a select of
  the allowed values for an enum.
- **Edits are batched.** One Save is one `PUT`, one CLI call, one atomic write per file. The reply
  is a `CommandResponse` rendered through `commandResultMessage`, so `rejected`, `timeout` and
  `error` read as what they are rather than as a failed fetch.
- **A cleared field is an unset, not an empty value.** Every machine key overrides something, so
  emptying one means stop overriding; writing `""` would pin the empty value, which is the gap the
  section exists to close. `buildConfigEdit` in `modules/ado/cliBridge.ts` is that decision, and it is
  pure so `cliBridge.test.ts` can pin it.
- **Save is pinned, and drafts survive a close.** The drawer's body scrolls and its foot does not:
  Save, Discard and the outcome of a save are portalled into the drawer's footer outlet
  (`shell/settings.ts`), and the foot takes no room while nothing is in it. The drafts live outside
  the component -- the drawer unmounts its content when it closes, and a scrim click must never
  throw away typing -- and their count is reported to the shell, which puts a dot on the avatar and
  says "Settings, 2 unsaved changes" in its label. Page-lifetime only, on purpose: a reload is a
  clean slate.
- **A row is two lines.** Name and source on one, the control full-width under it -- three columns
  across a 460px drawer would leave a path input about 170px wide with the path cut off.
- **A save shows at once.** The `PUT` reply carries the re-read list, and it goes straight into
  `getConfig`'s cache. Invalidating the tag instead would cost a second trip through the CLI, and a
  saved row would show its old value for those two seconds.
- **Restarts**: the section says none is needed, because the agent re-reads config per request and the
  write clears its two 45-second caches. The two exceptions are `web.agentPort` and
  `web.corsOrigins`, bound when the agent starts; the footer names them when you change one.

`config.default.json` is never offered: a `-Set` on `commands`, `workItemTypes`, `cliVersion` or
`managerWorkflow` is refused by the CLI with the sentence that says so, and the
card renders that refusal like any other. Navigation shortcuts are the exception: `aliases.<Name>.path`
is a machine key, so the section lists one path row per alias and a path typed there
lands in `config.local.json` like any other.

**Cross-half literals come from `src/shell/consts.ts`, never from a string in a card.** It imports
`consts.json` from the package root through the `@consts` alias -- declared in `vite.config.ts`,
`tsconfig.json`'s `paths` and `jest.config.mjs`'s `moduleNameMapper`, all three -- so the values
are inlined at build time with no fetch and no runtime dependency on the agent. The state names
`PromptStatus` sorts and colours by, the `**Closed:**` stamp, the `## PR Review Comments` heading
and the `current`/`archive` folder names are the CLI's and the agent's words too; a label, a
tooltip or a route is this half's own and stays where it is. `toRegExp` is the one piece of logic:
the contract's patterns carry a leading `(?m)`, which .NET and Python read inline and JavaScript
cannot, so it is lifted into a real flag -- and an inline flag with no JS equivalent throws at
build time rather than matching nothing. `src/shell/consts.test.ts` covers that and greps this
half for a retyped literal; ["The contract file"](../docs/CONFIGURATION.md#the-contract-file) in `docs/CONFIGURATION.md` is the long version.

**One way to say "nothing here": `shared/EmptyState.tsx`, in `PageCard`'s `empty` slot**, so an
empty page looks empty rather than half finished.

- **`PageCard` has an `empty` slot**: a `ReactNode`, like `headerLeft`, optional. `null` or
  `undefined` means the card has a body; anything else is shown INSTEAD of the body, with the header
  and footer kept -- a filter that hid everything has to stay reachable. Hand it an `<EmptyState>`.
- **`<EmptyState icon title detail? tone? action? />`** is the one component: the card's own icon, a
  title, and a second line that says why or what comes next. A card that is not a `PageCard` (Daily)
  or whose message sits below other content (the Log's filters) renders it directly.
- **Three tones that must not look alike.** `empty` -- nothing, and that is fine. `filtered` -- there
  IS something and a filter is hiding it; it says how many. `error` -- nothing was READ: a red icon
  and `role="alert"`, never dressed as empty: a "No ... yet" for a request that FAILED is an
  untruth. A card's query hands over `isError`; use it before you say "none".
- A new card uses the slot, never a bare `<Body1>No things found.</Body1>`.

**One way to count: `shared/StatTile.tsx`.** The house style is the engagement summary's tile
-- **81** Items closed, **4** Reviews, **6** Repos: the number beside its caption in a hairline box, in a wrapping, centred `<StatTiles>` row.

- **`<StatTile count label color? />`** -- `count` arrives formatted (`3/5`, `42%`,
  `toLocaleString()`); `color` is for a count that is a VERDICT (Test Health's pass ratio, the sprint's
  days left, velocity) and nothing else. It forwards its ref, so a `Tooltip` wraps one directly.
- Every card that counts uses it: the Space summary, the Issue Report, Test Health, Sprint Velocity,
  Milestones. A new counting card does too -- never a `Title3` over a `Caption1`.
  `StatTile.test.tsx` and `IssueReportCard.test.tsx` pin it.
- **The Issue Report's severity and kind counts are tiles too**: a SECOND `<StatTiles>` row,
  the identical component, GitHub's own words as the label (`sev1`, `bug`, `feat`); the severity
  colour is `StatTile`'s own `color` prop, the foreground tokens of Badge's
  `tint-danger`/`tint-severe`/`tint-warning` presets. Pinned by
  `IssueReportCard.test.tsx` (both rows share the identical tile class) and
  `IssueReportCard.severityColor.test.tsx` (which sev gets which token, and that a kind tile gets
  none -- checked against the React prop, since jsdom's `cssstyle` drops a `var(...)`-valued `color`
  outright and never reflects it through `style.color`, `style.cssText` or `getAttribute("style")`).

**A `reason` on a response beats the card's own empty state.** `PRsResponse`, `WorkItemsResponse`
and `DashboardResponse` may carry one, and `MyPRs` and `MyWork` render it as the empty state's
second line, under "No active pull requests" / "No work items assigned to you". The agent sends one only when the emptiness is a gap the reader
can close -- today, an identity it could not resolve -- never for a Tier 2/3 org, where empty is
the honest answer and the card's badge already explains it. That badge is `envBadge()` over the tier AND
the org's status, word, colour and sentence together: an `archive` org reads **Archive** (neutral) and a
`local` one **Local**, in green -- working from cards is a choice, and it is shown as one;
only an `active` org that tried and failed is yellow, and it is **Offline**, so one word means one thing.
The Dashboard's **Build** header wears the same badge. Because the badge reads the status as well as
the tier, an archived org never wears a warning for doing exactly what it is configured to do. `EnvCard`'s **Identity** row is the
standing version of the same fact: the address the ADO routes filter by, and whether it came from
`config`, `branchUser` or `az`. Rendering a config gap as "you have no pull requests" is the bug
these exist for.

`AdoHome` renders the `FilterDrawer` above the shell's grid and pre-fetches the two engagement
queries an archived org's cards need, so the grid gates once instead of flickering card by card.
`AdoSystem` renders the grid and nothing else.

**This module's known gaps** -- Create PR reading the card rather than its checkout, the repo filter
hiding cards with no Azure DevOps link, and the ADO verbs hidden rather than gone -- are listed once,
in [`docs/KNOWN-GAPS.md`](../docs/KNOWN-GAPS.md), rather than twice. Two things here that look like gaps are not:
`ReviewPage` is mounted **and** fed, by the growth module's `/api/reviews*` and
`/api/review-preview`. With growth off those 404 and the page reads "No reviews yet" -- which is the
design, not a missing route. And `SprintVelocity` offers no "Run"
button, because `StressCheck` is not a key in the CLI's command table and every press would come
back `status: rejected`. `SprintVelocity` is a read of `status` and
`activity` and keeps its charts, its repo dropdown and its refresh; what a real `StressCheck` verb
would have to be is written down in an open issue on the tracker.

## The growth module's surface

Routes: `/growth` (`GrowthPage` = `ReviewArchive` + `Goals`), `/growth/goals/:filename`
(`GoalDetailPage`), `/skills` (`SkillsPage`). Nav: **Growth**, matching `/growth*` and `/skills`.
No cards of its own; `ReviewArchive` and `SkillsSnapshot` are exported by name for the ADO module's
archive-mode home.

`api.growth.ts` injects nine endpoints into the shell's slice and adds the tag types `Growth`,
`Resume` and `Reviews`. Three of those endpoints are reads of a CLI verb run through the bridge on
the agent's side (`/api/review-preview`, `/api/resume-preview`, `POST /api/review/generate`), which
is invisible from here -- they are ordinary queries.

`GrowthPage` is `ReviewArchive` and `Goals`, plus whatever fills its `growth` slot -- the deck
module's launcher. The 1:1 workflow is the communication module's.

## The communication module's surface

Routes and nav, all of them spelled once in `paths.ts`:

| Path | Renders |
| --- | --- |
| `/communication` | `OneOnOne` -- the one-card landing page the `Meetings` nav points at. A complete session's row offers **Close**, behind a confirm, through `POST /cmd/MeetingAgenda` |
| `/communication/1on1/:filename` | `ManagerDetailPage` -- read view, with an `Edit / send` button to the session page and **Close** on a complete session |
| `/communication/sessions/new` | `ManagerSessionPage` -- scaffold and edit |
| `/communication/sessions/:filename` | `ManagerSessionPage` -- edit, the stage ahead (`Prep` / `Retro` / `Plan` through `POST /cmd/MeetingAgenda`, saving the notes first), Close on a complete session, and the send. Reached from `Edit / send` on a meeting row and on the read view |
| `/growth/1on1/:filename` | **redirect**, filename forwarded |
| `/growth/sessions/new` | **redirect** |
| `/growth/sessions/:filename` | **redirect**, filename forwarded |

**The three redirects are not decoration.** The `/growth/` paths are the 1:1 pages' old addresses
(see History): the growth module does not serve them, and without a redirect every bookmark to one
would break. Two of the three are
components rather than plain `<Navigate>` entries, because a `<Navigate>` cannot read a route
parameter for you -- `useParams()` has to hand the filename across.

Route paths live in `paths.ts` for the repo's magic-string rule: a path that moves is changed in
one place, not found by hand in every `navigate()` call.

`api.communication.ts` adds the `Manager` tag type. `/env`'s `communication` block is typed **here**,
not on the shell's `EnvStatus`, for the same reason the tags are added here: it is this module's
vocabulary.

### The send button, and the write-back

The send lives on `ManagerSessionPage`, and its rule is a **pure function** -- `sendButtonState` in
`sendButton.ts` -- because there is no other way to check it. The alternative to asserting the rule
is pressing a button that posts to a real webhook.

| State | When |
| --- | --- |
| **absent** | `postRetroSummary` is false. The workflow does not include a send, so there is nothing to explain |
| **disabled** | The stage is not Retro, the recipient has no webhook, `## Sent` already records a send, or the Agenda holds only its placeholder -- and every reason that holds is rendered on the line below it, the recipient's first, **naming the environment variable** from the moment the page opens, before Retro as well as at it |
| **enabled** | Retro stage, recipient configured, an Agenda with content, nothing under `## Sent` |

Disabled-and-explained rather than hidden is the point: a button that vanishes teaches nobody what
to set. The reason string is the whole fix -- `Set TEAMS_WEBHOOK_MANAGER to this recipient's webhook
URL.`

A click posts

```jsonc
{ "caller": "ManagerSessionPage", "recipient": "<retroChannel>", "subject": "<session title>",
  "sections": [{ "heading": "Agenda", "body": "<the Agenda section>" }], "tone": "personal" }
```

and renders the engine's outcome inline -- all six statuses, because `disabled` and `skipped` are
answers rather than failures. **What goes out is the Agenda section and nothing else.** The Retro
holds a self-assessment, which is private reflection rather than a manager-facing note; a send that
took "the session" would post it the first time someone wrote one. `sendButton.test.ts` pins that.

**On `ok` it writes back.** The page `PUT`s the session with `append_sent`, and
`Sent to manager: <ISO date>` is appended under `## Sent`. The file records that the send happened
-- not this component's state, not a tracker. That is the same premise the whole store rests on, and
it is why `append_sent` exists as a request field rather than the client reading the file back to
add a line to it.

**The send and the record are two requests with two answers.** The send's outcome is reported
first, and a failed write-back separately as `sent; could not record it`, with the line to add by
hand -- so a send that landed never reads as a failure that invites pressing it again. And the button
is **absent on a closed session**: `GET /api/manager/{f}` serves `archive/`, `PUT` writes only
`current/`, so the detail carries `folder` and `sendButtonState` returns `shown: false` for
`archive` -- a send the file could never say happened is not offered.

## Portability

Everything committed under `web/` is subject to the same rule as the rest of the repo: **a clone
must be usable by someone who is not you.** No real name, no email address, no ADO org URL or tenant
id, no absolute machine path, nobody's name as a default.

The nav bar's `Avatar` is the case in point: it names nobody in `App.tsx` and reads
`env.displayName`, served by `/env` -- `branchUser`, else the local part of
`email` (configured, or resolved from `az`), else the neutral string `Toolkit`. A fresh clone with no `config.local.json`
greets nobody.

The Portability suite holds it here as everywhere: it scans `web/src` and `web/tests` (`*.ts`, `*.tsx`, and the smoke's `*.mjs`)
and the whole `agent/` package beside the PowerShell tree, and a line that genuinely needs an
exception carries `// portability-ok: <why>` in TypeScript ([Contributing](../docs/CONTRIBUTING.md)).

The same rule covers ports. `corsOrigins` is config (`config.default.json`'s `web` block), not a
literal in `agent/app.py`, for exactly this reason: a fixed pair of port numbers in source decides
for the next person which ports they are allowed to use.

## Tests

```bash
npm test
```

How many suites and tests the shell has, and every suite's count, is
[`docs/TESTING.md`](../docs/TESTING.md), which lists them all. The ones whose contract is worth a
paragraph:

| Suite | What it guards |
| --- | --- |
| `src/shell/registry.test.tsx` | The registry contract: a module whose flag is false is dropped and contributes no routes, nav or cards; a missing `features` map reads the same as false; a module with no `feature` is always on; module order is preserved across routes, nav and cards; a `hidden` nav predicate is honoured; a module that contributes nothing is not an error. And Home's tabs: cards grouped by the tab they declare, in strip order; an empty tab absent; the tab read from the address, `/board` as Cards |
| `src/modules/ado/homeTabs.test.ts` | Which Home tab each ADO card is on, as a table: active at Tiers 1-3 with sprint awareness on and off, `local`, archived with growth on and off, and not loaded yet -- and no card on two tabs |
| `src/shared/usePersistedState.test.ts` | Surviving a remount, falling back rather than throwing on corrupt stored values or a stale `isValid` shape, localStorage that throws, and the updater form composing two updates in one batch instead of clobbering |
| `src/modules/ado/cliBridge.test.ts` | The CLI parameter contract: the exact argv each of the two dialogs produces, that a value with spaces stays one element, that a field left blank is omitted rather than sent as the script's own default, and that each of the four statuses renders as its own message |
| `src/modules/communication/stages.test.ts` | The three stages in one place -- the file's word, the badge's label, what comes next, complete only at the last -- so no page keeps its own list; and the one switch the session page offers, the stage ahead |
| `src/modules/communication/sendButton.test.ts` | The send button's three states -- including that it is **absent** rather than disabled when the workflow has no send, and that what goes out is the Agenda and never the self-assessment |
| `src/modules/growth/registry.growth.test.tsx` | The registry contract from growth's side: off contributes no route, nav entry or card; on contributes its three routes and its one nav entry, and no home cards of its own |
| `src/modules/communication/registry.communication.test.tsx` | The same from communication's side: off contributes nothing; on contributes exactly its seven routes, including the three redirects |
| `src/modules/ado/cardActions.test.ts` | What a card offers in the list and on the board, as a table: an ADO card and a card with no work item at every state, with Azure DevOps on and off -- every action present, which are disabled, and each one's reason. Absent is not disabled: Open on the tracker and Create PR are absent where they can never apply, and Create PR is disabled, naming `ThreadHash`, while no commit is recorded |
| `src/shared/rowVocabulary.test.ts` | One vocabulary for every row's menu: reads every source file and fails on a row action typed by hand, an own move that is a vocabulary move under another word or wears its icon, a word on two records, and a README that disagrees -- and proves it on rows written wrong on purpose ([One vocabulary for row actions](#one-vocabulary-for-row-actions)) |
| `src/modules/ado/logChart.test.ts` | The Log card's chart puts the oldest day on the left whatever order the agent serves entries in, and its badge says `latest 500` only when the answer was cut at the cap and nothing narrows it |
| `src/modules/ado/promptFilters.test.ts` | The predicates the list and the board share: state, sprint, text -- an exact id, a substring, the words in any order and never a typo -- type with Untyped inside All, the type row counted from the cards, and the unlinked cards a repo filter hid; and linkedness as a table: All / Linked / Custom over ADO-born, GitHub-born and custom cards, composed with the other filters, counted from the cards, and when the row is drawn -- a mixed Space, never an all-custom or all-linked one unless a filter is active |
| `src/modules/ado/TrackerBadge.test.tsx` | The card's tracker chip as a table: `github` wears **gh**, `ado` wears **ado**, and `none`, an absent field (an older agent) or an unknown word wear nothing |
| `src/modules/ado/Board.badge.test.tsx` | The board's card face in a mixed Space: a GitHub-born, an ADO-born and a custom card each wear their own chip, the custom one none |
| `src/modules/ado/FilterDrawer.test.tsx` | The drawer's linkedness row: drawn in a mixed Space with counts from the cards, a badge sets its filter and the active one sets All back, absent where every card is custom, kept while a filter is active |
| `src/modules/ado/billingNote.test.ts` | The sentence under the week on Daily Activity: what it was built from, and the cards that are NOT on it and why -- singular and plural, silence for a count of zero, and the git clause only for a hub that has git |
| `src/modules/ado/useBillableToggle.test.ts` | The toggle offers the opposite of what the card says now, and says what the change means for Daily |
| `src/hooks/useFacePref.test.tsx` | A browser that refuses storage: with `localStorage.getItem` throwing BEFORE the Face store is imported -- its read runs at module scope, in the shell, through the logo -- the store answers the default face and the logo renders; with `setItem` throwing, a chosen face holds for the session and nothing is kept |
| `src/hooks/useCurrentTheme.test.ts` | A theme choice in a browser that refuses storage: with every storage call throwing, a chosen theme holds for the session, and a fresh load of the store answers the default again; where storage keeps, a fresh load answers the choice |
| `src/landing/landing.test.tsx` | The landing page's words are the README's: each piece read out of `README.md` and `THIRD-PARTY-NOTICES.md` is found there as written, a README missing a piece is refused by name, and the page draws exactly those words, band by band, with band 3 absent while it is held ([The landing page](#the-landing-page)) |
| `src/hooks/usePagination.test.ts` | Clamping a page that is out of range, paging independently of the filtered set's size, and controlled mode where the caller's `onPageChange` is the only writer |

The per-module registry tests mock **every** module, not only their own -- see
[Every registry test mocks every module](#every-registry-test-mocks-every-module).

### The smoke test

`npm run smoke` drives both halves together in a real browser, against the fixture hub, and is
what proves "off means absent" from outside the app. **How to run it** -- the one-time Chromium
download, the servers, the port it drives and the orphaned-dev-server trap -- is
[`docs/TESTING.md`](../docs/TESTING.md), "The smoke test needs a browser, two servers and a hub"; the
`-Fixture` switch is [the command reference](../docs/CLI.md#the-other-two-halves). In short, one
command per mode:

```powershell
tkWeb -Dev -Fixture                 # then: npm run smoke
tkWeb -Dev -Fixture -Modules on     # then: npm run smoke -- --modules=on (alias: npm run smoke:modules)
tkWeb -Dev                          # afterwards: back on your own hub
```

`-Fixture` restarts this checkout's agent as a test run and hands it the fixture hub, its Space and
the flags through its environment, with no `TEAMS_WEBHOOK_*` -- `config.local.json` is never
written. That matters to the web half because the send button's state is read from the
**agent's** environment (`/api/env` -> `communication.recipients[].configured`), which no `unset`
in your shell reaches. The smoke refuses before it starts, exit 2, if `/api/env` reports any
recipient `configured: true`, and it never presses the send button either way. The rest of this
section is what the web half asserts.

**Two modes, because "off means absent" has two halves.** `--modules=off` is the default: every
flag false, and the assertions are absences. `--modules=on` expects the agent to have been started
with `features.growth` and `features.communication` both true, and asserts the modules are there --
nav entries, pages, the fixture hub's own data, and the send button's disabled state. It does not
configure `features.organize`: it reads that flag off `/api/env`, and with Organize on it expects an
**Organize** nav entry and the fixture sessions on `/organize`, where communication's Meetings card
sits, rather than a Meetings entry.

The flag does **not** configure the agent. It says which configuration the run is asserting, and a
mismatch fails loudly. A smoke that silently adapted to whatever happened to be running would prove
nothing about either state.

**A mode with its own servers: `--studio`** (`npm run smoke:studio`). Some claims are about the
agent's configuration CHANGING -- a flag flipped under a running agent, read on the next request --
and a smoke must never change the configuration of servers someone else started. So this mode needs
nothing running: `tests/smokeStack.mjs` copies the package's runtime parts into a scratch folder,
copies `Tests/fixtures/hub-spaces/config.local.json` in (a leftover `"features": { "studio": false }`),
starts that copy's agent as a test run on `Tests/fixtures/hub-spaces/hub` and a Vite of this `web/`
proxying to it, and stops both and removes the scratch at the end. Every change after the start is
`PUT /api/config` -- the settings drawer's road, through the bridge -- never a file write. The cases
(`tests/smokeStudio.mjs`): the Studio tab and its Spaces card are there with the leftover line; a
module flag set true then false shows its nav entry on a reload and drops it on the next, the
agent's process the same throughout (`flipCase`, built to be shared); and the Spaces card's tags --
each count and the chip's total, each filter's rows, the tags and the header holding their boxes as
the filter changes, the choice kept after a reload, a fresh browser context opening on All.
`docs/TESTING.md` has the why at length, and the ports and interpreter switches.

**`--matrix`** (`npm run smoke:matrix`) runs on the same kind of servers, over `Tests/fixtures/hub`:
each module flag alone on -- its nav entry, page, data and source there, every other module's absent and
never requested, one new browser context per pass, the cases being `docs/SCENARIOS.md`'s "The nav, by
module" rows; `flipCase` on the Lounge; and each choice kept in browser storage (the Spaces filter, the
Reminders filter, the theme, the Lounge's tic-tac-toe) in a fresh context and in one whose
`localStorage` and `sessionStorage` throw on access. Chromium only, and opt-in because every flag write
is a `Config` run through the bridge.

**`--a11y`** (`npm run smoke:a11y`) is the accessibility audit, on the same kind of servers: every
module flag off and then on, each in `seaglass` and `aurora` (the theme set in storage before the app
runs), axe-core (`@axe-core/playwright`) on every page the registry mounts in that mode. It prints the
findings grouped by impact -- page, theme, mode, rule, selector, help URL -- and a one-line count, and
exits 1 on any serious or critical finding: a gate, separate from the default smoke because a run
takes about ten minutes. `docs/TESTING.md` has the detail.

**`--first-run`** (`npm run smoke:first-run`) is the first tutorial card's move, on the same kind of
servers with a COPY of `samples/hub` as the hub (the way `Start` makes one): Demo's board shows the card
alone in Backlog, the drag lands it in To do, and the file is read back from `demo/current/`.

**A second axis: the viewport.**

```bash
npm run smoke                          # desktop, 1400x900 (the default)
npm run smoke -- --viewport=mobile     # 430x932
npm run smoke -- --viewport=both       # desktop, then mobile; every line tagged
```

Every check runs in whichever viewport is current, and each route adds one more: **the document is
never wider than the window**. `document.documentElement.scrollWidth <= window.innerWidth`, asserted
per route, is the whole class -- the Face card's grid, the nav row, and whatever is added next. A
phone that scrolls sideways is the defect; scrolling to reach the content is not a workaround.

**And it can keep the picture.** `--shots=<dir>` writes one full-page PNG per route it visits, per
viewport, into `<dir>/<viewport>/<route>.png`:

```bash
npm run smoke -- --viewport=both --shots=shots/gate8
```

`web/shots/` is **gitignored**. A screenshot is evidence for a gate, not an artifact of the repo:
it belongs to the machine and the hub that produced it, and a committed one would be a stale picture
of a page that has changed. The file names are the routes (`home.png`, `system.png`, ...) with no
timestamp, so two runs of the same folder diff cleanly in an image viewer -- the folder is the run.

It is not a verb and it drives nothing extra: the smoke already visits every route the shell and the
enabled modules serve, and this saves what is on screen when it gets there. `VERIFY.md`'s Gate 8
names it as the way to keep a visual record of "your real cards render".

The layout rules that keep it true, so a new card does not lose them: a card and a grid child carry
`min-width: 0` (the default is the content's width, which is what pushed the page wide), a picker
wraps with `repeat(auto-fit, minmax(...))` rather than a fixed column count, and the themed
background is on `<body>` -- a background on a container is only viewport-wide, so any overflow
showed as a white band rather than as the page it belongs to.

The fixture hub is deliberately boring: two cards under `test/current/`, one Active and one Code
Review, no toolkit inside it and no `.git`. That last part is the point -- it is the arrangement
`promptsRoot` exists to support, and a hub that is not a git repository must still serve every
Tier-2 route. It also carries the two modules' fixtures, which the smoke test's growth checks prove
go **unread** while the flag is off: `growth/current/` (one artifact per type), `reviews/`,
`resume/resume.md` and `manager/current/` (three sessions, and deliberately no `archive/`).

**With the flags off**, what each check proves (the per-route width checks and the Home-tab checks
come on top of these; the totals are in [`docs/TESTING.md`](../docs/TESTING.md)):

| Check | Proves |
| --- | --- |
| `/` renders both fixture prompts | The chain works end to end: browser → Vite proxy → agent → a hub that contains no toolkit |
| `/` shows the Active and Code Review states | The Python parsers derive state from file content, and the card renders it |
| `/system` renders `EnvCard` with a tier badge | `/env` answered, tier resolved, and the system page is built from the module's `systemCards` |
| No Growth nav entry | A module that is not in the registry contributes no nav entry |
| `/growth` renders no growth page | An unmatched route renders nothing rather than erroring -- "off" is absence, not a 403 |
| No Meetings nav entry | The communication mirror of the same, from a browser rather than from `registry.communication.test.tsx` or the agent's 404s |
| `/communication` renders no 1:1 page | The route half of communication's absence |
| **No growth data was requested** | The data half of "off means absent", checked at the network layer: with the flag off, nothing asks the agent for `/api/growth`, `/api/reviews`, `/api/resume` or `/api/review-preview`. This is the one an in-app assertion cannot make |
| **No 1:1 data was requested** | The same, for `/api/manager` and `/api/comms` |
| **No growth / communication / organize / lounge source was requested** | The bytes half of "off means absent": with the flag off, nothing under `src/modules/<id>/` but the descriptor (`index.tsx`, `paths.ts`) is served in dev, and no chunk named after one of the module's parts is served from a build. The part names are read off the module's folder at run time, so a new page is covered the day it is added |
| No page errors across the routes | Nothing threw while proving the others |

**With `--modules=on`**, the first three checks are the same; the rest are the presences:

| Check | Proves |
| --- | --- |
| Growth nav entry is present | Turning the flag on adds the nav entry, not only the route |
| `/growth` lists the three fixture artifacts | By title -- so a page that renders against an empty or a different store fails rather than passing on the heading |
| growth data was requested | The data half from the other direction: something really asked the agent |
| `/skills` renders | The module's third route is mounted, not only its first |
| Meetings nav entry is present | Communication's nav entry appears with its own flag -- or, with `features.organize` on, the Organize entry does instead |
| `/communication` lists the three fixture sessions | The fixture hub's `manager/current/`, read through the agent (on `/organize` when Organize is on) |
| `/communication` shows each session's stage | Plan, Prep and Retro -- the **stage label**, not the raw value in the file, which is `draft` for the first one |
| 1:1 data was requested | `/api/manager` was actually called |
| The retro session has a send button | The third state of `sendButtonState`: shown, because `postRetroSummary` is on |
| The send button is disabled | And an **enabled** one here is a reason to stop: it means a live webhook is configured in the agent's environment |
| The send button names `TEAMS_WEBHOOK_MANAGER` | The disabled reason sends a reader to a shell rather than to source. This is the check the whole "read-only" rule exists to make possible -- the button is never pressed |
| Each meeting row offers `Edit / send` | The page the send button is on can be reached from the list |
| The read view offers `Edit / send` | And from the page a row lands on |
| `Edit / send` lands on the session page | The button is pressed -- it navigates, it does not send -- and the URL is `/communication/sessions/2026-02-05.md` |
| Exactly the complete session offers Close | Presence on one of three rows, never pressed: a press runs `MeetingAgenda -Close` and moves a file in the committed fixture hub |
| No page errors across every route visited | Nothing threw while proving the others |

It uses raw `playwright`, not `@playwright/test` -- chromium, `domcontentloaded`, then wait for the
app's own `Loading toolkit...` gate to clear. Waiting on the app's gate rather than a timeout is
what keeps it from being flaky on a cold agent.

## Production

Two paths, both serving the same `dist/client`:

**Docker.** `docker compose up -d --build` builds the SPA and serves it from nginx: host port 5174, published on the loopback only (`127.0.0.1:5174`),
container 5173, with `/api/` proxied to `host.docker.internal:<web.agentPort>`. The agent is **not**
in this compose file -- it runs on the host, and `extra_hosts: host.docker.internal:host-gateway` is
what lets the container reach it. The port is not in the image: `nginx.conf.template`
carries `${P20_AGENT_PORT}`, the nginx image's entrypoint substitutes it at container start
(`NGINX_ENVSUBST_FILTER=^P20_` keeps it off nginx's own `$host` and `$uri`), and
`docker-compose.yml` passes the variable in from the shell that ran it -- `tkWeb` exports it from
the merged config first; a `docker compose up` typed by hand with nothing exported gets the shipped
default the compose file names.

It follows that **the BUILD must not need the port**: the builder stage has neither config file
(the context copies `consts.json` and `web/`; `config.local.json` is dockerignored) nor the variable
(compose passes it as `environment:`, read at container start, not as `args:`). So `vite.config.ts`
spreads the proxy block in for `command === "serve"` alone -- resolving the port while `vite build`
constructs the config would stop the image building -- and `npm run test:config` asserts both
halves.

**The container is not a dev server.** It serves a static production build. Editing source on the
host changes nothing until `docker compose up -d --build` runs again. This is the single most
common "why doesn't it see my edit".

**The agent.** If `web/dist/client` exists, `agent/app.py` mounts `/assets` from it and serves
`index.html` as the fallback for every non-API path -- and an unmatched `/api/...` path is a JSON
404 naming the path, not the page. One process, no nginx, no Docker. It is a
no-op in a dev checkout, because `dist/` is gitignored and nothing builds it for you. The directory
is checked at **import** time, so an agent started before `npm run build` serves no UI until it is
restarted.

**The build stage runs Node 24** (`node:24-alpine`), the same major the repository states everywhere else (`.nvmrc`, `web/package.json` `engines`, `docs/QUICKSTART.md`); the serving stage is `nginx:alpine`, which carries no Node. A bump of the repository's Node line moves the first `FROM` in `web/Dockerfile` with it. Built and smoked on Windows with Docker 29 and Compose v5: the image builds (105 MB) and `npm run smoke -- --port=5174` reads clean against the running container.

**This Docker path is for Docker Desktop (macOS, Windows), not for native Linux Docker Engine.**
Docker Desktop runs containers inside a VM whose networking gives `host.docker.internal` a special
resolution that reaches a listener bound to the host's loopback -- which is why the two runs below
work. A native Linux Docker Engine has no such VM: `host-gateway` resolves `host.docker.internal` to
the container's real bridge-network gateway address, a different network namespace from the host's
loopback interface, so the agent's loopback-only bind (`docs/ARCHITECTURE.md`, "Trust model") is not
reachable from the container through that route. This is how Docker's own bridge-network model works,
not something that needed a Linux host to discover -- nobody has run this image on one. On native
Linux, run the agent and the web UI directly on the host instead: `tkWeb -Dev`, which already works
there (`docs/QUICKSTART.md`, "Supported platforms"). An opt-in, non-default bind address that would
let the Docker path work on native Linux too is a known gap, not built (`docs/KNOWN-GAPS.md`).

**Verified by a run (2026-09-16).** On a Mac with Docker Desktop 28.3.0 and Compose 2.38.1: the image builds (104 MB),
`http://localhost:5174/` serves the built `index.html` with the hashed asset the build emitted, the
deep link `/system` returns the app rather than an nginx 404, and `/api/env` through the container
returns a payload byte-identical to `curl` straight to 4100 -- so `host.docker.internal:host-gateway`
does reach an agent on the host. The rebuild claim was tested rather than inferred: changing
`index.html`'s `<title>` on the host changed nothing in the container until
`docker compose up -d --build`, and then it changed. The agent's own path serves the same
`dist/client` on 4100 with `/api/env` and `/api/status` still answering JSON, so the `/{path:path}`
fallback does not shadow a registered API route.

**The healthcheck asks for `127.0.0.1`, not `localhost`.** In this image `localhost` resolves to
`::1` as well as `127.0.0.1`, while `nginx.conf`'s `listen 5173;` binds IPv4 only, so a healthcheck
on `localhost` reports a container serving perfectly on the published port as `unhealthy`. And an
**unmatched** `/api/` path is a JSON 404, not the SPA with 200: the agent's catch-all is registered
after the API router and refuses the API prefix; `Tests/test_app_serving.py`
holds it with a scratch `dist/client`.

## Stack

React 19 · Fluent UI v9 (`@fluentui/react-components`, `makeStyles`/`tokens`) · Redux Toolkit +
RTK Query · React Router 8 (`react-router`) · Recharts · react-markdown 10 + remark-gfm + rehype-raw + rehype-sanitize · Vite 8 · Jest 30 +
ts-jest + Testing Library · Playwright (the raw package) · TypeScript 6.0, because ts-jest and typescript-eslint do not yet accept 7 ([Known gaps](../docs/KNOWN-GAPS.md)). Node 24, the active LTS (`.nvmrc`, `engines`); verified on 24.21. Lint is ESLint 10 with typescript-eslint; `eslint-plugin-react` still declares a peer range that ends at ESLint 9, so `package.json` `overrides` hands it the root's ESLint, and `eslint.config.js` reads React's version from its package because the plugin's `"detect"` calls an API ESLint 10 removed.

Fluent and RTK Query are whole-app dependencies, not per-card ones. A fork that wanted a different
stack would be rewriting the views, not relocating files.

## History

What changed under a name, an address or a stored key that someone may still hold:

- **2026-09-16** -- the communication module took the 1:1 pages out of growth; their old addresses,
  `/growth/1on1/...` and `/growth/sessions/...`, are the three redirects to `/communication/...`.
- **2026-09-17** -- navigation shortcuts (`aliases.<Name>.path`) became machine keys, settable from
  the Configuration section.
- **2026-09-18** -- the communication nav entry was renamed from `1:1s` to **Meetings**; the
  Configuration card left `/system` for the settings drawer (it was `ConfigCard`, the fifth system
  card).
- **Before the bridge** -- `POST /api/create-ado-item` and `POST /api/resolve-bug` were native agent
  routes that built their own command strings; they were retired
  as duplicates of bridge calls, and the two dialogs' mutations kept their names and call sites.
- **2026-09-22** -- Daily's page moved from `/billing` ("Weekly Summary") to `/daily` ("Daily
  Activity"); `/billing` redirects.
- **2026-09-28** -- Home's List | Boards toggle, remembered in `localStorage["toolkit-home-view"]`,
  became the Focus and Board tabs; that key is no longer read. The Environment card's foot of
  add-on rows became `ModulesCard`, and `FacePicker` moved to the Lounge.
