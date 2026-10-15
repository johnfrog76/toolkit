import { render, screen } from "@testing-library/react";
import { TestHealth } from "./TestHealth";

// The card's Space badge reads `active_space`, the name the route serves
// since the Space rename. It read `active_org`, which never arrives, so the
// badge and the foot's "in the X Space" were never drawn.

const response = {
  machine: "PC",
  active_space: "toolkit",
  days: [
    {
      date: "2026-10-06",
      passed: 10,
      total: 10,
      suites: [
        { suite: "Menu", result: "pass", passed: 10, total: 10, detail: "ok", description: "" },
      ],
    },
  ],
  last_run: "2026-10-06T12:00:00",
  streak: 3,
  machines: [
    {
      machine: "PC",
      timestamp: "2026-10-06T12:00:00",
      suites: {},
      halves: {
        cli: {
          half: "cli",
          result: "pass",
          passed: 10,
          failed: 0,
          skipped: 0,
          total: 10,
          seconds: 1,
          reason: "",
          timestamp: "",
        },
      },
    },
  ],
};

jest.mock("recharts", () => {
  const passthrough = ({ children }: { children?: unknown }) => <div>{children as never}</div>;
  return {
    BarChart: passthrough,
    Bar: () => null,
    XAxis: () => null,
    YAxis: () => null,
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

describe("TestHealth's Space badge", () => {
  it("shows the Space the route names in active_space", () => {
    render(<TestHealth />);
    expect(screen.getByTitle("The Space the last run was in: toolkit").textContent).toBe("toolkit");
    expect(screen.getByText(/in the toolkit Space/)).toBeTruthy();
  });
});
