import { useMemo } from "react";
import { useParams, useSearchParams } from "react-router";
import { DeckPlayer } from "./engine/DeckPlayer";
import { PresenterNotes } from "./engine/PresenterNotes";
import { BAKED_VOICES, voiceUrl } from "./bakedVoices";
import { useViewport } from "./viewport";
import { DECKS } from "./decks/index";
import { DeckRoom } from "./DeckRoom";

// The Toolkit's host for the deck player: it resolves the two facts DeckPlayer
// refuses to infer -- which MODE this window is, and where its AUDIO comes from
// -- and hands them over as props. Everything else is the engine's.
//
// Mode. The package this engine came from was always "presenter": it had a live
// /api/narrate, so the notes window spoke and the deck window never did. The
// Toolkit has no narration service, and its voices are baked files, which only
// the AUDIENCE path plays. So the default here is audience -- the deck reads
// itself aloud, with no key and no server -- and `?present=1` is the podium:
// notes in a second window, the deck window silent. A phone is always audience;
// it cannot open the second window presenter mode needs.
//
// Audio. `hasApi={false}` and a resolver over the baked files (./bakedVoices).
// A voice is offered for a slide exactly when its file exists.
//
// This is the FIRST resolver: a deck found by the route's id in DECKS, the
// static list. A deck built from data (Team Agile's standup) comes through the
// second, GeneratedDeckHost.tsx, and is never pushed into DECKS.

function Player() {
  const { deckId } = useParams<{ deckId: string }>();
  const [searchParams] = useSearchParams();
  const { isMobile } = useViewport();
  const isPresenter = !isMobile && searchParams.get("present") === "1";

  const deck = DECKS.find((d) => d.id === deckId);
  const slides = useMemo(() => deck?.slides() ?? [], [deck]);

  return (
    <DeckPlayer
      deckId={deckId}
      deck={deck}
      slides={slides}
      mode={isPresenter ? "presenter" : "audience"}
      voices={BAKED_VOICES}
      hasApi={false}
      resolveNarrationUrl={(slide, voice) => voiceUrl(deckId, slide.id, voice)}
    />
  );
}

// The notes window narrates from the same baked files the player does, so it is
// handed the same facts: there is no narration service to ask.
function Notes() {
  const { deckId } = useParams<{ deckId: string }>();
  return (
    <PresenterNotes
      decks={DECKS}
      voices={BAKED_VOICES}
      hasApi={false}
      resolveNarrationUrl={(slide, voice) => voiceUrl(deckId, slide.id, voice)}
    />
  );
}

/** `/deck/:deckId` */
export default function DeckHost() {
  return (
    <DeckRoom>
      <Player />
    </DeckRoom>
  );
}

/** `/deck/:deckId/notes` -- a SEPARATE WINDOW with its own React tree. */
export function DeckNotesHost() {
  return (
    <DeckRoom>
      <Notes />
    </DeckRoom>
  );
}
