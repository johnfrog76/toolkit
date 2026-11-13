/**
 * The Meetings panel: every session in the hub, filtered, paged, and a dialog
 * that scaffolds the next one.
 *
 * It was mounted unconditionally on the growth page, which is how a card for a
 * workflow you had never switched on ended up on your home screen. It now has
 * a route of its own under this module's nav entry, and the module's flag
 * decides whether any of it exists.
 */
import { useState } from "react";
import { useNavigate } from "react-router";
import { EditRegular, PeopleCommunityRegular } from "@fluentui/react-icons";
import { ROW, defineRowMoves } from "../../shared/CardActions";
import { FOLDERS } from "../../shell/consts";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { FilterChip } from "../../shell/kinds/ListPanel";
import type { CardItemData } from "../../shell/CardItem";
import { useGetManagerQuery } from "./api.communication";
import type { ManagerItem } from "./api.communication";
import { CloseMeetingDialog } from "./CloseMeeting";
import { NewMeetingDialog } from "./NewMeetingDialog";
import { oneOnOnePath, sessionPath } from "./paths";
import { stageAfter, stageOf } from "./stages";

type SessionFilter = "all" | "current" | "past" | "archive";

const FILTERS: { id: SessionFilter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "current", label: "Current" },
  { id: "past", label: "Past" },
  { id: "archive", label: "Archive" },
];

/** A meeting's own move, on no other record: the session page, where the notes
 *  are edited and the retro is sent. */
const MEETING_MOVES = defineRowMoves("meeting", {
  edit: { word: "Edit or send", icon: EditRegular },
});

function formatSessionDate(iso: string): string {
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(year, month - 1, day).toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  });
}

// `SessionFilter` is this panel's own vocabulary; `folder` is the agent's, and
// the two folder names are the contract file's (web/src/shell/consts.ts). They
// read alike and are not the same thing -- "past" is a current/ session that
// has reached retro.
function inFilter(item: ManagerItem, filter: SessionFilter): boolean {
  if (filter === "archive") return item.folder === FOLDERS.archive;
  if (filter === "current") return item.folder === FOLDERS.current && item.stage !== "retro";
  if (filter === "past") return item.folder === FOLDERS.current && item.stage === "retro";
  return true;
}

export function OneOnOne() {
  const navigate = useNavigate();
  const { data, isLoading, isFetching, isError, refetch } = useGetManagerQuery();
  const [sessionFilter, setSessionFilter] = useState<SessionFilter>("all");
  const [creating, setCreating] = useState(false);
  // The session Close is asking about.
  const [closing, setClosing] = useState<ManagerItem | null>(null);

  const allItems = data?.items ?? [];
  const shown = allItems.filter((i) => inFilter(i, sessionFilter));

  const chips: FilterChip[] = FILTERS.map((f) => ({
    id: f.id,
    label: f.label,
    count: allItems.filter((i) => inFilter(i, f.id)).length,
    active: sessionFilter === f.id,
    onSelect: () => setSessionFilter(f.id),
  }));

  const toItem = (item: ManagerItem): CardItemData => {
    const stage = stageOf(item.stage);
    const nextStage = stageAfter(item.stage);
    const isClosed = item.folder === FOLDERS.archive;
    const title = `${item.series || "1:1"} — ${formatSessionDate(item.date)}`;
    return {
      id: item.filename,
      title,
      badges: [{ label: stage.label, color: stage.color, appearance: "outline" }],
      // A closed session says so; a complete one is offered Archive in its
      // menu, which runs MeetingAgenda -Close through the bridge -- the verb
      // that moves the file to manager/archive/ AND writes the closed stamp.
      description: isClosed
        ? "Closed"
        : nextStage
          ? `Next up: ${nextStage.label}`
          : "Complete. Archive it to close it and move it to the archive.",
      meta: [{ text: item.filename, title: item.filename, shrink: true }],
      // Two destinations, and both are named: the read view, exposed, and the
      // session page where the notes are edited and the retro is sent.
      primary: ROW.open.action({
        detail: "the meeting",
        onClick: () => navigate(oneOnOnePath(item.filename)),
      }),
      menu: [
        MEETING_MOVES.edit.action({ onClick: () => navigate(sessionPath(item.filename)) }),
        ...(!isClosed && !nextStage
          ? [ROW.archive.action({ onClick: () => setClosing(item) })]
          : []),
      ],
    };
  };

  const icon = <PeopleCommunityRegular />;
  return (
    <>
      <ListPanel
        title="Meetings"
        info="Your recurring meetings, one file a session: plan it, prepare it, write the retro, then archive it. Each new one carries forward what the last left open."
        items={shown}
        item={toItem}
        loading={isLoading ? { label: "Loading meetings..." } : undefined}
        // Failed is not empty: "No meetings yet" for a request that was never
        // answered is the untruth Daily had.
        empty={
          isError
            ? {
                icon,
                tone: "error",
                title: "Could not load your meetings",
                detail: "The agent did not answer. Nothing was read.",
              }
            : {
                icon,
                title: "No meetings yet",
                detail:
                  "Plan your next 1:1 with the + below. It carries forward what the last one left open.",
              }
        }
        filteredEmpty={
          sessionFilter !== "all" && !isError
            ? {
                icon,
                tone: "filtered",
                title: `No ${sessionFilter} meetings`,
                detail: "Others are hidden by the filter.",
              }
            : undefined
        }
        filters={[{ label: "Filter meetings", chips }]}
        refresh={{ onClick: refetch, isFetching }}
        count={allItems.length}
        countLabel={`${allItems.length} meetings`}
        create={{ label: "New 1:1", onClick: () => setCreating(true) }}
      />

      {creating && <NewMeetingDialog onClose={() => setCreating(false)} />}
      {closing && (
        <CloseMeetingDialog
          filename={closing.filename}
          date={closing.date}
          series={closing.series}
          onClose={() => setClosing(null)}
        />
      )}
    </>
  );
}
