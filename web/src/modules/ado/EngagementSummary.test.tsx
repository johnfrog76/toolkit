// The Space card's tiles as drawn (docs/SCENARIOS.md, "The Space summary's tiles, by the growth
// flag"; the model is summaryTiles.ts). Reviews are the growth module's work reviews: with growth
// off, or never configured, the card draws no Reviews tile -- not a 0 that reads as "no reviews".
const env = jest.fn();
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: env(), isLoading: false }),
}));
jest.mock("./api.ado", () => ({
  useGetEngagementSummaryQuery: () => ({
    data: {
      client: "Acme",
      role: "",
      startDate: "",
      endDate: "",
      projects: ["widgets"],
      stats: { daysBilled: 0, workItemsClosed: 4, reviewsGenerated: 0, prsReviewed: 0 },
    },
    isLoading: false,
  }),
}));

import { render, screen } from "@testing-library/react";
import { EngagementSummary } from "./EngagementSummary";

describe("the Space card's Reviews tile follows the growth flag", () => {
  it.each<[string, object, boolean]>([
    ["growth not configured", { features: {} }, false],
    ["growth off", { features: { growth: false } }, false],
    ["an agent that sent no features", {}, false],
    ["growth on", { features: { growth: true } }, true],
  ])("%s", (_why, e, shown) => {
    env.mockReturnValue(e);
    render(<EngagementSummary slug="acme" />);
    expect(screen.getByText("Items closed")).toBeTruthy();
    expect(screen.queryAllByText("Reviews")).toHaveLength(shown ? 1 : 0);
  });
});
