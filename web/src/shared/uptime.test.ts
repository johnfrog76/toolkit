import { uptimeWords } from "./uptime";

describe("uptimeWords", () => {
  it("says it in the two units a person reads", () => {
    expect(uptimeWords(42)).toBe("42s");
    expect(uptimeWords(60 * 7)).toBe("7m");
    expect(uptimeWords(3600 * 3 + 60 * 5)).toBe("3h 5m");
    expect(uptimeWords(377560)).toBe("4d 8h");
  });
});
