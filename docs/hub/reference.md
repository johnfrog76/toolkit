# Reference -- the file

The shape of one reference document, and how every reader reads it. A reference document is kept for
**reading, not for doing**: a company holiday list, a policy guide, the key terms of an agreement. The
Organize add-on reads these; its document is [`docs/modules/organize.md`](../modules/organize.md). This
file is about the FOLDER.

## Where

`<promptsRoot>/reference/current/` -- a hub-root sibling of `reminders/` and `growth/`, **never under an
org**, and keyed by no slug. A hub that has never kept one has no folder, and that is not an error: the
list is empty. Only `current/` is read; nothing is archived, moved or marked past its dates.

The folder's name is the hub's to declare once the CLI's `Reference` verb lands and adds the key to both
halves' folder tables; until then every reader uses `reference`.

## One document, one file

```text
reference/current/days-off-2027.md
```

```markdown
# 2027 Observed Days Off

**Source:** Office announcement, emailed 2026-11-11
**Valid:** 2027-01-01 to 2027-12-31
**Added:** 2026-11-11
**Original:** days-off-2027.pdf

---

The document's content, as markdown.
```

| Part | Read as |
| --- | --- |
| `# Title` | the first heading; with none, the file's name without `.md` |
| `**Source:**` | where it came from, free text |
| `**Valid:**` | `<from> to <to>`, kept exactly as written -- the readers show it and never parse it |
| `**Added:**` | the day it was filed |
| `**Original:**` | optional: a PDF or scan kept beside the `.md`; the `.md` is the record, so a search finds the document by its words |

A header line that is missing reads empty, and a file with none is still a document. A file whose name does
not end in `.md` is not one. The filename is the document's address; unlike a card, it carries no id.

## Who reads it

| Reader | Does |
| --- | --- |
| The agent | `GET /api/reference` lists the documents, with `?q=` to search them; `GET /api/reference/{name}` returns one document's whole text. Both are gated on `features.organize` and answer 404 when it is off |
| The web UI | Organize > Reference lists them, searches them and reads one |
| The CLI | the `Reference` verb ([#315](https://github.com/johnfrog76/toolkit/issues/315)), when it lands |

**Search** is the rule the hub's other searches use: every word must appear somewhere in the document,
in any order, case ignored, and a hit says the first line that carries one of the words.

**Both halves read one table**, `Tests/fixtures/reference/table.json`: each document's header as read,
and each search with the files it finds. The agent asserts it today (`Tests/test_reference.py`); the CLI's
suite asserts the same file when its half lands.

Nothing writes this folder. A person files a document by hand.
