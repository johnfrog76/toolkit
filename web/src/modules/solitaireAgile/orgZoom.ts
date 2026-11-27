// The Org page's zoom (docs/modules/solitaire-agile.md, "The web UI"): its rules,
// apart from its drawing. Pure, so the tests read them as the page does.
//
// Zoom scales the chart's own layer and nothing else. The page opens at the
// scale that fits the chart's box to its width, capped at 100% -- a tree that
// already fits looks exactly as it did -- and the buttons step it by 10%
// between 25% and 200%. A fitted scale need not be a step (73%): the first
// press moves to the next step in that direction (80%, or 70%).

export const ZOOM = {
  /** The smallest scale the buttons reach, and the floor a fit never goes under. */
  min: 0.25,
  /** The largest scale the buttons reach. */
  max: 2,
  /** One press of Zoom in or Zoom out. */
  step: 0.1,
} as const;

/** A scale's percentage, a whole number: 0.734 is 73. */
export const zoomPercent = (scale: number): number => Math.round(scale * 100);

/** What the live region says: "Zoom 75%". */
export const zoomLabel = (scale: number): string => `Zoom ${zoomPercent(scale)}%`;

/** The scale that fits a chart `layoutWidth` wide into a box `boxWidth` wide:
 *  never above 100%, never under the floor. A box not measured yet (0) is 100%. */
export function fitScale(boxWidth: number, layoutWidth: number): number {
  if (!(boxWidth > 0) || !(layoutWidth > 0)) return 1;
  return Math.min(1, Math.max(ZOOM.min, boxWidth / layoutWidth));
}

// Scales are stepped in whole tenths, so 0.1 + 0.2 never drifts to 0.30000000000000004.
const tenths = (scale: number): number => Math.round(scale * 100) / 10;

/** One press of Zoom in: the next 10% step above, up to 200%. */
export function zoomIn(scale: number): number {
  return Math.min(ZOOM.max, (Math.floor(tenths(scale) + 1e-9) + 1) / 10);
}

/** One press of Zoom out: the next 10% step below, down to 25%. */
export function zoomOut(scale: number): number {
  return Math.max(ZOOM.min, (Math.ceil(tenths(scale) - 1e-9) - 1) / 10);
}

export const canZoomIn = (scale: number): boolean => scale < ZOOM.max - 1e-9;
export const canZoomOut = (scale: number): boolean => scale > ZOOM.min + 1e-9;
