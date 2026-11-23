# The org chart -- `org.json`

`org.json` is the hub's picture of an organisation as a tree: the **positions** it has (an office, not
whoever sits in it), who each one reports to, and which model or person sits in each **seat** today. One
file, one reader, and nothing in it is derived from the cards: it is what you say your org is, and the
tool draws it back so a change in who sits where is something you can see.

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

It is **hand-edited** and the tool only reads it. `Config` does not write it; `Staff` is a later verb.
It is UTF-8, with or without a BOM.

## The shape

```json
{
  "activeTree": "main",
  "trees": [
    {
      "id": "main",
      "name": "Laptop and mini",
      "machines": ["laptop", "mini"],
      "positions": [
        { "id": "owner", "title": "Owner",
          "seats": [ { "id": "owner", "person": "Sam" } ] },
        { "id": "vp-engineering", "title": "VP of engineering",
          "prompt": "vp-of-engineering.prompt.md", "reportsTo": "owner", "defaultModel": "fable",
          "seats": [ { "id": "vp-engineering", "model": "fable", "machine": "mini" } ] },
        { "id": "team-lead", "title": "Team lead",
          "prompt": "team-lead.prompt.md", "reportsTo": "vp-engineering", "defaultModel": "opus",
          "seats": [
            { "id": "alpha", "model": "fable", "machine": "mini", "space": "alpha" },
            { "id": "beta",  "model": "opus",  "machine": "mini", "space": "beta" },
            { "id": "gamma", "machine": "mini", "space": "gamma" }
          ] },
        { "id": "builder", "title": "Builder", "reportsTo": "team-lead",
          "defaultModel": "sonnet for crew cards, opus across halves", "seats": [] }
      ]
    }
  ]
}
```

Everything is an **array of objects addressed by `id`**, never an object keyed by name, so a later `Config`
can write `trees.<id>.positions.<id>.seats.<id>.model` without a second shape. The words `orgs` and
`activeOrg` are not used: they are the retired spellings of `spaces` and `activeSpace`, and an "org" here
is the tree you draw, never a Space.

