import type { IssueFacts } from "./IssuePopover";
import type { RitualItem } from "./api.solitaireAgile";

// One reading of a standup item, for the page and the played deck alike
// (docs/SCENARIOS.md, "the tracker and the cards read, joined"): an item is an
// ISSUE when it has a number -- `#<n>`, linked to its url -- and otherwise a
// CARD: its id, no link, with the card's path.

/** True for an issue (a number), false for a card of its own. */
export const isIssue = (i: RitualItem): boolean => i.number != null;

/** How the item is named in text: `#<n>`, or a card's id. */
export const itemRef = (i: RitualItem): string => (isIssue(i) ? `#${i.number}` : (i.id ?? ""));

/** A stable React key: the issue's number, else the card's id. */
export const itemKey = (i: RitualItem): string | number => i.number ?? i.id ?? i.title;

/** What the popover shows for it: the url for an issue, the path for a card. */
export const itemFacts = (i: RitualItem): IssueFacts =>
  isIssue(i)
    ? { title: i.title, label: itemRef(i), url: i.url }
    : { title: i.title, label: itemRef(i), path: i.path };

/** How the voice reads it: `issue <n>, <title>` or `card <id>, <title>`. */
export const itemSpoken = (i: RitualItem): string =>
  `${isIssue(i) ? `issue ${i.number}` : `card ${i.id}`}, ${i.title}`;
