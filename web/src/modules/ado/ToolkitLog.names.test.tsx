import { render, screen } from "@testing-library/react";
import { ToolkitLog } from "./ToolkitLog";

// The Log card's two filters are native <select>s with no visible label,
// and axe's select-name (critical) found them nameless on the System page. A
// screen reader announces each by its aria-label, so the names are a contract.

jest.mock("recharts", () => {
  const passthrough = ({ children }: { children?: unknown }) => <div>{children as never}</div>;
  return {
    AreaChart: passthrough,
    Area: () => null,
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
  LOG_LATEST: 500,
  useGetLogEntriesQuery: () => ({
    data: {
      count: 1,
      entries: [
        {
          timestamp: "2026-10-07 09:00:00",
          type: "CMD",
          machine: "PC",
          source: "Status",
          detail: "ok",
        },
      ],
    },
    isLoading: false,
    isFetching: false,
    error: undefined,
    refetch: jest.fn(),
  }),
  useRunCommandMutation: () => [jest.fn()],
}));

describe("ToolkitLog's filters", () => {
  it("names the type and period selects", () => {
    render(<ToolkitLog />);
    expect(screen.getByRole("combobox", { name: "Entry type" })).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "Period" })).toBeTruthy();
  });
});
