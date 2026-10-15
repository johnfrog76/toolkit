/**
 * Chart color palette — Recharts needs resolved hex, not CSS vars.
 * Import `useChartColors` in any component that renders a chart.
 */
import { useWornTheme } from "./useWornTheme";

export const CHART_PALETTE = {
  light: {
    pass: "#8587B8",
    fail: "#C26566",
    succeeded: "#8587B8",
    failed: "#B05A6A",
    partiallySucceeded: "#D9A84E",
    canceled: "#A8AACF",
    running: "#6E709A",
    ERR: "#C26566",
    WARN: "#B07040",
    CMD: "#8587B8",
    INFO: "#3A8CC4",
    bug: "#C26566",
    story: "#3A8CC4",
    feature: "#4d7d51",
    task: "#9E85B8",
    heatLow: "#D8EAF7",
    heatMed: "#6AACD6",
    heatHigh: "#2A5E8A",
    billingBar: "#8587B8",
    billingAvg: "#B07040",
    teamLow: "#F5E4C0",
    teamMed: "#D9A84E",
    teamHigh: "#9B6B1A",
  },
  dark: {
    pass: "#4d8a4d",
    fail: "#F1707B",
    succeeded: "#7B83EB",
    failed: "#F1707B",
    partiallySucceeded: "#F7C948",
    canceled: "#A6A7DC",
    running: "#3BC9DB",
    ERR: "#F1707B",
    WARN: "#F7C948",
    CMD: "#54B054",
    INFO: "#4FC3F7",
    bug: "#F1707B",
    story: "#4FC3F7",
    feature: "#54B054",
    task: "#A6A7DC",
    heatLow: "#1B3A5C",
    heatMed: "#2B88D8",
    heatHigh: "#60CDFF",
    billingBar: "#7B83EB",
    billingAvg: "#F7C948",
    teamLow: "#2E1D06",
    teamMed: "#B8852A",
    teamHigh: "#F7C948",
  },
} as const;

export type ChartColorKey = keyof (typeof CHART_PALETTE)["light"];

/** Resolved palette for the current theme. */
export function useChartColors() {
  return CHART_PALETTE[useWornTheme().theme];
}
