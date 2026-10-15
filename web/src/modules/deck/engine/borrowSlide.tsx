import type { Deck, Slide } from "../decks/types";
import { Say, Beat, Context } from "./PresenterNoteKit";

// Compilation-deck helper: build a deck from other decks' slides. Part of the
// deck engine's public toolkit for deck authors; no shipped deck uses it yet,
// and it is kept for a deck that gathers slides from other decks.
//
// A borrowed slide arrives WHOLE — `copy` and `content` untouched, in the
// source deck's own visual voice (safe because every deck's Stage mounts its
// own keyframes, so frames are self-contained; source-deck eyebrows read as
// museum labels). Only two things are replaced: the id (prefixed `hit-`, so
// it never collides and keys a fresh narration-cache entry) and the notes
// (your re-narration — typically a one-line story Say).
//
// Slide numbers are 1-based, exactly as the presenter's "N / M" counter shows
// them — curate by watching the deck, not by reading its code. The spread
// pattern is:
//
//   ...HITS.map(borrowSlide)
//
// Caveat: the copy is a shallow reuse of the source's ReactNodes (immutable
// descriptions — never mutate them), and a borrowed closing slide brings its
// CopyLinkButton along; prefer non-closing slides.

export interface BorrowedSlide {
  deck: Deck;
  /** 1-based slide number as shown in the source deck's presenter counter. */
  n: number;
  /** The re-narration — usually one sentence: what story this deck tells. */
  say: string;
  /** Presenter-only background: source deck, slide №, why it's in the set. */
  context?: string;
  /** Pacing cue; defaults to the register-shift pause. */
  beat?: string;
}

export function borrowSlide({ deck, n, say, context, beat }: BorrowedSlide): Slide {
  const source = deck.slides()[n - 1];
  if (!source) {
    throw new Error(`borrowSlide: ${deck.id} has no slide ${n} (deck has ${deck.slides().length})`);
  }
  return {
    ...source,
    id: `hit-${deck.id}`,
    notes: (
      <>
        <Beat>{beat ?? "Borrowed frame — pause, let the world change, then one sentence."}</Beat>
        <Say>{say}</Say>
        {context && <Context>{context}</Context>}
      </>
    ),
  };
}
