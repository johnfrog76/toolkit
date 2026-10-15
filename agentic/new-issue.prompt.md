---
description: "Turn a bug you found, an improvement idea or a planned feature into one GitHub issue with the six-section body and its labels, after a search for a duplicate."
argument-hint: "Describe the issue -- paste an error, explain the problem, or just say what's wrong"
agent: "agent"
---

> Commands below use the default `tk` prefix. If you registered a different one, substitute it --
> the prefix is config (`commandPrefix`), not part of any command's name.

# New Issue

Take a freeform issue description and file it as **one GitHub issue** in this repository's
tracker. The issue is the whole record: **no local file is written.** `docs/CONTRIBUTING.md`, "Start with an issue", says where
the backlog lives and how an issue is filed, worked and closed.

## Steps

1. **Read the user's input** -- a pasted error, a verbal description, a code snippet.
2. **Search for a duplicate before anything else.**
   - `gh issue list --state all --search "<words>"` -- open and closed.
   - `docs/KNOWN-GAPS.md`, "Known gaps", too: a seam already listed there
     needs an issue, not a second listing.
   If a match exists, tell the user (and link it) instead of filing a duplicate.
3. **Ask whether the repository is public.** `gh repo view <owner>/<repo> --json visibility --jq .visibility`.
   `PUBLIC` means the issue is read by strangers, and it is written for them: skip the template
   below and follow "On stage: a public repository". Ask every time -- the repository you file
   INTO is not always the one you are standing in.
4. **Name the commit.** Run `git rev-parse --short HEAD` and record it in Source, so the report is
   anchored to a state of the tree rather than to a day.
5. **Draft the title and body** from the template below. The title is `Bug: ...`, `Improve: ...` or
   `Feature: ...` followed by what is true, in one line.
6. **Choose the labels** (vocabulary below): one type, one severity, and -- if you can judge it -- one
   routing label.
7. **Confirm before filing.** Show the user the title, the labels and a summary of the sections.
8. **File it.** Write the body to a scratch file and run
   `gh issue create --title "<title>" --body-file <file> --label <type> --label <sev> [--label <routing>]`.
9. **Print the issue URL** and a one-line summary.

## Body template

```markdown
## Problem

{What is wrong or missing and why it matters. 2-4 sentences.}

## Location

{Files, functions, line numbers, or modules affected. Be specific.}

## Severity

{Low | Medium | High} -- {one-line justification}

## Fix

{Proposed change. Concrete enough to act on. Refined as the issue is worked.}

## Source

{How identified: user report, code review, test failure, conversation. The date and the commit it
was observed on.}

## Status

Open
```

## On stage: a public repository

A public repository is a stage. An issue there is part of how the product presents. It is read by a visitor deciding whether
the project is alive and by a contributor deciding whether to help, and neither has this repo's
vocabulary.

The body is four sections, written as a maintainer speaking to that reader:

```markdown
## Why

{What a visitor or user gains. Start from what already works.}

## What changes

{The change, as a numbered list a contributor could pick up cold.}

## Done when

{Checks anyone can make from the repository's own page.}

## Out of scope

{What this issue deliberately leaves alone.}
```

What stays out of it:

- **The internal template.** No Severity, Source or Status sections, and no `Bug:` / `Improve:`
  prefix in the title: say what will be true.
- **People and dates.** No "<name>, <date>:" attribution, no quotation from a working conversation.
- **Private things.** No private repository by name or link, no hub path, no card, no spec
  section, nothing from a client's Space.
- **A machine.** No home-directory or drive-letter path. A path is relative to the repository's
  root.
- **Shorthand.** A project's own nicknames for its parts mean nothing to a stranger: describe the
  thing itself.
- **A judgement of the product.** It is not "a portfolio repo" and nothing is "only" anything.

Labels are the target repository's own (`gh label list -R <owner>/<repo>`); this repo's severity
and routing labels do not exist there and are not created there. Confirming before filing matters
more here, not less: GitHub keeps an edited issue's first wording in its history.

The same holds for a pull request's description and for any comment in a public repository.

## Labels

This repository's own labels (`gh label list`), stated once. Another repository's are its own:

- **Type** -- `bug` (something is broken or wrong), `enhancement` (new or better: improvements and
  features), `documentation`, `accessibility` (a barrier for people with disabilities).
- **Severity** -- `sev1` drop everything, `sev2` next session, `sev3` when it fits. The Severity
  section's Low / Medium / High maps to `sev3` / `sev2` / `sev1`.
- **Routing**, by the **shape of the work** -- each routing label names the tier of worker the work
  is handed to, and the tiers are a team's own: this repository uses `fable` **with** `deep-water`
  for deep or risky work (architecture, scoping traps, process plumbing, migrations), `opus` for
  volume and multi-file builds, and `sonnet` for well-scoped, pattern-following work. A team with
  other tiers makes its own labels.
- **`verify-close`** -- merged, but only another host (Windows, or a real org, or a browser) can
  prove it: the fix has a `VERIFY.md` Gate 12 row, and the issue stays open until that row is
  walked. The person who merges closes everything else at merge, so a closed issue means merged and
  pushed, and what verification finds afterwards is a new issue. A closing label, not a filing one.

**Severity says WHEN, routing says WHO, and they are chosen independently**: a sev3 can be deep
water, and a sev1 can be a one-line fix for the lightest tier. A filer who cannot judge the routing
**leaves it off** and triage adds it.

## Rules

- **Do not invent details.** If the user didn't mention a file or line, write `TBD -- needs
  investigation` in Location. Better: open the file and check before you write the line.
- **Do not inflate severity.** Default to Low (`sev3`) unless there is a clear user-facing impact,
  data loss, or something that reaches a real Teams channel or a real ADO board.
- **Match the voice** of existing issues -- terse, technical, sourced, no filler.
- **One issue per filing.** If the user describes several problems, ask which one to file first;
  companion issues cross-link with a comment on each.
- **All three halves file here.** A defect in `web/` or `agent/` is this repo's, and so is one in
  the growth or communication module. There is no per-half tracker.
- **Not every problem is an issue.** A decision that belongs to the build plan is named in the
  reply and recorded there, not filed here.
- **A design conversation is a note, not an issue body.** The issue is its backlog entry; the living
  note goes in `design/` beside its spec, with a `> GitHub: <issue url>` line at the top.
- **Commits reference the issue** -- `Refs #N` -- and change the documentation in the same commit.
  The issue is closed through the verb (`tkCloseItem <n> -Comment "..."` from a Space whose tracker
  is this repository) with a comment naming the commit and any `VERIFY.md` Gate 12 row.
- **Offline.** With no `gh`, nothing fails: write the finding on the card being worked, and file it
  when the tracker answers. The tool degrades rather than failing.
