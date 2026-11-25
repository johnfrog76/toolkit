# agentic/org/ -- the org's roles

This folder holds the **roles** a team can staff when it works a Space with agents. Each role is one
`<role>.prompt.md`, written as a job description: what the role is for, where it sits, what it owns,
what it decides and what it hands to others, the standards it holds, and what good looks like. A
task prompt in the folder above (`new-issue`, `pr-ship`) is something you run once. A role is an
office someone holds, or a job an agent does on a card, so the roles share one shape and live
together here.

**Every role has the same shape**: it reads like a job description or a bio written for a valued
colleague -- who you are, what you are good at, what you care about, and how you work with the people
around you -- in prose, in the second person, with each standard carrying its reason and each hard
limit stated plainly with why. It is not a rule list or a procedure.

The toolkit ships the roles, and your hub fills the seats. Which roles a team uses, who reports to
whom and which model or person sits in each seat is the hub's `org.json`
([the org chart](../../docs/hub/org.md)). `tkOrgChart` prints it, and a position names its role with
`"prompt": "<role>.prompt.md"`. A team's own way of working (card size, what a milestone means to
them, who decides what) is its Space's how-we-work note, which every role reads first.

**Every role responds to the work at hand.** A role is not a job sheet run the same way every day. Each
one tells its seat to read its situation first -- the Space, the tracker, the open cards, what waits on
whom -- with the verbs that seat would use, and then to do the job for the work in front of it. The role
sets the standards and the judgement; the work supplies the specifics.

## The roles

| Role | Takes in | Hands on | Suggested model |
|---|---|---|---|
| `pm` | the owner's direction, the open issues (`tkTriage`) and the active cards (`tkStatus`), a ready from a lead, a merge's hash, and the drafts of a seat that assists it | a queue of cards whose specs are ready, to the seats that lead the work; each ready, checked once more, to the seat that merges; what merged and closed onto the cards and the tracker (`tkLand`); and its decision on each draft, written itself (`tkRoute`, `tkNewItem`, the tracker) | Opus (`opus`) |
| `team-lead` | a card or a queue of them, for one lane or Space | a pull request made ready, one at a time, proved and caught up with its base; and the findings its lane turned up, to the seat that plans the work | Opus (`opus`); its builders chosen per card |
| `vp-of-engineering` | a ready pull request, named by its head | a merge, reported with its hash to the seat that keeps the record, or a finding that sends the pull request back; the engineering standards every lane holds | the team's choice: a judgement seat |
| `vp-of-product` | a design question, a draft (a note, a spec, a page, a piece of copy), a release candidate, and the week's list of designs to archive from the seat that keeps them | a decision written where it belongs, a spec made ready to build, a yes or no on each design to archive, or a release note for the owner's word | the team's choice: a judgement seat |
| `intern` | the open issues (`tkTriage`) and the active cards (`tkStatus`), joined on the id, the tracker's milestones (`gh api`, read only), and the how-we-work note | the milestones and where each stands, to the team; and proposals, to the seat it assists: milestones (a name, the items, why they go together), breakdowns of an issue or user story too big for one card, items that look done with the evidence, and a severity with its reason for each bug -- one at a time, or as a single list over the open bug backlog with the uncertain ones marked | Haiku (`haiku`) |
| `butler` | the design notes and specs in the hub and each product's repository, once a week, unattended: the Design lifecycle row (`tkEnv`), `tkStampDesign -WhatIf`, and the cards each design names | every unstamped file given its id (`tkStampDesign`, `-Hub`); and one report to the seat it reports to: what it stamped, the designs whose work looks finished with the evidence and the exact `tkMoveDesign` call for that seat to run, and what it left and why | Haiku (`haiku`) |

**The owner is not a role file.** Every role names "the owner" as the person whose word settles scope,
voice, anything a person outside the team will see, and anything that cannot be undone -- what ships and
when among them.

**A role names its neighbours by relationship**, never by another role's title: the seat you report to,
the seat that plans the work, the seat that merges, the seats that build. So each one reads correctly in a
two-seat org where the owner covers several roles, in a large one, and whether the seats beside it are
models, people or the owner. Each says what it takes in and what it hands on, and a role that hands on
what another takes in connects to it.

**The merge is a duty, not a role.** It is written once, in `vp-of-engineering.prompt.md` ("The merge"):
check for yourself that the head is the one the ready named, that the branch is caught up with its base,
that every check has finished and passed, and read the whole diff; then report the merge with its hash.
The VP of engineering holds it by default. A team may give it to another seat in its how-we-work note,
and the other roles only ever say "the seat that merges", so they read the same either way.

**Every role carries a stand-in section**, headed "If you are covering this seat": what the seat's loop
is, which a stand-in runs; what waits for the holder, the decisions a stand-in does not make; and the short
list a stand-in keeps for the holder's return.

