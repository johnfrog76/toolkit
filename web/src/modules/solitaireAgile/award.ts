import type { Milestone } from "../ado/api.ado";
import { milestoneStage } from "../ado/milestones";
import type { MilestoneStage } from "../ado/milestones";
import { hasSeen, markSeen } from "./celebrate";

// The award (docs/modules/solitaire-agile.md, "Milestones: the tab and the award"):
// which reached milestone the Milestones tab congratulates next, what its one line
// says, and the browser's mark that it has been. Pure but for the mark, and kept
// out of the dialog so a test can read the rule without drawing a canvas.
//
// "Reached" is the ado core's one rule, served by the agent (every issue closed,
// and at least one issue -- so a milestone with no issues is never reached and
// never awarded); this file adds the one state that is the browser's: AWARDED,
// a reached milestone whose dialog this browser has shown. The mark lives in the
// store every celebration uses (celebrate.ts: localStorage, wrapped, falling back
// to the page's memory), under this tab's own key.

/** The browser's key for the milestones already awarded, all Spaces. Its own key,
 *  not the PM Corner's old confetti mark: the award has never been shown. */
export const AWARD_SEEN_KEY = "p20.solitaireAgile.milestones.awarded";

/** What a row on the tab reads as: the Stats card's stage, or awarded. */
export type AwardStage = MilestoneStage | "awarded";

/** The id a milestone is remembered by: the Space slug (never a colon in it), a
 *  colon and its title, whole -- the PM Corner's own key shape (corner.ts). */
export const awardKey = (space: string, m: Pick<Milestone, "title">): string =>
  `${space}:${m.title}`;

export const isAwarded = (space: string, m: Milestone): boolean =>
  m.reached && hasSeen(AWARD_SEEN_KEY, awardKey(space, m));

/** A row's stage on the tab: awarded once its dialog has been seen. */
export function awardStage(space: string, m: Milestone): AwardStage {
  return isAwarded(space, m) ? "awarded" : milestoneStage(m);
}

/** The reached milestones this browser has not congratulated yet, in the list's order. */
export function pendingAwards(space: string, list: Milestone[]): Milestone[] {
  return list.filter((m) => m.reached && !hasSeen(AWARD_SEEN_KEY, awardKey(space, m)));
}

/** Set the mark: this milestone has had its dialog, and never gets another. */
export function markAwarded(space: string, m: Milestone): void {
  markSeen(AWARD_SEEN_KEY, awardKey(space, m));
}

const MONTHS = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

/** A YYYY-MM-DD day as "D Month YYYY"; "" for anything that is not a day. */
export function dayWords(day: string | undefined): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(day ?? "");
  if (!m) return "";
  const month = MONTHS[Number(m[2]) - 1];
  return month ? `${Number(m[3])} ${month} ${m[1]}` : "";
}

/** The day it was reached: GitHub's close, else its last change -- the last issue closing. */
export const reachedDay = (m: Milestone): string => m.closed_at || m.updated_at || "";

/** The dialog's heading. */
export const awardTitle = (m: Milestone): string => `Congratulations: ${m.title} reached!`;

/** The dialog's one line of what it took: the issues, then the dates the tracker gives. */
export function tookLine(m: Milestone): string {
  const n = m.closed;
  const issues = `${n} ${n === 1 ? "issue" : "issues"} closed`;
  const from = dayWords(m.created_at);
  const to = dayWords(reachedDay(m));
  if (from && to) return from === to ? `${issues}, on ${to}.` : `${issues}, ${from} to ${to}.`;
  if (to) return `${issues}, reached ${to}.`;
  return `${issues}.`;
}
