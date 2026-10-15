import { STATUS } from "../../shell/consts";

// What a PERSON may do to a card on the board -- one pure function, so the drop
// targets and the "Move to..." menu can never disagree about it.
//
// State is derived from the file (AGENTS.md), and every lane now has
// TWO writers: git's token, and a person's. A commit bullet is In Progress and so
// is a **Started:** line; a PR URL is Code Review and so is a **Review:** line;
// Done is the archive folder. Dropping a card on a lane writes the person's line
// through the Move verb -- the board became one more thing that writes a line,
// beside ThreadHash and NewPR, and the rule does not care who wrote it.
//
// A card travels one way. The lanes BEHIND a card are not targets: to take a
// card back, a person removes the line by hand, on purpose.

export const LANES = [STATUS.active, STATUS.inProgress, STATUS.codeReview, STATUS.done] as const;
export type Lane = (typeof LANES)[number];

const ORDER: Record<string, number> = {
  [STATUS.active]: 0,
  [STATUS.inProgress]: 1,
  [STATUS.codeReview]: 2,
  [STATUS.done]: 3,
};

/** The lanes a card in `state` may be moved TO by a person: every lane ahead of it. */
export function legalMoves(state: string): Lane[] {
  const from = ORDER[state];
  if (from === undefined) return [];
  return LANES.filter((lane) => ORDER[lane] > from);
}

/** Why a card in `state` cannot be moved to `lane` -- "" when it can. */
export function whyNotAMove(state: string, lane: Lane): string {
  if (legalMoves(state).includes(lane)) return "";
  if (state === lane) return "It is already here.";
  return "A card travels one way.";
}

/** The one-line rule under a lane's heading: who puts a card here. */
export function laneHint(lane: Lane): string {
  switch (lane) {
    case STATUS.active:
      return "A card is here from the moment it is made.";
    case STATUS.inProgress:
      return "A commit puts a card here -- or drop one, and it says you started.";
    case STATUS.codeReview:
      return "A pull request puts a card here -- or drop one, and it says look at this.";
    default:
      return "";
  }
}
