import {
  AlertRegular,
  ArrowUploadRegular,
  CalendarLtrRegular,
  FlagRegular,
  MoneyRegular,
  TagRegular,
} from "@fluentui/react-icons";
import { ROW, defineRowMoves } from "../../shared/CardActions";
import type { RowMove } from "../../shared/CardActions";
import { STATUS } from "../../shell/consts";
import { trackerName } from "./TrackerBadge";
import type { PromptInfo } from "./api.ado";
import { lanesFor, legalMoves, whyNotAMove } from "./legalMoves";
import type { Lane } from "./legalMoves";

// What a PERSON may do to a card -- every action, in every view. One pure
// function, so the list's row and the board's card can never offer different
// things.
// legalMoves.ts answers for the lanes; this answers for the whole menu, and
// asks legalMoves for the lanes.
//
// Three axes decide it: the card's KIND (does it have a work item -- `linked`),
// its STATE (the derived lane, and what the record carries), and whether Azure
// DevOps is in use at all (`/env` ado.enabled). And one rule over all three,
// the one sendButton.ts draws:
//
//   absent    the action cannot apply to this card at all -- Open on <tracker> on a
//             card with no work item, every ADO action when ADO is off, Create
//             PR on an archived card. Offering it wastes a click and teaches a
//             person to distrust the menu.
//   disabled  it applies, but not yet -- and `whyNot` says what would change
//             that. Hiding it would strand a legitimate next step.
//
// Create PR, decided here:
//   - absent with ADO off, on a card with no work item (NewPR takes a work item
//     id), and on a Done card (it is archived; nothing moves out of Done);
//   - disabled while the RECORD has no commit bullet. Active is a statement
//     about the file, not about git -- there may be commits on a branch that
//     ThreadHash has not written in yet -- so the reason names that next step.
//     An In Progress card that got there by a person's **Started:** line has
//     no commit either, and reads the same;
//   - disabled when the card already carries a `PR URL:` line: the pull request
//     exists, and its review is the next step. Disabled rather than absent,
//     because a second PR for the same work item is legitimate work -- it is
//     not a thing that can never apply. A Code Review card by a person's
//     **Review:** line (no PR URL) is judged on its commits like any other;
//   - enabled otherwise. It opens the Create PR dialog, and the dialog asks
//     for the work item id: typing it is the deliberate step.
//
// Remind me about this, decided here: present only while the organize module
// is on (`/env` features.organize) -- off means absent, so with the flag off
// the menu does not name a module that is not there. It is the last item, and
// opens the organize module's New Reminder dialog pre-filled with the card's
// title and its id as the ref (docs/modules/organize.md, "The web UI").
//
// `commits` is served by the agent from the file (docs/hub/cards.md). An older
// agent does not send it; then a card past Active is given the benefit of the
// doubt rather than a reason that may be false.

// Plan milestone, Plan sprint and Tag, decided here: a form over the CLI's Plan and
// Tag verbs (POST /api/cmd/Plan, /api/cmd/Tag), each one line of the card
// (docs/hub/cards.md, "Milestone and sprint: two lines"). Present on every card in
// play or planned -- the verbs find a card in current/ and backlog/ -- and absent on
// a Done card, which the verbs do not look for: planning is forward. Nothing here
// writes the tracker; a GitHub milestone is Route's, an Azure DevOps one EditItem's.

export type CardActionId =
  | "open-ado"
  | "open-card"
  | "move"
  | "billable"
  | "create-pr"
  | "milestone"
  | "sprint"
  | "tags"
  | "remind";

/** A card's own moves -- on no other record. Everything else on its menu is the
 *  shared vocabulary (shared/CardActions ROW): Open the card, Move to <lane>,
 *  Archive (move to Done), and Open on <tracker>. */
export const CARD_MOVES = defineRowMoves("card", {
  createPr: { word: "Create PR", icon: ArrowUploadRegular },
  markNotBillable: { word: "Mark not billable", icon: MoneyRegular },
  makeBillable: { word: "Make billable again", icon: MoneyRegular },
  planMilestone: {
    word: "Plan milestone",
    icon: FlagRegular,
    tooltip: "Set or clear the card's milestone line",
  },
  planSprint: {
    word: "Plan sprint",
    icon: CalendarLtrRegular,
    tooltip: "Set or clear the card's sprint line",
  },
  tag: { word: "Tag", icon: TagRegular, tooltip: "Add or take off the card's tags" },
  remind: { word: "Remind me about this", icon: AlertRegular },
});

export interface CardActionSpec {
  id: CardActionId;
  /** The vocabulary entry, or the card's own move, this action is drawn from. */
  move: RowMove;
  /** The detail the move's word takes ("the card", "In Progress", "GitHub"). */
  detail?: string;
  /** The lane, for a `move`. Done is the archive. */
  to?: Lane;
  label: string;
  href?: string;
  disabled?: boolean;
  whyNot?: string;
  dividerBefore?: boolean;
}

