# Roadmap -- the order the three design ideas get built in

The owner, 2026-09-20: "I give you freedom to organise them in the order we need, because this is waterfall --
we can't have a first run experience until we have custom cards, and we need to put a primary experience
as an add-on -- and technically this is what we did when we said we need a Demo slug for FRE."

The designs are notes, each worked into a spec and built from there. This file is only their ORDER, and why.
Each phase is a handful of small steps, each with its own GitHub issue, commit, docs and UAT.

| Design idea (the owner's three) | Where it stands |
| --- | --- |
| Swim-lane view for all cards, custom and ADO-linked -- *the feature* | the cards design; phases 1-3 below, DONE |
| The first run, leveraging custom cards | the first-run design: watch, do, make your own; phase 5 |
| Solitaire Agile -- the Lounge tab | the Lounge design; phase 7, specced and built to M3 |

## Milestones

- **2026-09-20 -- a card no longer needs Azure DevOps.** The owner: "that is a huge milestone -- note that."
  On one Sunday the product's definition changed and the code caught up with it the same day: the idea
  in the morning ("ADO is just an add-on -- it is not core at all?"), three designs, a spec, and by the
  evening roadmap phase 1 built -- one id rule, a short id of its own for a card with no work item, the
  Spike type, the card as a MODEL with `type` a first-class field, and the **+** in the browser making a
  card from a title and a type on an org with no Azure anywhere. "Spike DG4C: Wallet ticket from a QR
  code" was the first one. Cards are the core purpose of this software and cannot be turned off; ADO
  can. Found on the way, because it was tried for real: `Archive` had been broken as a verb for three
  days, and `current/` was not protected from the keyboard.

- **2026-10-09 -- the front door.** The owner: "this is a foundational shift." The product stopped being a card
  system with add-ons and became the answer to one question -- how do you want to work? -- with three
  answers in his words: by yourself, on a team in Azure, with agents. Core is ToolKit alone; the other
  two are the add-ons the tree already had. Everything moves to the disruption, and the disruption is
  orchestrated development, so GitHub issues and AI orchestration is the commercial's first window and
  Azure DevOps is the shelf -- agile on the shelf, literally. The ritual engine is the proof: once the
  work is orchestrated, the person's problem is keeping up, and the standup is the first thing built for
  that. The record is what you carry across the shift. Written the same morning in
  the front-door design note, *how do you want to work?* (the thesis, the platforms' layer and ours, the bottom line, eight
  decisions) and placed below as the pre-flip set and F1-F4.

## The waterfall

```text
0  ADO can be absent            DONE 2026-09-19 -- the Demo org
        |
1  Custom cards                 DONE 2026-09-20 -- a card with no work item is first-class
        |
2  Lanes                        DONE 2026-09-20 -- the board: all cards, moving by themselves
        |
3  Accounting from the card     DONE 2026-09-20 -- Billable; Daily from the cards' own dates, git or no git
        |
4  Azure DevOps is a plugin     the thin, visible half DONE 2026-09-20; unregistering the verbs is phase 8
        |
5  The first run                watch, do, make your own
        |
6  Ledgers                      what ADO and billing know, shown on the card; publish a card to ADO
        |
7  The Lounge                   Solitaire Agile
        :
8  The rename                   the invisible half of the carve -- any time after 4
```

### 0. ADO can be absent -- done

What the owner noticed: the moment First Run needed a Demo org that never contacts Azure, the primary
experience had already been made an add-on -- in behaviour. An org whose status is `local` runs the
product from its files; the ADO-only cards are absent; a Connect card says what is missing. `Start`,
`samples/hub`, 2026-09-19. Everything below builds on that being true.

### 1. Custom cards -- *needs 0*

**DONE 2026-09-20.** Steps A (one id rule), B (a short id at creation, the Spike type), C (the card model,
served by `/api/status`) and D ("New card" from the web **+**). A card with no work item is a first-class card,
from the terminal and from the browser.

A card with no work item is a first-class card. One id rule, read one way by every verb; a short id
(`K7M2`) at creation; the **Spike** type; `/api/status` carries `id` and `type`; the web **+** makes a
card from a title and a type. *Cards design, steps 1-4.*
**Done when:** the owner presses **+**, types "Wallet ticket from a QR code", picks Spike, and it appears --
with no Azure anywhere.

### 2. Lanes -- *needs 1*

**DONE 2026-09-20.** Steps E (the board), F (drop on Done, and the Move menu) and G (the sample hub has a card
in every lane, and a Spike with no work item). `docs/images/board-in-action.gif` is it working.

The board as a second view of Home, with Home's filters plus Sprint: Active, In Progress, Code Review,
Done. Cards move by themselves -- a commit, a pull request. The one move a person makes is dropping a
card on Done to archive it, and every card has a "Move to..." menu for the keyboard. *Cards spec, E-F.*
**Minimum deliverable -- the owner, 2026-09-20: "not planning yet and no backlog."** A card is in play the
moment it is created. Planning (a Planned mark or a `backlog/` folder, My Work in the first lane) is a
later build-out, and is not a phase yet.
**Done when:** the Costco week's cards can be made on Monday and watched across the board by Friday.

### 3. Accounting from the card -- *needs 1*

`**Billable:** yes / no` on a card (decided 2026-09-20; built here because nothing a user sees changes
until Daily honours it). Daily is built from the cards' own `Created` and `Closed` dates, honouring Billable, with git only as
enrichment. *Cards design, step 9.* Closes the two open billing bugs.
**Done when:** Friday's timesheet is right after a hub folder move, and a first-run user's Daily is not empty.
Why before 5: a first run whose Daily page says "nothing recorded" undoes the introduction.

**Done 2026-09-20** -- built on `feature/accounting-from-the-card`, accepted by the owner and merged the same day. Both halves of "done when"
were checked for real: a scratch first-run hub with NO git shows the sample cards on Daily, Monday to
Friday, and the folder-move case is pinned by a test that failed before. Billable shipped as **no / absent**
rather than yes / no -- a card is billable unless it says otherwise, so nothing needed migrating; the verb
is `Billable <id> [-No]`, and the board and the list both carry the mark and the toggle. Along the way:
the agent's in-memory "last week" cache went (a finished week CAN change -- a closed card gets marked on
Monday), and a week that could not be built now says so on Daily instead of reading as a quiet one.
**Asked for next, not built** (the owner, 2026-09-20): page Daily back further than last week, with the same
pattern in the CLI -- an open issue. **This phase and that draft share one
spec, Daily's.**

