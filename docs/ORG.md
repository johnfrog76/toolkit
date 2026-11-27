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
| **You** | the Org tab in Team Agile: the tree drawn as offices, each org's description, and each role's job description one click away. Over the chart, **Zoom out**, **Zoom in** and **Fit to width** show a large org whole or up close; it opens fitted to the page's width |

The org rides [Team Agile](modules/solitaire-agile.md). It is there wherever Team Agile is on in the
Space you are in: `features.solitaireAgile`, with the Space answered "with agents".

## Three starting orgs, small first

You do not start from an empty file. The toolkit ships three starting orgs, and the Org tab previews each
one from its dropdown:

- **The Executive Suite (Small).** You, a VP of engineering who drives the work through builders, and a
  VP of product who reads what ships and holds the merge. Every decision is made at the top.
- **The Branch Office (Medium).** The Executive Suite, plus one team -- a team lead with their own
  builders, who takes the cards, briefs a builder for each and checks the work -- and a test runner who
  proves each change before it merges.
- **Corporate Headquarters (Large).** The full org, with seats for the process: a PM who plans the work
  and keeps the record, a team for each project under the PM, each lead with their own builders, a merge
  stand-in, a weekly butler that keeps the design notes tidy, and an intern that fetches the milestones and
  drafts proposals.

**Small first.** The Executive Suite is the simplest, and the place to learn how a team of agents works
together: a few seats, a few choices, each with a sensible default. Each org's description on the Org tab
says how its work flows and who owns what.

In every starting org the VP of product holds the merge. The roles let a team place the merge on any seat,
and each org's description says where it sits.

## Saving an org, and the one in use

On the Org tab, **Use this org** on a preview saves it, after three questions that are already answered: your
name and the two VPs' models. Two labelled dropdowns sit in the header: **View**, for the org you are looking
at, and **Active**, for the org in use. Choosing in Active makes that org the one in use. In the terminal,
`tkStaff` does the same:

```powershell
tkStaff -Preset S -Owner "Sam"          # save the Executive Suite as an org of your own
tkStaff -Preset M                       # save the Branch Office beside it, as a draft
tkStaff -Activate branch-office         # make it the org in use
tkOrgChart                              # read it back
```

- **A hub keeps up to three orgs** in one file, `org.json`, and **one of them is in use.** Only the org in
  use is read by Team Agile; the others affect nothing until you make one active.
- **Each org has a state: active, draft or inactive.** The **active** org is the one in use. A **draft** was
  saved and has never been in use; an **inactive** org was in use before and another is now. The state is
  worked out, never typed: `activeTree` says which org is active, and each org keeps the day it last became
  active, `activatedAt`, which `tkStaff` writes.
- **Saving never changes the org in use.** `-Preset` saves a draft, and `-Activate` is the one way to
  choose. Your first org is the only one, so it is in use as soon as it is saved.
- **Nothing is overwritten.** An org's id is taken once. A fourth org is refused, naming the three you
  have.
- **Every save is checked** with the same checks `tkOrgChart` makes, before anything is written. A save
  that fails leaves the file as it was. `-WhatIf` shows the result without writing.

`tkStaff` works through the web UI's bridge too, so the page can save through the same verb.

## Seats, and who sits in them

An org is made of **positions**, the offices, and the **seats** in each:

- **You are the owner.** The owner's seat is a person, never a model, and **its name is yours to choose
  and to change.** You name it when you save an org (`tkStaff -Preset S -Owner "Sam"`), and a starting org
  calls it `You` until you do. To rename it on an org you have already saved, use the owner's **Change**
  button on the Org tab, or `tkStaff -Seat owner.owner -Person "Sam"`.
- **Every other seat** holds a model and, if you like, the name of the session that sits there: the name
  other sessions use to reach it. A seat with neither is **vacant**, and the Org tab draws it as an empty
  desk.
- **Builders are a pool,** not seats. They come and go with the cards, at the pool's default model. A team
  is one lead and its own pool, so each team's builders work for that lead alone.
