import type { Slide } from "../decks/types";
import type { NarrationVoice } from "./narrationConstants";

// Voice coverage — the shared answer to "can this deck be narrated in this
// voice, at all?" Both narration surfaces ask it: the audience player's chrome
// (DeckChrome's Voice group) and the presenter notes popout. Neither may
// re-derive it, because when they disagree the UI lies in one of two directions
// — offering a voice that plays nothing, or hiding one that would have worked.
//
// Why a DECK-WIDE question and not a per-slide one, and why the bar is ALL
// slides. Per-slide availability already exists (SlideNarration.available gates
// the play toggle on the current slide). It is the wrong signal for the voice
// PICKER: a picker that enables Brian because slide 4 happens to have a Brian
// clip invites a viewer to select a voice that goes silent for the other twenty
// slides. The rule (voice controls are enabled only when voice files exist for
// them) is therefore evaluated once over the whole deck, as a COMPLETE
// CONTRACT — a voice is offered only if it can narrate the deck end to end:
//
//   • a voice missing a clip for ANY slide is disabled. Not "mostly baked" —
//     one gap means selecting it buys a deck that stops talking partway, which
//     is worse than a voice that was never offered. Partial bakes are a
//     backend-side state (a bake in progress), not a viewing option;
//   • if NO voice covers the deck, narration is unavailable altogether and the
//     controls come off the chrome entirely — toggle and picker both. There is
//     nothing to choose between and nothing to play.
//
// This is also why coverage is computed from the SAME resolver the player uses
// to fetch audio (resolveNarrationUrl). A second source of truth — a manifest,
// a deck-level boolean, a naming convention — could drift from what actually
// plays. Asking the resolver means "enabled" is by construction the set of
// voices that have a real URL behind them.
//
// ── The rule is about the HOST, not the deck ──────────────────────────────────
// The same deck is narratable in one app and not the other, so coverage is not a
// property of the deck. It is a property of (deck, host):
//
//   • hasApi: true — the prompts web UI, which has /api/narrate. There is NO
//     coverage question here. Any voice can synthesize any slide on demand, so
//     every voice stays enabled even for a deck with zero baked files. Baked
//     mp3s are only a write-through cache in this world; a cache miss is a
//     slower play, not a missing feature. Disabling a voice here because an
//     asset is absent would break narration that demonstrably works today.
//   • hasApi: false — CSS Wasteland, backend-free by design. Playable audio is
//     exactly the committed files, so the complete-contract rule above applies
//     and uncovered voices are disabled.
//
// Callers state which world they're in rather than having it inferred, so
// "no resolver passed" can never be mistaken for "no audio exists".

/** One voice's verdict, plus the display name so callers can render directly. */
export interface VoiceAvailability extends NarrationVoice {
  /**
   * True only if EVERY slide has a clip in this voice — the complete contract.
   * A single missing slide makes this false and the picker option disabled.
   */
  available: boolean;
  /**
   * How many slides have a clip in this voice. Compare against slides.length to
   * see how incomplete a partial bake is (this is NOT zero when unavailable —
   * an uncovered voice can still have most of its clips).
   */
  slideCount: number;
}

export interface VoiceCoverage {
  /** Per-voice verdicts, in the order the voices were declared. */
  voices: VoiceAvailability[];
  /**
   * True if ANY voice covers the deck completely. False → the host has no
   * narration to offer and must disable the whole control group, picker
   * included (rule 2a: no voice covers the deck ⇒ both disabled).
   */
  hasAnyNarration: boolean;
  /**
   * The voice a fresh session should start on: the caller's preferred voice if
   * it's actually covered, else the first covered voice, else "". Keeps a
   * remembered-but-unusable preference (a stored "Brian" on a Jenny-only deck)
   * from silently selecting a dead voice.
   */
  defaultVoiceId: string;
}

/**
 * Compute which of `voices` can narrate `slides` on THIS host.
 *
 * @param hasApi True when a live synthesizer (/api/narrate) is available, as in
 *   the prompts web UI: every voice is reported available regardless of baked
 *   assets. False for backend-free hosts (CSS Wasteland), where the
 *   complete-contract survey below decides.
 * @param resolveUrl Returns a clip URL, or null when that pair has no audio.
 *   Required to survey coverage when hasApi is false; ignored when it's true.
 * @param preferredVoiceId A remembered choice to honor if it's covered.
 */
export function voiceCoverage({
  slides,
  voices,
  hasApi = false,
  resolveUrl,
  preferredVoiceId,
}: {
  slides: readonly Slide[];
  voices: readonly NarrationVoice[];
  hasApi?: boolean;
  resolveUrl?: (slide: Slide, voiceId: string) => string | null;
  preferredVoiceId?: string;
}): VoiceCoverage {
  // A live synthesizer, or no way to survey at all (no resolver) — either way
  // there are no known-missing assets, so every voice stays enabled. Treating an
  // absent resolver as "unlimited" rather than "empty" keeps a host that simply
  // didn't wire coverage from silently losing its narration controls.
  if (hasApi || !resolveUrl) {
    const allCovered = voices.map((v) => ({
      ...v,
      // Still gated on there being something to narrate, so "available" can
      // never contradict hasAnyNarration on an empty deck.
      available: slides.length > 0,
      slideCount: slides.length,
    }));
    return {
      voices: allCovered,
      hasAnyNarration: voices.length > 0 && slides.length > 0,
      defaultVoiceId: pickDefault(allCovered, preferredVoiceId),
    };
  }

  const surveyed = voices.map((voice) => {
    // Count every hit rather than short-circuiting on the first MISS: the count
    // is what makes a partial bake legible ("Brian: 3 of 21") in a tooltip or a
    // log, instead of a bare boolean that can't say how far off it was. A
    // deck-wide survey is a cheap map lookup per slide.
    let slideCount = 0;
    for (const slide of slides) {
      if (resolveUrl(slide, voice.id)) slideCount += 1;
    }
    // Full coverage only. An empty deck has no slides to cover and so offers
    // nothing to narrate — guard against 0 === 0 reading as "covered".
    return {
      ...voice,
      available: slides.length > 0 && slideCount === slides.length,
      slideCount,
    };
  });

  return {
    voices: surveyed,
    hasAnyNarration: surveyed.some((v) => v.available),
    defaultVoiceId: pickDefault(surveyed, preferredVoiceId),
  };
}

/**
 * Preferred voice if covered, else the first covered voice, else "" — never a
 * voice we know plays nothing.
 */
function pickDefault(surveyed: readonly VoiceAvailability[], preferredVoiceId?: string): string {
  const preferred = surveyed.find((v) => v.id === preferredVoiceId);
  if (preferred?.available) return preferred.id;
  return surveyed.find((v) => v.available)?.id ?? "";
}
