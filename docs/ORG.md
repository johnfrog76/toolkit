# The org

An org is a shared understanding of how a team works together: which roles there are, who reports to
whom, and who fills each role today, whether a person or a model. Written down once, the same structure
is read by everyone who needs it. The team reads it, an agent reads it, and you read and change it. When
you work a Space with agents, the org is how you say who does what.

This page is the story. The file's exact shape, field by field, is [`docs/hub/org.md`](hub/org.md).

## Three readers, one structure

| Reader | What the org is to them |
| --- | --- |
| **The team** | a shared understanding: who sits where, who reports to whom, and which seat merges |
| **An agent** | `org.json`, the structure itself, readable as it is. `tkOrgChart -AsJson` prints it in the shape the web UI reads, less the few fields only the page uses |
| **You** | the Org tab in Team Agile: the tree drawn as offices, each org's description, and each role's job description one click away |

The org rides [Team Agile](modules/solitaire-agile.md). It is there wherever Team Agile is on in the
Space you are in: `features.solitaireAgile`, with the Space answered "with agents".

## Three starting orgs, small first

You do not start from an empty file. The toolkit ships three starting orgs, and the Org tab previews each
one from its dropdown:

- **The Executive Suite (Small).** You, a VP of engineering who drives the work through builders, and a
  VP of product who reads what ships and holds the merge. Every decision is made at the top.
- **The Branch Office (Medium).** The Executive Suite, plus a team lead who takes the cards, briefs a
  builder for each and checks the work, and a test runner who proves each change before it merges.
- **Corporate Headquarters (Large).** The full org, with seats for the process: a PM who plans the work
  and keeps the record, team leads under the PM, a merge stand-in, a weekly butler that keeps the design
  notes tidy, and an intern that fetches the milestones and drafts proposals.

**Small first.** The Executive Suite is the simplest, and the place to learn how a team of agents works
together: a few seats, a few choices, each with a sensible default. Each org's description on the Org tab
says how its work flows and who owns what.

In every starting org the VP of product holds the merge. The roles let a team place the merge on any seat,
and each org's description says where it sits.

## Saving an org, and the one in use

The Org tab previews. `tkStaff` saves:

```powershell
tkStaff -Preset S -Owner "Sam"          # save the Executive Suite as an org of your own
tkStaff -Preset M                       # save the Branch Office beside it, as a draft
tkStaff -Activate branch-office         # make it the org in use
tkOrgChart                              # read it back
```

- **A hub keeps up to three orgs** in one file, `org.json`, and **one of them is in use.** Only the org in
  use is read by Team Agile. The others are drafts: you can keep and change them, and they affect nothing
  until you make one active.
- **Saving never changes the org in use.** `-Preset` saves a draft, and `-Activate` is the one way to
  choose. Your first org is the only one, so it is in use as soon as it is saved.
- **Nothing is overwritten.** An org's id is taken once. A fourth org is refused, naming the three you
  have.
- **Every save is checked** with the same checks `tkOrgChart` makes, before anything is written. A save
  that fails leaves the file as it was. `-WhatIf` shows the result without writing.

`tkStaff` works through the web UI's bridge too, so the page can save through the same verb.

## Seats, and who sits in them

An org is made of **positions**, the offices, and the **seats** in each:

- **You are the owner.** The owner's seat is a person, by the name you give it (`-Owner`), never a model.
- **Every other seat** holds a model and, if you like, the name of the session that sits there: the name
  other sessions use to reach it. A seat with neither is **vacant**, and the Org tab draws it as an empty
  desk.
- **Builders are a pool,** not seats. They come and go with the cards, at the pool's default model.
- **The default models** a saved org starts with:

  | Seat | Starts with |
  | --- | --- |
  | VP of engineering | Opus (`-VpEngineering` to choose another) |
  | VP of product | Fable (`-VpProduct` to choose another), and the merge |
  | Team lead | Opus |
  | Builders (the pool) | Sonnet |
  | Intern, butler | Haiku |
  | PM, test runner, merge stand-in | vacant, for you to fill |

  A model is stored as its id from [`Config/models.json`](../Config/models.json), and the page shows its
  name ("Opus 5.5") by looking it up, never by reading the id.

## How it fits orchestration

Each position names a **role**, a job description from the toolkit's [`agentic/org/`](../agentic/org/README.md):
the PM, the team lead, the VPs of engineering and product, the intern and the butler. A session that
holds a seat reads its role to know what the job is, and the Space's how-we-work note to know how this team
does it. The roles name each other by relationship ("the seat that merges", "the seat you report to"),
and the org says which seat that is. The Org tab's office for each role opens it in the Studio's reading
room.

## Editing it by hand

`org.json` is a plain file at the hub's root, and a hand edit works. `tkStaff` is its one writer, and it
keeps every tree, key and note it was not asked to change. Fields the tool does not know are kept and
named once as a warning, never refused. [`Config/org.schema.json`](../Config/org.schema.json) is the
schema, and `tkOrgChart` says plainly what is wrong with a file that fails its checks.

## Where the structure lives

| What | Where |
| --- | --- |
| Your org | `org.json` at your hub's root, beside `hub.json`. It is your hub's, the same in every Space |
| Its shape, field by field, and what is checked | [`docs/hub/org.md`](hub/org.md) |
| The schema | [`Config/org.schema.json`](../Config/org.schema.json) |
| The starting orgs | [`samples/org-presets/`](../samples/org-presets/) |
| The roles | [`agentic/org/`](../agentic/org/README.md) |
| The verbs | `tkOrgChart` and `tkStaff`, in [the CLI's command reference](CLI.md) |
| The page | Team Agile's Org tab, in [Team Agile, "The web UI"](modules/solitaire-agile.md#the-web-ui) |

## Where it is going

**Not built yet.** This section describes what is planned, so that you can see where the org is heading.
None of it works today. [Known gaps](KNOWN-GAPS.md#the-org-is-set-up-from-the-terminal-not-yet-from-the-page) lists it too.

**The next steps:**

- **Setting up an org from the page.** "Use this org" on a preview asks three questions (your name and the
  two VPs' models, each with its default filled) and saves it. Two dropdowns: **View**, to choose the org
  you are looking at, and **Active**, to choose the org in use.
- **The seat dialog.** Each seat of a saved org gets an **Assign** or **Change** button. It sets the
  seat's model and session, and for a team lead its Space.
- **Adding a team.** A team is a team lead assigned to one Space, with builders under it. The org grows
  with your projects, one team for each: Small has no team, adding the first team makes it the Branch
  Office, and adding a second makes it Corporate Headquarters.
- **Zoom** for a large org's chart.
- **A seat's brief.** It is composed on demand from the role, the Space's note and the seat, so nothing
  is copied and nothing goes stale.
- **Printing a starting org** from the terminal.

**The direction:**

- **Read, then update, to match reality.** An agent reads the org, then updates it so the file says what
  is really happening. The tests hold both the page and the terminal to every change.
- **The org grows with the projects receiving attention.** You change who is staffed as your attention
  moves, and the org's shape grows as your projects do.
- **The constraints the design acknowledges:** tokens, machines and attention. None of them is read by the
  Org tab today, and tokens may be brought into the design later.
