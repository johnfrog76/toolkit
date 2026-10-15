---
description: "Turn a freeform bug description into a work item on the active Space's tracker and a card for it, drafting the repro steps, the actual and expected results, severity and priority for you to confirm before tkNewItem and tkNewPrompt write them."
argument-hint: "Describe the bug -- paste an error, describe what went wrong, or give repro steps"
agent: "agent"
tools: ["read_file", "list_dir", "run_in_terminal", "grep_search"]
---

> Commands below use the default `tk` prefix. If you registered a different one, substitute it --
> the prefix is config (`commandPrefix`), not part of any command's name.

# New Bug

Turn a freeform bug description into a work item on the tracker and a card in the hub, wired
together. Two commands do the writing -- `tkNewItem` creates the item, `tkNewPrompt <id>` creates the
card from it -- and this prompt decides what goes into them.

## Context

1. `tkSwitchSpace Status` -- the active Space is where the item is filed. Do not switch Space unless
   the user says to.
2. `tkConfig -List` -- the Space's `projects`. If it has more than one and the user didn't name
   one, list them and ask.
3. `tkStatus` -- the cards already open. Check them for a duplicate before creating anything.

## Steps

### 1. Draft the bug fields

From the user's description, extract or infer:

| Field | Notes |
|---|---|
| **Title** | Present tense, ≤ 80 chars -- describes the symptom, not the cause. E.g. "Login form submits with empty password field" not "Password validation broken" |
| **Repro Steps** | Numbered list. Start from a clean state. Include env (browser, OS, role) if relevant. |
| **Actual Result** | What actually happens. Be specific -- include error text, wrong value, or broken behavior. |
| **Expected Result** | What should happen. Reference spec or AC if available. |
| **Severity** | 1=critical (data loss/crash), 2=high (core flow broken), 3=medium (workaround exists), 4=low (cosmetic) |
| **Priority** | 1=fix now, 2=this sprint (default), 3=backlog, 4=someday |

Show the user the draft and confirm before creating anything.

### 2. Create the work item

`tkNewItem` derives the organisation, project and your identity from config and assigns the item
to you. Preview first with `-ReadOnly`, which prints the fields and writes nothing:

```powershell
tkNewItem `
  -Type Bug `
  -Title "{title}" `
  -Description "{summary-as-html}" `
  -ReproSteps "{repro-html}" `
  -Priority {priority} `
  -ReadOnly
```

Then run the same command without `-ReadOnly`. Add `-Project "{name}"` when the Space has more
than one project. Capture the new id from the output.

On a GitHub Space the item is an issue: drop `-Priority` and `-Points`, which an issue does not
have and the command refuses by name; the acceptance criteria and repro steps join the issue's
body as sections.

Severity is set separately from priority, and how depends on the tracker:

- **Azure DevOps** -- `tkNewItem` has no `-Severity` switch; set it with
  `az boards work-item update --org "{org-url}" --id {id} --fields "Microsoft.VSTS.Common.Severity={severity}"`.
- **GitHub** -- severity is a label: pass `-Tags <label>` on the create, with the repository's own
  severity label (`gh label list`).

> **Repro steps format (Azure DevOps):** stored as HTML. Use `<ol><li>Step one</li><li>Step two</li></ol>` for numbered steps. Wrap actual/expected as: `<p><strong>Actual:</strong> ...</p><p><strong>Expected:</strong> ...</p>`

### 3. Create the card

```powershell
tkNewPrompt {id}
```

It reads the item back from the tracker and writes the card into the Space's `current/` -- the
filename, the template, the branch suggestion and the `**ADO Link:**` line are its job, not yours.
If a card for that id is already in `current/`, it returns that card and writes nothing.

Then fill the card **in place** (edit the sections; do not rewrite the file):

- `## Repro` -- the structured repro, in plain text, not HTML: test environment (browser/OS/role
  from the description, or `TBD -- needs investigation`), the numbered steps, actual result,
  expected result, and user impact (who is affected and how severely)
- `## Acceptance Criteria` -- what passing looks like (often the inverse of the actual result)

### 4. Confirm and finish

Print:

- The work item URL
- The card's path
- A one-line summary: what is broken and where

## Rules

- **Confirm before the tracker write.** Show the full field draft and wait for go-ahead.
- **Do not invent repro steps.** If the description is ambiguous, ask for exact steps before proceeding. Write `TBD -- needs investigation` in Location/Root Cause fields, not guesses.
- **Check for duplicates first.** Search the open cards (`tkStatus`, then the files in `current/`) for keywords from the title. If a match exists, show it to the user and ask before creating a new item.
- **One bug per run.** If the description covers multiple issues, ask which to file first.
- **Identity comes from config.** Never ask the user for their email -- `tkNewItem` reads `email` from config, else the signed-in `az` account.
- **The active Space is the target.** Never file into another Space unless the user says so.
- **The commands write; you fill.** The card is created by `tkNewPrompt` and only edited after, so it comes out in the same shape, with the same bytes, as every other card.
- **Severity ≠ priority.** A low-severity cosmetic bug can be high priority if it's on the login screen. Set them independently.
