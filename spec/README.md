# Specs

A product's specs can live here, in its own tree, or anywhere else the people who make it keep them.
This public product keeps a clean closet: the specs behind it are the maintainer's record, kept
outside the tree, so this folder holds nothing but this file.

When a product keeps its specs here, the folder holds one spec per file, `spec/<name>.spec.md`, with
the built ones under `archive/`. A spec carries the same id as the design note it grew from, and
`tkStampDesign` gives one to a file written without it. The Design tab reads the folder beside
`design/` and pairs each spec with its note, and the `design` row of the optional surfaces (`tkEnv`,
`tkMenu -All`) reads both to say whether the lifecycle is on; with nothing beside this file it reads
`not configured`. The file shape, the naming and the state rule are in
[`docs/hub/design.md`](../docs/hub/design.md).
