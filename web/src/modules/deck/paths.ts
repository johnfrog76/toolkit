// The deck module's addresses -- the one file its descriptor (index.tsx) may
// import statically (shell/lazyModules.test.ts), so the routes, the nav and the
// pages read the same strings.

/** The Decks card's own tab, when growth is off, and a deck's page under it. */
export const DECKS_HOME = "/decks";

/** A deck's page: between the list and the player, with the shell around it. */
export const DECK_PAGE_ROUTE = `${DECKS_HOME}/:deckId`;

/** The player, unchanged: full screen, chromeless. */
export const DECK_PLAY_PREFIX = "/deck/";

export function deckPagePath(id: string): string {
  return `${DECKS_HOME}/${encodeURIComponent(id)}`;
}

export function deckPlayPath(id: string): string {
  return `${DECK_PLAY_PREFIX}${encodeURIComponent(id)}`;
}
