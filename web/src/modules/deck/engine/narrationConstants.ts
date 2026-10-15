// Narration constants — the voice roster, the storage key, and the exact words
// the UI uses to explain an unavailable voice.
//
// These were literals in three places (DeckChrome's picker, PresenterNotes'
// picker, Wasteland's bakedVoices), which is how the two windows drifted apart in
// the first place: a voice id typo'd in one list, or one surface saying "not
// baked" while the other said nothing, is invisible until someone plays a deck.
// Naming them once makes disagreement a type error instead of a silent bug.
//
// The ids are Azure neural voice names and are load-bearing beyond display: they
// are sent to /api/narrate AND they appear in baked filenames
// (<slideId>-<voiceId>.mp3). Renaming one orphans every baked asset for it, so
// treat this list as a published contract, not a preference.

/** A selectable narration voice: stable id + short display name. */
export interface NarrationVoice {
  id: string;
  name: string;
}

/**
 * The curated voice shortlist, shared by every host. Must stay a subset of the
 * backend's ALLOWED_NARRATE_VOICES; the Wasteland re-exports it rather than
 * keeping a parallel copy.
 */
export const NARRATION_VOICES: readonly NarrationVoice[] = [
  { id: "en-US-JennyNeural", name: "Jenny" },
  { id: "en-US-BrianNeural", name: "Brian" },
] as const;

/** Fallback voice when nothing valid is remembered. */
export const DEFAULT_VOICE_ID = "en-US-JennyNeural";

/** localStorage key for the presenter's remembered voice choice. */
export const VOICE_STORAGE_KEY = "toolkit-narration-voice";

/**
 * localStorage key for a generated deck's mute: "1" muted, absent or
 * "0" not. Per browser; read before the first slide plays.
 */
export const NARRATION_MUTED_STORAGE_KEY = "toolkit-narration-muted";

/** The mute button's tooltip, by state. Its accessible name stays MUTE_NARRATION_LABEL. */
export const MUTE_NARRATION_LABEL = "Mute narration";
export const UNMUTE_NARRATION_LABEL = "Unmute narration";

// ── Control copy ─────────────────────────────────────────────────────────────
// Kept here so both pickers explain an unavailable voice the same way. The
// distinction matters: a voice is "not baked" (this deck lacks its audio) which
// is different from narration being absent entirely.

/** Suffix on a picker option for a voice this deck wasn't fully baked in. */
export const VOICE_NOT_BAKED_SUFFIX = "— not baked";

/** Title/tooltip when no voice can narrate this deck on this host. */
export const NO_NARRATION_TITLE = "No narration available for this deck";

/** Title/tooltip for the voice picker when narration is available. */
export const VOICE_PICKER_TITLE = "Narration voice";

/** Label for a voice option, marking the uncovered ones inline. */
export function voiceOptionLabel(name: string, available: boolean): string {
  return available ? name : `${name} ${VOICE_NOT_BAKED_SUFFIX}`;
}
