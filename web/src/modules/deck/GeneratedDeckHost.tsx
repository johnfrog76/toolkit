import { useMemo, useState } from "react";
import type { ReactElement } from "react";
import { Spinner } from "@fluentui/react-components";
import { SlideTextRegular } from "@fluentui/react-icons";
import { DeckPlayer } from "./engine/DeckPlayer";
import { NARRATION_MUTED_STORAGE_KEY } from "./engine/narrationConstants";
import type { NarrationVoice } from "./engine/narrationConstants";
import { usePersistedFlag } from "../../shared/usePersistedState";
import type { Deck, Slide } from "./decks/types";
import { DeckRoom } from "./DeckRoom";
import { EmptyState } from "../../shared/EmptyState";

// ── The second resolver: a deck BUILT from data ─────────────────────────────
//
// DeckHost.tsx is the first: it finds a hand-written deck by the route's id in
// DECKS, the static list. A generated deck -- Team Agile's standup, written
// this morning by the tracker -- is not in that list and is never pushed into
// it. The module that owns its data builds the Deck and hands it here as a
// RESOLUTION, with the two states a fetch has before it has a deck; the room
// and the player are the same ones a listed deck gets.
//
// Its own file, not a second export of DeckHost.tsx, on purpose: DeckHost
// imports DECKS and the baked voices, and a module that plays a generated
// deck (with `features.deck` off, even) should fetch the engine, not the two
// shipped decks and their audio.
//
// A generated deck is an audiobook (decks/types.ts): no baked clip exists for
// a sentence written this morning, so the voice is the browser's
// (useSpeechNarration), offered as one voice, and the deck opens in Suitcase
// Mode, narrating, at any width. Always audience: a presenter's notes window
// finds its deck in DECKS, and this one is not there.

/** What a second resolver hands the host. */
export interface DeckResolution {
  /** The built deck, once there is one. */
  deck?: Deck;
  loading: boolean;
  /** Why there is no deck, in the module's own words, for the shared empty state. */
  error?: { title: string; detail?: string };
}

/** The one voice a generated deck offers: the browser's own (D-TA7). */
export const BROWSER_VOICE: readonly NarrationVoice[] = [{ id: "browser", name: "Browser voice" }];

/** No clip exists for a generated slide; the browser's voice reads it. */
const noClip = (_slide: Slide, _voice: string): string | null => null;

function centered(child: ReactElement) {
  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      {child}
    </div>
  );
}

function GeneratedPlayer({ resolution }: { resolution: DeckResolution }) {
  const { deck, loading, error } = resolution;
  const slides = useMemo(() => deck?.slides() ?? [], [deck]);
  // Suitcase is the host's preference to keep, as the Wasteland's host keeps
  // its own; here it starts ON and lives as long as the room does.
  const [suitcase, setSuitcase] = useState(true);
  // Mute: per browser, read before the first slide plays. Default is
  // not muted -- narration on, as it was. Storage refused reads as the default.
  const { value: muted, toggle: toggleMuted } = usePersistedFlag(NARRATION_MUTED_STORAGE_KEY);
  if (loading) return centered(<Spinner size="medium" label="Loading the deck..." />);
  if (error || !deck) {
    return centered(
      <EmptyState
        icon={<SlideTextRegular />}
        tone="error"
        title={error?.title ?? "Nothing to play"}
        detail={error?.detail}
      />,
    );
  }
  return (
    <DeckPlayer
      deckId={deck.id}
      deck={deck}
      slides={slides}
      mode="audience"
      voices={BROWSER_VOICE}
      hasApi
      resolveNarrationUrl={noClip}
      narrateByDefault
      mute={{ muted, onToggle: toggleMuted }}
      suitcaseMode={suitcase}
      onToggleSuitcaseMode={() => setSuitcase((on) => !on)}
    />
  );
}

/** A deck built from data by the module that owns it; see DeckResolution. */
export function GeneratedDeckHost({ resolution }: { resolution: DeckResolution }) {
  return (
    <DeckRoom>
      <GeneratedPlayer resolution={resolution} />
    </DeckRoom>
  );
}
