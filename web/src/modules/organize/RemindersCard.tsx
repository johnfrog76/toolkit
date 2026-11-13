/**
 * The Reminders panel -- the Organize add-on's first surface.
 *
 * A list panel: the count in the header, the bucket chips with their counts (a
 * filter over ONE list, not three stacked lists), a card item per reminder with
 * its bucket beside the title, its source tag and its due date in words, and
 * the item's actions -- Archive exposed, the snoozes and Edit in its menu --
 * the pager in the foot, and the foot's + for a quick add.
 *
 * A ref the agent resolved to a card is named on the item's second line, and a
 * card in current/ opens from the menu; any other ref is part of the tag, as
 * written (docs/modules/organize.md, "A ref that names a card").
 *
 * Every write is one of the CLI's two verbs through the bridge: Snooze, Edit
 * and Archive run `Reminders`, the + runs `NewReminder` (NewReminderDialog.tsx). Edit corrects the entry
 * (EditReminderDialog.tsx); Snooze moves it by a fixed step and stays the one-click shortcut. A stated
 * refusal comes back as `status: error` with the verb's own sentence and is shown as a refusal. The
 * bucket is the agent's; this panel only filters and labels by it.
 */
import { useEffect, useState } from "react";
import { useLocation, useNavigate } from "react-router";
import { AlertRegular, EditRegular, SnoozeRegular } from "@fluentui/react-icons";
import { HubSyncLine } from "../ado/HubSyncLine";
import { ROW, defineRowMoves } from "../../shared/CardActions";
import { usePersistedValue } from "../../shared/usePersistedState";
import { dueLabel } from "../../utility/dates";
import { FOLDERS, REMINDERS } from "../../shell/consts";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { FilterChip } from "../../shell/kinds/ListPanel";
import type { CardItemData } from "../../shell/CardItem";
import {
  buildReminderArchiveParams,
  buildReminderSnoozeParams,
  commandResultMessage,
} from "../ado/cliBridge";
import type { CommandResponse } from "../ado/api.ado";
import { cardPath } from "../ado/paths";
import { useGetRemindersQuery, useRunRemindersMutation } from "./api.organize";
import type { Reminder, ReminderBucket } from "./api.organize";
import { REMINDERS_BUCKET_STATE } from "./paths";
import { EditReminderDialog } from "./EditReminderDialog";
import { NewReminderDialog } from "./NewReminderDialog";

type BucketFilter = "all" | ReminderBucket;

const BUCKET_LABEL: Record<ReminderBucket, string> = {
  overdue: "Overdue",
  today: "Today",
  upcoming: "Upcoming",
};

const BUCKET_COLOUR: Record<ReminderBucket, "danger" | "warning" | "informative"> = {
  overdue: "danger",
  today: "warning",
  upcoming: "informative",
};

/** What each snooze word means, in the words a person reads in the menu. The
 *  arithmetic is the CLI's (Scripts/Reminder-Rules.ps1); this only labels it. */
const SNOOZE_LABEL: Record<(typeof REMINDERS.snooze)[number], string> = {
  "1h": "In an hour",
  tomorrow: "Tomorrow, 9:00 AM",
  nextweek: "Next Monday, 9:00 AM",
};

/** A reminder's own moves, on no other record. */
const REMINDER_MOVES = defineRowMoves("reminder", {
  snooze: { word: "Snooze:", icon: SnoozeRegular },
  edit: { word: "Edit", icon: EditRegular },
});

interface Outcome {
  ok: boolean;
  text: string;
}

function outcomeOf(result: CommandResponse, done: string): Outcome {
  return { ok: result.status === "success", text: commandResultMessage(result, done) };
}

