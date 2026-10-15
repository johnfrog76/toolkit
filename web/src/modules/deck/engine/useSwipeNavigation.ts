import { useCallback, useRef } from "react";

// ── useSwipeNavigation — thumb paging for the compact deck ───────────────────
//
// A horizontal drag across the slide pages the deck: left ⇒ next, right ⇒
// prev, the same direction a photo roll moves. Compact layouts only; on a
// desktop the hook returns no handlers at all, so a mouse drag over a slide
// stays a mouse drag over a slide.
//
// DUPLICATED FILE — same contract as useSlideNarration and SuitcaseTransport
// (see their headers): this file exists byte-identical in prompts
// web/src/app/deck-components and connected-deck src/deck-engine. The repos
// share no package; they sync by porting. So: React only, no imports beyond
// it, no context, no ambient hooks, and any change made in one copy gets made
// in the other.
//
// No gesture library on purpose. The detection is a subtraction and three
// thresholds; what a library would add here is a second dependency that BOTH
// repos have to install and keep at matching versions forever, for arithmetic.
// The hard part of a swipe isn't recognizing a good one, it's rejecting the
// bad ones — a scroll, a tap, a slow fidget, a drag that started on the
// transport button — and those four rules are clearer named here than as a
// config object handed to someone else's state machine.
//
// Pointer Events rather than touch events: one code path covers touch, pen,
// and mouse, and setPointerCapture means a drag that wanders off the element
// (or off the window) still resolves on THIS element instead of vanishing.
//
// ── What this must not disturb ───────────────────────────────────────────────
//
// Suitcase Mode's auto-advance. This hook does not touch narration, the dwell
// timer, or `paused` — it calls the SAME stepNext/stepPrev the paging arrows and
// the arrow keys call, so a swipe is indistinguishable from a manual page as
// far as the rest of the player is concerned. Everything downstream keeps
// working because it was already written for manual paging:
//
//   • Mid-dwell swipe (the ~5s gap after a clip ends): useSlideNarration's
//     `stop()` clears the pending dwell timer on the slide change, so the
//     queued auto-advance can't fire a second stepNext on top of the swipe.
//   • Playing deck: the url change restarts narration at the new slide's clip
//     from the beginning, which is exactly the "plays from the start" the
//     arrows already give.
//   • Paused deck: `heldRef` loads the new clip without starting it, so an
//     explicit pause outranks the swipe and survives it.
//
// If a future change makes swipe navigation call anything other than the
// host's own paging callbacks, all three of those stop being free.

/** Minimum horizontal travel, in px. Below this the gesture was a tap. */
const SLOP_PX = 50;

/**
 * How decisively horizontal a swipe must be: |dx| must exceed |dy| by this
 * factor. A deck slide on a phone is a scrollable column of copy, and the
 * cost of the two mistakes isn't symmetric — a swallowed page-turn is a
 * shrug and a second try, a page-turn that fires mid-scroll loses the
 * reader's place in something they were reading.
 */
const DIRECTION_RATIO = 1.5;

/**
 * Longest gesture still read as a swipe. Past this the thumb was resting,
 * dragging, or selecting, and a page turn would come as a surprise.
 */
const MAX_DURATION_MS = 600;

/**
 * A gesture starting on a control belongs to that control. Suitcase Mode's
 * transport is a big circular button sitting right under the thumb — without
 * this, a slightly-dragged tap on Pause would page the deck as well.
 */
const INTERACTIVE = "button, a, input, select, textarea, [role='button'], [role='slider']";

export interface SwipeHandlers {
  onPointerDown?: (e: React.PointerEvent) => void;
  onPointerUp?: (e: React.PointerEvent) => void;
  onPointerCancel?: (e: React.PointerEvent) => void;
}

export function useSwipeNavigation({
  onNext,
  onPrev,
  enabled,
}: {
  /** Page forward. Pass the host's own stepNext — see the header. */
  onNext: () => void;
  /** Page back. Pass the host's own stepPrev. */
  onPrev: () => void;
  /**
   * Off ⇒ the returned object is empty and nothing binds. The caller's
   * layout gate (compact/mobile) lives here rather than inside this hook:
   * the hook knows what a swipe is, the host knows where swiping is wanted.
   */
  enabled: boolean;
}): SwipeHandlers {
  // The in-flight gesture. A ref, not state: nothing about a half-finished
  // drag belongs on screen, and re-rendering the whole player on pointermove
  // is the one thing that would make this feel worse than no gesture at all.
  const startRef = useRef<{ x: number; y: number; t: number; id: number } | null>(null);

  const onPointerDown = useCallback((e: React.PointerEvent) => {
    // Secondary buttons and multi-touch (a pinch-zoom's second finger) are
    // not page turns. isPrimary keeps the second contact from opening a
    // gesture the first one will then try to close.
    //
    // `=== false` rather than a falsy check: an environment without a real
    // PointerEvent constructor (jsdom, and any synthetic event built from a
    // plain Event) leaves isPrimary undefined, and treating that as
    // not-primary silently rejects every gesture. Only an explicit false — a
    // genuine secondary contact — disqualifies.
    if (e.isPrimary === false || e.button !== 0) return;
    if ((e.target as Element | null)?.closest?.(INTERACTIVE)) return;
    startRef.current = { x: e.clientX, y: e.clientY, t: e.timeStamp, id: e.pointerId };
    // NO setPointerCapture here, deliberately — it was tried and removed.
    //
    // Capture is the textbook move for drags, and it is wrong for this one.
    // The swipe surface is a full-bleed, position-fixed element that fills
    // the player: a gesture cannot leave it, so capture buys nothing. What it
    // COST was the feature — with capture held, slide content re-rendering
    // under the pointer fired pointercancel mid-gesture, and every swipe from
    // the third slide on died silently. Measured: an identical gesture
    // without capture advances the same slide immediately.
    //
    // If a future layout lets a drag start inside the surface and end outside
    // it, revisit — but pair it with the pointercancel handling below, and
    // re-run the repeated-swipe check, not just a single swipe.
  }, []);

  const onPointerUp = useCallback(
    (e: React.PointerEvent) => {
      const start = startRef.current;
      startRef.current = null;
      if (!start || start.id !== e.pointerId) return;

      const dx = e.clientX - start.x;
      const dy = e.clientY - start.y;
      const elapsed = e.timeStamp - start.t;

      if (elapsed > MAX_DURATION_MS) return; // a drag, not a flick
      if (Math.abs(dx) < SLOP_PX) return; // a tap, or a twitch
      if (Math.abs(dx) < Math.abs(dy) * DIRECTION_RATIO) return; // a scroll

      // Drag the content left to bring the next slide in from the right.
      if (dx < 0) onNext();
      else onPrev();
    },
    [onNext, onPrev],
  );

  // Cancel means the browser took the gesture over (scroll takeover, or the
  // OS back-swipe on a screen edge). Drop it — pointerup will never come, and
  // a stale start would let the NEXT unrelated pointerup measure against it.
  const onPointerCancel = useCallback(() => {
    startRef.current = null;
  }, []);

  // Nothing to bind when disabled — no listeners, no per-render allocation on
  // the tier that will never use them.
  if (!enabled) return {};

  return { onPointerDown, onPointerUp, onPointerCancel };
}
