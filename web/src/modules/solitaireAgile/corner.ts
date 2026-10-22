import { RITUALS } from "../../shell/consts";
import type { Corner, StandupResponse } from "./api.solitaireAgile";

// The PM Corner as the Team Agile page reads it (AR-4; docs/modules/solitaire-agile.md,
// "The PM Corner: the line, the chevron, the confetti"). Pure, and kept out of the
// part so the scenarios test can read it without drawing anything. The line is the
// agent's, derived over the joined list; nothing here re-derives it.

/** The browser's key for the milestones already celebrated, all Spaces. */
export const CORNER_SEEN_KEY = "p20.solitaireAgile.corner.reached";

const [ONE_LEFT, MANY_LEFT, REACHED] = RITUALS.cornerShapes;

/** The Corner the page draws: the response's, or null when it carries none. */
export function cornerOf(data: StandupResponse | undefined): Corner | null {
  return data?.corner ?? null;
}

/** Whether the line carries the chevron: a pick to start (one left, several left). */
export const hasChevron = (c: Corner): boolean =>
  (c.shape === ONE_LEFT || c.shape === MANY_LEFT) && !!c.command;

/** Whether the line says the milestone is reached -- the confetti's line. */
export const isReached = (c: Corner): boolean => c.shape === REACHED;

/** What `StartWork` is given for the chevron: the issue's number, else the card's id. */
export const cornerArg = (c: Corner): string =>
  c.number != null ? String(c.number) : (c.id ?? "");

/** The id a milestone is remembered by in this browser: the Space slug (never a colon in it), a colon and its title, whole
 *  -- the same title the tracker and a card's **Sprint:** line both carry. */
export const milestoneKey = (space: string, c: Corner): string =>
  c.milestone ? `${space}:${c.milestone}` : "";

/** The brief with the Corner's last line set aside: the page draws the Corner at its
 *  head, so the chair's reading below it stops above that line. Copy still copies the
 *  brief exactly as the agent rendered it. */
export function briefSansCorner(data: StandupResponse): string {
  const brief = data.brief ?? "";
  const line = data.corner?.brief;
  if (!line) return brief;
  const tail = `${line}\n`;
  if (brief.endsWith(tail)) return brief.slice(0, -tail.length);
  if (brief.endsWith(line)) return brief.slice(0, -line.length);
  return brief;
}
