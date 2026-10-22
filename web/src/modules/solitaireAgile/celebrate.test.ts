import { hasSeen, markSeen, resetCelebrateMemory, shouldCelebrate } from "./celebrate";

// The once-per-thing rule behind the confetti (D-AR14): a table, one row per input the
// rule distinguishes, and the seen mark's storage falling back to memory.

describe("shouldCelebrate", () => {
  const rows: [string, { active: boolean; wasActive: boolean | null; seen: boolean }, boolean][] = [
    ["not reached: never", { active: false, wasActive: null, seen: false }, false],
    ["not reached, was reached: never", { active: false, wasActive: true, seen: false }, false],
    ["first sight, reached, no mark: once", { active: true, wasActive: null, seen: false }, true],
    ["first sight, reached, the mark set (a reload): never", { active: true, wasActive: null, seen: true }, false],
    ["the transition while watching, no mark: once", { active: true, wasActive: false, seen: false }, true],
    ["the transition while watching, the mark set: once", { active: true, wasActive: false, seen: true }, true],
    ["already reached and still reached: never again", { active: true, wasActive: true, seen: false }, false],
  ];
  it.each(rows)("%s", (_name, state, want) => {
    expect(shouldCelebrate(state)).toBe(want);
  });
});

describe("the seen mark", () => {
  const KEY = "p20.test.celebrate";
  beforeEach(() => {
    localStorage.clear();
    resetCelebrateMemory();
  });

  it("is kept by id under its key, in localStorage", () => {
    expect(hasSeen(KEY, "widgets:B")).toBe(false);
    markSeen(KEY, "widgets:B");
    expect(hasSeen(KEY, "widgets:B")).toBe(true);
    expect(hasSeen(KEY, "widgets:C")).toBe(false);
    expect(JSON.parse(localStorage.getItem(KEY) ?? "[]")).toEqual(["widgets:B"]);
  });

  it("holds in this page's memory when storage throws, and never throws itself", () => {
    const get = jest.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("denied");
    });
    const set = jest.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("denied");
    });
    try {
      expect(hasSeen(KEY, "widgets:B")).toBe(false);
      expect(() => markSeen(KEY, "widgets:B")).not.toThrow();
      expect(hasSeen(KEY, "widgets:B")).toBe(true);
    } finally {
      get.mockRestore();
      set.mockRestore();
    }
  });

  it("reads an unreadable entry as nothing seen", () => {
    localStorage.setItem(KEY, "{not json");
    expect(hasSeen(KEY, "widgets:B")).toBe(false);
  });
});
