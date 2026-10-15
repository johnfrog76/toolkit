/**
 * Settings BY WORKFLOW -- the questions a person asks, in their words, each
 * tied to an optional surface by key (docs/CONFIGURATION.md, "Settings by workflow: the questions, and the one list behind them").
 *
 * ONE file, Config/settings-workflows.json, read here at build time through
 * the `@workflows` alias (the `@consts` shape: vite, tsconfig and jest each
 * resolve it) and by the CLI at run time, which puts the question on every
 * inventory row. The STATE of a surface never comes from here: it is the
 * CLI's (D-W2), served by GET /api/surfaces; this module only knows how to
 * read an entry against those states.
 *
 * Three doors (D-W4): `change` opens the drawer at `anchor`; `walk` is a
 * journey -- the wizard, W2; until it exists a walk with an anchor opens the
 * drawer like a change and one without is its sentence; `sentence` is the
 * whole answer. A `tip` is offered while EVERY surface of the entry reads
 * `not configured` -- never `off` (D-W3).
 *
 * An entry that names a `space` (the three demo Spaces, one per grain,
 * D-W17) is about THAT Space, so it is not read against the inventory: a
 * journey tips while the Space is declared and still `local`, and walks that
 * Space; anything else tips while you are in it (spaceTipEntries).
 */
import workflows from "@workflows";
import type { SurfaceRow } from "./api";

export type WorkflowDoor = "change" | "walk" | "sentence";
export type SurfaceState = SurfaceRow["state"];

/** The tracker a Space's address names -- /env's `tracker` (D-G2). */
export type TrackerKind = "github" | "ado" | "none";

/** One answer of an entry that asks ("How do you want to work in
 *  {space}?"): the words on the radio, the value it writes to the entry's
 *  `answerKey` through `Config -Set -Hub`, its one sentence, and the trackers on
 *  which it can be picked -- elsewhere it is drawn disabled, never hidden. */
export interface WorkflowAnswer {
  label: string;
  value: string;
  sentence: string;
  live: TrackerKind[];
}

export interface WorkflowEntry {
  id: string;
  question: string;
  sentence: string;
  surfaces: string[];
  door: WorkflowDoor;
  /** `{slug}` stands for the active Space. Absent on a sentence, and on a walk with no key. */
  anchor?: string;
  /** A walk's own page, `{slug}` filled in the same way -- the connect wizard's `/connect/{slug}` (D-W12). */
  route?: string;
  /** The Space this entry is about -- its tip follows that Space, and
   *  its walk goes there when the Space is declared. */
  space?: string;
  tip?: string;
  /** Radios in the drawer, each writing its value to `answerKey`. */
  answers?: WorkflowAnswer[];
  /** The key the answers write -- `{slug}` is the active Space. */
  answerKey?: string;
  /** Per tracker, the one sentence saying why the disabled answers are disabled. */
  why?: Partial<Record<TrackerKind, string>>;
}

/** The little of a Space a tip needs -- a row of /env's `config.spaces`. */
export interface DeclaredSpace {
  slug: string;
  status?: string;
}

export const WORKFLOW_ENTRIES: WorkflowEntry[] = (workflows as { entries: WorkflowEntry[] })
  .entries;

/** The anchor with the active Space filled in. */
export function entryAnchor(entry: WorkflowEntry, activeSpace: string): string | undefined {
  return entry.anchor?.replace("{slug}", activeSpace || "<slug>");
}

/** A walk's page with a Space filled in: the entry's own `space` when that
 *  Space is declared (the GitHub demo's wizard), else the one you are in --
 *  so the same question still walks YOUR Space on a hub without the demos. */
export function entryRoute(
  entry: WorkflowEntry,
  activeSpace: string,
  declared: DeclaredSpace[] = [],
): string | undefined {
  const own = entry.space && declared.some((s) => s.slug === entry.space) ? entry.space : "";
  return entry.route?.replace("{slug}", own || activeSpace || "");
}

/** An entry's state from its surfaces': `on` if any is on, `not configured`
 *  if every one is, else `off`. An entry whose surfaces the inventory does
 *  not carry reads `not configured` -- the honest word for "nothing known". */
export function entryState(entry: WorkflowEntry, surfaces: SurfaceRow[]): SurfaceState {
  const states = entry.surfaces.map(
    (k) => surfaces.find((s) => s.key === k)?.state ?? "not configured",
  );
  if (states.some((s) => s === "on")) return "on";
  if (states.every((s) => s === "not configured")) return "not configured";
  return "off";
}

/** The question with the Space you are in for `{space}`; "this Space"
 *  when none is known -- the CLI's inventory says the same. */
export function entryQuestion(entry: WorkflowEntry, spaceName?: string): string {
  return entry.question.replace("{space}", spaceName || "this Space");
}

/** The key an entry's answers write, the active Space filled in. */
export function answerTarget(entry: WorkflowEntry, activeSpace: string): string | undefined {
  return entry.answerKey?.replace("{slug}", activeSpace || "<slug>");
}

/** Whether an answer can be picked on a Space whose tracker is `tracker`: the
 *  rule's other half is the agent's (how_i_work) -- an answer is never live
 *  where the Space's answer is LOCKED, which /env says. */
export function answerLive(answer: WorkflowAnswer, tracker: TrackerKind, locked: boolean): boolean {
  return !locked && answer.live.includes(tracker);
}

/** The CLI lines that change an entry's surfaces -- the tooltip's second half. */
export function entryConfigLines(entry: WorkflowEntry, surfaces: SurfaceRow[]): string[] {
  return entry.surfaces
    .map((k) => surfaces.find((s) => s.key === k)?.config)
    .filter((c): c is string => !!c);
}

/** The entries that may tip right now: they carry a tip and every surface is
 *  not configured (D-W3). The tips card rotates them; this only says which. */
export function tippableEntries(surfaces: SurfaceRow[]): WorkflowEntry[] {
  return WORKFLOW_ENTRIES.filter(
    (e) => !!e.tip && !e.space && entryState(e, surfaces) === "not configured",
  );
}

/** The tips that belong to one Space, in the list's order. A journey
 *  (an entry with a `route`) tips while its Space is declared and still
 *  `local` -- connecting it is what retires the tip, and a Space hidden by
 *  Hide Demo is not declared; any other entry tips while you are IN its Space. */
export function spaceTipEntries(declared: DeclaredSpace[], activeSpace: string): WorkflowEntry[] {
  return WORKFLOW_ENTRIES.filter((e) => {
    if (!e.tip || !e.space) return false;
    if (e.route) return declared.some((s) => s.slug === e.space && s.status === "local");
    return e.space === activeSpace;
  });
}

/** Whether a Space carries a tip of its own -- the generic connect tip stands
 *  aside there rather than say the same thing twice. */
export function spaceHasOwnTip(slug: string): boolean {
  return WORKFLOW_ENTRIES.some((e) => !!e.tip && e.space === slug);
}
