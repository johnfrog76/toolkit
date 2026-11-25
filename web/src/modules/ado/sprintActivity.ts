import type { SprintActivityEntry } from "./api.ado";
import { localDay } from "../../utility/dates";

// What the Sprint Velocity card says about the recorded history, in one place
// so a tile, a tooltip and a chart description use the same words.
export const SPRINT_WORDS = {
  mine: "my commits",
  team: "team commits",
  rest: "rest of the team",
} as const;

export interface SprintBar {
  date: string;
  label: string;
  /** My commits that day, as recorded. */
  mine: number;
  /** The team's commits that day, as recorded. It already includes mine. */
  team: number;
  /** The part of the bar that is mine: mine, held at the team's count so the bar never outgrows it. */
  drawnMine: number;
  /** The team's commits that are not mine: team minus mine, never below zero. */
  rest: number;
}

/**
 * One bar per calendar day of the window. The record's `team` count includes
 * `mine`, so a bar is drawn as two parts, mine and the rest, whose sum is the
 * team's count.
 */
export function buildSprintBars(
  startDate: string,
  endDate: string,
  mine: SprintActivityEntry[],
  team: SprintActivityEntry[],
): SprintBar[] {
  const mineMap = new Map(mine.map((d) => [d.date, d.count]));
  const teamMap = new Map(team.map((d) => [d.date, d.count]));
  const bars: SprintBar[] = [];
  const cursor = new Date(startDate + "T00:00:00");
  const end = new Date(endDate + "T00:00:00");
  while (cursor <= end) {
    const date = localDay(cursor);
    const m = mineMap.get(date) ?? 0;
    const t = teamMap.get(date) ?? 0;
    bars.push({
      date,
      label: cursor.toLocaleString("default", { weekday: "short", day: "numeric" }),
      mine: m,
      team: t,
      drawnMine: Math.min(m, t),
      rest: Math.max(t - m, 0),
    });
    cursor.setDate(cursor.getDate() + 1);
  }
  return bars;
}

/** The last day the history records, whatever its count: a quiet day is still recorded. */
export function lastRecordedDay(
  mine: SprintActivityEntry[],
  team: SprintActivityEntry[],
): string | null {
  let latest: string | null = null;
  for (const d of [...mine, ...team]) {
    if (latest === null || d.date > latest) latest = d.date;
  }
  return latest;
}
