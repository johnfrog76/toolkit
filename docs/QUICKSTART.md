# Quick start

From a fresh clone to a first card, then to the web UI. This is the short path, and every step
links to the document that owns the detail. [`VERIFY.md`](../VERIFY.md) is the long way round:
the same install gate by gate, with what you should see at each one.

## Requirements

| | |
| --- | --- |
| **PowerShell** | 5.1 (Windows built-in) or 7+. Both supported; the installer sets up both. On 5.1 the module turns TLS 1.2 on at import, so a locked-down machine that still leads with TLS 1.0 can reach Azure DevOps, the Anthropic API and Teams. |
| **git** | Required by `Sync` and `ThreadHash`. Everything else degrades gracefully. |
| **Azure CLI** (`az`) | Only for ADO commands. Sign in with `az login`. |
| **Python** 3.12+ | Only for the agent (`agent/`). The CLI never calls it. Runtime deps: `agent/requirements.txt`. |
| **Python test deps** | Only for `python3 -m pytest Tests/` (Windows: `python` or `py -3`): `pytest` and `httpx` (`fastapi.testclient` imports httpx), and `ruff`, the Python half's linter. All three live in `agent/requirements-dev.txt`, which pulls the runtime file in. |
| **Node** 24.22.0+ | Only for the web UI (`web/`). Node 24 is the active LTS; `.nvmrc` at the repository root and `web/package.json` `engines` both say so, and `engines` sets the floor at 24.22.0, because on 24.21 `npm test` is sometimes broken by a crash in Node itself ([Contributing](CONTRIBUTING.md)). `nvm install 24 && nvm alias default 24` moves an older 24 up. |
| **Playwright browsers** | Only for `npm run smoke`. `npm ci` installs the library; the chromium binary lives in a machine-level cache and needs `npx playwright install chromium` once. |
| `ANTHROPIC_API_KEY` | **Optional.** Only for `AddPRReview` and the agent's `suggest` route. Everything else works without it. |