**The builder's brief is not here yet.** A builder is handed one card rather than holding an office, so it
is a pool in `org.json` rather than a seat, and the brief it works from is still `build.prompt.md` in the
folder above, which `tkStartWork` carries. A hub that wants a role the toolkit does not ship writes its
own and names it in `org.json` (see below).

## Who they are

- **The PM** is the team's memory and its sense of order. Ask it what is next, what is waiting on whom, or
  whether a thing is really done, and it can tell you, because it read the tracker before you asked.
- **The team lead** sees how the pieces fit before they collide. It reads every diff all the way down,
  calls nothing a flake until it has earned the word, and leaves its lane clean at the end of the day.
- **The VP of engineering** is the steady hand at the main line. It reads carefully, says no kindly, and
  reports every merge with its hash, so the record never has to go looking.
- **The VP of product** keeps asking who this is for. It reads every screen as a stranger would, and it is
  happiest when the simplest version turns out to be the right one.
- **The intern** is eager, curious and quick to ask. It fetches the milestones so everyone knows how close
  the next one is, and it fetches the pizza when the team gets there.
- **The butler** keeps the house. Once a week, on its own, it gives every design its id and points out the
  finished ones for putting away, and the best sign it was here is that nobody had to tidy anything.

## How work moves between the roles

Work goes down a chain, one step to a seat, and the record comes back up it. Who sits in each seat is
`org.json`'s; one seat may hold several steps.

1. **Plan.** The seat that owns the product turns a design into a spec ready to build. The seat that plans
   the work turns direction into milestones, issues and cards, in the order the owner set. A seat that
   assists it -- the intern -- fetches the tracker's milestones and where each stands, and drafts
   milestones, breakdowns, close-outs and severities; the seat it assists decides each and makes the
   writes itself: it creates a milestone on the tracker by hand, because no verb creates one, places each
   issue with `tkRoute <n> -Milestone <title>`, which only accepts an existing open milestone, applies a
   severity with `tkRoute <n> -Severity <sev>`, splits an issue into sub-issues, and closes what is done. A card with no issue cannot go
   into a tracker milestone, so the intern proposes it as a candidate for the planned release and the seat
   places it there.
2. **Hand out.** The seat that plans the work reads each card's spec, and hands a lead a queue of the
   cards that are defined. A card resting on an open decision goes to the owner first.
3. **Build.** The lead briefs a builder per card -- `tkStartWork <id>` prints the hand-off block a builder
   starts from -- with the card's contract lines, the suites to run and the stop rule. Each card is built
   on its own branch from the current base.
4. **Make ready.** The lead reads the diff, proves the work, catches the branch up with its base by merge,
   and hands on one ready at a time, named by its head, through the seat that plans the work.
5. **Merge.** The seat that merges checks the ready for itself and merges it, or sends it back with a
   finding. It reports the merge with its hash.
6. **Record.** The seat that plans the work records the merge: `tkLand <id>` writes it onto the card,
   closes the issue and archives the card. Then the lead catches up its next ready.
7. **Celebrate.** When a milestone's last item closes, the intern orders pizza for the team.
8. **Keep the designs.** Once a week, as a routine the owner schedules, the butler gives every design note
   and spec with no id its own (`tkStampDesign`, `-Hub` for the hub's), and sends the seat that owns the
   product one report: what it stamped, the designs whose work has shipped, each with its evidence and the
   `tkMoveDesign` call that archives it (`-To Archive` for a note with no spec, `-To Complete -Doc <path>`
   for a built and documented spec), and what it left and why. The butler archives nothing: that seat runs
   the moves it agrees with, because running the move is the decision. Neither verb commits: a stamp in a
   product's repository goes on the butler's own branch, which the report names, and lands through that
   repository's own way of landing work.

In the sample hub's `org.json` (`samples/hub/org.json`), the VP of product, the VP of engineering and the
PM report to the owner, the butler reports to the VP of product, the team lead and the intern report to
the PM, and a builder pool sits under the team lead. Every office there names its shipped role, which the sample hub does not copy. That is one way
to seat the chain; the roles only say which relationship they have to the seats beside them.

## Where a role is found

A position's `prompt` is a file **name**, never a path. The toolkit looks for it in three places, in
order, and uses the first one it finds:

1. your hub's `agentic/org/`
2. your hub's `agentic/` (where a position's prompt was always looked for, so an `org.json` written
   before this folder existed keeps working)
3. the toolkit's own `agentic/org/` (this folder)

So a role you write in your hub's `agentic/org/` under a shipped role's name wins over the shipped one,
and a hub can name a shipped role, such as `intern.prompt.md`, without copying it. A name found in
none of the three places is refused by `tkOrgChart` with the sentence that says where it looked
([What is checked](../../docs/hub/org.md#what-is-checked)).
