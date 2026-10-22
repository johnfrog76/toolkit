# The agent and the web UI

How the other two halves fit onto the CLI: why the CLI is the base, the one-way dependency, the
store they share, `/env`'s shape, the bridge, the shell-and-modules split of the web UI, and the
repo's layout. This is the overview -- what
neither half's own document owns alone. The detail for each half lives in that half --
[`agent/README.md`](../agent/README.md) and [`web/README.md`](../web/README.md) -- and the opt-in
modules have [their own guide](modules/README.md). The root [README](../README.md) is the map of
the other documents.

**The dependency runs one way.** The web UI reads through the agent; the agent reads the same
config and store the CLI does; nothing in the web half changes a card except through the CLI, via
the bridge. Neither half holds state between requests -- config and the hub are re-read on every
request that touches them, so a `tkSwitchSpace` in another shell, or a hand-edited
`config.local.json`, takes effect on the next fetch rather than on a restart; an open CLI shell notices the same change at the start of its next verb (it compares the write times of `config.local.json` and `hub.json` and re-imports). A card archived from
the terminal is gone from the browser on its next fetch, with nothing syncing the two.

**Why a CLI.** A CLI is the only interface that works everywhere this has to work: a terminal, an
agent tool call, CI, a git hook, a machine with no browser. Anything else is a second view of
something the command line already does, which is why the agent and the web UI are built on it
rather than beside it. The command surface is data, not code: one config value decides the prefix,
and any number of prefixes share one implementation ([The CLI, "The prefix"](CLI.md#the-prefix)).
That is what lets this be a base rather than one person's script.

**The hub is the prompt store, and it is configuration**: `promptsRoot`, plus the active Space's
subfolder from `spaces[].promptsFolder`. It is never derived from where this repo happens to sit.
The hub is not this repo's parent folder, need not contain the toolkit, and need not be a git
repository; resolving it from configuration alone is most of what `agent/core/config.py` is for.
The layout of this repo itself is [the last section](#repo-layout).

## The agent

`agent/` is a FastAPI app -- the read layer the web UI talks to, plus the bridge back into the CLI.
[`agent/README.md`](../agent/README.md) has the layout, the six severed layout assumptions, the
tier and identity contracts, the full route table and what is deliberately absent.

```bash
python3 -m pip install -r agent/requirements.txt    # fastapi, uvicorn, pydantic  (Windows: python or py -3)
python3 -m uvicorn agent.app:app --port 4100        # from the repo root, not from agent/
```

Or `tkAgent`, which does the same with the configured port, backgrounds it, and refuses with a
readable message if a dependency is missing; `tkAgent -Status` probes `/api/health`. The launcher's
own behaviour -- the foreign-listener check, returning through a pipe, the Windows `npm` shim -- is
CLI workflow, documented in [`docs/CLI.md`, "The other two halves"](CLI.md#the-other-two-halves).

**`web.agentPort` and `web.corsOrigins`** are the two config keys that reach the whole product --
what resolves them, how `tkWeb` hands the port to Vite and to the nginx image, and why a production
build must not need it, is [Configuration](CONFIGURATION.md#what-tkconfig-writes-and-where). One
consequence worth knowing here, because it looks like a bug the first time: **through a proxy, CORS
is never exercised.** `npm run dev` and nginx both forward `/api` server-side, so the browser only
ever sees one origin -- which is why the smoke test passes on a port that is not in `corsOrigins` at
all. `corsOrigins` matters only when a browser calls the agent's origin directly.

### `/env`

`GET /api/env` is the single round trip the web shell gates on before it renders anything. It
answers: `version` (the product's, `consts.json`'s -- the System page's Environment card shows it in
its footer), machine and OS, `tier` and its label, `spaceStatus`, the `features` map, whether an
Anthropic key is configured, `displayName`, `cliPrefix`, the `cardTypes` a card may be, `tracker`
(which tracker the active board's address names -- `"ado"`, `"github"` or `"none"`), `howIWork` (the
active Space's answer to "How do you want to work here?", `answer`, `source`, `tracker`, `locked` and
Team Agile's `switch` as set -- `features` already carries the gate), `identity`
(`{email, source}`, who the ADO routes filter by), nine named checks, and the active Space's config
including the full `spaces` list -- each Space with its `tracker` and its own `laneNames`. `agent/README.md`'s Tier and identity sections have each field's
fallback chain and why the tier probe runs off the event loop, cached 45 seconds.

**Every route is under `/api`**: the ADO core's and the shell's, the GitHub tracker's, and each
module's own. The module routes are mounted unconditionally and
gated **per request** -- see [the modules guide](modules/README.md) -- so the schema does not move
when a flag does; only whether a request gets an answer or a 404. The full table, with what each
route reads and writes, is [`agent/README.md`, "The route table"](../agent/README.md#the-route-table);
what is deliberately absent (a route named but not built, or retired outright) is
[the section under it](../agent/README.md#deliberately-absent).

**A route about the active Space can be asked about another.** `GET /api/issue-report`, `/api/deploys`, `/api/visibility`,
`/api/issue/{n}` and `GET /api/status` take an optional `?space=<slug>`: absent, the active Space as
always; present, that Space's own entry in `spaces[]` (one lookup, `space_entry()` behind `space_scope()`
in `agent/ado/accounting.py`), an undeclared slug a 404 naming it. `/api/visibility` also takes `?refresh=1`, past its per-repository cache, as `/api/env?refresh=1` goes past the probe's -- the Spaces card's Refresh. The tracker reads probe that Space's
tier; `/api/status` reads that Space's `current/` and `backlog/` and asks no tracker. The Studio's Spaces card
reads its non-GitHub rows through `/api/status?space=` -- one row per Space, none switched into -- and every
GitHub row through ONE read, `GET /api/studio/ledger` (`consts.json` `studio.ledgerRoute`): the three answers
above for every GitHub Space, from one `gh api graphql` call plus a `gh run list` per repository, kept on the
agent's disk for 600 s ([`modules/studio.md`](modules/studio.md#the-routes)).

**A route may read through a verb.** `GET /api/spaces/candidates` -- the repositories the Spaces card's
**+** offers, an owner's with `?owner=`, one typed repository with `?repo=` -- runs `NewSpace -Discover -AsJson` through the bridge's own `run_command`, as
`/api/config` runs `Config -List`, so the rule that proposes a slug and the rule that says "already a
Space" exist once, in the CLI. It writes nothing, and it never refuses: with no `gh` it answers
`available: false` and the verb's sentence. Adding the Space is `POST /api/cmd/NewSpace`.

**A route may read the package itself.** `GET /api/studio/prompts` (`consts.json` `studio.promptsRoute`)
lists the agentic prompts the package ships in `agentic/` -- with `agentic/prompts.json`'s marks, which way
of working each belongs to and who sends it -- beside the hub's own (its `agentic/` and
`agenticExtensionPath`), each with its whole text and its last change from git, and beside the active
Space's own `agentic/`, read from its repository through `gh` behind the Design tab's gate (`group:
space`, `ref: space/<name>`); the response's `space` says which Space that was and whether its repository
is this package's own origin (`isToolkit`), so the web never works that out. It is the Studio's, so
core and ungated; a shipped prompt that belongs to an add-on that is off is left out, and its read is a
404. The web picks the Space's set by how you work there; the agent serves them all
([`modules/studio.md`](modules/studio.md#the-routes)).

**One module route renders text another half renders too.** Team Agile's
`GET /api/ritual/standup?space=<slug>` (gated on `features.solitaireAgile` as resolved -- the switch on AND
the active Space answered `agents` -- 404 when off) fills the
standup from the Space's GitHub labels and issues -- or, for a local Space, from its cards in the hub
 -- and returns it as data *and* as `text` (and, at the grain of the work, as `work.text` -- standup prose) -- the same
bytes the CLI's `Standup` prints, held to one fixture (`Tests/fixtures/rituals/`) from both suites --
so the web shows `text` verbatim and parity is one string comparison. The one part only the agent
has is `spoken`: with a model key, each worker's sentences re-said by the model and held by a
guard both halves implement over one fixture (`standup-dress.json`), the prose kept wherever a fact
was added, dropped or changed; the played view reads it. It stores nothing, and a Space
with no reachable GitHub tracker still answers 200 with the ritual and the reason
([Team Agile](modules/solitaire-agile.md), "The file shape, and how a standup is read").
`GET /api/ritual/triage` (V1) is the same shape for triage, against `Tests/fixtures/rituals/triage.json`;
its answers are the CLI's `Route`, which the web runs only as `POST /api/cmd/Route` -- the module's
first write is a tracker label, through the bridge like every other. The hand-off block (`StartWork`)
has no route at all: the page's copy box asks for it as `POST /api/cmd/StartWork`, so the CLI is its one
implementation -- and so is the launch (`StartWork -Launch`, a session in a worktree), whose availability
`/api/env` reports as the top-level `startWorkLaunch` (`claude` on the agent's PATH).

### A card's pictures

`GET /api/assets/{space}/{card key}/{file}` ([the card](hub/cards.md), "A card's pictures")
serves a picture from that Space's `assets/` -- the folder beside `current/` and `archive/` where the CLI's
`Cover` verb copies a card's cover. It is core, with no flag, and it writes nothing: the path is resolved
and then checked to lie inside that Space's `assets/`, one folder deep, an image type, with the content
type from the extension; anything else is a 404. The card model's `cover` and `before` are URLs of this
route, or `null` ([the card](hub/cards.md#a-cards-pictures----spaceassets)), which is all the web reads:
the board's card face, the list's thumbnail and the card page draw what the agent serves. Attaching from
the browser keeps the one writer: `POST /api/assets/upload?name=<file>` takes the file's
bytes as the body (no multipart, one blob) into a temp file under the system temp folder and answers its
path, writing nothing into the hub (the bridge removes that folder when the verb returns, and the agent sweeps day-old ones at start); the web then runs `Cover <card> <path>` -- or `NewPrompt -Cover` /
`-Before <path>` from the + dialog -- through the bridge, and the verb copies the file in and writes the
line. The route refuses only what the verb would (a type outside `assets.coverExtensions`, a size over
`assets.coverMaxBytes`, no bytes), so the browser hears it before a shell starts.

### The bridge

A read stays native Python; a write goes into this repo's own PowerShell, so there is exactly one
implementation of archiving a card, opening a PR or closing a work item, and the web UI and the
terminal cannot drift:

```bash
$ curl -s -X POST localhost:4100/api/cmd/Archive \
       -H 'Content-Type: application/json' -d '{"params":["402-timeout-on-large-files.prompt.md"]}'
{"command":"Archive","status":"success","exit_code":0,
 "output":"Moved: test/current/402-... -> test/archive/402-...","error":null,"duration":3120}
```

That request moved the file and stamped `**Closed:** <today>` into it -- it *is* `tkArchive`: the
agent forks this repo's own PowerShell and calls the function. **The allowlist is the CLI's command
table, not a list `agent/ado/bridge.py` keeps of its own** -- it reads `Get-P20CommandMap`, cached
against the modification times of `utilities.psm1`, the two config files and
`Config/*.commands.psd1`, so a verb added the usual way (see [Contributing](CONTRIBUTING.md)) is
bridgeable on the next request with no backend edit, and switching a module on makes its verbs
callable on the next request too. Parameters travel as process argv -- no command string is built
or parsed on either side -- and a reply is always a `CommandResponse` with one of four statuses
(`success`, `error`, `rejected` -- nothing ran, `timeout`). `agent/README.md`, "The bridge" has the
rest: which PowerShell it picks, the size limits, per-verb timeouts, and the exit-code contract a
verb that catches its own failure still honours.

## The web UI

`web/` is a React + Fluent UI app in two parts: a **shell** that owns the chrome, and **modules**
that own everything else. `web/README.md` has the layout, the `ToolkitModule` interface field by
field, every module's own surface, and the production path in full.

```bash
cd web && npm ci && npm run dev        # http://localhost:5174 -- or the next free port, which it prints
```

The dev server proxies `/api` to the agent, which must already be running -- `tkWeb -Dev` is the
one-liner for both, and starts, stops and reports each of them ([the CLI's `Web` and `Agent`
rows](CLI.md#the-other-two-halves)). Production is `docker compose up --build` in `web/` instead;
[`web/README.md`, "Production"](../web/README.md#production) has the detail, including why the
image build must not need `web.agentPort`.

**A second entry: the landing page.** `web/landing.html` is the page GitHub Pages serves to a visitor
who has installed nothing -- the README's first screen with the commercial playing. It is built by the
same Vite config in its own mode (`npm run build:landing`, to `dist/landing/`) and imports the deck
engine, the commercial and its clips as source and nothing else of the app: no router, no store, no
agent, no flag. Its words are read from `README.md` and `THIRD-PARTY-NOTICES.md` at build time, so it
retypes nothing; `.github/workflows/pages.yml` deploys it on every push to `main`.
[`web/README.md`, "The landing page"](../web/README.md#the-landing-page) has the bands and the rules.

### The shell owns the chrome; a module owns the rest

The shell (`src/shell/`) keeps the theme, the nav bar, the `Loading toolkit...` gate on `/env`, the
store, and the `<Routes>` table -- and no
opinion about *which* routes, nav entries or cards there are. A module is one exported object: an
`id`, an optional `feature` flag, `routes` mounted verbatim, and optional `nav`, `homeCards` and
`systemCards` builders; the shell filters modules by `env.features[module.feature]`. **Off means
absent** -- no route, no nav entry, no card, and nothing fetches the module's data; not hidden, not
disabled, not a 403 -- and no bytes: `registry.ts` imports only each module's
descriptor, and the module's pages, cards and header items are lazy chunks fetched when first drawn
(`web/src/shell/lazy.tsx`; `web/README.md`, "Off means absent", is the long version).

**A feature flag has a scope, and the default scope is the engineer.** Nothing but the ADO core is
org-dependent, so a top-level `features` key holds steady across `activeSpace`; the exception is the
ADO core's own org-scoped flags (`sprintAwareness`). `GET /api/env` serves the merged view and
`Tests/test_features.py` pins the rule. Two modules have no flag: the ADO module -- an install
that switched it off would have no home page -- and the Studio, core from the first run
(D-S13): its descriptor declares no `feature`, so it always mounts, and
its pages are still lazy chunks, because lazy is about bytes, not about being optional.

**The web UI changes the configuration it reports, through the CLI and nowhere else.** The avatar's
settings drawer holds machine keys, the active Space's fields and two org actions; every save is
`PUT /api/config`, which runs `tkConfig` through the bridge. [`web/README.md`, "The Configuration
section"](../web/README.md#the-configuration-section-and-what-it-does-not-do) has the detail; [the
schema itself is Configuration's](CONFIGURATION.md).

**The avatar menu is the one Space switcher** (`src/shell/AvatarMenu.tsx`): Theme, Space and the
registry's settings links. Its Space entry lists `config.spaces` from `/env` and a choice runs
`SwitchSpace` through the bridge. Up to `SPACE_QUICK_MENU_THRESHOLD` (8) Spaces it is a plain
submenu; past it the same entry opens a searchable quick menu with **View all**
(`src/shell/SpaceQuickMenu.tsx`) -- same call, same order, nothing new stored. [`web/README.md`, "The
avatar menu, and arriving at a setting"](../web/README.md#the-avatar-menu-and-arriving-at-a-setting)
has the detail; [`SCENARIOS.md`](SCENARIOS.md) tables the two counts.

## Trust model

The Toolkit is one person's workstation tooling, and its trust model is that it stays on that
workstation. Nothing in the agent authenticates a caller: there are no accounts, tokens or sessions.
So the boundary is **where each half listens**, plus the fact that everything which changes a card
goes through one door. [`SECURITY.md`](../SECURITY.md) is the two-paragraph version and says how to
report a weakness; this is the long one, with the file that holds each part.

### Who may call the agent

Any process on the same machine, and nothing else. **The agent binds to the loopback address and
nowhere else.** `Scripts/Start-Agent.ps1` -- the one place the agent is started, by `tkAgent` and by
`tkWeb -Dev` through it -- passes uvicorn `--host` with the value of `consts.json` `agent.bindHost`,
which is `127.0.0.1`. It is deliberately not a setting: the launcher has no host parameter,
`config.default.json` has no key that names an interface (its network keys are `web.agentPort` and
`web.corsOrigins`), and `-Port` changes the port and nothing else. Another machine on the network
cannot reach the agent.

`Tests/test_consts.py` (`TheAgentListensOnTheLoopbackOnly`) holds this. The host the contract names
must be a loopback address and never a wildcard; the launcher must read it from the contract and pass
it as `--host` in the only place it starts uvicorn; no shipped setting, launcher parameter or `tkAgent`
switch may name an interface; and the dev server and the Docker image below may publish no more than
the loopback. Setting the default to `0.0.0.0` fails them.

**Do not put the agent behind a proxy or publish its port.** Anything that can reach it can run every
verb the bridge exposes, with your credentials. If you need it from elsewhere, put a layer you trust
that authenticates in front of it and keep the agent on the loopback; widening the bind is not the
answer.

### The web UI is served to the same machine

Vite's development server is given no `host`, so it listens on localhost: `web/vite.config.ts` has no
`host:` line and no npm script passes `--host`. The Docker image publishes its port as
`127.0.0.1:5174:5173` in `web/docker-compose.yml` -- not `5174:5173`, which would publish it on every
interface of the machine. The image's nginx proxies `/api/` to the agent on the host through
`host.docker.internal`, so the container and the agent are two processes on one machine.

A note on Docker, and where it works. Docker Desktop (macOS, Windows) runs containers inside a
lightweight VM whose networking layer gives `host.docker.internal` a special resolution that reaches
a listener bound to the host's loopback -- the combination both runs below are checked against.
Native Linux Docker Engine has no such VM, so `host-gateway` resolves `host.docker.internal` to the
container's real bridge-network gateway address instead, a different network namespace from the
host's loopback interface: a listener bound only to `127.0.0.1` is not reachable from the container
through that route. This follows from Docker's own documented bridge-network model, not from a run
on a real Linux host -- nobody has run this combination on one, but the reason it will not connect is
already known. **The Docker path in this repository is for Docker Desktop.** On native Linux, skip
Docker and run the agent and the web UI directly on the host instead -- `tkWeb -Dev`, which already
works there ([Quickstart](QUICKSTART.md), "Supported platforms"). An opt-in, non-default bind
address that would let the Docker path work on native Linux too is a known gap, not built
([Known gaps](KNOWN-GAPS.md)). Do not rebind the agent to a wider address to make the container reach
it.

### CORS

The agent accepts cross-origin requests from the origins in `web.corsOrigins`, which defaults to the
two dev-server origins (`http://localhost:5173` and `http://localhost:5174`), for the methods its
routes use (`GET`, `POST`, `PUT`). It is not a wildcard. CORS is a browser's rule about which pages
may read a response, so it is a second fence for the browser case and **not authentication**: a
process on the machine is not a browser and is not subject to it. Adding an origin to
`web.corsOrigins` lets a page from that origin read the agent's answers and run the bridge as you, so
add only an origin you serve yourself. The production image needs none: it serves the page and proxies
`/api/` from one origin.

### The bridge runs the CLI's command table and nothing else

`POST /api/cmd/{name}` forks a child `pwsh` for a verb that is a row in the CLI's own command table
(`Get-P20CommandMap`; [the bridge](#the-bridge)). A name that is not in it is answered
`status: rejected` and nothing runs; so is a request with more than 32 parameters or a parameter
longer than 4,096 characters, and so is a verb of a module that is switched off, because it is not in
the table. Parameters travel as process argv, with no command string built or parsed on either side,
so a parameter cannot become a second command. A verb that runs past its timeout is killed. The
bridge is a way to type a verb, not a way to run a script: it cannot be given a file to run, and a
verb that refuses (a card in `current/` is never overwritten) refuses in the browser with the same
sentence it prints in a terminal.

### What the web half can and cannot change

The web UI reads through the agent, and **nothing in it changes a work-item card except through the
CLI**, by the bridge: no route creates or overwrites a card in `current/`, and every agent-side edit
of an existing card goes through one writer, `core/cards.write_card_text`. The agent does write
natively in these places, and no others:

| Route | What it writes | Notes |
| --- | --- | --- |
| `POST /api/switch-mode` | `activeSpace` in `config.local.json` | Refuses a slug that is not a declared Space |
| `PUT /api/config` | a setting, by running `Config -Set` through the bridge | The schema decides what may be set; a refusal comes back as a typed body |
| `PUT /api/manager/{filename}` | an existing 1:1 session (opt-in module) | Edits a file that exists; creating one (`POST /api/manager`) runs the `NewMeeting` verb, which refuses an existing session |
| `POST /api/assets/upload` | one image, into a fresh folder under the system temp directory | Never the hub; the `Cover` verb copies it in, through the bridge |
| `POST /api/comms/send` | nothing on disk; posts to a Teams webhook | Needs the webhook variable set; `dryRun` runs every gate and sends nothing |

Anything else the browser can make happen -- archiving a card, opening a pull request, closing a work
item -- is a verb run through the bridge, with the same checks the terminal applies.

### Where secrets live

In the environment, and nowhere else. The model key (`ANTHROPIC_API_KEY`, with `CLAUDE_API_KEY` as the
fallback name) and each Teams webhook URL (`TEAMS_WEBHOOK_<RECIPIENT>`) are read from the process
environment, which the package's `.env` fills at import. `.env` is not committed, and
[`.env.example`](../.env.example) is the committed record of what it may hold and says that each value
is a secret. `Config -Set` writes `config.local.json` and `hub.json` and has no setting for either, and
nothing in the tree writes a secret to a file. Tracker access uses the `az` or `gh` session already on
your machine; the Toolkit stores no token for either.

### What it does not defend against

Someone who already runs code as your user can do everything above directly, so the Toolkit does not
try to stop them, and it adds nothing to the file permissions that protect the hub from other users of
a shared machine. If either matters to you, do not rely on the Toolkit for it.

## Repo layout

```text
utilities.psm1          Module: config merge, command map, module loader, prefix registration
config.default.json     Orgs, commands, defaults, the web block (committed)
config.local.json       Machine-specific overrides and feature flags (gitignored)
consts.json             The contract file: the literals all three halves parse (committed)
ruff.toml               The Python linter's settings, for agent/ and Tests/*.py (docs/CONTRIBUTING.md, "Lint")
Config/                 One opt-in module's CLI contribution per pair (D-CM, docs/modules/README.md)
  growth.commands.psd1    Feature, Commands, Order, Help -- a DATA file, it cannot run code
  growth.commands.ps1     The five wrapper functions
  communication.commands.psd1 / .ps1   The same, for the three communication verbs
  organize.commands.psd1 / .ps1        The same, for the two organize verbs
  solitaireAgile.commands.psd1 / .ps1  The same, for the three Team Agile verbs
  settings-workflows.json The question each optional surface answers
  ceremonies.json         Team Agile's ceremony slots
  standup-vocabulary.json Team Agile's standup vocabulary
Scripts/                One script per command, core and module alike
  Get-Consts.ps1          The CLI's reader for consts.json -- dot-sourced, not a verb
  Invoke-TrackerRead.ps1  Invoke-P20TrackerRead, the one gh/az call (stderr as text on 5.1 too) -- dot-sourced
  Get-AdoToken.ps1        The Azure DevOps token, its headers and the 401/403 advice, for every ADO script -- dot-sourced
  Initialize-CliFallbacks.ps1  Get-CliPrefix and Write-CliError for a script run with no module -- dot-sourced
Prompt20Toolkit/        Autoload shim installed into the module path
templates/              Prompt file templates by work item type, plus the module ones:
                        Training, Presentation, Goal (growth), ManagerSession (communication),
                        DesignNote (the Studio, core)
agentic/                Six card-workflow prompts, pr-suggest, new-issue, four module
                        prompts, and prompts.json -- which way of working each belongs to,
                        who sends it and its category (the Studio's Prompts card reads it)
spec/                   Where a product may keep its specs; this tree keeps only the README ([spec/README.md](../spec/README.md))
samples/hub/            The sample hub `tkStart` copies out on a first run: one `local` org, Demo, with cards,
                        meetings, a goal and a review. Read-only here -- it is never used in place
design/                 Where a product may keep its design notes; this tree keeps only the README ([design/README.md](../design/README.md))
.github/workflows/      verify.yml, the suites in CI; pages.yml, the landing page's deploy (docs/TESTING.md, "In CI")
AGENTS.md  CHANGELOG.md  VERIFY.md  the agent guide, the change log, the verification gates
docs/                   The documentation. The root README is the map; each subject has one owner
  QUICKSTART.md           Requirements, install, the first run, a first card, the web UI up
  CONFIGURATION.md        tkConfig, the three config files, consts.json, the hub's hub.json
  CLI.md                  The prefix, the workflow, the command reference, tiers, errors, the log
  TESTING.md              tkSetup, the four runners, the suites and their counts
  ARCHITECTURE.md         How the three halves fit; the agent and the web UI in overview; this layout
  SCENARIOS.md            Every configuration a machine can be in, what it shows, the test that holds it
  KNOWN-GAPS.md           The roadmap of known gaps, each with what you see and its issue
  ROADMAP.md              The order the design ideas get built in; the backlog is GitHub Issues
  CONTRIBUTING.md         The contributor's first page: setup, the runners, the rules a change meets
  modules/README.md       The modules, "off means absent", and D-CM
  modules/deck.md         The deck module, briefly -- it points at Connected Deck's README
  modules/ado.md          Azure DevOps, the add-on, end to end -- it stands alone, as each of these does
  modules/growth.md       Growth, end to end -- written by its builder
  modules/communication.md  The same for communication
  modules/organize.md     Organize (reminders), end to end
  modules/solitaire-agile.md  Team Agile (the standup, triage, Route), end to end
  modules/studio.md       The Studio (core, no switch): the foyer across every Space, end to end
  modules/lounge.md       The Lounge, the ambient room
  hub/README.md           THE DATA MODEL: what is in a hub, and which document owns each shape
  hub/cards.md            The card -- filename, heading, parsed tokens, footer, derived state, the served model
  hub/growth.md           The file-shape contract for growth/, reviews/, resume/
  hub/manager.md          The session-file contract for manager/
  hub/reminders.md        The file contract for reminders/
  hub/design.md           The file contract for design/, the Studio's seed drawer
agent/                  The FastAPI agent -- see agent/README.md
  app.py                  The app: CORS, the /api router, module mounting, static serving
  core/                   config, config_routes, consts, env, identity, tier, parsers, cards, clock, hosts,
                          model, surfaces, assets, child, log, log_writer -- always on
  ado/                    status, pr_comments, accounting, reporting, sprint, design, docs, bridge
  ado/Get-WeeklyBilling.ps1   Module-private: /billing shells out to it. Not a CLI command
  growth/                 growth, reviews, resume -- one router, gated on features.growth
  communication/          manager (the routes) + comms (the engine, carried whole)
  organize/               reminders -- gated on features.organize
  studio/                 the hub's design/ notes, and the + dialog's repositories (NewSpace -Discover) -- core, mounted with no gate (D-S13)
  solitaire/              the standup and triage, from a GitHub Space's tracker -- gated on features.solitaireAgile
web/                    The React shell + modules -- see web/README.md
  landing.html            The landing page's entry, the second one; built by `npm run build:landing`
  src/landing/            The landing page: its own copy (copy.ts), the banner, the three ways, the commercial
  src/shell/              App, main, theme, store, api, registry, cards, consts (../consts.json)
  src/modules/ado/        The always-on core: index, routes, api.ado, every card
  src/modules/growth/     GrowthPage, Goals, ReviewArchive, SkillsSnapshot, SkillsPage
  src/modules/communication/  OneOnOne, ManagerSessionPage, sendButton, paths, Timer
  src/modules/organize/  src/modules/deck/  src/modules/lounge/  src/modules/solitaireAgile/   The other four modules
  src/modules/studio/     The Studio, core with no flag (its pages lazy): the foyer -- the Spaces card, one row per Space, one filter
  src/shared/  src/hooks/  src/utility/    Reusable UI, reusable logic, formatters
  tests/smoke.mjs         Playwright: the two halves together in a browser
  tests/smokeStack.mjs    the servers a smoke mode owns: a scratch package, its agent, a Vite
  tests/smokeStudio.mjs   --studio: the Studio's contract on those servers
  tests/smokeMatrix.mjs   --matrix: each module flag alone, the flip, fresh and hostile storage
Tests/                  Suites -- Test-*.ps1 (PowerShell) and test_*.py (the agent)
  fixtures/parsers/       Four prompt files both parsers are pinned against
  fixtures/hub/           A prompt store with no toolkit in it and no .git: two cards under
                          test/current/, plus growth/current/ (one artifact per type),
                          reviews/test/2026/..., resume/resume.md and manager/current/
                          (three sessions, and deliberately no archive/)
  fixtures/hub-spaces/    the smoke's --studio hub: one Space of each kind under hub/, and a
                          config.local.json seed carrying a leftover features.studio
```

Templates live here, in the tool, because they are how prompts are normalised -- part of the
software, not part of your data.

`Tests/` holds both languages on purpose. They test one contract from two sides -- the state a
prompt file derives, and the tier a machine is at -- and splitting them by language would make
drift between the halves someone's second job.