### 4. Azure DevOps is a plugin -- *needs 1-2; the VISIBLE half of the carve*

The owner: "we keep always custom cards and user can plug in to Azure", and: "this is the core purpose of this
software and it can't be turned off -- ADO can be turned off." Cards have no flag and never will. ADO
gets one. A switch, like Growth: Settings ->
Modules -> Azure DevOps. Off means absent -- no ADO verbs in the menu, no ADO cards on Home, no Connect
nagging. On, and everything it does today comes back. The org's `local` / `active` status remains the
per-org answer; this is the product-level one.
**Done when:** a new user never meets the words "Azure DevOps" unless they go looking, and an existing
user sees no difference at all.
Why before 5: the first run should describe the product in its final shape -- "plug in Azure DevOps" --
not be rewritten a month later.

**The thin half, done 2026-09-20** -- built on `feature/ado-is-a-plugin`, merged on the owner's word the same day, to the
Azure DevOps plugin's spec ([the add-on](modules/ado.md) is its record). The owner: "only if it isn't disruptive", so the switch is DERIVED
(`features.ado`, else the status of the org you are in) and a user in an active org sees no difference:
`Menu`, `Menu -All` and `Menu -Markdown` on `main` and on the branch differ by one line pair, the new
inventory row. A machine `Start` made is shown only what it can use -- in `Menu`, `Setup` (which no longer
fails a machine with no `az`, and states the tier), the New card dialog and Settings. The verbs stay
registered; unregistering them is phase 8. The Settings "Modules -> Azure DevOps" switch this section
describes exists as the labelled `features.ado` row; whether it should sit with Growth and Meetings is
an open item in the spec.