export function RemindersCard() {
  const navigate = useNavigate();
  const { data, isLoading, isError, isFetching, refetch } = useGetRemindersQuery();
  const [runReminders, { isLoading: acting }] = useRunRemindersMutation();
  const { value: storedFilter, setValue: setStoredFilter } = usePersistedValue(
    "organize.reminders.bucket",
    "all",
    (v) => v === "all" || (REMINDERS.buckets as string[]).includes(v),
  );
  const filter = storedFilter as BucketFilter;
  // Arriving from the header bell: the router state names a bucket, and it
  // becomes the remembered filter -- keyed on the navigation, so a second click
  // while already here applies it again.
  const location = useLocation();
  const askedFor = (location.state as Record<string, unknown> | null)?.[REMINDERS_BUCKET_STATE];
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [addOpen, setAddOpen] = useState(false);
  // The reminder the Edit dialog is open on.
  const [editing, setEditing] = useState<Reminder | null>(null);

  const all = data?.items ?? [];
  const shown = filter === "all" ? all : all.filter((r) => r.bucket === filter);

  useEffect(() => {
    if (
      typeof askedFor === "string" &&
      (REMINDERS.buckets as readonly string[]).includes(askedFor)
    ) {
      setStoredFilter(askedFor);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.key]);

  const act = async (params: string[], done: string) => {
    setOutcome(null);
    try {
      const result = await runReminders({ params }).unwrap();
      setOutcome(outcomeOf(result, done));
    } catch {
      setOutcome({ ok: false, text: "Could not reach the agent. Nothing was changed." });
    }
  };

  const counts = data?.buckets;
  const chips: FilterChip[] = [
    {
      id: "all",
      label: "All",
      count: all.length,
      active: filter === "all",
      onSelect: () => setStoredFilter("all"),
    },
    ...REMINDERS.buckets.map((b) => ({
      id: b,
      label: BUCKET_LABEL[b],
      count: counts?.[b] ?? 0,
      active: filter === b,
      onSelect: () => setStoredFilter(b),
    })),
  ];

  const toItem = (item: Reminder): CardItemData => {
    const due = dueLabel(item.due);
    // A ref that names a card is drawn as the card; any other ref stays in the tag.
    const card = item.card ?? null;
    const tag = item.ref && !card ? `${item.source} ${item.ref}` : item.source;
    const cardWords = card ? `${card.id} ${card.title}` : "";
    // The card page reads current/, so an archived card is named, not opened.
    const current = card !== null && card.folder === FOLDERS.current;
    return {
      id: item.filename,
      title: item.title,
      badges: [{ label: BUCKET_LABEL[item.bucket], color: BUCKET_COLOUR[item.bucket] }],
      description: card ? (current ? cardWords : `${cardWords} (done)`) : undefined,
      meta: [
        ...(tag
          ? [
              {
                badge: {
                  label: tag,
                  color: "informative" as const,
                  appearance: "outline" as const,
                },
              },
            ]
          : []),
        { text: due ? `Due: ${due}` : "No due date" },
      ],
      // One exposed action -- Archive, the act a reminder exists for
      // (`Reminders <id> -Archive`), in the vocabulary's word for the move to
      // the archive; a reminder has no page to go to -- and the menu for the
      // rest: the card it names, the snoozes (the same one choice away they
      // always were), then Edit.
      primary: ROW.archive.action({
        disabled: acting,
        onClick: () => act(buildReminderArchiveParams({ id: item.id }), "Done."),
      }),
      menu: [
        ...(card && current
          ? [ROW.open.action({ detail: "the card", onClick: () => navigate(cardPath(card.file)) })]
          : []),
        ...REMINDERS.snooze.map((word) =>
          REMINDER_MOVES.snooze.action({
            detail: SNOOZE_LABEL[word],
            onClick: () => act(buildReminderSnoozeParams({ id: item.id, word }), "Snoozed."),
          }),
        ),
        REMINDER_MOVES.edit.action({ dividerBefore: true, onClick: () => setEditing(item) }),
      ],
      busy: acting,
    };
  };

  const icon = <AlertRegular />;
  return (
    <>
      <ListPanel
        title="Reminders"
        info="Notes to yourself, each with a due date or none. A reminder is one file in your hub; Archive puts it away when it is done."
        items={shown}
        item={toItem}
        loading={isLoading ? { label: "Loading reminders..." } : undefined}
        empty={
          isError
            ? {
                icon,
                tone: "error",
                title: "Could not load your reminders",
                detail: "The agent did not answer. Nothing was read.",
              }
            : {
                icon,
                title: "Nothing to remember",
                detail: "A note to yourself with a due date. The + below adds one.",
              }
        }
        filteredEmpty={
          filter !== "all" && !isError
            ? {
                icon,
                tone: "filtered",
                title: `Nothing ${BUCKET_LABEL[filter].toLowerCase()}`,
                detail: "Others are hidden by the filter.",
              }
            : undefined
        }
        filters={[{ label: "Filter reminders", chips }]}
        refresh={{ onClick: refetch, isFetching }}
        count={all.length}
        countLabel={`${all.length} open reminders`}
        status={
          outcome
            ? {
                tone: outcome.ok ? "success" : "error",
                text: outcome.text,
                onDismiss: () => setOutcome(null),
              }
            : undefined
        }
        create={{ label: "New Reminder", onClick: () => setAddOpen(true) }}
        footNote={<HubSyncLine />}
      />

      {/* Mounted only while open, so each opening starts from empty fields. */}
      {addOpen && (
        <NewReminderDialog
          open
          onClose={() => setAddOpen(false)}
          onAdded={(result) => {
            setAddOpen(false);
            setOutcome(outcomeOf(result, "Added."));
          }}
        />
      )}
      {editing && (
        <EditReminderDialog
          editing={editing}
          onClose={() => setEditing(null)}
          onSaved={(result) => {
            setEditing(null);
            setOutcome(outcomeOf(result, "Updated."));
          }}
        />
      )}
    </>
  );
}
