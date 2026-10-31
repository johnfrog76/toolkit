// How the module throws confetti (D-AR14; docs/modules/solitaire-agile.md, "Milestones:
// the tab and the award"). The party is drawn ONCE, at the app root, over the whole
// viewport: the module contributes one mount, ConfettiLayer, through the registry's
// `overlays` (shell/registry.ts), and a caller throws a burst through `useConfetti()`.
// So nothing that celebrates draws a canvas under its own tree.
//
// This file is the channel between the two, and it is deliberately small and free of
// React components and of the confetti package: a caller and the mount both import it,
// and neither one's chunk pulls the package in. A module-level channel rather than a
// React context, because a provider that WRAPS the app cannot be a lazy part without
// suspending everything under it; the mount listens here instead, from wherever the
// shell draws it. With features.solitaireAgile off, the mount is not drawn, this file is
// never fetched, and nothing is listening.
//
// One trigger is one burst. Under prefers-reduced-motion a throw does nothing at all --
// no burst, no fetch of the package -- and the words that say what was reached are the
// caller's, so they stay. Whether to celebrate is the caller's rule (celebrate.ts's mark),
// and the award dialog is the one caller (a test holds that): confetti with no dialog
// around it to say why read as a glitch.

const REDUCED_MOTION = "(prefers-reduced-motion: reduce)";

/** Whether the viewer asked for less motion. Never throws; no matchMedia reads as no. */
export function prefersReducedMotion(): boolean {
  try {
    return !!window.matchMedia?.(REDUCED_MOTION).matches;
  } catch {
    return false;
  }
}

type Listener = () => void;
const listeners = new Set<Listener>();
// A throw that arrived before the mount's chunk did: held, and handed to the first
// listener, so it still rains -- once.
let pending = false;

/** Throw one burst over the whole viewport. Under reduced motion, nothing. */
export function throwConfetti(): void {
  if (prefersReducedMotion()) return;
  if (listeners.size === 0) {
    pending = true;
    return;
  }
  listeners.forEach((l) => l());
}

/** The mount's side: called once per burst thrown. Returns the unsubscribe. */
export function onConfetti(listener: Listener): () => void {
  listeners.add(listener);
  if (pending) {
    pending = false;
    listener();
  }
  return () => {
    listeners.delete(listener);
  };
}

/** The hook a caller throws confetti through: `const throwConfetti = useConfetti()`. */
export function useConfetti(): () => void {
  return throwConfetti;
}

/** Forget every listener and any held burst -- for the tests. */
export function resetConfetti(): void {
  listeners.clear();
  pending = false;
}