export interface CardActionPlan {
  /** The flat button beside the menu -- Open the card, the one that goes somewhere in the app. */
  primary?: CardActionSpec;
  secondary: CardActionSpec[];
}

export type ActionCard = Pick<
  PromptInfo,
  "status" | "linked" | "ado_url" | "pr_url" | "billable"
> & { commits?: number };

export interface CardActionContext {
  /** `/env` ado.enabled -- an older agent that does not say reads as on. */
  adoEnabled: boolean;
  /** `/env` tracker -- names WHOSE page the primary opens (the owner:
   *  the tooltip said ADO while the link went to the GitHub issue). */
  tracker?: string;
  /** The prefix the verbs are typed with on this machine, from `/env`. */
  cliPrefix: string;
  /** The org's word for a lane; the contract's word when omitted. */
  laneLabel?: (status: string) => string;
  /** `/env` features.organize: whether a card can make a reminder about itself. */
  organize?: boolean;
}

/** The organize module's item on a card's menu. */
export const REMIND_LABEL = CARD_MOVES.remind.label();

/** The billable toggle: the opposite of what the card says now. */
function billableMove(card: Pick<PromptInfo, "billable">): RowMove {
  return card.billable ? CARD_MOVES.markNotBillable : CARD_MOVES.makeBillable;
}

/** The billable toggle's words: the opposite of what the card says now. */
export function billableActionLabel(card: Pick<PromptInfo, "billable">): string {
  return billableMove(card).label();
}

/** One spec, its label drawn from the move it names. */
function spec(
  id: CardActionId,
  move: RowMove,
  rest: Omit<CardActionSpec, "id" | "move" | "label"> = {},
): CardActionSpec {
  return { id, move, label: move.label(rest.detail), ...rest };
}

/** The reason Create PR is not available yet -- "" when it is, or when it is absent. */
export function whyNotCreatePR(card: ActionCard, ctx: CardActionContext): string {
  if (card.pr_url) return "It already has a pull request -- its review is the next step.";
  const commits = card.commits ?? (card.status === STATUS.active ? 0 : 1);
  if (commits === 0) {
    return `No commits recorded on the card -- thread them with ${ctx.cliPrefix}ThreadHash first.`;
  }
  return "";
}

export function cardActions(card: ActionCard, ctx: CardActionContext): CardActionPlan {
  const label = ctx.laneLabel ?? ((s: string) => s);
  const ado = ctx.adoEnabled && card.linked && !!card.ado_url;
  const moves = legalMoves(card.status, ctx.tracker);

  // Done is the archive: its lane is the archive move, in the vocabulary's
  // word, with the org's name for the lane after it.
  const lane = (to: Lane, rest: Omit<CardActionSpec, "id" | "move" | "label"> = {}) =>
    to === STATUS.done
      ? spec("move", ROW.archive, { to, detail: `(move to ${label(to)})`, ...rest })
      : spec("move", ROW.move, { to, detail: label(to), ...rest });
  const lanes: CardActionSpec[] = lanesFor(ctx.tracker)
    .filter((to) => to !== card.status)
    .map((to) =>
      moves.includes(to)
        ? lane(to)
        : lane(to, { disabled: true, whyNot: whyNotAMove(card.status, to) }),
    );

  const secondary: CardActionSpec[] = [...lanes];

  if (ado && card.status !== STATUS.done) {
    const whyNot = whyNotCreatePR(card, ctx);
    secondary.push(
      spec("create-pr", CARD_MOVES.createPr, whyNot ? { disabled: true, whyNot } : {}),
    );
  }
  secondary.push(spec("billable", billableMove(card)));
  if (card.status !== STATUS.done) {
    secondary.push(spec("milestone", CARD_MOVES.planMilestone));
    secondary.push(spec("sprint", CARD_MOVES.planSprint));
    secondary.push(spec("tags", CARD_MOVES.tag));
  }
  if (ctx.organize) secondary.push(spec("remind", CARD_MOVES.remind));
  // The lanes are one group, what you do WITH the card is the other.
  if (lanes.length > 0 && secondary.length > lanes.length) {
    secondary[lanes.length] = { ...secondary[lanes.length], dividerBefore: true };
  }
  // The external link last, always (shared/CardActions draws its divider).
  if (ado) {
    secondary.push(
      spec("open-ado", ROW.external, {
        detail: trackerName(ctx.tracker) || trackerName("ado"),
        href: card.ado_url!,
      }),
    );
  }

  return {
    // The one exposed action goes somewhere in the app: the card's own page.
    primary: spec("open-card", ROW.open, { detail: "the card" }),
    secondary,
  };
}
