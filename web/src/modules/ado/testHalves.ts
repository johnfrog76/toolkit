import { TESTS } from "../../shell/consts";
import type { HalfResult, TestHistoryResponse } from "./api.ado";

/**
 * What the Health card draws for a machine's three halves: one tile a
 * half, in the order `{cliPrefix}Test` runs them, read from THIS machine's
 * `test-summary.<machine>.json` as the agent serves it. A half with no record
 * is absent -- nothing has run it here -- and a skipped half is a tile that says
 * so with its reason, never a pass.
 */
export type HalfTone = "pass" | "fail" | "skip";

export interface HalfTile {
  half: HalfResult["half"];
  label: string;
  count: string;
  tone: HalfTone;
  /** The tooltip: the half's own words for what ran, or why it did not. */
  detail: string;
}

const LABELS: Record<HalfResult["half"], string> = {
  agent: "Agent",
  cli: "CLI",
  web: "Web UI",
};

export function halfTiles(
  data: Pick<TestHistoryResponse, "machine" | "machines"> | undefined,
): HalfTile[] {
  if (!data) return [];
  const mine = data.machines.find((m) => m.machine === data.machine);
  const halves = mine?.halves;
  if (!halves) return [];
  const tiles: HalfTile[] = [];
  for (const half of TESTS.halves) {
    const rec = halves[half];
    if (!rec) continue;
    const label = LABELS[half];
    if (rec.result === "skip") {
      tiles.push({ half, label, count: "Skipped", tone: "skip", detail: rec.reason || "Skipped" });
      continue;
    }
    const parts = [`${rec.passed} passed`, `${rec.failed} failed`];
    if (rec.skipped > 0) parts.push(`${rec.skipped} skipped`);
    tiles.push({
      half,
      label,
      count: `${rec.passed}/${rec.passed + rec.failed}`,
      tone: rec.result === "pass" ? "pass" : "fail",
      detail: parts.join(", "),
    });
  }
  return tiles;
}
