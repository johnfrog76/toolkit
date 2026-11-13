import { useState } from "react";
import { useNavigate } from "react-router";
import { TargetArrowRegular } from "@fluentui/react-icons";
import { ROW } from "../../shared/CardActions";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { FilterChip } from "../../shell/kinds/ListPanel";
import type { CardItemData, MetaItem } from "../../shell/CardItem";
import { useGetGrowthQuery } from "./api.growth";
import type { GrowthItem, GrowthStatus } from "./api.growth";
import { canComplete } from "./GoalActions";
import { CompleteGoalDialog } from "./CompleteGoal";
import { RetireGoalDialog } from "./RetireGoal";
import { NewGrowthDialog } from "./NewGrowthDialog";
import { TYPE_COLOUR, TYPE_LABEL, goalPath } from "./growthLabels";

type StatusFilter = "all" | GrowthStatus;

const STATUSES: GrowthStatus[] = ["new", "active", "complete"];
const STATUS_LABEL: Record<GrowthStatus, string> = {
  new: "New",
  active: "Active",
  complete: "Complete",
};

// The agent falls back to the file's own stem when no heading parses (a file
// a person made by hand, or a template with the title line removed), and
// that fallback is pinned behaviour on that side (Tests/test_growth.py: "the
// stem, as for a generated file with no title"). A raw slug read as a title
// is a file fact, not a name -- Goals.test.ts pins this the other way, from
// the web side.
export function isUntitledGrowthItem(title: string, filename: string): boolean {
  return title === filename.replace(/\.md$/, "");
}

// The Goals panel: every growth item in growth/current/ -- a goal, a training,
// a talk -- each a card item whose one exposed action is its page and whose
// menu holds its moves (Complete for a goal that is not complete yet, Archive
// either way). The status chips split the one list.
export function Goals() {
  const navigate = useNavigate();
  const { data, isLoading, isFetching, isError, refetch } = useGetGrowthQuery();
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [creating, setCreating] = useState(false);
  // The item a move's dialog is open on.
  const [completing, setCompleting] = useState<GrowthItem | null>(null);
  const [archiving, setArchiving] = useState<GrowthItem | null>(null);

  const allItems = data?.items ?? [];
  const shown =
    statusFilter === "all" ? allItems : allItems.filter((i) => i.status === statusFilter);

  const chips: FilterChip[] = [
    {
      id: "all",
      label: "All",
      count: allItems.length,
      active: statusFilter === "all",
      onSelect: () => setStatusFilter("all"),
    },
    ...STATUSES.map((s) => ({
      id: s,
      label: STATUS_LABEL[s],
      count: allItems.filter((i) => i.status === s).length,
      active: statusFilter === s,
      onSelect: () => setStatusFilter(s),
    })),
  ];

  const toItem = (item: GrowthItem): CardItemData => {
    const untitled = isUntitledGrowthItem(item.title, item.filename);
    const title = untitled ? `Untitled ${TYPE_LABEL[item.type]}` : item.title;
    const training = item.type === "training";
    // The description is the item's facts as the file has them: who gives a
    // training and how long it is, then its dates.
    const facts = [
      training && item.provider ? item.provider : null,
      training && item.hours && item.hours !== "TBD" ? `${item.hours}h` : null,
      item.date || null,
    ].filter((fact): fact is string => fact !== null);
    const meta: MetaItem[] = [
      {
        badge: {
          label: TYPE_LABEL[item.type],
          color: TYPE_COLOUR[item.type],
          appearance: "outline",
        },
      },
    ];
    if (item.due_date) meta.push({ text: `Due: ${item.due_date}` });
    // A file with no title of its own is named by its file.
    if (untitled) meta.push({ text: item.filename, title: item.filename, shrink: true });
    return {
      id: item.filename,
      title,
      name: item.title,
      description: facts.length > 0 ? facts.join(" · ") : undefined,
      badges: [
        {
          label: STATUS_LABEL[item.status],
          color: item.status === "new" ? "important" : "subtle",
        },
      ],
      meta,
      primary: ROW.open.action({
        detail: "the goal",
        onClick: () => navigate(goalPath(item.filename)),
      }),
      menu: [
        ...(canComplete(item) ? [ROW.complete.action({ onClick: () => setCompleting(item) })] : []),
        ROW.archive.action({ onClick: () => setArchiving(item) }),
      ],
    };
  };

  const icon = <TargetArrowRegular />;
  return (
    <>
      <ListPanel
        title="Goals"
        info="What you are growing into: a goal, a course, a talk you are preparing. Each is one file in your hub."
        items={shown}
        item={toItem}
        loading={isLoading ? { label: "Loading goals..." } : undefined}
        empty={
          isError
            ? {
                icon,
                tone: "error",
                title: "Could not load your goals",
                detail: "The agent did not answer. Nothing was read.",
              }
            : {
                icon,
                title: "No goals yet",
                detail: "A goal, a course or a talk you are preparing. The + below starts one.",
              }
        }
        filteredEmpty={
          statusFilter !== "all" && !isError
            ? {
                icon,
                tone: "filtered",
                title: `No ${statusFilter} goals`,
                detail: "Others are hidden by the filter.",
              }
            : undefined
        }
        filters={[{ label: "Filter goals", chips }]}
        refresh={{ onClick: refetch, isFetching }}
        count={allItems.length}
        countLabel={`${allItems.length} growth items`}
        create={{ label: "New Growth Item", onClick: () => setCreating(true) }}
      />

      {creating && (
        <NewGrowthDialog
          existing={allItems.map((i) => i.filename)}
          onClose={() => setCreating(false)}
        />
      )}
      {completing && (
        <CompleteGoalDialog
          filename={completing.filename}
          title={completing.title}
          open
          onOpenChange={(open) => {
            if (!open) setCompleting(null);
          }}
        />
      )}
      {archiving && (
        <RetireGoalDialog
          filename={archiving.filename}
          title={archiving.title}
          open
          onOpenChange={(open) => {
            if (!open) setArchiving(null);
          }}
        />
      )}
    </>
  );
}
