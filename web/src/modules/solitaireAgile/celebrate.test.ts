import { hasSeen, markSeen, resetCelebrateMemory } from "./celebrate";

// The once-per-thing mark behind the award (D-AR14): the seen mark's storage, and its
// fallback to memory when the browser refuses it.

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
