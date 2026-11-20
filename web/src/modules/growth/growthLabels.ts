import type { GrowthType } from "./api.growth";

// Three types, and the badge reads the item rather than asking whether it is a
// presentation. It used to be a boolean, which was true of the two types that
// existed then and silently labelled the third one "Training".
export const TYPE_LABEL: Record<GrowthType, string> = {
  training: "Training",
  presentation: "Presentation",
  goal: "Goal",
};
export const TYPE_COLOUR: Record<GrowthType, "success" | "brand" | "informative"> = {
  training: "success",
  presentation: "brand",
  goal: "informative",
};

/** One growth item's page. */
export function goalPath(filename: string): string {
  return `/growth/goals/${encodeURIComponent(filename)}`;
}
