import { useEffect, useRef, useState } from "react";
import ReactConfetti from "react-confetti";
import { prefersReducedMotion } from "./useConfetti";

// The celebration (D-AR14; docs/modules/solitaire-agile.md, "Milestones: the tab and
// the award"): confetti over the whole viewport, once, in the page -- no backend, no
// sound, no push, no message to anyone. ONE wrapper over the `react-confetti` package
// owns it, so every surface that celebrates looks the same. It is mounted in one place,
// the module's root overlay (ConfettiLayer.tsx), and thrown through useConfetti() --
// whose one caller is the award dialog on the Milestones tab (a test holds both).
//
// The wrapper is mounted with the viewport's size, `recycle={false}` and a piece count
// that rains out in a few seconds, and draws NOTHING under prefers-reduced-motion --
// the words that say what was reached are the caller's, and they stay.
//
// It is only ever imported by a lazyPart (shell/lazy.tsx), so its bytes and the
// package's are fetched the first time a burst is thrown, never with the app.

/** How many pieces one burst throws: enough to fill the screen, few enough to finish
 *  in a few seconds with recycle off. */
export const CONFETTI_PIECES = 400;

/** The burst's layer: one above the layer Fluent mounts its portals in (a dialog, a
 *  menu, a toast -- z-index 1000000), so drawn from the app root it still rains OVER
 *  the dialog that threw it. It takes no pointer events, so nothing under it is lost. */
export const CONFETTI_Z_INDEX = 1_000_001;

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
      style={{ position: "fixed", inset: 0, zIndex: CONFETTI_Z_INDEX, pointerEvents: "none" }}
      onConfettiComplete={(instance) => {
        instance?.reset();
        done.current?.();
      }}
    />
  );
}
