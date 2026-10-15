import type { Slide } from "../decks/types";
import { slideSpokenText } from "./sayText";

// How fast the Azure voice reads at its default rate (no SSML `rate` change).
// Re-calibrated against a real Brian recording of owasp-threat-codex (30
// slides, ~11.5k spoken chars, real transitions under 10s): that run clocked
// just under 15:00, which solves to ~15 chars/sec at a 5s dwell — closer to
// the ~15 raw-wpm math than the original 12 tuned for Jenny on museum-of-bugs.
// Re-measure and adjust if a future voice or rate reads noticeably differently.
export const NARRATION_CHARS_PER_SEC = 15;

// Flat per-slide time to take the slide in, on top of narration — the transition
// pause the estimate is asked to include. Applies even to a slide with no Say
// text (a pure-visual slide still costs viewing time).
export const SLIDE_DWELL_SECONDS = 5;

// Parse an authored "mm:ss" override into seconds, or null if not well-formed.
function parseMmSs(value: string | undefined): number | null {
  if (typeof value !== "string") return null;
  const match = /^(\d+):([0-5]\d)$/.exec(value.trim());
  return match ? Number(match[1]) * 60 + Number(match[2]) : null;
}

// Estimated on-screen seconds for one slide: an authored approximateTime wins
// outright, otherwise narration read time + the flat dwell.
export function estimateSlideSeconds(slide: Slide): number {
  const authored = parseMmSs(slide.approximateTime);
  if (authored !== null) return authored;
  const narrationSeconds = slideSpokenText(slide).length / NARRATION_CHARS_PER_SEC;
  return narrationSeconds + SLIDE_DWELL_SECONDS;
}

// Format a duration in seconds as "m:ss" (minutes are not zero-padded).
export function formatDuration(totalSeconds: number): string {
  const safe = Math.max(0, Math.round(totalSeconds));
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

// Approximate time to get through a whole deck, formatted "m:ss".
export function estimateDeckDuration(slides: Slide[]): string {
  return formatDuration(estimateDeckSeconds(slides));
}

// Unformatted, so callers can sum decks without parsing "m:ss" back apart.
export function estimateDeckSeconds(slides: Slide[]): number {
  return slides.reduce((sum, slide) => sum + estimateSlideSeconds(slide), 0);
}

/**
 * Total runtime of a whole library, in seconds.
 *
 * Separate from estimateDeckDuration because the unit differs: one deck is
 * minutes and formats as "m:ss", a library is hours and doesn't. Pass whichever
 * set you mean — every deck, or just the public ones.
 */
export function estimateLibrarySeconds(decks: readonly { slides: () => Slide[] }[]): number {
  return decks.reduce((sum, deck) => sum + estimateDeckSeconds(deck.slides()), 0);
}

/**
 * A library's runtime as "5h 30m" — the shape you'd say out loud, not a
 * timestamp. Falls back to "Nm" under an hour rather than printing "0h".
 */
export function formatLongDuration(totalSeconds: number): string {
  const safe = Math.max(0, Math.round(totalSeconds));
  // Carry BEFORE splitting: 59m40s rounds to 60 minutes, which must read "1h",
  // never "60m" or "0h 60m".
  const totalMinutes = Math.round(safe / 60);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours === 0) return `${minutes}m`;
  return minutes === 0 ? `${hours}h` : `${hours}h ${minutes}m`;
}

/** Convenience: a library's runtime, formatted. */
export function estimateLibraryDuration(decks: readonly { slides: () => Slide[] }[]): string {
  return formatLongDuration(estimateLibrarySeconds(decks));
}
