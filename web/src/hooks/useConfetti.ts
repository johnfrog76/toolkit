import { createContext, useContext } from "react";

// The celebration's one way in (D-AR14; docs/modules/solitaire-agile.md, "Milestones:
// the tab and the award"). The confetti belongs to the whole app: ONE burst is mounted
// at the shell's root (shell/ConfettiProvider.tsx), over the whole viewport, and a
// caller throws it through this hook rather than mounting a component of its own --
// so whatever celebrates gets the full-screen party, not something drawn under one
// dialog's tree. Whether to celebrate stays the caller's rule, and so do the words
// that say why: a test holds that the award dialog is the one caller.

const REDUCED_MOTION = "(prefers-reduced-motion: reduce)";

/** Whether the viewer asked for less motion. Never throws; no matchMedia reads as no. */
export function prefersReducedMotion(): boolean {
  try {
    return !!window.matchMedia?.(REDUCED_MOTION).matches;
  } catch {
    return false;
  }
}

/** The root's thrower. Outside a provider it does nothing, which is what a tree with no
 *  shell (a component under test, the landing page) should get. */
export const ConfettiContext = createContext<() => void>(() => {});

/** `throwConfetti()`: one burst over the viewport, once per call. A call while a burst
 *  is still raining is absorbed into it, and under prefers-reduced-motion nothing
 *  rains -- the caller's words are what say it. */
export function useConfetti(): () => void {
  return useContext(ConfettiContext);
}
