# Testing

How the product is tested: the four runners, what each suite guards, the counts a green run prints on
this commit, and why a claim about this checkout needs a shell with exactly one toolkit in it. Read it
before running the suites on a new machine, after changing anything, or when a count in a document
disagrees with a run. [`VERIFY.md`](../VERIFY.md) is the manual runbook for what no suite can assert.

**One line runs the three halves:**

```powershell
tkTest                   # the agent, the CLI, the web UI -- one summary, one verdict
tkTest -Half agent       # one half: cli, agent or web
tkTest -Fast             # the CLI runner's -Fast; the agent and the web run in full
```

`tkTest` runs `pytest` (through the Python that has it, below), the CLI runner and `npm test`, in that order, each in its own child with the environment its runner
sets for itself ("The runners own their environment", below; `npm test` sets none, so its child alone gets
the webhooks removed and the run marker set). Then one summary -- per half the passed, failed and skipped
counts and its time -- and one verdict. A half that cannot run is **skipped with its reason** (no Python,
no `pytest` or `httpx`, no `pwsh`, no `npm`, no `web/node_modules`) and the verdict names it **SKIPPED**,
not passed. Exit 0 when every half that ran passed; exit 2, after the summary and one `Error:` line, when
a half failed or none ran. Each half is read from the line it prints last -- pytest's closing line, jest's
`Tests:` and `Test Suites:`, the CLI runner's `Total:` -- not from the runners' internals.

**Which Python runs pytest.** The first of these that imports both `pytest` and `httpx`: a `.venv` in the
package, then `~/.venv-toolkit` (create it with `python3 -m venv ~/.venv-toolkit` and install
`agent/requirements-dev.txt` into it, for a machine whose system Python should stay clean), then the
PATH's Python, which `Scripts/Resolve-Python.ps1` chooses (so never the Store's `python3` stub). The
half's line in the summary ends `[via ~/.venv-toolkit/bin/python]` or `[via python3 (PATH)]`, so a
count always says which interpreter produced it. With none that has both, the half is skipped with
the reason, and the paste block's `pytest:` line says `NOT AVAILABLE`, which `tkTestToolkit
-DocCounts` refuses like any line that is not a count.

It also prints **expected vs actual** per half, the expected side read from this page's own lines below
(the `tkTestToolkit` line, the `pytest` line, the `npm test` line). That is information, never the verdict:
those counts are pasted by the person who merges, from the full run on the host that built the change, so a branch, a partial run or
Windows reads differently on purpose, and a difference is one `Note:` line.

`test-summary.<machine>.json` covers the three halves: every suite entry carries a `half` (`cli`,
`agent`, `web` -- consts.json `tests.halves`; an entry with none is the CLI's), the agent and the web
UI are one entry each (`pytest`, `jest`), and a `halves` block holds one record per half, a skip with its
reason. The CLI runner writes its own entries the way it always has; a half `tkTest` did not run keeps
what it had. The System page's Health card draws the machine's halves from it, and `tkSetup` prints one
line of it. `tkTestToolkit -TestAll` (the halves stubbed), `Tests/test_test_summary.py` and
`web/src/modules/ado/testHalves.test.ts` hold it.

A suite that exits 0 and prints no tests (`Results: 0/0 passed`) ends **WARN**: neither a pass nor a
failure, and it does not fail the run. It is recorded under its own word -- `warn` in the
`result` column of `test-results.<machine>.log` and in the suite's entry in the summary file -- so the one
suite that ran nothing is not the one the record leaves out. It counts as neither passed nor
failed in the CLI half's record, which says how many warned in `skipped`; the Health card shows it as a
skip, and the streak does not break on it. `Write-P20TestResult` takes `pass`, `fail` or `warn` and
refuses any other word; `tkTestToolkit -TestAll` holds the writer.

A suite whose file is not found (it is in the registry, and not on disk) is a failed suite, and the record
says so: a `fail` line in the log, `0` of `1`, with `file not found: <file>` as its detail, a `fail` entry
in the summary, one failed in the CLI half, and a non-zero exit from the runner. It has no word of its own --
a reader that knows `fail` already breaks the streak and fails the run, which is what a missing suite should do.

**Four runners**, one per half plus one that drives a browser over both -- the one-half form, for when you
want one. Every count below was
observed on this commit, on one host with pwsh 7.6, Python 3.12 and Node 24.

```powershell
tkTestToolkit            # 45 suites, 7952 assertions
tkTestToolkit -List      # enumerate suites without running any
tkTestToolkit -Autoload  # run one suite; any suite name from -List works this way
tkTestToolkit -GitRoot   # a folder inside someone else's repository is not a checkout of its own
```

```bash
python3 -m pip install -r agent/requirements-dev.txt   # once -- runtime deps plus pytest, httpx and ruff
python3 -m pytest Tests/     # 1268 passed, 3 skipped -- the agent
cd web && npm ci             # once
cd web && npx playwright install chromium   # once -- for `npm run smoke` only
cd web && npm test           # 5 build-contract checks, then 137 suites, 1577 tests -- the shell
cd web && npm run smoke              # 23 checks, flags off -- the browser; needs two servers up
cd web && npm run smoke -- --modules=on  # 30 checks, both module flags on
cd web && npm run smoke -- --studio      # the Studio's contract -- starts and stops its own servers
cd web && npm run smoke -- --matrix      # each module flag alone, the flip, fresh and hostile storage -- its own servers too
cd web && npm run smoke -- --a11y        # axe on every page, flags off and on, light and dark -- its own servers; fails on any serious or critical finding
cd web && npm run smoke -- --first-run   # the first tutorial card dragged from Backlog to To do on a copy of samples/hub -- its own servers
```

**The CLI total is per platform.** The figure above is the one from the host that built the change. Windows runs a few assertions
fewer on the same commit, every suite green on both (a Windows run, at `0381f12`, read 4372 against
4383 on the other host); a run on the other host shows which suites differ, and the per-suite table to compare
it with is a comment on the issue that made the CLI total per platform. A `config.local.json` moves the figure too -- "One more on a machine that
has a `config.local.json`", below.

**The counts, after a merge.** The paste block is the one record of a run's figures, and it is three
figures: the CLI's per-suite line and total, a `pytest:` line and a `web:` line. `tkTest` (the
all-halves runner, every half and no `-Fast`) prints all three under its summary. `tkTestToolkit`
alone -- a full run, every suite, none named, each one passing -- prints the CLI pair and says in the
other two lines' place that it did not run them. A half skipped or failed in a `tkTest` run is named in
its line's place (`pytest: NOT AVAILABLE -- ...`, `web: not run -- ...`), never a stale number to copy;
a passing `pytest:` line may end `(via <python>)`, which is information and not part of the count. The block, as
`tkTest` prints it:

```text
  Counts for docs/TESTING.md's paste block, from this run:
  Consts 188, Compat 1535, Menu 1887, Environment 62, Archive 200, PRComments 109, BackfillStamps 50, Update 58, Start 67, PullRequest 10, CloseWorkItem 36, PromptStatus 125, ThreadHash 76, Setup 82, Move 36, Billable 36, Plan 33, Cover 106, Design 135, NewPrompt 90, ExitCodes 118, Autoload 86, GitRoot 17, Sync 19, Connect 62, NewSpace 149, EditItem 69, PublishPR 31, Config 235, HubJson 184, Portability 89, Web 165, Agent 129, TestAll 155, ModuleCommands 74, Reminders 71, Rituals 637, StandupRemind 85, Triage 121, StartWork 70, Review 69, SendTeams 43, NewMeeting 63, MeetingAgenda 175, DocCounts 115
  45 suites, 7952 assertions
  pytest: 1268 passed, 3 skipped
  web: 137 suites, 1577 tests
