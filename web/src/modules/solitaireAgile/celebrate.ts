// The once-per-thing mark behind a celebration (D-AR14; docs/modules/solitaire-agile.md,
// "Milestones: the tab and the award"). Generic on purpose: the Milestones tab's award
// marks a milestone it has congratulated (award.ts), and any other surface that
// celebrates something reached -- a shelf filled, a milestone in another world -- keeps
// its own storage key and its own ids here. Kept out of Confetti.tsx so a test can
// read it without loading a canvas.
//
// The mark is a per-viewer convenience in this browser's localStorage: it can be empty,
// refused or throwing (a private window, site data off), so every read and write is
// wrapped, and a refusal falls back to this page's memory -- the celebration then holds
// for the page's life instead of forever, and nothing breaks.

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
