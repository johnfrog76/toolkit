import { CardActions } from "../../shared/CardActions";
import type { CardAction } from "../../shared/CardActions";
import { useGetEnvQuery } from "../../shell/api";
import type { PromptInfo } from "./api.ado";
import { cardActions } from "./cardActions";
import type { CardActionContext, CardActionSpec } from "./cardActions";
import { useLaneLabel } from "./laneNames";
import type { Lane } from "./legalMoves";

// The ONE renderer of a card's actions -- the list's row and the board's card
// both draw this. It decides nothing: cardActions.ts says what is offered,
// disabled and why, and which move each one is; this gives each answer its
// handler and hands it to shared/CardActions, which draws the move's word,
// icon and tooltip.

/** What the action model needs from `/env`: is Azure DevOps in use, and the prefix. */
export function useCardActionContext(): CardActionContext {
  const { data: env } = useGetEnvQuery();
  const laneLabel = useLaneLabel();
  return {
    // An older agent that does not say reads as on -- what it always was.
    adoEnabled: env?.ado?.enabled ?? true,
    tracker: env?.tracker,
    cliPrefix: env?.cliPrefix ?? "",
    laneLabel,
    organize: Boolean(env?.features?.organize),
  };
}

export interface CardActionHandlers {
  onOpenCard: () => void;
  /** Done is the archive: the view asks first, as it always has. */
  onMove: (to: Lane) => void;
  onToggleBillable: () => void;
  onCreatePR: () => void;
  /** Remind me about this -- offered only while organize is on (cardActions.ts). */
  onRemind?: () => void;
  /** Land -- offered on every Code Review card (cardActions.ts). */
  onLand?: () => void;
}

function toCardAction(spec: CardActionSpec, h: CardActionHandlers): CardAction {
  const onClick =
    spec.id === "open-card"
      ? h.onOpenCard
      : spec.id === "billable"
        ? h.onToggleBillable
        : spec.id === "create-pr"
          ? h.onCreatePR
          : spec.id === "remind"
            ? h.onRemind
            : spec.id === "land"
              ? h.onLand
              : spec.id === "move" && spec.to
                ? () => h.onMove(spec.to!)
                : undefined;
  // The word, icon and tooltip are the move's (shared/CardActions ROW, or the
  // card's own CARD_MOVES); nothing here names an action.
  return spec.move.action({
    detail: spec.detail,
    href: spec.href,
    disabled: spec.disabled,
    whyNot: spec.whyNot,
    dividerBefore: spec.dividerBefore,
    onClick: spec.disabled ? undefined : onClick,
  });
}

interface CardActionMenuProps extends CardActionHandlers {
  card: PromptInfo;
  context: CardActionContext;
  /** A write on this card is running. */
  busy?: boolean;
}

export function CardActionMenu({ card, context, busy, ...handlers }: CardActionMenuProps) {
  const plan = cardActions(card, context);
  const name = card.name || card.title || card.file;
  return (
    <CardActions
      primaryAction={plan.primary ? toCardAction(plan.primary, handlers) : undefined}
      secondaryActions={plan.secondary.map((s) => toCardAction(s, handlers))}
      forceOverflow
      menuLabel={`Actions for ${name}`}
      busy={busy}
    />
  );
}
