/** This module's route paths, in one place (see communication/paths.ts for why). */
export const SOLITAIRE_AGILE_HOME = "/solitaire-agile";

export const ROUTES = {
  /** Today's standup: the tab root, the useful view (the text). */
  home: SOLITAIRE_AGILE_HOME,
  /** Triage (V1): the open issues one at a time, unplaced first. Under
   *  the tab root, so the one Team Agile nav entry stays lit. */
  triage: `${SOLITAIRE_AGILE_HOME}/triage`,
  /** Milestones: one row per tracker milestone with its bar, and the award
   *  dialog -- the module's one celebration. Under the tab root, like Triage. */
  milestones: `${SOLITAIRE_AGILE_HOME}/milestones`,
  /**
   * Today's standup, PLAYED: the Remote Standup's stage as an audiobook deck
   * (V1). Under the deck module's `/deck/` prefix so it reads as a deck, but
   * this module's route -- it plays whether or not `features.deck` is on.
   */
  play: "/deck/ritual/standup",
} as const;

/** The played standup's deck id: what DeckPlayer is told it is playing. */
export const STANDUP_DECK_ID = "ritual-standup";
