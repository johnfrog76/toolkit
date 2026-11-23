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

## The roles

| Role | Takes in | Hands on | Suggested model |
|---|---|---|---|
| `intern` | the open issues (`tkTriage`) and the active cards (`tkStatus`), joined on the id, the Space's `design/` and `spec/` notes, and the how-we-work note | proposals, to the seat it assists: milestones (a name, the items, why they go together), breakdowns of an issue or user story too big for one card, items that look done with the evidence, and a severity with its reason for each bug -- one at a time, or as a single list over the open bug backlog with the uncertain ones marked; and designs whose work has shipped, to archive | Haiku (`haiku`) |

**Only the intern ships today.** The standing offices it hands work to (the seat that plans the work,
the seat that leads a Space and hands cards out, the seats above them) and the brief a builder works
a card from arrive in this folder later. Until they do, a hub that wants them writes its own and names
them in `org.json` (see below), and the builder's brief is still `build.prompt.md` in the folder above.

## How work moves between the roles

The intern is the first link in the chain, and it never writes:

1. **The intern reads and proposes.** On a Space with no milestones it drafts them. On any Space it
   proposes breakdowns, close-outs and severities, and on a Space with a `design/` tree, the designs
   whose work has shipped. Every proposal carries its evidence.
2. **The seat it assists decides and writes.** That seat plans the work. It coaches the intern on each
   draft, then makes the changes itself:
   - it creates a milestone on the tracker by hand, because no verb creates one;
   - it places each issue with `tkRoute <n> -Milestone <title>`, which only accepts an existing open
     milestone;
   - it approves the intern's severities, one bug or a whole backlog list at a time, and applies each
     with `tkRoute <n> -Severity <sev>`; it archives a shipped design with `tkMoveDesign` (`-To Archive`,
     or `-To Complete -Doc <path>` for one with a spec); it splits an issue into sub-issues, and closes
     what is done.

   A card with no issue cannot go into a tracker milestone, so the intern proposes it as a candidate
   for the planned release and the seat places it there.
3. **The cards go on to be built.** A card that is planned and placed is handed out, built on its own
   branch, reviewed and merged. Each step has its own seat, and the seat that merges is the one that
   closes the issue. `tkStartWork <id>` prints the hand-off block a builder starts from.
4. **When a milestone is reached, the intern orders pizza for the team.** That is the celebration.

In the sample hub's `org.json` (`samples/hub/org.json`), the intern reports to a PM, which reports to
the owner. That is one way to seat the chain. The role only says it assists the seat that plans the
work.

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
