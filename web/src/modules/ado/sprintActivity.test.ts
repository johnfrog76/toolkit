import { buildSprintBars, lastRecordedDay } from "./sprintActivity";

const e = (date: string, count: number) => ({ date, count, churn: 0 });

describe("buildSprintBars", () => {
  const mine = [e("2026-03-02", 2), e("2026-03-03", 0), e("2026-03-04", 3)];
  const team = [e("2026-03-02", 5), e("2026-03-03", 1), e("2026-03-04", 3)];

  it("draws each bar's total as the team's count, mine being part of it", () => {
    const bars = buildSprintBars("2026-03-02", "2026-03-05", mine, team);
    expect(bars).toHaveLength(4);
    for (const b of bars) expect(b.mine + b.rest).toBe(b.team);
    expect(bars.map((b) => b.rest)).toEqual([3, 1, 0, 0]);
    expect(bars.map((b) => b.team)).toEqual([5, 1, 3, 0]);
  });

  it("never lets the rest go below zero when a record has mine above team", () => {
    const bars = buildSprintBars(
      "2026-03-02",
      "2026-03-02",
      [e("2026-03-02", 4)],
      [e("2026-03-02", 3)],
    );
    expect(bars[0].rest).toBe(0);
  });
});

describe("lastRecordedDay", () => {
  it("is the last recorded day even when its count is zero", () => {
    expect(
      lastRecordedDay(
        [e("2026-03-02", 2), e("2026-03-04", 0)],
        [e("2026-03-03", 1), e("2026-03-04", 0)],
      ),
    ).toBe("2026-03-04");
  });
  it("is null with no record", () => {
    expect(lastRecordedDay([], [])).toBeNull();
  });
});
