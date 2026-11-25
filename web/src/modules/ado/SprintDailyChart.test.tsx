import { render, screen } from "@testing-library/react";
import {
  ChartTooltipContent,
  SPRINT_CHART_DESCRIPTION,
  SprintDailyChart,
} from "./SprintDailyChart";
import type { SprintBar } from "./sprintActivity";

jest.mock("../../hooks/chartPalette", () => ({
  useChartColors: () => ({ billingBar: "#111", billingAvg: "#222" }),
}));
jest.mock("../../hooks/useWornTheme", () => ({ useWornTheme: () => ({ theme: "light" }) }));
// The chart library draws nothing in jsdom, so the stand-ins record what the
// component hands it: the data rows, and each Bar's key and stack.
const drawn: {
  data: Array<Record<string, number>>;
  bars: Array<{ dataKey: string; stackId: string }>;
} = {
  data: [],
  bars: [],
};
jest.mock("recharts", () => ({
  BarChart: ({ data, children }: { data: Array<Record<string, number>>; children?: unknown }) => {
    drawn.data = data;
    drawn.bars = [];
    return <div>{children as never}</div>;
  },
  Bar: (p: { dataKey: string; stackId: string }) => {
    drawn.bars.push({ dataKey: p.dataKey, stackId: p.stackId });
    return null;
  },
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: () => null,
  ResponsiveContainer: ({ children }: { children?: unknown }) => <div>{children as never}</div>,
}));
jest.mock("./api.ado", () => ({ useGetSprintActivityQuery: () => ({}) }));

const bar: SprintBar = { date: "2026-03-02", label: "Mon 2", mine: 2, team: 5, rest: 3 };

describe("SprintDailyChart", () => {
  it("states mine and the team's total as the record has them", () => {
    render(<ChartTooltipContent active payload={[{ payload: bar }]} />);
    expect(screen.getByText("Mine: 2 commits")).toBeTruthy();
    expect(screen.getByText("Team: 5 commits")).toBeTruthy();
  });

  it("describes what it draws", () => {
    render(
      <SprintDailyChart
        activityOverride={{ startDate: "2026-03-02", endDate: "2026-03-03", mine: [], team: [] }}
      />,
    );
    expect(screen.getByRole("img", { name: SPRINT_CHART_DESCRIPTION })).toBeTruthy();
    expect(SPRINT_CHART_DESCRIPTION).toMatch(/team commits.*my commits.*rest of the team/);
  });

  it("stacks mine and the rest, and each stack stands at the team's count", () => {
    const e = (date: string, count: number) => ({ date, count, churn: 0 });
    render(
      <SprintDailyChart
        activityOverride={{
          startDate: "2026-03-02",
          endDate: "2026-03-04",
          mine: [e("2026-03-02", 2), e("2026-03-03", 5)],
          team: [e("2026-03-02", 5), e("2026-03-03", 3)],
        }}
      />,
    );
    expect(drawn.bars.map((b) => b.dataKey)).toEqual(["drawnMine", "rest"]);
    expect(new Set(drawn.bars.map((b) => b.stackId)).size).toBe(1);
    const [keyA, keyB] = drawn.bars.map((b) => b.dataKey);
    // Mine above team on the second day: the stack is still the team's height.
    expect(drawn.data.map((r) => r[keyA] + r[keyB])).toEqual([5, 3, 0]);
  });
});
