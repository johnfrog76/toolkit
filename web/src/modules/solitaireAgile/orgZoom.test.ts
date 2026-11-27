import {
  ZOOM,
  canZoomIn,
  canZoomOut,
  fitScale,
  zoomIn,
  zoomLabel,
  zoomOut,
  zoomPercent,
} from "./orgZoom";

// The Org page's zoom rules (orgZoom.ts): the fit, the steps and their ends,
// and the words the live region says.

describe("the fit", () => {
  it("fits the chart to the box's width, never above 100%", () => {
    expect(fitScale(1000, 2000)).toBe(0.5);
    expect(fitScale(1000, 1000)).toBe(1);
    expect(fitScale(1200, 800)).toBe(1);
  });

  it("never goes under the floor, however wide the tree", () => {
    expect(fitScale(100, 2000)).toBe(ZOOM.min);
  });

  it("is 100% before the box is measured", () => {
    expect(fitScale(0, 2000)).toBe(1);
    expect(fitScale(1000, 0)).toBe(1);
  });
});

describe("the steps", () => {
  it("are 10% from a step, between 25% and 200%", () => {
    expect(zoomIn(1)).toBe(1.1);
    expect(zoomOut(1)).toBe(0.9);
    expect(zoomIn(0.3)).toBe(0.4);
    expect(zoomOut(0.4)).toBe(0.3);
  });

  it("from a fitted scale between steps, move to the next step that way", () => {
    expect(zoomIn(0.734)).toBe(0.8);
    expect(zoomOut(0.734)).toBe(0.7);
  });

  it("stop at the ends, and the buttons say so", () => {
    expect(zoomIn(1.95)).toBe(2);
    expect(zoomIn(2)).toBe(2);
    expect(zoomOut(0.3)).toBe(0.25);
    expect(zoomOut(0.25)).toBe(0.25);
    expect(canZoomIn(2)).toBe(false);
    expect(canZoomIn(1.9)).toBe(true);
    expect(canZoomOut(0.25)).toBe(false);
    expect(canZoomOut(0.3)).toBe(true);
  });

  it("walk the whole range in whole steps, with no drift", () => {
    const up: number[] = [];
    for (let s: number = ZOOM.min; canZoomIn(s); s = zoomIn(s)) up.push(zoomPercent(zoomIn(s)));
    expect(up[0]).toBe(30);
    expect(up[up.length - 1]).toBe(200);
    expect(up.every((p) => p % 10 === 0)).toBe(true);
  });
});

describe("the words", () => {
  it("say the percentage, whole", () => {
    expect(zoomLabel(0.75)).toBe("Zoom 75%");
    expect(zoomLabel(0.734)).toBe("Zoom 73%");
    expect(zoomLabel(1)).toBe("Zoom 100%");
  });
});
