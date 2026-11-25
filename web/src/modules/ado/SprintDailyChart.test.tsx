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
});
