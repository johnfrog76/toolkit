// The foyer's words (Studio S2b, D-S2 as amended by D-S13): which Spaces get a
// row, and the one line each row says. Pure, so the rule is a table in
// foyer.test.ts.
//
// EVERY Space the agent offers has a row (D-S13): a person with one Azure
// DevOps Space, or only their own cards, must not land in an empty room. What a
// row says is what its tracker can give -- the tracker the agent derived from
// the Space's address (/env's `config.spaces[].tracker`, never re-derived here):
//
//   - a GitHub row, led by its repository's visibility (`Public`, `Private`, or
//     `Visibility unknown` when the tracker did not answer; nothing at
//     all for a Space not connected yet, which is not asked), then its
//     issues and deploys, in GitHub's own vocabulary: open,
//     closed this week, sev1, the last deploy's state and age ("a product with
//     nothing to say says so in one line ('no open issues; last deploy 3 days
//     ago, green')");
//   - an Azure DevOps row, or a row with no tracker, its cards -- counted from
//     /api/status, for another Space through its `space` argument, under
//     that Space's own lane names. An archived Space's row is not asked: its
//     cards are read by going in.
//
// A row whose tracker does not answer says what connecting would show -- the
// teaching empty state -- and never reads as an error.
import type { DateTime } from "luxon";
import type { EnvStatus, SpaceInfo } from "../../shell/api";
import { STATUS } from "../../shell/consts";
import type { DeploysResponse, IssueReport, StatusResponse } from "../ado/api.ado";
import { localNow, parseLocal } from "../../utility/dates";

/** The Spaces the foyer draws a row for: every one /env offers, in its order. */
export function foyerSpaces(env: EnvStatus | undefined): SpaceInfo[] {
  return env?.config?.spaces ?? [];
}

// The Spaces card's filter: one row of exposed tags over the list, All first.
// Every bucket is DERIVED from fields a Space already has -- its status,
// whether it is a shipped example, its tracker -- so the filter stores nothing
// but the choice. One Space is in exactly one bucket, by the first rule that
// fits (spaceBucket); All is every Space listed. There is no Hidden entry:
// hiding a Space is not built, and an entry that can hold nothing is noise.
export type SpacesFilter = "all" | "products" | "work" | "outOfBox" | "archive";
export type SpaceBucket = Exclude<SpacesFilter, "all">;

/** The filter tags, in its order, each with what its empty list says. */
export const SPACES_FILTERS: ReadonlyArray<{ value: SpacesFilter; label: string; empty: string }> =
  [
    { value: "all", label: "All", empty: "No Spaces" },
    { value: "products", label: "Products", empty: "No product Spaces" },
    { value: "work", label: "Work", empty: "No work Spaces" },
    { value: "outOfBox", label: "Out of box", empty: "No out-of-box Spaces" },
    { value: "archive", label: "Archive", empty: "No archived Spaces" },
  ];

/** True for a value the tags offer -- a stored choice is checked with it,
 *  so a value an older build wrote, or nonsense, reads as All. */
export function isSpacesFilter(value: string): value is SpacesFilter {
  return SPACES_FILTERS.some((f) => f.value === value);
}

/**
 * Which bucket a Space is in -- the first rule that fits:
 *   archived              -> Archive (an archived GitHub Space is not a product any more)
 *   a shipped example     -> Out of box (the demos, whatever their tracker)
 *   its tracker is GitHub -> Products (the things you make)
 *   anything else         -> Work (an Azure DevOps Space, or your own cards with no tracker)
 */
export function spaceBucket(space: SpaceInfo): SpaceBucket {
  if (space.status === "archive") return "archive";
  if (space.example === true) return "outOfBox";
  if (space.tracker === "github") return "products";
  return "work";
}

/** The Spaces a filter shows, in the list's order. Honest: only what matches,
 *  even when that leaves out the Space you are in. */
export function filterSpaces(spaces: SpaceInfo[], filter: SpacesFilter): SpaceInfo[] {
  return filter === "all" ? spaces : spaces.filter((s) => spaceBucket(s) === filter);
}

/** What the list says in its own place when a filter matches nothing. */
export function spacesFilterEmpty(filter: SpacesFilter): string {
  return SPACES_FILTERS.find((f) => f.value === filter)?.empty ?? "No Spaces";
}

/**
 * What a Space's row menu offers for the end of its life, in order:
 *   Retire -- every Space not already archived (status archive, its cards kept);
 *   Remove -- every Space but the one you are in (un-declared; its folder stays).
 * The verb refuses the rest in its own words, inside the confirm (a Space
 * config.default.json ships can be retired, not removed). Never on the avatar
 * menu's short list: only here, where every Space has a row.
 */
export type SpaceLifecycleAction = "retire" | "remove";
export function spaceLifecycleActions(space: SpaceInfo, here: boolean): SpaceLifecycleAction[] {
  const actions: SpaceLifecycleAction[] = [];
  if (space.status !== "archive") actions.push("retire");
  if (!here) actions.push("remove");
  return actions;
}

/** A row reads the tracker's numbers only for a GitHub Space. An older agent
 *  sends no tracker at all, and that row reads as cards -- no guess from the address. */
export function isGithubRow(space: SpaceInfo): boolean {
  return space.tracker === "github";
}

/** Whether a row asks its repository's visibility: a GitHub Space
 *  that is connected (`active`). One not connected yet was never asked, so its
 *  line says nothing about visibility -- not even `Visibility unknown`. */
export function readsVisibility(space: SpaceInfo): boolean {
  return space.tracker === "github" && space.status === "active";
}

