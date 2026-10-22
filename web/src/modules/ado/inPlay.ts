import { STATUS } from "../../shell/consts";

// The WIP line, the web's half. The CLI's is Scripts/Get-InPlayLine.ps1; the
// number is `limits.inPlay`, served once by /env as config.inPlayLimit, so the
// board keeps no reader of its own.
//
// A LINE THE PRODUCT SAYS, NEVER A GATE: nothing here refuses a move, blocks a
// pull or hides a card. "limit doesn't mean slow it down, it means more focus."
//
//   no limit (null, undefined, below 1)  -> no line at all (opt in)
//   count at or under the limit          -> "in play 4"
//   count past the limit                 -> "in play 7 of 5", and amber
//
// "of N" is said only past the limit, the same rule the CLI follows.

/** The three lanes a card in `current/` can be in -- everything but Backlog and Done. */
const IN_PLAY = new Set<string>([STATUS.active, STATUS.inProgress, STATUS.codeReview]);

export interface InPlay {
  text: string;
  past: boolean;
}

/** Cards in play: every lane of current/, never the backlog and never the archive. */
export function countInPlay(cards: ReadonlyArray<{ status: string }>): number {
  return cards.filter((c) => IN_PLAY.has(c.status)).length;
}

export function inPlayLine(count: number, limit: number | null | undefined): InPlay | null {
  if (typeof limit !== "number" || !Number.isInteger(limit) || limit < 1) return null;
  if (count > limit) return { text: `in play ${count} of ${limit}`, past: true };
  return { text: `in play ${count}`, past: false };
}
