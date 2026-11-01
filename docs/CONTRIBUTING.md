# Contributing

ToolKit is an engineering studio for working on software: one board, one workflow and one Markdown file
per card, so the work leaves a record you own. This is the page to start from if you would like to
change it -- how to set up each of its three halves, how to run the tests, what a change has to meet,
how to file an issue, and how a pull request is read. Each section is short and links the document
that owns the detail, so nothing here is the only place a rule is written.

Participation is under the [code of conduct](../CODE_OF_CONDUCT.md). A vulnerability is reported
privately, as [`SECURITY.md`](../SECURITY.md) says, and never in a public issue.

## Start with an issue

Work is tracked in [GitHub Issues](https://github.com/johnfrog76/toolkit/issues). Search first -- the
bug or the idea may already be there -- then file one through a form under `.github/ISSUE_TEMPLATE/`:
a bug, an improvement or a question. Say what you saw, where, and on which commit; an issue that names
a commit and a path can be picked up cold. If you would like to build the change yourself, say so in
the issue and talk it through before you start. A commit for the change says `Refs #N`, so the issue
and the code find each other. The maintainer closes the issue when the fix merges.

### The issue's life

1. File it with `agentic/new-issue.prompt.md`: search first, then one six-section body (Problem,
   Location, Severity, Fix, Source, Status), a type label and a severity label. A filing is an issue
   only: no file is written beside it.
2. Work it: a commit says `Refs #N`, and the documentation changes in the same commit.
3. Close it through the verb from a Space whose tracker is this repository, `tkCloseItem <n> -Comment "..."`, the comment
   naming the commit and any `VERIFY.md` Gate 12 row. The person who merges closes the issue, so
   closed means merged; a defect found afterwards is a new issue, never a reopen. A fix only another
   host can prove stays open with the `verify-close` label and its Gate 12 row until that host walks it.

A bug or improvement gets an issue before it gets a fix, and the issue names the commit it was seen
on: one that cannot is an impression, not a report. A closed issue is never deleted; the closed list
is the record the next diagnosis reads. UX is a kind, not a type: a UX issue is an `enhancement`
whose Problem opens with `**Kind: UX.**`. The CLI, the agent and the web UI are one repository and
one backlog, so an issue in any half is filed here with Location naming its paths. A defect found
on a host that did not build the fix is filed, not fixed there. With no `gh` at hand, the finding is
written on the card being worked and filed when the tracker answers. A design that is going to be
built is worked in the maintainer's hub, not in this tree; a contributor opens an issue and the
discussion lives there. A product that keeps its own notes and specs in its tree uses `design/` and
`spec/` as [`docs/hub/design.md`](hub/design.md) describes. [`docs/KNOWN-GAPS.md`](KNOWN-GAPS.md)
is the reader-facing list of seams left open, and the issue list is the backlog behind it.

## Set up the three halves

The repository holds three things that share one configuration and one store of cards, and the first
is the only one you need to start: **the CLI** (PowerShell, the `tk*` commands), **the agent**
(FastAPI, in `agent/`) and **the web UI** (React, in `web/`). The web UI reads through the agent, and
nothing in the web half changes a card except through the CLI, so every write has one implementation
([how the halves fit](ARCHITECTURE.md)). [Quick start](QUICKSTART.md) has the requirements and the
supported platforms; in short:

```powershell
Import-Module ./utilities.psm1 -Force                # the CLI, in this shell
tkInstallAutoload                                    # the CLI, in every future shell
tkStart                                              # a hub of sample cards to work against
python3 -m pip install -r agent/requirements-dev.txt # the agent, once. On Windows: python or py -3
cd web; npm ci; cd ..                                # the web UI, once
tkWeb -Dev                                           # start the agent and the web UI together
tkWeb -Stop                                          # and end them
```

Commands are `{prefix}Command`, and the prefix is configurable -- `tk` by default; `tkMenu` lists the
live surface and `<command> -Help` describes any one. Commands load by themselves once
`tkInstallAutoload` has run; there is no import line to add, and a command that is not recognised
means `tkInstallAutoload -Force`. Each half also has its own README for the detail:
[`agent/README.md`](../agent/README.md) and [`web/README.md`](../web/README.md).

Every pull request runs a check, `.github/workflows/verify.yml` (also on every push to `main`, and from the Actions tab's button): the agent's, the CLI's and the web UI's runners on Ubuntu. That is the check a pull request has to pass, alongside CodeQL. The Windows job -- the CLI typed from Windows PowerShell 5.1 and the two browser smoke modes that start their own servers (`smoke:matrix`, `smoke:a11y`) -- does not run on an ordinary pull request or a push to `main`: it runs once each weekday evening against `main`, from the Actions tab's button, and on a pull request that carries the `ci` label, so label a change that is heavy on PowerShell or the browser when it wants that proof before it merges. The label takes effect on the pull request's next push (or reopen); to run Windows on a branch right away, use the button on that branch (`gh workflow run verify.yml --ref <branch>`). A label added to an open pull request starts nothing by itself, on purpose: a label must never cancel the running checks. A scheduled failure is filed as an issue with the run's URL and the next fix to merge carries the repair. Each step failed on a failure, a skipped half or a run that counted nothing, read from the runner's own summary line ([Testing](TESTING.md), "In CI"). It needs no secret, and a suite that does not pass without one is a defect of the suite. It does not run each suite as a file under 5.1, the agent's or the web UI's runners on Windows, or the smoke against servers you started, so a change to anything only those can show is still proved by running them, and the pull request says which ran.

The web half (`web/`) runs on **Node 24, the active LTS, from 24.22.0**. The version is stated twice:
`.nvmrc` at the repository root (`24`, the line) and `web/package.json` `engines.node` (`">=24.22.0 <25"`,
the floor and the line). The floor is there because on Node 24.21 a jest worker in `npm test` is sometimes
killed by a segfault in V8's garbage collector -- `Test suite failed to run` on a suite whose tests all pass,
a different suite each time -- and 24.22.0 does not do it. `.nvmrc` stays `24`, so `nvm use` and CI take the
newest 24 release. To move an older 24 up: `nvm install 24 && nvm alias default 24`. There is
one `.nvmrc`, at the root, not a second copy in `web/`: `nvm use` (nvm-sh) finds it from `web/` by walking up,
and on nvm-windows, which does not read the file, run `nvm install 24` then `nvm use` with the version it
installed. Without `engine-strict`, `npm ci` on an older Node warns (`EBADENGINE`) rather than refusing.

## Run the suites

One command runs all three halves and prints one verdict:

```powershell
tkTest                   # the agent, the CLI and the web UI
tkTest -Half agent       # one half: cli, agent or web
```

Or run the half you touched with its own runner -- `tkTestToolkit` for the CLI, `python3 -m pytest Tests/`
for the agent (on Windows: `python` or `py -3`), and `npm test` from `web/` for the web UI --
and `npm run smoke` from `web/` when a change shows in the browser. Run the ones your change touches,
and read the summary line rather than the total: a skip is not a pass. What each suite guards, the
counts a green run prints, and the one rule for a shell with two checkouts in it (one toolkit per
shell) are in [Testing](TESTING.md). The runners remove any `TEAMS_WEBHOOK_*` variable from their own
processes, so a suite never posts to a real channel.

## The refusal contract

A command that refuses says why once, and the exit code carries that across the boundary between a
script in `Scripts/` and the wrapper in `utilities.psm1` that ran it. A script that refuses calls
`Write-CliError`, which prints the `Error:` and the `Hint:`, and exits **2**; the wrapper then prints
nothing on top. Any other non-zero exit is a failure that said nothing, and the wrapper explains it
with a generic block. Exit 0 is success and nothing else is. A new script dot-sources
`Scripts/Initialize-CliFallbacks.ps1` near its top, before its first refusal, so it refuses the same
way when it is run with no module loaded; it does not carry its own copy of either helper. A switch
you add to a script goes in three places -- the script's `param()`, the wrapper's `param()` in
`utilities.psm1`, and the verb's `usage` in `config.default.json` -- and `tkTestToolkit -Menu`
checks the three against each other. The full contract is [`AGENTS.md`, "The refusal contract"](../AGENTS.md#the-refusal-contract).

## The documentation rule

Documentation changes in the **same commit** as the behaviour it describes, never in a follow-up.
Stale documentation is a defect of the same severity as a failing test, and it is the one defect the
tests cannot catch. Each subject has one document that owns it, and a change to a verb, a route, a
path or a rule changes that document: a command, switch or error message in [The CLI](CLI.md); a
configuration key in [Configuration](CONFIGURATION.md); a suite or a runner in [Testing](TESTING.md);
how the halves fit in [the agent and the web UI](ARCHITECTURE.md); an add-on in
[its module document](modules/README.md); what a file in the hub carries in [`docs/hub/`](hub/README.md).
The [README's Documentation table](../README.md#documentation) is the map, and
[`AGENTS.md`, "Documentation is part of the change"](../AGENTS.md#documentation-is-part-of-the-change) holds the full table. Something left
open on purpose is a row in [Known gaps](KNOWN-GAPS.md), not a comment in the code. A change a user
would notice also gets a line under `[Unreleased]` in [`CHANGELOG.md`](../CHANGELOG.md); how that
section becomes a release is [`AGENTS.md`, "A release is a tag on main"](../AGENTS.md#a-release-is-a-tag-on-main).

## How a pull request is reviewed

A pull request opens with the template in `.github/PULL_REQUEST_TEMPLATE.md`: what changed and which
issue it refers to, how it was tested, and which documents changed. A maintainer reads it against the
rules below, and a change is ready when:

- the runners for the half it touches are green, and the pull request says which it ran and, for any it
  could not run, which and why;
- lint is clean ([Lint](#lint));
- the documentation moved with the code ([the documentation rule](#the-documentation-rule));
- PowerShell still parses on 5.1, and no committed file carries anything personal
  ([The rules a change meets](#the-rules-a-change-meets)).

Review comments arrive as threads on the pull request. Answer each one in its thread, push the fix,
and resolve the thread once it is dealt with; a maintainer merges once they are settled.

Dependabot opens pull requests for the web UI's npm packages, the agent's pip requirements and GitHub Actions, weekly: minor and patch updates together, one pull request per ecosystem, and each major update on its own. A Dependabot pull request meets the same bar as any other before it merges: the runners for the half it touches are green (`npm test` and `tsc` for `web/`, `python -m pytest Tests/` for `agent/`), and a major update is read for its breaking changes first.

## Dependencies and the audit

The agent's Python requirements are **floors**, not pins: `agent/requirements.txt` and `agent/requirements-dev.txt` say `>=` the version the suites pass on, and Dependabot moves them. The one exception is the linter. `ruff` is pinned exactly (`==`) in `agent/requirements-dev.txt`, so "zero findings" means the same thing tomorrow; moving it is a pull request of its own that fixes whatever the new version finds. The Python version is stated in [QUICKSTART.md](QUICKSTART.md), "Requirements" (3.12 or newer), in the head of both requirements files and as `target-version` in `ruff.toml`.

`pip-audit` checks the requirements against the Python advisory database. It is not itself a requirement, since what it knows comes from the database and not from its version, so it goes in a separate environment and reads the requirements file, which it resolves in a throwaway environment of its own:

```bash
python -m venv ~/.venv-audit
~/.venv-audit/bin/python -m pip install pip-audit    # Windows: %USERPROFILE%\.venv-audit\Scripts\python.exe
~/.venv-audit/bin/python -m pip_audit -r agent/requirements-dev.txt
```

`No known vulnerabilities found` is clean, and a change that raises or adds a requirement runs it before it merges. The Ubuntu job of `.github/workflows/verify.yml` runs both audits -- this one and `npm audit --omit=dev --audit-level=high` in `web/` -- on every run, so an advisory fails a run the day it is published. A requirement that changes also keeps `python Scripts/third_party_notices.py --check` true (see "A new web dependency keeps the bundle permissive" below).

## The rules a change meets

The rules below are the ones review checks. Each is held by a suite where a suite can hold it.

**A new web dependency keeps the bundle permissive.** `npm run license:check`, from `web/`, fails when a production dependency is under a license outside MIT, ISC, Apache-2.0, BSD-2-Clause, BSD-3-Clause, 0BSD or MIT AND ISC. It runs `license-checker` through `npx` at a pinned version, so it needs the network the first time and adds nothing to the lockfile. A dependency that changes the answer is added to [`THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md) in the same commit, and a package under a copyleft license does not go in the bundle. One package is excluded from the check by name and version: `tween-functions@1.2.0`, the one dependency of `react-confetti` (the Team Agile page's confetti), whose `package.json` says only `BSD` -- which the checker reads as `BSD*` -- while its `LICENSE.txt` is the three-clause BSD text, word for word. The pin is the point: a new version fails the check again until someone reads its license. The page is held true by `python Scripts/third_party_notices.py --check`, which `Tests/test_third_party_notices.py` runs: the web list is generated from `web/package-lock.json` (`--write` rewrites it after a dependency change), every agent requirement must be named, and a font, picture, sound or `web/public/` file added to the repository must be given a row under "Fonts, artwork and audio" with its source, or the check names it.

PowerShell scripts must parse on **PowerShell 5.1**. That rules out:

`&&` and `||` · ternary `?:` · null-coalescing `??` and `?.` · `ConvertFrom-Json -AsHashtable` ·
three-argument `Join-Path` · `[System.IO.Path]::GetRelativePath` · em and en dashes inside
double-quoted strings (Windows-1252 misreads them -- use ASCII `-` and `--`)

Use `Resolve-Path -Relative` where you would reach for `GetRelativePath`.

**Adding a command** is three edits: the script in `Scripts/`, an entry in `$script:ModuleState.CommandMap` in
`utilities.psm1`, and a description in `config.default.json`. Nothing else, and that includes the
web half -- the agent's bridge derives what it may run from that same `$script:ModuleState.CommandMap`
([the agent overview](ARCHITECTURE.md#the-bridge)), so the new verb is callable from the browser with no backend change.

**Adding a command to an opt-in module** is a different three, and none of them touches the core:
the script in `Scripts/`, a row and a `Help` entry in that module's `Config/<module>.commands.psd1`,
and a wrapper in the sibling `.ps1`. The loader merges them before `Register-PromptAlias`, so the
verb gets its alias, its menu line, its `-Help` and its bridge entry for free, and the module's help
never reaches `config.default.json`. The contract is
[How a module contributes commands](modules/README.md#how-a-module-contributes-commands-d-cm).

**Never hardcode a prefix.** Write `{cliPrefix}` in any description, usage string or example, and
it resolves to whichever prefix is registered. Every render path goes through one resolver,
`Expand-CliPrefix` -- so a raw `{cliPrefix}` reaching output is a bug in the render path, not in
the metadata. The resolver expands both `{cliPrefix}` and the older `{p}`, every render path calls
it, and the `Menu` suite asserts that no `{token}` survives any row of `-All` or
`-Markdown`, with the module flags off and on.

**Nothing personal in committed files.** This tool is meant to be forkable, so a clone must be
usable by someone who is not you: no real email addresses, no ADO org URL or tenant id in
`config.default.json`, no absolute machine paths, no one's name as a parameter default. The
`Portability` suite enforces all four, across **all three halves**: the CLI, `web/src` and
`web/tests`, and `agent/`. If a line genuinely needs an exception -- a third-party tool's fixed
install location, say, or an SSH remote prefix that has an `@` in it -- append
`# portability-ok: <why>` to it, or `// portability-ok: <why>` in TypeScript. A marker with no
reason after it does not count; the point is to make the exception argued, not silent.

**A seam is a roadmap row, not a comment.** No work-marker comment (the four words `Test-Portability`'s Clause 13 matches: the usual to-do, fix-me, hack and triple-X tags) and no commented-out code ships. Something half-built or knowingly left open is a row in [`docs/KNOWN-GAPS.md`](KNOWN-GAPS.md) with what a reader sees when they hit it, and an issue; dead code is deleted, because the history keeps it. Clause 13 holds the marker words at zero; the commented-out-code half is held by review, since a comment line that ends in a semicolon is as often a sentence as a statement.

**A comment is written for a stranger.** No date, no person's or agent's name, no nickname for a host (say Windows or macOS), no pointer into a private archive, no private repository, no machine path, and a tracker number only inside a closed parenthetical that the export can drop. Say the rule, not who said it or when. `Test-Portability`'s Clause 14 reads the comments of every file type the tree uses (the trailing ones too, and the JSON `_` keys) and fails naming `file:line`.

**Never catch and continue silently.** An empty `catch {}` around a fallback hides the very
failure it was meant to survive. Report it.

**A new CLI suite ends its top-level `try` with a catch that records the error as a FAIL**, and calls
only `Assert-*` helpers it defines or loads -- `Test-Portability` refuses either shape
([TESTING.md](TESTING.md), "A suite ends with a catch").

## Lint

Lint is clean, at the settings committed in the repository, and a change keeps it that way. A warning
is a finding like an error: the bar is zero of either.

| Half | From | Command | Settings |
| --- | --- | --- | --- |
| web | `web/` | `npm run lint`: `eslint src`, then `prettier --check src` (CI runs it) | `web/eslint.config.js`, `web/.prettierrc.json`, `web/.prettierignore` |
| agent | the repository root | `ruff check` | `ruff.toml` |
| agent | the repository root | `ruff format --check`; without `--check` to apply | `ruff.toml` |
| CLI | the repository root, in `pwsh` | the PSScriptAnalyzer command below | `PSScriptAnalyzerSettings.psd1` |
| documentation | `web/` | `npm run lint:md` (markdownlint-cli2 over every document in the repository: the root `README.md` and other root documents, `docs/`, the `design/` and `spec/` READMEs, `web/README.md`, `agent/README.md`) | `.markdownlint-cli2.jsonc` |

A Prettier failure names the files: fix them with `npx prettier --write <file>` (`npm run format` for all of `web/src`), then run `npm run lint` again.

`.gitattributes` pins `web/src` to LF on disk, which is what Prettier's `endOfLine` expects, so a Windows checkout with `core.autocrlf` true passes `--check`. A clone that predates that line keeps its CRLF files until they are checked out again.

ruff covers `agent/` and the suites in `Tests/*.py`, the repository's only Python, and comes with
`agent/requirements-dev.txt`, pinned exactly. The line is 120 for the formatter and for `E501` alike. The rules
are ruff's defaults plus pycodestyle's errors; each rule set aside is named in `ruff.toml` with its
reason, and a blind `except Exception` that degrades on purpose says why on its own line
(`# noqa: BLE001 -- <why>`).

PSScriptAnalyzer covers every `.ps1`, `.psm1` and `.psd1` outside the vendored and generated folders
`Tests/ScanExclusions.ps1` names -- the same list the static suites skip, so a checkout's
`node_modules` or an agent's worktree under `.claude/` is never read. Install it for your user, at
the version the settings were measured with, then run it from the repository root:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser -RequiredVersion 1.25.0
. ./Tests/ScanExclusions.ps1
Get-ChildItem -Recurse -File -Include *.ps1, *.psm1, *.psd1 |
    Where-Object { -not (Test-ScanExcluded $_.FullName.Substring($PWD.Path.Length)) } |
    Invoke-ScriptAnalyzer -Settings ./PSScriptAnalyzerSettings.psd1 -Severity Warning, Error
```

No output is clean. The rules are PSScriptAnalyzer's defaults, plus `PSUseCompatibleSyntax` for 5.1
and 7; each rule set aside is named in `PSScriptAnalyzerSettings.psd1` with its reason --
`Write-Host` because the CLI colours its output, the global functions and variables because the verbs
are global on purpose. Where a rule is wrong for one function or one parameter, the
`[Diagnostics.CodeAnalysis.SuppressMessageAttribute('<rule>', '<target>', Justification = '<why>')]`
on that `param()` block says why; one without a `Justification` does not count.

Fix the code, not the rule. Where a rule is wrong for one line, the disable comment names the rule
and the line above it says why -- `// eslint-disable-next-line <rule>` with no reason beside it does
not count, for the same reason a `portability-ok` marker needs one.

## Naming the Python interpreter

Write `python3` and say, on the same line or in a note beside the first command, that on Windows it
is `python` (or `py -3`): there `python3` is the Microsoft Store alias, not an interpreter. A document
followed on Windows (`VERIFY.md`) writes the Windows form first. Code never prints the literal --
`Scripts/Resolve-Python.ps1` finds the interpreter and messages name what it found
(`Start-Agent`, `Update`). `tkTestToolkit -Menu` fails a document under `docs/`, the READMEs, `AGENTS.md`
or `VERIFY.md` that says `python3` and never names `python` beside a mention of Windows.

## Writing a menu description

A description is what a person scans in `{prefix}Menu`, so it is one dense line: what the verb does,
at most 53 characters after `{cliPrefix}` is expanded (the row starts at column 27, and 53 is what fits
an 80-column window; aim for 40). No flags, config keys, examples, reasons or edge cases -- those go
in `usage`, `switches`, `examples` and `notes`, which `-Help` renders. No trailing period, no markdown,
and "card" rather than "prompt". `tkTestToolkit -Menu` holds the length and the shape for every core
and module verb. The rule is there because a wrapped row starts again under the command names and
the menu stops reading as a list; the reader cannot make the window wider.
