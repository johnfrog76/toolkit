import { useEffect, useMemo } from "react";
import { MemoryRouter, useLocation } from "react-router";
import { DeckPlayer } from "../modules/deck/engine/DeckPlayer";
import { DeckRoom } from "../modules/deck/DeckRoom";
import { BAKED_VOICES, voiceUrl } from "../modules/deck/bakedVoices";
import { theToolkitDeck } from "../modules/deck/decks/the-toolkit";

// The commercial on the landing page: the same deck, engine and baked clips
// the app's Deck tab plays, imported as source (D-LP2).
//
// The banner's call to action plays it: the deck fills the window in its own
// room, reading itself aloud in its baked voices -- the press is the gesture a
// browser asks for before it plays sound -- and leaving it (its own exit, or
// Escape) brings the page back with focus on the call to action.
//
// The player is the app's DeckPlayer exactly as DeckHost.tsx hands it over,
// with one difference: narration starts on. Its controller pages and exits
// through a router, so it plays inside an in-memory one that holds two entries,
// the page and the deck; the address bar is never touched, and the page itself
// has no routes.

const PAGE_PATH = "/";
const DECK_PATH = `/deck/${theToolkitDeck.id}`;

/** Leaves the player when its controller navigates away from the deck. */
function ExitWatch({ onExit }: { onExit: () => void }) {
  const { pathname } = useLocation();
  useEffect(() => {
    if (pathname !== DECK_PATH) onExit();
  }, [pathname, onExit]);
  return null;
}

/** The deck, playing over the whole window. */
export function CommercialPlayer({ onExit }: { onExit: () => void }) {
  const slides = useMemo(() => theToolkitDeck.slides(), []);
  return (
    <DeckRoom>
      <MemoryRouter initialEntries={[PAGE_PATH, DECK_PATH]} initialIndex={1}>
        <ExitWatch onExit={onExit} />
        <DeckPlayer
          deckId={theToolkitDeck.id}
          deck={theToolkitDeck}
          slides={slides}
          mode="audience"
          voices={BAKED_VOICES}
          hasApi={false}
          resolveNarrationUrl={(slide, voice) => voiceUrl(theToolkitDeck.id, slide.id, voice)}
          narrateByDefault
        />
      </MemoryRouter>
    </DeckRoom>
  );
}
