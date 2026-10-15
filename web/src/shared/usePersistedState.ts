import { useCallback, useState, useSyncExternalStore } from "react";

// One place that knows how a browser preference is stored.
//
// Every persisted setting in these apps had been hand-rolling the same three
// things: read at mount with a typeof-window guard, write on change, and
// (sometimes) catch the exception. "Sometimes" is why this exists — Safari in
// private mode and browsers with site data disabled THROW on localStorage
// access rather than returning null, and a module that forgot the try/catch
// takes the whole app down at import time on those browsers. Centralizing the
// access means a setting can't be written without that protection.
//
// Deliberately NOT a store, a context, or a sync layer. It's useState that
// happens to survive a reload: each caller still owns its own key, its own
// default, and any rules about how its value relates to another's (see
// voicePreference.tsx, where Suitcase Mode and narration are coupled). Putting
// those rules here would make one module the place every unrelated setting
// goes to argue.
//
// A shared value that stops being true when something else changes is forgotten
// with clearPersisted(keys); the Docs and Design filters are cleared that way on
// a Space switch (shell/filtersSlice.ts).

/** Never throws. A browser that refuses storage reads as "nothing stored". */
function readRaw(key: string): string | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage?.getItem(key) ?? null;
  } catch {
    return null;
  }
}

/** Never throws. Failing to persist is survivable — the value still holds
 *  for this session, which is strictly better than crashing the render. */
function writeRaw(key: string, value: string): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage?.setItem(key, value);
  } catch {
    // Private mode / storage disabled / quota. Session-only is fine.
  }
}

/**
 * A boolean setting remembered per browser, stored as "1" / "0".
 *
 * Returns the same shape as useState, plus a `toggle` for the common switch
 * case. Anything absent or unparseable reads as `fallback`, so a key that was
 * never written and a browser that refuses storage behave identically.
 */
export function usePersistedFlag(
  key: string,
  fallback = false,
): {
  value: boolean;
  setValue: (next: boolean) => void;
  toggle: () => void;
} {
  const [value, setLocal] = useState(() => {
    const raw = readRaw(key);
    return raw === null ? fallback : raw === "1";
  });

  const setValue = useCallback(
    (next: boolean) => {
      setLocal(next);
      writeRaw(key, next ? "1" : "0");
    },
    [key],
  );

  // Reads through the setter rather than closing over `value`, so a caller
  // can hand this to an onChange without it going stale between renders.
  const toggle = useCallback(() => {
    setLocal((cur) => {
      writeRaw(key, cur ? "0" : "1");
      return !cur;
    });
  }, [key]);

  return { value, setValue, toggle };
}

/**
 * A string setting remembered per browser (PresenterNotes' selected voice).
 *
 * `isValid` guards what comes back out: stored values outlive the code that
 * wrote them, so a voice id that has since been removed must not be handed to
 * a caller that assumes it still exists.
 */
export function usePersistedValue(
  key: string,
  fallback: string,
  isValid?: (stored: string) => boolean,
): {
  value: string;
  setValue: (next: string) => void;
} {
  const [value, setLocal] = useState(() => {
    const raw = readRaw(key);
    if (raw === null) return fallback;
    return !isValid || isValid(raw) ? raw : fallback;
  });

  const setValue = useCallback(
    (next: string) => {
      setLocal(next);
      writeRaw(key, next);
    },
    [key],
  );

  return { value, setValue };
}

// ---------------------------------------------------------------------------
// ONE value, TWO places on screen. usePersistedValue is useState that survives
// a reload, so two components holding the same key each hold their own copy
// and never hear the other's change. The Issues tab's filters live in the
// filter drawer AND are read by the list under it -- one choice, two
// readers -- so this variant keeps the value in the browser's storage and
// tells every holder of the key when it changes (useSyncExternalStore). Still
// not a store of settings: each caller owns its key, default and validity.
const sharedListeners = new Map<string, Set<() => void>>();
// Where a value lives for the session when the browser refuses storage.
const sharedMemory = new Map<string, string>();

/** Never throws; true when the browser kept it. */
function writeRawKept(key: string, value: string): boolean {
  if (typeof window === "undefined") return false;
  try {
    if (!window.localStorage) return false;
    window.localStorage.setItem(key, value);
    return true;
  } catch {
    return false;
  }
}

/**
 * A string setting remembered per browser AND shared by every component that
 * holds the same key: a change in one re-renders the others. Same contract as
 * usePersistedValue -- absent or invalid reads as `fallback`, never throws.
 */
export function useSharedPersistedValue(
  key: string,
  fallback: string,
  isValid?: (stored: string) => boolean,
): {
  value: string;
  setValue: (next: string) => void;
} {
  const subscribe = useCallback(
    (onChange: () => void) => {
      let set = sharedListeners.get(key);
      if (!set) {
        set = new Set();
        sharedListeners.set(key, set);
      }
      set.add(onChange);
      return () => {
        set.delete(onChange);
      };
    },
    [key],
  );
  const read = () => {
    const raw = readRaw(key) ?? sharedMemory.get(key) ?? null;
    if (raw === null) return fallback;
    return !isValid || isValid(raw) ? raw : fallback;
  };
  const value = useSyncExternalStore(subscribe, read, read);
  const setValue = useCallback(
    (next: string) => {
      if (writeRawKept(key, next)) sharedMemory.delete(key);
      else sharedMemory.set(key, next);
      sharedListeners.get(key)?.forEach((l) => l());
    },
    [key],
  );
  return { value, setValue };
}