/** What kind of Space this is, in the row's own words. */
export function spaceKind(space: SpaceInfo): string {
  if (space.tracker === "github") return "GitHub";
  if (space.tracker === "ado") return "Azure DevOps";
  return "Your own cards";
}

/** What connecting would show, for a Space whose tracker does not answer. */
export const CONNECT_GITHUB =
  "not connected yet -- connect it, and this row shows its open issues and last deploy";
export const CONNECT_ADO =
  "not connected yet -- connect it, and its board's work items come in beside its cards";
export const CONNECT_NONE =
  "no tracker -- connect it to a GitHub repo and this row shows its open issues and last deploy";

/** The issues half of a GitHub row's line, or null while it is still being read. */
export function issuesPhrase(report: IssueReport | undefined): string | null {
  if (!report) return null;
  if (!report.supported) return CONNECT_GITHUB;
  if (report.reason) return report.reason;
  const parts = [report.open === 0 ? "no open issues" : `${report.open} open`];
  if (report.closed_recent > 0) parts.push(`${report.closed_recent} closed this week`);
  const sev1 = report.sev?.sev1 ?? 0;
  if (sev1 > 0) parts.push(`${sev1} sev1 open`);
  return parts.join(", ");
}

/** "today", "yesterday", "3 days ago" -- a run's day against the local today. */
export function dayAge(day: string, now: DateTime = localNow()): string {
  const at = parseLocal(day, now.zoneName ?? undefined);
  if (!at) return day;
  const days = Math.round(now.startOf("day").diff(at.startOf("day"), "days").days);
  if (days <= 0) return "today";
  if (days === 1) return "yesterday";
  return `${days} days ago`;
}

const RUN_WORD: Record<string, string> = {
  success: "green",
  failure: "red",
  cancelled: "cancelled",
};

/** The deploy half of a row's line; "" when there is nothing to say about deploys. */
export function deployPhrase(
  deploys: DeploysResponse | undefined,
  now: DateTime = localNow(),
): string {
  if (!deploys || !deploys.supported || deploys.reason) return "";
  const last = deploys.runs[0];
  if (!last) return "no deploys yet";
  const state =
    RUN_WORD[last.conclusion] ??
    (last.conclusion || (last.status === "completed" ? "done" : "running"));
  return `last deploy ${dayAge(last.when, now)}, ${state}`;
}

/** A GitHub row's whole line, or null while the issues are still being read. */
export function foyerLine(
  report: IssueReport | undefined,
  deploys: DeploysResponse | undefined,
  now: DateTime = localNow(),
): string | null {
  const issues = issuesPhrase(report);
  if (issues === null) return null;
  const deploy = report?.supported ? deployPhrase(deploys, now) : "";
  return deploy ? `${issues}; ${deploy}` : issues;
}

/**
 * A GitHub row's line, led by its repository's visibility: `Public` or
 * `Private`, then the row's facts, in the line's own `; ` style --
 * `Public; 4 open; last deploy 3 days ago, green`. A tracker that did not answer
 * gives `Visibility unknown`, said rather than left out. Null while either half
 * is still being read, so the line appears once, whole. Only a GitHub row is
 * given one: an Azure DevOps row, or one with no tracker, has no visibility.
 */
export function githubRowLine(visibility: string | null, facts: string | null): string | null {
  if (visibility === null || facts === null) return null;
  return visibility ? `${visibility}; ${facts}` : facts;
}

// The lanes a card in current/ can be in, in board order. Done lives in
// archive/, which /api/status does not read.
const OPEN_LANES = [STATUS.active, STATUS.inProgress, STATUS.codeReview];

/** The cards half of a row's line, from /api/status: how many cards are in
 *  play, and how many sit in each lane -- under the Space's own lane names. */
export function cardsPhrase(status: StatusResponse, laneNames?: Record<string, string>): string {
  const cards = status.prompts ?? [];
  if (cards.length === 0) return "no cards in play";
  const counts = OPEN_LANES.map(
    (lane) => [lane, cards.filter((c) => c.status === lane).length] as const,
  )
    .filter(([, n]) => n > 0)
    .map(([lane, n]) => `${n} ${laneNames?.[lane] ?? lane}`);
  const total = `${cards.length} ${cards.length === 1 ? "card" : "cards"} in play`;
  return counts.length > 0 ? `${total}: ${counts.join(", ")}` : total;
}

/** Whether a non-GitHub row asks /api/status for its cards: the Space you are
 *  in always, any other Space unless it is archived -- an archived
 *  Space's work is done, and its row is not worth a read on every visit. */
export function readsCards(space: SpaceInfo, here: boolean): boolean {
  return here || space.status !== "archive";
}

/**
 * A row's whole line for an Azure DevOps Space or one with no tracker, or null
 * while the cards are still being read. `status` is /api/status for THIS Space
 * when the row reads its cards (`reads`, from readsCards); a row that does not
 * says how to see them. The connect half is added while the Space's tracker
 * cannot answer: no address at all, or an address whose Space is not yet `active`.
 */
export function cardsLine(
  space: SpaceInfo,
  reads: boolean,
  status: StatusResponse | undefined,
  laneNames?: Record<string, string>,
): string | null {
  let cards: string;
  if (reads) {
    if (!status) return null;
    cards = cardsPhrase(status, laneNames);
  } else {
    cards = "go in to see its cards";
  }
  if (space.status === "archive") return cards;
  if (space.tracker === "ado" && space.status !== "active") return `${cards}; ${CONNECT_ADO}`;
  if (space.tracker === "none") return `${cards}; ${CONNECT_NONE}`;
  return cards;
}
