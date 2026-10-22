import { useEffect, useRef, useState } from "react";
import ReactConfetti from "react-confetti";
import { hasSeen, markSeen, shouldCelebrate } from "./celebrate";

// The celebration (D-AR14; docs/modules/solitaire-agile.md, "The PM Corner: the line,
// the chevron, the confetti"): confetti over the whole viewport, once, in the page --
// no backend, no sound, no push, no message to anyone. ONE wrapper over the
// `react-confetti` package owns it, so every surface that celebrates looks the same:
// the Team Agile page's milestone reached today, and any later surface that calls
// <Confetti> and useCelebrateOnce with its own storage key.
//
// The wrapper is mounted with the viewport's size, `recycle={false}` and a piece count
// that rains out in a few seconds, and draws NOTHING under prefers-reduced-motion --
// the words that say what was reached are the caller's, and they stay.
//
// It is only ever imported by a lazyPart (shell/lazy.tsx), so its bytes and the
// package's are fetched with the part that celebrates, never with the app.

/** How many pieces one burst throws: enough to fill the screen, few enough to finish
 *  in a few seconds with recycle off. */
export const CONFETTI_PIECES = 400;

const REDUCED_MOTION = "(prefers-reduced-motion: reduce)";

/** Whether the viewer asked for less motion. Never throws; no matchMedia reads as no. */
export function prefersReducedMotion(): boolean {
  try {
    return !!window.matchMedia?.(REDUCED_MOTION).matches;
  } catch {
    return false;
  }
}

function viewport(): { width: number; height: number } {
  return { width: window.innerWidth || 0, height: window.innerHeight || 0 };
}

/** One burst over the whole viewport, then `onDone`. Under reduced motion it draws
 *  nothing and calls `onDone` at once. */
export function Confetti({
  onDone,
  pieces = CONFETTI_PIECES,
}: {
  onDone?: () => void;
  pieces?: number;
}) {
  const [size, setSize] = useState(viewport);
  const [reduced] = useState(prefersReducedMotion);
  // The latest onDone, kept outside render (a burst may end after a re-render).
  const done = useRef(onDone);
  useEffect(() => {
    done.current = onDone;
  }, [onDone]);

  useEffect(() => {
    if (reduced) {
      done.current?.();
      return;
    }
    const resize = () => setSize(viewport());
    window.addEventListener("resize", resize);
    return () => window.removeEventListener("resize", resize);
  }, [reduced]);

  if (reduced) return null;
  return (
    <ReactConfetti
      data-testid="confetti"
      width={size.width}
      height={size.height}
      recycle={false}
      numberOfPieces={pieces}
      style={{ position: "fixed", inset: 0, zIndex: 1000, pointerEvents: "none" }}
      onConfettiComplete={(instance) => {
        instance?.reset();
        done.current?.();
      }}
    />
  );
}

/**
 * Whether to show a burst for `id` now, and the call that ends it. The rule is
 * celebrate.ts's: a transition to `active` while this mount watched, or a first sight of
 * it active with the browser's mark absent under `storageKey`. Firing sets the mark, so
 * a reload does not fire again.
 */
export function useCelebrateOnce(
  storageKey: string,
  id: string,
  active: boolean,
): { firing: boolean; done: () => void } {
  const last = useRef<{ id: string; active: boolean } | null>(null);
  const [firing, setFiring] = useState<string | null>(null);

  useEffect(() => {
    const wasActive = last.current && last.current.id === id ? last.current.active : null;
    last.current = { id, active };
    if (!id) return;
    if (shouldCelebrate({ active, wasActive, seen: hasSeen(storageKey, id) })) {
      markSeen(storageKey, id);
      setFiring(id);
    }
  }, [storageKey, id, active]);

  return { firing: !!id && firing === id, done: () => setFiring(null) };
}
