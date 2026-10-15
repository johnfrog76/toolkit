# Design notes

A product's design notes can live here, in its own tree, or anywhere else the people who make it
keep them. This public product keeps a clean closet: the notes behind it are the maintainer's record,
kept outside the tree, so this folder holds nothing but this file.

When a product keeps its notes here, the folder holds one note per file, `design/<slug>.md`, with the
finished ones under `archive/`. A note carries an id in its frontmatter, and `tkStampDesign` gives one
to a file written without it. The Design tab reads the folder and groups what it finds by state, and
the `design` row of the optional surfaces (`tkEnv`, `tkMenu -All`) reads it to say whether the
lifecycle is on; with nothing beside this file it reads `not configured`. The file shape, the naming
and the state rule are in [`docs/hub/design.md`](../docs/hub/design.md).
