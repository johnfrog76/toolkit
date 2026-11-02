import { useCallback, useRef, useState } from "react";
import type { ReactNode } from "react";
import { ConfettiContext, prefersReducedMotion } from "../hooks/useConfetti";
import { lazyPart } from "./lazy";

// The app's one confetti mount (D-AR14; docs/modules/solitaire-agile.md, "Milestones:
// the tab and the award"). It wraps the app once, near the root, and hands its
// thrower down through `useConfetti()` (hooks/useConfetti.ts): a caller says WHEN,
// and the burst is drawn here, over the whole viewport, outside every page's and
// dialog's tree.
//
// No bytes until something throws: the burst -- the wrapper (shared/Confetti.tsx)
// and the `react-confetti` package behind it -- is a lazyPart, fetched the first time
// a burst is drawn. With Team Agile off nothing calls the thrower, so nothing is
// fetched; under reduced motion a throw is a no-op, so nothing is fetched then
// either. The provider itself is a context and a counter: shell code, no package.

const Burst = lazyPart(
  () => import("../shared/Confetti"),
  (m) => m.Confetti,
  null,
);

export function ConfettiProvider({ children }: { children: ReactNode }) {
  // The burst raining now (its number, so the next one is a fresh mount), or null.
  const [burst, setBurst] = useState<number | null>(null);
  const thrown = useRef(0);
  const throwConfetti = useCallback(() => {
    if (prefersReducedMotion()) return;
    setBurst((b) => b ?? ++thrown.current);
  }, []);
  const done = useCallback(() => setBurst(null), []);
  return (
    <ConfettiContext.Provider value={throwConfetti}>
      {children}
      {burst !== null && <Burst key={burst} onDone={done} />}
    </ConfettiContext.Provider>
  );
}
