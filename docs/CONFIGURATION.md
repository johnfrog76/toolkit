# Configuration

Every setting the product reads: the three files it lives in, the one verb that writes it, and
which settings belong to the machine, the Space, the hub or the team. Read it to change a setting, to
add a Space, or to find out why a value is what it is. [Quick start](QUICKSTART.md) sets the two keys
a new machine needs; this is everything else.

**The word is Space.** ToolKit has Spaces to manage your GitHub issues, ADO work items, and
custom cards -- one Space per context, each a folder of cards in your hub, each with an address
that decides which tracker it talks to (or none). The product says Space everywhere a person
reads (D-G13), and so do the config keys --
`activeSpace`, `spaces[]`, `spaces.<slug>.status` -- with the older spelling still read and never
written ("The container's keys", below). Where this document says "org" it is naming Azure DevOps's organisation, the address a Space
may carry, not the container.

**`tkConfig` is the one writer.** It reads every setting and says which file it
came from, it writes the ones that are yours, and it refuses the ones that are
not -- so nothing has to be edited by hand, and the web UI's settings drawer
is a form over this verb rather than a second implementation ([the web UI overview](ARCHITECTURE.md#the-web-ui)).

```powershell
tkConfig                                  # every setting, with its source
tkConfig -Set email=you@example.com       # one machine key
tkConfig -Set features.growth=true        # one feature flag
tkConfig -Set spaces.acme.status=archive    # one org, in the hub
tkConfig -Set email=you@example.com,features.growth=true   # several pairs, comma-separated (-Set cannot be repeated)
tkConfig -Unset email                     # drop a local override
tkConfig -Schema                          # what may be set, and where it lands
```

Hand-editing still works and is still documented below -- the files are plain
JSON and nothing hides them. The verb exists because three files, two shapes of
`spaces` and a set of keys that belong to somebody else is more than a README
should have to hold in a reader's head.

Three files, and the split is the whole of it:

| File | Committed? | Holds | Written by |
| --- | --- | --- | --- |
| `config.default.json` | yes | Orgs, command definitions, defaults. Shared. | a commit, never `tkConfig` |
| `config.local.json` | **no** (gitignored) | Your machine: paths, active org, prefix, `email`, your feature flags. | `tkConfig -Set <key>=<value>` |
| `<promptsRoot>/hub.json` | it is your hub's | **Your orgs**, the hub-root folder names, `storeSync`. | `tkConfig -Set spaces.<slug>.<field>=<value>` |

`config.default.json` ships a **template** org, not a real one -- no ADO URL, no tenant, no
email. Nothing that identifies a person or an organisation is committed. Your real values go in
`config.local.json`, which patches the shipped org by slug:

```json
{
  "activeSpace": "azure-demo",
  "promptsRoot": "C:/ws/my-prompts",
  "quietStart": true,
  "spaces": {
    "azure-demo": {
      "name": "Contoso",
      "org": "https://dev.azure.com/your-ado-org",
      "tenant": "00000000-0000-0000-0000-000000000000",
      "projects": [
        { "name": "YourProject", "repo": "your-repo", "defaultBranch": "main" }
      ]
    }
  }
}
```

The older spelling, `activeOrg` and `orgs`, is still read ("The container's keys", below).

**The `org` address also decides the TRACKER.** A board carries one address, and the address names
which tracker would answer for it: blank is none (a local board), a `github.com` host is GitHub, and every other address is Azure DevOps. There is no `tracker` key to set; the rule
is `Scripts/Resolve-Tracker.ps1` and the agent's `tracker()`, held together by one shared table,
and `/env` serves the answer. Whether the tracker is CONTACTED is a separate question -- the Space's
`status` and the tier decide that.

The patch is sparse -- name any field you want to change and the rest of the shipped entry stands.
This is enforced, not just convention: the Portability suite fails the build if a real org URL,
tenant id or email reaches `config.default.json`.

## What `tkConfig` writes, and where

A setting has a **scope**, and the scope decides the file. `tkConfig -Schema` prints the whole
table; this is the shape of it:

| Scope | Keys | Goes to |
| --- | --- | --- |
| **machine** | `email`, `branchUser`, `activeSpace`, `promptsRoot`, `wsRoot`, `agenticExtensionPath`, `commandPrefix`, `storeSync`, `quietStart`, `suppressDeprecationHints`, `menuResetTimestamp` (the stamp `{prefix}Menu -Reset` writes through this command; `-Schema` names it and `-List` leaves it out), `web.agentPort`, `web.corsOrigins`, `ai.model`, `features.<flag>`, `aliases.<Name>.path` / `.description` / `.display` | `config.local.json`, created as a sparse patch if it is not there |
| **org** | `spaces.<slug>.name` / `.status` / `.orgType` / `.org` / `.tenant` / `.promptsFolder` / `.projects` / `.howIWork` / `.features.sprintAwareness` / `.features.suggestions` / `.features.trainingHoursPerQuarter` | the hub's `hub.json` -- or `config.local.json`'s `spaces.<slug>` patch with **`-Local`** |
| **hub** | `storeSync`, `folders.<name>` | the hub's `hub.json`, and only with **`-Hub`** |
| **default** | `commands`, `workItemTypes`, `cliVersion`, `managerWorkflow` | nowhere. These are the team's, and a `-Set` on one is refused by name |

Five things worth knowing before you use it:

- **A slug nobody has declared is how you add an org** -- and `tkNewSpace` is the easy way to do it
  ([Adding a Space](#adding-a-space), below), writing these same keys. `tkConfig -Set spaces.acme.name=Acme` appends
  an entry to `hub.json` carrying the two fields both loaders require -- `slug` and `promptsFolder`
  -- with `status: local`, so nothing contacts ADO until you give it a URL and say so. A slug the
  SHIPPED config declares (`azure-demo`, the Azure demo) is not new: `-Set spaces.azure-demo.org=<url>` writes a
  sparse patch -- `slug`, the shipped `promptsFolder` and the field you set -- that both loaders
  deep-merge over the shipped Space, so it keeps its name and its shipped status. Since the three demo
  Spaces shipped, that status is `local`, so an address set this way is not contacted until the Space is made active:
  `tkConnect azure-demo -Address <url>` writes both at once (an address implies active, D-W14), and is the
  Azure demo's one door. A machine that patched the address in before then reads `local` afterwards and
  needs that one `Connect` (or `-Set spaces.azure-demo.status=active -Hub`).
- **The Azure demo's slug was once `test`, and the old slug still works.** A machine's
  `hub.json` entry under `test` that carries no `name` -- the patch the two bullets above describe --
  is read as `azure-demo`, keeping its `promptsFolder`, so a connected Example's cards stay in
  `<hub>/test/`. A `config.local.json` patch under `spaces.test`, an `activeSpace` of `test`, and a
  slug typed to `SwitchSpace`, `Connect` or `Config` mean `azure-demo` too, and the verb says the new
  name once. One rule: an old slug means its new Space while no Space is declared under the old one --
  so a hub that declares its own `test` with a `name` keeps it. The map is `consts.json`
  `spaces.renamed`; `Resolve-P20RenamedSlug` and `renamed_slug` read it, held to one table,
  `Tests/fixtures/space-renamed/table.json`. Nothing moves a folder: a hub copied by `tkStart` before
  the rename keeps the Azure demo's sample cards in `test/`, which the shipped `azure-demo` (folder
  `azure-demo/`) no longer reads -- move them by hand if you want them there.
- **A Space is retired or removed, and its cards are never deleted.** Retiring one is `-Set
  spaces.<slug>.status=archive`, the value the web shell already renders as the retrospective view;
  removing one is `-Unset spaces.<slug> -Hub`, which takes its whole entry out of `hub.json` (refused
  for the Space you are in and for one `config.default.json` ships), and `-Unset spaces.<slug>` drops
  this machine's patch for it. `tkRetireSpace` and `tkRemoveSpace` are the verbs that run these
  ([Retiring or removing a Space](#retiring-or-removing-a-space), below). `-Unset` will not take a
  required FIELD away, even with `-Hub`.
- **A Space's `projects` is a field like the others.** The PR, work-item and dashboard reads iterate
  `projects`, and `NewPR` reads `defaultBranch` from it. `tkConfig -Set spaces.<slug>.projects="Name/repo;
  Other/repo2" -Hub` writes it, or a JSON array of `{ name, repo, defaultBranch }`; `tkConnect <slug>
  -Projects` is the wizard's writer, and the Configuration card takes the same text. A Space with
  none shows empty accounting cards, and the cards say so in their `reason` line.
- **Everything is validated before anything is written.** A `-Set` with a bad value, an unknown key
  or a key that belongs to `config.default.json` refuses with a stated reason, exit 2, and no file
  touched -- including the other pairs in the same run.
- **Every write is atomic and byte-stable**: a temp file renamed over the target, UTF-8 with no BOM,
  LF, two-space indent, the same on PowerShell 5.1 and 7. A half-written `config.local.json` is a
  toolkit that will not load, and `ConvertTo-Json` is two different formats on the two hosts. Byte
  stability also covers a key `-Set` was not asked to touch: PowerShell 7's `ConvertFrom-Json` reads
  an ISO-8601-looking string (`errorsAckedAt`, the stamp `{prefix}Log -Errors` writes) as a
  `[datetime]`, which would otherwise come back out re-serialised in .NET's own format. The reader
  passes `-DateKind String` where the parameter exists (7.3+) so every string round-trips as itself.

## A `config.local.json` that will not parse

A hand-edited file with a stray comma or a missing brace does not stop the toolkit; it makes the
machine behave as if the file were absent, so the shipped defaults answer (prefix, hub root, Space,
flags). That used to happen without a word. Now the module prints one warning,
`Failed to parse config.local.json (<the parser's message>). Using defaults only.`, and says it
**once per process**: the loader at import is the first to say it, and every other reader of the file
(the prefix, the hub root, the agentic extension path, the help ports, the menu's scores and the
recent-errors count) calls the same helper, `Write-P20ConfigParseWarning` in
`Scripts/Write-ConfigParseWarning.ps1`, which remembers the file in the process rather than in a
module variable. The readers still fall back to the defaults; fix the file and open a new shell. A
child `pwsh` (the web bridge, a test runner) is its own process and says it once for itself.

The agent behaves the same way: it starts on the defaults, keeps answering, and `GET /api/env` carries a
failing `configLoaded` check (the "Settings files" row) whose detail names the file and the parser's message. Fix the file and the
next request reads it again; no restart is needed. `POST /api/switch-mode` answers 409 with the same
sentence rather than overwrite a file it could not read.

That is every reader in the tree, not a list of six: the agent port, the Space lifecycle
read, the other scripts that look at the file when no module is loaded (`SwitchSpace`'s status,
`Connect`, `SendTeams`, `NewGrowth`, the review generator, the weekly billing script, the
prerequisites check) go through the helper too, the last few through `Read-P20LocalConfigJson`,
which returns `$null` for a file it cannot parse. A reader that **writes** the file does not fall
back, it refuses: `Menu -Reset`, `Log -Ack` and `SwitchSpace <slug>` print the warning and a stated
`Error:` saying nothing was changed, and leave the file's bytes alone, rather than write one key over
a file they could not read. `Config -Set` already refused a file that is not valid JSON and still
does. `tkTestToolkit -Config` holds the list: it walks every script's syntax tree, finds each
`ConvertFrom-Json` over `config.local.json`, and fails naming the file and line when its `catch`
neither calls the helper nor states a refusal, so a new reader cannot be added quietly. The same
file spelled with `/` or `\` counts as one file for the once-only rule.

When those three DO write, they write the way `Config` does: `Menu -Reset` sets `menuResetTimestamp` through
`Config` itself, and `SwitchSpace` and `Log -Ack` through its writer (`Write-ConfigJson` in
`Scripts/Write-ConfigJson.ps1`), so the file is UTF-8 with no BOM, LF, two-space indent and atomic on
both hosts, and a date-looking string comes back out as the string it was. The same syntax-tree walk
fails naming the file and line of any other write into `config.local.json` -- `Set-Content`,
`Add-Content`, `Out-File`, a `[System.IO.File]` write or a redirection -- in `utilities.psm1`, `Scripts/`
or `Config/`.

A file that **does** parse but holds a value that is not a date -- `menuResetTimestamp` (the menu's
scores) or `errorsAckedAt` (the error indicator) -- is not called unparseable. The warning names the
key and the value, `config.local.json's errorsAckedAt is not a date (nope). Ignoring it.`, once per
process per key, and the menu goes on without that marker.

## A module flag and an open shell

The agent and the web UI read a `features.*` flag on the next request. A shell does not: it registers
its verbs, its menu and its inventory when the module is imported, so a window that was open when you
flipped the flag keeps listing (and answering) the old set. It sees the flag in a new window, or after
the module is re-imported into it -- `tkUpdate` and `tkStart` both do that. `tkConfig -Set features.<name>=...`
ends with one line saying so. The other documents that say "no restart" mean the agent and the web UI
and link here.

Almost nothing needs a restart. The agent re-reads config on every request that touches it, and
`PUT /api/config` clears its two 45-second caches -- the ADO reachability probe and the resolved
identity -- after a successful write. The exceptions are `web.agentPort` and `web.corsOrigins`,
which are bound when the agent starts; `tkConfig` says so when you change one.

**`ai.model` is the provider profile**: the one model id every model call sends --
`AddPRReview` in the CLI, and the agent's `suggest` (a draft reply on the PR Comments page) and
`rewrite` (the notes tidy-up) routes, and Team Agile's standup dress (the worker sentences the
played view speaks, re-said in standup language and guarded so no fact is added). `config.default.json` ships a value; `tkConfig -Set
ai.model=<id>` overrides it on this machine, and `GET /api/env` reports the one in force as
`aiModel`. The KEY is not a setting: `ANTHROPIC_API_KEY` in the environment (or `CLAUDE_API_KEY`,
the fallback name `.env.example` documents), never a file this tool writes. The agent reads the SDK
lazily, so a machine without `anthropic` installed still starts and those two routes decline by
name (412) until `pip install -r agent/requirements.txt`. The standup is never refused for it: the
dress's decline is the same sentence, written to the usage log (`INFO`), its `spoken` is null and the
prose stands. With a key set, every new standup (a new set of groups) asks the model once; there is
no separate switch.

**`web.agentPort` reaches the whole product.** One resolver, `Scripts/Get-AgentPort.ps1`
-- `config.default.json` patched by `config.local.json`, last read wins -- is what `tkAgent` listens
on and what `tkWeb` hands to the two proxies that point at the agent and cannot read config: before
it launches Vite or `docker compose`, `tkWeb` exports the port under the contract's variable name
(`consts.json` `env.agentPort`, `P20_AGENT_PORT`); `web/vite.config.ts` reads that variable for the
dev proxy, and `web/docker-compose.yml` passes it into the nginx image, whose entrypoint writes it
into `nginx.conf.template`. `npm run dev` typed by hand reads the same two config files itself, so it
agrees with `tkAgent -Status`; a `docker compose up` typed by hand with nothing exported gets the
shipped default. So `tkAgent -Port <n>`, the launcher's own advice on a port conflict, gives a web UI
that reaches its agent.

**The container is handed the port at START, never at BUILD.** nginx does the
production proxying, so the number is substituted into its config by the image's entrypoint; the
builder stage does not have it and must not need it. `web/vite.config.ts` therefore resolves the
port only when Vite is SERVING -- `defineConfig` takes its function form and the proxy block is
spread in for `command === "serve"` alone, because the image copies `consts.json` and `web/` but no
config file, and a build that asked for the port would refuse.

- **`promptsRoot`** -- where your prompt files live. This is *not* this repo. Point it at your own
  prompt store: another git repo, a synced folder, anywhere on disk. The tool reads and writes
  `current/` and `archive/` beneath it.
- **`activeSpace`** -- which org entry in `config.default.json` every command scopes to. Change it
  with `tkSwitchSpace <slug>`; check it with `tkSwitchSpace Status`.
- **`isDemoDismissed`** -- `false` shipped. Every org that SHIPS is marked `"example": true` -- a
  property, not its slug: `azure-demo` / "Azure demo" (once "Example", and slug `test`) in `config.default.json`, and the sample hub's
  `demo` / "Demo" and `github-demo` / "GitHub demo" in `samples/hub/hub.json` (the owner:
  "whatever ships ... follow the same pattern"; the demo Spaces are
  [the add-on's](modules/ado.md#the-demo-spaces-one-per-grain)). Set this `true` (Settings: **Hide Demo**) and those orgs are left out of every list a
  person picks an org from: the web's switcher, Settings, the Reviews page's org chips (all read `/env`'s
  `config.spaces`, which the agent filters), and `tkSwitchSpace Status`. It is **never removed from
  config**, `tkSwitchSpace azure-demo` still works, and the org you are IN is always shown. One rule in each
  half -- `Scripts/Select-OfferedSpaces.ps1` and `offered_orgs` in `agent/core/config.py` -- held to one
  table, `Tests/fixtures/offered-orgs/table.json`. `tkStart` does not set it. Not an opt-in surface, so
  it has no row in the inventory.
- **`branchUser`** -- branch name prefix. Defaults to your OS username.
- **`email`** -- who "me" is, for the ADO lookups that filter by a person:
  `MyPRs`, `Dashboard`, `MyWork`, and the agent's `/api/prs`, `/api/dashboard` and
  `/api/work-items`. **Set it, and you will not depend on the fallback.** With it empty, both
  halves ask `az account show --query user.name -o tsv` instead -- which is right when you are
  signed in and slow when you are not, and a machine that has never run `az login` then has no
  identity at all. It is per machine by construction: `config.local.json` is gitignored and
  `config.default.json` ships `""` and must (the Portability suite fails the build over a real
  address). The System card's **Identity** row shows the address and whether it came from
  `config`, `branchUser` or `az`, and each of the three routes says so in place of an empty list
  rather than rendering a config gap as "no pull requests".
- **`quietStart`** -- suppress the import banner.
- **`storeSync`** -- `git` or `none`, and **the shipped value is `none`**: the tool writes files
  into a directory and has no opinion about what you do with it. `none` is why `Archive` can print
  `Archived. Store is not git (storeSync='none') -- nothing committed` and still have done its job,
  and why `Sync` on such a hub has nothing to commit and says so rather than failing. State
  derivation never reads git, so the *workflow* loses nothing -- and neither does
  **Daily**, which is built from the cards' own `**Created:**` / `**Closed:**` dates and uses git only
  to say which of those days a card was touched. Review generation is different: it
  reads `git log`, and cards created before the `**Closed:**` stamp existed can only be
  dated from history -- so set this to `git`, and keep the history, if you intend to generate
  reviews over an existing corpus. `config.default.json`'s `_storeSync` note is the same text.
  A hub that is not a repository is a **first-class** case, not a degraded one: `tkStatus` asks git
  once, skips it entirely, dates every card from the filesystem, and **exits 0** rather than leaving
  `$LASTEXITCODE` at git's own 128, so a script checking the code sees no failure.
  **It is also the one key the hub itself may declare** ([below](#the-hub-declares-its-orgs)):
  whether the store is a git repository is a fact about the *hub*, not about the machine reading
  it, so a hub kept in sync across two machines needs no per-machine switch. The order is the orgs'
  order -- `config.default.json`, then the hub's `hub.json`, then `config.local.json` -- so a
  machine that must never push sets `none` here and leaves the hub alone.

## `spaces[].features.trainingHoursPerQuarter` -- the quarter's training requirement

A whole number of hours, and the second key a Space may set under `features` (with `sprintAwareness`; the
list is `consts.json` `features.spaceScoped`). Org-scoped because it is a fact about one engagement: a
client may require eight hours a quarter and another nothing. **Unset means no requirement, and nothing is
shown** -- the Growth page has no line, `GET /api/growth` answers `trainingQuarter: null`, and `tkEnv`
lists it as `not configured`. Set, the Growth page (with `features.growth` on) reads "Q3: 6 of 8 hours,
two weeks left": the hours of complete trainings dated in the current calendar quarter against the
number. `tkConfig -Set spaces.<slug>.features.trainingHoursPerQuarter=8 -Hub`, or the Space's section in
Settings. A number is read off the Space; the merged `features` map (`/api/env`) holds flags only. The
rules of the sum are in [`docs/modules/growth.md`](modules/growth.md#the-quarter-line).

## `spaces[].laneNames` -- what this org calls its lanes

Five org fields, display only: `laneNames.backlog`, `.active`, `.inProgress`, `.codeReview`, `.done`. The board and
the list print them; the state stored in a card, compared by every verb and served as `status` is always
the contract's word (`consts.json` `status`), and the CLI's `Status` prints those. Org-scoped like
`sprintAwareness`, because which words fit is a fact about the org: a client's ADO board wants "Code
Review", and the sample hub's Demo ships `To do / Doing / Waiting / Done` for someone with no team and
no tracker. An org that says nothing is called by the five contract words, so an existing ADO org is
untouched. `tkConfig -Set spaces.<slug>.laneNames.codeReview=Waiting -Hub`, or the org's section in
Settings; a lane that is not one of the five is refused (`planned` among them: the planned lane is
`backlog`, the folder's own word).

## `firstRun.welcome` -- the first-run banner

A machine setting, `false` in the shipped config. `tkStart` sets it `true` when it copies the sample hub,
and Home then shows a banner offering the deck *Introducing ToolKit*; the banner's **Get Started**
and its close **x** both set it `false` again, through `Config`, and that is the end of it. `/env` serves it
as `config.firstRunWelcome`. It shows only while the deck module is on. `tkConfig -Set
firstRun.welcome=true` brings the banner back, and so does turning off **Hide Overview Deck** in Settings,
which draws this key inverted. [`docs/modules/deck.md`](modules/deck.md), "The first-run
banner".

## `features.studio` -- retired: the Studio has no switch

The Studio is part of the core, from the first run (D-S13, which
amends D-S1): its tab, its two routes and its verbs `NewDesign` and `StampDesign` are there on every
machine, like the cards. There is no `features.studio` any more. A line left in a machine's
`config.local.json` -- `true` or `false` -- is ignored by all three halves and is never an error.
`tkConfig -Set features.studio=...` (and `-Unset`) is refused, exit 2, with one sentence: `The Studio is
part of the core and has no switch: features.studio is not a setting any more, and a line left in
config.local.json is ignored.` The sentence lives in `Get-P20RetiredConfigKeys`
(`Scripts/Get-ConfigSchema.ps1`), the table of keys that used to be settings: a retired key is answered
with what became of it rather than with `Unknown setting`. [`docs/modules/studio.md`](modules/studio.md)
is the Studio end to end.

## `features.solitaireAgile` -- Team Agile

The engineer's switch for Team Agile ([`docs/modules/solitaire-agile.md`](modules/solitaire-agile.md)): top-level, never a
Space's, off until set -- and the module is on only where this switch is on **and** the Space
you are in answers **With agents** (`spaces[].howIWork`, the next section). There, `tkStandup` prints today's standup for the Space you are in -- what is
waiting on you, then one block per worker label -- the agent serves it at `GET /api/ritual/standup`, and
the web UI has its tab; `tkTriage` lists the open issues by milestone (`GET /api/ritual/triage`, and a Triage page under the tab), and `tkRoute` is its one write -- a label, an assignee or a milestone on the tracker, or, for a card with no issue behind it, the card's one `**Assigned:**` line (`tkRoute <id> -Assign me`). Anywhere else it is absent in every half: no verb, a 404, no tab. `tkConfig -Set
features.solitaireAgile=true`, or the module's switch in Settings; the "How do I…" question's **Change** goes
to it. The words it prints are `consts.json`
`rituals.text`; its slots and vocabulary are `Config/ceremonies.json` and `Config/standup-vocabulary.json`.
[`docs/modules/solitaire-agile.md`](modules/solitaire-agile.md) is the add-on end to end.

## `startWork.prompts` -- which prompt the hand-off carries

Team Agile's `StartWork <id>` prints a hand-off block that ends with an `agentic/` prompt
([`docs/modules/solitaire-agile.md`](modules/solitaire-agile.md), "StartWork: the hand-off block").
Which prompt is **configuration, not contract** -- a team's prompts are its own -- so it is a table in
`config.default.json`, one row per kind: a card's type with the spaces removed (`Bug`, `Task`,
`UserStory`, `Feature`, `Spike`) or `issue`, for a GitHub issue no card carries. A value is a path
relative to the Toolkit package, or absolute; an `agentic/<name>` row goes through the one prompt lookup,
so a tuned copy in `agenticExtensionPath` wins. The shipped rows all name `agentic/build.prompt.md`, which starts the work on a card that already exists
and hands over to `pr-ship` when the code is ready; no `design` row ships, because no design prompt does.

```powershell
tkConfig -Set startWork.prompts.Bug=agentic/my-bug-fix.prompt.md     # one row, in config.local.json
tkConfig -Set startWork.prompts.Meeting=agentic/meeting.prompt.md    # a kind the shipped table lacks
tkStartWork 23A3 -Prompt agentic/new-issue.prompt.md                # another prompt, for one call
```

`Config` writes the one row to `config.local.json` and the other rows stay the shipped ones (rows merge
one by one). A kind with no row, or a row whose file is not there, makes `StartWork` refuse with the key
named (`startWork.prompts.<kind>`). The block's WORDS -- its head line and three headings -- are the
contract instead, `consts.json` `startWork.text`, because the web shows what the CLI typed.

## `spaces[].howIWork` -- how you work in this Space

**How do you want to work in `<Space>`?** is the Space's answer, not the person's: nobody works one
way all the time, so a learning Space is worked alone and a product Space with agents. It is the second
Space-scoped switch after `sprintAwareness`, and the tracker the Space's address names
(`Scripts/Resolve-Tracker.ps1`) says which answers there are:

| The Space's tracker | The answer | Asked? |
| --- | --- | --- |
| GitHub | `agents` (With agents -- Team Agile on for this Space) or `alone` (Alone -- no background rituals), as stored; **`alone` until someone answers** | yes -- the one case a tracker cannot tell |
| Azure DevOps | `team` (On a team in Azure) -- their board holds the rituals; Team Agile is off here | no: derived, never stored |
| none (your own cards) | `alone` | no: derived -- connect a tracker to unlock working with agents |

`tkConfig -Set spaces.<slug>.howIWork=agents -Hub` (or `=alone`), or the Settings drawer's "How do I…"
section, whose radios run that line through `PUT /api/config`. The schema allows `alone` and `agents`
only -- `team` is what an Azure DevOps address means, and writing it is refused like any unknown value; a
value stored on a Space whose tracker decides is ignored, never an error. The tracker is the ADDRESS's, so a
GitHub Space that is still `local` is asked too, and its standup fills from its cards.

The rule is one function per half -- `Scripts/Resolve-HowIWork.ps1` and `agent/core/config.py`'s
`how_i_work()` -- held to one table, `Tests/fixtures/how-i-work/table.json`, and applied once where the
flags are resolved (`Get-P20Features`, `load_config`): `features.solitaireAgile` comes out `true` only where
the switch is on and the answer is `agents`, so the module loader, `Menu`, the bridge's table, the agent's
routes and `/env`'s `features` all read one answer. `/env` also serves `howIWork` -- `answer`, `source`
(`derived`, `chosen` or `default`), `tracker`, `locked`, and the `switch` as set -- which the Settings
control draws from. Switching Space re-evaluates: per request in the agent and the web UI, at the
re-import `SwitchSpace` does in a shell. The inventory row reads `on (chosen: with agents in <slug>)`,
`off (derived: ...)` or `off (chosen: alone in <slug>)`, and `not configured` for a GitHub Space nobody
has answered.

## `spaces[].features.suggestions` -- whether Team Agile suggests your next move

A boolean, and the third Space-scoped switch (with `sprintAwareness` and `howIWork`): whether the chair's
reading ends on one derived next move -- the item, the rule that chose it and the command that acts on it
-- in place of `Next: nothing is waiting on you.` It rides Team Agile, so it means something only where
Team Agile is on, and there **unset is on**; `false` turns the line back to today's
([the suggestion](modules/solitaire-agile.md#the-suggestion-one-next-move-derived)). It is declared in
`consts.json` `features.spaceScoped`, so a top-level `features.suggestions` is ignored and the merged map
`/env` serves carries the Space's value when it sets one.

```powershell
tkConfig -Set spaces.<slug>.features.suggestions=false -Hub   # no suggestion in this Space
tkConfig -Unset spaces.<slug>.features.suggestions -Hub       # back to the default: on where Team Agile is on
```

One rule per half -- `Test-P20SuggestionsOn` (`Scripts/Suggest-Rules.ps1`) and `suggestions_on()`
(`agent/solitaire/suggest.py`), the `switch` rows of `Tests/fixtures/suggestion/table.json`. The inventory
row, `Suggestions`, reads `not configured` where Team Agile is on and nothing is set (on, by default),
`on` where it is set true, and `off` where it is set false or Team Agile is off in that Space -- each
with the line that changes it, under the question "Can it tell me what to do next?".

## `features.ado` is not like the other flags

Every other flag under `features` is a module's on / off switch, off until someone sets it. **`features.ado`
has three answers, and the usual one is ABSENT**: unset, Azure DevOps follows the org you are in -- on
in an org whose `status` is `active` AND whose address names Azure DevOps (`Scripts/Resolve-Tracker.ps1`),
off in a `local` or `archive` one, and off on a connected GitHub Space, which is `active` too but whose
tracker is GitHub. So the machine `tkStart` leaves (in Demo, which is `local`) shows no ADO verbs, someone
in their client's org sees exactly what they always saw, with no key to set and nothing to migrate, and a
GitHub Space's inventory reads `GitHub issues on` beside `Azure DevOps off (follows the org you are in:
<slug>'s tracker is GitHub)` rather than two trackers on. Set it to say otherwise: `false` hides ADO even
in an active org; `true` shows it even in a local one, or on a GitHub Space, which is how the old menu
comes back.

It decides what is **shown** -- `Setup`'s `az` checks, the opt-in inventory's state, `/env`'s `ado`
block. Nothing is unregistered: an ADO verb typed by name still answers, with its tier sentence -- and
`Menu`'s tracker rows stay on a connected GitHub Space, where the same verbs answer through `gh`. One
rule, `Scripts/Test-AdoEnabled.ps1`, over three inputs; [the add-on's
document](modules/ado.md#the-switch-and-its-scope) states it. Cards have no such flag and never will.

## The contract file

There is a **third** committed file beside those two, and it is not configuration:
**`consts.json`** at the package root. It holds the literals that cross a half boundary -- the
strings and patterns the CLI, the agent and the web UI must agree on to the character:
`**Closed:**` and `**Created:**`, the `PR URL:` line, the `## PR Review Comments` heading, the
state names `Backlog` / `Active` / `In Progress` / `Code Review` / `Done`, the `current`, `archive` and
`backlog` folder names (`backlog/` is a Space's third card folder: cards planned, not yet in play -- [the
card](hub/cards.md), "State is derived, never stored"), the `reviews/` file name and its `+` slug-set separator, the two regexes that derive a
card's state, **the shape of a card's id** (`regex.cardId`: a work item number, or the
four-character id of a card with no work item -- at least one letter and one digit, no look-alike
characters, uppercase; see [The workflow](CLI.md#the-workflow) and [the card](hub/cards.md), "The filename"),
and **which feature flags are the org's** (`features.spaceScoped`, today `["sprintAwareness", "trainingHoursPerQuarter", "suggestions"]`: the
flags read from `spaces[].features` rather than the top-level block -- `SpaceScopedFeatures` in
`utilities.psm1`, `SPACE_FEATURES` in `agent/core/config.py` and `FEATURES.spaceScoped` in
`web/src/shell/consts.ts` all read this list, so the second org-scoped flag is added in one place
and the three consts suites say so), and **which repo files a GitHub Space's Docs tab reads**
(`docs.readme`, `docs.root`, `docs.segment`: `README.md`, the markdown under `docs/`, and what one
path segment may look like -- the agent's `/api/docs` routes refuse every other path and the web's
link resolver opens exactly these in the reading room), and **a design's identity**
(`design.idKey`, `design.idRegex`, `design.states`, `design.outcomes`: the frontmatter key a
design's id lives under, its shape -- a UUID v4, lowercase, hyphenated -- and the state and outcome
words of the design lifecycle ([the state rule](hub/design.md), "State -- derived, never stored"); `NewDesign` and
`StampDesign` write the id, see [`design/` in the hub](hub/design.md)), and **the line a card names its
design with** (`tokens.design`, `tokens.spec`, `design.cardLineRegex`: `> Design: [<title>](<link>) <id>`,
which `NewPrompt -Design` writes, and the corpus's hand-written `> Spec:` form, read as written -- the CLI's
`Get-P20CardDesign` and the agent's `card_design` read it by one table, see [the card](hub/cards.md)),
and **the Studio's Prompts card's read** (`studio.promptsRoute`, which the agent mounts and the web asks,
see [the Studio](modules/studio.md#the-web-ui)),
and **the halves a test run
covers** (`tests.halves`, `agent`, `cli`, `web` in the order `tkTest` runs them, and `tests.legacyHalf`,
what a `test-summary.<machine>.json` entry with no `half` is read as: the CLI runner and `tkTest` write
the tag, `agent/core/log.py` serves it and the Health card draws it -- [Testing](TESTING.md)),
and **the package's own repository** (`repository.url`: what the agent compares a Space's repository with when the package has no git origin to read, so ToolKit connected to itself still reads as itself on the Prompts card -- a checkout's origin wins when it is there),
and **the product's version** (`version`, the one top-level value that is not a group: `Env` prints it
in its first block, `GET /api/env` serves it and the System page's Environment card shows it).
Two files carry a copy because they must hold their own literal -- `ModuleVersion` in
`Prompt20Toolkit/Prompt20Toolkit.psd1`, which `Update-ToolkitManifest.ps1` writes from this key, and
`version` in `web/package.json` -- and the three consts suites fail naming the file that disagrees.
A bump is one edit here, one in `web/package.json` and a regenerated manifest; a partial one is red.
JSON, because it is the one format all three read with no new dependency:
`ConvertFrom-Json` on the PowerShell 5.1 floor (through `Scripts/Get-Consts.ps1`), `json.load` in
`agent/core/consts.py`, and a build-time `import` in `web/src/shell/consts.ts` through the
`@consts` alias, so nothing is fetched at runtime.

The line between the two kinds of file is worth keeping: **`config.default.json` is what a team may
change** -- orgs, commands, `workItemTypes` -- and **`consts.json` is what nobody may change alone.**
`**Closed:**` was typed in three languages and eleven files, and the commit-bullet regex exists
twice on purpose; either one edited on its own is a card that silently stops being read. Literals
only one half ever types stay where they are, per `AGENTS.md`'s "One place for magic strings", and
the templates keep their literal text because they are documents a person reads rather than
parsers. Three suites guard it, one per side -- `tkTestToolkit -Consts`, `Tests/test_consts.py`,
`web/src/shell/consts.test.ts` -- each stating the value it resolved for every key and grepping its
own half for a retyped copy.

**The two files hold `spaces` in two different shapes, on purpose.** In `config.default.json` it is
an **array** -- the list of orgs, each entry carrying its own `slug`. In `config.local.json` it is
an **object keyed by slug**, because it is a patch onto one of those entries rather than a second
list. A local `spaces` written as an array matches nothing and is ignored; both the PowerShell
module and the agent **warn** when they find one, naming the shape they wanted.

So a new org is added to the **array** in `config.default.json` -- `slug`, `org` (the ADO URL),
`tenant`, `promptsFolder` -- or, for your own orgs, to **`hub.json` in the hub**, below. Anything
about it that is yours rather than the team's goes in `config.local.json` under `spaces.<slug>`, where
`slug` is the key and therefore not a field inside it. Per-org `tenant` means an org on a different
Azure AD tenant is a config edit, not a code change.

## Adding a Space

**`tkNewSpace`, or the + on the Studio's Spaces card** -- the same verb, the + runs it through the
bridge ([Studio](modules/studio.md)). You need to know only which repository you want:

```powershell
tkNewSpace -Repo you/juggling-engine                 # a GitHub repository -> Space 'juggling-engine', "Juggling Engine", active
tkNewSpace acme -Address https://dev.azure.com/acme  # an Azure DevOps organisation, active; then tkConnect acme -Discover for its projects
tkNewSpace notes                                     # your own cards, no tracker, local
tkNewSpace -Discover                                 # your repositories (gh), each with the line that adds it
tkNewSpace -Discover -Owner acme                     # an organisation's repositories; -Owner collaborator: the ones shared with you
tkNewSpace -Discover -Repo someone/their-project     # one repository, its PUBLIC or PRIVATE read before it is added
tkNewSpace -Repo someone/their-project               # a repository you do not own -- any one the gh login can read
```

A repository you do not own -- a project you contribute to, or an organisation's -- is a Space like any
other. It is marked `READ-ONLY` while the account can read it and not write to it, and its
`PUBLIC` is said: a write there is in someone else's house. The New Space dialog offers the same owners
above its list, and a full `owner/name` typed into its search is a row of its own, its Public or Private
read before it is added -- or `Visibility unknown` and `not visible to this login` when the `gh` login
cannot see it. A list is read to 1000 repositories; past that it says so, and a repository beyond them is
typed as `owner/name`.

It writes the Space **through `Config`** -- these are exactly the lines it runs, and typing them
yourself still works:

```powershell
tkConfig -Set spaces.juggling-engine.name="Juggling Engine" -Hub
tkConfig -Set spaces.juggling-engine.status=active -Hub
tkConfig -Set spaces.juggling-engine.promptsFolder=juggling-engine -Hub
tkConfig -Set spaces.juggling-engine.org=https://github.com/you/juggling-engine -Hub
```

-- and then makes `<hub>/<slug>/current` and `archive`. A folder already there is **adopted, never
touched**, and the output counts its cards: removing a Space does not delete its folder, so adding it
again brings the cards back. It does not switch you into the new Space; its last line is the
`tkSwitchSpace <slug>` that does. `-WhatIf` prints every key and the folder and writes nothing; the
refusals (a slug or folder already taken, a repository that is already a Space, a slug that is not a
slug) are one sentence each. The whole contract is [`docs/CLI.md`](CLI.md#the-studio-spaces-and-design-notes), "The Studio: Spaces and design notes".

## Retiring or removing a Space

Two different things, and the product names both. Each is a verb, and each is in the `...` of
the Space's row on the Studio's Spaces card, which runs it through the bridge after showing the verb's
own `-WhatIf` -- never on the avatar menu's Space list.

| | **Retire** -- the engagement is over, keep the record | **Remove** -- it should never have been a Space, or it is truly gone |
| --- | --- | --- |
| The verb | `tkRetireSpace <slug>` | `tkRemoveSpace <slug> [-Force]` |
| What `Config` writes | `-Set spaces.<slug>.status=archive -Hub` (and `-Unset spaces.<slug>.status` when this machine overrides the status) | `-Unset spaces.<slug> -Hub`, and `-Unset spaces.<slug>` when this machine has a patch for it |
| The Space afterwards | still declared, `status: archive`: under **Archive** on the Spaces card, its tracker never asked | not declared: gone from every list, `/env` and `SwitchSpace` |
| Its folder and cards | stay, and stay readable | **stay, exactly as they were**; the output says where, how many, and the line that brings them back |
| Undo | `tkConfig -Set spaces.<slug>.status=<what it was> -Hub` -- the output names it | `tkNewSpace <folder>` with its `-Repo` or `-Address` -- the output names it; the folder is adopted untouched |
| Refused | a slug that is not declared | a slug that is not declared; the Space you are in (switch first); a Space `config.default.json` ships -- the team's, which can be hidden (`isDemoDismissed`) or retired, not removed |

```powershell
tkRetireSpace acme -WhatIf      # the Config line, and the folder that stays
tkRetireSpace acme
tkRemoveSpace side-notes -WhatIf  # the keys that would go, the folder that would stay, its cards counted
tkRemoveSpace side-notes
```

**Removing never deletes a card.** Deleting the folder is a person's act, in their own file manager, on
purpose -- the rule that protects `current/`. A Space with cards in `current/` asks before it is removed,
naming the count; a caller that cannot answer (the bridge, a script) needs `-Force`, which the web's
confirm sends once the person has seen the count. Both verbs take `-WhatIf` and refuse in one sentence,
exit 2. The whole contract is [`docs/CLI.md`](CLI.md#the-studio-spaces-and-design-notes).

## The hub declares its orgs

`config.default.json` is committed and shared, so a real org URL cannot go in it -- the Portability
suite fails the build over exactly that. For a team's fork, adding the org to the committed array is
right. For one engineer whose orgs are private, it is not: the org belongs with the engineer's data,
and the engineer's data is the hub. The owner's rule: *"data separate from software."*

So a hub may declare its own orgs, in an optional `hub.json` at `promptsRoot`:

```jsonc
// <promptsRoot>/hub.json -- yours, never in this repo
{
  "hub": 1,
  "storeSync": "git",                           // git | none -- a fact about the hub
  "spaces": [                                   // the older `orgs` is still read
    {
      "slug": "acme",
      "name": "Acme Engineering",
      "status": "active",                       // active | local | archive
      "orgType": "engagement",                  // engagement | portfolio | internal
      "org": "https://dev.azure.com/acme",
      "tenant": "00000000-0000-0000-0000-000000000000",
      "promptsFolder": "acme",
      "projects": [
        { "name": "Platform", "repo": "platform", "defaultBranch": "main" }
      ],
      "features": { "sprintAwareness": true }
    }
  ],
  "folders": {                                  // hub-root siblings; omit any to keep the default
    "growth": "growth", "manager": "manager", "reviews": "reviews",
    "resume": "resume", "agentic": "agentic"
  }
}
```

**The order is: `config.default.json`'s orgs, then the hub's merged by slug -- a hub entry with a
shipped slug deep-merges over it, a new slug is appended -- then `config.local.json`'s `spaces.<slug>`
patches, last.** So the team's list, then yours, then this machine's.

`hub.json` declares **orgs, folder names and `storeSync`, and nothing else**. `activeSpace`, `promptsRoot`,
`email`, `branchUser`, `wsRoot`, `web`, `commands` and the top-level `features` block are the
machine's and stay in config; a copy of one here is ignored with a warning naming the key. The same
line divides the feature flags: an org-scoped flag (`sprintAwareness`, [the web UI overview](ARCHITECTURE.md#the-shell-owns-the-chrome-a-module-owns-the-rest)) works on a hub org exactly as on a shipped
one, while an engineer's flag there is ignored and told where it belongs.

`folders` names the hub-root siblings the modules read -- `growth/`, `manager/`, `reviews/`,
`resume/`, `agentic/`, `reminders/` (the Organize add-on's), `design/` and `spec/` (the hub's designs
and specs, the same four folders a product keeps, [`hub/design.md`](hub/design.md)). Omit a key and it
keeps its default, which is its own name.

`storeSync` is the same argument applied to a scalar: whether the store is a repository is the
hub's fact, so one hub kept in sync from two machines declares it once, in the file both share. A value that is neither `git` nor `none` warns and the configured value
stands.

Nothing about this is required. **A hub with no `hub.json` declares nothing** and the other two files
decide everything, a malformed
one is a warning naming the path rather than a crash, and an org entry without `slug` or
`promptsFolder` is skipped with a warning rather than half-applied. `tkSetup`, `tkEnv` and
`GET /api/env` each report whether a manifest was read and how many orgs it declared.

**You do not have to write one by hand.** `tkConfig` creates and maintains it: `-Set
spaces.<slug>.<field>` writes an org (appending the entry, with its required fields, when the slug is
new), and `-Set folders.<name>` or `-Set storeSync` with **`-Hub`** writes the other two things a
hub may declare. The web UI's settings drawer (the avatar opens it) does the same through `PUT /api/config`, which
runs this verb. Hand-editing still works -- it is a small JSON file in your own hub -- and the
schema above is what the verb will accept.

**There is no `config.local.example.json`, and "copy config.default.json" is the wrong advice.**
The shipped file is the whole table -- every org, every command, every help string -- and a private
copy of it silently stops tracking the committed one. The import warning on a machine with no local
config prints the four-line patch above instead.

Confirm the machine is set up correctly:

```powershell
tkSetup      # validates prerequisites and reports what is missing
tkEnv        # machine, OS, tier, hub, active org, az identity, and what the tier allows
```

## The container's keys: `spaces` and `activeSpace`

The container is a **Space** (the GitHub spec's D-G13). Its keys are `spaces` -- an array in
`config.default.json` and `hub.json`, an object keyed by slug in `config.local.json` -- and
`activeSpace`.

**The files are written in this spelling, and the older one is still read.** `Config -Set`, the web's
`PUT /api/config` behind it, and `SwitchSpace` put `spaces` and `activeSpace` on disk; a file that
still says `orgs` or `activeOrg` comes out saying the new name where the old one stood, its values
intact. `Sync` does the same for the hub's `hub.json` once, on the machine that pulled it, and
commits it as `sync: hub.json says spaces`. The sample hub `Start` copies says `spaces`.

**The keys a person types say Space too**: `Config -Set spaces.<slug>.status=…`, `activeSpace=…`, the
schema's rows and the web's `spaces.<slug>.laneNames.<key>`. The older typed spelling --
`orgs.<slug>.x`, `activeOrg` -- is still accepted, lands on the same row, and is answered with the new
name once; `SwitchOrg` still answers as `SwitchSpace` with the same one-time hint the Item family's old
names carry.

**The old spelling is read in exactly one place per half**: `ConvertTo-P20SpaceKeys` in
`Scripts/Resolve-HubConfig.ps1`, applied at every place a config file is parsed, and `space_keys` in
`agent/core/config.py`. Both map `orgs` / `activeOrg` onto the new names and DROP them, so nothing
downstream ever sees the old key, and a file that carries both is read by the new spelling. The
agent-web contract is `spaceStatus`, `config.activeSpace`, `config.spaces`, `hub.spaces` and consts'
`features.spaceScoped`; the CLI's in-memory config is `$global:P20Config.Spaces`, `.ActiveSpace` and
`.HubSpaceCount`, its helpers `Merge-SpacePatch`, `ConvertTo-P20HubSpace`, `Select-P20OfferedSpaces`
and `Get-P20SpaceFieldSchema`, and the agent's `space_keys` and `offered_spaces`. `Setup` names a file
that still says the old word, as a note with the verbs that will rewrite it; the two array-shape
warnings say `spaces`; `Env` and `Setup` say "N Spaces declared".

Pinned by `-HubJson` (the canonicaliser at the unit: old-only, both, blank, and the write side),
`Tests/fixtures/hub-parity-spaces` (the parity fixture spelled the new way, resolved by both suites to
the same answer as `hub-parity`), `-Setup` (the note) and `Tests/test_switch_space.py` (a switch
a -> b -> a through the agent leaves `config.local.json` saying `activeSpace` alone).

## Overrides from the environment

Three keys can be answered **per process** from the environment instead of from a file. Each one
wins over the files, in both halves -- the module (`Scripts/Resolve-HubConfig.ps1`) and the agent
(`load_config` / `hub_root` in `agent/core/config.py`) -- and each one replaces exactly the key it
names: the rest of `config.local.json` (a Space patch, the port, the prefix, your email) still
applies.

| Variable | Stands in for | Value |
| --- | --- | --- |
| `PROMPTS_ROOT` | `promptsRoot` | A path; relative resolves against the package, as in the file. On Windows the CLI reads an 8.3 short path (`C:\Users\RUNNER~1\...`) in its long form, from either source |
| `P20_ACTIVE_SPACE` (`consts.json` `env.activeSpace`) | `config.local.json`'s `activeSpace` | A Space slug. One nobody declared falls back the way an unknown slug in the file does |
| `P20_FEATURES` (`consts.json` `env.features`) | `config.local.json`'s top-level `features` block -- **replaced, not patched** | A JSON object: `{"growth":true,"communication":true}`. `{}` is "no flag set", the file with no `features` block; `config.default.json`'s flags still stand under it. Anything that is not a JSON object is a warning and is ignored, so a typo falls back to the file rather than switching every module off |

They exist for one caller: **`Web -Dev -Fixture`**, which starts the agent against
`Tests/fixtures/hub` for `npm run smoke` with all three set, plus the test-run marker and no
`TEAMS_WEBHOOK_*` ([the command reference](CLI.md#the-other-two-halves)), so a smoke run never
rewrites this machine's `config.local.json` and there is no restore to forget. The agent's bridge
children inherit them, so a verb the browser runs reads the same Space and flags the agent does, and
`/api/surfaces` -- the CLI resolver in a child `pwsh` -- agrees with `/api/env`. Nothing writes them
and `Config` does not know them: they are a launcher's, not a setting. One consequence to know: while
`P20_ACTIVE_SPACE` is set, a Space switch still writes `activeSpace` to the file but does not take
effect in that process -- the override wins, which is what it is for. Without it, a shell that was open when another one wrote `activeSpace` (the GUI's switch, `Config -Set`) acts on the new Space from its next verb: the module compares the write times of `config.local.json` and `hub.json` before each verb and re-imports when either moved. `PROMPTS_ROOT` and `P20_ACTIVE_SPACE` are part of the same comparison, so one exported into a shell that had already loaded the toolkit (a profile that imports it at startup) is seen on the next verb exactly as a changed file is -- `Env`'s `Hub` check and its `Your hub` row then name one hub, and the verb acts on it, saying `Hub changed to <path> since this shell loaded (it was <path>); re-read.` once. The two new names are the
contract's (`env.activeSpace`, `env.features`) because both halves type them; `PROMPTS_ROOT` predates
the contract file and is typed where it is read.

## Settings by workflow: the questions, and the one list behind them

Every optional surface carries a QUESTION in the person's words -- "Can it post to Teams for me?", "Where do my cards live?" -- and the
questions are one file, **`Config/settings-workflows.json`**, read by all three halves (D-W1, D-W8):

- **The CLI** reads it in `Scripts/Get-SettingsWorkflows.ps1` and puts the question on every row of the
  inventory (`Scripts/Get-OptionalSurfaces.ps1`), so `tkEnv`'s "Optional surfaces" block and
  `tkMenu -All`'s "Opt in by configuration" block print the question first (D-W10). Two of the
  inventory's rows exist for it: **Your hub** (`promptsRoot`, first -- D-W7; `on` only when someone SAID
  where the hub is) and **Spaces** (`spaces`, how many and which you are in).
- **The agent** serves `GET /api/surfaces`: the inventory with its states and the entries, read by
  running the CLI's `Get-P20SurfaceInventory` in a child PowerShell -- the state of a surface is
  computed by the CLI's resolver and by nothing else (D-W2). Cached briefly; a config write through
  `PUT /api/config` invalidates it.
- **The web** imports the same file through the `@workflows` alias and draws the settings drawer's
  first section, **How do I…** -- each question, a sentence, the CLI's state word as a chip, and the
  door -- and draws the tips at the foot of Home from the entries that carry a `tip`, while every
  surface of the entry reads `not configured` (never `off`: an answered no is respected, D-W3).

**An entry** is `{ id, question, sentence, surfaces[], door, anchor?, route?, space?, tip? }`. `surfaces` are inventory
keys (`features.growth`, `email`, `TEAMS_WEBHOOK_*`, `tracker.github`); one question may cover two (meetings and
reminders, D-W9). **The door is one of three** (D-W4): `change` opens the drawer at `anchor` (`{slug}`
is the active Space); `walk` is a journey -- the connect wizard, below -- offered as *Set it up* when
the entry names an anchor or a route, and otherwise shown as its sentence; `sentence` is the whole
answer, for the environment variables this tool never writes.

**An entry that asks** carries `answers`, `answerKey` and `why` too -- one does today, **How do you want to
work in {space}?** ([`spaces[].howIWork`](#spaceshowiwork----how-you-work-in-this-space)). `{space}`
in a question is the Space you are in, by name ("this Space" when none is known), in the CLI's inventory
and in the drawer alike. Each answer is a `label`, the `value` it writes to `answerKey` (`{slug}` the
active Space) with `-Hub`, its `sentence`, and the trackers it is `live` on; `why` is one sentence per
tracker saying why the others are disabled. The drawer draws every answer -- one the Space cannot make is
disabled, never hidden -- checks the one `/env`'s `howIWork` names, and on a pick shows it at once with a
tiny **Saving…** spinner beside the group, the other answers locked and the group `aria-busy` while
`Config -Set` runs; a refusal puts the pick back and shows the CLI's sentence. The entry's door
still goes to its `anchor`, Team Agile's own switch.

**An entry that names a `space`** is about that one Space -- the demo Spaces, one per grain
([the add-on's demo Spaces](modules/ado.md#the-demo-spaces-one-per-grain)) -- and its tip is not
read against the inventory. A journey (an entry with a `route`) tips while that Space is declared and
still `local`, and connecting it retires the tip; its walk goes to that Space when it is declared and to
the one you are in when it is not, so the same question still walks your own Space on a hub without the
demos. Any other such entry tips while you are in its Space (the Demo's). A Space that **Hide Demo**
leaves out of the list is not declared, so its tip goes too. These tips come first in the rotation,
`connect-github` first of all, then `connect-azure` and the Demo's. The two connect
entries are the old single `connect` entry split by grain (D-W17). `tracker.github` is the inventory's **GitHub issues**
row: `on` once a Space whose address is GitHub is `active`, else `not configured` -- the shipped GitHub
demo has an address and is `local` until connected.

**Held both ways.** `tkTestToolkit -Environment` runs the real resolver and fails naming the key if an
inventory row has no question or an entry names a key the inventory does not have;
`web/src/shell/settingsWorkflows.test.ts` holds the web's half (every module the registry declares
has a question, and no entry names a module the web does not know); `Tests/test_surfaces.py` holds
the route and, when PowerShell is present, the same parity from the agent's side. Adding a surface to
`Get-OptionalSurfaces.ps1` without an entry turns both CLI and agent suites red.

**The journeys: `Connect <slug>`.** A row whose door is *Walk me through it* opens the
connect wizard -- `/connect/<slug>` in the web, `tkConnect <slug>` in a terminal -- four steps, each named as
whose it is (D-W13): the address is yours and we write it through `Config` (an address implies active, D-W14);
signing in is yours, said with the exact command and checked, never run; discovery is ours, and what you pick
is written as `spaces.<slug>.projects` on an Azure DevOps Space or as the repo-grained ADDRESS on a GitHub
Space -- because a Space's grain follows its tracker (D-W17): an Azure DevOps Space is an organisation with
projects inside it, a GitHub Space is one repo, and a Space with no address is your cards alone; sprint
awareness is the last step. Step 1 is done when the Space has an address AND is connected to it: a
Space that ships with an address and stays `local` (the GitHub demo) shows the address with "local until
you connect it", and saving it -- the same `-Address`, or **Connect** on the page -- makes it active.
`Connect azure-demo -As <slug>` graduates the shipped Azure demo -- or any demo Space -- into your own Space
(D-W15): declared from its settings, its folder moved, made active. **`spaces.<slug>.projects`** is the
field discovery writes: `Name/repo; Other/repo2` or a JSON array of `{ name, repo, defaultBranch }`,
through `Config -Set ... -Hub` like every Space field.