/**
 * Forget shared values (useSharedPersistedValue keys): storage, the session
 * fallback, and every holder, which re-renders on its fallback. Never throws.
 * For a value that stops being true when something else changes (the Docs and
 * Design filters on a Space switch). Same storage, not a second mechanism.
 */
export function clearPersisted(keys: readonly string[]): void {
  for (const key of keys) {
    sharedMemory.delete(key);
    if (typeof window !== "undefined") {
      try {
        window.localStorage?.removeItem(key);
      } catch {
        // Storage refused: nothing was kept to forget.
      }
    }
    sharedListeners.get(key)?.forEach((l) => l());
  }
}

/** Escape hatch for read-once-at-module-scope callers that aren't hooks.
 *  Same guarantees: never throws, absent reads as the fallback. */
export function readPersistedFlag(key: string, fallback = false): boolean {
  const raw = readRaw(key);
  return raw === null ? fallback : raw === "1";
}

/** Never throws. A browser that refuses storage reads as "nothing stored". */
function readSessionRaw(key: string): string | null {
  if (typeof window === "undefined") return null;
  try {
    return window.sessionStorage?.getItem(key) ?? null;
  } catch {
    return null;
  }
}

/** Never throws. Failing to persist is survivable — the value still holds
 *  for this render, which is strictly better than crashing. */
function writeSessionRaw(key: string, value: string): void {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage?.setItem(key, value);
  } catch {
    // Private mode / storage disabled / quota. In-memory-only is fine.
  }
}

/**
 * An arbitrary JSON-serializable value remembered for the TAB's session, not
 * the browser. Where usePersistedFlag/usePersistedValue answer "what did this
 * visitor choose, forever" (localStorage — a device preference), this answers
 * "what was this visit doing a moment ago" (sessionStorage — browsing state:
 * a collection's current page and filters, not a setting anyone "chose").
 * Closing the tab is the correct time to forget it; a device preference is
 * not.
 *
 * A stored value that fails to parse (corrupt JSON, or a shape from a code
 * version that's since changed) reads as absent rather than throwing — same
 * rule as the localStorage pair: a bad stored value degrades to the
 * fallback, it never crashes the render.
 *
 * `isValid` catches what JSON.parse can't: valid JSON in the wrong shape
 * (fields renamed/retyped since the value was written), or a value that
 * parses fine but no longer makes sense against current app state (e.g. a
 * stored tag filter naming a tag that doesn't exist anymore). Same contract
 * as usePersistedValue's isValid above — reject and fall back, don't throw.
 */
export function usePersistedState<T>(
  key: string,
  fallback: T,
  isValid?: (value: unknown) => value is T,
): {
  value: T;
  setValue: (next: T) => void;
} {
  const [value, setLocal] = useState<T>(() => {
    const raw = readSessionRaw(key);
    if (raw === null) return fallback;
    try {
      const parsed: unknown = JSON.parse(raw);
      return !isValid || isValid(parsed) ? (parsed as T) : fallback;
    } catch {
      return fallback;
    }
  });

  const setValue = useCallback(
    (next: T) => {
      setLocal(next);
      writeSessionRaw(key, JSON.stringify(next));
    },
    [key],
  );

  return { value, setValue };
}

/**
 * An arbitrary JSON-serializable value remembered per BROWSER, not per tab.
 *
 * The localStorage half of the pair above. Same JSON round-trip, same
 * degrade-to-fallback rules, same `isValid` contract — the only difference is
 * which storage it lands in, and that difference is the whole decision: this
 * is for a device preference that must survive closing the tab ("which decks
 * have I watched"), where usePersistedState is for browsing state that
 * shouldn't ("what page was this collection on").
 *
 * ONE deliberate difference from its sibling: `setValue` also takes an updater
 * function, the way useState's setter does. The sibling's value-only setter
 * forces a caller to close over the current value, which is wrong for a
 * read-modify-write over a map — two calls landing before a re-render would
 * have the second overwrite the first from a stale snapshot. Watch history is
 * exactly that shape (see wasteland/src/watchHistory.tsx: the deck-change path
 * in useDeckController can record twice in a row), so the updater form is what
 * makes its upsert correct by construction. The write happens INSIDE the state
 * updater, so what lands in storage is always what was just computed, never a
 * snapshot from the render that scheduled it.
 */
export function useLocalPersistedState<T>(
  key: string,
  fallback: T,
  isValid?: (value: unknown) => value is T,
): {
  value: T;
  setValue: (next: T | ((prev: T) => T)) => void;
} {
  const [value, setLocal] = useState<T>(() => {
    const raw = readRaw(key);
    if (raw === null) return fallback;
    try {
      const parsed: unknown = JSON.parse(raw);
      return !isValid || isValid(parsed) ? (parsed as T) : fallback;
    } catch {
      return fallback;
    }
  });

  const setValue = useCallback(
    (next: T | ((prev: T) => T)) => {
      setLocal((prev) => {
        const resolved = typeof next === "function" ? (next as (p: T) => T)(prev) : next;
        // Skipping the write when the updater returned the same reference
        // keeps a no-op upsert (see watchHistory's totalSlides <= 0 guard)
        // from touching storage at all.
        if (resolved !== prev) writeRaw(key, JSON.stringify(resolved));
        return resolved;
      });
    },
    [key],
  );

  return { value, setValue };
}
