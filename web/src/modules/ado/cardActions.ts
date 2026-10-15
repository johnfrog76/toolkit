import { STATUS } from "../../shell/consts";
import type { PromptInfo } from "./api.ado";
import { LANES, legalMoves, whyNotAMove } from "./legalMoves";
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
//   absent    the action cannot apply to this card at all -- Open in ADO on a
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

export type CardActionId = "open-ado" | "open-card" | "move" | "billable" | "create-pr" | "remind";

export interface CardActionSpec {
  id: CardActionId;
  /** The lane, for a `move`. Done is the archive. */
  to?: Lane;
  label: string;
  href?: string;
  disabled?: boolean;
  whyNot?: string;
  dividerBefore?: boolean;
}

export interface CardActionPlan {
  /** The flat button beside the menu -- the card's link into Azure DevOps. */
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
export const REMIND_LABEL = "Remind me about this";

/** The billable toggle's words: the opposite of what the card says now. */
export function billableActionLabel(card: Pick<PromptInfo, "billable">): string {
  return card.billable ? "Mark not billable" : "Make billable again";
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
  const moves = legalMoves(card.status);

  const lanes: CardActionSpec[] = LANES.filter((lane) => lane !== card.status).map((lane) =>
    moves.includes(lane)
      ? {
          id: "move",
          to: lane,
          label: `Move to ${label(lane)}${lane === STATUS.done ? " (archive)" : ""}`,
        }
      : {
          id: "move",
          to: lane,
          label: label(lane),
          disabled: true,
          whyNot: whyNotAMove(card.status, lane),
        },
  );

  const secondary: CardActionSpec[] = [...lanes];

  if (ado && card.status !== STATUS.done) {
    const whyNot = whyNotCreatePR(card, ctx);
    secondary.push({
      id: "create-pr",
      label: "Create PR",
      ...(whyNot ? { disabled: true, whyNot } : {}),
    });
  }
  secondary.push({ id: "billable", label: billableActionLabel(card) });
  secondary.push({ id: "open-card", label: "Open the card" });
  if (ctx.organize) secondary.push({ id: "remind", label: REMIND_LABEL });
  // The lanes are one group, what you do WITH the card is the other.
  if (lanes.length > 0 && secondary.length > lanes.length) {
    secondary[lanes.length] = { ...secondary[lanes.length], dividerBefore: true };
  }

  return {
    primary: ado
      ? {
          id: "open-ado",
          label: ctx.tracker === "github" ? "Open on GitHub" : "Open in ADO",
          href: card.ado_url!,
        }
      : undefined,
    secondary,
  };
}
