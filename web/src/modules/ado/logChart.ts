// The Log card's chart data and its badge, as pure functions the card renders.
//
// The agent serves entries newest first (the list reads that way), and the
// chart used to take the days in that order -- so its time axis ran right to
// left while Health, beside it, ran left to right. A chart's days are sorted
// here, oldest on the left, whatever order the entries arrive in.
import type { LogEntry } from "./api.ado";

export interface ChartRow {
  label: string;
  ERR: number;
  WARN: number;
  CMD: number;
  INFO: number;
}

export function buildChartData(entries: LogEntry[]): ChartRow[] {
  const byDate = new Map<string, Record<string, number>>();
  for (const e of entries) {
    const d = e.timestamp.slice(0, 10);
    if (!byDate.has(d)) byDate.set(d, { ERR: 0, WARN: 0, CMD: 0, INFO: 0 });
    const m = byDate.get(d)!;
    m[e.type] = (m[e.type] ?? 0) + 1;
  }
  // Oldest on the left. The dates are ISO, so a string sort is a date sort.
  return Array.from(byDate.entries())
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([date, counts]) => {
      const dt = new Date(date + "T00:00:00");
      const dayName = dt.toLocaleDateString(undefined, { weekday: "short" });
      const dayNum = dt.getDate();
      return { label: `${dayName} ${dayNum}`, ...counts } as ChartRow;
    });
}

/** The number on the card's badge. The agent answers with at most `cap`
 *  entries, so a badge reading "500" was a limit dressed as a count: when the
 *  answer was cut at the cap and nothing narrows it, say so. A filtered view
 *  says how many match. */
export function logBadge(shown: number, served: number, cap: number): string {
  if (served >= cap && shown === served) return `latest ${cap}`;
  return String(shown);
}
