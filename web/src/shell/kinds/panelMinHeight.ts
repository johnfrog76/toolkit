import { makeStyles } from "@fluentui/react-components";
import { PANEL_GRID_MIN_WIDTH_PX, PANEL_MAX_HEIGHT_PX, PANEL_MIN_HEIGHT_PX } from "../panelHeight";
import type { PanelKind } from "../panelHeight";

const wide = `@media (min-width: ${PANEL_GRID_MIN_WIDTH_PX}px)`;

const useStyles = makeStyles({
  // A list panel is exactly this tall: its floor is its cap, and its page fits.
  list: {
    [wide]: {
      minHeight: `${PANEL_MIN_HEIGHT_PX.list}px`,
      maxHeight: `${PANEL_MAX_HEIGHT_PX.list}px`,
    },
  },
  status: { [wide]: { minHeight: `${PANEL_MIN_HEIGHT_PX.status}px` } },
  stat: { [wide]: { minHeight: `${PANEL_MIN_HEIGHT_PX.stat}px` } },
  chart: { [wide]: { minHeight: `${PANEL_MIN_HEIGHT_PX.chart}px` } },
  scene: { [wide]: { minHeight: `${PANEL_MIN_HEIGHT_PX.scene}px` } },
});

/** The class that gives a panel its kind's height bounds on a wide page: a
 *  minimum for every kind, and for a list panel the same figure as its maximum.
 *  A kind wears it on its root; a panel not yet on a kind may wear it meanwhile. */
export function usePanelMinHeightClass(kind: PanelKind): string {
  return useStyles()[kind];
}