| Level | Key | Required | Meaning |
| --- | --- | --- | --- |
| file | `activeTree` | when there is more than one tree | the id of the tree in use. With exactly one tree it may be left out and that tree is the one |
| file | `trees` | yes | an array of at least one tree |
| tree | `id` | yes | the tree's address; unique among trees |
| tree | `name` | no | what it is called; the id when absent |
| tree | `machines` | no | the machines this configuration runs on, as words you choose (`laptop`, `mini`) |
| tree | `positions` | yes | the tree's positions, in the order you want siblings drawn |
| position | `id` | yes | unique within its tree. The same id in two trees is fine |
| position | `title` | no | the office's name; the id when absent |
| position | `prompt` | no | the **file name** of the position's role -- its job description -- looked up in three folders, in order ([Where a position's prompt is found](#where-a-positions-prompt-is-found)). A name, not a path |
| position | `reportsTo` | on every position but the root | the id of the position it reports up to |
| position | `defaultModel` | no | free text: the model this office is meant to have, or a line about how it is staffed |
| position | `seats` | no | an array of seats; absent or `[]` means a pool |
| seat | `id` | yes | unique within its position |
| seat | `model` | one of `model`, `person`, or neither | the model sitting there |
| seat | `person` | " | a person sitting there (free text) |
| seat | `machine` | no | where it runs, a word from the tree's `machines`. Not checked against them |
| seat | `space` | no | the Space slug the seat serves. Not checked against the hub's Spaces |
| seat | `active` | no | a boolean, **tolerated and never written, and not drawn in v1**: the file cannot say truthfully whether a session is running now, so a reader keeps the value and does nothing with it |

A key the tool does not read is **ignored with a warning** naming where it is, as `hub.json` treats one
(`org.json: 'x' is not a key this tool reads in position 'p' of tree 't' -- ignored.`). A key that starts
with an underscore is a note and is not said. Key names are matched exactly, case included, and an id is
compared character for character (`A` is not `a`); a number given as an id is read as its text.

## Where a position's prompt is found

A position's `prompt` names a **role**: a job description, one `<role>.prompt.md`. The toolkit ships
five in its own `agentic/org/` -- `pm`, `team-lead`, `vp-of-engineering`, `vp-of-product` and `intern`,
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
| `staffed` | the seat names a `model` or a `person` | `Team lead · fable [alpha] (mini)` |
| `vacant` | it names neither | `Team lead · vacant [gamma] (mini)` |

The state is **derived**, never written. There are only these two in v1; idle and active arrive with a
reader that can tell, not with a field someone types. If a seat names both a model and a person, the text
prints the model and the response carries both.

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
`null` (an array that is not set is `[]`), so both halves serialise one shape.

```json
{
  "activeTree": "main",
  "tree": {
    "id": "main",
    "name": "Laptop and mini",
    "machines": ["laptop", "mini"],
    "positions": [
      { "id": "owner", "title": "Owner", "prompt": null, "reportsTo": null, "defaultModel": null,
        "level": 0,
        "seats": [ { "id": "owner", "model": null, "person": "Sam", "machine": null, "space": null,
                     "active": null, "state": "staffed" } ] },
      { "id": "team-lead", "title": "Team lead", "prompt": "team-lead.prompt.md",
        "reportsTo": "vp-engineering", "defaultModel": "opus", "level": 2,
        "seats": [ { "id": "gamma", "model": null, "person": null, "machine": "mini", "space": "gamma",
                     "active": null, "state": "vacant" } ] },
      { "id": "builder", "title": "Builder", "prompt": null, "reportsTo": "team-lead",
        "defaultModel": "sonnet for crew cards, opus across halves", "level": 3, "seats": [] }
    ]
  }
}
```

`activeTree` is always the file's own choice, so a reader asked for another tree still knows which is in
use. [`Tests/fixtures/org/charts/`](../../Tests/fixtures/org/charts/) holds the responses the table states.

**The one difference between the two halves: the prompt fields.** The route adds two keys to every
position, which `OrgChart -AsJson` does not print -- the CLI has no prompt reader, and the Studio's is the
agent's:

| Key | Is | From |
| --- | --- | --- |
| `promptTitle` | the prompt's title: its front matter's `title`, else its one `#` heading, else the file's name without `.prompt.md` | `agent/studio/prompts.py`'s `record`, the one reader every prompt goes through -- not a second parser |
| `promptRef` | the address after `/studio/prompts/` that opens the prompt in the Studio's reading room: `yours/<name>` for the hub's copy, `<name>` for a role the toolkit ships -- the `ref` a Studio prompt row carries (the web builds the link with `promptPath(ref)`) | the same rule the Studio lists by; `null` for a file the room does not list (not `<name>.prompt.md`, or a name that is not a plain word), which still has its title |

Both are `null` on a position with no `prompt`. The file read is the one the reading room opens -- the
machine's `agenticExtensionPath` copy where there is one, else the first of the
[three folders](#where-a-positions-prompt-is-found) that has it. Everything else in the response
is byte for byte the CLI's (`Tests/test_org.py` strips the two keys and compares the rest to the table's
responses).

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
| `on` | Team Agile is on and the file is valid: the tree's name and its seat count |

Its question, "Who sits in which seat in my org?", is in `Config/settings-workflows.json`.

## The scope -- where it is and is not there

The chart rides Team Agile, and Team Agile is on only where `features.solitaireAgile` is on **and** the
Space you are in is answered `agents` ([`howIWork`](../CONFIGURATION.md#spaceshowiwork----how-you-work-in-this-space)).
The file is the engineer's and sits at the hub root, but the **view of it is Team Agile's**: stand in a
Space that is not worked with agents and `OrgChart` is not there -- no verb, no menu line, no `-Help` --
even though the file is. That is the module rule, not a fault; to see the chart from a Space, answer it
`agents`.

## What is not in v1

No writer (`Config` and a `Staff` verb come later), no `active` drawn, no count of builders from the cards
in flight, and no join with the standup's workers. The web's Org tab draws the tree the route serves
([Team Agile, the web UI](../modules/solitaire-agile.md#the-web-ui)); a vacant seat is drawn as an empty desk.

## An example to copy

[`samples/hub/org.json`](../../samples/hub/org.json) is a small tree, copied out with the rest of the
sample hub: an owner, with a VP of product, a VP of engineering and a PM reporting to it; a team lead
under the PM, with one staffed and one vacant seat, and a builder pool under the lead; and an intern under
the PM. Seven seats in all. Every office names the role the toolkit ships for it -- `vp-of-product.prompt.md`,
`vp-of-engineering.prompt.md`, `pm.prompt.md`, `team-lead.prompt.md` and `intern.prompt.md` -- and the
sample hub copies none of them, so each is found in the toolkit's `agentic/org/`. The owner is a person and
the builder a pool, so neither names a role.

The lead reports to the PM because the PM is the seat that hands it a queue and carries its readies to the
seat that merges; a team where engineering hands out the work would put the lead under the VP of
engineering instead, as the example under [The shape](#the-shape) does. The roles name their neighbours
by relationship, so either tree reads the same to them.
