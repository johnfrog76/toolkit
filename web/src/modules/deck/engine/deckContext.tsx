import { createContext, useContext } from "react";
import type { Deck } from "../decks/types";

// The deck a slide is being rendered inside, for the few things a slide's
// content needs to know about its owner that a `Slide` does not carry. Today
// that is one thing: which project the deck belongs to, so the giveaway
// button can resolve its target without every deck passing a URL.
//
// Provided by DeckPlayer around the live slide and by PresenterNotes around
// the next-slide preview. Null everywhere else — the poster wall, the details
// page, a test render — and every consumer has a sensible answer for null,
// because a slide must render the same whether or not a player is around it.
export const DeckContext = createContext<Deck | null>(null);

export function useDeck(): Deck | null {
  return useContext(DeckContext);
}
