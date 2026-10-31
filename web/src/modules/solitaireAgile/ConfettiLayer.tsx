import { useEffect, useState } from "react";
import { lazyPart } from "../../shell/lazy";
import { onConfetti } from "./useConfetti";

// The ONE place confetti is mounted (D-AR14; docs/modules/solitaire-agile.md,
// "Milestones: the tab and the award"): the module's root overlay, contributed through
// the registry's `overlays` and drawn by the shell after everything else, so a burst
// covers the whole viewport whatever page or dialog threw it. It draws nothing until a
// burst is thrown through useConfetti(), and the confetti component -- with the
// `react-confetti` package behind it -- is a chunk of its own, fetched the first time
// something throws, never at load.

const Confetti = lazyPart(
  () => import("./Confetti"),
  (m) => m.Confetti,
  null,
);

export function ConfettiLayer() {
  // The burst being drawn, numbered so a second throw is a burst of its own; 0 is none.
  const [burst, setBurst] = useState(0);
  useEffect(() => onConfetti(() => setBurst((b) => b + 1)), []);
  if (burst === 0) return null;
  return <Confetti key={burst} onDone={() => setBurst((b) => (b === burst ? 0 : b))} />;
}
