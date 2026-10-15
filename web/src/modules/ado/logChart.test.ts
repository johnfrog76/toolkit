import { buildChartData, logBadge } from "./logChart";
import type { LogEntry } from "./api.ado";

const entry = (timestamp: string, type: string): LogEntry => ({
  timestamp,
  type,
  machine: "mac",
  source: "Status",
  detail: "",
});

describe("buildChartData", () => {
  it("puts the oldest day on the left whatever order the entries arrive in", () => {
    // The agent serves newest first; Health beside this chart runs oldest-left.
    const rows = buildChartData([
      entry("2026-09-22T10:00:00", "CMD"),
      entry("2026-09-20T10:00:00", "ERR"),
      entry("2026-09-21T10:00:00", "CMD"),
      entry("2026-09-22T11:00:00", "WARN"),
    ]);
    expect(rows.map((r) => r.label)).toEqual(["Sun 20", "Mon 21", "Tue 22"]);
    expect(rows[2]).toMatchObject({ CMD: 1, WARN: 1, ERR: 0, INFO: 0 });
    expect(rows[0]).toMatchObject({ ERR: 1 });
  });

  it("is empty for no entries", () => {
    expect(buildChartData([])).toEqual([]);
  });
});

describe("logBadge", () => {
  it("says a count when the answer was not cut, or when a filter narrowed it", () => {
    expect(logBadge(37, 37, 500)).toBe("37");
    expect(logBadge(12, 500, 500)).toBe("12");
  });

  it("says 'latest N' when the agent's answer was cut at the cap and nothing narrows it", () => {
    expect(logBadge(500, 500, 500)).toBe("latest 500");
  });
});
