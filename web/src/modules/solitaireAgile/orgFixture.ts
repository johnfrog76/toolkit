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
  models: Record<string, { name?: string; family?: string }>;
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

/** A seat's modelFamily as the route serves it (org.py's model_family): an id's
 *  row family; a family the current block names, itself; anything else null. */
export function modelFamilyOf(model: string | null): string | null {
  if (!model) return null;
  const row = MODEL_MAP.models[model];
  if (row) return row.family ?? null;
  const today = Object.entries(MODEL_MAP.current).find(
    ([f]) => f.toLowerCase() === model.toLowerCase(),
  )?.[1];
  return today ? (MODEL_MAP.models[today]?.family ?? null) : null;
}

/** The families the route serves: the model map's current block, in its order. */
export const FAMILIES = Object.keys(MODEL_MAP.current);

/** The etag every test chart is served with. */
export const TEST_ETAG = "a".repeat(64);

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
    p.defaultModelFamily = modelFamilyOf(p.defaultModel);
    for (const s of p.seats) {
      s.modelName = modelNameOf(s.model);
      s.modelFamily = modelFamilyOf(s.model);
    }
  }
  return { ...chart, etag: TEST_ETAG, families: FAMILIES };
}
