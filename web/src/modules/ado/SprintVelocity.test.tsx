import { render, screen } from "@testing-library/react";
import { SprintVelocity } from "./SprintVelocity";
import type { SprintVelocitySnapshot } from "./SprintVelocity";
import type { StressContext } from "./api.ado";

jest.mock("./api.ado", () => ({
  useGetStressStatusQuery: () => ({}),
  useGetSprintActivityQuery: () => ({}),
  useGetStressReposQuery: () => ({}),
}));
jest.mock("./SprintDailyChart", () => ({ SprintDailyChart: () => null }));
jest.mock("./SprintDayScatterChart", () => ({ SprintDayScatterChart: () => null }));

const e = (date: string, count: number) => ({ date, count, churn: 0 });

const CTX: StressContext = {
  sprintName: "S1",
  sprintFullName: "S1",
  daysRemaining: 9,
  mergeVelocity: 12,
  upstreamMerges: 14,
  surfaceAreaChange: 0,
  rebasePressure: "Low",
  conflictZones: [],
  prBroadcasted: false,
  visibilityScore: 0.5,
  updateCadence: "Normal",
};

function snapshot(ctx: Partial<StressContext>, over: Partial<SprintVelocitySnapshot> = {}) {
  return {
    repos: { repos: [], defaultRepo: null },
    status: {
      enabled: true,
      org: "o",
      detail: "ok",
      generatedAt: "2026-03-04T10:00:00Z",
      sourceRepo: null,
      sprintSource: null,
      context: { ...CTX, ...ctx },
      sprintStress: null,
      originStress: null,
      communicationStress: null,
      teamDynamicsStress: null,
    },
    activity: {
      startDate: "2026-03-02",
      endDate: "2026-03-08",
      mine: [e("2026-03-02", 2), e("2026-03-04", 0)],
      team: [e("2026-03-02", 5), e("2026-03-04", 0)],
    },
    asOf: "2026-03-08",
    ...over,
  } as SprintVelocitySnapshot;
}

// The danger colour is for a failure; a count is information.
const DANGER = /colorPaletteRedForeground1|var\(--colorPaletteRedForeground1\)/;
const dangerSpans = (c: HTMLElement) =>
  Array.from(c.querySelectorAll<HTMLElement>("[data-stat-tile] span")).filter((s) =>
    DANGER.test(s.getAttribute("style") ?? ""),
  );

describe("SprintVelocity tiles", () => {
  it("labels the team count for what it counts", () => {
    render(<SprintVelocity snapshot={snapshot({})} />);
    expect(screen.getByText("team commits")).toBeTruthy();
    expect(screen.getByText("my commits")).toBeTruthy();
    expect(screen.queryByText("merges")).toBeNull();
  });

  it("draws a busy week and a few days left without the danger colour", () => {
    const busy = render(
      <SprintVelocity snapshot={snapshot({ mergeVelocity: 30, upstreamMerges: 40 })} />,
    );
    expect(dangerSpans(busy.container)).toHaveLength(0);
    busy.unmount();
    const late = render(<SprintVelocity snapshot={snapshot({ daysRemaining: 1 })} />);
    expect(dangerSpans(late.container)).toHaveLength(0);
  });

  it("draws no countdown tile when the days remaining are not known", () => {
    render(<SprintVelocity snapshot={snapshot({ daysRemaining: null })} />);
    expect(screen.queryByText("days left")).toBeNull();
    expect(screen.queryByText(/^0$/)).toBeNull();
  });

  it("counts the days elapsed on the calendar, active days out of them", () => {
    // 2026-03-02 is a Monday; the window to Sunday the 8th has elapsed in full.
    render(<SprintVelocity snapshot={snapshot({})} />);
    expect(screen.getByText("1/7")).toBeTruthy();
  });

  it("names the last recorded day in the footer, whatever its count", () => {
    render(
      <SprintVelocity
        snapshot={snapshot(
          {},
          { status: { ...snapshot({}).status, detail: "none", generatedAt: null } },
        )}
      />,
    );
    expect(screen.getByText(/Recorded as of 03\/04\/2026/)).toBeTruthy();
  });
});
