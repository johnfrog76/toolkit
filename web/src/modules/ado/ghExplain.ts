import type { HomeTabId } from "../../shell/registry";

// A GitHub space's intro lines: the same slots wearing that tracker's words
// (the owner: "board, backlog, stats"; the strip reads
// Issues | Board | Stats -- and no ADO word on gh soil). The Board holds the space's OWN files, custom cards included;
// an ADO card cannot appear here -- it lives in its ADO space's folder.
// No `cards` line here: a gh space's Board tab always DRAWS the board
// (homeViewFor), and the board carries its own explain line and New card.
// A line may name the tracker, read from the Space, never typed.
export const GH_EXPLAIN: Partial<Record<HomeTabId, (tracker: string) => string>> = {
  backlog: () =>
    "Every open GitHub issue in the product's repo, read in place. Triage here; a card is for work with weight.",
  sprint: () =>
    "The repo's GitHub issues, counted: open and closed, severity, where each milestone stands -- and its last deploys.",
  design: (tracker) =>
    `The product's designs and specs, read from its ${tracker} repository: each note first, then the spec it became.`,
  docs: (tracker) => `The product's README and its docs, read from its ${tracker} repository.`,
};
