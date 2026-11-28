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
| `shortDescription` | no | one line: what the org is. A count in it states the design's own limit (one team, a team for each project), never the user's world |
| `description` | no | a few sentences: how the work flows and who owns what, by the same rule for counts |
| `teamSize` | no | the standup room the org suggests: 3, 6 or 9. A suggestion only: the Space's `features.teamSize` decides the room |
| `preset` | no | the id of the preset the tree was started from |
| `activatedAt` | no | the day the tree last **became the org in use**, `YYYY-MM-DD`, written by `Staff` ([An org's state](#an-orgs-state)). A hand edit may write it; nothing asks one to |
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
| `portrait` | no | the picture the Org tab draws in the seat, on a seat that takes one ([A seat's portrait](#a-seats-portrait)): an id of `consts.json` `org.portraits`. Absent is the seat's own default face |
| `machine`, `active` | no, **retired** | read without a word, never drawn |

**Derived, never written:** a seat is `staffed` when it names a `model` or a `person`, and `vacant` otherwise
([Positions, seats, and the three shapes](#positions-seats-and-the-three-shapes)). A position with no seats is a
pool. A field of the wrong type reads as unset: `merges` only as a JSON `true` or `false`, `teamSize` only as a
whole number, `recommend` only as an array (its text entries trimmed, the empty and the non-text left out), and the
text fields as text (a number as its text).

### One complete tree

A tree started from the Branch Office and then edited by hand -- its one team lead office given a second seat --
after the owner has named themselves ("Sam") and a few seats are filled. The preset itself has one team, one lead
and its own builders ([Org presets](#org-presets)); a hand-made office of several seats reads and draws as well:

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

## An org's state

Each tree of the file has a state, **derived and never stored**, so it can never disagree with `activeTree`:

| State | When |
| --- | --- |
| `active` | `activeTree` names it -- or, with one tree and no `activeTree`, it is that tree. The one pointer, so exactly one tree is active |
| `inactive` | it is not active and carries an `activatedAt`: it was in use before, and another is now |
| `draft` | it is not active and carries no `activatedAt`: saved, and never in use. In an older file with no stamps, every tree but the active one reads as a draft |

`activatedAt` is the one stored fact behind it, and `Staff` writes it whenever a tree **becomes** the org in use:
`Staff -Activate` stamps the tree it puts in use; `Staff -Preset` stamps a new file's first tree, which is in use
from the moment it is saved; and whenever `Staff` adds a tree beside, or `-Activate` takes out of use, a tree in use
that has no stamp, it stamps that tree too, so it reads inactive rather than draft. `-Activate` on the tree already
in use writes nothing. **A stamp written that way records the day `Staff` first knew the tree had been in use**,
not the day it was first used, so read `activatedAt` as "in use by this day", never as a first-use date. A stamp
that is not a date (`26 November`, a number) is still a stamp: the readers do not parse it, so its tree reads
inactive, and the schema refuses its shape. Both readers derive the state the same way -- the CLI's `Get-P20OrgTreeState`, the agent's
`tree_state` -- from one shared table, [`Tests/fixtures/org/state.json`](../../Tests/fixtures/org/state.json),
asserted by `tkTestToolkit -OrgChart` and `Tests/test_org.py`. `OrgChart` lists a file's trees with their states
(`Trees: main (active), branch (draft)`) when it has more than one, and the route's `trees` carries each one's
`state` and `activatedAt`.

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
more than once. The presets give each team an office of its own instead -- one lead seat and the team's own
builder pool under it, a column a team -- and a hand-made office of several seats is drawn as a room.

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
Org tab names it by the model map's `name`. No machine is printed or drawn. A vacant seat that names a session
prints it too: `PM · vacant (desk-one)`.

**The count.** `OrgChart`'s text ends with an empty line and one count, `staffed: 4 of 10`. A **seat** is an entry
in a position's `seats` -- an office's seats, the owner's seat among them -- and a pool has none, so it counts
nothing however many builders it stands for. A seat is **staffed** when its state is: it names a `model` or a
`person`. That is the state the Org tab draws a vacant desk from, so the count is the page's staffed seats over
its seats. `OrgChart -AsJson` and the route carry the same facts -- each seat's `state` and `session` -- and no
count of their own. The rows that pin it are `tkTestToolkit -OrgChart`'s, one per shape: an office of several
seats, a person's seat, a pool, a seat with a session and nothing else (vacant), and a tree of pools
(`staffed: 0 of 0`).

- **The owner's seat** carries `person` and no model, and the position carries no `prompt`: it is a
  person, so its line reads `Owner · Sam`.
- **A pool** is a position with `seats: []` (or none) and a `defaultModel` line: builders come and go per
  card, so they are one line, `Builder · pool: sonnet for crew cards, ...`, not a seat each. A position with
  no seats and no default model reads `... · no seats`.

### A seat's portrait

A seat may choose the picture the Org tab draws in it. **One rule says which seats take one:** `consts.json`
`org.portraitSeats`, a list whose entries are `root` -- the root position's seat, the owner's -- or a key of
`org.roles`, naming the seats of every position whose role (its `prompt`) is that file (`vpEngineering`,
`vpProduct`). Today it is `["root"]`: **the owner's seat alone takes a portrait.** The CLI
(`Test-P20OrgTakesPortrait`), the agent (`takes_portrait`) and the web (`takesPortrait`) each read that list,
so widening it to the two VPs is a change to that one line and to the rows of the shared table below, and to
nothing else. A seat is told by its position's role and its place in the tree, never by its id: a hand-written
org with differently named positions takes a portrait at its root, and at a VP's office only where that office
names the VP's role file.

The portrait is an id of `consts.json` `org.portraits`: the cast's people -- `minimalist`, `pm`, `dev-hero`,
`designer`, `ultrawide`, `ops-dev`, `new-hire`, `vibemancer`, `qa` -- and four characters of their own,
`robot`, `alien`, `fat-cat` and `kubernetes-wizard`. Ids are matched exactly, case included, after a trim. **No
key is the default**, which is the face the seat always drew (the owner's own, for the owner): there is no id for
it, so `owner` is not one. Two seats may carry the same portrait. The seat's name and its position's title do not
change with it.

A reader serves `portrait` on a seat only where the rule names the seat and the id is one of the list; any other
non-empty `portrait` -- an unknown id, or one on a seat the rule does not name -- is **ignored for drawing and
said once as a warning** (`org.json: the portrait 'Robot' in seat 'owner' of position 'owner' in tree 't' is not
one this tool draws -- ignored.`, `org.json: the portrait in seat 'pm' of position 'pm' in tree 't' is on a seat
that takes none -- ignored.`), the way an unread key is, and the file is never refused for it. An empty one is no
portrait and is not said. `Staff -Seat <seat> -Portrait <id>` is the one writer ([The one writer:
Staff](#the-one-writer-staff)). [`Tests/fixtures/org/portraits.json`](../../Tests/fixtures/org/portraits.json) holds
both halves to it: every id, valid or not, and a row per seat kind -- the owner with a valid id, an unknown id and
an empty one, each VP, a PM, a team lead, a builder and a pool -- with whether the rule names the seat and what
`Staff` does.

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
where the file says so and `null` where it does not. **One key is the exception:** a seat's `portrait` is there
only where it is served ([A seat's portrait](#a-seats-portrait)), so a file without one reads exactly as before.
`OrgChart` prints it after the seat's line, `Owner · Sam · portrait: robot`.

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

**The one difference between the two halves: the fields only the route adds.** The route adds four keys to
every position, two to every seat and four to the document, which `OrgChart -AsJson` does not print -- the CLI has no prompt reader,
and the Studio's is the agent's; the model's name is what the Org tab draws, and the terminal prints the model as
the file writes it:

| Key | Is | From |
| --- | --- | --- |
| `promptTitle` | the prompt's title: its front matter's `title`, else its one `#` heading, else the file's name without `.prompt.md` | `agent/studio/prompts.py`'s `record`, the one reader every prompt goes through -- not a second parser |
| `promptRef` | the address after `/studio/prompts/` that opens the prompt in the Studio's reading room: `yours/<name>` for the hub's copy, `<name>` for a role the toolkit ships -- the `ref` a Studio prompt row carries (the web builds the link with `promptPath(ref)`) | the same rule the Studio lists by; `null` for a file the room does not list (not `<name>.prompt.md`, or a name that is not a plain word), which still has its title |
| `defaultModelFamily` (a position's) | the family of its `defaultModel` line by the same lookup as `modelFamily`; `null` where the map does not know it | the same as `modelFamily` |
| `defaultModelName` (a position's) | its `defaultModel` line by the same lookup as `modelName`: a pool's line that `Staff` wrote as an id reads as the model's name ("Sonnet 5.5"); words read as written; `null` with no line | the same as `modelName` |
| `trees` (the document's) | every tree of the file, in its order, as the Org tab's View and Active dropdowns list them: `{ "id", "title", "size", "preset", "active", "state", "activatedAt" }` -- `state` is [the tree's state](#an-orgs-state), `active` true on the active one alone -- each read as that tree's own chart reads it (`title`, `size`, `preset` and `activatedAt` `null` where unset) -- the same list whichever tree `?tree=` asks for | `agent/solitaire/org.py`'s `tree_summaries`, over the trees the reader has already checked |
| `etag` (the document's) | the SHA-256 of `org.json`'s bytes as this read saw them, lowercase hex -- the same whichever tree `?tree=` asks for. The seat dialog sends it back as `Staff -Seat -IfMatch`, so a file changed since the page read it is refused rather than written over | `agent/solitaire/org.py`'s `find_org_chart`, over the bytes it parsed |
| `families` (the document's) | the model families a seat can be staffed with: the keys of the model map's `current` block, in its order -- what the seat dialog offers a seat that is not a VP's | `agent/core/models.py`'s `read_model_current` |
| `familyNames` (the document's) | each of `families` by the name of the model it resolves to today ("Opus 5.5"): the model map's `name` for the `current` id, looked up, never parsed -- the seat dialog's labels, so the page types no version | `agent/solitaire/org.py`'s `family_names` |
| `modelFamily` (a seat's) | the family of the seat's `model`: the map's `family` for an id it has a row for, the family itself for one `current` names, `null` otherwise -- the choice the seat dialog starts on | `agent/solitaire/org.py`'s `model_family`, looked up, never parsed |
| `modelName` (a seat's) | what the seat's `model` is called: the model map's `name` for an id it has a row for ("Opus 5.5"); for a family the map's `current` names (`opus`), the name of the id that family is today; anything else as written; `null` with no model | `agent/core/models.py`'s `model_info` and `current_model`, the lookup the Agent line uses -- looked up, never parsed |

The prompt fields are `null` on a position with no `prompt`. The file read is the one the reading room opens -- the
machine's `agenticExtensionPath` copy where there is one, else the first of the
[three folders](#where-a-positions-prompt-is-found) that has it. Everything else in the response
is byte for byte the CLI's (`Tests/test_org.py` strips the route's keys and compares the rest to the table's
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

| Size | Preset | `id` | Seats | Room |
| --- | --- | --- | --- | --- |
| S | The Executive Suite | `executive-suite` | the owner, the VP of engineering (drives the work through builders) and the VP of product (reads what ships and holds the merge); a builder pool | 3 |
| M | The Branch Office | `branch-office` | S, plus one team -- a team lead (`lead-team`, one seat) with its own builder pool (`builders-team`) -- and a test runner; the lead sends its readies straight to the seat that merges | 6 |
| L | Corporate Headquarters | `corporate-headquarters` | M, plus a PM, a team for each project under it -- two to start, `lead-team-1` and `lead-team-2`, each one lead with its own builder pool (`builders-team-1`, `builders-team-2`) -- a merge stand-in, the butler (the weekly bot) and the intern | 9 |

In every preset **the VP of product holds the merge**. The roles write the merge once, as the VP of
engineering's by default, and let a team place it elsewhere ([the roles](../../agentic/org/README.md)); each
preset's description says where it sits. The merge stand-in covers that seat's merge. The owner's seat is a person (`You`); every other seat is open, for the owner to fill. No seat names a machine, and no
tree lists any: sessions talk across machines, so a machine is not a boundary in an org.
The test runner, the merge stand-in and the builders name no role, because none is shipped for them. A preset's
`teamSize` is the standup's room (3, 6 or 9, the chair counted), not a count of seats: the room seats who has work
first, and builders and invented cast members fill the windows left, so M's five seats sit in a room of six and
L's ten in a room of nine. Every
team lead's seat is `lead`, and no team names a Space yet: binding a team to a Space is a later step.

A preset file is **one tree** in [the shape](#a-tree), read as the one tree of a file, and it validates against
the schema's `#/$defs/tree`. The fields a preset uses:

| Key | Is |
| --- | --- |
| `id` | the preset's address, and the tree's id |
| `size` | `S`, `M` or `L`; the order they are offered in |
| `title` | its name, and the tree's title |
| `shortDescription` | one line: what the org is, kept for a place that names a preset briefly; the Org tab shows the description |
| `description` | a few sentences: how the work flows and who owns what |
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
and it writes `org.json` and nothing else. Three forms:

```text
Staff -Preset S|M|L [-Tree <id>] [-Title <text>] [-Owner <name>] [-VpEngineering <model>] [-VpProduct <model>] [-WhatIf]
Staff -Seat <position>[.<seat>] [-Tree <id>] [-Model <model>] [-Person <name>] [-Session <name>] [-Space <slug>]
      [-RoleName <file>] [-RoleTitle <text>] [-Portrait <id>] [-Merges] [-IfMatch <sha256>] [-WhatIf]
Staff -Seat <position>[.<seat>] -Vacate [-Tree <id>] [-IfMatch <sha256>] [-WhatIf]
Staff -Activate <tree-id> [-WhatIf]
```

- **`-Preset` saves a tree** from the [preset](#org-presets) of that size, creating the file when there is none.
  The tree is the preset's, key for key, under its new id, with `preset` set to the preset's id (the preset file's
  own `_` notes describe the preset and are not copied). `-Title` names it in place of the preset's title, and
  `-Owner` names the owner -- the root's seat, a person and never a model -- in place of the preset's `You`.
- **The default models are filled in**, each stored as a [`Config/models.json`](../../Config/models.json) id: a
  family resolves through the map's `current` block, an id passes through, and nothing is parsed. A name that is
  neither is refused. The two VP defaults and the owner's `You` are `consts.json` `org.steps`, the defaults the Org
  tab's "Use this org" steps show, so the page and the verb agree.

  The defaults are keyed by the **role** a position names -- its `prompt` -- not by its id, so every team's lead
  starts staffed whatever its office is called. The role files and their families are `consts.json`'s
  (`org.roles`, `org.roleDefaults`, and `org.steps` for the two VPs), which the seat dialog fills a vacant seat from too:

  | A position whose role is | Its seats start with |
  | --- | --- |
  | `vp-of-engineering.prompt.md` | Opus, or `-VpEngineering <model>` |
  | `vp-of-product.prompt.md` | Fable, or `-VpProduct <model>`, and `merges: true` |
  | `team-lead.prompt.md` | Opus, every seat |
  | `intern.prompt.md`, `butler.prompt.md` | Haiku |
  | any pool (no seats: the builders, each team's own) | its `defaultModel` line becomes Sonnet's id |
  | anything else -- the PM, the test runner, the merge stand-in | vacant |

- **`-Seat` staffs one seat** of a saved tree, active or a draft: the tree in use, or the one `-Tree` names. The
  seat is `<position>.<seat>`, the two ids with a dot between (an id may hold a dot itself; the split that names a real
  seat is the one taken), or **the position's id alone where the position has exactly one seat** -- `Staff -Seat
  vp-product -Model fable`; every office of every preset has one. The two-part reading comes first, so an address
  that named a seat before names the same one now: only where no split names a real seat is the whole address read
  as a position's id. A position of several seats is refused by its id alone, naming its seats (`'team-lead' is a
  position of 2 seats in the tree 'mine', so it does not say which. Its seats: team-lead.demo, team-lead.github-demo.`),
  and a pool as having none. An address that starts with a dash and names no seat is refused like any other unknown
  seat; typed bare after `-Seat` the binder takes it for a switch and refuses the missing address, and the page sends
  the address joined to its switch, as it sends every value. The change line names the seat by its whole address,
  however it was typed: `<position>.<seat>`, or, where either id holds a dot, each id quoted as the writer resolved
  it -- `'x.y'.'z'` -- so the line cannot be read two ways. **An id with a dot can make an address ambiguous:** with a
  position `x` holding a seat `y` and a position `x.y` holding one seat, `x.y` could name either, and the two-part
  reading wins, so it is `x`'s seat `y`. The full address is always exact: `x.y.z` names `x.y`'s seat `z`, since no
  other split of it names a seat. A switch given as false (`-Vacate:$false`, `-Merges:$false`) is a switch not
  given. `-Model` takes a family or an id and stores the id, as `-Preset` does; `-Person`, `-Session`
  (the session's name, the address readies go to) and `-Merges` (sets `merges: true`, and clears no other seat's: a
  stand-in may hold it too) are the seat's own. `-Space` is a team lead's -- a seat whose position's role is
  `consts.json` `org.roles.teamLead` -- and must be a Space the toolkit knows; any other seat's is refused, naming
  the position. **`-RoleName` (the position's `prompt`) and `-RoleTitle` (its `title`) belong to the position**, so
  they change every seat of it; a seat's own `roleTitle` is left as it is. An empty value takes that key away (an
  empty `-Space` on any seat). A typed value is one line: a newline, a tab or any other control character in it is
  refused, naming the switch, and nothing is stored. **`-Portrait <id>`** chooses the seat's picture on a seat
  [the rule](#a-seats-portrait) names -- today the owner's alone -- and is refused on any other seat, empty or not,
  naming the seats of the tree that take one (`-Portrait does not go on 'pm.pm', a PM's seat: in the tree 'mine',
  the seats that take one: owner.owner.`); an id that is not one of `org.portraits` is refused naming them, and
  `-Portrait ''` takes the key away, back to the seat's own default. **The owner's seat** -- the root's -- takes
  `-Person` and `-Portrait` only, and never an empty `-Person`: `-Model` on it is refused, because the owner is a person. It prints one line,
  `<position>.<seat>: <before> -> <after>`, each side the whole seat -- the position's title (a seat's own
  `roleTitle` before it), the model and the person, `[space]`, `(session)`, `· merges`, `· portrait: <id>`, and `{role file}` where
  `-RoleName` was given -- so every field the call set shows as a change; a call that changes nothing writes
  nothing and exits 0. No tree is stamped by a seat's edit.
- **`-Vacate` empties a seat:** it takes the seat's `model` and `session` away, and **nothing else**. The seat's
  `space`, its own `roleTitle`, its `merges`, a `person`, its notes and every other key stay, each in its place, so
  the file differs by those two lines. A `person` is kept because the seat is a person's as much as a model's: a seat
  a person holds still reads staffed after `-Vacate`, and `-Person ''` is how the person leaves. It goes alone:
  `-Model`, `-Person` or `-Session` with it is refused as a contradiction, and `-Space`, `-RoleName`, `-RoleTitle`,
  `-Merges` or `-Portrait` beside it as a second change: a portrait is kept by `-Vacate`, as a person is. The owner's seat is never vacated (`The owner's seat cannot be vacated:
  the owner is a person, and the seat always has one.`). It follows every rule above: the change line, `-WhatIf`,
  `-IfMatch`, the crash-safe write and the same bytes on both hosts; a seat with no model and no session writes
  nothing and exits 0.
- **`-IfMatch <sha256>`** is the SHA-256 of `org.json`'s bytes as the caller read them -- the route's `etag`. A file
  whose bytes have changed since is refused, `org.json changed since you read it; reload and try again.` (the words
  are `consts.json` `org.changedSince`), and nothing is written; the hash is checked again just before the rename, so a
  change made while the verb ran is refused too. A file that is not there at all is refused as that, first (`There is
  no org.json in the hub, so there is no seat to staff.`). [`Tests/fixtures/org/etag.json`](../../Tests/fixtures/org/etag.json)
  holds both halves to one hash: a file with a BOM, with CRLF, with a trailing newline and without. Without `-IfMatch`, `-Seat` edits the file as it is now: a person
  typing the verb is looking at the current file.
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
  temp file beside `org.json` and are renamed over it, so a write that fails leaves the file as it was. **The writer
  owns the file's layout:** the first write through `Staff` -- a `-Seat` edit included -- reformats a hand-written
  file to that layout, one-line seat objects and all, and keeps every key, note and tree, each in its order; an edit
  that changes nothing writes nothing. **A BOM is dropped:** a file saved with one is read as UTF-8, the BOM not part
  of the text (it still counts in the `etag`, which hashes the raw bytes), and written back without it, by the card
  writer's byte contract -- UTF-8 with no BOM -- while its own line ending is kept.
- **It never prompts.** A refusal is a stated one (`exit 2`, one sentence and a hint) and writes nothing; `-WhatIf`
  prints the file it would write and writes nothing. `POST /api/cmd/Staff` runs it through the bridge. A value that
  starts with a dash and names one of the verb's own switches (an owner called `-WhatIf`) would be read as that
  switch -- and the binder reads the en dash, the em dash and the horizontal bar as a dash too -- so the page sends
  a value starting with any of the four joined to its name, `-Person:-WhatIf`.

`tkTestToolkit -OrgChart` types it in a fresh shell over a scratch copy of the sample hub, and
`Tests/test_bridge.py` runs it through the bridge.

## What is not in v1

No machine drawn (the retired `machines`, `machine` and `active` are
read and never served), no count of builders from the cards in flight, and no
join with the standup's workers. `merges` is read, served and printed, and not yet drawn on the Org tab. The web's
Org tab draws the tree the route serves and staffs a seat through `Staff -Seat` (and empties one through `Staff -Seat -Vacate`) ([Team Agile, the web UI](../modules/solitaire-agile.md#the-web-ui)): an
office's title on its sign, a seat's model's name on its plate, its session on hover; a vacant seat is drawn as an empty desk.

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