Without `az` you still get the full local workflow -- see [Tiers](CLI.md#tiers-what-works-without-ado).

## Supported platforms

What has been run, and where. A row says "verified" only where someone ran it and the record is named.

| Platform | Status | Where it is verified |
| --- | --- | --- |
| **macOS** | Supported, verified | The maintainer's Mac: the CLI, agent and web suites on every change ([Testing](TESTING.md)) |
| **Windows**, with PowerShell 7 and with Windows PowerShell 5.1 | Supported, verified | A Windows PC, walked by hand: [`VERIFY.md`](../VERIFY.md), Gate 12, "Windows install and test", and its "Rows added by a fix" |
| **Linux** | **The suites, in GitHub Actions** | `ubuntu-latest`: the CLI's suites, the agent's and the web UI's have run green there (`.github/workflows/verify.yml`, [Testing](TESTING.md), "In CI"). The first-run path (`Start`, the web UI in a browser) has not been walked on a Linux machine |

| Runtime | Version | Where it is verified |
| --- | --- | --- |
| **PowerShell 7** | 7.6 | Both hosts: 7.6 on the Mac and on the Windows PC |
| **Windows PowerShell** | 5.1, the floor: every script must parse and run on it | The Windows PC only (5.1.26100), under `powershell.exe`: `Test-PS51Compat`, `Test-Portability` and the Gate 12 rows. Nothing on a Mac can run it |
| **Python** | 3.12 | Both hosts: 3.12.4 on the Mac and 3.12.10 on the Windows PC. 3.10 and 3.11 are not run by anything, so they are not claimed; the floor rises or falls with what runs |
| **Node** | 24, the active LTS, from 24.22.0 (`.nvmrc`, `web/package.json` `engines`) | The Mac: `npm ci` and `npm test` on Node 24.22.0, the recorded web counts. The Windows PC ran them on 24.21, below the floor; its run on 24.22.0 or later is a row under [`VERIFY.md`](../VERIFY.md)'s "Rows added by a fix" |
| **Docker image** (`web/Dockerfile`, `web/docker-compose.yml`) | Builds on `node:24-alpine`, serves from `nginx:alpine` | The Windows PC: `docker compose build` and the smoke against the running container, published on `127.0.0.1:5174`. Linux hosts: see the trust model's note on `host.docker.internal` |

---

## Install

From a clone of this repo:

```powershell
Import-Module .\utilities.psm1 -Force   # bootstrap: registers commands in THIS shell only
tkInstallAutoload                       # persistent: registers them in EVERY future shell
```

The first line is a one-time bootstrap. The second installs a module shim into your PowerShell
module path so commands autoload in any shell -- including ones that never run a profile, such as
agent tool calls, `pwsh -c`, and CI.

On Windows it installs to **both** host module directories, because they differ:

| Host | Module path |
| --- | --- |
| PowerShell 7 | `Documents\PowerShell\Modules\Prompt20Toolkit` |
| Windows PowerShell 5.1 | `Documents\WindowsPowerShell\Modules\Prompt20Toolkit` |

Verify from a **new** shell, with no profile:

```powershell
pwsh -NoProfile -c "tkStatus"
powershell -NoProfile -c "tkStatus"     # Windows PowerShell 5.1
```

If a command is not recognised, re-run `tkInstallAutoload -Force`. To bring the Toolkit itself up to
date later, `tkUpdate` pulls it (fast-forward only), re-imports it, and tells you if the shim needs
that re-install; `tkUpdate -Sync` also syncs your prompt store afterwards.

A Demo you copied out **before the sample cards had covers** keeps a bare board after the pull: `tkUpdate`
notices it (`N sample cards in this hub have no cover  ->  tkCover -Samples`) and writes nothing. Run
`tkCover -Samples -WhatIf` to see which cards, then `tkCover -Samples` to dress them. It gives a sample card
its picture only when the card has no `**Cover:**` line; a card you added, or gave a cover of your own, is
left alone, and so is any Space that is not one of the samples'.

> `Import-Module` affects only the process that runs it. A command working in one shell but not
> another almost always means autoload was never installed -- not that anything is broken.

---

## The first run: one command

```powershell
tkStart          # a hub of sample cards in ~/toolkit-hub, this machine pointed at it, and the web UI open
```

Before it, a fresh clone says so on its first import -- `This machine is not set up yet ... Run
tkStart for a sample hub` -- a notice, not a warning: nothing is wrong, nothing is configured yet. It is for a person
at a terminal: the agent's bridge sets `TOOLKIT_QUIET_STARTUP`, and then the import prints nothing.

That is the whole setup on a new machine. `tkStart` copies the sample hub that ships in
[`samples/hub`](../samples/hub) out to a folder you own (`-Path` to choose it), writes
`promptsRoot` and `activeSpace` for you, switches the four opt-in modules on so there is a whole
product to look at -- every sample card wearing a cover picture, so the board reads as a board -- and opens the UI. The sample organisation, **Demo**, is `local`: it works from
the files alone and never contacts Azure DevOps, so this needs no login, no `az` and no network.
Your real Space is added when you want it: the **+** on the **Spaces** card in the web UI's **Studio**
tab lists your GitHub repositories (or takes `owner/name`, or your own cards with no tracker), and
`tkNewSpace -Repo owner/name` does the same from the terminal ([Adding a Space](CONFIGURATION.md#adding-a-space)).
The Home page's connect tips connect the demo Spaces instead.

Demo is one of three demo Spaces, one per grain, each an invitation and none required. The
**GitHub demo** is the same product tracked on a small public repo: it is `local` too until you want
it, and the tip at the foot of Home -- or `tkConnect github-demo` -- connects it once `gh auth login`
has run, or points it at a repo of your own. The **Azure demo** is ready for YOUR Azure DevOps
organisation: give it the address (its tip, or `tkConnect azure-demo -Address https://dev.azure.com/<org>`)
and sign in with `az login` ([the demo Spaces](modules/ado.md#the-demo-spaces-one-per-grain)).

Above the tabs, a banner offers **Introducing ToolKit**, a nine-slide narrated deck: that is the
*watch*. Watch it or dismiss it, and the banner does not come back (`firstRun.welcome`, in
`docs/CONFIGURATION.md`).

Then the *do*, about ten minutes on the Demo board, with no account anywhere. Five tutorial cards wait
on it, and each is finished by doing the thing it teaches -- a thing the board already reads, so there
is nothing to dismiss and no progress kept anywhere but the cards themselves:

1. **Start here: pull me onto the board** (`Task H3RE`) is the one card in **Backlog**. A card is
   planned until you pull it, and the board reads the folder: drag it to **To do**, and the file moves
   from `demo/backlog/` to `demo/current/` (`tkMove H3RE -To Active` from a terminal). It also says what
   a card is -- one Markdown file, the record of the work -- and that its lane is worked out from the file.
2. **Open me and tick my boxes** (`Task T6CK`): a card is a document, and the bar on it counts every
   checkbox in the file. Done when every box is ticked.
3. **Find out one thing and write it down** (`Spike F7ND`): a Spike ends in a finding, not code. Find
   where the card lives on your disk, write it under **Findings**, and tick its one box.
4. **Say "look at this"** (`User Story R3VU`): review is a moment you record. Drag it to **Waiting**;
   that writes a `**Review:**` line into the card (`tkMove R3VU -To CodeReview`). On a project with a
   repository, a pull request does the same by itself.
5. **Drop me on Done** (`Bug D9NE`): a card travels one way. Dropping it on **Done** moves the file to
   `demo/archive/` and stamps the day it closed (`tkArchive D9NE`). Then drop the three finished ones
   on Done too, and the **To do** lane is empty: the first run, walked.

The rest of Demo is there to look at: RecipeBox's cards in the other lanes, a reminder due today in
Organize, and the Studio's **Hub Designs**, four designs about RecipeBox, one in each state of the
lifecycle -- a note still being thought about, one that graduated to a spec, a completed pair whose spec
points at a document in the hub's `docs/`, and a dropped one with its reason.

The last card ends at the *make your own*: press **+** and make your first real card. It lands in
Backlog, where the first card started. If Azure DevOps is your world, the Connect card on Home is where
it starts.

It never overwrites: a machine that already has a hub keeps it (`tkStart` just opens the UI), and a
folder with anything in it is refused. `tkStart -WhatIf` says what it would do.

The rest of this page is the same setup by hand, for a hub you already have.

## Point it at your prompt store

The tool is here; your prompt files live somewhere else. Tell it where, then ask it what it sees:

```powershell
tkConfig -Set promptsRoot=/path/to/your/prompts   # any folder: a git repo, a synced folder, a new empty one
tkSetup                                           # checks what the tool needs, and states the tier -- no az is a note, not a failure
tkEnv                                             # machine, tier, hub, active org, and what is switched on
```

`tkConfig` is the one writer for settings: it creates `config.local.json` (gitignored, yours) as a
sparse patch and never touches the committed `config.default.json`. The shipped active Space is the
**Azure demo** (slug `azure-demo`): `local`, with no address, which is enough for everything below.
A GitHub repo is the first door -- `tkNewSpace -Repo owner/name` adds it as a Space of its own, and
`tkConnect github-demo` connects the GitHub demo --
and connecting the Azure demo to your Azure DevOps organisation is `tkConnect azure-demo -Address https://dev.azure.com/<org>`
(or the wizard at `/connect/azure-demo`, which the Azure demo's tip on Home opens). Pointing a Space at a real org by hand, adding your own orgs to the hub's `hub.json`, the feature flags and every
other key are in [Configuration](CONFIGURATION.md).

## A first card, with no ADO

Nothing so far needs `az`, a board or a network:

```powershell
tkNewPrompt -Title "Timeout on large files" -Type Bug   # scaffolds a card into {promptsRoot}/azure-demo/current/
tkStatus                                                # every open card and its derived state: Active
tkMenu                                                  # every command, most-used first
```

With `az login` and a real org configured, `tkNewPrompt <id>` builds the same file from the ADO
work item instead, and the rest of the loop -- `tkThreadHash`, `tkNewPR`, `tkGetPRComments`,
`tkReplyPR`, `tkArchive` -- is [The workflow](CLI.md#the-workflow). What works at which tier is
[Tiers](CLI.md#tiers-what-works-without-ado).

## The web UI (optional)

The CLI needs neither of the other two halves. To see the same store in a browser:

```powershell
python3 -m pip install -r agent/requirements.txt   # once. On Windows: python or py -3
cd web; npm ci; cd ..                              # once
tkWeb -Dev                                         # starts the agent and Vite, prints the URL, opens the browser
tkWeb -Status                                      # both halves, and the agent's health
tkWeb -Stop
```

[The agent and the web UI](ARCHITECTURE.md) is the overview; [`web/README.md`](../web/README.md)
and [`agent/README.md`](../agent/README.md) are the detail.

## Removing ToolKit

The install writes one thing outside the checkout: the module shim in your PowerShell Modules folder
(a link where it can, a copy otherwise), in up to two places on Windows -- the PowerShell 7 folder and
the Windows PowerShell 5.1 folder in the table above. One verb takes it back out:

```powershell
tkInstallAutoload -Remove -WhatIf      # print each path it would remove; remove nothing
tkInstallAutoload -Remove              # remove the shim from every Modules folder it is in
```

It prints each path it removes (`nothing to remove` when there is none), never touches the checkout a
link points at, and then checks in a cold `-NoProfile` shell, in each host, that the `tk*` commands no
longer resolve. `-Remove` and `-Force` together are refused: one deletes, the other replaces.

What stays, because it is yours: your prompt store (the hub), and `config.local.json`. Nothing here
reads or removes either. Delete the checkout afterwards, once the verb has run: the shim is what
pointed shells at it, and the verb is part of the checkout.

## Where next

| To | Read |
| --- | --- |
| Use a real ADO org, add orgs, switch on growth or communication | [Configuration](CONFIGURATION.md) |
| Learn the loop and look up a command | [The CLI](CLI.md) |
| Prove the install, or run the suites | [Testing](TESTING.md), [`VERIFY.md`](../VERIFY.md) |
| Understand the agent, the bridge and the web shell | [The agent and the web UI](ARCHITECTURE.md) |
| Switch on a module, or write one | [The modules](modules/README.md) |
| Change the Toolkit | [Contributing](CONTRIBUTING.md), [`AGENTS.md`](../AGENTS.md) |