*Done 2026-09-22, before phase 5: lane names for people who do not ship code -- org-scoped lane
names with a plain default for Demo, the `Move` verb and the two tokens a person writes, and drag-and-drop
to every lane ahead of a card. Also the path-with-copy on every file page, and the pager on the toggle row --
which went on 2026-09-24, when Home became three named tabs, Cards | Sprint | Actions, and the toggle took its
place at the row's right edge. On 2026-09-28 the toggle went too (cards spec D-C14): Home is Focus | Board | Sprint | Actions, and a space shows only the tabs it has.*

*Agreed 2026-09-22, and next after the PC's triage: **the Meeting Agenda Planner**
([the communication add-on](modules/communication.md)). The owner: "I agree -- we do this. Meeting agendas, not manager agendas ...
What Teams does not do: it has no memory between meetings ... And an agenda item that becomes work becomes
a card, on the board, with the meeting it came from written in it." Built in the order the spec's
acceptance is written: the 1:1 unchanged first, then the second series. **Stage one built the same day**:
the series in the record's name, carry-forward per series, the quick menu, the web's list and dialog.*

### 5. The first run -- *needs 1, 2, 3, 4*

The tutorial cards (custom cards, in the sample hub), the Welcome page, the intro deck that is also the
README's demo. *First-run design.*
**Done when:** someone clones the repo, runs three lines, and ten minutes later has used the whole
system on their own board -- and has not been asked for an account.

*Behind this phase, and not scheduled: going public -- a project page and a feature tour generated from the
software -- the open-source front page and feature tour's design note, with the gates that come before it;
the bar they became is `PUBLIC-BAR.md`.*

### 6. Ledgers -- *needs 3 and 4*

