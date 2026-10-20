# Verifying an install

The manual runbook: the gates a person works through to prove a machine actually works, for
everything no automated suite can assert -- a live Azure DevOps or GitHub board, a real browser,
Windows PowerShell 5.1, a second machine. Run it after a fresh clone, after a move to a new laptop,
or after changing anything that touches command registration. A change is built and proved on one host and
walked from nothing on the other, and most of this file is that second walk on Windows;
Gate 12's "Rows added by a fix" is the ledger of checks a fix left for another machine to
confirm.

Work the gates **in order**. Each one's prerequisites are proven by the gate before it, so a
failure at gate 4 that skipped gate 2 tells you nothing.

Substitute your own prefix for `tk` throughout if you changed `commandPrefix`.

---

## Windows is verified last, and only there

The Toolkit's floor is Windows PowerShell 5.1, and nothing on macOS or Linux can run it -- the Compat suite
checks 5.1 syntax statically, which is not the same thing. So the build finishes on the host that
built the change, and a Windows machine runs one gate from nothing: [Gate 12, "Windows install and test"](#gate-12----windows-install-and-test)
-- clone by the README and [Quick start](docs/QUICKSTART.md) alone, autoload on both hosts, the full
suite in `powershell.exe`, agent and web cold start, one real card through the bridge, module flags
on and off. The Windows run is verification-only; every guess it has to make is a defect in the documentation.

**The verification run files defects, it does not fix them.** Anything Gate 12 turns up is filed as a GitHub issue
([Contributing, "Start with an issue"](docs/CONTRIBUTING.md#start-with-an-issue)); the diagnosis and the fix
happen on the machine that built the thing.

---

## Why this file exists

The suites prove what a machine can assert about itself: a rule over fixtures, a verb typed in a fresh
shell against a scratch hub, a stubbed `gh` or `az`. **VERIFY is for the checks no suite can make**: a
live Azure DevOps or GitHub board, a real browser, Windows PowerShell 5.1, a second machine, the two
halves talking to each other, and the flag that makes a whole module appear and disappear in all
three halves at once. A check that can be automated belongs in a suite; one that cannot is a gate here,
or it is not verified.

Every verb `config.default.json` defines is in the table below -- 42 always-on, and the 14 the modules
contribute through `Config/*.commands.psd1` (56 in all; `docs/CLI.md` prints both counts) -- with the
suite that types it and the gate that walks it. `Tests/Test-DocCounts.ps1` reads the table back, so a
verb added without a row fails a suite. **A row that says "neither" is a verb nothing verifies**; it is
left in the table rather than dropped, because a verb the reader cannot see in it is indistinguishable
from a verb that was never counted.

Suite names are `Tests/Get-ToolkitSuiteRegistry.ps1`'s keys (`tkTestToolkit -<Name>` runs one). "Typed"
means the suite runs the verb as a verb in a fresh shell; "script only" means it drives the script
behind it, or one rule inside it, and not the verb; "registration only" means it proves the verb is
present when its flag is on and absent when it is off, and nothing it does.

| Verb | Suite | Gate |
| --- | --- | --- |
| `Menu` | `Menu`, `ModuleCommands` (typed) | 2, 9, 10 |
| `Status` | `PromptStatus` (the state rule), `Move`, `Start` (typed) | 5, 6 |
| `Archive` | `Archive` (typed) | 5, 6 |
| `Start` | `Start` (typed) | 12 |
| `Update` | `Update` (typed) | 12 |
| `Sync` | `Sync` (typed, against a bare repo; hook cases skip where there is no `hooks/pre-commit`, and a skip is not a pass) | 6, 12 |
| `Move` | `Move` (typed) | neither |
| `Billable` | `Billable` (typed) | neither |
| `Cover` | `Cover` (typed) | 12 (the reader's paths on Windows and 5.1, and a picture on the board) |
| `NewPrompt` | `NewPrompt` (`-Title` offline form; `-Design` typed in a fresh shell) | 6 (the ADO form); 12 (`-Design` and its chip on Windows) |
| `NewItem` | `EditItem` (typed, `-FromCard` only, with `gh` stubbed); `Tests/test_studio.py` (typed, `-FromDesign` only) | 6; 12 (`-FromCard` against the GitHub demo) |
| `NewPR` | `PullRequest` (script only: the Described Changes parser) | 6 |
| `PublishPR` | `PublishPR` (typed, with `az`, `gh` and the REST call stubbed) | 6; 12 (a real draft on a real Azure DevOps org: the row under "Rows added by a fix") |
| `GetPRComments` | `PRComments` (script only: the thread filter, follow-ups, the side record; not the live fetch) | 6 |
| `ReplyPR` | `PRComments` (script only: the reply written into the card; not the live post) | 6 |
| `AddPRReview` | `ExitCodes` (the missing-key refusal; the branch search's and the details fetch's 401/403/404 with the REST call stubbed) | 12 (a real expired token) |
| `ThreadHash` | `ThreadHash` (script only) | 6 |
| `CloseItem` | `CloseWorkItem` (the transition rule and error parsing; typed in a fresh shell with `az` and the REST calls stubbed: `-WhatIf`, a Task to Closed, a Bug to Resolved, an item already closed) | 6 (the live close on a real board), 12 |
| `EditItem` | `EditItem` (typed, with `gh` and `az` stubbed) | 12 (a real repository) |
| `MyWork` | neither | 6, 8c |
| `MyPRs` | neither | 8c |
| `Dashboard` | neither | 8c |
| `SwitchSpace` | `Config` (typed against a file that already says `activeSpace`, the file read back), `Menu` (registration and wording) | 2, 3, 8 |
| `Env` | `Environment` (typed, through the wrapper) | 3 |
| `Setup` | `Setup` (typed, with `az` off the PATH) | 3 |
| `Config` | `Config` (typed) | 3 |
| `Connect` | `Connect` (typed, with both CLIs stubbed) | 12 (real sign-in) |
| `NewSpace` | `NewSpace` (typed, with `gh` stubbed or off the PATH); `Tests/test_new_space.py` (typed in a fresh shell against a scratch hub, and `GET /api/spaces/candidates`); `Menu` (usage, wrapper and script agree) | 12 (under 5.1, with a real `gh`; a person adding a Space from the + and from the terminal) |
| `RetireSpace` | `NewSpace` (typed: `-WhatIf`, status `archive` through `Config`, a local status override unset, already retired, the refusals); `Menu` (usage, wrapper and script agree) | 12 (under 5.1, and from the Spaces card's row menu) |
| `RemoveSpace` | `NewSpace` (typed: `-WhatIf`, the `-Force` rule, the folder and its cards untouched, the line that adopts them back, every refusal); `Config` (the whole-Space `-Unset`); `Menu` (usage, wrapper and script agree) | 12 (under 5.1, and from the Spaces card's row menu) |
| `Log` | `ExitCodes` (`Log -Days` leaves no stale exit code) | 7 |
| `InstallAutoload` | `Autoload` (typed) | 1 |
| `Web` | `Web` (the guards only: no suite starts a real server) | 8 |
| `Agent` | `Agent` (the guards only) | 8 |
| `Test` | `TestAll` (script only, every half stubbed: the parsers, each skip, the exit codes, the summary file); `Menu` (usage, wrapper and script agree) | 4, 12 (the three real halves on both hosts) |
| `TestToolkit` | `DocCounts` (the runner's own verdict rule) | 4 |
| `TestCompat` | it is the `Compat` suite, run alone | 4 |
| `TestMenu` | it is the `Menu` suite, run alone | 4 |
| `TestSync` | it is the `Sync` suite, run alone | 4 |
| `NewGrowth` | `ModuleCommands` (registration only) | 9 |
| `NewWorkReview` | `Review` (script only: `Generate-Review.ps1`) | 9, 12 (a git-history read under 5.1) |
| `PublishWorkReview` | neither | 9 (registration and `-Help` only) |
| `LogPeerReview` | `Archive` (script only: the record's bytes) | 9 (registration and `-Help` only) |
| `UpdateResume` | `ModuleCommands` (registration only) | 9 (registration and `-Help` only) |
| `SendTeams` | `SendTeams` | 10 |
| `NewMeeting` | `NewMeeting` | 10 |
| `MeetingAgenda` | `MeetingAgenda` | 10 |
| `NewReminder` | `Reminders` (typed) | neither |
| `Reminders` | `Reminders` (typed) | neither |
| `NewDesign` | `Tests/test_studio.py` (typed in a fresh shell: a core verb whatever a leftover `features.studio` says, and the file it writes); `Menu` (usage, wrapper and script agree) | 12 (the two writers under 5.1, Promote against a real repo; the Studio core in a profile-less shell) |
| `StampDesign` | `Tests/test_stamp_design.py` (typed in a fresh shell against a scratch repo and a scratch hub); `Menu` (usage, wrapper and script agree) | 12 (under 5.1, and on a CRLF checkout; the Studio core in a profile-less shell) |
| `MoveDesign` | `Tests/test_move_design.py` (typed in a fresh shell against a scratch repo and a scratch hub under `storeSync: git`: every road, every refusal, the journey, the stamps, the bytes, staging without a commit); `Menu` (usage, wrapper and script agree) | 12 (the hub road against a real synced hub, and the drawer's moves in a browser) |
| `Standup` | `Rituals` (typed, with `gh` stubbed) | neither |
| `Triage` | `Triage` (typed, with `gh` stubbed) | neither |
| `Route` | `Triage` (typed, with `gh` stubbed -- the exact argv per switch, never a real write) | 12 (one real write against a GitHub Space) |
| `StartWork` | `StartWork` (typed, the block byte for byte; `gh` stubbed for an issue) | 12 (the cold-agent walk) |

Gate numbers are this file's `## Gate N` headings (8c is gate 8c). The four `Test*` verbs after
`Test` are the CLI runner itself, so their rows say what covers the runner.

A green suite means the covered half is sound. It says nothing about the other half. The same split
applies to the agent and the web UI: `pytest` and `npm test` cover their logic, and gate 8 is where the
two processes are proven to talk to each other.

---

## Gate 1 -- Install

```powershell
Import-Module .\utilities.psm1 -Force
tkInstallAutoload
```

**Expect:** an `[OK]` line per module directory installed. On Windows there are two -- PowerShell 7
and Windows PowerShell 5.1 -- and you need both.

Now prove it survives a shell that never runs a profile:

```powershell
pwsh       -NoProfile -c "tkStatus"
powershell -NoProfile -c "tkStatus"
```

**Expect:** both print the status table. Neither says "not recognized".

- [ ] pwsh 7, no profile
- [ ] Windows PowerShell 5.1, no profile

> Failing only in 5.1 almost always means the installer wrote to
> `Documents\PowerShell\Modules` but not `Documents\WindowsPowerShell\Modules`. The two hosts do
> not share a module path.

---

## Gate 2 -- The prefix is data

```powershell
Register-PromptAlias -Prefix gt
gtStatus
gtMenu -Markdown | Select-String SwitchSpace
```

**Expect:** `gtStatus` produces identical output to `tkStatus`, and the markdown row reads
`gtSwitchSpace` -- not `tkSwitchSpace`, and not a literal `{cliPrefix}`.

- [ ] A second prefix registers
- [ ] Both prefixes resolve to the same functions
- [ ] Help and menu text render the *calling* prefix

Then confirm that ONE shell owns ONE toolkit. The verbs are global aliases, so a second checkout
imported into the same session takes the names -- and a toolkit installed on the machine resolves
them in a shell that imported nothing at all. In a fresh shell:

```powershell
pwsh -NoProfile -Command "`$env:PSModulePath = (Resolve-Path .); Import-Module ./Prompt20Toolkit/Prompt20Toolkit.psd1 -Force; tkMenu -All"
```

**Expect:** every row is `tk*` and comes from THIS checkout. Setting `PSModulePath` inside the
child is the part that matters: `-NoProfile` does not stop module auto-loading, and pwsh puts the
user and system module paths back at startup, so a variable set in the parent shell is not
isolation.

- [ ] One shell, one toolkit, and it is this checkout

---

## Gate 3 -- Configuration and tier

```powershell
tkSetup
tkEnv
tkSwitchSpace Status
```

**Expect from `tkSetup`:** all checks `[ok]` except ones naming something you genuinely have not
configured. **A warning you have decided to live with is fine; a warning you cannot explain is a
finding.** Nothing should reference a tool this package does not use.

**Expect from `tkEnv`:** the right machine, OS and tier, the hub you configured, the active Space
(slug and name), and the `az` identity you expect on the `az login` row. This is where a
wrong-tenant login shows up. It reports no repo and no branch, by design: the prompt store is not
this repo, and the cwd's branch is not what this command is about.

- [ ] Prerequisites explained
- [ ] `az` identity is the expected one
- [ ] Active org is the one you meant

> `az devops configure -l` may show a default org/project pairing that does not exist. Harmless --
> every command passes org and project explicitly from config -- but do not debug from it.

### An org the hub declared

Only if your hub has a `hub.json` (it is optional; skip this block if it does not). Write one that
declares an org whose slug is **not** in `config.default.json`, with its own `promptsFolder`, then:

```powershell
tkEnv                       # the hub.json row: "read, N Spaces declared"
tkSwitchSpace <that-slug>     # selects it
tkSwitchSpace Status          # reports it as active
tkStatus                    # reads that org's folder in the hub
```

```bash
curl -s localhost:4100/api/env | python -m json.tool | Select-String -Context 0,3 '"hub"'     # macOS/Linux: python3 ... | grep -A3
```

**Expect:** the org is selectable and scoped to exactly like a shipped one, `hub.spaces` in `/api/env`
matches the number `hub.json` declares, and the `hubManifest` check row says the same thing in
words. A hub with no `hub.json` must report `"manifest": false` and behave exactly as it did before.

- [ ] A hub-declared org appears in `tkSwitchSpace` and scopes `tkStatus`
- [ ] `tkEnv` and `/api/env` agree on whether a manifest was read and how many orgs it declared

### Configuration, written rather than hand-edited

`tkConfig` is the one writer for configuration, and the web UI's settings drawer is a form over it. This
gate proves both ends of that, and needs no ADO.

```powershell
tkConfig                                   # every setting, with its source
tkConfig -Schema                           # what may be set, and which file each lands in
tkConfig -Set email=you@example.com        # creates config.local.json if it is not there
tkConfig -Set commands=nope                # a stated refusal, exit 2, nothing written
```

**Expect:** the `-List` table names a source per row -- `default`, `hub`, `local`, `env` or
`unset` -- and `email` moves to `local` after the `-Set`. `config.local.json` is a **sparse patch**:
the key you set and nothing else, no copy of the shipped table. The refusal says `'commands' is
defined in config.default.json, which this command never writes` and leaves `$LASTEXITCODE` at 2.

Then the same thing from the browser, with the agent up (`tkAgent`) and the web UI on
(`tkWeb -Dev`). Open **System**, then click the **avatar** at the right of the nav bar and choose **All settings**
-- the settings drawer slides in over it:

1. under **Configuration**, change **Your work email** (its key, `email`, is the caption under the
   box) and press **Save** at the foot of the drawer;
2. close the drawer and read the **Identity** row in the Environment card.

```bash
curl -s -X PUT localhost:4100/api/config \
  -H 'Content-Type: application/json' \
  -d '{"set":{"features.growth":true}}'
curl -s localhost:4100/api/env | python -m json.tool | Select-String -Context 0,2 '"identity"'     # macOS/Linux: python3 ... | grep -A2
```

**Expect:** `result.status` is `success`, and `/api/env` reports the new identity **without an
agent restart** -- within a second, not after the 45-second cache TTL, because the write clears it.
`features.growth` likewise shows in `/env.features` on the next call. The drawer says no restart is
needed; it says the opposite only for `web.agentPort` and `web.corsOrigins`, which the agent binds
at startup.

- [ ] `tkConfig` lists a source per setting, and `-Set` creates `config.local.json` as a patch
- [ ] A key that lives only in `config.default.json` is refused by name, exit 2, nothing written
- [ ] Setting `email` from the settings drawer changes `/env.identity` with no restart
- [ ] An edit left unsaved survives closing the drawer (Escape, or a click on the scrim), and the
      avatar shows a dot until it is saved or discarded
- [ ] An org edit -- `tkConfig -Set spaces.<slug>.status=archive` -- lands in the hub's `hub.json`,
      and the org is still there afterwards

> An org is never deleted. `status=archive` is how one is retired, and `-Unset` refuses to remove a
> required field even with `-Hub`.

---

## Gate 4 -- The suite

```powershell
tkTestToolkit
```

**Expect:** every suite green, exit code 0, and the PS 5.1 compatibility suite reporting zero
findings. On this commit that is **44 suites, 7421 assertions** with a `config.local.json`, every one
of them reporting. `Sync`'s hook-interaction cases skip on their own where there is no
`hooks/pre-commit`, and the total does not depend on whether `npm ci` has run in `web/`: the Compat
sweep does not descend into `web/node_modules`. That total is the one from the host that built the change; a Windows run reads a few
fewer on the same commit, every suite green on both -- `docs/TESTING.md`, "The CLI total is per
platform".

Then the other two halves -- or all three at once with `tkTest`, which runs these same three and
names any half it had to skip:

```bash
python -m pytest Tests/      # Windows (python3 is the Store stub there); macOS/Linux: python3 -m pytest Tests/
cd web && npm test           # the shell; the current counts are in docs/TESTING.md
```

- [ ] All suites pass
- [ ] Exit code is 0
- [ ] **No suite is SKIPPED that you expected to run**
- [ ] `TEAMS_WEBHOOK_MANAGER` and `TEAMS_WEBHOOK_DEMO_CHANNEL` were **unset** before the run. The
      three communication suites unset them per process, but a run that starts from a shell holding
      a live webhook is one bug away from sending a real message

A skip is not a pass. Read the summary line, not just the total.

**What CI covers of this gate.** A pull request's check (`.github/workflows/verify.yml`) runs these three
runners on Ubuntu, reads each one's summary line and fails a step on a failure, a skipped half or a run
that counted nothing ([docs/TESTING.md](docs/TESTING.md), "In CI"). That is this gate on Linux under
`pwsh` 7. Its Windows job adds the CLI half on Windows: `tkTest -Half cli` typed in Windows PowerShell 5.1
after the one-manifest import, read the same way, with the runner starting each suite in `pwsh` 7. Nothing
more: each suite run as a file under 5.1, and the agent's and the web UI's runners on Windows, are still
walked here and in Gate 12.

---

## Gate 5 -- The local workflow, without ADO

This half must work on a machine with no `az` at all (Tier 2).

```powershell
tkStatus
tkArchive <name>          # on an unshipped card -- expect a refusal
tkArchive <name> -Force
```

**Expect:** `tkStatus` derives all four states from real files -- Active, In Progress, Code
Review, Done. `tkArchive` refuses a card with no `PR URL:` line, and says why, until `-Force`.

- [ ] All four states derive correctly
- [ ] Archive refuses unshipped work
- [ ] `-Force` overrides, moves the file, and commits

---

## Gate 6 -- The ADO round trip

**This is the gate the automated suite cannot reach.** It needs a real card in a real org.

```powershell
tkNewItem -Title "Verify install" -Type Task    # or use an existing card id
tkNewPrompt <id>
```

- [ ] File lands in `{promptsRoot}/{org}/current/`, **not** in the tool repo
- [ ] Title, type, sprint, acceptance criteria and ADO link all populated from the card
- [ ] Template link at the top resolves -- click it
- [ ] Suggested branch name uses `branchUser`, or your OS username if unset

Make **two** real commits on that branch, then -- **from inside the code repo, not the hub**:

```powershell
tkThreadHash
tkThreadHash          # deliberately twice
tkStatus
```

- [ ] Both commits appear, each its own `- {hash} {message}` bullet, oldest first
- [ ] The hashes are the **code repo's** -- check them against `git log` there, not the hub's
- [ ] The `- (pending)` placeholder is gone
- [ ] The second run adds nothing and says so
- [ ] `tkStatus` flips the card to **In Progress**

Then, from a folder that is not a git repository at all:

```powershell
tkThreadHash
```

- [ ] It refuses (exit 2), says it is not a git repository, and names `-Hash` as the way round it

```powershell
tkNewPR
```

- [ ] PR opens in the right repo
- [ ] ADO card moves to Code Review
- [ ] `PR URL:` is written back into the prompt file
- [ ] `tkStatus` now reads **Code Review**

```powershell
tkGetPRComments
tkGetPRComments          # deliberately twice
```

- [ ] Threads appended
- [ ] **The second run adds nothing and rewrites nothing** -- this is the one most likely to break

```powershell
tkReplyPR <pr> <thread> -Reply "verified"
```

- [ ] Reply visible on the PR
- [ ] Result threaded back into the prompt file

Then close a **test** work item -- a Task made for the purpose, never a real one -- dry run first:

```powershell
tkCloseItem <id> -WhatIf -Comment "verified"
tkCloseItem <id> -Comment "verified"
tkCloseItem <id> -Comment "verified"          # deliberately twice
```

- [x] `-WhatIf` names the work item, its current state and the planned transition (`Active -> Closed (Completed)` for a Task), and the board is unchanged afterwards
- [x] The real run sets the state to **Closed** (a Bug goes to **Resolved**) and ends with a `[RESULT]` line naming the type, state and reason
- [x] The board shows the new state, and the comment is in the item's discussion
- [ ] The second run says the item is already closed, changes no state, and still posts the comment
- [ ] A `-Reason` the project's process does not accept is refused (exit 2) with ADO's own sentence, and the item is left as it was

```powershell
tkMyWork
tkSync
tkArchive <name>
```

- [ ] `tkMyWork` returns *your* items (needs `email` set in `config.local.json`)
- [ ] `tkSync` pulls with rebase and pushes against the real remote -- it only does so when
      `storeSync` is `git`, which the hub declares in its own `hub.json` and `config.local.json`
      overrides per machine; on a `none` hub the expected result is `Nothing to sync`
- [ ] `tkArchive` moves to `archive/` and commits; `tkStatus` no longer lists it

---

## Gate 7 -- Diagnostics

```powershell
tkLog -Today
tkLog -Errors
```

- [ ] Today's commands are recorded
- [ ] Failures from this run appear under `-Errors`
- [ ] The log holds environment, command, failure and time -- **and no card content**

---

## Gate 8 -- The agent and the web UI

The automated suites cover the agent's logic and the shell's registry. They do not cover the two
processes actually talking to each other, or either one pointed at a real hub. That is this gate.

Start both. Once the prerequisites are installed, `tkWeb -Dev` is the whole of it:

```bash
python -m pip install -r agent/requirements-dev.txt    # Windows; macOS/Linux: python3. Runtime deps plus pytest and httpx
cd web && npm ci && npx playwright install chromium && cd ..   # the browser is for the smoke only
```

```powershell
tkWeb -Dev
tkWeb -Status
```

**Expect from `-Dev`:** the agent starts and prints its PID, then Vite starts and the command prints
the URL it actually took. It asks for 5174 and takes the next free one if that is busy -- note which
it printed, the rest of this gate needs it. The command **returns**; it does not hold the terminal.

**Expect from `-Status`:** both halves reported, the agent's health probe answering `ok`, and the
hub it is serving. That last line is the quickest check that `promptsRoot` is what you think.

- [ ] `tkWeb -Dev` brings up both halves and returns
- [ ] `tkWeb -Status` reports the dev server, its URL, and a healthy agent
- [ ] Dev server port noted

> The by-hand equivalent is `python -m uvicorn agent.app:app --port 4100` (`python3` on macOS/Linux) from the repo root and
> `npm run dev` in `web/`, in two terminals. Worth doing once if `-Dev` fails, because nothing is
> redirecting the output.

Now the fixture hub, which is what the smoke test asserts against. One command restarts the agent
on it as a test run, with its Space and no flags, through the environment -- **`config.local.json`
is not written**, so there is nothing to restore afterwards:

```bash
tkWeb -Dev -Fixture
curl -s localhost:4100/api/env
cd web && npm run smoke
```

**Expect from `/env`:** `promptsVolume` reads `<path> -- readable`, `activePrompts` reads
`2 active prompts`, and `displayName` is `Toolkit` on a clone with no personal config -- not
anyone's name.

**Expect from the smoke:** every line `PASS` (the count for each mode is in `docs/TESTING.md`) and
`smoke: clean (modules=off, viewport=desktop)`. The default mode is flags-off, and `-Fixture` without
`-Modules` starts the agent with **no** flag set whatever your own `config.local.json` says -- several
of the checks are assertions about modules that are absent. The flags-on mode is Gate 9b.

Then the phone, which is a different layout: at 430px nothing may lay out wider than the viewport.

```bash
npm run smoke -- --viewport=both --port=<the port Vite printed>
```

**Expect:** every line tagged `[desktop]` or `[mobile]`, each check once per viewport, and
`smoke: clean (modules=off, viewport=both)`. The per-route `does not scroll sideways` lines are the
ones that matter at 430px.

**And keep the picture.** `--shots=<dir>` writes one full-page PNG per route it visits, per viewport,
under `web/shots/` -- which is gitignored, because evidence belongs to the machine that produced it:

```bash
npm run smoke -- --viewport=both --shots=shots/gate8 --port=<the port Vite printed>
```

That is this gate's visual record, and the answer to "your real cards render" below: run it again
against the real hub and the two folders are what you look at. It is not a new verb and it captures
nothing the smoke does not already drive.

- [ ] `/env` reports the fixture hub as readable, 2 active prompts
- [ ] `displayName` is nobody's name
- [ ] `npm run smoke` passes every check and prints `smoke: clean (modules=off, viewport=desktop)`
- [ ] `--viewport=both` passes every check in both viewports, and nothing scrolls sideways at 430px
- [ ] `--shots=shots/gate8` leaves a PNG per route per viewport under `web/shots/`, and git does not
      see them

Then point it at a **real** hub -- your own `promptsRoot`, your own `activeSpace`; `tkWeb -Dev` puts
the agent back on it, since it sees an agent serving the fixture hub and restarts it -- and open the
UI in a browser.

- [ ] `/` lists your real cards, with the same states `tkStatus` derives for them
- [ ] `--shots` run again against the real hub, so the gate leaves a picture of what you saw
- [ ] `/system`'s `EnvCard` reports the tier you expect, and says why if it is not Tier 1
- [ ] The avatar menu: **Theme** changes the page at once and the submenu stays open; **Modules**
      opens the drawer with the first module's switch at the top, focused
- [ ] The nav avatar shows *your* name, from `branchUser` or `email` in `config.local.json`
- [ ] Switching org in the UI changes what `tkSwitchSpace Status` reports in a terminal -- one
      `config.local.json`, two interfaces

Then stop both, which is the other half of the claim:

```powershell
tkWeb -Stop
tkWeb -Status
```

- [ ] `-Stop` ends the dev server **and** the agent
- [ ] `-Status` afterwards reports both as not running, and still exits 0

**What CI covers of this gate.** The check's Windows job runs the two smoke modes that start their own
servers, `npm run smoke:matrix` and `npm run smoke:a11y`, and fails a step on a failure, a serious or
critical axe finding, or a run that never reached its closing `smoke:` line ([docs/TESTING.md](docs/TESTING.md),
"In CI"). The modes above, against servers `tkWeb -Dev` started, the phone viewport, the pictures and the
real hub are still walked here. The landing page is in no smoke mode: `npm test` holds its words, and
`.github/workflows/pages.yml` builds and deploys it on every push to `main`. The page in a
browser is walked: `npm run build:landing`, then `npx vite preview --mode landing` in `web/`, at desktop
and phone width in both system themes, **Play Introducing ToolKit** playing the first slide aloud and
Escape bringing the page back.

---

## Gate 8b -- A write through the bridge

Gate 8 proves the two processes talk. This proves the third thing: that a write from the web half
goes through the CLI and lands as the CLI would leave it. It needs no browser and no ADO.

Point `promptsRoot` at a **copy** of `Tests/fixtures/hub` -- not the committed fixture, because this
moves a file -- and make sure the copy has a `test/archive/` folder and `activeSpace` is `test`, the fixture's own Space (the shipped default is `azure-demo`). With the agent up:

```bash
curl -s -X POST localhost:4100/api/cmd/Archive \
  -H 'Content-Type: application/json' \
  -d '{"params":["402-timeout-on-large-files.prompt.md"]}'
```

**Expect:** `"status":"success"`, `"exit_code":0`, and an `output` beginning `Moved:`. Then, in the
copy:

```bash
ls <copy>/test/archive/
grep '\*\*Closed:\*\*' <copy>/test/archive/402-timeout-on-large-files.prompt.md
```

- [ ] The file is in `archive/` and gone from `current/`
- [ ] It carries a `**Closed:** <today>` stamp -- the same thing `tkArchive` writes (G23)
- [ ] `POST /api/cmd/NotACommand` returns 200 with `"status":"rejected"`, and runs nothing
- [ ] `POST /api/cmd/Status` through the **dev server's** port, not the agent's, returns the same
      body -- which is the proxy the browser actually uses

> **A `success` is the CLI's definition of success.** A verb that catches its own failure prints
> `Error: ...` and still exits 0, so read `output`, not just `status`. AGENTS.md, "The refusal
> contract", is the rule that keeps a verb from doing it; an `Error:` line under a `success` is a
> finding.

---

## Gate 8c -- The Tier-1 routes, against a real org

**This is the agent's half of Gate 6.** Every Python test runs against fixtures at Tier 2, and
Gate 8 runs the two processes against a hub with no tracker -- so `/prs`, `/work-items`,
`/dashboard`, `/dashboard/pipelines/{project}`, the sprint routes and `suggest` were carried from a
package where they worked, and no suite runs them against a live tracker. "Carried intact" is an
assumption until this gate is run. This gate needs what Gate 6 needs: `az login`, an
org whose `status` is `active` and whose `projects` are declared, and at least one open work item
and one open pull request of your own in it.

With the agent up and `tkSwitchSpace` on that org, the claim is that **each Tier-1 card on `/` shows
what the CLI verb beside it prints** -- same rows, same count, from the same `az`:

```powershell
tkEnv                                   # Tier 1, and Identity resolved -- the routes filter by it
tkMyWork                                # against the My Work card
tkMyPRs                                 # against the My Pull Requests card
tkDashboard                             # against the dashboard's counts and pipeline runs
```

```bash
curl -s localhost:4100/api/env | python3 -c 'import json,sys; e=json.load(sys.stdin); print(e["tier"], e["identity"])'
curl -s localhost:4100/api/work-items | python3 -c 'import json,sys; b=json.load(sys.stdin); print(b["count"], b["reason"])'
curl -s localhost:4100/api/prs        | python3 -c 'import json,sys; b=json.load(sys.stdin); print(b["count"], b["reason"])'
curl -s localhost:4100/api/dashboard  | python3 -c 'import json,sys; b=json.load(sys.stdin); print(b["tier"], b["pr_count"], b["work_item_count"], b["reason"])'
```

- [ ] `/env` reports `tier: 1` and the same address `tkEnv` shows under Identity
- [ ] `/work-items` lists the ids `tkMyWork` lists, no more and no fewer, and `reason` is `null`
- [ ] `/prs` lists the PRs `tkMyPRs` lists, author and reviewer both, and `reason` is `null`
- [ ] `/dashboard`'s `pr_count` and `work_item_count` are those two counts, and
      `/dashboard/pipelines/<project>?repo=<repo>` returns the runs `tkDashboard` prints for that
      project -- open the project's tab on `/` and compare the rows
- [ ] On `/`, the My Work, My Pull Requests and dashboard cards show exactly those rows. The
      `Updated` column on My Work matches the work item's changed date in ADO
- [ ] `/daily` shows the week's cards, and every row is a card `tkStatus` lists for this org (Daily
      is built from the cards' own dates, not from `az`, so this is the one card on the page that
      must NOT change when `az` goes away below)
- [ ] If the org has `features.sprintAwareness: true`, `/stress-status` answers with the sprint
      rather than `enabled: false`, and the Sprint card on `/` renders it

Then the degradations the fixtures cannot reach, because they need a real `az` to fail in a real
way. Each is an empty card **with a stated reason**, never a silently empty one:

```powershell
az logout                               # then, in the SAME shell the agent runs in, or restart it there
```

- [ ] `/prs` and `/work-items` answer `count: 0` with a `reason` that names the `az` command and
      the project it was asked about, and the cards on `/` show that sentence under the empty state
- [ ] `az login` again: the next fetch (after the 45-second probe TTL, or `GET /api/env?refresh=1`)
      is back to the rows above, with `reason: null`
- [ ] On an org whose `hub.json` entry has no `projects` (an org added through `Config` or the
      Configuration card is one), the three routes
      answer `No projects configured for <slug>` and ask `az` nothing

And `suggest`, the one model call in the ADO core, with a card in `current/` that has an open
review thread (Gate 6 leaves one):

```bash
curl -s -X POST localhost:4100/api/pr-comments/<card>/suggest -H 'Content-Type: application/json' \
  -d '{"thread_id":<id>,"comment_text":"<the comment>","file_path":"<path>","line":1,"reviewer":"bot","code_suggestion":""}'
```

- [ ] With `ANTHROPIC_API_KEY` unset in the agent's environment: **412**, and the detail names the
      variable -- `/env`'s `anthropicConfigured` said `false` beforehand
- [ ] With it set: 200, and a `recommendation` of `take`, `reject` or `modify` with a `draft_reply`
      under forty words -- the prompt it sent is `agentic/pr-suggest.prompt.md`, so an edit to that
      file's rules changes the next answer without a restart; `/env`'s `aiModel` is the model it sent
      (`ai.model` in config)
- [ ] `POST /api/pr-comments/<card>/save` is **404**: the route is retired, and the page posts a reply
      as `ReplyPR`, through the bridge

Record the org, the date and the counts in the run record below. A row that could not be checked
because the org lacks the thing (no pipelines, no open PR) is written as **not checked**, not as
passed.

---

## Gate 9 -- The growth module, on and off

Everything here needs a `config.local.json` at the **repo root**. Set the flag **top-level**, never
inside an `spaces[]` entry:

```jsonc
{ "promptsRoot": "Tests/fixtures/hub", "activeOrg": "test", "features": { "growth": true } }
```

**On.** Start a *fresh* shell -- module verbs are not in the autoload manifest, so they resolve
after an import and not before:

```powershell
pwsh -NoProfile -Command "Import-Module ./Prompt20Toolkit/Prompt20Toolkit.psd1 -Force; tkMenu -All"
pwsh -NoProfile -Command "Import-Module ./Prompt20Toolkit/Prompt20Toolkit.psd1 -Force; tkNewGrowth -Help"
```

**Expect:** `tkMenu -All` lists five more commands than it did with no flag -- `NewGrowth`,
`NewWorkReview`, `PublishWorkReview`, `LogPeerReview`, `UpdateResume` -- and each one answers `-Help`
with a usage line carrying **your** prefix, not a literal `{cliPrefix}`.

- [ ] All five verbs appear in `tkMenu -All`
- [ ] All five answer `-Help`, in the calling prefix

Then the web half, with `tkWeb -Dev` up and the fixture hub configured:

```bash
curl -s localhost:4100/api/growth
curl -s localhost:4100/api/reviews
```

- [ ] `/api/growth` returns the fixture's three artifacts -- a training, a presentation and a goal
- [ ] `/api/reviews` returns the one fixture review
- [ ] A **Growth** nav entry is in the browser, and `/growth` renders the three artifacts
- [ ] `/skills` renders `resume/resume.md`
- [ ] `/review` renders the review archive rather than "No reviews yet"

**Off.** Delete the `features` block -- restart nothing, the agent re-reads config per request -- and
start one new shell for the CLI half:

```bash
curl -s -o /dev/null -w '%{http_code}\n' localhost:4100/api/growth      # expect 404
curl -s -o /dev/null -w '%{http_code}\n' localhost:4100/api/reviews     # expect 404
curl -s -o /dev/null -w '%{http_code}\n' localhost:4100/api/resume      # expect 404
cd web && npm run smoke
```

- [ ] Those three, plus `/api/review-preview` and `/api/resume-preview`, return **404 -- not 403**
- [ ] `tkMenu -All` is silent about all five verbs, and `tkNewGrowth` is **not recognised**
- [ ] No **Growth** nav entry in the browser, and no **Meetings** nav entry either
- [ ] `npm run smoke` passes every check and prints `smoke: clean (modules=off, viewport=desktop)`
- [ ] `/review` reads "No reviews yet" **without an error** -- that page is an ADO card whose data
      growth serves, and this is the design rather than a failure

> The agent needed no restart between the two halves of this gate. If it did, that is a finding:
> the gate is a per-request dependency, not a mount-time decision. The smoke makes this flip
> itself: `npm run smoke -- --studio` sets `features.growth` true then false through `PUT /api/config`
> under one running agent and asserts the Growth nav entry comes and goes on a reload.

## Gate 9b -- The same thing from a browser, with both flags on

Gate 9's "off" half is proven twice over -- by `curl`, and by the smoke's default mode. Its "on"
half is proven by `npm run smoke -- --modules=on`, the repeatable version of driving it by hand.

Restart the agent with both flags on, through its environment -- as a test run, so no
`TEAMS_WEBHOOK_*` reaches it even when this machine's `.env` holds one, and with
`config.local.json` untouched:

```bash
tkWeb -Dev -Fixture -Modules on
cd web && npm run smoke -- --modules=on        # or: npm run smoke:modules
```

Unsetting the webhooks in your shell is **not** the recipe: the agent is started by `tkWeb`, which
imports the module, which reads `.env`. If the agent does hold one, the smoke refuses before it
opens a browser and names it.

**Expect:** every line `PASS` (the count is in `docs/TESTING.md`) and
`smoke: clean (modules=on, viewport=desktop)`.

- [ ] A **Growth** nav entry, and `/growth` lists the fixture hub's three artifacts by title
- [ ] `/skills` renders
- [ ] A **Meetings** nav entry, and `/communication` lists the three fixture sessions with their
      stages -- Plan, Prep, Retro
- [ ] The retro session's send button is **present, disabled, and names `TEAMS_WEBHOOK_MANAGER`**
- [ ] No page errors across the six routes

> The send button is never pressed, by the runner or by you. A press posts to a real webhook, and
> the engine takes whatever is in the environment at face value. The assertion is the disabled
> state and the variable's name -- an enabled button here means a live webhook is configured, and
> that is a reason to stop, not to continue.

---

## Gate 10 -- The communication module, and its second gate

```jsonc
{ "promptsRoot": "Tests/fixtures/hub", "activeOrg": "test", "features": { "communication": true } }
```

**On.** From a fresh shell:

```powershell
pwsh -NoProfile -Command "Import-Module ./Prompt20Toolkit/Prompt20Toolkit.psd1 -Force; tkMeetingAgenda -Help"
```

- [ ] `tkSendTeams`, `tkNewMeeting` and `tkMeetingAgenda` appear in `tkMenu -All`
- [ ] All three answer `-Help`, in the calling prefix
- [ ] `curl -s localhost:4100/api/manager` returns the fixture's three sessions, newest first
- [ ] A **Meetings** nav entry is in the browser, and `/communication` renders the card
- [ ] An old bookmark still works: `/growth/1on1/2026-02-05.md` redirects to
      `/communication/1on1/2026-02-05.md` with the filename intact

**The second gate -- the env var.** This is the one that is easy to mistake for a broken install.
With `TEAMS_WEBHOOK_MANAGER` **unset**:

```bash
curl -s localhost:4100/api/env | python -c "import json,sys; print(json.load(sys.stdin)['communication'])"     # macOS/Linux: python3
```

- [ ] `/env` has a `communication` block, and its one recipient reads `"configured": false`
- [ ] The block **names the variable** (`"webhookEnv": "TEAMS_WEBHOOK_MANAGER"`) and does not
      contain a URL anywhere
- [ ] On a Retro-stage session, the send button is **visible and disabled**, with the reason on the
      line below it naming `TEAMS_WEBHOOK_MANAGER` -- not hidden, and not an error
- [ ] `tkSendTeams manager 'test' -WhatIf` prints the same refusal, names the variable, and
      **exits 0** -- an unset variable is a configuration fact, not a failure

Then set the variable to anything and re-read `/env`:

- [ ] `"configured"` flips to `true` and the button enables at the Retro stage

> **Do not press it, and do not run `tkSendTeams` without `-WhatIf`, unless you mean to send.**
> `POST /api/comms/send` posts to whatever URL that variable holds, at face value. `-WhatIf` (or
> `"dryRun": true` on the body) runs every gate and formats the markdown without posting.

If you do mean to send, once: the file records it. On `ok` the page appends
`Sent to manager: <ISO date>` under `## Sent` through the `PUT`.

- [ ] A real send appends one `Sent` line to the session file, and leaves the agenda untouched

**Off.** Delete the `features` block:

```bash
curl -s -o /dev/null -w '%{http_code}\n' localhost:4100/api/manager        # expect 404
curl -s -X POST -o /dev/null -w '%{http_code}\n' localhost:4100/api/comms/send \
     -H 'Content-Type: application/json' -d '{}'                           # expect 404
```

- [ ] `/api/manager` and `POST /api/comms/send` return **404 -- not 403**
- [ ] `/env` has **no** `communication` block at all
- [ ] `tkMenu -All` is silent about all three verbs, and `tkSendTeams` is **not recognised**
- [ ] No **Meetings** nav entry in the browser

---

## Gate 10b -- The deck module

Web-only, so there is no CLI half to this gate -- and it has the one check in this file that no
suite can ever make: whether it SOUNDS right.

```powershell
tkConfig -Set features.deck=true
tkEnv          # Deck module   on -- web UI only -- it adds no verbs
tkWeb -Dev
```

- [ ] **Growth** has a **Decks** card beside Reviews and Goals, listing one deck: *Trailer -- The
      Connected Deck Universe*, 19 slides, with an approximate length and the four state filters
- [ ] The arrow opens `/deck/connected-deck-trailer` **full screen** -- no Toolkit nav bar around it
- [ ] Arrow keys move through the slides; the counter reads `n / 19`
- [ ] **It speaks.** Un-mute, and the slide is read aloud; switch **Jenny** to **Brian** and the
      voice changes. No key, no server, no network call but the mp3
- [ ] **Exit** returns to Growth
- [ ] `/deck/connected-deck-trailer?present=1` is the podium: notes open in a second window and the
      deck window is silent
- [ ] `tkConfig -Set features.growth=false`: the Growth tab goes and a **Decks** tab appears in its
      place -- the flag never shows nothing. Set it back
- [ ] `tkConfig -Set features.deck=false`: no Decks card, no Decks tab, and `/deck/connected-deck-trailer`
      is not a route

> The first load fetches no deck code: the engine, the deck and its 38 voice files are a chunk
> requested when a deck card or route is shown. With the browser's network panel open on Home, there
> is no `DeckHost` or `.mp3` request until you go to Growth.

---

## Gate 11 -- Cold start

The real test, and the only one that proves the documentation.

On a machine that has never run this: clone, then follow **`README.md` and the documents it links**
alone -- no spec, no notes, no memory of how it works -- and take one real card from scaffold to
archive. Then bring up the web half the same way, from the README, `docs/QUICKSTART.md` and
`web/README.md` only.

- [ ] Clone and install using only the README
- [ ] Complete a full card without consulting anything else
- [ ] Bring up the agent and the web UI from the docs alone, and see your own cards in a browser
- [ ] Switch on a module from `docs/modules/README.md` alone -- find the flag, find that it is
      top-level, restart the right thing, and get the verbs, the routes and the nav entry
- [ ] Every point where you had to guess is a README defect -- fix it in the same session

## Gate 12 -- Windows install and test

Gate 11 run on Windows, from nothing, and then the parts only Windows can prove. This is the Windows
run's whole job: the host that built the change builds and records; the Windows host verifies here
and records each row in the run table at the foot of this file. It exists because the Compat suite
checks Windows PowerShell 5.1 *syntax* statically and nothing on macOS or Linux can *run* 5.1.

**Two hosts, every time.** Windows PowerShell 5.1 (`powershell.exe`) is the floor; PowerShell 7
(`pwsh`) is the daily shell. A gate that passes in one and not the other has failed.

**A row that sets `PROMPTS_ROOT` or `P20_ACTIVE_SPACE` starts a fresh shell with them already set**
-- `pwsh -NoProfile -Command "$env:PROMPTS_ROOT = '<scratch>'; tk..."`, and the same in
`powershell.exe` -- rather than exporting them into a window that has already loaded the toolkit. The
next verb does re-read a changed override the way it re-reads a changed `config.local.json`
([Configuration](docs/CONFIGURATION.md), "Overrides from the environment"), but a fresh shell is the one
shape where every line of the row was read from the same hub, and nothing in the walk can land in the
real one.

**The three runs are one line:** `tkTest` runs the agent's `pytest`, the CLI runner and the web UI's
`npm test` in order, each with its own environment, and prints one summary and one verdict -- a half
that cannot run is named SKIPPED, not passed -- and writes all three into `test-summary.<machine>.json`
(`docs/TESTING.md`, at its head). The rows below that name `tkTestToolkit`,
`python -m pytest Tests/` or `npm test` are the one-half form of the same runs.

- [ ] **Clone from nothing.** A fresh clone, then `README.md` and the Quick start it links
      alone: install prerequisites they name, nothing they do not (`git`, `pwsh`, `az`, Node,
      Python -- `docs/QUICKSTART.md`, "Requirements", says which are optional and for what)
- [ ] **Autoload on both hosts.** `tkInstallAutoload` (or `Install-ToolkitAutoload.ps1` before the
      verbs exist), then open a fresh `powershell.exe -NoProfile` **and** a fresh `pwsh -NoProfile`:
      `tkMenu` answers in both. Gate 1's note about the two module directories is the usual failure
- [ ] **The suite on 5.1.** `tkTestToolkit` in `powershell.exe`, full pass, count read from
      `test-results.<machine>.log` (latest row per suite). Then again in `pwsh`. Both totals go in
      the ledger next to the other host's; a suite that passes only on 7 is a 5.1 defect, filed
- [ ] **Configure against the real hub.** `config.local.json` with `promptsRoot` at
      your real hub and your real `activeOrg`; `tkSetup` green; `tkStatus` lists the
      org's `current/`
- [ ] **One real card through the bridge.** `tkAgent`, then `POST /api/cmd/Archive` (or the
      Archive button in the web UI) on a card you want archived: the file moves and carries
      `**Closed:**`, exactly as `tkArchive` writes. `tkArchive` on a second card for the
      side-by-side
- [ ] **Agent and web cold start.** Python (`agent/requirements-dev.txt`), `npm ci` and
      `npx playwright install chromium` from `README.md` and `web/README.md`
      alone; `tkWeb -Dev`; `tkWeb -Status` reports both; your real cards render; `npm run smoke`
      clean against the fixture hub in **both** modes (see Gate 8 and Gate 9b); then `tkWeb -Stop`
      and confirm **nothing** is left on the dev port (`lsof -nP -i:5174`, or
      `Get-NetTCPConnection -LocalPort 5174` on Windows). Docker: `tkWeb`
      (no `-Dev`) if Docker Desktop is present -- Gate 12b below is the other host's transcript to compare
      against; record the result either way
- [ ] **Modules on and off, on 5.1.** Top-level `features` both true: `tkMenu` in
      `powershell.exe` lists the eight growth and communication verbs and each answers `-Help`,
      `/growth` and `/communication/...` render, and `npm run smoke -- --modules=on` passes every
      check; both false: none of the eight in `tkMenu`, 404s, and `npm run smoke` passes every
      check. `TEAMS_WEBHOOK_MANAGER` unset for all of it. *The smoke holds the browser half
      for every module flag, each alone on: `npm run smoke -- --matrix` (the 5.1 menu half is still walked
      by hand).*
- [ ] **Windows-only seams.** Paths with spaces and backslashes in `promptsRoot`; a hub on a
      different drive letter; **a git-history read under 5.1** -- `tkNewWorkReview -StartDate
      <YYYY-MM-DD> -EndDate <YYYY-MM-DD>` in `powershell.exe`, with `features.growth` on and
      `promptsRoot` pointing at a hub that **is** a git repository (`Tests/Test-GenerateReview.ps1`
      builds a throwaway one the same way: `git init`, cards under `<org>/archive/`, commits dated
      with `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`), asserting
      `reviews/<slug-set>/<year>/<start>_<end>/review.md` appears under the hub with the window's
      cards in it -- the scaffold is built from `git log`, which is the read this row is about;
      **the bridge under `powershell.exe` only** --
      remove `pwsh` from `PATH` for the agent's process, start `tkAgent`, confirm
      `/api/env`'s `bridgeHost.resolved` is `powershell`, and archive a card through the UI: the
      file must move and carry `**Closed:**` exactly as it does under `pwsh`. With **neither** host
      on `PATH`, `bridgeHost.resolved` is `null` and `POST /api/cmd/Env` answers `status: error`
      naming both names, never `rejected`; line endings in files the CLI writes (`**Closed:**`
      stamp, `Sent to manager:` line) -- CRLF must not break the parsers on either side
- [ ] **Every guess and every failed row is an issue, not a fix.** File it as a GitHub
      issue with `agentic/new-issue.prompt.md` -- what you saw, on which host, on which commit. The
      host that built the change triages; fixes come back the same way. The Windows run is verification-only from here: it files, it does not build

**Expect:** every row checked on both hosts, recorded in the run table below with the machine
name and both suite totals, and every defect filed as a GitHub issue.

### A cold-start walk on Windows

Three things a Mac or Linux walk never meets, and that cost a cold Windows walk time the first
time. Python as `python` or `py -3`, and the port check, are already above and in `docs/TESTING.md`.

- **Walk from a short path.** Clone into something like `C:\wt\p20cold` or `$env:TEMP\p20cold`, never
  a deep folder: `node_modules` under a long path hits the Windows path-length limit and `npm ci`
  fails partway. Set `$env:PSModulePath` to that folder **inside the shell that runs the walk** and
  import the manifest from it (AGENTS.md, "One toolkit per shell"). Forward slashes are fine in git
  and in pwsh. Use `pwsh` 7 for the walk itself; 5.1 is for the rows that name it.
- **Give the walk its own `web.agentPort` from the start.** Windows lets two processes bind the same
  port, and `localhost` then answers from the other one, so a cold walk can quietly talk to your real
  agent. Set `web.agentPort` in the walk's `config.local.json`, and check which agent answers
  `/api/health`: it names its package root, which must be the scratch folder. The agent prints its
  own hint when another agent already holds the port (`Scripts/Start-Agent.ps1`). To end a stray one,
  `Stop-Process -Id <pid>` takes the place of `kill`.
- **Stop the servers before removing the worktree.** Windows locks files in use, so
  `git worktree remove` fails with "permission denied" or "directory not empty" while the dev
  server, the agent or the shell itself is inside the folder. `tkWeb -Stop`, change directory out of
  the folder, then remove it.

### Rows added by a fix

A fix built and tested on one host that only another machine can CONFIRM leaves its check here, in
the same commit (AGENTS.md, "A fix its own host cannot confirm leaves its check in VERIFY.md"). Each row
names the command, what you should see, and the issue it closes. A row stays until a verification run confirms
it and records that on the issue. Then the row moves into the gate it belongs to, or goes if a suite
now covers it on Windows too. `tkStandup -Walk` is the way to read this gate on the verifying host: it prints each `verify-close` issue with the row below that names it, by issue number.

- [x] **A save from the browser keeps a session's line endings.** In a scratch hub with
  `communication` on, `NewMeeting -Date 2026-10-20` from a fresh shell writes an LF session. Make the hub a git
  repository with `core.autocrlf` off (with it on, git hides the difference) and commit it, start the agent,
  save that session once with `PUT /api/manager/2026-10-20.md` and `{"since": "notes"}`, then run
  `git diff --stat` in the hub. You should see only the edited lines changed (a few insertions and
  deletions), not every line of the file, and `git diff` shows no `^M`. Repeat on a session whose
  lines end CRLF: it stays CRLF.
  CONFIRMED on Windows: an LF session saved through the agent changed only its edited lines and gained no CR.
- [ ] **A git refusal reads the same under Windows PowerShell 5.1.** In `powershell` (5.1), with the module imported
  and `$ErrorActionPreference = 'Stop'` set in the shell, stand OUTSIDE any git repository (`cd $env:TEMP`) and run
  `tkThreadHash <id>` for a card in `current/`, then `tkStatus`. You should see ThreadHash's own sentence
  (`Error: Not in a git repository` and its `Hint:`) with `$LASTEXITCODE` of 2, and Status's table with exit 0 --
  never a `NativeCommandError` naming `git`, and never the generic `Error: exit code` block. Then
  `tkTestToolkit -Portability -GitRoot -ThreadHash -Update` on that host: green, and the Portability summary names no
  `D3J7 follow-up`. Closes the git sweep merged as PR #78.
- [ ] **The joined standup reads the same under Windows PowerShell 5.1.** In `powershell` (5.1) run
  `tkTestToolkit -Rituals -Billable -Consts`: green, with every `joined-*` row passing -- the
  together case's `standup-joined-together.txt`, `.work.txt` and `.brief.txt` byte for byte, and the
  typed GitHub Space with scratch cards printing a `Widgets` tile and a `Check` line. Then, with
  `features.solitaireAgile` on in a GitHub Space answered `agents` whose hub folder holds a card of
  its own in `current/`, `tkStandup`: that card under the Space's tile, and a card marked
  `tkBillable <id> -No` gone from it. Closes Feature V2C7 (the standup reads both records).
- [ ] **What moved, and the window, read the same under Windows PowerShell 5.1.** In `powershell` (5.1) run
  `tkTestToolkit -Rituals -Consts`: green, with `joined-counts`, `joined-not-billable-counts` and
  `joined-window-three-days` passing -- their motions, counts and goldens byte for byte -- and the typed
  `Standup -Since` rows (a day forty days back saying the issue closed a month ago, a day after today and
  `-Since yesterday` each exit 2 with one `Error:` block). Then, in a GitHub Space answered `agents` with a
  card in `current/` that has commit bullets, `tkStandup`: its line reads `(<n> commits)` or
  `(started, ...)`, and `tkStandup -Brief` opens on `Since <day>: ...`. Closes Feature RC6D (the standup says
  what moved).
- [ ] **The cold-agent walk: the hand-off block starts the work without a question.** With
  `features.solitaireAgile` on in a GitHub Space answered `agents`, run `tkStartWork <id>` for a real card in
  `current/`, and once for an open issue no card carries; paste each output, whole, into a fresh editor chat
  with no other briefing. You should see the agent start the work -- read the card, take its branch, begin the
  change -- without asking which prompt to follow or what the context is. Then, on Windows, `tkStartWork <id> | clip`
  pastes exactly the block (nothing before the `# Start work:` line, nothing after the prompt), and under Windows
  PowerShell 5.1 `tkTestToolkit -StartWork` is green with its CRLF row passing; on the Team Agile page, a list
  row's **Start work** shows the same block and **Copy** copies it. Walked on macOS against two Feature cards in
  the Toolkit Space: the block assembled whole (section one the `agents` sentence, the card with its footer, the
  `pr-ship` prompt) and read as self-sufficient; two things to watch on the second walk -- the card's path is
  relative to the hub, so an agent that has to write into the card finds the hub through `tkEnv`, and `pr-ship`
  opens at "when the code is ready", which an agent handed an unstarted card should read as where the work ends,
  not as a reason to ask. Closes Feature J2GV (AR-1, the hand-off block).

## Recording a run

Date it, name the machine, and note anything that needed a workaround. A gate passed on a
different machine six weeks ago is not evidence about this one.

## Gate 12b -- The Docker production path

The production path: the built web UI served by nginx in a container, in front of an agent on the
host. It is a numbered gate rather than a conditional line because what a reader trusts should have
been observed by somebody, and it is the transcript Gate 12's Docker row compares against.

```bash
cd web && npm run build                 # dist/client is the real output path
# agent up on 4100 on the host
cd web && docker compose up -d --build
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:5174/          # 200, the built index.html
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:5174/system    # 200 -- the SPA, not an nginx 404
diff <(curl -s localhost:5174/api/env) <(curl -s localhost:4100/api/env)  # same payload
docker compose ps                                                        # healthy within ~10s
```

- [ ] The image builds and the container serves the hashed asset the build emitted
- [ ] A deep link returns the app, not a 404 -- `try_files ... /index.html` works
- [ ] `/api/env` through the container equals `/api/env` straight to 4100 --
      `host.docker.internal:host-gateway` reaches an agent on the host
- [ ] **The rebuild claim, demonstrated not inferred.** Change a source file, reload: nothing.
      `docker compose up -d --build`, reload: the change
- [ ] `docker compose ps` reads **healthy**. The health check asks for `127.0.0.1`, not
      `localhost`: this image resolves `localhost` to `::1` as well, and `nginx.conf` binds IPv4
      only. `unhealthy` here means something other than that
- [ ] Separately, the agent's own static path: `npm run build`, restart the agent (the directory is
      checked at import), load `/` on 4100. `/api/env` and `/api/status` still answer JSON, so the
      `/{path:path}` fallback does not shadow a registered route. An **unmatched** `/api/` path
      (`curl -i localhost:4100/api/nope`) is a JSON 404 naming the path, not the SPA with 200
- [ ] A non-default `web.agentPort` reaches the container: `tkWeb` exports it as `P20_AGENT_PORT`,
      the image's entrypoint writes it into `nginx.conf.template`, and `/api/env` answers through
      `localhost:5174`

---

| Gate | Machine | Date | Result |
| --- | --- | --- | --- |
| | | | |
