/**
 * A growth item's moves, the same on its row and on its page: Complete, for a
 * goal that is not complete yet, and Archive, either way -- a complete goal
 * still has to be put away. Both are words from the row vocabulary
 * (`shared/CardActions`), and both run `NewGrowth` through the bridge.
 *
 * "Complete" is decided by the status the agent already derives from the file
 * (agent/growth/growth.py; the table in docs/hub/growth.md) -- nothing here
 * reads the file again. A training or a presentation reads its outcome from
 * other lines, so it is offered Archive only.
 */
import { useState } from "react";
import { CardActions, ROW } from "../../shared/CardActions";
import type { CardAction } from "../../shared/CardActions";
import { RetireGoalDialog } from "./RetireGoal";
import { CompleteGoalDialog } from "./CompleteGoal";

export interface GoalActionsItem {
  filename: string;
  title: string;
  /** "goal" | "training" | "presentation"; the detail route serves it as a string. */
  type: string;
  /** The derived status: "new" | "active" | "complete". */
  status: string;
}

/** Complete is offered to a goal the agent does not already read as complete. */
export function canComplete(item: Pick<GoalActionsItem, "type" | "status">): boolean {
  return item.type === "goal" && item.status !== "complete";
}

interface Props {
  item: GoalActionsItem;
  /** The row's flat button (Open); the page has none. */
  primaryAction?: CardAction;
  onArchived?: () => void;
}

export function GoalActions({ item, primaryAction, onArchived }: Props) {
  const [archiveOpen, setArchiveOpen] = useState(false);
  const [completeOpen, setCompleteOpen] = useState(false);

  // Archive: the vocabulary's word for the move to the archive. The verb
  // behind it is `NewGrowth -Close`; Complete's is `NewGrowth -Complete`.
  const moves = [
    ...(canComplete(item) ? [ROW.complete.action({ onClick: () => setCompleteOpen(true) })] : []),
    ROW.archive.action({ onClick: () => setArchiveOpen(true) }),
  ];

  return (
    <>
      <CardActions
        primaryAction={primaryAction}
        menuLabel={`Actions for ${item.title}`}
        secondaryActions={moves}
      />
      <RetireGoalDialog
        filename={item.filename}
        title={item.title}
        open={archiveOpen}
        onOpenChange={setArchiveOpen}
        onRetired={onArchived}
      />
      <CompleteGoalDialog
        filename={item.filename}
        title={item.title}
        open={completeOpen}
        onOpenChange={setCompleteOpen}
      />
    </>
  );
}
