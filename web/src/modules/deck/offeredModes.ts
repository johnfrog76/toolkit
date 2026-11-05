import { ALL_DECK_MODES } from "./engine/DeckPlayer";
import type { DeckMode } from "./engine/DeckPlayer";

// The modes each of this module's hosts offers the player (DeckPlayer's
// `offeredModes`). The engine draws Podium only where it is offered AND the
// window is wider than a phone, so the phone rule is the engine's and these say
// only where a podium can exist at all.

/**
 * A deck listed in decks/index.ts (DeckHost.tsx): Sofa, and Podium at
 * `?present=1`, because its notes window (`/deck/<id>/notes`) finds the deck in
 * the same list.
 */
export const LISTED_DECK_MODES: readonly DeckMode[] = ALL_DECK_MODES;

/**
 * The viewer's bar only, with no Podium anywhere: a deck built from data
 * (GeneratedDeckHost.tsx), whose notes window would not find it in the list,
 * and the landing page's commercial, which has no notes route at all.
 */
export const VIEWER_ONLY_MODES: readonly DeckMode[] = ["audience"];
