import type { Deck } from "./types";
import { connectedDeckTrailerDeck } from "./connected-deck-trailer";
import { theToolkitDeck } from "./the-toolkit";

// The decks this Toolkit ships, and the ONE place they are registered.
//
// Two decks, on purpose. Trailer 2.0 (the owner: "that is all I want to
// see there"); and Introducing ToolKit, the Commercial, built
// in the Wasteland studio to its QA gate and moved here whole ("this lives with
// the Demo slug OOB" -- the owner); it is the one the Home banner
// opens on a first run. Both play with sound, no key and no server, from baked
// voices under voices/<deckId>/ -- the player has no browser-speech fallback,
// so a deck with no bake reads "not baked" and plays silent.
//
// A third, Meet the Toolkit -- Kit's draft tour -- was
// removed the day Introducing ToolKit took its place on the
// banner: a draft with no voices, in the launcher beside a finished deck that
// says the same thing better. Nothing is lost -- it is maintained in the
// Wasteland studio (src/decks/meet-the-toolkit.tsx), which
// is where Kit's full guided tour grows from.
// toolkit-figures.tsx stays:
// it is Introducing ToolKit's slide art too, and it is the studio's file.
//
// ONE registry, where the package this engine came from had two (`index.ts`'s
// PUBLIC_DECKS and `all.ts`). The split existed so a private deck was never
// BUNDLED into the public site. The Toolkit publishes nothing (the owner:
// "it is no longer publishing decks"), so there is no public bundle to keep a
// deck out of. `deployed` and `audience` stay on the Deck type so a deck file
// ports unchanged, and nothing here reads them. `state` still means what it
// always did -- Draft, InProgress, Complete, Archive -- and the launcher
// filters on it.
//
// PUBLIC_DECKS is kept as a name because the engine's notes window imports it;
// here it is simply every deck.
export const DECKS: Deck[] = [connectedDeckTrailerDeck, theToolkitDeck];
export const PUBLIC_DECKS: Deck[] = DECKS;
