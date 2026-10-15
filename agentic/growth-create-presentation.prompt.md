---
description: "Put a talk, demo, brown bag, lightning talk or workshop you are preparing or have given on the record, as a presentation in the hub's growth/current/ created with tkNewGrowth and filled in from your description."
argument-hint: "Describe the presentation -- title, format, audience, date, and what it covers"
agent: "agent"
---

> Commands below use the default `tk` prefix. If you registered a different one, substitute it --
> the prefix is config (`commandPrefix`), not part of any command's name.

# New Presentation

`tkNewGrowth -Type presentation` creates the file; `tkNewGrowth -Help` lists its switches, and
`docs/hub/growth.md` is the shape it writes. This prompt does the three things the command does
not: it checks for a duplicate, it turns a paragraph into the command's fields, and it fills in
what the command leaves at its defaults.

## Steps

1. **Read what the user gave you** -- title, date and time, format, audience, why the talk
   exists. Ask for anything missing that is material to a section. Format and audience usually are.

2. **Check for a duplicate** -- search `growth/current/` and `growth/archive/` in the hub for the
   title. If something matches, say so and stop.

3. **Confirm, then create it.** Show the title, the date and the fields you will fill, then run:

   ```powershell
   tkNewGrowth -Type presentation -Title "<title>" -Date <YYYY-MM-DD> [-Notes "<context and intent>"]
   ```

   `-Date` is the delivery date, or the planned one. `-Notes` becomes `## Context & Intent`.

4. **Fill in the rest in place** -- `## Format`, `## Audience`, `## Prep Estimate`, and the outline
   only if the user described one. Edit the sections; do not rewrite the file, and keep its line
   endings.

5. **Print the full path**, and the filename on its own.

## Defaults

| Field | Default | Why |
|---|---|---|
| `## Presenter` | `branchUser` from config, else empty (the command fills it) | no name is ever written from a source file |
| `## Outline / Slide Summary` | `### Section 1 -` stubs | the outline is the talk; it is not yours to draft |
| `## Key Themes` | empty | same |
| `## Outcome & Follow-Up` | `Delivered: No` and blanks | filled in after the talk |

## Rules

- **Do not invent the talk.** No outline described means stubs. An invented outline is worse than
  an empty one, because it reads as a record of a decision nobody made.
- **Context & Intent is the one section worth writing** from what the user said: what problem
  or knowledge gap the talk addresses. Keep it to a few sentences.
- **Match the voice** of the existing files in `growth/current/` -- terse, professional, no filler.
