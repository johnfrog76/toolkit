import fs from "node:fs";
import path from "node:path";
import type { OrgResponse } from "./api.solitaireAgile";

// The Org page's tests read the SHARED table's responses
// (Tests/fixtures/org/charts/), the documents the CLI's reader and the agent's
// are held to, plus the two fields only the route adds. The table writes every
// prompt as an empty file, so the reading room's title for one is its name
// without `.prompt.md`, and its ref is `yours/<name>` (docs/hub/org.md, "The
// response"). Test-only: nothing in the app imports this file.

const CHARTS = path.resolve(__dirname, "../../../../Tests/fixtures/org/charts");

/** Every chart the table states, by its file's name without `.json`. */
export function chartNames(): string[] {
  return fs
    .readdirSync(CHARTS)
    .filter((f) => f.endsWith(".json"))
    .map((f) => f.replace(/\.json$/, ""))
    .sort();
}

/** One chart as GET /api/ritual/org serves it. */
export function orgResponse(name: string): OrgResponse {
  const chart = JSON.parse(fs.readFileSync(path.join(CHARTS, `${name}.json`), "utf8")) as {
    activeTree: string;
    tree: OrgResponse["tree"];
  };
  for (const p of chart.tree.positions) {
    const stem = p.prompt ? p.prompt.replace(/\.prompt\.md$/, "") : null;
    p.promptTitle = stem;
    p.promptRef = stem ? `yours/${stem}` : null;
  }
  return chart;
}
