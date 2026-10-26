import { useEffect, useRef, useState } from "react";
import ReactConfetti from "react-confetti";

// The celebration (D-AR14; docs/modules/solitaire-agile.md, "Milestones: the tab and
// the award"): confetti over the whole viewport, once, in the page -- no backend, no
// sound, no push, no message to anyone. ONE wrapper over the `react-confetti` package
// owns it, so every surface that celebrates looks the same. Its one caller is the
// award dialog on the Milestones tab (AwardDialog.tsx) -- a test holds that: confetti
// with no dialog around it to say why read as a glitch. Whether to celebrate is the
// caller's rule, over celebrate.ts's mark.
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
