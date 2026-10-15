import { act, renderHook } from "@testing-library/react";
import { usePersistedState, useLocalPersistedState } from "./usePersistedState";

// The bug this hook fixes: DeckCollection's page + filter state lived in a
// plain useState, so navigating to a deck's details page and back (a real
// unmount/remount — see routes.ts's navigateBack) threw it away. This pins
// the two things that actually matter for that fix: a fresh mount picks up
// what a previous mount wrote (survives unmount), and a bad/absent stored
// value degrades to the fallback rather than throwing (same rule as the
// localStorage-backed usePersistedFlag/usePersistedValue pair above it).

interface CollectionState {
  page: number;
  activeTags: string[];
}

const DEFAULT: CollectionState = { page: 0, activeTags: [] };

describe("usePersistedState", () => {
  const KEY = "wasteland:collection-state:test";

  beforeEach(() => {
    window.sessionStorage.clear();
  });

  it("starts at the fallback when nothing is stored", () => {
    const { result } = renderHook(() => usePersistedState<CollectionState>(KEY, DEFAULT));
    expect(result.current.value).toEqual(DEFAULT);
  });

  it("survives a remount — the whole point of choosing this over useState", () => {
    const { result, unmount } = renderHook(() => usePersistedState<CollectionState>(KEY, DEFAULT));

    act(() => {
      result.current.setValue({ page: 2, activeTags: ["css"] });
    });

    unmount();

    const { result: afterRemount } = renderHook(() =>
      usePersistedState<CollectionState>(KEY, DEFAULT),
    );
    expect(afterRemount.current.value).toEqual({ page: 2, activeTags: ["css"] });
  });

  it("falls back rather than throwing on a corrupt stored value", () => {
    window.sessionStorage.setItem(KEY, "{not json");
    const { result } = renderHook(() => usePersistedState<CollectionState>(KEY, DEFAULT));
    expect(result.current.value).toEqual(DEFAULT);
  });

  // isValid catches what JSON.parse alone can't: syntactically valid JSON in
  // the wrong shape, or a value that's since gone stale against current app
  // state (DeckCollection's real isValidCollectionState also checks a stored
  // tag still exists in DECKS — mirrored here with a plain allow-list so the
  // hook's own contract is pinned independent of that app-specific rule).
  describe("with an isValid guard", () => {
    const isValid = (v: unknown): v is CollectionState =>
      typeof v === "object" &&
      v !== null &&
      typeof (v as CollectionState).page === "number" &&
      Array.isArray((v as CollectionState).activeTags) &&
      (v as CollectionState).activeTags.every((t) => t === "css" || t === "azure");

    it("falls back to no filters, page 0 when the stored shape is wrong", () => {
      window.sessionStorage.setItem(KEY, JSON.stringify({ page: "two", activeTags: [] }));
      const { result } = renderHook(() =>
        usePersistedState<CollectionState>(KEY, DEFAULT, isValid),
      );
      expect(result.current.value).toEqual(DEFAULT);
    });

    it("falls back to no filters, page 0 when a stored tag no longer exists", () => {
      window.sessionStorage.setItem(
        KEY,
        JSON.stringify({ page: 2, activeTags: ["a-tag-that-was-removed"] }),
      );
      const { result } = renderHook(() =>
        usePersistedState<CollectionState>(KEY, DEFAULT, isValid),
      );
      expect(result.current.value).toEqual(DEFAULT);
    });

    it("keeps a valid stored value as-is", () => {
      window.sessionStorage.setItem(KEY, JSON.stringify({ page: 1, activeTags: ["azure"] }));
      const { result } = renderHook(() =>
        usePersistedState<CollectionState>(KEY, DEFAULT, isValid),
      );
      expect(result.current.value).toEqual({ page: 1, activeTags: ["azure"] });
    });
  });
});

