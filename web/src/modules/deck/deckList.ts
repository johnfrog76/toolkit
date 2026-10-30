import type { Deck } from "./decks/types";
import { DeckState } from "./decks/types";
import type { ConfigEditPayload } from "../ado/cliBridge";

/**
 * What the Decks card and a deck's page read, kept apart from both so the rules
 * are one table (`deckList.test.ts`, and the scenarios grid in
 * `shell/scenarios.test.tsx`). Nothing here imports a deck file: the decks are
 * handed in, so the rules load without the slides.
 *
 * TWO archives, and they are different things:
 *   - a deck's own `state` (draft, in progress, complete, archive) is the
 *     studio's, written in the deck file, and only read here;
 *   - `deck.archived` is THIS MACHINE's put-away list, by deck id, written
 *     through `Config` (PUT /api/config) and served by `/env` as
 *     `config.deckArchived`. Putting a deck away never edits its file.
 * docs/modules/deck.md, "A deck's page".
 */

/** The machine setting the put-away list is written to, through Config. */
export const DECK_ARCHIVED_KEY = "deck.archived";

/**
 * The played copy: the deck file in this repository. A deck file is named for
 * its id (`deckList.test.ts` holds it for every registered deck), so the path is
 * derived, not stored.
 */
export function deckFilePath(id: string): string {
  return `web/src/modules/deck/decks/${id}.tsx`;
}

/** A deck's lifecycle state as its file says it; unset reads Complete, as the card always has. */
export function deckState(deck: Pick<Deck, "state">): DeckState {
  return deck.state ?? DeckState.Complete;
}

/** The words a state wears on its chip. */
export const STATE_LABEL: Record<DeckState, string> = {
  [DeckState.Draft]: "draft",
  [DeckState.InProgress]: "in progress",
  [DeckState.Complete]: "complete",
  [DeckState.Archive]: "archive",
};

export const STATE_ORDER: DeckState[] = [
  DeckState.Draft,
  DeckState.InProgress,
  DeckState.Complete,
  DeckState.Archive,
];

/** The archived filter: the decks put away on this machine. */
export const ARCHIVED_FILTER = "archived";
export type DeckFilter = DeckState | typeof ARCHIVED_FILTER | null;

/** The put-away list, cleaned: a string id, each once. */
export function archivedIds(raw: readonly unknown[] | undefined): string[] {
  const out: string[] = [];
  for (const v of raw ?? []) {
    if (typeof v === "string" && v && !out.includes(v)) out.push(v);
  }
  return out;
}

export interface DeckListView<D> {
  /** The default list: every deck not put away on this machine. */
  current: D[];
  /** The decks put away on this machine, in the list's order. */
  archived: D[];
  /** Per state, over the default list. */
  stateCounts: Partial<Record<DeckState, number>>;
  /** Draw the state chips only once two decks in the default list differ. */
  showStates: boolean;
  /** Draw the archived chip only once a deck is put away. */
  showArchived: boolean;
  /** What the filter shows. */
  shown: D[];
}

/**
 * The Decks card's list for one filter. `null` is the default list (no deck put
 * away on this machine); a state narrows the default list; `archived` is the
 * decks put away. A put-away id that names no registered deck is ignored.
 */
export function deckListView<D extends Pick<Deck, "id" | "state">>(
  decks: readonly D[],
  archived: readonly string[],
  filter: DeckFilter,
): DeckListView<D> {
  const away = new Set(archived);
  const current = decks.filter((d) => !away.has(d.id));
  const archivedDecks = decks.filter((d) => away.has(d.id));
  const stateCounts: Partial<Record<DeckState, number>> = {};
  for (const d of current) {
    const s = deckState(d);
    stateCounts[s] = (stateCounts[s] ?? 0) + 1;
  }
  const shown =
    filter === ARCHIVED_FILTER
      ? archivedDecks
      : filter === null
        ? current
        : current.filter((d) => deckState(d) === filter);
  return {
    current,
    archived: archivedDecks,
    stateCounts,
    showStates: Object.keys(stateCounts).length > 1,
    showArchived: archivedDecks.length > 0,
    shown,
  };
}

/**
 * The Config edit that puts a deck away (`put` true) or brings it back. The list
 * is the whole value -- an array replaces -- and an empty list is unset rather
 * than written, so the shipped default (none) stands.
 */
export function archiveEdit(
  current: readonly string[],
  id: string,
  put: boolean,
): ConfigEditPayload {
  const next = put ? [...current.filter((x) => x !== id), id] : current.filter((x) => x !== id);
  return next.length > 0
    ? { set: { [DECK_ARCHIVED_KEY]: next }, unset: [] }
    : { set: {}, unset: [DECK_ARCHIVED_KEY] };
}