A card says what each ledger knows about it and offers the one action that settles a drift ("Done here,
still Active there"). **Publish a card to Azure DevOps**: the work item is made FROM the card. *Cards
design, section 2.*
**Done when:** the double entry is the tool's job, not the engineer's.
Why here and not earlier: it is only meaningful once ADO is a plugin a card may or may not report to.

### 7. The Lounge -- *needs 1-2; specced 2026-09-26, M1-M2 scheduled (see "The next three")*

*M3 -- the Skins dialog, the room in the GUI's clothes, two small games -- proposed from the issue that
asked to evolve the Lounge and the owner's hub note, LOCKED and BUILT the same day, 2026-09-28. The
living card keeps everything past it.*

Solitaire Agile. The Lounge's spec carves the buildable slice: the room and the skins
first (M1-M2), the study, the company and the story behind them; replay before live stands -- it
reads a build that already happened and costs nothing. The living design card keeps everything the
spec does not schedule. The live-team work still comes in behind a flight
(the flights design note: protect unfinished work), the first thing here likely to need one.

### 8. The rename -- *any time after 4; the INVISIBLE half of the carve*

Folders, module ids and docs stop saying "ADO core": a `cards` core, and `ado` a module beside growth,
communication and deck. No user-visible change, a large diff, every registry test and a good deal of
documentation. Deliberately separated from 4 so the part a user sees does not wait on it, and so it can
be done alone, when nothing else is in flight.

## The next three (agreed 2026-09-26)

The owner: "you can build first the github, then the lounge and then we go back to workflow based
settings." In order:

1. **The GitHub tracker** -- its spec's milestone 1: the second tracker
   through a real seam (which carves the SEAM SLICE of phase 8 first -- dispatch by board, not the
   rename), dogfooding on toolkit's own issues. This is `what-this-is.md` item 6 made real: "ADO is
   one of two" is the only version a stranger can verify.
2. **The Lounge, M1-M2** -- the Lounge's spec: the room and the skins, where the spec
   now ENDS (the owner, 2026-09-26: the Virtual Team is "not ready for spec -- I think the skins are").
   The living design note keeps everything beyond -- the study,
   the company, the story -- until the owner calls one ready.
3. **Workflow-based settings** -- back to the connect wizard as the family's first instance
   (the Azure DevOps on-ramp's issue for the wizard, the family's rules on the settings drawer's
   issue).

Phases 5-8 keep their places in the waterfall; these three interleave ahead of them because the
seam, the room and the wizards are what the day's design work made ready.

**Where that list stands, 2026-09-29:** 1 is built (Milestone P, 2026-09-27) and 2 is built (Lounge
M1-M3, 2026-09-28); 3 is next and is SPECCED as settings BY WORKFLOW ([Configuration](CONFIGURATION.md),
"Settings by workflow: the questions, and the one list behind them"; the owner, 2026-09-28: a FAQ-like section in the drawer plus Tips on Home; fourteen questions held to
the CLI's surface inventory; W1 the list and the section, W2 the connect wizard, W3 the family). Behind it, **the Studio** --
its spec, built as [the Studio](modules/studio.md) (2026-09-29, the owner: "gh issues is inspirational and brings us closer to
a studio experience"): every product a GitHub Space with a complete ledger (S1, the backfill and the closed issues in the web),
a foyer across products with design notes in the hub (S2), specs read from the product's repo and
review in the tracker's thread (S3). D-S8 orders it after the settings work, because the
out-of-the-box user is a studio developer connecting a first product.

## What is NOT on this list

The settings drawer's grouping (on hold at the owner's word), the remaining UX-audit issues, closing a meeting
from the web, and everything else on the GitHub issue list -- small, independent, and
fitted in between phases. A read-only **Issues page** in the web UI is also independent and can land
any time.

**Solitaire Agile** (specced 2026-10-02 from the Team Agile issue; built as [Team Agile](modules/solitaire-agile.md)) is written in
three phases -- M0 the engine as text, V1 the deck and triage, V2 the voices. **M0 DONE 2026-10-02**
(the owner: "ship because it has value now just seeing the status"). **V1 DONE 2026-10-03** (the owner: "continue driving towards
Team Agile"; seven issues, and two UX issues -- the Space's home icon and the Studio's design component -- shipped the same morning). V2 and
the running state are NOT placed yet.

## The front door, and the order after the flip (2026-10-09)

**The tracker carries this order** (the owner, 2026-10-09: "push the roadmap into the public milestone,
because we must get the commercial right"): the **Going public** milestone's description is the pre-flip
order with the commercial first, and the **After the flip** milestone holds F1-F4 as issues. The file and
the milestones say the same thing; when one changes, both do.

The public milestone is the bar (`docs/PUBLIC-BAR.md`) plus three pieces of one story, decided from
the front-door design note on 2026-10-09: the README's first screen says what ToolKit is in one
sentence -- a studio where you work on software by yourself, on a team, or orchestrating agents, and the
cards are the record either way (with the deck's order, the commercial); Settings asks "How do I work on this
Space?" and the answer sets Team Agile per Space; the Studio lists the agentic prompts that ship.
Nothing else is added before the flip.

After the flip, in this order, each from its design note into a spec first:

```text
F1  Daily: the record for everyone     the outcomes layer, edit-then-save; the billing format as the opt-in export
        |
F2  Start work                         the mirror points; Start work beside Route writes the hand-off: the seat's prompt, the card, the how-we-work note
        |
F3  The ritual engine's own repo       done in public; the standup's moved-items line and its folded also-ons are its first issues
        :
F4  New Space asks the question        when the orchestrating answer writes the team's files into the Space's hub folder
```

Why that order: F1 changes a page everyone sees from the first run; F2 is a button over three things that
exist; F3 moves code and is cleaner as a refactor on stage than as a delay before it; F4 waits for the
answer to have a consequence worth a dialog.

## Keeping this file honest

When a phase finishes, mark it DONE with the date, here, in the same commit. When the order changes,
change it here and say why. This is the only place the order is written down.