// The localStorage half of the JSON pair. Same degrade-to-fallback contract as
// its session-scoped sibling above; the difference that earns its own tests is
// the updater-form setter, which exists because watch history is a
// read-modify-write over a map and the deck engine can record twice before a
// re-render.
describe("useLocalPersistedState", () => {
  const KEY = "test:local-json";
  interface Entry {
    seen: number;
  }
  type Store = Record<string, Entry>;
  const DEFAULT: Store = {};

  const isStore = (v: unknown): v is Store =>
    typeof v === "object" &&
    v !== null &&
    !Array.isArray(v) &&
    Object.values(v).every(
      (e) => typeof e === "object" && e !== null && typeof (e as Entry).seen === "number",
    );

  beforeEach(() => {
    window.localStorage.clear();
  });

  it("round-trips a value through localStorage, not sessionStorage", () => {
    const { result } = renderHook(() => useLocalPersistedState<Store>(KEY, DEFAULT));
    act(() => result.current.setValue({ a: { seen: 3 } }));

    expect(result.current.value).toEqual({ a: { seen: 3 } });
    expect(JSON.parse(window.localStorage.getItem(KEY) ?? "null")).toEqual({ a: { seen: 3 } });
    // The whole reason this hook exists beside usePersistedState: a device
    // preference must not live in a store the tab throws away.
    expect(window.sessionStorage.getItem(KEY)).toBeNull();
  });

  it("reads a previously stored value back on mount", () => {
    window.localStorage.setItem(KEY, JSON.stringify({ b: { seen: 1 } }));
    const { result } = renderHook(() => useLocalPersistedState<Store>(KEY, DEFAULT));
    expect(result.current.value).toEqual({ b: { seen: 1 } });
  });

  it("degrades to the fallback for an absent key, corrupt JSON, or a wrong shape", () => {
    const absent = renderHook(() => useLocalPersistedState<Store>(KEY, DEFAULT, isStore));
    expect(absent.result.current.value).toEqual(DEFAULT);

    window.localStorage.setItem(KEY, "{not json");
    const corrupt = renderHook(() => useLocalPersistedState<Store>(KEY, DEFAULT, isStore));
    expect(corrupt.result.current.value).toEqual(DEFAULT);

    // Valid JSON, wrong shape — what a stored value from an older format looks
    // like. JSON.parse can't catch this; isValid is the only thing that can.
    window.localStorage.setItem(KEY, JSON.stringify({ a: { seen: "lots" } }));
    const wrongShape = renderHook(() => useLocalPersistedState<Store>(KEY, DEFAULT, isStore));
    expect(wrongShape.result.current.value).toEqual(DEFAULT);
  });

  it("survives a localStorage that throws on access", () => {
    // Safari private mode and browsers with site data disabled THROW rather
    // than returning null. A module that forgot the try/catch takes the app
    // down at import time on those browsers.
    const real = Object.getOwnPropertyDescriptor(window, "localStorage");
    Object.defineProperty(window, "localStorage", {
      configurable: true,
      get() {
        throw new Error("SecurityError: storage disabled");
      },
    });

    try {
      const { result } = renderHook(() => useLocalPersistedState<Store>(KEY, DEFAULT));
      expect(result.current.value).toEqual(DEFAULT);
      // Writing is a no-op rather than a crash — the value still holds for
      // this session, which is strictly better than a white screen.
      expect(() => act(() => result.current.setValue({ a: { seen: 1 } }))).not.toThrow();
      expect(result.current.value).toEqual({ a: { seen: 1 } });
    } finally {
      if (real) Object.defineProperty(window, "localStorage", real);
    }
  });

  describe("the updater form", () => {
    it("hands the updater the current value and persists what it returns", () => {
      const { result } = renderHook(() => useLocalPersistedState<Store>(KEY, DEFAULT));
      act(() => result.current.setValue({ a: { seen: 1 } }));
      act(() => result.current.setValue((prev) => ({ ...prev, b: { seen: 2 } })));

      expect(result.current.value).toEqual({ a: { seen: 1 }, b: { seen: 2 } });
      expect(JSON.parse(window.localStorage.getItem(KEY) ?? "null")).toEqual({
        a: { seen: 1 },
        b: { seen: 2 },
      });
    });

    it("composes two updates in one batch instead of clobbering", () => {
      // THE case this form exists for. Two read-modify-writes landing before a
      // re-render: with a value-only setter both would close over the same
      // stale snapshot and the second would erase the first. This is exactly
      // the shape of the deck engine's deck-change double-record.
      const { result } = renderHook(() => useLocalPersistedState<Store>(KEY, DEFAULT));
      act(() => {
        result.current.setValue((prev) => ({ ...prev, a: { seen: 1 } }));
        result.current.setValue((prev) => ({ ...prev, b: { seen: 2 } }));
      });

      expect(result.current.value).toEqual({ a: { seen: 1 }, b: { seen: 2 } });
    });

    it("does not touch storage when the updater returns the same reference", () => {
      // A no-op upsert (watchHistory's totalSlides <= 0 guard returns the map
      // it was given) should not schedule a state change or a write.
      window.localStorage.setItem(KEY, JSON.stringify({ a: { seen: 1 } }));
      const { result } = renderHook(() => useLocalPersistedState<Store>(KEY, DEFAULT));
      window.localStorage.setItem(KEY, "SENTINEL");

      act(() => result.current.setValue((prev) => prev));

      expect(window.localStorage.getItem(KEY)).toBe("SENTINEL");
    });
  });
});
