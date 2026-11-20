import { listPageSize } from "../../shell/pageSize";
import { leadChartPlotHeightPx, logChartPlotHeightPx } from "../../shell/layoutTokens";

describe("the Log card's page", () => {
  it("is six entries: the controls row and the taller chart leave room for six", () => {
    expect(
      listPageSize({
        density: "line",
        lead: true,
        controlsRow: true,
        leadExtraPx: logChartPlotHeightPx - leadChartPlotHeightPx,
      }),
    ).toBe(6);
  });
});
