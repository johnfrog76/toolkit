import { useMemo, useState } from "react";
import type { Slide } from "../decks/types";
import type { NarrationVoice } from "./narrationConstants";
import { voiceCoverage, type VoiceAvailability } from "./voiceCoverage";

// useVoiceControls — the ONE place that decides what the voice controls offer.
// Both narration surfaces mount it: the audience player's chrome (DeckPlayer →
// DeckChrome) and the presenter notes popout (PresenterNotes). It owns the two
// things they were each hand-rolling, and getting subtly differently:
//
//   1. which voices are selectable at all (deck-wide coverage), and
//   2. which voice is currently selected, kept honest against (1).
//
// Keeping selection in here with coverage is the point. Split apart — coverage
// in a helper, selection in each component's own useState — the two drift: a
// component can hold a selected voice its own picker has since disabled, and
// then the toggle looks live while every slide plays silence. Bound together,
// "selected" can only ever name a voice that actually narrates this deck.
//
// The host difference this encodes (see voiceCoverage.ts): pass hasApi when a
// live /api/narrate can synthesize on demand (the prompts web UI) and every
// voice stays enabled; pass a baked-asset resolver instead on a backend-free
// host (CSS Wasteland) and only fully-covered voices are offered. The SAME deck
// is therefore fully narratable in web and possibly silent in the Wasteland —
// coverage is a property of (deck, host), never of the deck alone.

export interface VoiceControls {
  /** Voices with deck-wide availability, for rendering the picker. */
  voices: VoiceAvailability[];
  /** The active voice id — always a covered one, or "" if none is. */
  voiceId: string;
  /** Select a voice. Ignores voices that can't narrate this deck. */
  setVoiceId: (voiceId: string) => void;
  /**
   * True if at least one voice can narrate at least one slide. False → the host
   * should render no narration controls at all (both voices missing ⇒ both
   * disabled, so there is nothing left to show).
   */
  hasAnyNarration: boolean;
}

export function useVoiceControls({
  slides,
  voices,
  hasApi = false,
  resolveUrl,
  preferredVoiceId,
  enabled = true,
}: {
  slides: readonly Slide[];
  voices: readonly NarrationVoice[];
  /**
   * True when the host has a live /api/narrate (the prompts web UI). Every voice
   * is then available regardless of what's been baked.
   */
  hasApi?: boolean;
  /**
   * Resolve a (slide, voice) clip URL, or null when absent. Needed to survey
   * coverage on backend-free hosts; ignored when hasApi is true.
   */
  resolveUrl?: (slide: Slide, voiceId: string) => string | null;
  /** A remembered choice (e.g. localStorage) to honor when it's covered. */
  preferredVoiceId?: string;
  /**
   * Set false to short-circuit the survey when the caller already knows
   * narration is off for this window (e.g. presenter mode in the player).
   */
  enabled?: boolean;
}): VoiceControls {
  const coverage = useMemo(
    () =>
      enabled
        ? voiceCoverage({ slides, voices, hasApi, resolveUrl, preferredVoiceId })
        : { voices: [], hasAnyNarration: false, defaultVoiceId: "" },
    [enabled, slides, voices, hasApi, resolveUrl, preferredVoiceId],
  );

  // Selection is stored as an INTENT and validated on read, rather than being
  // corrected by an effect. An effect would let one render escape with a dead
  // voice selected (and would re-run on every deck change); deriving keeps the
  // invariant true on the very first render, including when the deck changes
  // under a remembered-but-uncovered preference.
  const [intent, setIntent] = useState("");
  const voiceId = coverage.voices.find((v) => v.id === intent)?.available
    ? intent
    : coverage.defaultVoiceId;

  return {
    voices: coverage.voices,
    voiceId,
    setVoiceId: setIntent,
    hasAnyNarration: coverage.hasAnyNarration,
  };
}
