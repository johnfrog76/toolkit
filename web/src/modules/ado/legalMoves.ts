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
// Backlog is a FOLDER too, the first lane: a new card is planned there until it
// is pulled into play. Dropping a Backlog card on any lane ahead runs Move, which
// moves the file to current/ first (and writes the line, for In Progress and Code
// Review). The one way back is Active -> Backlog, which Move allows for a card
// with nothing threaded -- and an Active card, by the state rule, has nothing
// threaded: no commit, no PR URL, no Started or Review line.
//
// A card travels one way otherwise. The lanes BEHIND a card are not targets: to
// take a card back, a person removes the line by hand, on purpose.

export const LANES = [
  STATUS.backlog,
  STATUS.active,
  STATUS.inProgress,
  STATUS.codeReview,
  STATUS.done,
] as const;
export type Lane = (typeof LANES)[number];

const ORDER: Record<string, number> = {
  [STATUS.backlog]: 0,
  [STATUS.active]: 1,
  [STATUS.inProgress]: 2,
  [STATUS.codeReview]: 3,
  [STATUS.done]: 4,
};

/** The lanes a card in `state` may be moved TO by a person: every lane ahead of
 *  it -- and, for an Active card, back to Backlog. */
export function legalMoves(state: string): Lane[] {
  const from = ORDER[state];
  if (from === undefined) return [];
  return LANES.filter(
    (lane) => ORDER[lane] > from || (state === STATUS.active && lane === STATUS.backlog),
  );
}

/** Why a card in `state` cannot be moved to `lane` -- "" when it can. */
export function whyNotAMove(state: string, lane: Lane): string {
  if (legalMoves(state).includes(lane)) return "";
  if (state === lane) return "It is already here.";
  if (lane === STATUS.backlog && (state === STATUS.inProgress || state === STATUS.codeReview)) {
    return "Threaded work is in play, not backlog.";
  }
  return "A card travels one way.";
}

/** The one-line rule under a lane's heading: who puts a card here. */
export function laneHint(lane: Lane): string {
  switch (lane) {
    case STATUS.backlog:
      return "A new card starts here, planned -- not yet in play.";
    case STATUS.active:
      return "Pulled into play: drop a planned card here, or its first commit brings it.";
    case STATUS.inProgress:
      return "A commit puts a card here -- or drop one, and it says you started.";
    case STATUS.codeReview:
      return "A pull request puts a card here -- or drop one, and it says look at this.";
    default:
      return "";
  }
}
