# changelog.d

Each change a user would notice leaves its changelog entry here, as a file of its own, instead of
adding a line to `## [Unreleased]` in [`CHANGELOG.md`](../CHANGELOG.md). Two pull requests built side
by side then never edit the same lines. This page is the folder's own README and is never an entry.

## One file per entry

Name the file `<id>.<kind>.md`:

- `<id>` is the card or the issue the change belongs to: `MY6C`, `214`. Letters, digits, `-` and `_`,
  starting with a letter or a digit. A change with two entries of the same kind can put both in one
  file, or use two ids (`214-docs`).
- `<kind>` is the Keep a Changelog heading the entry goes under: `added`, `changed`, `removed` or
  `fixed`. A change that adds one thing and fixes another writes two files, `214.added.md` and
  `214.fixed.md`.

The file holds the entry exactly as it will read in the changelog: a line that starts with a dash and a space, written
for the person who reads release notes -- what they can now do, or what stopped going wrong, in a
sentence. Several entries are several such lines. A long entry may wrap onto indented lines; no
blank line and no heading goes inside.

```markdown
- `Land <id>` ends a card once its pull request is merged.
```

A change nobody would notice adds no file.

## At a release

The release pull request folds this folder into `CHANGELOG.md` before it renames the section:

```powershell
pwsh -NoProfile -File Scripts/Fold-Changelog.ps1 -WhatIf   # the section it would write
pwsh -NoProfile -File Scripts/Fold-Changelog.ps1           # write it, delete the folded files
```

Each entry goes at the end of its heading's list under `## [Unreleased]`, a missing heading is added
in Keep a Changelog order, and every folded file is deleted; this README stays. A file that is not
the shape above stops the fold before anything is written, naming the file. `-Check` reads the
folder and writes nothing; the CLI suite runs it over the committed tree, so a misnamed file fails
the pull request that adds it. The rest of the release is
[`AGENTS.md`, "A release is a tag on main"](../AGENTS.md#a-release-is-a-tag-on-main).
