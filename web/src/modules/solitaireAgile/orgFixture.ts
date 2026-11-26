import fs from "node:fs";
import path from "node:path";
import type { OrgResponse } from "./api.solitaireAgile";

// The Org page's tests read the SHARED table's responses
// (Tests/fixtures/org/charts/), the documents the CLI's reader and the agent's
// are held to, plus the fields only the route adds. The table writes every
// prompt as an empty file, so the reading room's title for one is its name
// without `.prompt.md`, and its ref is `yours/<name>`; a seat's modelName is
// the model map's name as the agent looks it up (docs/hub/org.md, "The
// response"). Test-only: nothing in the app imports this file.

const PACKAGE = path.resolve(__dirname, "../../../..");
const CHARTS = path.join(PACKAGE, "Tests/fixtures/org/charts");
const MODEL_MAP = JSON.parse(fs.readFileSync(path.join(PACKAGE, "Config/models.json"), "utf8")) as {
  models: Record<string, { name?: string }>;
  current: Record<string, string>;
};

/** A seat's modelName as the route serves it (agent/solitaire/org.py's
 *  model_name): an id's row name; a family's id of today, by its name; anything
 *  else as written. The test mirror of the agent's lookup, so a page test reads
 *  what the route would send. */
export function modelNameOf(model: string | null): string | null {
  if (!model) return null;
  const row = MODEL_MAP.models[model];
  if (row) return row.name || model;
  const family = Object.keys(MODEL_MAP.current).find(
    (f) => f.toLowerCase() === model.toLowerCase(),
  );
  const today = family ? MODEL_MAP.current[family] : undefined;
  return today ? (MODEL_MAP.models[today]?.name ?? today) : model;
}

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
    p.defaultModelName = modelNameOf(p.defaultModel);
    for (const s of p.seats) s.modelName = modelNameOf(s.model);
  }
  return chart;
}
