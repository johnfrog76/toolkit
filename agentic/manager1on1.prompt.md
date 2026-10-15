---
description: "Work a 1:1 session file end to end: the assistant reads the current session, works out from its contents whether it needs an agenda or a retro, writes that back into the file, and sends the summary only when you say so."
argument-hint: "Optional: the session's date (YYYY-MM-DD); by default the newest 1:1 in the hub's manager/current/"
agent: "agent"
---

> Commands below use the default `tk` prefix. If you registered a different one, substitute it --
> the prefix is config (`commandPrefix`), not part of any command's name.

# 1:1 Session

Read the session file, work out which pass it is asking for, run that pass, and write the result
back into the same file. The file is the record: nothing about a 1:1 is stored anywhere else.

Paths here are relative to the hub (`promptsRoot`), not to this package; `tkEnv` prints where the
hub is. The session is the user's side of a recurring 1:1 -- whether they are the one being
managed or the manager -- and the notes in it are theirs.

## 1. Find the session

List `manager/current/` in the hub by name descending and take the first `.md` file whose name is a
date (or the one the user named). If there is none, stop and say so -- do not create one;
`tkNewMeeting` and `tkMeetingAgenda -Plan` are what create a session.

Read it in full before deciding anything.

## 2. Decide the pass

In this order:

1. `## Retro` already holds all four structured subheadings (`**Summary**`, `**Commitments
   table**`, `**Carry-Forward**`, `**Self-assessment**`), or a commitments table with an `Owner`
   column — **skip**. Report that the retro pass has already run and rewrite nothing.
2. `## Retro` holds at least one non-empty line of raw notes and none of those subheadings —
   **retro pass**.
3. Otherwise — **draft pass**. This is also the answer when `## Agenda` is blank or still holds its
   placeholder.

---

## Draft pass

**3. Find the prior session.** The `## Carried from <date>` heading names it. The heading is
filled once, when the session is created, so check it before trusting it: list
`manager/current/` and `manager/archive/` for the records in the same series (the 1:1's are named
by date alone; a series' carry its name in front, `client-weekly-YYYY-MM-DD.md`) and find the
latest one dated before this session. `tkMeetingAgenda -Date <date>` does the same check and
prints a `Check:` line when the heading is wrong, and the agent's session detail carries it as
`carried_from_note`; look for either. When the heading names a different session from that latest
earlier one, names one that is not there, or is missing, **say so** -- both dates -- and ask which
to carry forward from before writing the agenda. Do not rewrite the heading; it is the record,
and a hand edit may be on purpose. Read the session you carry from and take:

- its `## Retro` — the thread left open
- any commitments row whose `Status` is exactly `open`, case-sensitive

If there is no prior session, carry nothing forward and say so rather than inventing continuity.

**4. Look up what the notes refer to.** `## Since Last Session` and `## Unresolved / Forward` will
mention work, training, presentations or projects by whatever name the writer happened to use.

Always list the hub's other record folders — `growth/current/` if the growth module is on — rather
than only searching for an exact phrase. References are partial, informal and misspelled ("that
presentation", "the clean-code thing"). Break the mention into keywords and match on any
significant overlap with a filename or a `## Title`; when in doubt, open the file.

Having opened a match, take the concrete specifics out of it — status, how far along, what is next,
dates — and use them to sharpen the relevant Work bullet. A vague "course progress" becomes
"four of nine modules done; control structures still ahead". If nothing in either folder shares a keyword,
leave the bullet at the level of the notes. **Do not invent specifics.**

**5. Reframe before writing anything.** Raw notes can carry frustration; an agenda must not. Extract
the concern underneath and state it forward: a grievance becomes a challenge, a complaint becomes
an ask, a position becomes a collaborative question. The agenda should read as though written by
someone calm and prepared.

This applies to every section below, not only the alignment one.

**6. Write the agenda** as a two-level bullet outline that can be read from in the meeting:

```
- **Work**
  - Theme one
    - supporting point
    - supporting point
  - Theme two
    - supporting point

- **Alignment**
  - Forward-looking question or ask

- **Forward**
  - One growth or direction thought
```

Plain dashes at every level. Switch to `1.` / `a.` only if one Work theme genuinely has more than
five supporting points.

**Work** — two to four themes from Since Last Session, each with one to three sub-bullets carrying
just enough detail to jog memory. No IDs, filenames or ticket numbers.

**Alignment** — one or two bullets where direction, priorities or posture need a check-in. Source
them from Unresolved / Forward, and from Work when something there raises a question of principle.

Ground each alignment bullet in the concrete work it comes from. The hub may also hold an optional
`manager/principles.md` -- the values or principles the user wants these conversations held to,
whether their organisation's, their team's or their own; when it exists, read it and name the
principle each alignment bullet serves in parentheses after it. When it does not, do not invent a
framework. Where reframing changed the actor, the goal or the expected outcome, add `(reframed)`
as well.

**Forward** — exactly one bullet, genuinely forward-looking and not a restatement of Alignment.

**7. Write to the file.** Replace the `## Agenda` content with the agenda, list any carried open
commitments above it, and set `## Stage` to `prep`. Touch nothing else.

---

## Retro pass

**3. From the raw notes in `## Retro`, write:**

**Summary** — three to five sentences. Factual, forward-looking: what got covered, what shifted.

**Commitments table** — every commitment mentioned, on both sides. Flag any with no clear timeline.

```
| Owner | Item | Timeline | Status |
| ----- | ---- | -------- | ------ |
```

**Carry-Forward** — one thread to pick up next session.

**Self-assessment** — one honest sentence about how the writer showed up. Name what was most
tested or most missed. No softening.

**4. Write to the file.** Replace the `## Retro` content with that output and set `## Stage` to
`retro`. Touch nothing else.

**5. Send it to the other side of the 1:1** — gated on `managerWorkflow.postRetroSummary` in config,
which is top-level and read regardless of the active Space, because a 1:1 history is not scoped to
one Space.

- `postRetroSummary` false: skip this step entirely. No send, no mention of one.
- True: the message is the **`## Agenda` section, and nothing else** — the same payload the web
  UI's send button posts (`docs/hub/manager.md`, "What reads these files"), so the other person gets
  one message whichever path sent it. **Never the Retro and never the Self-assessment** — that is
  private reflection, not a note for the other person.
- Before sending, read `## Sent`. A line there means it already went — say so and stop. The web
  button reads the same section and disables itself on it.
- Send through the communication engine (`POST /api/comms/send` on the running agent, or the
  `tkSendTeams` command with `-Session <file>`) to the recipient key in
  `managerWorkflow.retroChannel` -- `manager` by default, the channel the user declared for the
  person they meet with -- with `tone: "personal"`. Preview it unsent first -- `"dryRun": true`
  on the body, or `-WhatIf` on the command -- and send for real only when the user says so.
- Report the status back — `ok`, `dry-run`, `disabled`, `skipped` or `error`. Never assume it
  landed. `skipped` usually means the recipient's webhook environment variable is not set, and the
  message says which one.
- After an `ok`, the session file gets `Sent to <recipient>: <today, ISO>` under `## Sent`.
  `tkSendTeams -Session <file>` writes that line itself; after a direct POST, add it by hand in the
  same shape. The file records that it happened; nothing else does.

---

## Output

Draft — the two-level outline above. No prose, no full sentences; scannable at a glance.
Retro — prose summary, then the table, then single-line carry-forward and self-assessment.

Afterwards, confirm three things: which pass ran, what was written, and what stage the file is now
in.

## Voice

Factual. Direct. No filler. The alignment item must read as a question, not a position. The
self-assessment has no softening -- peer-level honesty only.
