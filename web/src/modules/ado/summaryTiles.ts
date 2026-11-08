/**
 * The Space summary's tiles, as data: which tiles the card draws, in order, for one Space's totals.
 * EngagementSummary draws this list and the scenario grid asserts it (docs/SCENARIOS.md, "The Space
 * summary's tiles, by the growth flag").
 *
 * Reviews are the growth module's work reviews, so the tile is drawn only while growth is on: off,
 * or not configured, it is absent -- not a 0 that reads as "no reviews were written".
 */
import type { EngagementStats } from "./api.ado";

export interface SummaryTile {
  label: string;
  count: number;
}

export function summaryTiles(
  stats: EngagementStats,
  repos: number,
  opts: { growth: boolean },
): SummaryTile[] {
  const tiles: SummaryTile[] = [{ label: "Items closed", count: stats.workItemsClosed }];
  if (opts.growth) tiles.push({ label: "Reviews", count: stats.reviewsGenerated });
  if (stats.prsReviewed > 0) tiles.push({ label: "PRs reviewed", count: stats.prsReviewed });
  if (repos > 0) tiles.push({ label: "Repos", count: repos });
  return tiles;
}
