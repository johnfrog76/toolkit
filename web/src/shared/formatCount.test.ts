import { countAxisWidth, countTicks, formatCount, formatRatio } from "./formatCount";

// Test Health's counts (formatCount.ts): exact, grouped by the reader's locale, and an axis wide
// enough for its widest label.
describe("formatCount: exact, with the locale's grouping", () => {
  it.each<[number, string, string]>([
    [12661, "en-US", "12,661"],
    [14000, "en-US", "14,000"],
    [999, "en-US", "999"],
    [0, "en-US", "0"],
    [12661, "de-DE", "12.661"],
  ])("%d in %s reads %s", (n, locale, text) => {
    expect(formatCount(n, locale)).toBe(text);
  });

  it("keeps a single failure visible in a large total", () => {
    expect(formatRatio(12660, 12661, "en-US")).toBe("12,660/12,661");
  });

  it("leaves a total under 1,000 as it was", () => {
    expect(formatRatio(10, 10, "en-US")).toBe("10/10");
  });
});

describe("countTicks: from 0, in round steps that hold the max", () => {
  it.each<[number, number[]]>([
    [12661, [0, 3500, 7000, 10500, 14000]],
    [9363, [0, 2500, 5000, 7500, 10000]],
    [1884, [0, 500, 1000, 1500, 2000]],
    [100, [0, 25, 50, 75, 100]],
    [10, [0, 3, 6, 9, 12]],
    [3, [0, 1, 2, 3, 4]],
    [0, [0, 1, 2, 3, 4]],
  ])("a max of %d", (max, ticks) => {
    const got = countTicks(max);
    expect(got).toEqual(ticks);
    expect(got[got.length - 1]).toBeGreaterThanOrEqual(max);
  });
});

describe("countAxisWidth: the widest label is drawn whole", () => {
  it("is wider for 14,000 than the 30px that cut it to 4000", () => {
    const ticks = countTicks(12661);
    const width = countAxisWidth(ticks, 10, "en-US");
    // Five digits and a comma at 10px, plus the tick's offset.
    expect(width).toBeGreaterThan(30);
    expect(width).toBeGreaterThanOrEqual(Math.ceil(5 * 6.2 + 3.5 + 12));
  });

  it("grows with the label and not with the count of ticks", () => {
    const small = countAxisWidth(countTicks(100), 10, "en-US");
    const large = countAxisWidth(countTicks(12661), 10, "en-US");
    expect(large).toBeGreaterThan(small);
    expect(countAxisWidth([0, 14000], 10, "en-US")).toBe(large);
  });
});
