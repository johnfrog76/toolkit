# The agent

The agent is the FastAPI half of the Toolkit: the read layer the web UI talks to, over the same
config and prompt store the CLI reads, and the bridge that runs a CLI verb for everything that
writes. It is for serving the browser without becoming a second implementation of the workflow.
About 8,500 lines of Python across thirty-three files, plus two PowerShell scripts it owns
privately.

How the three halves fit, `/env` in overview and the repo layout are
[`docs/ARCHITECTURE.md`, "The agent"](../docs/ARCHITECTURE.md#the-agent). This file is the detail:
what the agent reads, what it refuses to assume, every route, and the bridge's contract.

## Run it

```bash
# On Windows, `python` or `py -3` -- see the Requirements table in docs/QUICKSTART.md.
python3 -m pip install -r requirements.txt       # fastapi, uvicorn[standard], pydantic  (Windows: python or py -3)
python3 -m pip install -r requirements-dev.txt   # the above plus pytest, httpx and ruff, for the tests and lint
cd .. && python3 -m uvicorn agent.app:app --port 4100
```

From the CLI instead: `tkAgent` starts it on the port `web.agentPort` names, backgrounded, with
`agent.log` and `agent.err.log` at the repo root; `tkAgent -Status` probes `/api/health`;
`tkAgent -Dev` adds `--reload`. It refuses with a readable message, not a traceback, when `uvicorn`
or `fastapi` is missing. The by-hand form above is what it runs. The launcher's other switches are
[`docs/CLI.md`, "The other two halves"](../docs/CLI.md#the-other-two-halves).

**It finds the interpreter rather than assuming one**, in `Scripts/Resolve-Python.ps1`: `python`,
then `py -3`, then `python3` on Windows; `python3` then `python` everywhere else. Each candidate is
**run**, not just looked up, because the name that resolves on Windows is usually the Microsoft
Store alias, which answers `Get-Command` and executes nothing -- only an interpreter that reports
major version 3 is taken. `tkAgent` prints the one it found (`Python: py -3 (3.12.10)`) and every
message that tells you to type a Python command names that one, not `python3`. When there is none,
the error lists what it tried, in order.

**From the repo root, not from `agent/`.** `agent` is imported as a package, and
`core/config.py` walks up from its own file -- `agent/core/config.py` → `agent/core` → `agent` →
repo root -- to find `config.default.json`. Started from inside `agent/`, the import fails before
any of that matters.

The agent keeps no state between requests. Config is re-read on every request that touches it: the
two JSON files are tiny and on local disk, so the I/O is negligible, and it matches how the CLI
reads config on each shell invocation. A `tkSwitchSpace` in another terminal, or a hand-edited
`config.local.json`, takes effect on the next fetch rather than on a restart.

## Layout

```text
agent/
├── app.py                  the FastAPI app: CORS, the /api router, module mounting, static serving
├── requirements.txt        the runtime packages, as floors (`>=`) -- runtime only
├── requirements-dev.txt    the runtime file plus pytest and httpx, for `pytest Tests/`, and ruff, pinned exactly (`==`)
├── core/                   always on
│   ├── config.py             config merge + hub resolution -- the hub is config, not layout
│   ├── config_routes.py      GET /config/schema, GET /config, PUT /config -- every write through the bridge
│   ├── consts.py             the reader for ../consts.json, the literals all three halves parse
│   ├── env.py                GET /health, GET /env, POST /switch-mode
│   ├── surfaces.py           GET /surfaces -- the CLI's optional-surface inventory, as one answer
│   ├── cards.py              write_card_text: the agent's one writer for a hub file that already exists (today: the meeting-session save)
│   ├── clock.py              a timestamp to the reader's LOCAL day, the one way
│   ├── child.py              run_read: every gh, az and git child read as UTF-8, never an empty success
│   ├── hosts.py              which PowerShell a child process gets: pwsh, else powershell.exe
│   ├── identity.py           who "me" is: config email, else branchUser-as-address, else az. Cached 45s
│   ├── log.py                POST /log, GET /log-entries, GET /test-history
│   ├── log_writer.py         the tab-separated writer, beside the CLI's own log (P20_USAGE_LOG_DIR moves both)
│   ├── disk_cache.py         the agent's on-disk cache: the user cache folder, or P20_AGENT_CACHE_DIR; never the hub or the package
│   ├── parsers.py            the canonical prompt-file parsers -- pure, content-only
│   ├── assets.py             a card's pictures: card_image(), GET /assets/{space}/{key}/{file}, POST /assets/upload
│   └── tier.py               the tier decision, parity-pinned against PowerShell
├── ado/                    the tracker surface, Azure DevOps and GitHub -- always on, no flag
│   ├── status.py             GET /status, GET /status/{filename}
│   ├── pr_comments.py        the PR-comment side record, plus the model-assisted suggest (through core/model)
│   ├── accounting.py         the tracker's ledger: PRs, work items, issues, milestones, dashboard, pipelines, deploys
│   ├── design.py             GET /design, GET /design/search, GET /design/{path} -- a GitHub Space's design/ and spec/
│   ├── docs.py               GET /docs, GET /docs/{path}, GET /docs/asset/{path} -- a GitHub Space's README.md and docs/
│   ├── repo_read.py          folders of a GitHub repo through gh: one GraphQL call for the shape, texts batched, parsed rows on disk by blob sha
│   ├── reporting.py          reporting over archive/ and git log: billing, the four engagement reads
│   ├── sprint.py             sprint awareness, gated per org
│   ├── bridge.py             POST /cmd/{name} -- the route, and the derived allowlist
│   ├── bridge.ps1            module-private; the child PowerShell the bridge runs
│   └── Get-WeeklyBilling.ps1 module-private; /billing shells out to it
├── growth/                 opt-in, features.growth -- one router, one gate
│   ├── __init__.py           growth_router(): the gate, declared once on the router
│   ├── growth.py             GET /growth, GET /growth/{filename}
│   ├── reviews.py            /reviews, /reviews/{folder}, /review-preview, POST /review/generate
│   └── resume.py             /resume, /resume-preview
├── communication/          opt-in, features.communication
│   ├── __init__.py           re-exports manager.py's router, which carries the gate
│   ├── manager.py            /manager (GET/POST), /manager/{f} (GET/PUT), /comms/send, /rewrite
│   └── comms.py              the communication engine
├── organize/               opt-in, features.organize
│   ├── __init__.py           the router `app.py` mounts, gated per request
│   └── reminders.py          GET /reminders -- read only; every write is a verb through the bridge
├── studio/                 core, no flag (D-S13) -- always mounted
│   ├── __init__.py           the router `app.py` mounts -- notes', spaces', prompts' and the ledger's together
│   ├── ledger.py             GET /studio/ledger -- every GitHub Space's report, runs and visibility for the Spaces card: one gh api graphql call, kept on disk 600 s
│   ├── notes.py              GET /studio/design, /studio/design/search, /studio/design/{path} -- the hub's design/ notes, read only
│   ├── prompts.py            GET /studio/prompts, /studio/prompts/{ref} -- the agentic prompts, ToolKit's and yours, read only
│   └── spaces.py             GET /spaces/candidates -- your repositories for the Spaces card's +, NewSpace -Discover through the bridge
└── solitaire/              opt-in, features.solitaireAgile
    ├── __init__.py           the router `app.py` mounts, gated per request
    ├── standup.py            GET /ritual/standup -- the standup, derived from a GitHub Space's tracker; stores nothing
    ├── remind.py             GET /ritual/standup/remind, POST /ritual/standup/attend -- the reminder to attend; writes only through Organize's verbs
    └── triage.py             GET /ritual/triage -- the open issues by milestone (V1); the answers are Route, through the bridge
```

`core` is always on, and so are `ado` and `studio` -- the Studio is core from the first run
(D-S13), its router mounted with no gate. `growth`, `communication`,
`organize` and `solitaire` are the **opt-in modules** with an agent half, each a sibling package with its own routes behind its own flag. The
web-only modules, `deck` and `lounge`, have **no package here at all**: a deck is compiled into the
web build and its voices are baked files, so there is nothing for the agent to serve -- and
`/narrate` stays on the deliberately-absent list below.

Nothing in this package reaches outside itself for code, and nothing derives the prompt store from
where the package happens to live.

## The hub is config, not layout

This is the point of `core/config.py`: **the prompt store is never the parent folder of the toolkit
directory.** Resolving it that way silently requires the toolkit to live *inside* the store, and it
does not have to. The hub comes from configuration alone:

| | Resolves to |
| --- | --- |
| `promptsRoot` (config) | The hub root. Relative values resolve against the repo root, so a committed config stays portable |
| `spaces[].promptsFolder` | The active org's subfolder inside the hub |
| `PROMPTS_ROOT` (environment) | An explicit override, and it wins. It survives only as an override -- never as the primary source |
| `P20_ACTIVE_SPACE`, `P20_FEATURES` (environment) | Its two siblings (`consts.json` `env.activeSpace`, `env.features`): stand-ins for `config.local.json`'s `activeSpace` and its top-level `features` block (a JSON object, replacing the block; `{}` is no flag set), applied in `load_config`. Set by `tkWeb -Dev -Fixture` for the smoke, so no file is written; the module reads the same two ([Configuration](../docs/CONFIGURATION.md#overrides-from-the-environment)) |
| Neither set | `hub_root()` returns `/nonexistent-prompts-root`, a path that cannot exist |

That last row is a deliberate design choice, not a fallback. Returning an impossible path rather
than `None` means the `.exists()` guard every read route already has does the right thing with no
second code path: nothing raises, every read degrades to empty, and `/env`'s `promptsVolume` check
says which of the three states you are in, in words --

```text
promptsRoot is not set in config.default.json or config.local.json
/path/to/hub -- not found
/path/to/hub -- readable
```

`load_config()` merges `config.default.json` then `config.local.json` with exactly the semantics
`Merge-SpacePatch` uses in `utilities.psm1`: nested maps merge key by key, scalars and lists replace
wholesale. `Tests/test_config.py` asserts that agreement, because a config merge that behaves one
way in the CLI and another in the agent is a bug you only find in production.

Per-org patches in `config.local.json` are keyed by slug and applied before the active Space is
chosen. An org whose `status` is not one of `active`, `local` or `archive` is **failed closed** to
`local` with a WARN in the log -- an unknown status must never reach Tier 1.

### The hub declares its own orgs

There is a third source, and it sits between the two files: an optional `<promptsRoot>/hub.json`,
read by `read_hub_manifest()`. The contract -- what a hub may declare, the resolution order
(`config.default.json`, then the hub's orgs merged by slug, then `config.local.json`'s patches), and
why -- is [`docs/CONFIGURATION.md`, "The hub declares its orgs"](../docs/CONFIGURATION.md#the-hub-declares-its-orgs).
What the agent does with it:

- A machine-scoped key in `hub.json` (`activeSpace`, `promptsRoot`, `email`, `branchUser`, `wsRoot`,
  `web`, `commands`, top-level `features`) is ignored with a WARN naming the key, as is an
  engineer's feature flag on a hub org; `ORG_FEATURES` (`sprintAwareness`) is honoured there exactly
  as on a shipped org. An org without `slug` or `promptsFolder` is skipped with a WARN; a malformed
  file is a WARN naming the path, never a raise; an absent file changes nothing.
- `/env` reports `hub` (`manifest`, `path`, `orgs`) and a `hubManifest` check row.
- `load_config()` reads `config.default.json` and `config.local.json` through `read_config_file`, which
  never raises: an unreadable file, malformed JSON or a top level that is not an object is logged as a
  WARN naming the path, the file is skipped (the defaults, then `hub.json`, stand), and the sentence
  lands in `load_config()["configProblems"]`. `/env` reports it as a failing `configLoaded` check row (the "Settings files" row),
  so a typo in `config.local.json` costs a red row rather than the agent. `POST /switch-mode` reads the
  local file the same way and answers 409 with that sentence instead of writing over a file it could not read.
- `folders` names the hub-root siblings. `DEFAULT_HUB_FOLDERS` holds the defaults and
  `hub_folder(name)` is the one accessor the modules read; no module types a folder name.
- `storeSync` (`git` or `none`, `STORE_SYNC_VALUES`) resolves in the orgs' order and lands in
  `load_config()["storeSync"]`; a value that is neither warns and the configured one stands. The
  CLI reads the same three sources into `$global:P20Config.StoreSync`, which is what `Sync` and
  `Archive` gate on -- nothing in this half acts on it.

`Tests/test_hub_json.py` pins every rule and, with `Tests/fixtures/hub-parity`, pins it against the
CLI's answer as well.

### Six layout assumptions it does not make

Each of these would assume a *repo* layout where only a *hub* is guaranteed:

| The assumption | What the agent does instead |
| --- | --- |
| `Get-WeeklyBilling.ps1` lives at `PROMPTS_ROOT/toolkit/Scripts/` -- the hub contains the toolkit | A path relative to the agent's own tree: `agent/ado/Get-WeeklyBilling.ps1`, resolved from `config.py`'s `BILLING_SCRIPT` |
| The narration voice and deck directories live under the hub's `web/` | Nothing here reads them; they belong with `/narrate`, which the deck-engine spec owns |
| `stress-log*.json` sits at the hub root | Kept. A hub-root sibling is a legitimate thing for the hub to hold; only the *toolkit* being there is wrong |
| A per-org `billing/` folder exists | None is read. Billing derives from the cards' own dates, `**Created:**` to `**Closed:**` -- see [`Get-WeeklyBilling.ps1`](#get-weeklybillingps1) |
| CORS origins are the literal ports 5174 and 5173 | `web.corsOrigins` in config, with those two as the default when the list is empty or absent |
| `git log` runs with `cwd` = the hub, so the hub is a git repository | Kept, failing soft. `/env` reports `gitHistory` separately so a non-versioned hub is visible rather than fatal |

The static web build is the same class of question answered the other way: `app.py` serves
`web/dist/client` from **this repo's** tree, never through `promptsRoot`, because the prompt store
holds cards, not a front end. The same logic puts `usage.{machine}.log`,
`test-results.{machine}.log` and `test-summary.{machine}.json` at the repo root -- they are a
property of the tool, not of the store, and the PowerShell writer already puts them there.
`test-summary.{machine}.json` covers the machine's three halves: `tkTest` and the CLI runner write
it (`Scripts/TestAll-Rules.ps1`), every suite entry carries a `half` (`cli`, `agent`, `web`; consts.json
`tests.halves`, and an entry with none is the CLI's), the agent's and the web UI's runs are one entry each
(`pytest`, `jest`), and a `halves` block holds one record per half -- a skipped half with its reason.
`core/log` serves both on `GET /test-history` (`machines[].halves`, `suites[].half`), and for a file
written before the halves it sums the CLI half from the suite entries. A suite's `result` is `pass`,
`fail` or `warn` -- a `warn` is a suite that ran no tests, counted as neither a pass nor a
failure: it is one of the legacy CLI half's `skipped`, it shows `ok` as its detail, and it does not break
the history's streak.

## Tier

Tier is a statement about **capability**, not about whether the tracker happens to have data right
now.

| Tier | Means |
| --- | --- |
| 1 | Full ADO access |
| 2 | Local only |
| 3 | Minimal -- no hub, or no git |

`_tier_from(repo_ok, git_ok, az_ok, ado_reachable, status)` in `core/tier.py` is the decision, and
it is **pure** -- no I/O -- so it can be parity-tested. `Scripts/Resolve-TierDecision.ps1` implements
the same formula in PowerShell, and `Tests/test_tier_parity.py` runs both against the canonical
formula over every input combination and prints `all 80 combinations agree across PowerShell and
Python` (16 boolean combinations × 5 status values, the five including two deliberately invalid
ones).

`_resolve_tier` gathers the inputs and defers. It skips the ADO probe entirely when the probe cannot
matter -- a missing hub, no git, or an org declared `local`/`archive` -- and the probe itself is
`az devops project list`, not an HTTP request.

### The probe blocks, so it runs off the loop and only every 45 seconds

`_resolve_tier` **shells out**. It costs a cold `az` start -- 3–4s on the PC, and up to the 15s
timeout when `az` hangs -- and every route that resolves tier, `/env` included, runs it through
`asyncio.to_thread`. Called inline from an `async def`, the probe holds the event loop, and for its
length the agent serves **nothing else**: `/health`, which makes no `az` call at all, queues behind
it, and the web shell gates every page on `/env`.

Beside that, the answer is cached. `ADO_PROBE_TTL_SECONDS` is **45** -- reachability is a fact about
this machine's ADO access rather than about this request, and the PowerShell half has always treated
it as a session-time fact (`$global:P20Env`). Long enough that a burst of page loads costs one
probe; short enough that an `az login` in another terminal is picked up without restarting the
agent. The cache is keyed by **org URL**, because switching org asks a different question, and two
things bypass it: `GET /api/env?refresh=1`, which the System card's refresh button sends, and
`POST /api/switch-mode`, which clears it outright before answering with the new org's `/env`.

A caller that does not pass `refresh` sees an answer that is at most 45 seconds stale in one
field. The probe is `az`, not HTTP, because an HTTP probe is unreliable here: unauthenticated it
follows a sign-in redirect to a 200, which reads as a false positive, and the Bearer-token path can
302 even when the CLI works. What the toolkit actually uses for every real call is the CLI, so the
CLI is what "reachable" should mean.

### One identity, three routes

`/prs`, `/dashboard` and `/work-items` filter by a person, and the CLI resolves who that is with a
fallback: `Resolve-P20Identity` takes the configured `email` and, when it is empty, asks
`az account show --query user.name -o tsv`. The agent resolves it the same way, so a machine with no
`email` in its own (gitignored) `config.local.json` shows the same pull requests in the browser as
`tkMyPRs` does in the terminal.

`core/identity.py` is the one resolver, and the order is the CLI's: config `email`, else
`branchUser` **only if it carries an `@`** (it is normally a branch-name segment, and ADO wants a
unique name), else `az account show`. It **blocks** -- every caller runs it through
`asyncio.to_thread` -- and it is cached per process behind `ADO_PROBE_TTL_SECONDS`, the same 45
seconds and for the same reason as the reachability probe: the fallback is a cold `az` start and
the dashboard would otherwise pay for one per load. `POST /switch-mode` clears it.

**An empty answer is stated, not silent.** When nothing resolves, each route returns its ordinary
empty shape *plus* a `reason` -- the sentence *No identity: set `email` in config.local.json, or run
`az login`.* -- and writes that same sentence as one `WARN`. That is the CLI's refusal contract (a
stated reason and a hint, never a silent empty result) applied to a route that cannot refuse
outright without taking the page down with it, which is why it is a 200 with a field rather than a
500. The **tier** gate is a different case and stays silent: Tier 2/3 legitimately has no PRs and
the badge already says so. `/work-items` degrades further still -- ADO's own `@Me` names the
signed-in user -- so it runs the query anyway and carries the reason only when the result is also
empty.

The same field carries the other two things that make a Tier-1 list empty for a reason.
An org with no `projects` answers *No
projects configured for `<slug>`: add `projects` to the org in hub.json* before any `az` call is
made. And when `az` itself fails -- a timeout, no `az` on PATH, a non-zero exit, output that is not
JSON -- the **first** failure is the reason, as one sentence naming the command and the project it
was asked about (*`az repos pr list` failed for Demo/WebApp: TF400813: ...*), the same sentence the
log gets. One helper, `_az_json`, runs every `az` call and answers `(rows, why)`, so a caller cannot
take the rows without seeing the failure. The rule about populated lists holds throughout: rows from
one project carry no reason for another's failure. `/dashboard/pipelines/{project}` carries it too,
on `ProjectPipelines.reason`. `Tests/test_accounting_reasons.py` stubs `subprocess.run` inside the
module for every shape of failure.

### How a `gh`, `az` or `git` child is read

Every child the agent reads for data -- `gh`, `az`, the hub's `git` -- goes through one helper,
`run_read` in `core/child.py`. It captures the output and decodes it as **UTF-8 with
`errors="replace"`**, because that is what the three tools write. `subprocess.run(..., text=True)`
with no `encoding` decodes with the locale's code page instead, cp1252 on a Windows console, and
a byte cp1252 has no character for (0x81, 0x8d, 0x8f, 0x90, 0x9d) kills subprocess's reader
thread: the call comes back exit 0 with `stdout=None`, and `result.stdout or "[]"` reads that as
an empty list. That is how the standup's issue read with bodies answered `tracker.ok: true` with
every worker empty on Windows while `Standup` listed dozens. The Mac never sees it, because
macOS is UTF-8.

So a byte that is not UTF-8 becomes U+FFFD and the read goes on, and an output that still did not
arrive raises `ChildReadError`. Each caller states that as its reason, the way it states a timeout
(`<repo>: gh's output could not be read (exit code 0)`), and never as rows. The standup's and
triage's shared reader, `read_tracker` in `solitaire/tracker.py`, also turns any exception out of a reader into `tracker.ok: false` with the
reason. The shell rule is unchanged: on Windows `gh` and `az` run through the shell (`az.cmd`
needs it), so a `&` in an argument is cmd's, and `accounting.unsafe_for_shell` refuses one before
it reaches the helper. A `git` read passes `shell=False`. The bridge and `/surfaces` read their
PowerShell children with an explicit `encoding="utf-8"` too. `Tests/test_child_reads.py` holds the
rule: each read under a stand-in for a cp1252 console keeps a title with an em dash, curly quotes
and `Ï` (UTF-8 `C3 8F`) whole, a dead reader is a reason everywhere, and no `text=True` call in
`agent/` goes without an `encoding` except the two named there that read neither `gh` nor `az`.

### `git_ok` means git is installed

`git_ok` is **git is installed**, not *the hub has a `.git` directory*. Reading it the second way
demands that the prompt store be a git repository and drops a perfectly good hub to Tier 3 -- the
same class of bug as the `promptsRoot` sibling assumption, one layer down. The store does not have
to be versioned (`storeSync` defaults to `none`, and the hub may say otherwise in its own
`hub.json`); whether it happens to be is reported separately, by `/env`'s `gitHistory` row.

## The module packages

`growth`, `communication`, `organize` and `solitaire` each export one router, and the whole router carries one
dependency (`studio` exports one too, with none -- it is core):

```python
api = APIRouter(dependencies=[Depends(require_growth)])
```

**The gate is declared once, on the router, not repeated per route.** A route added later is gated
by existing, which is the opposite of the usual arrangement where it is gated by someone
remembering.

**Off is 404, not 403.** Absent, not forbidden -- "off means absent" is the rule the whole shell is
built on, and a 403 says something different: that the route exists and you may not have it. It does
not exist. With the flags off, `/api/growth`, `/api/manager`, `/api/resume`, `/api/reviews`,
`/api/review-preview`, `/api/resume-preview`, `POST /api/comms/send`, `POST /api/rewrite`,
`/api/reminders`, `/api/ritual/standup` (with `GET /api/ritual/standup/remind` and
`POST /api/ritual/standup/attend`, which sit on the same gated router) and `/api/ritual/triage` all answer 404. `/api/studio/design`
always answers: a `features.studio` left in a config is ignored.

**The check runs per request, not at mount time.** `app.py` includes every router unconditionally;
the dependency re-reads config on each call. Config is re-read on every request everywhere else in
this agent -- a `tkSwitchSpace` from another shell, a hand-edited `config.local.json` -- and gating at
import would make a module flag the one thing in the system that needs a restart, while `/env`,
which the web UI gates on, would already be reporting the new value. One consequence worth knowing:
the OpenAPI schema lists every route whatever the flags say. What moves is the answer, not the
shape.

**Every module reads the hub from `promptsRoot`**, never from where the package sits, and `PROMPTS_ROOT` in
the environment is an explicit override that wins -- the same `hub_root()` the ADO side uses. The
CLI's twin of it is `Get-P20PromptsRoot` in `Scripts/Resolve-HubConfig.ps1`, and
`Tests/test_hub_json.py`'s parity case runs both halves under one `PROMPTS_ROOT` and fails if they
answer with different roots. The
folders they read are hub-root **siblings** of the per-org folders, for the same reason their flags
are the engineer's:

| Package | Hub folders | Contract |
| --- | --- | --- |
| `growth` | `growth/current/`, `growth/archive/`, `reviews/<slug-set>/<year>/<start>_<end>/`, `resume/resume.md` | [`../docs/hub/growth.md`](../docs/hub/growth.md) |
| `communication` | `manager/current/`, `manager/archive/` | [`../docs/hub/manager.md`](../docs/hub/manager.md) |
| `organize` | `reminders/current/` | [`../docs/modules/organize.md`](../docs/modules/organize.md) |
| `studio` | `design/` | [`../docs/hub/design.md`](../docs/hub/design.md) |
| `solitaire` | none -- it reads the tracker, and writes nothing to the hub | [`../docs/modules/solitaire-agile.md`](../docs/modules/solitaire-agile.md), "The file shape, and how a standup is read" |

Those folder names are defaults, not constants: they are what `hub.json`'s `folders` block declares,
and every path above is resolved through `hub_folder()`.

### Growth: three routes call the CLI, through the bridge

`/review-preview`, `/resume-preview` and `POST /review/generate` do their work by running a CLI
verb -- `PublishWorkReview -Preview`, `UpdateResume -Preview`, `NewWorkReview` -- and parsing the
JSON it prints. They go through **`bridge._run`**, with the function resolved out of the CLI's own
command table and the parameters travelling as argv.

That is the point of the row rather than an implementation note: there is one thing in this repo
that knows how to start the CLI. A second `pwsh -Command` builder beside the bridge would need its
own quoting, and a comma-separated slug list would need hand-added quotes to survive it; argv has no
such reading.

`GET /api/engagement/{slug}/skills` is **not** in this package, although `SkillsSnapshot` is
growth's component and its only caller. It counts tags across one org's `archive/` -- card data --
and it already lives in `ado/reporting.py`. Moving it would have bought a tidier folder and a worse
boundary. `agent/growth/reviews.py` imports the slug-set readers from that file rather than keeping
a second copy.

### Communication: the engine, and the one write that bends the rule

`comms.py` is the communication engine: tone formatting, the Adaptive Card envelope, recipient
resolution, the master switch, validation, dry run, and fail-soft failure, each pinned by
`Tests/test_comms_format.py`. The master switch reads the merged **engineer-scoped** features map
that `load_config()` produces, not `spaces[].features`.

`PUT /manager/{filename}` is the one session write in this API that does not go out through the
CLI. The reason is stated rather than assumed: it saves a form someone is typing into, and
round-tripping keystrokes through a PowerShell process start would make the editor unusable.
It writes the file the way the CLI's `Write-CardText` does (`core/cards.py`, `write_card_text`): UTF-8
with no BOM, and the line ending the session file already has -- LF stays LF and CRLF stays CRLF, on
every OS -- so a save in the browser changes the lines that were edited and not the whole file in a
git-synced hub. `Tests/test_manager.py` holds both endings.

`POST /manager` creates a session by running `NewMeeting` through the bridge -- `-Date`, and `-Type`
for a series -- with `PROMPTS_ROOT` set to the hub this process resolved, and reads the file the
verb wrote to answer in `ManagerDetailResponse`'s shape. It takes `{date, series}` and nothing else:
notes are an edit. An existing session, in `current/` or `archive/`, is a 409 naming the folder
before the verb runs; the verb missing from the command table is a 503 naming it.
`_build_session_file` is the one thing in Python that writes a session, and it never creates one;
`Tests/test_manager.py` runs the real verb in a scratch package and asserts the file is the
template's, byte for byte.

**What a save will not do.** `PUT` reads back everything the notes form does not own -- the agenda,
the prep, the carry-forward heading and body, the stage, the `Sent` lines -- and writes them again
unchanged. A save from the notes form cannot delete an agenda, cannot move the stage, and cannot
lose a `Sent` line. `Tests/test_manager.py` asserts each of those three.

`append_sent` is the one addition to the request shape: one line to add under `## Sent`. It is
appended **server-side**, so the caller never has to read the file back in order to add to it. It is
what the web UI's retro send uses to record that a send happened, which is the same premise the
whole store rests on: the file is the record.

> **`POST /comms/send` posts for real.** The engine takes whatever is in the recipient's webhook
> variable at face value. Send `"dryRun": true` on the body -- or use `tkSendTeams -WhatIf` -- to run
> every gate and format the markdown without posting.

### `/env` gains a `communication` block

Only when the flag is on, and `core/env.py` **does not import this module** to build it. It asks a
module that is switched on to describe itself, lazily and inside the flag check, so a checkout
without the module still serves `/env`.

```json
"communication": {
  "postRetroSummary": true,
  "retroChannel": "manager",
  "recipients": [
    { "key": "manager", "display": "My Manager (DM via Workflow)", "type": "channel",
      "scope": "managerWorkflow", "webhookEnv": "TEAMS_WEBHOOK_MANAGER", "configured": false }
  ]
}
```

`recipients[]` is the second gate, answered **before the click**: `configured` says whether the
named environment variable is set, and `webhookEnv` names it so the UI can tell someone what to set
rather than merely refusing; with `TEAMS_WEBHOOK_MANAGER` unset it is `false`, as above. **The URL
itself is never in config and never in this response** --
config names the variable, the environment holds the value.

`scope` says which config block each entry came from. It exists because the `manager` recipient is
top-level (`managerWorkflow`) while every other recipient is the active Space's -- which is *why*
switching org changes one list and not the other. That is gap C7 ([Known gaps](../docs/KNOWN-GAPS.md))
answered by rendering rather than by moving one of them; a UI that flattened the two could
not explain the difference.

## The route table

47 core routes, all mounted under `/api` -- the Studio's six among them since it became core,
the Prompts card's two the newest. The modules add 19 more -- 8 from growth, 6 from
communication, 1 from organize and 4 from solitaire
-- listed below and documented in
[`../docs/modules/growth.md`](../docs/modules/growth.md),
[`../docs/modules/communication.md`](../docs/modules/communication.md),
[`../docs/modules/organize.md`](../docs/modules/organize.md) and
[`../docs/modules/solitaire-agile.md`](../docs/modules/solitaire-agile.md); the Studio's are in
[`../docs/modules/studio.md`](../docs/modules/studio.md). 66 in total, counted off the app's own
route list.

| Route | Module | Gate | Reads | Writes |
| --- | --- | --- | --- | --- |
| `GET /health` | `core/env` | any | hub root, `current/` | — |
| `GET /surfaces` | `core/surfaces` | any | the CLI's `Get-P20SurfaceInventory` in a child PowerShell (the state of a surface is the CLI's, D-W2); `Config/settings-workflows.json` through it | — |
| `GET /env` | `core/env` | any | config, hub, `az` (the tier probe **and** the identity fallback), `PATH` (the bridge host); each offered Space in `config.spaces` carries the `tracker` its address names | — |
| `POST /switch-mode` | `core/env` | any | config | **`config.local.json`** (`activeSpace`) |
| `GET /config/schema` | `core/config_routes` | any | `Config -Schema -AsJson`, through the bridge; cached per process | — |
| `GET /config` | `core/config_routes` | any | `Config -List -AsJson`, through the bridge | — |
| `PUT /config` | `core/config_routes` | any | the reply of the write, then the re-read | **whatever `Config` writes** -- `config.local.json`, or the hub's `hub.json` |
| `POST /log` | `core/log` | any | — | `usage.{machine}.log` (or `P20_USAGE_LOG_DIR`); a tab or line break in `source` or `detail` is written as one space, so an entry is always one line of five columns |
| `GET /log-entries` | `core/log` | any | `usage.*.log`, from the same directory the writer uses | — |
| `GET /test-history` | `core/log` | any | `test-results.{machine}.log`, `test-summary.*.json` | — |
| `GET /status` | `ado/status` | Tier 2+ | `{hub}/{org}/current/`, then `{hub}/{org}/backlog/` (a card from there is `status: Backlog`, the folder read first; it sorts after the cards in play); on a GitHub Space at Tier 1 each card also carries `pinned` (one `gh api graphql` `pinnedIssues` call per repo, held 60 s, dropped when `/cmd/EditItem` runs) -- at Tier 2, on ADO and with no tracker `gh` is not asked. `?space=<slug>` reads THAT Space's `{hub}/{promptsFolder}/current/` instead (the Studio's Spaces card): a folder read, no tracker asked and no `pinned` set for a Space you are not in; an undeclared slug is **404**, the same lookup as `/issue-report`'s (`space_entry()`) | — |
| `GET /status/{filename}` | `ado/status` | Tier 2+ | one card, from `current/` or else `backlog/`. Its `design` -- the card's `> Design:` line, else a hand-written `> Spec:` line, parsed by `core/parsers.py` `card_design` -- has its id resolved: the hub's designs from disk (`studio/notes.list_hub_designs`), and the active Space's repo through `/design`'s own gate and cached listing when the line's link is a GitHub URL; `state`, `where` (`hub`/`repo`) and `path` say what was found, empty when nothing was. `/status` carries the same field unresolved | — |
| `GET /assets/{space}/{key}/{file}` | `core/assets` | Tier 2+ | one picture from `{hub}/{space's promptsFolder}/assets/` -- resolved, then confined to that folder exactly one level deep; images only (png, jpg, jpeg, webp, gif), content type from the extension; 404 otherwise. Core, no flag; writes nothing | — |
| `POST /assets/upload` | `core/assets` | any | the raw request body (the file itself, no multipart); `?name=` gives its extension. No bytes or a type `Cover` does not accept is **400**, a body over the size limit **413** | **one temp file** in a fresh `p20-upload-` folder under the system temp directory, never the hub; its path comes back, and `Cover` / `NewPrompt -Cover` through the bridge place the picture. The bridge removes that folder when the verb returns, whatever the outcome, and only a folder of that name directly in the system temp; the agent also removes any older than a day when it starts |
| `GET /pr-comments` | `ado/pr_comments` | Tier 2+ (a file read: no probe, no `az`) | cards with a PR-comments section | — |
| `GET /pr-comments/{filename}` | `ado/pr_comments` | Tier 2+ | one card | — |
| `POST /pr-comments/{filename}/suggest` | `ado/pr_comments` | a key and the SDK (`core/model`), else **412** saying which is missing | `agentic/pr-suggest.prompt.md`, `ai.model` from config | — |
| `GET /prs` | `ado/accounting` | Tier 1 | ADO via `az` | — |
| `GET /work-items` | `ado/accounting` | Tier 1 | by the space's tracker: ADO via `az` (WIQL), or `gh issue list` per repo -- `?all=1` is the Issues tab's unassigned many; `?state=open\|closed\|all` is the other axis, `open` by default, anything else read as `open`. A gh row carries `state`, `closed` (the day), `worker` (the label whose description starts `Routed to`) and `pinned` (GitHub's own `isPinned` -- the web sorts pinned rows first; `/issue/{number}` carries it too); open rows sort first, then closed ones newest-closed first. ADO ignores `state` | — |
| `GET /issue-report` | `ado/accounting` | Tier 1, GitHub spaces only -- `supported: false` elsewhere. `?space=<slug>` asks about THAT Space instead of the active one (an undeclared slug is **404**; the Studio's foyer reads the same report for every GitHub Space at once through `/studio/ledger`) | `gh issue list --state all`: open/closed, sev1..3, kinds, milestones | — |
| `GET /milestones` | `ado/accounting` | Tier 1, GitHub spaces only -- `supported: false` elsewhere, and gh is not asked | `gh api repos/{owner}/{repo}/milestones?state=all` per repo: each milestone's `title`, `number`, `repo`, `url`, GitHub's `state`, its `open` and `closed` counts, `due` and `closed_at` (days, "" when unset), and `reached` -- DERIVED, every issue closed and at least one issue, whatever GitHub's state says | — |
| `GET /issue/{number}` | `ado/accounting` | Tier 1, GitHub spaces only -- `supported: false` elsewhere | `gh issue view --json` (body, thread, meta) plus the timeline API's high signal -- commits, the linked PR, cross-refs. `?repo=<short>` picks the repo on a many-repo space; `?space=<slug>` reads it through that Space instead of the active one -- a hub design note's thread, from the Studio (S2b); an undeclared slug is **404** | — |
| `GET /design` | `ado/design` | Tier 1, GitHub spaces only -- `supported: false` elsewhere; an owner-grained address is **400** with the sentence naming it | the four folders through `ado/repo_read.py` `read_folder_rows` (Studio S2, D-S11): ONE `gh api graphql` call for their shape -- names and blob shas, `repository.object(expression: "HEAD:<folder>")`, the query in a file (`-F query=@<file>`) and every value a field, never in a URL -- and one more, aliased `object(oid:)` lookups a hundred at a time, for the texts of only the blobs never parsed before; when nothing has been parsed yet the shape call carries every text, so a cold listing is one call. A blob whose text comes back null (binary, or past what GitHub inlines) is read by the contents call alone. Each markdown file's title (first `#`), frontmatter `description`, and the thread its `> GitHub:` line names; design/ before spec/, a missing folder is an empty list. The listing is cached 60 s per process; under it the PARSED ROW FIELDS (`design.design_fields`, no body) are kept on disk by blob sha in the agent's cache (`core/disk_cache.py`), so a restart refetches nothing unchanged -- measured on a repository of 190 notes, 91 s and 194 calls before, 2.0 s and one call cold, 0.6 s and one call warm. Each design row carries `cards`: the active Space's cards in `current/` and `archive/` (as Done) whose `> Design:` line names its id -- `{ file, id, title, status, space, archived }`, read from disk on every request over a copy of the cached listing (`design.attach_cards`) | — |
| `GET /design/search` | `ado/design` | as `/design`; `supported: false` where `/design` is | `?q=` -- GitHub's code search (`gh api search/code`) scoped to the repository, asked on request and never on the tab's first draw; every word must appear, in any order, case ignored; a hit names the design, its state and the first matching line, and `note` says what code search cannot see (the default branch only, lagging a push by minutes); `available: false` with a reason when the search could not answer | — |
| `GET /design/{path}` | `ado/design` | as `/design`; `{path}` is a path (`{path:path}`), one `.md` file in `design/`, `design/archive/`, `spec/` or `spec/archive/` -- anything else is **404** before gh is asked | one file's text and the same fields. While the listing is inside its TTL its blob sha finds a body already on disk, and an unchanged note opens with no `gh` call; otherwise one `gh api repos/{owner}/{repo}/contents/{path}`, its body kept on disk by its sha for the next open | — |
| `GET /docs` | `ado/docs` | **the same gate as `/design`** (`design.repo_gate`): Tier 1, GitHub spaces only -- `supported: false` on an ADO Space, a Space with no tracker or Tier 2, and `gh` never asked; an owner-grained address is **400** | `gh api repos/{owner}/{repo}/contents/README.md`, then `.../contents/docs` walked four folders deep (D-S12): `readme` and `items` -- every `.md` under `docs/`, sorted by path, names and paths only (no file text, so one gh call per folder); listing cached 60 s per process | — |
| `GET /docs/{path}` | `ado/docs` | as `/docs`; **the path rule first** (`docs.doc_path`, the contract's `consts.json` `docs` and the table `Tests/fixtures/docs/paths.json` the web reads too): `README.md` or a `.md` under `docs/`, and never a `..`, an empty or dot segment, a backslash or a leading slash -- anything else is **404** with the rule, before gh is asked | one document's text, its title (first `#`) and its github.com URL, read through the same `repo_read.file_text` `/design/{path}` reads through (its body kept on disk by blob sha); `issues`, the repository's issues on github.com from `gh api repos/<repo>` (cached per repository for the listing's TTL), or `""` when it has issues turned off or gh did not answer -- the room links a `#N` only when it is set | — |
| `GET /docs/asset/{path}` | `ado/docs` | as `/docs`, with the path rule for an image (png, jpg, gif, webp, svg) anywhere in the repository, never with a `..`; not supported is **404** | the image's bytes, decoded from the contents route -- or, past the 1 MB it inlines, from `git/blobs/<sha>` -- with its content type, `nosniff` and a CSP that runs no script; an image over `ASSET_MAX_BYTES` (10 MB) is **413** with a sentence, and the blob is never asked | — |
| `GET /deploys` | `ado/accounting` | Tier 1, GitHub spaces only -- `supported: false` elsewhere. `?space=<slug>` as `/issue-report` | `gh run list` per repo: the newest workflow runs, the pane's "last deploy" | — |
| `GET /visibility` | `ado/accounting` | GitHub spaces only -- `supported: false` and `visibility: ""` elsewhere; below Tier 1 `unknown` with `gh` not asked. `?space=<slug>` as `/issue-report` | `gh api repos/{owner}/{repo}` -> `visibility`, once per repo, held 600 s (an unanswered call is not held); `?refresh=1` drops that Space's repos' answers and goes past the tier probe's cache, then asks again -- the Spaces card's Refresh: `public`, `private` (gh's `INTERNAL` too) or `unknown`, never guessed (`consts.json` `visibility`). A Space of several repos is `public` when any is | — |
| `GET /dashboard` | `ado/accounting` | Tier 1 | ADO via `az`, plus local repo health | — |
| `GET /dashboard/pipelines/{project}` | `ado/accounting` | Tier 1 | ADO via `az` | — |
| `GET /billing` | `ado/reporting` | Tier 2+ | `Get-WeeklyBilling.ps1` over the cards' own dates, enriched by `git log` where the hub has one | — |
| `GET /engagement/{slug}/summary` | `ado/reporting` | Tier 2+ | `archive/`, config | — |
| `GET /engagement/{slug}/work-breakdown` | `ado/reporting` | Tier 2+ | `archive/` | — |
| `GET /engagement/{slug}/skills` | `ado/reporting` | Tier 2+ | `archive/`, reviews | — |
| `GET /engagement/{slug}/reviews` | `ado/reporting` | Tier 2+ | review folders in the hub | — |
| `GET /stress-status` | `ado/sprint` | `features.sprintAwareness` | `stress-log*.json` | — |
| `GET /stress-sprint-activity` | `ado/sprint` | `features.sprintAwareness` | `stress-log*.json`, `git log` | — |
| `GET /stress-repos` | `ado/sprint` | `features.sprintAwareness` | config aliases, local checkouts | — |
| `POST /cmd/{name}` | `ado/bridge` | the name must be a key in the CLI's `$script:ModuleState.CommandMap` | — | whatever the CLI verb writes |

**The ledger as a tool.** A session working a GitHub Space -- an agent reading the backlog before filing, or checking whether a
thing was already seen -- uses **the product's doors**, not a `gh` of its own. AGENTS.md's
"Read the issues before diagnosing" is done through them:

| To... | Ask | Answers |
| --- | --- | --- |
| read the whole ledger, closed included | `GET /api/work-items?all=1&state=all` (`state=closed` for the history only) | every issue with `state`, `closed`, `labels`, `worker`, `assignee`, `pinned`; open first |
| see where the work is going | `GET /api/milestones` | every milestone with its counts and `reached`; a reached one still `open` is the milestone nobody closed |
| read one issue and its thread | `GET /api/issue/{n}` (`?repo=<short>` on a many-repo Space) | body, comments, timeline (commits, the PR, cross-refs), `state` |
| file a new one | `POST /api/cmd/NewItem` with `{"params": ["<title>", "-Type", "Bug", ...]}` | the CLI verb, through the bridge -- the one writer, with its refusals |
| pin or unpin one | `POST /api/cmd/EditItem` with `{"params": ["<n>", "-Pin"]}` (or `-Unpin`; add `-WhatIf` to see it first) | GitHub's own pin; a fourth is refused as the verb's sentence |

Each is tier- and tracker-gated like the rest, speaks the same `reason` when gh does not answer, and
logs to the same usage log -- a session's reads show up where a person's do.

And the modules', gated per request on their flag and 404 when it is off:

| Route | Package | Reads | Writes |
| --- | --- | --- | --- |
| `GET /growth` | `growth/growth` | `{hub}/growth/current/` | — |
| `GET /growth/{filename}` | `growth/growth` | one artifact | — |
| `GET /resume` | `growth/resume` | `{hub}/resume/resume.md` | — |
| `GET /resume-preview` | `growth/resume` | `UpdateResume -Preview`, through the bridge | — |
| `GET /reviews` | `growth/reviews` | `{hub}/reviews/`, scoped to the active Space | — |
| `GET /reviews/{folder}` | `growth/reviews` | one `review.md` | — |
| `GET /review-preview` | `growth/reviews` | `PublishWorkReview -Preview`, through the bridge | — |
| `POST /review/generate` | `growth/reviews` | `NewWorkReview`, through the bridge | **the scaffold the verb writes** |
| `GET /manager` | `communication/manager` | `{hub}/manager/{current,archive}/` | — |
| `GET /manager/{filename}` | `communication/manager` | one session | — |
| `POST /manager` | `communication/manager` | `NewMeeting`, through the bridge | **the session the verb writes in `{hub}/manager/current/`** |
| `PUT /manager/{filename}` | `communication/manager` | one session | **that session** |
| `POST /comms/send` | `communication/manager` | `/env`'s recipient registry, the webhook variable | **an outbound webhook** |
| `POST /rewrite` | `communication/manager` | a model | — |
| `GET /reminders` | `organize/reminders` | `{hub}/reminders/current/` -- gated on `features.organize`, 404 when off; the bucket derived against the local clock | — (every reminder write is `NewReminder` / `Reminders` through the bridge) |

| Route | Package | Gate | Reads | Writes |
| --- | --- | --- | --- | --- |
| `GET /studio/design` | `studio/notes` | none -- core (D-S13); a leftover `features.studio` is ignored | the hub's `design/` (`hub_folder("design")`): each note matching `consts.json` `studio.noteName` -- title, frontmatter `description` and `space`, the thread its `> GitHub:` line names, and `thread_space`, the declared GitHub Space whose repos hold that thread. No folder is an empty list with `exists: false`. Each design row carries `cards`, as `/design`'s do, read from EVERY declared Space's folders -- a hub design belongs to no product | — (a note is written by `NewDesign` through the bridge) |
| `GET /studio/design/search` | `studio/notes` | as `/studio/design` | `?q=` -- the hub's four folders on disk (`design/`, `design/archive/`, `spec/`, `spec/archive/`): every word, any order, case ignored; a hit names the design, its state and the first matching line. Declared before the `{path}` read so "search" is not taken for a document's name | — |
| `GET /studio/design/{path}` | `studio/notes` | as `/studio/design`; `{path}` is a path (`{path:path}`), one `.md` file in the hub's `design/`, `design/archive/`, `spec/` or `spec/archive/` -- anything else is **404** before the disk is read | one note's text and the same fields | — |
| `GET /studio/prompts` | `studio/prompts` | none -- core; a shipped prompt of an add-on that is off is left out | the package's `agentic/*.prompt.md` with `agentic/prompts.json`'s `workflows`, `sender`, `module`, `drives` and `category`; yours from `agenticExtensionPath` and the hub's `agentic/` (`hub_folder("agentic")`); every row's one record -- `title`, `purpose` (the frontmatter's `description`), `owner` (`toolkit`, `yours` or the Space's slug, from where the file lives) and `category` (the index's, else the frontmatter's, else `uncategorized`) -- its last change (one `git log` per folder, else the file's time) and its history URL when the clone's origin is GitHub, and its whole `body`; and the index's `categories`, in its order | — |
| `GET /studio/ledger` | `studio/ledger` | none -- core (D-S13); per Space, what `/issue-report` gates on: a GitHub tracker, a hub, git, a status that is not `local` or `archive` -- `supported: false` otherwise with `gh` not asked -- and the tracker answering (the GraphQL call itself; only a call that does not answer at all resolves the tier the old way, so a signed-out `gh` is `supported: false`). `?refresh=1` goes past the disk cache | `spaces`, every declared GitHub Space by slug, each `{report, deploys, visibility}` in `/issue-report`'s, `/deploys`' and `/visibility`'s own shapes: ONE `gh api graphql` call per twenty repositories (aliased `repository(owner:, name:)` -- `visibility`, open and closed `totalCount`, the open issues' labels and milestones newest-created first, the recently closed issues' `closedAt`; a backlog past a hundred reads its next pages; query in a file, values as `-f` fields) and `gh run list` per repository in parallel (`_github_deploys`). Each Space's answer is kept in [the agent's cache](../docs/CONFIGURATION.md#the-agents-cache) as `ledger-1/<slug>.json` for `VISIBILITY_TTL_SECONDS` (600), keyed by its repositories and status; one that did not fully answer is not kept. The visibility answers seed `/visibility`'s cache | the agent's cache only |
| `GET /studio/prompts/{ref}` | `studio/prompts` | as `/studio/prompts`; `{ref}` is a path (`{ref:path}`), since a ref such as `yours/bench-billing` has a slash; a name outside the two places is **404**, and so is a shipped prompt of an add-on that is off, naming it | one prompt, the same fields | — |
| `GET /spaces/candidates` | `studio/spaces` | none -- core; not tier-gated, because these are the `gh` account's repositories, not the active Space's tracker (a local Demo Space is exactly when they are wanted) | `NewSpace -Discover -AsJson` through the bridge (`run_command`), `?owner=` as its `-Owner` (an organisation's, or `collaborator`), `?repo=owner/name` as its `-Repo` (the one repository typed into the dialog's search, read before it is added, with a `note` when the `gh` login cannot see it), with the `owners` the dialog's selector offers, the `ceiling` a list is read to and `more` when it stopped there: each repository with owner, visibility, `isArchived` (GitHub has archived it), `viewerPermission` and `readOnly` (you can read it and not write to it), the slug and name `NewSpace` would give it, and `space` when it already is one. Never refused: no `gh`, `gh` signed out, or a bridge that cannot run answers `available: false` and the sentence why | — (a Space is added by `NewSpace` through the bridge) |
| `GET /ritual/standup` | `solitaire/standup` | `features.solitaireAgile` as resolved, per request -- the switch on AND the active Space answered `agents` (`how_i_work`); **404** when off, its detail naming which. `?space=<slug>` scoped like `/issue-report` (an unknown slug is 404); `?since=<yyyy-MM-dd>` widens yesterday's window back to that day, as `Standup -Since` does -- a `since` that is not a day, or is after today, is **422** naming it | the Space's `gh label list` and `gh issue list --state all` -- workers are the labels whose description starts `consts.json` `rituals.workerLabelPrefix`; slots, queue and the `Config/standup-vocabulary.json` pick per the spec's "The M0 build contract". A Space with no address, or a `local` one, reads its own `current/` and `archive/` instead (`source: cards`, no `gh`). An ADO Space (`rituals.text.adoTracker`), tier below 1 or a silent `gh` is still **200**, `tracker.ok` false and the reason in `text`. `text` is the CLI's `Standup` byte for byte (`Tests/fixtures/rituals/`); `work` is the same standup at the grain of the work -- each slot's items grouped by milestone, design card or common stem, one phrase a group, each group spoken as one standup sentence (each worker's `prose`, and `queueProse`), and its `text` the CLI's `Standup -Grain work` (`standup-work.json`, `standup-prose.json`), for which the issue read also asks `gh` for `milestone` and `body`. Every slot item carries `motion` (`closed`, `started` or `inProgress`) and `commits`, its card's distinct hashes, and `counts` sums them per worker and in total -- the brief's first line (`standup-joined.json`'s `counts`, `not-billable-counts` and `window-three-days` cases). `spoken` is this route's alone: with `ANTHROPIC_API_KEY` set, each worker sentence re-said by the model (`core/model.py`, `ai.model`) and kept only where `dress_guard` finds no fact added, dropped or changed (`standup-dress.json`); null with no key -- the decline is logged, never a 412 -- and the played view then speaks `work` | — |
| `GET /ritual/triage` | `solitaire/triage` | as `/ritual/standup` | the Space's `gh label list` and `gh issue list --state open` with `milestone` -- the open issues grouped by milestone (none first, then most open), each with its worker (the size), severity and `deep-water`, each group's "N open, M routed, K unrouted"; the words, slots and severities are `Config/ceremonies.json`'s `triage`. No tracker is still **200** with a `Tracker` line. `text` is the CLI's `Triage` byte for byte (`Tests/fixtures/rituals/triage*`) | — (every answer is `Route` through the bridge) |
| `GET /ritual/standup/remind` | `solitaire/remind` | as `/ritual/standup` | the standup reminder as it stands, for the settings row: whether `features.organize` is on, and the open reminder's id, due, cadence (`HH:mm days`), time and days, from the hub's `reminders/current/` (source `standup`) | — |
| `POST /ritual/standup/attend` | `solitaire/remind` | as `/ritual/standup` | the open standup reminder; once a day, the page calls it per view | nothing itself -- `Reminders <id> -Archive` and `NewReminder` through the bridge, the reminder's one writer. With `features.organize` off it does nothing and says so (`action: off`); not an error |

`POST /review/generate` and `POST /manager` are writes that go **through the CLI**, so they are not
exceptions to the rule below. `PUT /manager/{filename}` is, and the reason is stated above.

`PUT /config` is a write that goes **through the CLI**, so it is not an exception either: the body
is `{"set": {...}, "unset": [...]}`, `core/config_routes.build_params` turns it into one `-Set`
token carrying a JSON object and one `-Unset` token carrying a JSON array -- the bridge splats a
flat argv list, so a repeated `-Set` cannot survive it -- and `Config` does the validating and the
writing. Nothing in Python decides what a legal setting is; the schema is
`Scripts/Get-ConfigSchema.ps1` and `GET /config/schema` only serves it. After a successful write the
route clears the identity and reachability caches, which is why `/env` reflects a new `email`
within a second rather than after the 45-second TTL. `POST /switch-mode` writes `activeSpace` in
Python, beside the CLI's `SwitchSpace`, and is the one config write that does not go through the
bridge.

Every write in the core table is either config or the card's own side record. **No core route
mutates a prompt file or ADO** in Python; that is the bridge's job, and the bridge does it by
running the CLI. The modules add exactly one Python write, inside the hub and neither a prompt
file nor an ADO card: `PUT /manager/{filename}`, the deliberate exception argued above. A new
growth item is `NewGrowth` through the bridge (`POST /cmd/NewGrowth`), so the browser and the
terminal write it with one writer and there is no second shape to drift.

**Feature flags have a scope, and the default scope is the engineer**
([the modules guide](../docs/modules/README.md) owns the rule): every top-level `features` key is
the person's and an org cannot override it; only the org-scoped keys -- `sprintAwareness` -- are
read from the active Space. In this half the list is `ORG_FEATURES` in `core/config.py`:
`load_config()["features"]` is the merged view, `/env` serves it, and
`_active_org_feature` in `ado/sprint.py` reads it rather than the org directly.
`Tests/test_features.py` pins the rule.

The sprint gate is the honest kind. With `features.sprintAwareness` off, `/stress-status` returns
`{"enabled": false, "detail": "sprint awareness is off for this org"}` **without reading the log
file** -- not a 404, not an empty success that looks like "no data this sprint".

`/billing` degrades with a message rather than a parse error. If the script is missing, or produces
nothing because there is no hub to read, the response is a `BillingResponse` whose `raw` says so:
`No billing data: promptsRoot is not configured or does not exist`. An empty string is not fed to a
JSON parser so that a configuration problem can be reported as a crash.

### The model call, and the provider profile

Two routes ask a model for text: `POST /pr-comments/{filename}/suggest` (a draft reply to one
review thread, called by the PR Comments page's **Suggest a reply**) and the communication module's
`POST /rewrite` (tidy a notes box). Both go through one module, `core/model.py` -- the provider
profile:

- **the model** is `ai.model` in config, shipped in `config.default.json` and overridden per machine;
  `Scripts/Invoke-PRReview.ps1` reads the same key for `AddPRReview`'s default, so one setting names
  the model for every half, and `/env` reports it as `aiModel`;
- **the key** is `ANTHROPIC_API_KEY` in the environment, or `CLAUDE_API_KEY` as the fallback name
  `.env.example` documents -- `anthropic_configured()` is the same answer `/env` serves;
- **the transport** is the official SDK, imported lazily inside the call so an agent on a machine
  that never installed it still starts and serves every other route.

A route that cannot call the model says so before it builds anything: **412**, with the profile's
sentence -- which variable to set, or `pip install -r agent/requirements.txt` -- never a generic 502
from a failed call. A 502 is reserved for the model really failing after that. The prompt `suggest`
sends is `agentic/pr-suggest.prompt.md`, prose above the fence and the instruction below it, read
the way `Invoke-PRReview.ps1` reads `pr-review.prompt.md`; the thread's fields are substituted by
name. `Tests/test_model.py` holds the profile, with the SDK stood in for.

**No route in the ADO core edits a card.** `POST /pr-comments/{filename}/save` used to write a
decision and a reply into the card natively; it was retired as the second writer it was --
the page posts a reply as `ReplyPR` through `POST /cmd/ReplyPR`, which posts to the tracker and
fills the card's `Reply:` slot through `Write-CardText`. `core/cards.write_card_text`, the Python
side of that byte rule ([`docs/CLI.md`, "The bytes a card is written with"](../docs/CLI.md#the-bytes-a-card-is-written-with)),
has one caller today: `PUT /manager/{filename}` saves a meeting session, a hub file rather than a card,
through it. It stays the writer for any further native edit, held by `Tests/test_card_writer.py`. There is deliberately no
create in that module: a card is created by the CLI, through `POST /cmd/NewPrompt`.

### Deliberately absent

One route belongs to the deck module, and six are retired outright. `app.py`'s module docstring
names each with its owner, so the 404 is a statement about ownership rather than a regression.
Every row is asserted 404 (405 for `POST /growth`, whose path keeps its `GET`), and absent from the
OpenAPI schema, by `Tests/test_app_serving.py`.

| Absent | Owner |
| --- | --- |
| `POST /narrate` | the deck module, [`docs/modules/deck.md`](../docs/modules/deck.md) |
| `POST /pr-comments/{filename}/save` | **Retired 2026-10-01.** A second writer of the card's `Decision:` and `Reply:` slots beside `ReplyPR`, which the page runs through the bridge. `Tests/test_pr_comments.py` asserts the 404 |
| `POST /create-ado-item`, `POST /resolve-bug` | **Retired.** Both built their own command string instead of calling the CLI. They are `POST /cmd/NewItem` and `POST /cmd/CloseItem` |
| `POST /growth` | **Retired.** A second writer of a growth item beside `NewGrowth`, retyping the verb's three file shapes in Python. The Growth page runs `POST /cmd/NewGrowth` instead; `GET /growth` stays, so the path answers **405** for a POST |
| `GET /engagement/{slug}/activity`, `GET /engagement/{slug}/billing-timeline` | **Retired 2026-09-22.** Nothing in `web/src` requests either, and nothing draws them (`ActivityHeatmap`, `BillingTimeline` are not in this product). The `**Closed:**` stamps the timeline read are still read, by `/engagement/{slug}/summary` |

A module route with its flag **off** is also a 404, which is the same answer for a different
reason -- and the reason matters, because one is "nobody has built this" and the other is "you have
not asked for it".

## What `/env` and `/status` serve

The fields a reader of these two routes needs beyond the overview in
[`docs/ARCHITECTURE.md`, "`/env`"](../docs/ARCHITECTURE.md#env); what a card's fields mean is
[`docs/hub/cards.md`](../docs/hub/cards.md).

**`GET /env`'s check rows tell "never asked" from "tried and failed".** An `archive` org and a `local` one
are never probed, so `adoReachable` -- the **ADO Add-on** row -- cannot FAIL there: it reads `not contacted
-- archived`, or `not configured (expected)` for a local org, `ok: true`. Only an `active` org can be
`unreachable (<org>)`; one that answers is `connected (<org>)`. `tkEnv` prints the same words. And
`activePrompts` is `ok` at zero for an archived org, which is supposed to have nothing in flight
(`Tests/test_env_org_state.py`).

**`GET /env` serves `config.laneNames`** -- `{contract word: display name}` for the active Space's four lanes,
from `spaces[].laneNames` (`lane_names()` in `core/config.py`; the contract's words where the org says
nothing, unknown keys ignored). Display only: `status` is always the contract's word. Each entry of
`config.spaces` carries the same map for ITS lanes, as `laneNames`, so a reader counting another
Space's cards names them as that Space does.

**Every detail route serves `path`** -- `GET /status/{file}`, `GET /growth/{file}`, `GET /manager/{file}`:
the file's absolute path on the machine the agent runs on, exactly what it resolved to read the file. The
web shows it with a copy button on every file page, so a person can hand the record to an assistant
(`Tests/test_card_model.py`, `test_growth.py`, `test_manager.py` each pin it).

**`GET /env` serves `ado`** -- `{ enabled, explicit }`: whether Azure DevOps is part of what is SHOWN.
`ado_enabled()` in `core/config.py` is the mirror of the CLI's `Scripts/Test-AdoEnabled.ps1` -- `features.ado`
when someone has set it, else whether the active Space's status is `active` AND its tracker (`tracker()`,
from the address) is `ado`, so a connected GitHub Space serves `enabled: false` beside `tracker: "github"`
-- and one shared table, `Tests/fixtures/ado-enabled/table.json`, holds the two together
(`Tests/test_ado_enabled.py`, `Tests/Test-Setup.ps1`). It gates no route: an ADO route on an org with no
ADO already answers with its tier sentence.

**`GET /env` serves `cardTypes`** -- the configured card type names, in config's order, with a team's own
included -- which is what the web's "New card" dialog offers.

**`GET /status` serves the Card model** ([`../docs/hub/cards.md`](../docs/hub/cards.md), "The model, as the agent serves it"), not a list of titles. Each
prompt carries `id` (from the FILENAME, by the one id rule -- `card_id()` in `core/parsers.py`, held to
`Scripts/Resolve-CardName.ps1` by the shared table `Tests/fixtures/parsers/card-ids.json`), `type` and
`name` (from the H1, matched against the CONFIGURED type names, longest first, so "User Story" is not
read as a type called "User" and a team's own type is known), and `linked` -- whether there is an ADO
link, which is the whole difference between an "ADO card" and any other -- and `tracker`, the
tracker rule (`core/config.py`'s `tracker()`, the Space's own rule) run over the CARD'S link: `github`,
`ado`, or `none` exactly when not linked, so a card in a mixed Space names its own ledger. `title` is the whole
heading, for what reads it. The agent reads `workItemTypes` for this the way the CLI does:
defaults, then the machine's patch, per request. `GET /status/{filename}` serves the same fields.
Both also carry `cover` and `before`: the URL of `GET /assets/...` for the picture a card's
`**Cover:**` / `**Before:**` line names, or `null` -- no line, a missing file, or a path outside the Space's
`assets/`. `core/assets.py`'s `card_image()` is held to the CLI's `Resolve-P20CardImage` by the shared table
`Tests/fixtures/parsers/covers.json` (`Tests/test_assets.py`).
`Tests/test_card_model.py` runs it end to end, including a type added in `config.local.json`.

**`GET /status` sorts by state, then by file name**, from `status_sort_key` in `core/parsers.py`.
The CLI sorts on the same pair with an ordinal comparison, so a hub is numbered the same in the
terminal and in the browser. Both are explicit because `Sort-Object` is unstable on Windows
PowerShell 5.1: left implicit, a list of cards all in one state comes out rotated there and not in
the agent. A shared expectation rather than a shared call -- the same arrangement as the
parsers, and `Tests/Test-Status.ps1` runs the CLI against the same eight names this suite orders.

## The bridge

Reads stay native Python, because a page render must not fork a PowerShell process per card. Writes
go into the Toolkit's own PowerShell through `POST /cmd/{name}`, so there is exactly one
implementation of each verb. Why, and a worked `Archive` request, are
[`docs/ARCHITECTURE.md`, "The bridge"](../docs/ARCHITECTURE.md#the-bridge); this section is the
contract.

### Which PowerShell

`agent/core/hosts.py`, and nothing else, decides. Two names in order:

| Order | Name | Where it is probed |
| --- | --- | --- |
| 1 | `pwsh` | Every platform. PowerShell 7+, the daily shell, and the only one macOS and Linux have |
| 2 | `powershell` | **Windows only.** Windows PowerShell 5.1, the built-in -- the floor [Quick start](../docs/QUICKSTART.md#requirements)'s Requirements table promises. Elsewhere the name is either absent or something that is not PowerShell, so it is not even looked for |

Resolved once per process (`PATH` does not change under a running agent) and used by both call
sites here, plus `/billing`'s `Get-WeeklyBilling.ps1`, so there is no second copy to drift. The argv
is the same under both hosts -- `-NoProfile -File <script> <args...>`, tokens after the script path
handed over positionally as strings -- which is why `bridge.ps1` needs no host-specific branch and
must contain no 7-only syntax. `Tests/Test-PS51Compat.ps1` scans it for that statically, since
nothing on a Mac can run 5.1.

**With neither host on `PATH`**, nothing can run, and both halves say so plainly:

- `GET /env` reports `"bridgeHost": {"resolved": null, "path": ""}` and a failing `bridgeHost`
  check row, so the web UI shows it before anyone clicks anything;
- `POST /cmd/{name}` answers `status: "error"` -- **not `rejected`** -- with `error` naming both
  names it tried. `rejected` means *this name is not a command*, and with an empty allowlist that
  would tell a 5.1-only machine that every write is "not a command in this CLI";
- `_read_command_map()` returns `{}` rather than raising, and logs the missing host **once** per
  process -- a failed read is deliberately not cached, so logging per read would be a line per
  request forever.

### Two files, and why there are two

| File | Does |
| --- | --- |
| `ado/bridge.py` | The route. Derives the allowlist, checks the parameters, runs the child, maps the outcome to a `CommandResponse` |
| `ado/bridge.ps1` | The child. Imports this repo's manifest by a path relative to its own location, resolves the function, calls it with `@args` |

`bridge.ps1` exists so that nothing on the Python side has to know how to load the toolkit or how to
quote a PowerShell argument. It is not a CLI command: no alias, no entry in the command map, no
`{prefix}` form, same reasoning as `Get-WeeklyBilling.ps1` below.

### The allowlist is derived

`bridge.py` names no command anywhere -- there is a test that greps its source to keep it that way.
It runs `Get-P20CommandMap`, a function in `utilities.psm1` that emits `$script:ModuleState.CommandMap` as one
line of JSON:

```json
{"Menu":"Get-P20Menu","Archive":"Move-P20PromptToArchive","NewPR":"New-P20PullRequest", ...}
```

The result is cached against the modification times of everything the table is built from --
`utilities.psm1`, `config.default.json`, `config.local.json` and every `Config/*.commands.psd1` --
so the cost is one PowerShell start per change to one of those rather than one per request, and a
verb added the four-step way is bridgeable on the **next request** -- no backend edit, no restart.
The config files are in the key because a module's verbs are in the table only while its
`features.*` flag is on (D-CM). A flag flipped from the Configuration card goes through the bridge
itself, which would prime the cache with the pre-flip table, so `PUT /api/config` also forces a
re-read after a successful write; a `tkConfig -Set` from a terminal is seen through the key, which is each file's mtime, size and a digest of its bytes (a rewrite in the same clock tick still changes it).
A failed read is deliberately not
cached: a moment when PowerShell was unavailable must not leave the bridge refusing everything until
someone restarts it.

The keys are what a caller sends (`Archive`); the values are what gets invoked
(`Move-P20PromptToArchive`). **The function, never a prefixed alias** -- the prefix is data, more
than one can be registered at once, and `tkArchive` is therefore not a stable name for a machine to
call.

There is no hand-maintained list of names beside the table, and one cannot quietly appear:
`test_bridge.py` asserts both that no constant with `ALLOWED` in its name exists and that no command
name appears in the module's source.

### Parameters are argv, not a string

```text
<host> -NoProfile -File agent/ado/bridge.ps1 <Function> <param> <param> ...
```

Nothing builds or parses a command string on either side. `bridge.ps1` has no `param()` block and
reads `$args` positionally, which is the only shape that survives a parameter beginning with `-`:
PowerShell's binder claims such a token as a parameter *name* before a declared `[string[]]` could
receive it, and `-Comment` and `-Reason` are most of what the verbs take.

So a parameter may contain spaces, quotes or punctuation: with no concatenation there is nothing to
guard against. The limits are about size and sanity, not injection:

| Limit | Value |
| --- | --- |
| Parameters per call | 32 |
| Characters per parameter | 4096 |
| Control characters | Refused, except tab, newline and carriage return, which are ordinary inside a PR reply body |

### The four statuses

The reply is always HTTP 200 and always a `CommandResponse`: a refusal is an answer, not a transport
failure, and a client that types the body renders every outcome the same way.

| `status` | `exit_code` | Means |
| --- | --- | --- |
| `success` | `0` | The verb ran and exited 0; its console output is in `output` |
| `error` | the verb's | The verb ran and exited non-zero; `error` is its stderr. Also `-1` and `duration` 0 when there is no PowerShell host at all -- see [Which PowerShell](#which-powershell) |
| `rejected` | `-1` | **Nothing ran.** The name is not in the command table, or a parameter broke a limit. `duration` is 0 |
| `timeout` | `-1` | The verb outlived its timeout and was killed |

Each call is logged through `core/log_writer` as `Agent/<name>` -- the bare command name, never a
prefixed one, for the same reason the invocation uses the function.

### Timeouts live on the command

```json
"Status": { "bridgeTimeoutSeconds": 30, "category": "prompt", "description": "..." }
```

On the verb's own entry in `config.default.json`, beside its help text, rather than in a second
table here. Absent, the bridge allows 120 seconds -- the floor is a PowerShell start plus a module
import, and an ADO round trip is slower than that again. Three verbs say otherwise today:
`TestToolkit` and `AddPRReview` get 300, `Status` gets 30 because the UI polls it and a read must
not hold a connection for two minutes while `az` hangs.

### One thing to know about `success`

`bridge.ps1` exits 0 on a clean return and 1 on a terminating error. It deliberately does **not**
exit with `$LASTEXITCODE`, which holds the exit code of the last *native* command anywhere inside
the verb -- with that, a perfectly successful `tkEnv` would report as a failure whenever its `az`
probe missed.

A stated refusal still arrives as a failure. `bridge.ps1` sets `TOOLKIT_QUIET_STARTUP`, and under
it the CLI's one guard, `Invoke-ToolkitScript`, re-raises an `exit 2` refusal instead of returning
cleanly, so the reply is `status: "error"` with the verb's stated sentence, never `success`
(`Tests/test_bridge_refusals.py`; the contract is AGENTS.md's "The refusal contract"). A verb that
catches its own failure outside that guard and returns normally still exits 0, and the bridge
reports `success` with the text in `output` -- the same contract `Tests/Test-ExitCodes.ps1` asserts
for the terminal, so the bridge and the CLI agree about what failed.

## `Get-WeeklyBilling.ps1`

`/billing` is the other route that shells out to PowerShell -- through the same `core/hosts.py`
resolver the bridge uses -- and the script it calls lives here, in
`ado/`, rather than in `Scripts/`. That is deliberate: it is **not a CLI command**, has no alias, no
entry in the command map and no `{prefix}` form. It belongs to this module, is invoked by path, and
takes `-PromptsRoot` and `-PromptsFolder` so the agent hands it the hub and the active Space's folder
instead of the script guessing at either. Both are required: the script resolves no Space of its own,
so the folder Daily bills is the one `load_config` resolved, fallback included. A Space whose cards sit
at the hub root is passed as `.` -- Windows PowerShell 5.1 drops an empty argument.

```bash
pwsh -NoProfile -File agent/ado/Get-WeeklyBilling.ps1 -PromptsRoot <hub> -PromptsFolder <folder> -AsJson
```

**The cards decide; git enriches.** The script enumerates `current/` and
`archive/`, keeps the files that carry a card id (`Scripts/Resolve-CardName.ps1` -- the one id rule, so
a notes file is never billed), and puts each card on every working day from `**Created:**` to
`**Closed:**`, or to today while it is open. `git log` is read too when the hub is a repository, and
is used for exactly two things: which days inside that interval the card was touched, and a date for a
card that carries none. It cannot add a day outside the interval, so a hub-wide folder move bills
nobody on a day their card was not open. Both passes read an id through that one rule and key on the
string (`141`, `K7M2`), so a card with no work item, or a configured type prefix, gets its git days
too. A card that says `**Billable:** no` (`consts.json`
`stamps.billable`) is left off. The JSON says what happened, and `BillingResponse` carries it to the
web:

| Field | Means |
| --- | --- |
| `source` | `stamps` (no git, or none needed) or `stamps+git` |
| `nonBillable` | cards inside the week left off because they say so |
| `unstamped` | cards with no date and no git to lend one: counted, never guessed |
| `error` | set **only** when the week could not be built (no script, no PowerShell host, a timeout, a script that failed, no hub -- the script exits 2 for that one). `days` is empty then too, which is also what a quiet week looks like, so Daily reads this field and not the emptiness |

**There is no server-side cache.** A finished week can still change -- the first time a card closed
on Friday is marked not billable on Monday -- and a cache keyed by week would also ignore the org and
outlive a `Sync`. The cache for this route is the browser's (RTK Query, the `Billing` tag).

It dot-sources `Scripts/Get-Consts.ps1` and `Scripts/Resolve-CardName.ps1` from the package, and
**exits 1 loudly** if either is missing -- silently billing nothing is the one failure a timesheet
cannot afford. `GET /status` serves the same fact per card, as `billable` (default `true`).

The alternative -- putting it in `Scripts/` -- would have made it a command, and a command is a thing
someone can run, needs help text for, and expects to be in `tkMenu`. It is a subroutine of one
route.

## Tests

The agent's suite is Python, and it lives in the repo's shared `Tests/` folder rather than in a
folder of its own, because it tests one contract from two sides. The runner, the current counts and
every file's one-line summary are [`docs/TESTING.md`](../docs/TESTING.md); this section is what the
agent's own files guard.

```bash
python3 -m pip install -r requirements-dev.txt   # once -- pytest, httpx and ruff  (Windows: python or py -3)
python3 -m pytest Tests/          # the whole agent suite, from the repo root
python3 Tests/test_tier_parity.py # standalone; prints the combination count
```

Every file that imports `fastapi.testclient` guards it through `Tests/_skipguard.py`, so without
`httpx` those files skip and the rest of the session still runs -- an acceptable run on a machine
that only wants the CLI; a module-level `sys.exit()` there would abort collection and report **no
tests at all**.

> **Unset `TEAMS_WEBHOOK_MANAGER` and `TEAMS_WEBHOOK_DEMO_CHANNEL` before running these** on a
> machine that has ever sent a real message. `test_comms_format.py` exercises the engine's
> resolution path, and a live variable in the environment is the difference between a test and a
> message someone receives.

| File | Guards |
| --- | --- |
| `Tests/test_consts.py` | `../consts.json` parses, every key resolves to the value all three halves agreed (the table is hand-written here on purpose -- changing the contract makes a person say so out loud, in three languages), the patterns compile and match real card text, `parsers.py`'s state vocabulary comes from the file, `config.ORG_FEATURES` is the file's `features.orgScoped` list rather than a tuple typed beside it, and no runtime Python retypes a guarded literal |
| `Tests/test_parsers.py` | The prompt-file parsers against the shared fixtures in `Tests/fixtures/parsers/`: state derivation, title and sprint truncation, ADO and PR URLs, PR-comment rounds, the log's org-scoping rule, and the ledger's sort order |
| `Tests/test_tier_parity.py` | The tier decision agrees across the spec formula, Python and PowerShell, over every combination |
| `Tests/test_log_override.py` | A test run is not an event: `P20_USAGE_LOG_DIR` is the one override both halves read, a write lands in it, the real `usage.*.log` is byte-identical afterwards, and this very run is redirected (`Tests/conftest.py`, at import time -- collection logs) |
| `Tests/test_health.py` | `/health` reports `package_root`, the checkout the agent runs from, and it does not follow `PROMPTS_ROOT` -- the launcher tells its own agent from another package's by it |
| `Tests/test_env_probe.py` | `/env` does not hold the event loop and does not re-probe on every call: with `_probe_ado` stubbed to sleep, `/health` finishes **before** the probe does (an ordering, not a stopwatch -- a blocked loop makes the clock lie), a second `/env` inside the TTL makes no second probe, `?refresh=1` and an expired entry do, and the cache is keyed by org |
| `Tests/test_identity.py` | Identity resolves the way the CLI's `Resolve-P20Identity` does, with `az` **stubbed** throughout (the fallback is the thing under test, so a signed-in machine must not be able to pass a failing assertion): config wins and az is never started, az is the fallback, `branchUser` counts only when it is an address, nothing resolves to `("", "")`, a missing az is not an exception, one az start per TTL window with `refresh` and expiry going past it, all three routes filter by the resolved address, an unresolved one produces the stated `reason` and exactly one `WARN`, `/work-items` still reaches `@Me`, and `/env` reports `{email, source}` and the `identity` check without holding the event loop |
| `Tests/test_config.py` | The hub comes from config and not from layout -- including that it is *not* the parent of the package, that a relative value resolves against the repo root, that `PROMPTS_ROOT` is an override, and that a missing root neither raises nor lies. Plus the merge semantics and the CORS defaults |
| `Tests/test_accounting_reasons.py` | An empty ledger says why: with `az` stubbed inside `accounting.py` to exit non-zero, time out, be missing, or print something that is not JSON, `/prs`, `/work-items`, `/dashboard` and `/dashboard/pipelines/{project}` carry the first failure in `reason`, naming the command and the target; an org with no `projects` is its own reason and asks `az` nothing; identity still comes first; rows from one project carry no reason for another's failure; a clean empty answer has none |
| `Tests/test_child_reads.py` | Every `gh`, `az` and `git` child is read as UTF-8 through `core/child.py` `run_read`: under a stand-in for a cp1252 Windows console a title with an em dash, curly quotes and `Ï` comes back whole from `_gh_issues`, `_gh_json`, `design._gh` and `_az_json`; a reader that died (exit 0, no stdout) is a stated reason in each, never an empty list; and an AST scan finds no other `text=True` call in `agent/` without an `encoding` |
| `Tests/test_card_writer.py` | The agent's one writer for an existing hub file: an edit of a CRLF card comes out all CRLF, of an LF card all LF, a mixed card consistent, never a BOM, UTF-8 intact, and no module in `agent/ado/` writes a file with a bare `write_text` |
| `Tests/test_pr_comments.py` | `GET /pr-comments` is a file read at every tier: on an ACTIVE org with the probe stubbed to fail, the open threads in a copy of the fixture hub are listed, the probe is never called, the source names no tier gate, the detail route reads the same card, a card with nothing open is not listed, and no `current/` is an empty answer rather than an error. `suggest`: no key is a 412 naming `ANTHROPIC_API_KEY` with the model never called, the prompt is the file in `agentic/` with the thread's fields in place and the prose above the fence left out. `save` is retired: the route answers 404, the module imports no card writer, and the page posts replies as `ReplyPR` |
| `Tests/test_app_serving.py` | What the app serves around the routes: with a scratch `dist/client` mounted, `/` and a deep link are the page, `/assets` is served, a registered route still wins, and an unmatched `/api/...` path is a JSON 404 naming the path -- with the prefix read from `API_PREFIX`, not retyped; with no client directory nothing is mounted. And CORS: `PUT /api/config` passes preflight from a configured origin, every method a route is registered with is in `CORS_METHODS`, and one nothing registers still fails. And the deliberately-absent list: each retired or unbuilt route is 404 and out of the OpenAPI schema |
| `Tests/test_bridge.py` | The allowlist is the live command table and nothing else: every name in it is admitted, names outside it are refused, the map is re-read when `utilities.psm1` changes, and -- in a scratch package, so the engineer's `config.local.json` is never written -- a module flag flipped on disk puts the module's verb in the table on the next read with no `force`, the key names every input, and a new `Config/*.commands.psd1` changes it, and `Env` is run for real so a broken PowerShell half cannot pass. Plus the parameter rules, the four statuses, the timeout lookup, and the host resolver -- `pwsh` preferred, `powershell` as the Windows-only fallback, and no host answering `error` rather than `rejected` |
| `Tests/test_bridge_refusals.py` | A verb that refuses is `status: error` with its stated sentence, never `success`: `Archive` of a name that matches nothing, run end to end through the real bridge (it writes nothing on any hub) |
| `Tests/test_features.py` | The flag-scope rule: a top-level key is the engineer's and an org cannot override it; `sprintAwareness` is read from the active Space; `/env` serves the merged view |
| `Tests/test_growth.py` | The growth routes against the fixture hub and the 404 gate. There is no write to test here: a growth item is written by `NewGrowth` alone, through the bridge from the browser. Plus the heading reader: a value is the first VALUE line under a heading, so the writer's `---` and the template's `<!-- -->` hints read as nothing |
| `Tests/test_reviews_multi_org.py` | A review folder's membership is split-on-`+` **set** membership, not a substring search. `first+second` must surface for `first` and for `second` and nobody else, and `first` must not drag in `firstclass` |
| `Tests/test_manager.py` | The 1:1 routes against a **copy** of the fixture hub -- list, read, create (the real `NewMeeting`, through the bridge, in a scratch package: the file is the template's byte for byte, notes are a 422 on create and an edit through `PUT`, the verb's absence from the table is a 503 that names it, and it is run with `PROMPTS_ROOT` set to the test's hub), save -- plus both gates: off is a 404 that writes nothing, and `/env` reports the recipient unconfigured with its variable's name, then configured once it is set. Also that a save never deletes an agenda, never moves the stage and never loses a `Sent` line |
| `Tests/test_comms_format.py` | The engine: tone formatting, the Adaptive Card envelope, recipient resolution, the master switch, validation, dry run and fail-soft failure |

**Parity with PowerShell works differently in the two cases**, and the difference is worth knowing.
Tier parity is one test that runs both implementations and compares them. Parser parity is by
**shared fixture**: `test_parsers.py` exercises the Python side, `Tests/Test-Status.ps1` runs
`Get-PromptFileStatus` against the same four files, and neither calls the other. The fixtures are
what make a regex drifting on one side fail on that side.

`Tests/fixtures/hub/` is a hub, not a repository: two cards, no toolkit inside it, no `.git`. It is
what the config tests and the web smoke test point `promptsRoot` at, and its shape is the assertion
-- a hub without a toolkit in it must serve every Tier-2 route.

It also carries the modules' fixtures as hub-root siblings of `test/`: `growth/current/` with one
artifact per type, `reviews/test/2026/2026-04-01_2026-04-30/review.md`, `resume/resume.md`, and
`manager/current/` with three sessions whose `## Stage` values are `draft`, `prep` and `retro`.
There is deliberately **no `manager/archive/`** -- a hub without one must still serve `GET /manager`,
and `test_manager.py` is what says so. Pointed at this hub, `GET /api/growth` answers 3 items,
`GET /api/manager` 3 sessions and `GET /api/reviews` 1 review.

## Serving the web UI in production

```python
CLIENT_DIR = REPO_ROOT / "web" / "dist" / "client"
```

If that directory exists, `create_app()` calls `mount_client()`, which mounts `/assets` from it and
serves `index.html` as the SPA fallback for every non-API path. The `/api` router is registered
first, so API routes always win over the fallback -- and the fallback **refuses the API prefix**: an
unmatched `/api/...` path (a typo, a retired route, a client built against a newer agent) is a JSON
404 whose `detail` names the path, never `200 text/html`. The prefix is `API_PREFIX` in
`core/config.py`, read by the router and the refusal alike rather than typed twice. In a dev checkout
the directory does not exist -- `web/dist/` is gitignored and nothing builds it for you -- so the
whole block is a no-op and the dev server (`npm run dev`, with its own `/api` proxy) is what serves
the UI. `Tests/test_app_serving.py` builds a scratch `dist/client` and mounts it on an app of its
own, so the behaviour is under test whether or not anyone has run `npm run build`.

The other production path is Docker, which is `web/`'s business: see [`../web/README.md`](../web/README.md).