```

**Which lines the paste owns.** The per-suite line is the `tkTestToolkit` row's list in the table below; the
total is the `tkTestToolkit` line in the command block above, and the one AGENTS.md ("Four test runners"),
this page and `VERIFY.md` print; the `pytest:` line is the totals after `python3 -m pytest Tests/` in the
command block; the `web:` line is the totals after `cd web && npm test`. Paste all three; never type any
of them. `-Fast`, `-Slow`, `-Failed` or a named suite prints no paste, because a partial run cannot know the
others, and a full run with a suite that did not pass names it and prints no counts. `tkTestToolkit -DocCounts`
holds every one of those places to the paste block, from this page's text alone (no run, no
machine-local file, so it holds in CI): the row's list equal to the per-suite line, and the three totals
equal to their paste lines. A stale place fails naming the line and, for the row, the first suite whose
number differs; a paste line that says `not run` or `NOT AVAILABLE` is not a count and fails too, so a paste from a run that
lacked a half cannot land. `Tests/fixtures/doc-counts/` has one file per drift shape. It also holds
the shape they are pasted into: the suite count in the three documents, the combined row naming every
suite once in the runner's order, and no single suite's row carrying a count of its own; it also holds that `VERIFY.md`'s coverage table has a row for every verb in `config.default.json` and the modules' data files, and that the verb counts its opening sentence states (always-on, module, total) are those same counts. It also holds the agent row below to the tree: its "in N files" is the number of `Tests/test_*.py` files, and each plain `(N)` after a file's name is that file's `def test_` count (an entry written another way, or with no count, is not checked).

**The runners own their environment.** Every runner -- `Tests/Test-Toolkit.ps1`,
`Tests/conftest.py` -- removes every `TEAMS_WEBHOOK_*` variable for its own process tree by pattern and
puts it back afterwards, does the same for the two per-shell overrides, `P20_ACTIVE_SPACE` and `PROMPTS_ROOT` (`consts.json` `env.activeSpace` and `env.promptsRoot`) -- they beat the config files, so a shell that holds them would point every suite that copies `samples/hub` at a Space or folder that hub does not have (`Tests/Test-Toolkit.ps1` and `tkTest` through `Scripts/Hide-RunOverrides.ps1`, `Tests/conftest.py` itself; the browser smoke pins both for every server it starts); a suite that means to test an override sets it itself -- points `P20_USAGE_LOG_DIR` at a scratch folder so the run never writes into
your real usage log, points `P20_AGENT_CACHE_DIR` (`consts.json` `env.agentCacheDir`) at another so it never
fills the agent's real cache (`conftest.py` gives every test a fresh one, because a fixture's blob sha is
whatever the test says it is), and sets the run marker (`consts.json` `env.testRunMarker`, `P20_TEST_RUN`) that the
engine's one POST and `SendTeams` refuse on while it is set. `Tests/Test-Toolkit.ps1` also removes `TOOLKIT_QUIET_STARTUP` for the run (and `Test` removes it around the CLI half): the web UI's Test Health card runs `Test` through the bridge, which marks its child non-interactive with that variable, and every suite's shell would inherit it, where a stated refusal throws instead of exiting 2. Nothing to unset by hand, and a send from
another shell still works while a suite runs: the marker is an environment variable and lives only
in the runner's children. `Tests/test_runner_environment.py` and `tkTestToolkit -SendTeams` prove it; `Tests/test_run_overrides.py` and `tkTestToolkit -TestAll` prove the overrides the same way, each starting a run from a shell that holds both and asserting the suite saw neither and the shell has them back after.
`Tests/Test-Menu.ps1` does not lean on that: its scoring section points `P20_USAGE_LOG_DIR` at a scratch folder of its own and seeds the log it asserts against, so the "Most used" cases give the same answer run directly (`pwsh -NoProfile -File Tests/Test-Menu.ps1`) as through the runner, whatever this machine has typed.
**And the module does not undo it**: importing `utilities.psm1` reads the package's `.env`
into the process -- except while the run marker is set, because on a machine whose `.env` holds
webhooks that import put them straight back into every suite.

**On Windows** the Python is `python` (or `py -3`) rather than `python3`, and one more kind of skip
applies: `Tests/test_billing_script.py` runs `agent/ado/Get-WeeklyBilling.ps1` under **`pwsh`** and
skips as a whole when only Windows PowerShell 5.1 is on the PATH (`HAVE_PWSH`); the CLI suites that type
a verb in a fresh shell (`-Archive`, `-Setup`, `-Move`, `-Billable`, `-Start`) spawn `pwsh` too. A Windows machine with
PowerShell 7 installed runs everything; one without it reads short, and the summary line names the skips.

**Run as a file under Windows PowerShell 5.1** (`powershell -NoProfile -File Tests/Test-X.ps1`), with the same
result as under PowerShell 7: `Test-Design`, `Test-Rituals` and `Test-Connect`, and also `Test-ExitCodes`,
`Test-SendTeams`, `Test-Menu`, `Test-NewPrompt`, `Test-Web`, `Test-Cover`, `Test-Archive`, `Test-ThreadHash`, `Test-GenerateReview` and `Test-Agent`. `Test-ExitCodes`, `Test-SendTeams`, `Test-Menu` and `Test-NewPrompt` ran their cases in a child `pwsh` under
`$ErrorActionPreference = 'Stop'`, and 5.1 turns a native command's stderr line into a terminating error record
under `Stop`, so each now runs the child in a function-local `'Continue'` and reads its output as text; the
`-Command` text of `Test-SendTeams` travels as `-EncodedCommand` because 5.1 does not escape a double quote
inside a native argument. `Test-Web` does the same for its sandbox child and its wrapper probe, and
retries the write over a file it has just copied or a child has just read, which a scanner can hold for a moment under 5.1.
`Test-Cover`, `Test-Archive`, `Test-ThreadHash`, `Test-GenerateReview` and `Test-Sync` commit into a scratch git repository, and with `core.autocrlf` true git writes
`LF will be replaced by CRLF` to stderr on `git add`, which 5.1 under `Stop` turns into a terminating error; each
scratch repository is now created with `core.autocrlf false` in its own config, so the warning never fires.
`Test-GenerateReview` stopped under 5.1 on a different line, `fatal: not a git repository`, and that one was the script's own: `Scripts/Generate-Review.ps1` ran `git log` with `2>&1` in its caller's error preference, so a hub that is not a repository threw on 5.1 whenever the caller's preference was `Stop`. It now reads git through `Invoke-P20TrackerRead`. `Test-Sync` also clones an EMPTY bare repository for its hub, and git writes `You appear to have cloned an empty repository` to stderr, which `--quiet` does not silence; that one call runs under a function-local `Continue` and the output is read as text. The defect was the suite's: `Sync` itself never clones.
`Test-Agent`'s two pipe cases failed under 5.1 because the script was wrong, not the suite: a launcher run by
5.1 handed the child a second, inheritable copy of its own stdout that the .NET Framework keeps, so the reader never saw
EOF. `Scripts/Start-Detached.ps1` now keeps every pipe but stdin from crossing, and the cases are unchanged.

**`Test-Start` runs the same way, and its count is the same every run**. Its cases sit in one `try`, and under 5.1
the scratch package's `config.local.json` can still be held by the previous `Start`'s shell for a moment; the write that
followed used to throw, end the `try`, and drop the last cases with nothing said. The write now retries and asserts that
it landed, and a `catch` turns any other terminating error into a FAIL line, so a case cannot vanish silently.

**`Test-Config` runs the same way too, and its count is the same every run**. Its scratch packages are copied and
written to between child shells, and under 5.1 a freshly copied or just-written file (`config.default.json`,
`config.local.json`) can still be held by a scanner or a winding-down child: the next read, write or copy threw
(`being used by another process`, `Stream was not readable`) and the suite's top-level catch turned it into a FAIL. Every read, write and
copy of a scratch file now goes through one helper, `Invoke-LockRetry` (20 tries, half a second apart), which asserts: a file
held for ten seconds is a named FAIL, one held for a moment is waited for.

**A suite ends with a catch**. A CLI suite that wraps its cases in a top-level `try` -- one around all of
them, or one per group around its own scratch folder -- ends that `try` with
`catch { Assert-True 'the cases ran to the end without a terminating error' $false $_.Exception.Message }`
before its `finally`, written with the file's own helper (where `Assert-True` takes two parameters, the message
goes into the name). Without it, a terminating error -- a locked file, a helper's throw, a native command's stderr
under 5.1 and `Stop` -- ends the `try`, every case below it never runs, and where the summary prints in the
`finally` it prints a smaller `N/N` in green: a count that is short and says nothing, which is "a skip is not a
pass" failing one level down. With it, the early end is a FAIL line naming the error, and the count moves only
when it fires. A suite whose cases sit at script scope needs none: a terminating error there ends the script
before `Results:` prints, which is visible. The same goes for every `Assert-*` a suite calls: one the file never
defines prints `CommandNotFound` and is never counted. `Test-Portability`'s Clauses 11 and 12 refuse both shapes.

**The fixtures are LF on every host.** `Tests/fixtures/**` is pinned `eol=lf` in `.gitattributes`: the
golden texts and `previous-round.md` are compared byte for byte by all three runners, and a Windows checkout
under `core.autocrlf=true` would otherwise have them CRLF on disk and turn every such comparison red. A
checkout that predates the pin keeps its CRLF copies until `Tests/fixtures` is deleted and checked out again.
A test that reads a SCRIPT's source normalises it to LF on read (`Test-PRComments.ps1`); scripts are not pinned.

**Three cases run on Windows only**, and are the three skips a run on another operating system shows: a hub reached through
its 8.3 short name (`C:\Users\RUNNER~1\...`, what `%TEMP%` and `tempfile` hand out for a user name
that does not fit 8.3) for `NewSpace`, `StampDesign` and Billing. Every other case takes its
scratch tree in its LONG form through `Tests/_shortpath.py`, so the short form is tested on purpose,
once per verb, and not by accident everywhere.

**A suite that does not report has failed**. The runner reads each child's `Results: n/m passed`
through `Get-P20SuiteVerdict` (`Tests/Get-ToolkitSuiteRegistry.ps1`): no Results line -- the suite threw
before it got there -- is ONE failure, named under the summary box as `no Results line -- the suite
threw?`, and the Total goes red; a non-zero exit is at least one failure even after an `n/n` line; a
stated skip prints `Results: 0/0 passed` and exits 0, and reads as a warning.

**Running less.** `tkTestToolkit -Fast` runs the suites that spawn no shell (Consts, Compat, Menu,
Environment, PRComments, PullRequest, CloseWorkItem, PromptStatus, HubJson, Portability, Review,
BackfillStamps, Sync, DocCounts) -- a few minutes, the set to run after a pull; `-Slow` is the rest, one host
process per case, which is where the time goes on Windows; `-Failed` reruns whatever failed in the last
run on this machine, read from `test-summary.<machine>.json`, which also carries each suite's seconds.
The runner prints each suite's time as it finishes. On Windows, real-time scanning of `%TEMP%` and
the package folder is a large part of the cost of the slow set; excluding them is your call to make
knowingly.

| Runner | What it guards |
| --- | --- |
| `tkTestToolkit` | The CLI, per suite: Consts 188, Compat 1535, Menu 1887, Environment 62, Archive 200, PRComments 109, BackfillStamps 50, Update 58, Start 67, PullRequest 10, CloseWorkItem 36, PromptStatus 125, ThreadHash 76, Setup 82, Move 36, Billable 36, Plan 33, Cover 106, Design 135, NewPrompt 90, ExitCodes 118, Autoload 86, GitRoot 17, Sync 19, Connect 62, NewSpace 149, EditItem 69, PublishPR 31, Config 235, HubJson 184, Portability 89, Web 165, Agent 129, TestAll 155, ModuleCommands 74, Reminders 71, Rituals 637, StandupRemind 85, Triage 121, StartWork 70, Review 69, SendTeams 43, NewMeeting 63, MeetingAgenda 175, DocCounts 115. This row is the one place a CLI suite's count is written, and a full run prints it ready to paste ("The counts, after a merge", above). What each suite guards is `tkTestToolkit -List`, and the module suites' rows below |
| `tkTestToolkit -Reminders` | The Organize add-on (its count is in the row above): the bucket and snooze rules over `Tests/fixtures/reminders/buckets.json` (shared with `Tests/test_reminders.py`), what `-Due` accepts, off means no verb, both verbs typed in a fresh shell -- create, snooze, edit (each switch its own line, the same values writing nothing), archive -- fifteen stated refusals with a refused edit writing nothing, and the bytes |
| `python3 -m pytest Tests/` | The agent (the total is in the command block above; on Windows `python` or `py -3`), in 66 files: `test_run_overrides.py` -- a shell's `P20_ACTIVE_SPACE` and `PROMPTS_ROOT` do not reach a test, proved by a child pytest started with both set; `test_first_run.py` (3) -- the first run's board as `GET /api/status` and `/api/env` serve it from an untouched copy of `samples/hub` with the shipped config: the first tutorial card Backlog, the other four Active, no other card Active so the lane can empty, and Demo's Active called To do while Backlog keeps its name; `test_visibility.py` (18) -- a Space's repository visibility: gh's word as the contract's, a Space of several repositories, the route per Space with `gh` stubbed (public, private, unknown when unanswered, not asked below Tier 1 or on ADO or with no tracker, an undeclared slug 404, read once per repository and an unanswered read asked again, and `?refresh=1` asking again past the cache for that Space's repositories only and past the tier probe, and asking nothing where there is no visibility); `test_new_space.py` (35) -- `NewSpace` typed in a fresh pwsh against a scratch package and hub with `gh` a stand-in or off the PATH (each form, each refusal writing nothing, adoption, `-WhatIf`, `-Discover`, `-Discover -Owner` with the owners, an organisation's and the shared-with-you lists, read-only marked, no `&` in a `gh` argument and an unseen owner refused, the proposals over `Tests/fixtures/spaces/proposals.json`, and -- on Windows only, skipped elsewhere by name -- a hub reached through its 8.3 short name), and `GET /api/spaces/candidates` with the bridge stubbed, the verb's own answer included, and absent; `test_surfaces.py` (4) -- see its row below; `test_ledger.py` (37) -- the Studio's Spaces card's one read of every GitHub Space, see its row below; `test_design.py` (38) -- the Design tab through a stubbed `gh` that answers the GraphQL shape and blob queries and the contents call: the listing (design/ before spec/, title, frontmatter description, the `> GitHub:` thread, a missing folder as an empty list, the structure flags, gh not answering as a reason), how often gh is asked (a cold listing one call with the query in a file, a warm one the shape alone, one changed note one more ask, new texts a hundred to an ask, the same count for 3, 60 and 190 notes, an unchanged sha never fetched again by a new process, a blob with no inline text read by the contents call alone), the detail served from the disk while the listing is fresh and a changed note opening with its new text, the cache folder per platform and its override, the front-matter parser and the state rule over their shared tables, the grouping by id in road order (a conflict shown as none, an id outside the contract's shape read as none, a note archived before its spec still a Spec), the search inside the designs, and the routes (the gate -- GitHub and Tier 1 only, an owner-grained address a 400 -- a bad path never reaching gh, an archived document by its path, and the cards that name a design); `test_readme_routes.py` (2) -- `agent/README.md`'s route tables and the app's own route list name the same routes, a missing row and a row for a route that is gone each failing by name; `test_repo_read.py` (10) -- the shared folder reader's own options: the query for `depth` (depth 1 is the query it always was, deeper nests `entries`, a blob's text asked for only when told to), a nested answer as paths in one call, a depth per folder and the repository root, an absent folder, the issues switch riding the same call, nested texts parsed from the one call, `parse=None` asking for no text and writing nothing to the disk cache, no `&` and the query in a file; `test_cache_prune.py` (18) -- the agent's disk cache is capped by one rule: records past 3000 or unseen for 30 days pruned on write, oldest-unseen first, over the rows file's `seen` stamps and the dress folder's modification times (a touched file survives, a write in flight is not a record), the opened bodies the same way, a hit rewriting the file only once its stamp is a day old, and a prune that errors leaving the cache as it was; `test_docs.py` -- the Docs tab's three routes through a stubbed `gh` (the listing one GraphQL call that nests, the document and image reads the contents route): the path rule over the shared table `Tests/fixtures/docs/paths.json` that `docRooms.test.ts` reads too (README.md or `.md` under `docs/`, never a `..`), the gate (an ADO Space, no tracker and Tier 2 answer `supported: false` and ask `gh` nothing), the README and the `docs/` tree sorted by path in one gh call however it nests (flat, 16 folders and four levels all the same, a fifth level not listed), the same rows as the contents walk made, nothing but the one shape call asked again after the in-memory cache is cleared, the cache, a refused path never reaching gh, and an image decoded to its bytes with its content type -- under `docs/` or anywhere else in the repository, never through a `..` -- one past the 1 MB the contents route inlines read from its blob by sha, a 413 past the 10 MB ceiling with no blob asked, the repository's `issues` address (empty with issues turned off, asked again when gh did not answer, read from the one repository record the visibility cache holds -- a cold document read with the record warm, from the ledger or the listing, makes no `repos/<repo>` call, and with it cold asks once and holds it for the visibility read too), and no `&` in any `gh` argument; `test_backlog_github.py` (12) -- the GitHub Issues list and report through a stubbed `gh`, including the Issues tab's state axis (`?state=open\|closed\|all`, anything else read as open), closed rows sorting after open ones, and the worker read from a label's `Routed to` description; `test_milestones.py` (10) -- the Milestones card's read through a stubbed `gh api .../milestones?state=all`: the reached rule as a table (0 of 0, 0 of n, n of n open, n of n closed, mixed), the fields, gh not answering as a reason, and the gate (GitHub and Tier 1 only, gh never asked elsewhere); `test_switch_space.py` (2) -- `POST /api/switch-mode` walked a → b → a: `/env` says the new Space at once, an unknown slug is refused and writes nothing, and `config.local.json` comes out saying `activeSpace` alone, the old `activeOrg` dropped; `test_clock.py` (6) -- a day from git is the reader's LOCAL day: one instant read on seven clocks from the shared table `Tests/fixtures/clock/local-days.json` that `Test-BackfillStamps.ps1` reads too, and no agent code asks git for a zoned date; `test_growth_status.py` (3 tables, 20 cases) -- what a growth file says about itself is what the page says: both generations of the Outcome heading, Delivered yes / no / absent, and every status word; `test_env_org_state.py` (9) -- the Environment card's ADO row tells "never asked" from "tried and failed", so an archived or a local org cannot fail it; `test_offered_orgs.py` (4) -- which orgs a person is offered to pick from once the Example org is dismissed, over the ONE table `Tests/Test-Config.ps1` reads too; `test_ado_enabled.py` (6) -- whether Azure DevOps is part of what is shown, over the ONE table `Tests/Test-Setup.ps1` reads too (status, tracker and flag: a connected GitHub Space is off), and what `/env` serves for it; `test_parsers.py` (54, including `assigned` -- a card's **Assigned:** line over `Tests/fixtures/parsers/assigned-lines.json` -- the folder states (`backlog/`, `archive/`) read FIRST over `Tests/fixtures/parsers/states.json` -- and `commits` -- git's bullets counted, never a `**Started:**` line -- with the two person-written tokens' fixtures asserted from the CLI suite too, with the card-id table `card-ids.json` that `Test-Archive.ps1` reads too) over the shared fixtures in `Tests/fixtures/parsers/`; `test_billing_script.py` (30) -- including a planned card in `backlog/` never billed -- `agent/ado/Get-WeeklyBilling.ps1` run for real, under pwsh: against a scratch git hub it bills the folder the caller names and refuses without one (a dot, a folder two levels down, a subfolder of a repository, a short Windows path), reads the review day from git or from a person's `**Review:**` line, treats a mechanical commit as no work, bills a commit rebased past the week on its own day and not one authored after it, and says "no activity" as JSON rather than prose; and on a hub with no git at all Daily is built from the cards' own dates -- `**Billable:** no` takes a card off and is counted, a file that is not a card is never billed, a card with no date is counted and not guessed, a hub-wide folder move bills nobody on a day they were not open; `test_card_model.py` (20) -- including `billable`, `assigned`, `commits` and `tracker`, a card in `backlog/` served as Backlog and listed after the cards in play (each card names its own tracker from its own link), `/env`'s `firstRunWelcome`, true unless the card says otherwise, that a week which could not be built says so in `error` while an empty week does not, and that `GET /billing?week=last` asked twice around a change gives two answers, because a week is not cached in memory; the Card model end to end through `GET /api/status`: id from the filename, type from the heading against the CONFIGURED types including one added in `config.local.json`, and a card with no work item deriving its state like any other; `test_status.py` (8) -- `GET /api/status`'s reads: a card's `modified` day over the shared table `Tests/fixtures/status-modified/history.json` that `Test-Status.ps1` reads too (a renamed card, a card moved from `backlog/`, one changed since its last commit, one never committed, a name outside ASCII, a hub that is not a repository), ONE git call for every card in `current/` and `backlog/` (forty cards, one call), the shared reader `core/git_history.py`'s keys and its answer outside a clone, and the card page's design listings read once per request and not at all for a line with no id; `test_tier_parity.py` (2), which runs `Scripts/Resolve-TierDecision.ps1` and `agent/core/tier.py` against the spec formula over every input combination; `test_config.py` (32) -- the hub comes from config, not from layout, the Python merge behaves as `Merge-SpacePatch` does, and a local `orgs` written as an array warns instead of being ignored; `test_bridge.py` (37) -- the allowlist is the live command table, a name outside it is refused, a parameter with spaces is not, `Env` is run for real so a broken PowerShell half cannot pass, `StartWork` is run for real (in the table with Team Agile on and rejected off, the `Tests/fixtures/start-work/` block byte for byte, a refusal's sentence), and `NewPR -WhatIf` is run for real from a Toolkit checkout on a branch of its own, to prove it reads the card and never that checkout; `test_bridge_refusals.py` (11) -- a verb that refuses is `status: error` with its stated sentence, never `success`, run end to end for the same reason; `test_features.py` (7), which pins the flag-scope rule; `test_health.py` (2) -- `/health` names the checkout the agent runs from (`package_root`), which is how `tkAgent -Stop` and `-Reuse` tell their own agent from another package's; `test_model.py` (10) -- the provider profile: `ai.model` from config with the shipped default and the literal agreeing, a missing key or a missing SDK as a stated reason before any network call, the one SDK call carrying the model, the system prompt and the effort, and no route module owning a transport of its own; `test_env_probe.py` (10) -- `/env` neither holds the event loop nor re-probes `az` on every call, and its `startWorkLaunch` follows `claude` on the PATH; `test_tier_probe_merge.py` (15) -- the tier probe is keyed by the GitHub owner (an Azure DevOps address by its URL), concurrent misses share one probe (ten Spaces under one owner, one probe; two owners, two), a probe that raised reaches everyone who shared it and is not cached, and the TTL and `probe_cache_clear()` still forget; `test_log_override.py` (5) -- a test run writes to a scratch log, not to the engineer's; `test_hub_json.py` (55) -- the hub declares its own orgs, its folder names and its `storeSync`, in the order the CLI resolves them and with the same warnings, plus the cross-loader parity case over `Tests/fixtures/hub-parity`, and a renamed shipped Space's old slug over the table `Tests/fixtures/space-renamed/table.json` that `Test-HubJson.ps1` reads too; `test_consts.py` (21) -- `consts.json` parses, every key resolves to the value all three halves agreed, and no runtime Python retypes one; `test_identity.py` (23) -- who "me" is, resolved the way the CLI resolves it, with `az` stubbed throughout; `test_config_routes.py` (20) -- the three config routes build the argv the bridge's contract needs, answer refusals as typed bodies, clear the two TTL caches only on a successful write, and are checked against the real verb in a scratch package; and the four the modules brought, below |
| `cd web && npm test` | The shell -- preceded by `tests/viteconfig.mjs`, **5 checks** on what `vite.config.ts` asks for (a build declares no `/api` proxy and so never resolves `web.agentPort`; serving resolves one and prefers `P20_AGENT_PORT`; the dev port stays the literal `Start-Web.ps1` and `Show-ConfigHelp.ps1` find by regex). It is not a jest suite because it is not about the bundle: it loads the config the way Vite does, for both commands, and it exists because resolving the port unconditionally stopped the production image building at all. Then the jest suites (their count is in the command block above) -- among them the deck engine's own, carried with it (`DeckPlayer`, `PresenterNotes`, `useVoiceControls`, `voiceCoverage`), and `DeckPlayer.audiobook.test.tsx` (7), this repo's own: an `audiobook` deck opens in Suitcase at desktop width with prev and next beside the transport, the browser's voice reads a slide with no clip (or the slide lives its read time silently with no speech API), pause holds it, and a deck without the hint keeps the desktop rule and never reaches `speechSynthesis`: `NewSpaceDialog.test.tsx` (12) the Spaces card's + and its dialog -- the picker with Public/Private, an Archived chip sorted last and the Spaces disabled, search, the proposal shown and editable, the typed `owner/name` when `gh` or the agent cannot list, own cards, a refusal in the verb's words, success adding the row without a reload; `newSpace.test.ts` the dialog's mirror of the verb's proposals over the same shared table; `SpaceLifecycleDialog.test.tsx` a Space's Retire and Remove from its row -- the house confirm showing the verb's `-WhatIf` before Submit can be pressed, a Remove run with `-Force` and a Retire with the slug alone, a refused preview keeping Submit shut while Cancel works, a refused run kept in the dialog; the row menu's two entries are in `FoyerCard.test.tsx` and their rule (`spaceLifecycleActions`) a table in `foyer.test.ts` and `scenarios.test.tsx`; `registry.test.tsx` (13) is the registry contract, including settings sections, named slots, chromeless paths, which switched-off module owns a path, and the avatar menu's destinations; `AvatarMenu.test.tsx` (8) the avatar menu's Space entry -- today's submenu at `SPACE_QUICK_MENU_THRESHOLD`, past it the quick menu: the box focused, the active Space first and checked, typing narrows by name or slug and Enter switches through the same call, the arrows, View all only when the short list leaves some out, the empty-result sentence, Escape back to the Space entry; `themeList.test.ts` (6) the named themes -- both kinds in both modes, a flat theme opaque all the way down, white on every primary button at AA, a brand tint badge's text on its background at AA, the legacy `dark`/`light` values, and the WHOLE accent following the theme; `configLabels.test.ts` (6) the settings drawer's words -- the two first-run switches named for hiding, the banner's drawn inverted -- -- a named key, an org's field whatever the org is called, and the fallback that keeps an unnamed key usable; `prepareMarkdown.test.ts` (17) what a card's text needs before it is rendered -- comments, front matter and field lines, with fences and wrapped prose left alone, plus the contents list's headings -- h2 and h3 with a level, an orphan h3 at the top, repeated words given distinct ids, the section a part belongs to -- and the doubled-title rule; `consts.test.ts` (17) the contract file -- it parses, this half reads it, `toRegExp` turns a portable pattern into a JS one, and no `.ts`/`.tsx` under `src/` retypes a guarded literal; `envBadge.test.ts` (5) the Environment card's headline -- Archive and Local are not warnings (Local is green), only an active org that tried and failed is, and it says Offline; `homeView.test.ts` (4) one view at a time, and the board alone for an org with no Azure DevOps; `legalMoves.test.ts` (5) a person may move a card to every lane ahead of it and none behind, and each lane says who puts a card there; `cardActions.test.ts` (23) the one action model the list and the board both render, as a TABLE -- an ADO card and a card with no work item at Active / In Progress / Code Review / Done, each with Azure DevOps on and off, one row each asserting every action present, which are disabled and why: Open in ADO and Create PR ABSENT on a card with no work item or with ADO off, Create PR DISABLED with no commit recorded (naming `{prefix}ThreadHash`) or with a PR already open; `laneNames.test.ts` (3) the org's own words for its lanes, keyed by the contract's; `promptFilters.test.ts` (9) the predicates the list and the board share -- text as an exact id, a substring or the words in any order, type with an Untyped bucket inside All, the type row counted from the cards -- including the unlinked cards a repo filter hides; `logChart.test.ts` (4) the Log card's chart days oldest-left whatever order the agent serves them, and a badge that says `latest 500` only when the answer was cut at the cap; `billingNote.test.ts` (5) and `useBillableToggle.test.ts` (2) -- what Daily Activity says it was built from and left off, and the words of the billable toggle; `cliBridge.test.ts` (31) the CLI parameter contract, `Billable`'s argv included and `Route`'s (the number positional, one switch per answer, a milestone title one element) (a filename, and `-No` or nothing -- there is no `-Yes`), `MeetingAgenda`'s (`-Date`, `-Type` only for a series that is not the 1:1, one switch), including the config card's payload builder; `usePagination` (3) and `usePersistedState` (13) the two shared hooks; `filtersSlice.test.tsx` (7) a Space switch opens with the drawer clear -- the six values back at their defaults on a successful `switchMode`, an unrelated or rejected action leaving them, and the Docs and Design filters cleared while the Spaces card's stays (`clearPersisted`); `dates.test.ts` (26) the one clock -- every day helper pinned at 23:30 Pacific, where the UTC date is already tomorrow, `timeAgo`'s words, and a walk of `src/` that fails if any file slices or splits a `toISOString()` down to a day; `thinScrollbar.test.ts` (3) the one themed scrollbar -- the webkit bar and the standard pair from the same token, and no other file under `src/` styling a scrollbar; `StatTile.test.tsx` (3) and `IssueReportCard.test.tsx` (1) the one way a card counts -- the number beside its caption in the boxed tile, a colour only when the card passes one, a Tooltip able to wrap it, and the Issue Report's three counts in it; `ConfirmDialog.test.tsx` (4), `CardActions.test.tsx` (3) and `RetireGoal.test.tsx` (3) the one grammar for dialogs and row actions -- the house confirm, busy and a refusal in place, a lone secondary action in the menu with the external link last, and Retire asking through it; `DesignList.test.tsx` (28) the Design tab's list and reading room -- and, since L2b, search inside on the button with its hits, reasons and note, and the Archived group's outcome chips -- one list grouped by state in road order with Complete and Archived collapsed to a count (design lifecycle L2), a row the design with its state, id and thread, the not-shown line and the empty state that teaches, the thread after the document in one viewer and only from the Space's own repo (Studio S2), an archived document by its path; `DocsLanding.test.tsx` the Docs tab landing on the README with the `docs/` tree folded beside it, Open on GitHub last, and one document's room handed its repo path and the anchor its address carried; `docLinks.test.ts` and `DocLink.test.tsx` the three link kinds -- a room (anchor kept), an anchor that scrolls, out in a new tab with the hover sentence for a repo file the room does not read -- and the image rule; `docRooms.test.ts` the docs path rule over the shared table the agent reads too, one resolver for both rooms, every repo image through the agent and an issue of the repository opening its room; `markdownPlugins.test.tsx` also holds a `#N` mention to a link in prose and to text in code, in a link and with no issues known; `MyWork.test.tsx`'s chip groups (11) the Issues tab's three axes -- state and assignee asked of the agent, worked by over the list, each remembered per browser, closed rows wearing their state; `ActionDialog.titles.test.tsx` (4) and the Backlog rows of `MyWork.test.tsx` the string pass -- each dialog door's title and each Backlog state naming its tracker and its thing, with no ADO word on gh soil; `homeBanner.test.tsx` (3) the first-run banner is in Home's slot only while `/env` says `firstRunWelcome` -- never before `/env` answers; `landing.test.tsx` the landing page's words are the README's -- the logo, the tagline, the sentence, the three ways, the five quick-start lines, the footer's documents as files that exist and the notices' narration sentence, each found as written, a README missing a piece refused by name, and the page drawing exactly those with band 3 absent while it is held; and the three the modules brought, below; the dev port stays the literal `Start-Web.ps1` and `Show-ConfigHelp.ps1` find by regex). It is not a jest suite because it is not about the bundle: it loads the config the way Vite does, for both commands, and it exists because resolving the port unconditionally stopped the production image building at all. Then the jest suites (their count is in the command block above) -- among them the deck engine's own, carried with it (`DeckPlayer`, `PresenterNotes`, `useVoiceControls`, `voiceCoverage`), and `DeckPlayer.audiobook.test.tsx` (7), this repo's own: an `audiobook` deck opens in Suitcase at desktop width with prev and next beside the transport, the browser's voice reads a slide with no clip (or the slide lives its read time silently with no speech API), pause holds it, and a deck without the hint keeps the desktop rule and never reaches `speechSynthesis`: `NewSpaceDialog.test.tsx` (12) the Spaces card's + and its dialog -- the picker with Public/Private, an Archived chip sorted last and the Spaces disabled, the Owner selector, a Read-only chip and the **Add owner/name** row, search, the proposal shown and editable, the typed `owner/name` when `gh` or the agent cannot list, own cards, a refusal in the verb's words, success adding the row without a reload |
| `cd web && npm run smoke` | The two halves together, in a real browser. **Two modes**: 23 checks with every flag off (the default) and 30 with `--modules=on` (the three Home-tab checks run in both) -- see below. And a third that brings its own servers, **`--studio`** (`npm run smoke:studio`): a leftover `features.studio: false` leaves the Studio tab and its Spaces card in place; a module flag set true then false through `PUT /api/config` under the running agent shows its nav entry on a reload and drops it on the next; and the Spaces card on `Tests/fixtures/hub-spaces` -- each tag's count and the chip's total, each filter's rows, the tags and the header holding their boxes as the filter changes, the choice kept after a reload, a fresh browser context opening on All. And a fourth on the same footing, **`--matrix`** (`npm run smoke:matrix`, Chromium only): one pass per module flag -- growth, communication, organize, deck, lounge, solitaireAgile -- each alone on, asserting its nav entry (the row of `docs/SCENARIOS.md`'s "The nav, by module"), its page with the fixture hub's data, its data and source requested, and every other module's nav entry, data and source absent; the flip again, on the Lounge; and each persisted choice -- the Spaces filter, the Reminders filter, the theme, the Lounge's tic-tac-toe, the standup player's mute -- in a new context (its default, then a choice kept across a reload) and in one whose `localStorage` and `sessionStorage` throw (drawn, no page error, still answering a choice). And a fifth, **`--a11y`** (`npm run smoke:a11y`): axe on every page the registry mounts, flags off and on, in `seaglass` and `aurora`, the findings listed by impact -- a gate that fails on any serious or critical one, see below. And a sixth that needs no servers at all, **`smoke:landing`** (`npm run smoke:landing`): it builds the landing page, serves it locally and follows every link (a same-origin one must answer 200; the repository link and each file link into it are held against the tree rather than the network), then checks the banner at 390 px (no horizontal scroll, the words stack, the figures drop below) and at 1280x640 (the first screen holds the whole banner). And a seventh, **`--first-run`** (`npm run smoke:first-run`): on a copy of `samples/hub`, Demo's board with the first tutorial card alone in Backlog and four in To do, the card dragged to To do and the moved file read back from `demo/current/` |

**The subtest count needs a recent pytest.** `N subtests passed` is printed by pytest 8.4+ and 9.x,
which report `unittest` subtests natively; an older pytest runs the same assertions and prints only
`N passed`, with no mention of them. Both are the same run. If the second line is missing, check
`pytest --version` rather than looking for a plugin -- nothing in `agent/requirements-dev.txt`
supplies it.

**A missing Python dependency skips one file, not the run.** `pytest` imports every test module
during collection, so a module-level `sys.exit()` or an unguarded `ImportError` ends the whole
session with **zero tests** rather than skipping the one file that could not import. The ten files
that reach `fastapi.testclient` therefore route their imports through `Tests/_skipguard.py`, which
raises a real module-level skip under pytest and keeps the `python3 Tests/test_x.py` direct-run path
printing `SKIP:` and exiting 0. Without `httpx` installed those files skip and the rest still runs;
with it, the full run. **That is an acceptable run,
not a broken one**: a machine that only wants the CLI does not need the Python test dependencies,
and the skips are named in the summary so nobody mistakes the short run for the full one. `tkTestToolkit -Agent` asserts the shape statically, so it holds on a machine
with no Python at all.

## In CI

Four workflows. `release.yml` runs on a tag push alone: it reads the tag's section out of
`CHANGELOG.md` and publishes the GitHub Release with it, refusing a tag with no section, with the
default token and the one permission a release needs. `pages.yml` deploys the landing page.
`codeql.yml` runs CodeQL's default queries over the web (JavaScript and TypeScript) and the agent (Python) on every push to `main`, on every pull request and weekly, with `contents: read` and `security-events: write`; PowerShell is not a CodeQL language, and the CLI half's scanner is the PSScriptAnalyzer lint that `docs/CONTRIBUTING.md` ("Lint") names.
`.github/workflows/verify.yml` has two jobs, an Ubuntu one and a Windows one, and they run on different triggers. **The Ubuntu job** runs on every pull request, on every push to `main` and from the Actions tab's button; it is the check a pull request has to pass to merge. **The Windows job** is slower and runs on a schedule (once each weekday evening, against `main`), from the same button, and on a pull request that carries the `ci` label, for a change heavy on PowerShell that wants the proof before it merges. The label takes effect on the pull request's next push (or reopen); to run Windows on a branch right away, use the button on that branch (`gh workflow run verify.yml --ref <branch>`). A label added to an open pull request starts nothing by itself, on purpose: a label must never cancel the running checks. An ordinary pull request and a push to `main` do not run it. A scheduled failure is filed as an issue with the run's URL and is not re-run; the next morning's first merge carries the fix.

**On `ubuntu-latest`, the three halves**, in one job: the checkout; Node from `.nvmrc` with npm's cache and `npm ci` in `web/`; Python 3.12 with
pip's cache and `python -m pip install -r agent/requirements-dev.txt`; the runner's own `pwsh`. Then three
steps, in `tkTest`'s order, then the Python lint, the documentation and the dependencies:

| Step | Runs | Read from |
| --- | --- | --- |
| The agent | `python -m pytest Tests/` | pytest's closing line |
| The CLI | `tkTest -Half cli`, in a shell with exactly one toolkit in it ("One toolkit per shell", below) | the CLI runner's `Total:` line |
| The web UI | `npm test` in `web/` | jest's `Tests:` line |
| The Python lint (the agent and `Tests/`) | `ruff check` and `ruff format --check` from the root, with `ruff.toml` | each command's exit code |
| The documentation | `npm run lint:md` in `web/`: markdownlint-cli2 over the root `README.md` and the other root documents, `docs/`, the `design/` and `spec/` READMEs, `web/README.md` and `agent/README.md`, with `.markdownlint-cli2.jsonc` | the linter's exit code; it prints every finding |
| The dependencies (Ubuntu) | `npm audit --omit=dev --audit-level=high` in `web/`, and `pip-audit` over `agent/requirements-dev.txt` in a throwaway environment (`docs/CONTRIBUTING.md`, "Dependencies and the audit") | each audit's exit code: an advisory at high or above in what ships, or any known vulnerability in the agent's requirements, fails the run the day it is published, before Dependabot's weekly pull request |

**On `windows-latest`, what only Windows proves** (on the schedule, the button or the `ci` label, above), in one job with a timeout: the same checkout and `npm ci`,
`npx playwright install chromium`, and Python 3.12 with `python -m pip install -r agent/requirements.txt` (the
smoke starts its own agent; this job runs no pytest). Then three steps, in sequence:

| Step | Runs | Read from |
| --- | --- | --- |
| The smoke, matrix | `npm run smoke:matrix` in `web/` (`--matrix`): each module flag alone, the flip with no restart, fresh and storage-refusing browser contexts | the closing `smoke:` line |
| The smoke, a11y | `npm run smoke:a11y` in `web/` (`--a11y`): axe on every page the registry mounts, modules off and on, in two themes | the closing `smoke: a11y --` line |
| The CLI | `tkTest -Half cli` from **Windows PowerShell 5.1**: `powershell.exe -NoProfile`, `PSModulePath` set to the package inside that shell, the one manifest imported by path | the CLI runner's `Total:` line |

Both smoke modes start and stop their own agent and Vite on a scratch copy of the package (`web/tests/smokeStack.mjs`),
on free ports, so the job brings up no long-lived server. The CLI step is the import and the verb on the 5.1 floor;
the runner then starts every suite in `pwsh`, as it does on every host, so the suites themselves run under
PowerShell 7 on Windows. `PSModulePath` is set inside the 5.1 shell because a `powershell.exe` started from `pwsh`
can inherit PowerShell 7's module folders, and 5.1 then loads PowerShell 7's copies of a module.

Each step tees its runner's output to a transcript and hands it, with the runner's exit code, to
`Scripts/Test-CiHalf.ps1`. That reads the half with the parser and the verdict `tkTest` uses
(`Get-P20CiHalfVerdict` in `Scripts/TestAll-Rules.ps1`) and one rule tighter, because a check nobody
watches cannot notice a short run: **no summary line, a failure, a non-zero exit, or nothing passed**
(`Total: 0/0`, `no tests ran`, every test skipped) **fails the step**, whatever the exit code said. A test or a
CLI suite that skips itself (`Results: 0/0 passed`) is counted and shown as a warning on the run, not
failed -- the runners' own rule, above. The smoke is read the same way, with `-Half smoke`: a check mode counts
its `PASS` and `FAIL` lines, the a11y mode counts the pages it audited and fails on a serious or critical finding,
and a run that never launched a browser has no closing line and fails. Each verdict is also a line in the run's summary.
`tkTestToolkit -TestAll` holds the rule with one row per shape, runs the gate as the workflow calls it,
and fails if the workflow stops reading any half or either smoke mode through it, if the Windows job stops
importing under 5.1, or if the Windows job stops running on the schedule, the button and the `ci` label (or starts running on a push to `main`), or if a job loses its timeout.

The steps of each job run whatever the one before them did, so one red half cannot hide the others' answers;
a step whose install failed does not run. The agent and the web UI run their runners directly rather than
through `tkTest` for the same reason: a CLI that does not import on a host cannot take their results with
it. pytest sets its own environment (`Tests/conftest.py`); `npm test` sets none, and the job holds no
`TEAMS_WEBHOOK_*` for it to strip.

**No secret.** Each job asks for `contents: read` and uses the default `GITHUB_TOKEN`; there is no webhook,
no model key, no `gh` sign-in and no `az` login. A suite that needs one of them to be green is a defect of
the suite, filed as its own issue, not worked around in the workflow. A newer push to the same pull request
cancels the run in progress; a push to `main` and a scheduled run never cancel one, and a scheduled run has a
concurrency group of its own so a push cannot take its place in the queue.

**The landing page's deploy.** `.github/workflows/pages.yml` is a second workflow, run on every push to
`main` and from the Actions tab's button. One job builds the page (`npm ci`, then `npm run build:landing` in `web/`)
with `contents: read`, and uploads `web/dist/landing`; a second deploys it with the GitHub Pages action,
holding `pages: write` and `id-token: write` and nothing else. It runs no suite: the page's words are held
by `src/landing/landing.test.tsx` in `npm test`, which `verify.yml` already runs. `tkTestToolkit -TestAll`
fails if `pages.yml` gains a trigger, a secret, a permission past those three, or an action not pinned to a
major version.

**What CI does not prove, and stays a walk:** each suite run as a file under Windows PowerShell 5.1
(`powershell -NoProfile -File Tests/Test-X.ps1`, above) -- the runner starts its suites in `pwsh` -- and the
5.1 rows of [`VERIFY.md`](../VERIFY.md), Gate 12; the smoke's default, `--modules=on` and `--viewport`
modes, which run against servers someone started (Gate 8 and 9b), and its `--studio` and `--first-run` modes; the agent's and the web UI's suites on Windows;
a live tracker (Gates 6 and 8c). Nor does it compare counts: the counts at the top of this page are those of the host that
built the change, pasted after a merge, and a Linux or Windows run reads differently on purpose.

## The scenario grid

What each configuration shows -- Space status, tier, tracker, every module on or off -- is written
as one grid in [`docs/SCENARIOS.md`](SCENARIOS.md), and its executable form is
`web/src/shell/scenarios.test.tsx`: the real module registry, one row per configuration, and for
each what you see. A cell and its row change in the same commit.

## The module suites

What each opt-in module's suites guard, across the three runners, and the newer core verbs' CLI
suites beside them. A CLI suite's count lives in one place, the `tkTestToolkit` row above; the
pytest and jest rows carry the count of the file they name. Organize's CLI suite is
`tkTestToolkit -Reminders`, also above; Team Agile's are `tkTestToolkit -Rituals`, `tkTestToolkit -Triage` and `tkTestToolkit -StartWork`, below.

| Suite | Count | Guards |
| --- | --- | --- |
| `tkTestToolkit -ModuleCommands` | in the `tkTestToolkit` row | D-CM end to end: off means absent, the prefix is data, help comes from the module's own file, a colliding name refuses the module whole, a malformed or `[ordered]` data file is skipped **by path**, `Order` decides registration order, a data file cannot run code, and a module enabled only in `config.local.json` stays out of the autoload manifest |
| `tkTestToolkit -TestAll` | in the `tkTestToolkit` row | `tkTest` with all three halves STUBBED -- it never runs a real suite, which would recurse: a scratch package with a fake CLI runner and a `docs/TESTING.md` of known counts, a fake `python` and `npm` on a scratch PATH. The pytest, jest and CLI-runner parsers, the expected counts read from the REAL `docs/TESTING.md` (so an edit that moves those lines fails here), the summary merge, the order, `-Half`, `-Fast` reaching the runner, every stated skip (no Python, no `httpx`, no `npm`, no `node_modules`, and no `pwsh` with Windows PowerShell as the host), exit 0 and 2, the `npm test` child with no webhook and the run marker set, and the CLI entries left exactly as the runner wrote them; and the two workflows' switches -- `verify.yml`'s and `pages.yml`'s ("In CI") |
| `tkTestToolkit -Review` | in the `tkTestToolkit` row | `Generate-Review.ps1` against a throwaway git hub: the bare-date regression (`git log --after=2026-05-11` means "after that date at the current wall-clock time", so the same scan returned different files morning and evening -- the script pins `T00:00:00`/`T23:59:59` and this asserts it still does), what the scan includes and excludes, the scaffold's sections, multi-org slug sets, and the publish preview |
| `tkTestToolkit -SendTeams` | in the `tkTestToolkit` row | Gate 2 **reported rather than raised**, the `TEAMS_WEBHOOK_<KEY>` fallback, the catch-all variable, and the wrapper. Every case runs in a sandbox with its own config and an agent port nothing listens on |
| `tkTestToolkit -NewMeeting` | in the `tkTestToolkit` row | The eight headings by name, the prior session found across folders and out of order, an existing session reported rather than overwritten -- with its hand-written content asserted still there -- and a date already closed into `archive/` **refused**, with nothing scaffolded beside the record |
| `tkTestToolkit -EditItem` | in the `tkTestToolkit` row | The pin, typed in a fresh shell against a scratch package and hub with `gh` and `az` stubbed as functions that write down every call and change nothing: `-Pin` and `-Unpin` call `gh issue pin` / `gh issue unpin` with the Space's repo and no `gh issue edit`, a pin beside an edit runs both, `-WhatIf` prints the transition and calls neither, GitHub refusing a fourth pin is said as "GitHub pins three issues per repository; unpin one first" (exit 2, said once), `-Pin -Unpin` is refused, and on an Azure DevOps Space both switches are a stated refusal before `az` is asked anything. And `NewItem -FromCard`, typed the same way: one `gh issue create` on the Space's repo titled by the card's name, its body the card's Summary (template comments dropped) ending `Toolkit card: <id>`, a Bug card labelled `bug`, the URL written into the card's `**ADO Link:**` line with every other byte of a CRLF card unchanged and no BOM; `-WhatIf` and `-ReadOnly` print the whole issue and create and write nothing; a card already linked, an id that is not a card, `-Title` beside it, an Azure DevOps Space and a Space with no tracker each exit 2 in one sentence with no issue asked for. And `NewItem -Parent` on a GitHub Space: the parent read first (`gh issue view <n> --json number,title,url`), then one `gh issue create`, then the new issue's id (`gh api repos/<repo>/issues/<new>`) and the sub-issue call `gh api --method POST repos/<repo>/issues/<n>/sub_issues -F sub_issue_id=<id>`, after the create and with no `&` in any argument, the parent's body untouched; where GitHub refuses the route, the parent's body read and written back with `- [ ] #<new>` appended, and the output naming the refusal; `-WhatIf` reads the parent, prints both calls and makes neither write; a parent that does not exist exits 2 with nothing created; `-Priority` still refused by name |
| `tkTestToolkit -PublishPR` | in the `tkTestToolkit` row | `PublishPR`, typed in a fresh shell against a scratch package and hub with `az`, `gh` and `Invoke-RestMethod` stubbed as functions that write down every call and change nothing: `-WhatIf` prints the exact `PATCH` and its body, asks `az` for no token, makes no REST call and leaves the card's bytes alone; the success path is one token for the Azure DevOps resource, one GET, one `PATCH` with `{"isDraft":false}` at the address the card's `PR URL:` line names, and one `PR published: <url>` line directly under it in the card's own line endings (a CRLF card stays CRLF) with no BOM; run again, the card is not written twice. A pull request already ready, a card with no `PR URL:` line, an id that is not a card and a GitHub pull request (the hint is `gh pr ready <url>`) each exit 2 in one block with nothing sent and nothing written |
| `tkTestToolkit -Connect` | in the `tkTestToolkit` row | The connect wizard's verb, typed in a fresh shell against a scratch package and hub (W2, D-W12 to D-W17): the report with no step, the address written through `Config` and implying active, the grain said per tracker, `-Projects` on Azure DevOps and refused on GitHub, `-Repo` on GitHub and refused on Azure DevOps, `-Sprint`, discovery refused without an address or a sign-in (the CLIs are stubbed, so the step is SAID and never run), `-WhatIf` writes nothing, and the Example graduating into your own Space with its folder moved and made active |
| `tkTestToolkit -MeetingAgenda` | in the `tkTestToolkit` row | The stage lifecycle, read back out of the **file** rather than out of the command's output, and `-Close` end to end: the move, the `**Closed:**` stamp, `archive/` created when it is absent, a second run that reports rather than errors, and `-DryRun` writing nothing -- plus the **duplicate** case, where a session sits in `current/` and a closed one in `archive/` for the same date and `-Close` refuses rather than reporting success. Plus two absence tests: the help names none of the three retired hub prompts, and the retro still does not suggest the org-scoped `Archive` verb -- it names `-Close` |
| `tkTestToolkit -Cover` | in the `tkTestToolkit` row | A card's pictures: `Resolve-P20CardImage` over the shared table `Tests/fixtures/parsers/covers.json` (a normal cover, a missing file, two climbs out of `assets/`, a CRLF card, no line, an archived card, a non-image, the wrong depth); the card key; and `Cover` typed in a fresh shell -- the copy into `assets/<card key>/` and one line above Created, every refusal (no card, not a file, a type, 6 MB naming the limit) exit 2 writing nothing, `-WhatIf`, re-attaching replacing only the card's own picture, `-Remove`, a second round taking `cover-r2` while the archived round keeps its own, a hand-put mock never touched, `NewPrompt -Cover` / `-Before` (and a refused picture writing no card), and `storeSync: git` making the picture and the card one commit |
| `pytest Tests/test_assets.py` | 15 (+ subtests) | The agent's side of the same table (`card_image`), the model's `cover` / `before` as URLs of `GET /api/assets/...` on the list and the detail route, the route's content type, images only, 404 for a missing picture or an unknown Space, no spelling of `..` getting out, nothing written, and no flag |
| `pytest Tests/test_third_party_notices.py` | in the pytest row | `THIRD-PARTY-NOTICES.md` is true to the repository: the web dependency list regenerated from `web/package-lock.json` and compared, every `agent/requirements.txt` name present in the agent section, and every tracked font, picture, sound and `web/public/` file covered by a row under "Fonts, artwork and audio" (and every row covering something), each failure mode proved on a made-up tree; stdlib only, so it never skips. `python Scripts/third_party_notices.py --check` is the same check by hand |
| `npm test -- ImageDropZone` | 9 | The one picture in (C2): the rules (a type the verb takes under the limit is no problem; the rest say the verb's sentence; the one image among what was dropped or pasted; a pasted snap named from its type), and the zone -- a visible, named group with the three ways in, its Choose a file button the one interactive element in it (a button inside a button was axe's nested-interactive), the file picker's accept list, a drop and a paste handing over the image, a refusal in the verb's words with nothing handed over, holding a file by name in the same box with Remove giving it back, disabled taking nothing |
| `npm test -- AttachCover` | 7 | The card page's attach: the zone in the cover's box uploading first then running `Cover <file> <path>` and saying the verb's line; a before with `-Before` and Cancel when asked from the header; the upload's refusal said in the route's words with Cover never run; the verb's refusal in its words; no actions for a card without a cover; Replace cover, Add before and Remove cover for one with; Remove asking first then `Cover <file> -Remove` |
| `npm test -- ActionDialog.parent` | 4 | The new-item door names a parent: on a GitHub Space a **Parent issue** field, filled from Split's `initialParent`; the create sends it as `parent` (so `-Parent <n>`), the verb's `Linked: ... sub-issue` line is shown as it said it, and the parent stays for the next piece while the title clears; on Azure DevOps the field keeps the name **Parent ID** |
| `npm test -- ActionDialog.picture` | 4 | The + dialog's picture: a visible zone on the New ToolKit Card door; without a picture no `-Cover`; with one the upload first, then `NewPrompt ... -Cover <path>`; marked as what is wrong, `-Before`; the upload's refusal said and no card made. `cliBridge.test.ts` holds `buildCoverParams` and the new-card builder's `-Cover` / `-Before` |
| `npm test -- CardCover` | 8 | The board's face draws the cover as its top and a card with none starts with its title row (no gap), no `<img>` inside a draggable face, the list thumbnail is nothing without a cover, and the card page's cover, Before and After, and "The image is missing" |
| `pytest Tests/test_growth.py` | 37 (+ subtests) | The growth routes against the fixture hub and the 404 gate; a growth item has one writer, `NewGrowth`, which the browser runs through the bridge, so there is no second writer to compare. And the heading reader: an empty provider is `None` rather than the writer's `---`, and a file made by hand from `templates/Training.template.md` reads the template's `<!-- -->` hints as nothing, so it lists like a generated one |
| `pytest Tests/test_reviews_multi_org.py` | 18 | A review folder's membership is split-on-`+` **set** membership, not a substring search. A substring implementation passes every happy-path example and quietly puts one engagement's review in another's list |
| `pytest Tests/test_manager.py` | 36 | The 1:1 routes against a copy of the fixture hub -- list, read, create (the real `NewMeeting` through the bridge, so the file is the template's byte for byte; the test owns its environment: the child `pwsh` reads this checkout's config, which a clean export or worktree has no `config.local.json` in, so the setup gives it `features.communication` through `P20_FEATURES`, the per-process stand-in both halves read, and the series case asserts the create answered 200 before it saves -- and skips, naming why, where no PowerShell is present), save -- plus all three gates (a bad date, a session in `current/`, and one already closed into `archive/`), and that a save never deletes an agenda, never moves the stage and never loses a `Sent` line |
| `pytest Tests/test_comms_format.py` | 21 | The engine, carried with **every assertion unchanged**: tone formatting, the Adaptive Card envelope, recipient resolution, the master switch, validation, dry run and fail-soft failure. This file is the evidence the engine did not change behaviour while it moved packages |
| `npm test -- settingsWorkflows` | 7 | Settings by workflow: the one list's shape and rules; every module the registry declares has a question and no entry names a module the web does not know; an entry's state from its surfaces' (`on` if any, `not configured` if all, else `off`); the anchor with the active Space filled in; tips only from `not configured` and only entries that carry one (D-W3) |
| `npm test -- PRCommentsDetail.reply` | 7 | The page's h1 is the card's title; the reply box: an open thread with no reply gets it and a triaged one keeps Resolve; Suggest a reply fills the draft from the model's answer and maps the recommendation to ReplyPR's status; Post reply runs `ReplyPR` through the bridge with the draft and the status and re-reads the card; the agent's 412 is shown as its own sentence; with no key the button is absent and the box names the variable |
| `npm test -- ConnectPage` | 6 | The wizard page: a Space with no address is a whole shape and steps 2-3 wait; Save address is the verb's step; an Azure DevOps Space says it is an organisation, names `az login` and never runs it; a GitHub Space is one repo with no sprint step; the sprint switch is the last step; the Example offers to become yours (D-W15) |
| `npm test -- HowDoI` | 5 | The drawer's "How do I…" section: every question with the CLI's state word; Change opens the drawer at `spaces.<active>.org`; a sentence and a keyless journey have no door; folded on arrival at an anchor and unfolded by a click (D-W11) |
| `npm test -- useFacePref` | 2 | The Face store where browser storage throws: `localStorage.getItem` made to throw before the module loads, the hook answering the default face and `ToolKitLogo` rendering; `setItem` throwing, a chosen face holding for the session with nothing stored |
| `npm test -- useCurrentTheme` | 3 | A theme choice where browser storage is refused: every storage call throwing, a choice reading back for the session; a fresh load (a reload) giving the default; storage that keeps, a fresh load giving the choice |
| `npm test -- TestHealth.badge` | 1 | The Test Health card's Space badge: rendered from a `/api/test-history` answer carrying `active_space` and the three-half `halves` block, the badge and the foot name the Space |
| `pytest Tests/test_studio.py` | 50 (+ subtests) | The Studio (S2b): the `space` argument on `/issue-report`, `/deploys`, `/issue/{n}` and `/status` (another Space's cards from its own folder, no tracker asked) (the named Space's repos and tier; an ADO Space unsupported with `gh` never asked; an undeclared slug 404; no argument the active Space's as before); `/env`'s per-Space `tracker` and lane names; the seed drawer's two routes over a scratch fixture hub (every field, non-notes skipped, no folder empty with `exists: false`, the name rule, the folder renamed through `hub.json`, the thread-Space rule, a leftover `features.studio` true or false changing nothing -- the Studio is core); and, where `pwsh` is on the machine, **`NewDesign` and Promote typed as verbs** in a fresh shell -- both Studio verbs resolving, in `Menu -All`, `-Help` and the bridge whatever a leftover flag says, the autoload manifest naming them, `Config -Set features.studio=` refused with exit 2 and nothing written; the file from the template with its bytes and an `id:` of the contract's shape (`design.idRegex`) that the agent's reader still parses past, never overwriting, `-Space`, the stated refusals; `NewItem -FromDesign` with `gh` stubbed: the issue from the note labelled `design`, the thread line written back in the note's own endings, `-ReadOnly`, six refusals |
| `pytest Tests/test_ledger.py` | 37 (+ subtests) | The Studio's Spaces card's one read, `GET /api/studio/ledger`, with `gh` stubbed: one GraphQL call whatever the number of Spaces and one more per twenty repositories, no tier probe when it answers; a second read inside the 600 s TTL and an agent restart make no `gh` call, Refresh, an expired entry and a changed address do; a read that did not answer is not kept; the report equal to `_github_issue_report`'s over one backlog; `/issue-report` served from the ledger entry -- no `gh` call warm, one read of that Space cold, `?refresh=1` past it, a bridge `CloseItem` dropping the active Space's entry; visibility seeding `/visibility`'s cache as one record per repository -- visibility, `has_issues`, `url` -- again from disk after a restart, and the REST read filling the same record; no argv a shell would split |
| `pytest Tests/test_stamp_design.py` | 9 | `StampDesign` (design lifecycle L1) typed as a verb in a fresh shell, in a scratch repository and hub, where `pwsh` is on the machine: the bridge can call it (a core verb); `-WhatIf` names every file and writes none (bytes and mtimes); an id first in an existing block, a block made where there is none, a spec sharing its note's id by stem, archives walked, `README.md` skipped, a present id byte-identical, CRLF kept, a second run writing nothing, a disagreeing pair left alone, the refusals exit 2, and `-Hub` stamping the hub root and a declared Space's folders and nothing else; on Windows only, a hub reached through its 8.3 short name is named and stamped in its long form |
| `tkTestToolkit -Design` | in the `tkTestToolkit` row | The design lifecycle's reader (L2), this half: the state rule `Resolve-P20DesignState` over the ONE table `Tests/fixtures/design/states.json` (shared with `Tests/test_design.py`) -- state, outcome, mismatch and Closed, row for row; the tree reader `Read-P20DesignTree` over a scratch tree (the four folders, grouping by id, a file with no id counted and not shown, two notes with one id a conflict, `README.md` skipped, a CRLF file read the same, the row's title, description, thread and Docs line, road order, the structure flags); and the `Design lifecycle` row of `Get-P20OptionalSurfaces` -- `not configured` outside a repository, without `design/`, or with nothing but a README in it, `on` with every file stamped, `off` with the count, its question and its config line. And the line a card names its design with: `Get-P20CardDesign` over the ONE table `Tests/fixtures/parsers/design-lines.json` (shared with `Tests/test_parsers.py`) -- a Design line, a repo URL, CRLF, the corpus's hand-written Spec lines read as written, Design over Spec, an uppercase id kept as words, an empty line naming nothing; `New-P20DesignLine` and the reader agreeing; and `Select-P20Design`, the one name rule `MoveDesign` and `NewPrompt -Design` ask. Runs as a file under Windows PowerShell 5.1 too |
| `tkTestToolkit -Config` | in the `tkTestToolkit` row | `Config` (`Scripts/Set-ToolkitConfig.ps1`) in a scratch package, every case run as a child `pwsh` so the exit code is the refusal contract: the schema, `-Set` and `-Unset`, the three files a key may land in, every refusal and its sentence, the JSON form the bridge carries (`-Set '{...}'`, `-Unset '[...]'`), and an open shell following what moved after it loaded -- `activeSpace` written from another shell, a module flag flipped there, and `PROMPTS_ROOT` or `P20_ACTIVE_SPACE` exported into the shell itself: the next verb re-reads, `Env` names one hub, and the card lands where the environment says. Runs as a file under Windows PowerShell 5.1 too: the runner hands the child its arguments as one `-EncodedCommand`, because a 5.1 host strips the `"` out of a native argument and pwsh 7.3+ does not |
| `pytest Tests/test_design.py` | 38 | The agent's side: the same state table through `design_state`; `GET /api/design` reading the four folders in order in one GraphQL call, the listing cached and its parsed rows on disk by blob sha (the call count constant in the number of notes, a restart refetching nothing unchanged, the null-text fallback, no `&` in argv), the detail served from the disk while the listing is fresh, `structure`, a README skipped, the grouped shape (every field of a row, a conflict shown as none, an id outside the contract's shape read as none, a note archived before its spec still a Spec with its sentence); an archived document by its path with `kind`, `archived`, `closed` and `outcome`; the gate; a bad path never reaching `gh` |
| `pytest Tests/test_move_design.py` | 17 | `MoveDesign` (design lifecycle L3) typed as a verb in a fresh shell, in a scratch repository with an origin remote and a scratch hub under `storeSync: git`, where `pwsh` is on the machine: the bridge can call it; `-WhatIf` names the git root and writes nothing; `-To Spec` scaffolds from the template (id, description, thread; LF, no BOM) and writes the journey above `**Created:**`, staged with no commit; a CRLF note kept; `-To Archive` shipped and dropped with the reason required and written, the stamps and the journey above them; `-To Complete` archiving both with `> Docs:` under the spec's title, a spec alone completing; every refusal exit 2 with one `Error:` and nothing written; naming by id prefix, file or stem, the ambiguous, the unknown and the unstamped refused; `-Hub` committing once, `-Hub -Space` on a Space's own folder, outside a repository refused |
| `npm test -- DesignList` | 28 | The Design tab's list and reading room (the jest row above names it); `DesignsCard.test.tsx`'s groups and `docFilters.test.tsx`'s kind-and-text rule are the hub drawer's and the drawer's side of the same contract |
| `tkTestToolkit -Rituals` | in the `tkTestToolkit` row | Team Agile's standup: every case of `Tests/fixtures/rituals/standup.json` (shared with `Tests/test_rituals.py`) -- the window's start, the day of the year, the chair's lines, the queue, each worker's slots by number, `empty` and the status sentence -- and the text against the golden `standup-<name>.txt` byte for byte, again after a JSON round trip, and the chair's reading against `standup-<name>.brief.txt` for every case; `Standup -Brief` typed prints that reading alone and `-AsJson` carries it; every case of `standup-cards.json`, the cards alone -- the one worker's slots and the walk queue by card id, the `sources` and `titles` tables, the goldens `standup-cards-<name>.txt`, a not-billable card nowhere -- and `Get-P20StandupCards` over real folders (a card that says `**Billable:** no` reading billable false); every case of `standup-joined.json` (shared with `Tests/test_rituals.py`), the two sources joined on the id -- each shape's walk and every worker's slots by ref, the `Check` lines and the links, the together case's detail, work and brief goldens (`Tests/regenerate_joined_goldens.py` writes them, and `standup.json`'s and `standup-cards.json`'s) byte for byte and after a JSON round trip, no card in play reading as the issues alone, the tracker down, rounds of one id, and what moved -- each item's motion and commits, the counts per worker and in total, the `counts` and `window-three-days` goldens; `Standup -Since` typed, widening yesterday, and its refusals; no `fakeWork` line in any case (D-SA5); off is no verb, no function, no bridge entry and no `Menu -All` line; and `Standup` typed in a fresh shell with only this package's manifest and `gh` stubbed as a function answering the friday case -- the text the rule renders for now, `-Json` round-tripping to the same text, `gh` failing and an Azure DevOps Space each a `Tracker` line with exit 0 (ADO's the contract's `adoTracker`), a local Space filling from its scratch cards line for line, the GitHub Space joining its scratch cards to the stubbed issues line for line (a card of its own on the Space's tile, a `Check` line for a card whose issue is closed, a not-billable card nowhere), an undeclared `-Space` a stated refusal, and the hub untouched; and `Standup -Walk` over a scratch `VERIFY.md` -- fixture issue 104's Gate 12 row verbatim and wrapped under its line, fixture issue 105's `no VERIFY row` line (a longer number is not its row), `-AsJson` carrying `walk[]` and nothing else, the empty list, `gh` down, `-Walk -Remind` a stated refusal, and the walk leaving before the attend block; and the work grain: every case and small table of `standup-work.json` (shared with `Tests/test_rituals.py`, which asserts the same rows from the agent) -- each group of the queue and of every worker's slots by name, `by`, count, refs and phrase, the `heads`, `keys`, `types` and `counts` tables, the goldens `standup-work-<case>.txt` byte for byte and after a JSON round trip -- and the prose: every `sentences` row, every `folds` row (today's also-ons as one sentence, named up to four and counted past it) and every case of `standup-prose.json` (shared with `Tests/test_rituals.py`) -- the queue's sentences, each worker's in order, the goldens `standup-prose-<case>.txt` byte for byte and after a JSON round trip -- and the dress guard: every row of `standup-dress.json` (shared with `Tests/test_rituals.py`) -- a model's sentence and its group's facts in, kept or the first of `rituals.dressGuards` it fails out (a fact added, dropped or changed, a kind miscounted, a name invented), every group's prose sentence passing its own guard, every guard with a row, and a reply naming issue 999 keeping the prose for that group -- and `Standup -Grain work\|detail\|brief` typed, with a word that is not a grain and `-Brief -Grain work` each a stated refusal; and the work grain: every case and small table of `standup-work.json` (shared with `Tests/test_rituals.py`, which asserts the same rows from the agent) -- each group of the queue and of every worker's slots by name, `by`, count, refs and phrase, the `heads`, `keys`, `types` and `counts` tables, the goldens `standup-work-<case>.txt` byte for byte and after a JSON round trip -- and the prose: every `sentences` row, every `folds` row (today's also-ons as one sentence, named up to four and counted past it) and every case of `standup-prose.json` (shared with `Tests/test_rituals.py`) -- the queue's sentences, each worker's in order, the goldens `standup-prose-<case>.txt` byte for byte and after a JSON round trip -- and `Standup -Grain work\|detail\|brief` typed, with a word that is not a grain and `-Brief -Grain work` each a stated refusal. The friday case's issue 101 title carries an em dash, curly quotes and `Ï` (UTF-8 `C3 8F`, a byte cp1252 cannot map), so both halves -- and Windows PowerShell 5.1 reading the fixture -- carry a non-ASCII title through the golden. The suggestion: `Tests/fixtures/suggestion/table.json` (shared with `Tests/test_rituals.py`) -- every nearest-milestone row, every rule row (the candidates in order, the pick, its shape, sentence and command, each excluded ref with the first exclusion it met), every switch row, and three chair's readings end to end against `suggestion-<case>.brief.txt` byte for byte; `Tests/fixtures/parsers/card-milestone.json`; and typed, `Standup -AsJson` carrying the suggestion and none with `spaces.<slug>.features.suggestions=false` in the hub |
| `tkTestToolkit -StandupRemind` | in the `tkTestToolkit` row | Team Agile's reminder: the cadence table `Tests/fixtures/rituals/remind.json` (next due, Friday -> Monday, the ref's spelling), `-Remind` writing one Organize reminder and a second rewriting it, attending archiving today's and writing the next, once a day, Organize off refusing with the key named, the switch in three places |
| `pytest Tests/test_studio_prompts.py` | -- | The Studio's Prompts card: `GET /api/studio/prompts` lists every core prompt in `agentic/` with `agentic/prompts.json`'s marks (ways of working, sender, module, what it drives), the two the tools send not by hand, each row's whole file and its description; an add-on's prompts absent while it is off and listed when on, its read a 404 naming it; a name outside the folder a 404; the hub's `agentic/` listed as yours for every way of working, an extension folder's copy under a shipped name `overrides` and wins over the hub's; last changed from git in a scratch clone, linked to the file's history only for a GitHub origin; every shipped row's title and purpose line read from its header. `Tests/test_agentic_index.py` holds the index to the folder and to the How do you want to work? answers in `Config/settings-workflows.json`, every prompt to the one header shape (frontmatter with `description`, `argument-hint` and `agent`, one `#` title), and no prompt to a known-gap note or an issue number |
| `python3 -m pytest Tests/test_standup_remind.py` | -- | the same cadence table from the agent's side; `POST /api/ritual/standup/attend` through a stubbed bridge; `GET /api/ritual/standup/remind`; 404 off; Organize off answers `action: off` |
| `tkTestToolkit -Triage` | in the `tkTestToolkit` row | Team Agile's triage: every case of `Tests/fixtures/rituals/triage.json` (shared with `Tests/test_triage.py`) -- the groups in order (no milestone first, then most open, a tie by title), each group's counts, context line and numbers, each issue's worker, size, who, severity and deep-water mark, the sizes -- and the text against the golden `triage-<name>.txt` byte for byte, again after a JSON round trip; the who rule, and a card's `**Assigned:**` line over `Tests/fixtures/parsers/assigned-lines.json` (shared with `Tests/test_parsers.py`); off is no `Triage`, no `Route`, no `-Assign` and no bridge entry; `Triage` typed in a fresh shell with `gh` stubbed (the mixed golden, `-AsJson`, an Azure DevOps Space's `Tracker` line with exit 0, an undeclared `-Space` refused); and `Route` typed with `gh` stubbed as a function that writes down every call -- the exact `gh issue edit` argv for `-Size`, `-Milestone`, `-Severity` and `-DeepWater`, alone and all four in order, `-WhatIf` writing nothing, the two moves printed, and nine refusals plus a failing write each exit 2 with one `Error:` block and no write; `-Assign me` the one `--add-assignee @me` write (printed, not made, under `-WhatIf`), `-Assign <size>` the `-Size` write byte for byte, and five `-Assign` refusals (an Azure DevOps Space among them); `-Assign` on a card -- one `**Assigned:**` line above `**Created:**`, LF and CRLF kept, an unchanged card not written, the sizes from the repo's labels, a local Space's card taking `-Assign me` -- and five card refusals, a size with no connected repository to read labels from among them |
| `tkTestToolkit -StartWork` | in the `tkTestToolkit` row | Team Agile's hand-off block, typed in a fresh shell over a scratch hub built from `Tests/fixtures/start-work/` (shared with `Tests/test_bridge.py`, which runs it through `POST /api/cmd/StartWork`, and `StartWorkBox.test.tsx`): off is no `StartWork` and no bridge entry; the card's block is `expected-card.md` byte for byte -- and the same for the card in CRLF, the id in lower case and the full filename; `39` never assembles `Task139`; a `how-we-work.md` switches section one's heading to its path; an issue no card carries is `expected-issue.md` with one `gh issue view` (stubbed); `-Prompt`; a partial name named in a terminal and refused for a non-interactive caller; and twelve refusals each exit 2 with one `Error:` block and the hub untouched. `-Launch`, from scratch git clones with a stub `claude` first on the PATH: `-WhatIf`'s commands, the model from every place a size is read, every launch refusal (`fable` on a card and on an issue, and no size, among them) leaving no worktree and no log, and -- off Windows, a named skip there -- the launch itself through a pipe, back while the stub session lives on, its log opening on the block |
| `pytest Tests/test_child_reads.py` | -- | How the agent reads a `gh`, `az` or `git` child: `core/child.py` `run_read` asks for UTF-8 with replacement, keeps the Windows shell rule, and raises on a reader that died rather than reading empty; each of `_gh_issues`, `_gh_labels`, `_gh_json`, `design._gh` and `_az_json` under a stand-in for a cp1252 console keeps a title whole and states a dead reader as its reason; no other `text=True` call in `agent/` lacks an `encoding`. `Tests/test_rituals.py` carries the route's half: the friday case read through the same stand-in is the golden byte for byte, a dead reader is `tracker.ok` false with the sentence, and a reader that raises is `The tracker read failed: ...` |
| `pytest Tests/test_triage.py` | 22 (+ subtests) | `GET /api/ritual/triage` over the same table: the groups, each issue's fields (`who` among them), the sizes and the golden text for every case, the who rule, and the goldens the regeneration script's (`Tests/regenerate_joined_goldens.py`); the route answering `mixed` byte for byte with the gh calls it made (labels, then `--state open` with `milestone` and `assignees`, then `gh api user`), and a viewer `gh` cannot name reading `@<login>`; the field names; no `space` is the active one; an Azure DevOps Space and a tier below 1 a `Tracker` line with `gh` never asked; `gh` timing out the no-tracker golden; an undeclared Space 404; off 404, not 403; nothing written to the hub |
| `npm test -- studio` | 4 suites | The Studio's web half: `foyer.test.ts` (the Spaces filter's bucket rule as a table, and the row's words as tables -- every Space a row, the GitHub half, the cards half, what connecting would show -- and the spec's example line), `FoyerCard.test.tsx` (a row for every Space, the tracker read only for GitHub rows, another Space's cards counted by its slug under its own lane names and an archived one not asked, a cold first run's three demo Spaces with nothing reading as an error, Connect, a row is the switch; the Spaces filter -- All first, the filtered count, honest, the empty sentence, remembered per browser; the load, Refresh and pager -- one loading state then the whole list, no placeholder line, Refresh before the chip re-reading every row, five a page with the filter first, an unconnected GitHub Space not asked its visibility), `DesignsCard.test.tsx` (the drawer, a hub with no `design/` folder, New Design Note through the bridge, the reading room as a document with its thread, Promote's rules and its bridge call), `registry.studio.test.tsx` (core: no flag, mounted whatever `/env` says; the Prompts reading room's route), `PromptsCard.test.tsx` (the Space's way of working read from `/env`'s `howIWork`, the set and the line that counts the others, the two groups and their marks, Copy prompt copying the whole file, the reading room by its ref and a 404 in the agent's words) |
| `npm test -- solitaireAgile` | 9 suites | Team Agile's web half (M0, V1's played view, the reminder's settings row, triage, the work grain, the issue popover, the stage bubbles, its prose, and the hand-off's copy box): `StandupPage.test.tsx` -- the response built from the shared fixture (`Tests/fixtures/rituals/standup.json`) and the golden read from disk; the grain's three tabs (Detail by default, Work showing `standup-prose-friday.txt` verbatim and copying it, Brief once, remembered per browser, a stored word that is not a grain read as Detail); `stage/standupDeck.test.tsx` (22) -- the deck built from `friday` (chair lines and the `nothing` sentence picked from the vocabulary by the fixture's indices): queue, chair, Fable, Opus, Sonnet, chair, queue in that order with stable ids, the plates (`TEAM LEAD · DEV-HERO (fable)` ...), one Say line per slot, the mug and the status on Sonnet, nine tiles and the register on every slide, reduced motion in the keyframes, and the bubbles: the speaking tile alone has a speech surface carrying its slot lines, the thought surface opens on a click of its real button with each slot's items, Escape and the deck advancing close it, a mug offers none, the cloud floats under the stage's reduced-motion rule, and the voice's text is unchanged; `stage/standupDeck.test.tsx` also plays at the work grain as prose over `standup-prose.json`'s `friday` -- one Say line a sentence, the queue's, Opus's and Fable's as the agent wrote them, nothing for an empty slot, an empty queue the contract's sentence; and dressed, from `standup-dress.json`'s reply -- a worker in `spoken` speaking and showing its spoken sentences, `spoken: null` and a worker not in it the prose, the queue and the mug never dressed; the page shows `friday`'s text byte for byte (line one the header, the rest the monospace body) with fixture issue 104 linked to its url on both its lines, `no-tracker`'s with no links, an error rather than an empty standup when the agent is away, and Play the one other button, opening the played route; and the issue popover (nine cases, `IssuePopover.tsx`): the number's text and the page's `textContent` unchanged, a click opening the surface without following the href, hover opening it, the title, the worker chip (only for a known seat), severity and milestone from the one triage read (and neither when the read lacks the number or is absent), state from the row's slot (yesterday Closed; today, blockers and the queue Open), Open on GitHub the last and only external link, Escape closing, and a card's surface with its path and no link; `api.solitaireAgile.test.ts` -- the query is `rituals.route` under the slice's base, with `?space=<slug>`; `registry.solitaireAgile.test.tsx` -- off is no route and no nav entry, on is the tab and the played route (chromeless only while on), and the nav reads Studio, Team Agile, Lounge; `stage/standupDeck.test.tsx` (14) -- the deck built from `friday` (chair lines and the `nothing` sentence picked from the vocabulary by the fixture's indices): queue, chair, Fable, Opus, Sonnet, chair, queue in that order with stable ids, the plates (`TEAM LEAD · DEV-HERO (fable)` ...), one Say line per slot, the mug and the status on Sonnet, nine tiles and the register on every slide, reduced motion in the keyframes; `no-tracker` plays queue, chair, chair, queue with the tracker's seat lit; the deal of workers onto seats; `stage/StandupPlay.test.tsx` (3) -- the resolver's loading, error and played states; `TriagePage.test.tsx` -- the read built from `Tests/fixtures/rituals/triage.json`: the queue in the read's order (no milestone first), the context line, who has it (`me`, `@<login>`, the worker, `nobody`, and an older read's fallback), Next skipping, the exact `Route` argv for a severity, an OPEN milestone, **me** (`-Assign me`, pressed when the issue is yours), a size and deep water's Assign Fable, Split live and opening the new-issue dialog with the issue as its parent (no dialog mounted before), a refusal shown in the verb's words, past the last issue, nothing open, no tracker, the agent away; `RitualPage.test.tsx` -- the Standup \| Triage strip, each tab an address; `api.solitaireAgile.test.ts` also holds `rituals.triageRoute` under the base; `StartWorkBox.test.tsx` -- the hand-off block's copy box: one `StartWork` call, `Tests/fixtures/start-work/expected-card.md` shown verbatim with its head as the title, Copy copying exactly the block, a refusal shown as the verb's sentence with no Copy, the agent away said so; and `StandupPage.test.tsx` holds a list row's **Start work** opening it with one call |
| `pytest Tests/test_surfaces.py` | 4 | `GET /api/surfaces` hands the CLI resolver's answer on and caches it, `?refresh=1` reads again, no PowerShell is a stated 503 -- and, with a host present, the real inventory: the hub first, every surface with a question, every entry naming a surface it has |
| `npm test -- lazy` | 9 | Off means NO BYTES: `lazy.test.tsx` -- a `lazyPart` draws the house's "Loading..." first and the picked export with its props once the chunk arrives, or nothing at all when told to (the header bell); `lazyModules.test.ts` -- every opt-in module's descriptor (`index.tsx`) is read as source and refused a static import from its own folder that is not `paths`, and must defer at least one part. The smoke's off mode holds the same rule in a browser: no module source is requested |
| `npm test -- registry.growth` | 9 | Growth contributes routes and a nav entry only when the flag is true, and no home cards of its own |
| `npm test -- registry.communication` | 7 | The same from communication's side: off contributes nothing; on contributes exactly its seven routes |
| `npm test -- stages` | 7 | The three stages in one place: the file's word, the badge's label, what comes next, complete only at the last -- and the one switch the session page offers: the stage ahead, `Plan` for a blank stage, nothing for a closed session |
| `npm test -- sendButton` | 21 | The send button's three states, including that it is **absent** rather than disabled when the workflow has no send, that a disabled button names the webhook variable before the Retro stage rather than only at it, that a send recorded under `## Sent` or an Agenda holding only its placeholder disables it with the reason, and that what goes out is the Agenda and never the self-assessment |

**Every module is mocked in every registry test**, including the ones the test is not about. A
registry test is about the registry's filtering, so the other modules are stand-ins by design -- and a
sibling's real tree left to load pulls in `react-markdown`, which is ESM and which ts-jest cannot take. The one suite that renders the real markdown pipeline,
`web/src/shared/markdownPlugins.test.tsx` (simple HTML, and what the sanitiser refuses), does it
through `transformIgnorePatterns` in `web/jest.config.mjs`, which lists exactly the markdown stack's ESM
packages and React Router 8's (ESM only too, and imported by nearly every page). Two more pieces carry the
router under jsdom: `web/tests/jest.setup.cjs` hands the test window Node's `TextEncoder` and `TextDecoder`,
which the router builds when it loads, and `moduleNameMapper` swaps its one file that reads `import.meta`
for `web/tests/routeModules.jest.cjs`, a stub of a route-module loader this SPA never calls.

**The PowerShell module suites are registered with the runner**, so `tkTestToolkit` runs them
and `tkTestToolkit -List` names them, exactly like a core suite. They also **unset
`TEAMS_WEBHOOK_*` per process**: a machine that has a real webhook in its environment must not be
able to turn a test run into a message someone receives.

**Compat does not scale with what is installed.** The sweep drops any path running through a
vendored or generated folder at **any** depth -- `node_modules`, `dist`, `__pycache__`, a `.venv`,
`.git` -- so `Compat` has one number whether or not `npm ci` has run in `web/`, and a total can be
compared run to run. It grows only when a shipped script joins the sweep. The list lives in `Tests/ScanExclusions.ps1` and `Test-Portability` reads the same one, because the
two suites had the same omission from opposite directions. The rule is judged on each path **relative to the package root**, so where the checkout itself lives (an agent worktree under `.claude/worktrees/`) never changes what is scanned; a case in `Test-Portability` copies a small tree under a `.dot/` folder to hold it.

**`Test-PS51Compat.ps1` and `Test-Portability.ps1` run as a file under Windows PowerShell 5.1 as well** (`powershell -NoProfile -File Tests/<suite>.ps1`), because they are the suites that prove the 5.1 floor, and a floor proved only by pwsh 7 is not proved. `Test-PS51Compat` reads each script with `-Encoding UTF8`: 5.1 reads a BOM-less UTF-8 file as the ANSI code page, so one multi-byte character turns into a curly quote. `Test-Portability`'s Clause 9 hands its snippets to the child `pwsh` in a file rather than on its command line, because 5.1 drops a bare `"` from a native command's argv and pwsh 7 re-escapes one a caller added. Its Clauses 11 and 12 read every `Tests/Test-*.ps1` (the runner, `Test-Toolkit.ps1`, aside) as an AST: a top-level `try` with no `catch` is a FAIL naming the file and line, and so is a call to an `Assert-*` the file neither defines nor dot-sources or imports by a literal path ("A suite ends with a catch", above). Its Clause 13 reads every shipped source file of the three halves, `Tests/` included and `Tests/fixtures/` not, for the four work-marker words at a word boundary and case-sensitively, and fails with each `file:line`; it holds the sweep at zero and does not hold commented-out code, which no heuristic over a comment line can tell from prose (review does, see [Contributing](CONTRIBUTING.md)). Its Clause 15 reads the CLI's runtime code -- the root module, `Scripts/` and `Config/` -- with the PowerShell tokenizer for a `gh`, `az` or `git` call whose stderr is redirected (`2>`, `*>`) anywhere but `Scripts/Invoke-TrackerRead.ps1`, and fails with each `file:line`: that redirection under `Stop` throws on 5.1 before the exit code is read (AGENTS.md, "Traps worth knowing"). Clause 16 reads every `Scripts/*.ps1` for an inline `function Get-CliPrefix` or `function Write-CliError`: the two standalone fallbacks live once, in `Scripts/Initialize-CliFallbacks.ps1`, which every script dot-sources, and a script that carries its own copy fails by file and line. A comment or a string that names such a call is not one, and a file that still keeps its own copy is on the clause's allow-list with its reason.

**One more on a machine that has a `config.local.json`.** The Autoload suite has one assertion that
only exists when a local config does -- that a nav alias declared only there has not leaked into
the committed manifest, which would turn this suite red on every other machine. It is trivially
true on a machine with no personal nav shortcuts, and it is the machine that *has* them where it
earns its place. A tree with no local config therefore reads one fewer than the same tree with one. A
local config that also declares a displayable nav alias adds two more (`Menu`'s alias-coverage
assertions), which is why a machine with personal shortcuts reads higher still.

**Parser parity is by shared fixture, not by one cross-language assertion.** `test_parsers.py`
exercises the Python parsers against `Tests/fixtures/parsers/`; the `PromptStatus` PowerShell suite
runs `Get-PromptFileStatus` against the *same four files*. Neither calls the other; the fixtures are
what make a regex drifting on one side fail on that side. A card's `modified` day is held the same way:
`Tests/fixtures/status-modified/history.json` is built into a scratch git hub by `test_status.py` and by
the `PromptStatus` suite, and each asserts every row's day and one git call for the folder. Tier parity is the stronger kind -- one
test, three implementations, and it printed `all 80 combinations agree across PowerShell and
Python` (16 boolean combinations across 5 status values, including the two invalid ones).

**The smoke test needs a browser, two servers and a hub.** `npm ci` installs the Playwright
*library*; the chromium *binary* lives in a machine-level cache
(`~/Library/Caches/ms-playwright`, `%LOCALAPPDATA%\ms-playwright`) and is downloaded by
`npx playwright install chromium`, which nothing in this repo runs -- there is no `postinstall`,
deliberately, because a 130 MB download is a surprise for a reader who only wanted `npm test`. On a
machine that has ever run Playwright for anything the smoke just works. Without it, `npm run smoke`
exits 2 and prints that one command rather than a launch stack trace.

Then start both servers against `Tests/fixtures/hub` -- a deliberately boring two-card store with
no toolkit inside it and no `.git`, one card Active and one Code Review, names and URLs belonging to
nobody -- with **one command per mode**, and run the matching smoke:

```bash
tkWeb -Dev -Fixture                  # then: cd web && npm run smoke
tkWeb -Dev -Fixture -Modules on      # then: cd web && npm run smoke -- --modules=on
tkWeb -Dev                           # afterwards: back on your own hub
```

`-Fixture` restarts this checkout's agent as a **test run** and hands it the fixture hub,
the fixture's Space and the flags through its environment -- `PROMPTS_ROOT`, `P20_ACTIVE_SPACE`,
`P20_FEATURES` and the run marker `P20_TEST_RUN`, with every `TEAMS_WEBHOOK_*` removed -- so
`config.local.json` is never written, and there is nothing to back up, swap or forget to restore
([the command reference](CLI.md#the-other-two-halves) has the table). An `unset` in your shell does
not reach the agent, which inherits what the module's `.env` loader puts in its process, so
`-Fixture` is the one way to run the modules-on smoke on a machine whose `.env` holds a webhook.
**The smoke refuses before it starts** if `/api/env` reports any
recipient `configured: true`: one message naming `.env` and `tkWeb -Dev -Fixture`, exit 2, rather
than four failed assertions per viewport on a live send button.

With no `--port`, `smoke` drives the port `tkWeb -Dev`'s Vite actually took -- read from `web.log`
at the repo root, and only while `.web.pid` says a dev server is up -- and falls back to 5174, the
port `npm run dev` asks for. Its first line says which: `smoke: http://localhost:5175 (web.log, from
tkWeb -Dev)`, `(--port)` or `(default)`.

**That default is why an orphaned dev server matters.** If something is already on 5174 when
`npm run dev` starts, Vite silently takes 5175 and the smoke run drives the *other* server -- code
that is no longer the tree, passing or failing for reasons that are not yours. `Web -Status` names
any listener on the dev port that it did not start, and `Web -Stop` ends it if it is a dev server --
anything else it reports and leaves alone ([the command reference](CLI.md#the-other-two-halves)). After a stop, check
with `lsof -nP -i:5174` (`netstat -ano | findstr :5174` on Windows) and expect nothing, or
a named process that is not yours. The agent half follows the same rule: `Web -Stop`
ends this checkout's agent even when another shell started it, and a `PROMPTS_ROOT` set after the
agent started makes `Web -Dev` restart it rather than reuse it -- so pointing a smoke run at
`Tests/fixtures/hub` is `$env:PROMPTS_ROOT = ...; tkWeb -Dev`, and the agent's reuse line names the
hub it serves. (`-Fixture` sets that variable for you, and restarts the agent whether or not it
matches -- see above.)

**It takes a mode, and both are run.** `--modules=off` is the default: every feature flag false.
Both fixture cards render on `/`; both states render; `/system` shows `EnvCard` with a tier badge;
`/growth` and `/communication` produce no nav entry, no page, **no requested data** and no requested
module source (every page an opt-in module contributes is a lazy chunk, so with the flag off no
file under its folder is fetched); each route is no wider than the window; and no page errors across
the routes. The tier-badge check reads its word list out of `envBadge.ts`'s source text rather than
retyping it -- a plain `node` run cannot `import` a `.ts` module, so it
extracts every `label: "..."` instead, which is why a fourth or fifth word never has to be added
here by hand. Against `Tests/fixtures/hub` the badge is usually **Offline**: the fixture's own Space,
`test` (beside the shipped `azure-demo`), carries a URL nobody owns, so a machine with `az` signed in probes it and fails --
correctly. A fresh machine with no `az` at all reads **Minimal** instead (Tier 3, before the Space is
even asked). Either is a pass; what fails is the word not being in the list at all.

The data and source checks are the ones that matter -- they are what "off means absent" looks like
from outside.

`--modules=on` is the other half, and it expects the agent to have been **started** with
`features.growth` and `features.communication` both true. It says nothing about
`features.organize`, on purpose: every machine the owner runs
this against has all four module flags on, which is exactly what `tkStart` writes, and Meetings
moving off its own nav entry onto the Organize tab when `features.organize` is true is by design
(`communication/index.tsx`'s `hidden`), not a thing this mode configures. So the Meetings check
reads `features.organize` off `/api/env` -- through the dev proxy, the same way the app itself reads
it -- and asserts an `Organize` nav entry (not a `Meetings` one) and the fixture sessions listed on
`/organize` when it is true, or the `Meetings` shape on `/communication` when it is not. Either way
is a pass. The checks: a Growth nav entry and
`/growth` listing the fixture hub's three artifacts by title, `/skills` rendering, a `Meetings` (or
`Organize`) nav entry and the three fixture sessions listed with their stage labels, both modules'
data actually requested, the retro session's send button **present, disabled, and naming
`TEAMS_WEBHOOK_MANAGER`**, and the page that button is on being **reachable**: an
`Edit / send` on each meeting row and on the read view, and the read view's landing on
`/communication/sessions/2026-02-05.md` when pressed, and exactly one of the three rows -- the
complete one -- offering **Close**, which is never pressed because it would move a file in the
committed fixture hub. The send button itself is read-only by design:
it is never pressed, because a press posts to a real webhook. The runner deletes both
`TEAMS_WEBHOOK_*` variables from its own environment -- which covers the runner and the browser it
launches, **not the agent**, the process the button's state is read from; `tkWeb -Dev -Fixture` is what
keeps the agent clean, and the refusal above is what catches one that is not. An *enabled* button
there is a reason to stop rather than a pass.

The mode does not configure the agent -- it declares which configuration the run is asserting, so a
mismatch fails loudly. `tkWeb -Dev -Fixture -Modules on` is what configures it.

**`--studio` starts its own servers, because it has to change one**. Its cases are what the
Gate 12 walks of the Studio's core, its card counts and its filter proved by hand: a config line left over from before the Studio
was core, a flag flipped under a running agent, and the Spaces card's boxes holding still. A flip
cannot be made against `tkWeb -Dev -Fixture`: that run carries the flags in `P20_FEATURES`, which
replaces `config.local.json`'s features on every read, so a `Config -Set` would land in the
checkout's own file and change nothing the agent serves. So the mode (`web/tests/smokeStack.mjs`)
copies the package's runtime parts -- the agent, the module, its scripts and config -- into a
scratch folder under the OS temp directory, copies `Tests/fixtures/hub-spaces/config.local.json` (the
dead `"features": { "studio": false }`) in beside them, and starts that copy's agent as a test run
(the run marker, no `TEAMS_WEBHOOK_*`, `PROMPTS_ROOT` at `Tests/fixtures/hub-spaces/hub`, the Space
through `P20_ACTIVE_SPACE`, and no `P20_FEATURES`) with a Vite of this checkout's `web/` proxying to
it. Every change after the start goes through `PUT /api/config`, the settings drawer's road, so the
bridge writes the scratch's `config.local.json` and nothing else; the servers are stopped and the
scratch removed when the run ends. Nothing needs to be running first. `--port=` and `--agent-port=`
choose the ports it takes (a free one each otherwise), `--python=` the interpreter (`python` on
Windows, `python3` elsewhere). Each flag write is a `Config` run through the bridge, so a run takes a
couple of minutes, most of it PowerShell starting. The New Space dialog's case (the fourth the mode was built for) is not
built: it needs a `gh` stand-in.

**`--matrix` is the same footing, wider** (`web/tests/smokeMatrix.mjs`): servers of its own on
`Tests/fixtures/hub`, Space `test`, with no seed. **The flag matrix** sets each module flag alone on
through `PUT /api/config` (the others written `false`) and opens a new browser context per pass, so
the requests it counts are that pass's own; the cases are `docs/SCENARIOS.md`'s "The nav, by module"
rows, named on each check. Team Agile mounts only on a Space answered *With agents*, so its pass
first writes the Space a GitHub address and that answer into the scratch package's local patch, through
the same writer (`answerWithAgents` in `smokeStack.mjs`); the Space stays `local`, so nothing asks the
tracker, and the passes after it run on that Space. **The flip** is `flipCase` again, on the Lounge -- a web-only module, so it
proves the browser half reads the flag per request with no agent route involved. **Storage**: with
Organize, the Lounge and Team Agile on, each surface that keeps a choice in the browser -- the Spaces filter
(`studio.spaces.filter`), the Reminders filter (`organize.reminders.bucket`), the theme
(`toolkit-theme`), the Lounge's tic-tac-toe (`toolkit-lounge-tictactoe`), the standup player's mute (`toolkit-narration-muted`) -- runs in a new context
with empty storage (its default, a choice, the choice after a reload) and in one where an init script
makes `localStorage` and `sessionStorage` throw on access, the shape of a browser with site data
blocked: the surface must be drawn with no page error and still answer a choice for the page's life.
The theme's choice in that context is printed as a `NOTE`, not held: `useCurrentTheme` re-reads
storage after a choice, so by its own comment the choice does not take there. Several minutes a run;
the default `npm run smoke` is unchanged.

**`--first-run` walks the first run's first move** (`web/tests/smokeFirstRun.mjs`, `npm run smoke:first-run`), on
servers of its own like `--studio`'s, with one difference: the hub is a COPY of `samples/hub` in the OS temp
folder, made the way `Start` makes it, and the Space is `demo`. The drag writes -- it runs `Move` through the
bridge -- so it cannot run on the committed fixture hub, and the package's own samples are never used in place.
It opens Demo's board and asserts the first tutorial card alone in Backlog and the other four alone in To do,
drags the first card's face onto the To do lane, waits for the file to appear in `demo/current/`, reads it back
(byte for byte the card that was in `demo/backlog/`: a pull is a rename), and asserts the board then draws it in
To do with Backlog empty. Six checks, about a minute; the scratch package and the copied hub are removed when it
ends. `Tests/Test-Start.ps1` walks the other four lessons through the CLI.

**`--a11y` is the accessibility audit** (`web/tests/smokeA11y.mjs`, `npm run smoke:a11y`), on the
same footing: servers of its own on `Tests/fixtures/hub`, Space `test`. Four passes -- every module flag
off, then every one on (written through `PUT /api/config`; the on passes run with the Space answered
*With agents* the matrix's way, so Team Agile's pages mount), each in the first light theme (`seaglass`,
`FIRST_LIGHT`) and in `aurora`, the theme put in `localStorage` (`toolkit-theme`) by an init script
before the app runs, the way a person who chose it arrives. Each pass opens every page the registry
mounts in that mode -- the core's routes (Home's tabs, the System page, a card, the review, the design
and docs rooms, the Studio) in both, each opt-in module's descriptor routes in the on pass, a route
with a parameter opened on the fixture hub's own file -- and runs axe-core (`@axe-core/playwright`, its
default rule set) on it. One thing is left out of every analysis, `[data-tabster-dummy]`: the
`<i tabindex="0" aria-hidden="true">` focus sentinels Fluent's tabster inserts around its focus roots,
which axe reads as `aria-hidden-focus` on every page and which are Fluent's markup, not ours -- the
exclusion goes if a Fluent version stops inserting them. It prints every finding grouped by impact (critical, serious, moderate, minor):
the page group, the route, the theme and mode, the rule id, the selector of each element named (with
its markup, cut short), and the rule's help URL; then any page that did not draw cleanly as a `NOTE`; then one line,
`smoke: a11y -- <n> critical, <n> serious, <n> moderate, <n> minor over <pages> pages`, a finding being
one rule on one page in one theme and mode. **It is a gate on serious and critical findings**: one of
either, on any page in either theme and either mode, fails the run (exit 1, after the list and a
`FAIL` line); moderate and minor are listed and counted, never failed; and a run that broke exits 1
too. It is not part of the default `npm run smoke` -- about ten minutes a run is too long for that --
so it stays its own script, `npm run smoke:a11y`, run before a change to the web UI is merged. A page
the registry adds is a row in its `PAGES` table.

**It also takes a viewport.** `--viewport=desktop` (1400x900, the default), `--viewport=mobile`
(430x932) or `--viewport=both`, which runs desktop and then mobile and tags every line with which
one it is. Each route visited adds one assertion in whichever viewport is current: the document is
never wider than the window (`scrollWidth <= innerWidth`). That catches a whole class rather than
one card: a fixed-width grid, or a themed background that stops at the content's width, shows on a
phone as a band down the right of every card.

## One toolkit per shell

The `tk*` verbs are global aliases. Two Toolkit checkouts -- or this one and any other toolkit
that publishes the same names -- imported into one session means whichever registered last owns
the name, and a green suite then proves nothing about the tree you are editing. So every run that
has to be about *this* checkout starts a fresh shell, limits `PSModulePath` to the package, and
imports exactly one manifest by path:

```powershell
pwsh -NoProfile -Command "`$env:PSModulePath = (Resolve-Path .); Import-Module ./Prompt20Toolkit/Prompt20Toolkit.psd1 -Force; tkTestToolkit"
```

**`-NoProfile` alone is not isolation.** Module auto-loading reads `$env:PSModulePath`, not the
profile, so a shim installed on the machine ([Quick start](QUICKSTART.md#install)) still answers for a name this checkout
never defined. Nor is setting the variable in the *parent* shell: pwsh prepends the user and
system module paths at startup, so a child inherits them straight back. It has to be set **inside**
the shell that runs the command, before the first command resolves -- which is what the line above
does, and what `Tests/Test-ExitCodes.ps1` does for every child process it spawns; a suite that skips
it can pass by exercising a different product entirely.

Run all four after installing on a new machine, and after changing anything. A green suite is what
makes the install trustworthy for real work.
