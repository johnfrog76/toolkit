# The org chart -- `org.json`

> What the org is, and how you use it: [The org](../ORG.md). This page is the file's reference.

An org is a shared understanding of how a team works together: which roles there are, who each one
reports to, and who -- a person or a model -- fills each one today. `org.json` is that structure written
down, as a file anyone can read as it is: a tree of **positions** (an office, not whoever sits in it) and
the **seats** in each. Nothing in it is derived from the cards; it is what you say your org is. The
[Org tab](../modules/solitaire-agile.md#the-web-ui) draws the tree back, so you can see it and read about the
org and the role behind each office; and as your attention moves from one project to another, you change it
through [`Staff`](#the-one-writer-staff), the file's one writer (a hand edit works too).

It rides [Team Agile](../modules/solitaire-agile.md): `OrgChart` and `GET /api/ritual/org` read it, and where
Team Agile is off in the Space you are in there is no verb and the route is a 404, so the chart is absent there -- see
[The scope](#the-scope----where-it-is-and-is-not-there). The file name is `consts.json` `org.file`, typed
by the CLI, the agent and the web from there and never retyped.

## Where, and how it is found

`<promptsRoot>/org.json` -- a hub-root sibling of [`hub.json`](../CONFIGURATION.md#the-hub-declares-its-orgs),
the engineer's and not a Space's. It is found the way `hub.json` is: at the hub the module resolved
(`PROMPTS_ROOT`, else `promptsRoot`), and only where someone **said** where the hub is -- "the hub
resolved" is not "a hub was configured", so with no hub named anywhere `OrgChart` refuses rather than
read a folder nobody chose. A hub that is not there (an unplugged drive) is refused with the hub's own
sentence.

It has **one writer**, [`Staff`](#the-one-writer-staff), and hand edits keep working beside it: `Staff` reads
the file, changes only what it was asked to and keeps everything else. `Config` does not write it. It is UTF-8,
with or without a BOM; a file `Staff` writes has none.

## The shape

This is the whole `org.json` contract. **A preset file is one tree in this same shape** ([Org presets](#org-presets)),
so a preset and a tree in `org.json` are the same object.

**One reading rule for every level: a key the tool does not read is ignored.** It is named once as a warning,
as `hub.json` names one (`org.json: 'x' is not a key this tool reads in position 'p' of tree 't' -- ignored.`),
and never refused. A key that starts with an underscore is a note and is never named. So a later field never
breaks a reader that predates it. Key names are matched exactly, case included (`Title` is not `title`), and an
id is compared character for character (`A` is not `a`); a number given as an id is read as its text.

Everything is an **array of objects addressed by `id`**, never an object keyed by name, so a writer can address
`trees.<id>.positions.<id>.seats.<id>.model` without a second shape. The words `orgs` and `activeOrg` are not
used: they are the retired spellings of `spaces` and `activeSpace`, and an "org" here is the tree you draw,
never a Space.

### The file

| Key | Required | Meaning |
| --- | --- | --- |
| `trees` | **yes** | an array of trees, at least one |
| `activeTree` | **when there is more than one tree** | the id of the tree in use. With one tree it may be left out, and that tree is the one |

### A tree

| Key | Required | Meaning |
| --- | --- | --- |
| `id` | **yes** | the tree's address, unique among the file's trees. For a preset, its preset id (`executive-suite`) |
| `title` | no | what the org is called ("The Branch Office"); the heading on the Org tab, and the id when absent. **It replaces `name`**: a reader takes an older file's `name` as the title when there is no `title` |
| `size` | no | `S`, `M` or `L`, drawn as the badge beside a preset's title |
| `shortDescription` | no | one line: what it is and what it fits |
| `description` | no | a few sentences: how the work flows, who owns what, what it fits |
| `teamSize` | no | the standup room the org suggests: 3, 6 or 9. A suggestion only: the Space's `features.teamSize` decides the room |
| `preset` | no | the id of the preset the tree was started from |
| `positions` | **yes** | the positions, in the order siblings are drawn |
| `name` | no, **retired** | an older file's title, read when there is no `title` |
| `machines` | no, **retired** | read without a word, never drawn: a machine is not a boundary in an org |

### A position (an office)

| Key | Required | Meaning |
| --- | --- | --- |
| `id` | **yes** | unique within its tree. The same id in two trees is fine |
| `title` | no | the office's name ("Team lead"); the id when absent |
| `prompt` | no | the **role name**: the file name of the position's role -- its job description -- looked up in three folders, in order ([Where a position's prompt is found](#where-a-positions-prompt-is-found)). A name, not a path |
| `reportsTo` | **on every position but the root** | the id of the position it reports to. Exactly one root |
| `defaultModel` | no | free text: the model the office is meant to have. On a pool (no seats) it is the line drawn under the pool |
| `recommend` | no | an array of the model families a picker offers without a "not recommended" note (`["opus", "fable"]`) |
| `seats` | no | the seats; absent or `[]` makes the position a **pool** |

### A seat

| Key | Required | Meaning |
| --- | --- | --- |
| `id` | **yes** | unique within its position |
| `roleTitle` | no | this seat's own label, **only where it differs** from the position's title (one of two team leads called "Alpha lead"). Drawn on the plate and printed in place of the position's title |
| `model` | no | the model sitting there: a [`Config/models.json`](../../Config/models.json) id (`claude-opus-5-5`). A reader also takes a family (`opus`, meaning the id `current.opus` names today) or any text, and **looks it up, never parses it**: the Org tab shows the map's `name` ("Opus 5.5"), and an id with no row as written |
| `person` | no; **the owner's seat has one** | a person sitting there, in your own words: the root position is the owner, and its seat carries `person` and no `model` |
| `session` | no | **the session's name** (`lead-session`): the address readies and messages route to, not a tool's session id |
| `merges` | no | `true` on the seat that holds the merge. At most one per tree should; more is allowed for a stand-in while it stands in |
| `space` | no | the Space slug the seat serves. Not checked against the hub's Spaces |
| `machine`, `active` | no, **retired** | read without a word, never drawn |

**Derived, never written:** a seat is `staffed` when it names a `model` or a `person`, and `vacant` otherwise
([Positions, seats, and the three shapes](#positions-seats-and-the-three-shapes)). A position with no seats is a
pool. A field of the wrong type reads as unset: `merges` only as a JSON `true` or `false`, `teamSize` only as a
whole number, `recommend` only as an array (its text entries trimmed, the empty and the non-text left out), and the
text fields as text (a number as its text).

### One complete tree

The Branch Office, staffed, after the owner has named themselves ("Sam") and a few seats are filled:

```json
{
  "activeTree": "branch-office",
  "trees": [
    {
      "id": "branch-office",
      "preset": "branch-office",
      "size": "M",
      "title": "The Branch Office",
      "shortDescription": "Local leads run the work: a team lead for each product, builders under the leads, and a test runner.",
      "description": "Each product has its own team lead, who briefs a builder for each card and sends each finished pull request to the seat that merges.",
      "teamSize": 6,
      "positions": [
        { "id": "owner", "title": "Owner",
          "seats": [ { "id": "owner", "person": "Sam" } ] },
        { "id": "vp-engineering", "title": "VP of engineering", "prompt": "vp-of-engineering.prompt.md",
          "reportsTo": "owner", "recommend": ["opus", "fable"],
          "seats": [ { "id": "vp-engineering", "model": "claude-opus-5-5", "session": "engineering-session" } ] },
        { "id": "team-lead", "title": "Team lead", "prompt": "team-lead.prompt.md", "reportsTo": "vp-engineering",
          "seats": [
            { "id": "alpha", "roleTitle": "Alpha lead", "model": "claude-opus-5-5",
              "session": "lead-session", "space": "alpha" },
            { "id": "beta", "model": "claude-opus-5-5", "space": "beta" }
          ] },
        { "id": "builder", "title": "Builder", "reportsTo": "team-lead",
          "defaultModel": "claude-sonnet-5-5", "seats": [] },
        { "id": "test-runner", "title": "Test runner", "reportsTo": "vp-engineering",
          "seats": [ { "id": "test-runner" } ] },
        { "id": "vp-product", "title": "VP of product", "prompt": "vp-of-product.prompt.md",
          "reportsTo": "owner", "recommend": ["opus", "fable"],
          "seats": [ { "id": "vp-product", "model": "claude-fable-5-2", "session": "product-session", "merges": true } ] }
      ]
    }
  ]
}
```

### The schema

[`Config/org.schema.json`](../../Config/org.schema.json) is the shape above as a JSON Schema (draft 2020-12):
the required keys (`activeTree` among them when there is more than one tree), the types, `size` as `S`/`M`/`L`, `teamSize` as 3, 6 or 9, `merges` as a boolean, and
`additionalProperties: true` at every level, so an unknown key passes. A file validates against it as a whole,
and a preset against its `#/$defs/tree`. It cannot express the cross-field checks -- ids unique, a `reportsTo`
naming a position in the same tree, no loop, exactly one root, a `prompt` that is a real role file -- which the
two readers keep ([What is checked](#what-is-checked)). Both suites validate the sample hub's `org.json` and the
three presets against it: `Tests/test_org.py` with `jsonschema` (a dev-only dependency,
`agent/requirements-dev.txt`), and `tkTestToolkit -OrgChart` with `Test-Json -Schema` on PowerShell 7, a named
skip on Windows PowerShell 5.1, which has no `Test-Json`. The readers do not read the schema: it is the contract a
file is written to, and a reader stays as tolerant as the reading rule says.

## Where a position's prompt is found

A position's `prompt` names a **role**: a job description, one `<role>.prompt.md`. The toolkit ships
six in its own `agentic/org/` -- `pm`, `team-lead`, `vp-of-engineering`, `vp-of-product`, `intern` and `butler`,
each described in [the roles](../../agentic/org/README.md#the-roles) with what it takes in and what it
hands on -- and a hub may write its own. The name is looked up in three folders, in this order, and the
first that has the file is the one used:

1. the hub's `agentic/org/` -- the hub's own roles;
2. the hub's `agentic/` -- where a position's prompt was always looked for, so an `org.json` written
   before the roles folder keeps validating;
3. the toolkit's `agentic/org/` -- the shipped roles.

So **a hub's own role wins**: a file in the hub's `agentic/org/` (or its `agentic/`) under a shipped
role's name is the one used, and the shipped one is not read. A hub can name a shipped role, such as
`intern.prompt.md`, without copying it. The toolkit's flat `agentic/` is not in the list: a task prompt
there is not a role. `agentic` in the first two is the hub's agentic folder as `hub.json` names it
(`folders.agentic`); `org` is `consts.json` `org.rolesFolder`. Both halves hold the same list -- the
CLI's `Get-P20OrgPromptDirs` in `Scripts/Read-OrgChart.ps1` and the agent's `prompt_dirs` in
`agent/solitaire/org.py` -- and the shared table has a row for each folder and one for a hub's role
shadowing a shipped one.

## Positions, seats, and the three shapes

A **position** is the office; its prompt is the job description; the model in it is **staffing**, which
changes for budget or quality. A position holds an **array of seats**, because one office can be filled
more than once: a team lead is one office with a seat per Space.

| State | When | How it reads |
| --- | --- | --- |
| `staffed` | the seat names a `model` or a `person` | `Team lead · claude-opus-5-5 [beta]` |
| `vacant` | it names neither | `Team lead · vacant [gamma]` |

The state is **derived**, never written. There are only these two in v1; idle and active arrive with a
reader that can tell, not with a field someone types. If a seat names both a model and a person, the text
prints the model and the response carries both.

`OrgChart`'s line is `Position · model [space] (session)`: a seat's `roleTitle` stands in for the position's
title, `[space]` and `(session)` are there when the seat names them, and `· merges` ends the line of the seat
that holds the merge -- `Alpha lead · claude-opus-5-5 [alpha] (lead-session)`,
`VP of product · claude-fable-5-2 (product-session) · merges`. The model is printed as the file writes it; the
Org tab names it by the model map's `name`. No machine is printed or drawn.

- **The owner's seat** carries `person` and no model, and the position carries no `prompt`: it is a
  person, so its line reads `Owner · Sam`.
- **A pool** is a position with `seats: []` (or none) and a `defaultModel` line: builders come and go per
  card, so they are one line, `Builder · pool: sonnet for crew cards, ...`, not a seat each. A position with
  no seats and no default model reads `... · no seats`.

## What is checked

The whole file is checked before anything is drawn -- **every** tree, not only the one in use -- and the
first failure, in this order, is the answer. Each has a `kind` (a code the CLI and the agent's reader agree
on) and one sentence.

| Kind | When | Sentence |
| --- | --- | --- |
| `unreadable` | not JSON, or not an object at the top | `org.json is not valid JSON (<the parser's words>).` / `org.json must be a JSON object at the top level.` |
| `no-trees` | `trees` absent, not an array or empty | `org.json has no trees: 'trees' must be an array with at least one tree.` |
| `missing-id` | a tree, position or seat with no id, in document order | `Tree 2 has no id.` / `Position 3 of tree 'a' has no id.` / `Seat 2 of position 'x' in tree 'a' has no id.` |
| `duplicate-tree` | two trees share an id | `Two trees share the id 'a'.` |
| `no-active-tree` | `activeTree` absent and more than one tree | `'activeTree' is not set and org.json has 2 trees (a, b): name the one in use.` |
| `unknown-active-tree` | `activeTree` names no tree | `'activeTree' names 'zzz', which is not a tree. Trees: a, b.` |
| `duplicate-position` | two positions in a tree share an id | `Two positions in tree 'a' share the id 'x'.` |
| `duplicate-seat` | two seats in a position share an id | `Two seats in position 'x' of tree 'a' share the id 's'.` |
| `unknown-reports-to` | a `reportsTo` names no position **in that tree** | `Position 'y' in tree 'a' reports to 'elsewhere', which is not a position in that tree.` |
| `cycle` | positions report to each other in a loop | `Positions in tree 'a' report to each other in a loop: p -> r -> q -> p.` |
| `no-root` | no position reports to nobody (a tree with no positions) | `Tree 'a' has no root: exactly one position reports to nobody.` |
| `several-roots` | more than one does | `Tree 'a' has 2 roots (x, y): exactly one position reports to nobody.` |
| `unknown-prompt` | a `prompt` that is a file in none of the three folders | `Position 'y' in tree 'a' names the prompt 'missing.prompt.md', which is not a file in the hub's agentic/org/ or agentic/ folder or the toolkit's agentic/org/.` |

The loop is named from the position where the walk up from the first affected position closes it, so a
position hanging off a loop is not in the sentence. A loop is said before a missing root (a tree whose every
position reports to another has both). A `prompt` that holds a path separator, `.` or `..`, or names a
folder, is an `unknown-prompt`: it is a file **name** in one of the three folders and cannot point out of
them. The hub's agentic folder is resolved as `hub.json` says (`folders.agentic`), and the sentence names
it as it is called there.

Two kinds belong to the reader's callers rather than to the file: `missing` (no `org.json` at the hub
root) and `unknown-tree` (`-Tree` names a tree the file does not have).

The table is one file, [`Tests/fixtures/org/table.json`](../../Tests/fixtures/org/table.json), a case per
row above and per way a valid file reads; `tkTestToolkit -OrgChart` asserts it for the CLI's reader, and
the agent's reader (`agent/solitaire/org.py`, a mirror of the CLI's: the same checks in the same order, the
same tolerance of an unknown key, the same derived state) is held to the same file by `Tests/test_org.py`,
**the `kind` being the contract** and the sentence the CLI's wording.

## The response

`OrgChart -AsJson` prints it, and `GET /api/ritual/org` (`consts.json` `rituals.orgRoute`) serves the same
document: the tree in use (or the one `-Tree` / `?tree=<id>` asks for) with its positions in **tree order** -- the root, then each position's reports in the file's
order, depth first -- each with its `level`, root 0. Every key is always there; one that is not set is
`null` (an array that is not set is `[]`), so both halves serialise one shape. `merges` is `true` or `false`
where the file says so and `null` where it does not.

```json
{
  "activeTree": "branch-office",
  "tree": {
    "id": "branch-office",
    "title": "The Branch Office",
    "size": "M",
    "shortDescription": "Local leads run the work: ...",
    "description": "Each product has its own team lead, ...",
    "teamSize": 6,
    "preset": "branch-office",
    "positions": [
      { "id": "owner", "title": "Owner", "prompt": null, "reportsTo": null, "defaultModel": null,
        "recommend": [], "level": 0,
        "seats": [ { "id": "owner", "roleTitle": null, "model": null, "person": "Sam", "session": null,
                     "merges": null, "space": null, "state": "staffed" } ] },
      { "id": "team-lead", "title": "Team lead", "prompt": "team-lead.prompt.md",
        "reportsTo": "vp-engineering", "defaultModel": null, "recommend": [], "level": 2,
        "seats": [ { "id": "alpha", "roleTitle": "Alpha lead", "model": "claude-opus-5-5", "person": null,
                     "session": "lead-session", "merges": null, "space": "alpha", "state": "staffed" } ] },
      { "id": "builder", "title": "Builder", "prompt": null, "reportsTo": "team-lead",
        "defaultModel": "claude-sonnet-5-5", "recommend": [], "level": 3, "seats": [] }
    ]
  }
}
```

The tree's `title` is the file's `title`, else an older file's `name`, else the id; the response has no `name`.
The retired keys are not in it at all: no `machines`, no seat `machine` or `active`, so nothing downstream can
draw one.

`activeTree` is always the file's own choice, so a reader asked for another tree still knows which is in
use. [`Tests/fixtures/org/charts/`](../../Tests/fixtures/org/charts/) holds the responses the table states.

**The one difference between the two halves: the fields only the route adds.** The route adds three keys to
every position and one to every seat, which `OrgChart -AsJson` does not print -- the CLI has no prompt reader,
and the Studio's is the agent's; the model's name is what the Org tab draws, and the terminal prints the model as
the file writes it:

| Key | Is | From |
| --- | --- | --- |
| `promptTitle` | the prompt's title: its front matter's `title`, else its one `#` heading, else the file's name without `.prompt.md` | `agent/studio/prompts.py`'s `record`, the one reader every prompt goes through -- not a second parser |
| `promptRef` | the address after `/studio/prompts/` that opens the prompt in the Studio's reading room: `yours/<name>` for the hub's copy, `<name>` for a role the toolkit ships -- the `ref` a Studio prompt row carries (the web builds the link with `promptPath(ref)`) | the same rule the Studio lists by; `null` for a file the room does not list (not `<name>.prompt.md`, or a name that is not a plain word), which still has its title |
| `defaultModelName` (a position's) | its `defaultModel` line by the same lookup as `modelName`: a pool's line that `Staff` wrote as an id reads as the model's name ("Sonnet 5.5"); words read as written; `null` with no line | the same as `modelName` |
| `modelName` (a seat's) | what the seat's `model` is called: the model map's `name` for an id it has a row for ("Opus 5.5"); for a family the map's `current` names (`opus`), the name of the id that family is today; anything else as written; `null` with no model | `agent/core/models.py`'s `model_info` and `current_model`, the lookup the Agent line uses -- looked up, never parsed |

The prompt fields are `null` on a position with no `prompt`. The file read is the one the reading room opens -- the
machine's `agenticExtensionPath` copy where there is one, else the first of the
[three folders](#where-a-positions-prompt-is-found) that has it. Everything else in the response
is byte for byte the CLI's (`Tests/test_org.py` strips the three keys and compares the rest to the table's
responses, and checks `modelName` against a row's `modelNames` where the table states them).

### What the route answers when there is no chart

Every refusal's `detail` is `{ "kind": ..., "message": ... }`, so a caller tells a missing file from an
invalid one without reading the sentence; the gate's own 404 (the module is off) is a plain string.

| Status | `kind` | When |
| --- | --- | --- |
| 404 | `no-hub` | no hub is configured (nobody said where it is) |
| 404 | `missing` | no `org.json` at the hub root, or the hub's folder is not there |
| 409 | any in [What is checked](#what-is-checked) | the file is there and fails its checks: the request is fine and the stored file conflicts |
| 422 | `unknown-tree` | `?tree=` names a tree the file does not have (the sentence lists the trees) |
| 404 | -- (string detail) | Team Agile is off in the Space you are in, whatever the file says |

`?tree=` is trimmed, as `-Tree` is. A key the tool does not read is said once in the agent's log and is not
in the response. There is no `space` parameter: the file is the engineer's, and the Space you are in only
decides whether the module is on.

## The CLI names it

`OrgChart` prints the text, `OrgChart -Tree <id>` another tree of the file, `OrgChart -AsJson` the response
([CLI](../CLI.md), the command reference). It reads one file and writes nothing; every refusal is a stated
one (`exit 2`, the sentence, a hint that names the file) -- no hub configured, no `org.json`, an invalid
file, an unknown `-Tree`. The inventory names the surface whether or not it is on, as the **Org chart** row
(`tkEnv`, `tkMenu -All`):

| State | When |
| --- | --- |
| `off` | Team Agile is off in the Space you are in -- *or* the file is there and fails its checks, in which case the note carries the sentence |
| `not configured` | Team Agile is on and there is no `org.json` |
| `on` | Team Agile is on and the file is valid: the tree's title and its seat count |

Its question, "Who sits in which seat in my org?", is in `Config/settings-workflows.json`.

## The scope -- where it is and is not there

The chart rides Team Agile, and Team Agile is on only where `features.solitaireAgile` is on **and** the
Space you are in is answered `agents` ([`howIWork`](../CONFIGURATION.md#spaceshowiwork----how-you-work-in-this-space)).
The file is the engineer's and sits at the hub root, but the **view of it is Team Agile's**: stand in a
Space that is not worked with agents and `OrgChart` is not there -- no verb, no menu line, no `-Help` --
even though the file is. That is the module rule, not a fault; to see the chart from a Space, answer it
`agents`.

## Org presets

A team starting out should not have to draw an org from an empty file. The toolkit ships three **presets**,
each one tree in this file's shape that names only the roles the toolkit ships, in
[`samples/org-presets/`](../../samples/org-presets/) -- beside the sample hub, read from the package and never
never used in place. The Org tab previews them ([Team Agile, the web UI](../modules/solitaire-agile.md#the-web-ui)),
and [`Staff -Preset`](#the-one-writer-staff) saves a copy of one as a tree of `org.json`; the folder is
`consts.json` `org.presetsFolder`.

| Size | Preset | `id` | Seats | Room | Fits |
| --- | --- | --- | --- | --- | --- |
| S | The Executive Suite | `executive-suite` | the owner, the VP of engineering (drives the work through builders) and the VP of product (reads what ships and holds the merge); a builder pool | 3 | one product, one person, moving fast |
| M | The Branch Office | `branch-office` | S, plus a team lead with a seat per product and builders under them, and a test runner; leads send their readies straight to the seat that merges | 6 | two or three products |
| L | Corporate Headquarters | `corporate-headquarters` | M, plus a PM the leads report to, a merge stand-in, the butler (the weekly bot) and the intern | 9 | many products, a heavy merge queue, an owner with little time |

In every preset **the VP of product holds the merge**. The roles write the merge once, as the VP of
engineering's by default, and let a team place it elsewhere ([the roles](../../agentic/org/README.md)); each
preset's description says where it sits. The merge stand-in covers that seat's merge. The owner's seat is a person (`You`); every other seat is open, for the owner to fill. No seat names a machine, and no
tree lists any: sessions talk across machines, so a machine is not a boundary in an org.
The test runner, the merge stand-in and the builders name no role, because none is shipped for them. L has ten seats for a room of
nine: the room seats who has work first, and the butler is a weekly bot.

A preset file is **one tree** in [the shape](#a-tree), read as the one tree of a file, and it validates against
the schema's `#/$defs/tree`. The fields a preset uses:

| Key | Is |
| --- | --- |
| `id` | the preset's address, and the tree's id |
| `size` | `S`, `M` or `L`; the order they are offered in |
| `title` | its name, and the tree's title |
| `shortDescription` | one line: what it is and what it fits, kept for a place that names a preset briefly; the Org tab shows the description |
| `description` | a few sentences: how the work flows, who owns what, what it fits |
| `teamSize` | the standup room it suggests, 3, 6 or 9. The Space's own `features.teamSize` decides the room; a preset sets nothing |
| `positions` | the tree's positions, in the shape above |

**A preset's reader ignores a field it does not know**, at every level, without a word (the hub's file names one
once), so a later field (a preset's swag, its ways of working) can be added without breaking a reader that
predates it.
`GET /api/ritual/org/presets` (`consts.json` `rituals.orgPresetsRoute`) serves all three, S first, each with
its `chart` in [the response](#the-response)'s shape and the fields only the route adds; the tree passes every check in
[What is checked](#what-is-checked), its prompts looked up in the toolkit's `agentic/org/` alone, and a file that
does not read as a preset is left out and said in the agent's log. `Tests/test_org.py` holds each preset to the
checks and to the shipped roles. `OrgChart -Preset` is not built yet: the CLI does not print a preset.

## The one writer: Staff

`Staff` rides Team Agile like `OrgChart`, so it is there exactly where the chart is ([the scope](#the-scope----where-it-is-and-is-not-there)),
and it writes `org.json` and nothing else. Two forms:

```text
Staff -Preset S|M|L [-Tree <id>] [-Title <text>] [-Owner <name>] [-VpEngineering <model>] [-VpProduct <model>] [-WhatIf]
Staff -Activate <tree-id> [-WhatIf]
```

- **`-Preset` saves a tree** from the [preset](#org-presets) of that size, creating the file when there is none.
  The tree is the preset's, key for key, under its new id, with `preset` set to the preset's id (the preset file's
  own `_` notes describe the preset and are not copied). `-Title` names it in place of the preset's title, and
  `-Owner` names the owner -- the root's seat, a person and never a model -- in place of the preset's `You`.
- **The default models are filled in**, each stored as a [`Config/models.json`](../../Config/models.json) id: a
  family resolves through the map's `current` block, an id passes through, and nothing is parsed. A name that is
  neither is refused.

  | Position | Its seats start with |
  | --- | --- |
  | `vp-engineering` | Opus, or `-VpEngineering <model>` |
  | `vp-product` | Fable, or `-VpProduct <model>`, and `merges: true` |
  | `team-lead` | Opus, every seat |
  | `intern`, `butler` | Haiku |
  | `builder` (the pool) | its `defaultModel` line becomes Sonnet's id |
  | `pm`, `test-runner`, `merge-stand-in`, and any other | vacant |

- **A saved tree is a draft.** `-Preset` never changes the tree in use; `-Activate <tree-id>` is the one way to
  choose it, and it does not go with `-Preset`. The first tree of a new file is the only one, so by the reading
  rule it is the one in use, and the file is written without `activeTree`. Adding a second tree to a file that names
  none sets `activeTree` to the tree that was in use -- never the draft -- so the file stays valid, and the output
  says which stays active.
- **A tree is never overwritten.** Its id is `-Tree`, else the preset's id, then `<id>-2` and `<id>-3`. A `-Tree`
  must be a plain word -- letters, digits, `-` and `_` -- so the `Staff -Activate <id>` the output prints always types
  as it reads. An id that is already a tree is refused, and so is a fourth tree, naming the three. `-Activate` with an
  id that is not a tree is refused, listing the trees; `-Activate` on the tree already in use (the file's `activeTree`,
  or its one tree) writes nothing.
- **Every write** reads the file, changes only what the command names, and keeps every other tree, key and note in
  its order. A file that fails [its checks](#what-is-checked) is refused before anything changes, and the result is
  checked with the reader's own checks (`Read-P20OrgText`, the same as `OrgChart`'s) before it lands. It is written
  as two-space JSON -- one text on PowerShell 7 and Windows PowerShell 5.1, non-ASCII as itself -- UTF-8 with no
  BOM, through `Write-CardText`: a created file is LF, an edited one keeps its own line ending. The bytes go to a
  temp file beside `org.json` and are renamed over it, so a write that fails leaves the file as it was. Reformatting is the
  writer's: a hand-written file comes back in its layout, not yours.
- **It never prompts.** A refusal is a stated one (`exit 2`, one sentence and a hint) and writes nothing; `-WhatIf`
  prints the file it would write and writes nothing. `POST /api/cmd/Staff` runs it through the bridge.

`tkTestToolkit -OrgChart` types it in a fresh shell over a scratch copy of the sample hub, and
`Tests/test_bridge.py` runs it through the bridge.

## What is not in v1

No seat editor yet (`Staff` adds a tree and chooses the one in use; editing one seat is a later form of it), no
way to start from a preset on the Org tab (the page previews; `Staff -Preset` saves), no machine drawn (the retired `machines`, `machine` and `active` are
read and never served), no picker reading `recommend` yet, no count of builders from the cards in flight, and no
join with the standup's workers. `merges` is read, served and printed, and not yet drawn on the Org tab. The web's
Org tab draws the tree the route serves ([Team Agile, the web UI](../modules/solitaire-agile.md#the-web-ui)): a
seat's `roleTitle` and its model's name on the plate, its session on hover; a vacant seat is drawn as an empty desk.

## An example to copy

[`samples/hub/org.json`](../../samples/hub/org.json) is a small tree, copied out with the rest of the
sample hub: an owner, with a VP of product, a VP of engineering and a PM reporting to it; a butler under
the VP of product; a team lead under the PM, with one staffed and one vacant seat, and a builder pool under
the lead; and an intern under the PM. Eight seats in all. Every office names the role the toolkit ships for
it -- `vp-of-product.prompt.md`, `butler.prompt.md`, `vp-of-engineering.prompt.md`, `pm.prompt.md`,
`team-lead.prompt.md` and `intern.prompt.md` -- and the sample hub copies none of them, so each is found in
the toolkit's `agentic/org/`. The owner is a person and the builder a pool, so neither names a role.

The butler reports to the VP of product because whether a design is finished is the product's call: the
butler stamps by itself and reports what looks finished, and that seat runs the archive moves. The lead
reports to the PM because the PM is the seat that hands it a queue and carries its readies to the seat that merges; a team where engineering hands out the work would put the lead under the VP of
engineering instead, as the example under [The shape](#the-shape) does. The roles name their neighbours
by relationship, so either tree reads the same to them.
