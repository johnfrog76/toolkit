import { render, screen } from "@testing-library/react";
import { TestHealth } from "./TestHealth";
import { countAxisWidth, countTicks } from "../../shared/formatCount";

// Test Health with this repository's own five-digit totals: every count grouped by the reader's
// locale -- tiles, halves, suite rows, the y-axis -- and the axis as wide as its widest label.
// Expected text is written with toLocaleString, so the rows hold in whatever locale runs them.

const half = (name: string, passed: number) => ({
  half: name,
  result: "pass",
  passed,
  failed: 0,
  skipped: 0,
  total: passed,
  seconds: 1,
  reason: "",
  timestamp: "",
});

const response = {
  machine: "PC",
  active_space: "toolkit",
  days: [
    {
      date: "2026-11-08",
      passed: 12661,
      total: 12661,
      suites: [
        {
          suite: "Compat",
          result: "pass",
          passed: 1730,
          total: 1730,
          detail: "ok",
          description: "",
        },
        { suite: "Consts", result: "pass", passed: 208, total: 208, detail: "ok", description: "" },
      ],
    },
  ],
  last_run: "2026-11-08T12:00:00",
  streak: 3,
  machines: [
    {
      machine: "PC",
      timestamp: "2026-11-08T12:00:00",
      suites: {},
      halves: { agent: half("agent", 1414), cli: half("cli", 9363), web: half("web", 1884) },
    },
  ],
};

jest.mock("recharts", () => {
  const passthrough = ({ children }: { children?: unknown }) => <div>{children as never}</div>;
  return {
    BarChart: passthrough,
    Bar: () => null,
    XAxis: () => null,
    YAxis: (p: { width: number; ticks: number[]; tickFormatter: (v: number) => string }) => (
      <div data-testid="y-axis" data-width={p.width}>
        {p.ticks.map((t) => (
          <span key={t}>{p.tickFormatter(t)}</span>
        ))}
      </div>
    ),
    Tooltip: () => null,
    ResponsiveContainer: passthrough,
  };
});
jest.mock("../../hooks/chartPalette", () => ({
  useChartColors: () => ({
    pass: "#0a0",
    fail: "#a00",
    warn: "#aa0",
    skip: "#888",
    grid: "#ccc",
    text: "#000",
  }),
}));
jest.mock("../../hooks/useWornTheme", () => ({ useWornTheme: () => ({ theme: "light" }) }));
jest.mock("./api.ado", () => ({
  useGetTestHistoryQuery: () => ({
    data: response,
    isLoading: false,
    isError: false,
    isFetching: false,
    refetch: jest.fn(),
  }),
  useRunCommandMutation: () => [jest.fn(), { isLoading: false }],
}));

const n = (v: number) => v.toLocaleString();

describe("Test Health's counts are grouped and its axis is wide enough", () => {
  it("groups the digits in the tiles, the halves and the suite rows", () => {
    render(<TestHealth />);
    expect(screen.getByText(`${n(12661)}/${n(12661)}`)).toBeTruthy();
    expect(screen.getByText(`${n(9363)}/${n(9363)}`)).toBeTruthy();
    expect(screen.getByText(`${n(1414)}/${n(1414)}`)).toBeTruthy();
    expect(screen.getByText(`${n(1884)}/${n(1884)}`)).toBeTruthy();
    expect(screen.getByText(`${n(1730)}/${n(1730)}`)).toBeTruthy();
    // Under 1,000, nothing changes.
    expect(screen.getByText("208/208")).toBeTruthy();
  });

  it("draws the y-axis ticks grouped, and wide enough for the widest", () => {
    render(<TestHealth />);
    const axis = screen.getByTestId("y-axis");
    expect(Array.from(axis.querySelectorAll("span")).map((s) => s.textContent)).toEqual(
      [0, 3500, 7000, 10500, 14000].map(n),
    );
    const width = Number(axis.getAttribute("data-width"));
    expect(width).toBeGreaterThan(30);
    expect(width).toBe(countAxisWidth(countTicks(12661), 10));
  });
});
