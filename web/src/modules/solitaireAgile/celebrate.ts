// The once-per-thing rule behind a celebration (D-AR14; docs/modules/solitaire-agile.md,
// "The PM Corner: the line, the chevron, the confetti"). Generic on purpose: the Team
// Agile page fires it for a milestone reached, and any other surface that celebrates
// something reached -- a shelf filled, a milestone in another world -- calls the same
// rule with its own storage key and its own ids. Pure but for the seen mark, and kept
// out of Confetti.tsx so a test can read the rule without loading a canvas.
//
// The mark is a per-viewer convenience in this browser's localStorage: it can be empty,
// refused or throwing (a private window, site data off), so every read and write is
// wrapped, and a refusal falls back to this page's memory -- the celebration then holds
// for the page's life instead of forever, and nothing breaks.

/**
 * Whether to celebrate now. `active`: the thing is reached. `wasActive`: what this
 * mount last saw for the SAME id -- `null` when this is its first sight (a fresh page,
 * a reload, a different id). `seen`: the browser's mark for the id.
 *
 * - a transition to reached while the page watched fires, mark or no mark;
 * - a first sight of something already reached fires only when the mark is absent;
 * - never otherwise -- so a reload of a finished milestone does not celebrate again.
 */
export function shouldCelebrate(state: {
  active: boolean;
  wasActive: boolean | null;
  seen: boolean;
}): boolean {
  if (!state.active) return false;
  if (state.wasActive === false) return true;
  if (state.wasActive === true) return false;
  return !state.seen;
}

// What holds when storage will not: this page's memory, per key.
const memory = new Map<string, Set<string>>();

function read(key: string): Set<string> {
  try {
    const raw = window.localStorage?.getItem(key);
    if (raw) {
      const list = JSON.parse(raw) as unknown;
      if (Array.isArray(list))
        return new Set(list.filter((x): x is string => typeof x === "string"));
    }
  } catch {
    // Unreadable or refused: fall through to this page's memory.
  }
  return new Set(memory.get(key) ?? []);
}

/** Whether the id carries the mark under this key. Never throws. */
export function hasSeen(key: string, id: string): boolean {
  return read(key).has(id) || (memory.get(key)?.has(id) ?? false);
}

/** Set the mark for the id under this key. Never throws. */
export function markSeen(key: string, id: string): void {
  const next = read(key);
  next.add(id);
  memory.set(key, new Set(next));
  try {
    window.localStorage?.setItem(key, JSON.stringify([...next]));
  } catch {
    // Private mode / storage disabled / quota: this page's memory holds it.
  }
}

/** Forget this page's memory -- for the tests. */
export function resetCelebrateMemory(): void {
  memory.clear();
}