- **The default models** a saved org starts with:

  | Seat | Starts with |
  | --- | --- |
  | VP of engineering | Opus (`-VpEngineering` to choose another) |
  | VP of product | Fable (`-VpProduct` to choose another), and the merge |
  | Team lead, in every team | Opus |
  | Builders (each team's own pool) | Sonnet |
  | Intern, butler | Haiku |
  | PM, test runner, merge stand-in | vacant, for you to fill |

  A seat starts with its default by the role it holds, so every team's lead starts at Opus whatever its
  office is called. A model is stored as its id from [`Config/models.json`](../Config/models.json), and the page shows its
  name ("Opus 5.5") by looking it up, never by reading the id.

## Staffing a seat

On the Org tab, each seat of a saved org, active or a draft, has a button on its plate: **Assign** on a
vacant seat, **Change** on a staffed one. It opens the seat dialog, already filled in: the model, each choice
named for the model it is today ("Opus 5.5"), and the session's name. A seat that holds an older model keeps
it as a choice of its own, chosen, until you pick another. A VP's seat offers Opus, Fable, and Sonnet marked
"not recommended". A team lead's seat also asks which Space the team serves; the owner's seat asks only for
your name. **Use a different title** opens the role title's field, for when the office should be called
something else; it is open already where it is. **View**, above each office, opens the role in the
Studio's reading room. A starting org you are only previewing has View and nothing else. A seat's
dialog also has **Vacate this seat**, beside **Use a different title**, wherever the seat has a model or a session:
it asks `Vacate PM?` in the same place, and **Vacate** empties the seat, taking its model and its session away and
nothing else, while **Keep** leaves it as it is. A vacant seat that still names a session has the link too, so the
session can go. The owner's seat has no such link.

In the terminal, `tkStaff -Seat` does the same:

```powershell
tkStaff -Seat vp-engineering.vp-engineering -Model opus -Session desk-one
tkStaff -Seat lead-team-1.lead -Tree corporate-headquarters -Session lead-alpha -Space toolkit
tkStaff -Seat owner.owner -Person "Sam"
tkStaff -Seat vp-product -Model fable     # a position with one seat: its id alone
tkStaff -Seat vp-engineering -Vacate      # empty the seat: its model and session go
tkOrgChart                                # who sits where, ending staffed: <n> of <seats>
```

- **A seat is `<position>.<seat>`**, or the position's id alone where the position has exactly one seat, as every
  office of every starting org has. A position of several seats needs the whole address, and says so, naming its
  seats. Without `-Tree` it is a seat of the org in use.
- **Vacating takes the model and the session, and nothing else.** The seat's Space, its own title, whether it
  holds the merge, and a person named in it all stay, so a seat a person holds still reads staffed. The owner's
  seat is never vacated.
- **`tkOrgChart` ends with a count**, `staffed: 4 of 10`: every seat of every office, the owner's included, a
  builder pool counting none, and a seat staffed where a model or a person sits in it.
- **The role name and title belong to the position,** so changing them changes every seat of it.
- **Nothing is written over.** The page sends what it read, and if `org.json` has changed since, the save is
  refused and the page offers to reload. Each change prints one line, what the seat was and what it is.

## How it fits orchestration

Each position names a **role**, a job description from the toolkit's [`agentic/org/`](../agentic/org/README.md):
the PM, the team lead, the VPs of engineering and product, the intern and the butler. A session that
holds a seat reads its role to know what the job is, and the Space's how-we-work note to know how this team
does it. The roles name each other by relationship ("the seat that merges", "the seat you report to"),
and the org says which seat that is. The Org tab's office for each role opens it in the Studio's reading
room.

## Editing it by hand

`org.json` is a plain file at the hub's root, and a hand edit works. `tkStaff` is its one writer, and it
keeps every tree, key and note it was not asked to change, each in its order. The layout is the writer's: the
first time `tkStaff` writes a file you formatted by hand, it comes back as two-space JSON, with nothing in it lost. Fields the tool does not know are kept and
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
None of it works today.

**The next steps:**

- **Adding a team.** A team is a team lead assigned to one Space, with builders under it. The org grows
  with your projects, one team for each: Small has no team, adding the first team makes it the Branch
  Office, and adding a second makes it Corporate Headquarters.
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
