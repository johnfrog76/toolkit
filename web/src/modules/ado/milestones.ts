// The Milestones card's rules, pure so a table can hold them without a
// store. "Reached" is the agent's derived word (every issue closed, at least
// one issue); this file says what a row is CALLED and in what ORDER rows go.
import type { Milestone } from "./api.ado";

/** Where a milestone stands: on its way, arrived, or holding nothing yet. */
export type MilestoneStage = "in flight" | "reached" | "empty";

export function milestoneStage(m: Milestone): MilestoneStage {
  if (m.reached) return "reached";
  return m.open + m.closed === 0 ? "empty" : "in flight";
}

/** Closed of total, 0 when there is nothing to close. */
export function milestoneProgress(m: Milestone): number {
  const total = m.open + m.closed;
  return total === 0 ? 0 : m.closed / total;
}

/** The row's one sentence about its state -- what is left to do, if anything.
 *  A reached milestone GitHub still shows open is the one thing left on the
 *  tracker, so it says so; a closed one wears its closed date. */
export function milestoneStateWords(m: Milestone): string {
  if (m.state === "closed") return m.closed_at ? `closed ${m.closed_at}` : "closed";
  if (m.reached) return "reached, not closed";
  return "";
}

const STAGE_RANK: Record<MilestoneStage, number> = { "in flight": 0, reached: 1, empty: 2 };

/** In flight first (most complete at the top), then reached (the ones still
 *  open on GitHub first, then newest closed), then empty. Title breaks a tie. */
export function orderMilestones(list: Milestone[]): Milestone[] {
  return [...list].sort((a, b) => {
    const sa = milestoneStage(a);
    const sb = milestoneStage(b);
    if (sa !== sb) return STAGE_RANK[sa] - STAGE_RANK[sb];
    if (sa === "in flight") {
      const d = milestoneProgress(b) - milestoneProgress(a);
      if (d !== 0) return d;
    }
    if (sa === "reached") {
      const openA = a.state === "closed" ? 1 : 0;
      const openB = b.state === "closed" ? 1 : 0;
      if (openA !== openB) return openA - openB;
      if (a.closed_at !== b.closed_at) return b.closed_at.localeCompare(a.closed_at);
    }
    return a.title.localeCompare(b.title);
  });
}

/** The tile row above the list: reached, in flight, issues left. */
export function milestoneTally(list: Milestone[]): {
  reached: number;
  inFlight: number;
  left: number;
} {
  let reached = 0;
  let inFlight = 0;
  let left = 0;
  for (const m of list) {
    const s = milestoneStage(m);
    if (s === "reached") reached++;
    else if (s === "in flight") inFlight++;
    left += m.open;
  }
  return { reached, inFlight, left };
}
