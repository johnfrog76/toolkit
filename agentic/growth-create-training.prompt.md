---
description: "Put a course, certification or workshop you enrolled in or completed on the record, as a training in the hub's growth/current/ created with tkNewGrowth and filled in from your description."
argument-hint: "Describe the training -- title, provider, dates, hours, and whether it was required or voluntary"
agent: "agent"
---

> Commands below use the default `tk` prefix. If you registered a different one, substitute it --
> the prefix is config (`commandPrefix`), not part of any command's name.

# New Training

`tkNewGrowth` creates the file; `tkNewGrowth -Help` lists its switches, and `docs/hub/growth.md` is
the shape it writes. This prompt does the three things the command does not: it checks for a
duplicate, it turns a paragraph into the command's fields, and it fills in what the command leaves
at its defaults.

## Steps

1. **Read what the user gave you** -- title, provider, dates, hours, required or voluntary.
   Ask for anything missing that would end up as a heading with nothing under it. Do not ask about
   anything that has a default below. A training needs an end date (`-DueDate`).

2. **Check for a duplicate** -- search `growth/current/` and `growth/archive/` in the hub for the
   title or the provider. If something matches, say so and stop. A second file about one training
   is worse than no file.

3. **Confirm, then create it.** Show the title, the dates and the fields you will fill, then run:

   ```powershell
   tkNewGrowth -Title "<title>" -Date <start> -DueDate <end> [-Provider "<provider>"] [-Hours <h>] [-Notes "<description>"]
   ```

4. **Fill in the rest in place** -- `## Type` when the training was required, and `## Provider` as
   `TBD` when none was given. Edit the sections; do not rewrite the file, and keep its line
   endings.

5. **Print the full path**, and the filename on its own.

## Defaults

| Field | Default | Why |
|---|---|---|
| `## Status` | `Not Started` | reads as **new** in the web UI |
| `## Type` | `Voluntary` | unless the user said required or mandatory |
| `## Hours` | `TBD` | a guess here becomes a number in a review |
| `## Date(s)` | `START to END` (the command writes it) | ASCII `to`, never a dash -- the shape document says why |
| `## Key Takeaways` | empty bullets | filled in as the training happens, not before |
| `## Outcome` | `Completed: No` and blanks | |

## Rules

- **Do not invent a detail.** No provider given means `TBD`, not a plausible provider.
- **Do not write the takeaways.** They are the point of the record and they are the user's.
- **Match the voice** of the existing files in `growth/current/` -- terse, factual, no filler.
