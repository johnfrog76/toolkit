import { STATUS } from "../../shell/consts";
import type { AgendaItem } from "./api.solitaireAgile";

// The Agenda's words, as the Team Agile page reads them (docs/modules/
// solitaire-agile.md, "The page"). Pure, and kept out of the page so the
// scenarios test can read it without drawing anything -- suggestion.ts's shape.

/** The sentence under the tab's title -- the owner's words. */
export const AGENDA_SENTENCE =
  "Here you can see the work items you can in fact kick off now, with the Work it now button.";
export const WORK_IT_NOW = "Work it now";
export const REVIEW_IT = "Review it";

/** The two views of the Agenda, cards the default. */
export const AGENDA_VIEWS = ["cards", "list"] as const;

/** A yyyy-MM-dd day the long way, in English: "Friday 23 October". "" for no day. */
export function longDay(day: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(day ?? "");
  if (!m) return "";
  const date = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  const parts = new Intl.DateTimeFormat("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "long",
  }).formatToParts(date);
  const part = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return `${part("weekday")} ${part("day")} ${part("month")}`;
}

/** The first lane's heading: the standup's own window, "Since Friday 23 October". */
export function sinceHeading(since: string): string {
  const day = longDay(since);
  return day ? `Since ${day}` : "Since the last standup";
}

/** The tile's one fact line. What moved: Closed (an issue) or Archived (a card).
 *  What waits: In review since, Active since, or Open since (an issue with no card).
 *  With no day on the record, the fact alone. */
export function agendaFact(item: AgendaItem, moved: boolean): string {
  const day = longDay(item.day);
  const at = (word: string, joiner: string) => (day ? `${word}${joiner}${day}` : word);
  if (moved) return item.kind === "card" ? at("Archived", " ") : at("Closed", " ");
  if (item.lane === STATUS.codeReview) return at("In review", " since ");
  if (item.lane === STATUS.active) return at("Active", " since ");
  return at("Open", " since ");
}

/** What StartWork is given for a tile: the issue's number, else the card's id. */
export const agendaArg = (item: AgendaItem): string =>
  item.number != null ? String(item.number) : (item.id ?? "");
