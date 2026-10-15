import { render, screen } from "@testing-library/react";
import { QuarterLine, quarterLineText, timeLeft } from "./QuarterLine";
import type { GrowthResponse, TrainingQuarter } from "./api.growth";

// The quarter's training line. The agent answers `trainingQuarter: null`
// when the active Space states no requirement, and the page then says nothing.
let growth: GrowthResponse | undefined;
jest.mock("./api.growth", () => ({
  useGetGrowthQuery: () => ({ data: growth }),
}));

const q = (over: Partial<TrainingQuarter> = {}): TrainingQuarter => ({
  quarter: "Q3 2026",
  hours: 6,
  required: 8,
  daysLeft: 14,
  planned: 0,
  ...over,
});

describe("the quarter line", () => {
  it("reads 'Q3: 6 of 8 hours, two weeks left'", () => {
    growth = { items: [], trainingQuarter: q() };
    render(<QuarterLine />);
    expect(screen.getByTestId("training-quarter").textContent).toBe(
      "Q3: 6 of 8 hours, two weeks left",
    );
  });

  it("adds planned hours only when there are some", () => {
    expect(quarterLineText(q({ planned: 4 }))).toBe("Q3: 6 of 8 hours, 4 planned, two weeks left");
    expect(quarterLineText(q({ planned: 0 }))).not.toContain("planned");
  });

  it("is absent when there is no requirement", () => {
    growth = { items: [], trainingQuarter: null };
    const { container } = render(<QuarterLine />);
    expect(container.textContent).toBe("");
    expect(screen.queryByTestId("training-quarter")).toBeNull();
  });

  it("is absent from an older agent that does not send the field", () => {
    growth = { items: [] };
    const { container } = render(<QuarterLine />);
    expect(container.textContent).toBe("");
  });

  it("says the time left in days inside two weeks and weeks after", () => {
    expect(timeLeft(0)).toBe("last day");
    expect(timeLeft(1)).toBe("1 day left");
    expect(timeLeft(9)).toBe("9 days left");
    expect(timeLeft(14)).toBe("two weeks left");
    expect(timeLeft(45)).toBe("six weeks left");
  });
});
