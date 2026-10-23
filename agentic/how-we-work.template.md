---
description: "How we work in {space}: the seats, the loop and the rules every session on this Space reads before it starts."
category: rituals
---

> Written by ToolKit's `tkHowWeWork` from the shipped template, then yours: edit it to fit the team,
> and nothing will write over it. Commands below use the default `tk` prefix; if you registered a
> different one, substitute it.

# How we work in {space}

This Space is worked by orchestrating agents. The tracker is {tracker}: its issues are the backlog and
the channel, and each piece of work has one card in this Space's folder, which is the record. The chat
is not the record. Read this file first, then the session note, then the card you were handed.

## The seats

A seat is a job with its own rules. Each one is held by whoever is sitting in it today, and holds the
same rules whoever that is.

| Seat | Owns | Does not |
| --- | --- | --- |
| **Product** | the order of the work, the specs, the reviews of anything a user will see, and the cut: what ships in a release and what waits | build, or merge a pull request |
| **Engineering** | the build: hands a card to the crew, proves it, merges on green, keeps the main line green, reports what merged | decide the order, or guess at a call that is product's |
| **Crew** | one card, one branch, one pull request, from the current main line | merge, start a second card, or fix what it finds along the way -- a finding is a new card |

When a call is needed, the seat that needs it asks the seat that owns it, writes the question on the
card, and works something else while it waits.

## The loop

Every piece of work goes the same way, one step at a time:

1. **Card.** The work is written on a card before it is built: what, why, and how you will know it is done.
2. **Branch.** One branch per card, from the current main line. Never stacked on another branch.
3. **Pull request, with proof lines.** One pull request per branch. Its description says what changed and
   why, and lists every check that was run, each with its real result. A skipped check is not a pass.
4. **Merge on green.** Engineering reads the diff and the proof, and merges only when every check is green.
5. **Archive with the hash.** The card gets the merged commit's hash as a bullet line and moves to
   `archive/` (`tkArchive <id>`). The card, not the chat, is what anyone finds later.

## The hand-off rule

A session can end at any moment, and the next one starts cold. So:

- **A session note, read first.** Before a seat stops, it writes where the loop stands: what merged,
  what is in flight, what is next and what is waiting on whom. The next session reads it before
  anything else.
- **`tkStartWork` builds the block.** `tkStartWork <id>` prints one block a cold session starts from:
  this file, the card whole, and the prompt for its kind. Hand that block over; do not retell the card.
- **Commit and push as you go.** Work that sits uncommitted is lost to the next seat.

## The relay rule

- **One paragraph each way.** A message between seats is one paragraph with what the other seat needs:
  what merged, what is blocked and on what, what has to be decided.
- **The tracker is the channel.** A decision goes on the card or the issue first, and is sent second.
  A decision someone says is still owed is answered by pointing at where it is written.
- Stale repeats are ignored.

## The stand-in rule

**A seat is not a model.** Whatever runs a seat today runs it by the rules above, and so does whatever
stands in for it tomorrow. When a stand-in meets a call the seat's rules do not answer, it asks the seat
that owns the call, and does not guess.
