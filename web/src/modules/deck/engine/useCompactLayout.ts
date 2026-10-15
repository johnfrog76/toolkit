import { useEffect, useState } from "react";

// The mobile-first breakpoint scheme (the owner's): everything below 576px is the
// BASE — standard portrait phones, where the player stacks art above copy and
// the chrome grows thumb-sized targets. 576px and up (landscape phones,
// foldables, small tablets) keeps the authored side-by-side split; 768+ needs
// nothing extra today. One constant so the player and its chrome can't
// disagree about where "compact" begins.
export const COMPACT_MAX_WIDTH = 575;

const QUERY = `(max-width: ${COMPACT_MAX_WIDTH}px)`;

// Live matchMedia subscription — resize/rotate flips the layout without a
// reload (rotating a phone to landscape SHOULD restore the split view).
// Guarded for jsdom, where matchMedia doesn't exist: tests get `false`, the
// desktop layout every existing test asserts against.
export function useCompactLayout(): boolean {
  const [compact, setCompact] = useState(() => window.matchMedia?.(QUERY).matches ?? false);

  useEffect(() => {
    const mql = window.matchMedia?.(QUERY);
    if (!mql) return;
    const onChange = (e: MediaQueryListEvent) => setCompact(e.matches);
    mql.addEventListener("change", onChange);
    return () => mql.removeEventListener("change", onChange);
  }, []);

  return compact;
}
