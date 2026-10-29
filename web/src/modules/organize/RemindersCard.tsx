/**
 * The Reminders card -- the Organize add-on's first surface.
 *
 * One card in the standard half-width column, built from the parts every card
 * here uses: the count badge in the header, the bucket chips with their counts
 * (a filter over ONE list, not three stacked lists), a row per reminder with its
 * source tag, its due date in words and the house row's actions -- Done exposed,
 * the snoozes and Edit in its menu -- the footer pager, and the footer +
 * for a quick add.
 *
 * A ref the agent resolved to a card is a link to that card's page; any other
 * ref is part of the tag, as written (docs/modules/organize.md, "A ref that
 * names a card").
 *
 * Every write is one of the CLI's two verbs through the bridge: Snooze, Edit
 * and Done run `Reminders`, the + runs `NewReminder` (NewReminderDialog.tsx). Edit corrects the entry;
 * Snooze moves it by a fixed step and stays the one-click shortcut. A stated refusal comes back as
 * `status: error` with the verb's own sentence and is shown as a refusal. The
 * bucket is the agent's; this card only filters and labels by it.
 */
import { useEffect, useState } from "react";
import { useLocation, useNavigate } from "react-router";
import {
  Badge,
  Body1Strong,
  Button,
  Caption1,
  Card,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger,
  Field,
  Input,
  Link,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { AlertRegular, EditRegular, SnoozeRegular } from "@fluentui/react-icons";
import { PageCard } from "../../shared/PageCard";
import { CreateButton } from "../../shared/CreateButton";
import { FilterBadge } from "../../shared/FilterBadge";
import { useFilterRowStyles, useListRowStyles } from "../../shared/listRowStyles";
import { EmptyState } from "../../shared/EmptyState";
import { StatusMessage } from "../../shared/StatusMessage";
import { RefreshButton } from "../../shared/RefreshButton";
import { Pagination } from "../../shared/Pagination";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { CardActions, ROW, defineRowMoves } from "../../shared/CardActions";
import { usePagination } from "../../hooks/usePagination";
import { usePersistedValue } from "../../shared/usePersistedState";
import { dueLabel } from "../../utility/dates";
import { REMINDERS } from "../../shell/consts";
import {
  buildReminderArchiveParams,
  buildReminderEditParams,
  buildReminderSnoozeParams,
  commandResultMessage,
} from "../ado/cliBridge";
import type { CommandResponse } from "../ado/api.ado";
import { useGetRemindersQuery, useRunRemindersMutation } from "./api.organize";
import type { Reminder, ReminderBucket } from "./api.organize";
import { REMINDERS_BUCKET_STATE } from "./paths";
import { joinDue, splitDue } from "./reminderEntry";
import { NewReminderDialog, REF_HINT, useReminderFieldStyles } from "./NewReminderDialog";
import { cardPath } from "../ado/paths";
import { FOLDERS } from "../../shell/consts";

const PAGE_SIZE = 5;

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

const useStyles = makeStyles({
  rowBody: { flex: 1, minWidth: 0 },
  tags: {
    display: "flex",
    gap: tokens.spacingHorizontalXS,
    alignItems: "center",
    flexWrap: "wrap",
  },
  meta: { marginTop: tokens.spacingVerticalXXS, color: tokens.colorNeutralForeground3 },
  cardRef: { fontSize: tokens.fontSizeBase200 },
});

interface Outcome {
  ok: boolean;
  text: string;
}

function outcomeOf(result: CommandResponse, done: string): Outcome {
  return { ok: result.status === "success", text: commandResultMessage(result, done) };
}

function ReminderRow({
  item,
  busy,
  onSnooze,
  onEdit,
  onDone,
}: {
  item: Reminder;
  busy: boolean;
  onSnooze: (word: string) => void;
  onEdit: () => void;
  onDone: () => void;
}) {
  const own = useStyles();
  const rows = useListRowStyles();
  const styles = { ...own, ...rows };
  const navigate = useNavigate();
  const due = dueLabel(item.due);
  // A ref that names a card is drawn as the card; any other ref stays in the tag.
  const card = item.card ?? null;
  const tag = item.ref && !card ? `${item.source} ${item.ref}` : item.source;
  const cardWords = card ? `${card.id} ${card.title}` : "";
  return (
    <Card className={styles.row} size="small" appearance="outline">
      <div className={styles.rowHeader}>
        <div className={styles.rowBody}>
          <div className={styles.tags}>
            <Badge color={BUCKET_COLOUR[item.bucket]} appearance="tint" size="small">
              {BUCKET_LABEL[item.bucket]}
            </Badge>
            {tag && (
              <Badge color="informative" appearance="outline" size="small">
                {tag}
              </Badge>
            )}
            {/* The card page reads current/, so an archived card is named, not linked. */}
            {card &&
              (card.folder === FOLDERS.current ? (
                <Link
                  className={styles.cardRef}
                  href={cardPath(card.file)}
                  title={card.file}
                  onClick={(e) => {
                    e.preventDefault();
                    navigate(cardPath(card.file));
                  }}
                >
                  {cardWords}
                </Link>
              ) : (
                <Caption1 title={card.file}>{`${cardWords} (done)`}</Caption1>
              ))}
          </div>
          <Body1Strong style={{ display: "block", marginTop: tokens.spacingVerticalXS }}>
            {item.title}
          </Body1Strong>
          <Caption1 className={styles.meta}>{due ? `Due: ${due}` : "No due date"}</Caption1>
        </div>
        {/* The house row: one exposed action -- Archive, the act a
            reminder exists for (`Reminders <id> -Archive`), in the
            vocabulary's word for the move to the archive; there is no page to
            go to -- and the menu for the rest: the snoozes first (the same one
            choice away they always were), then Edit. */}
        <CardActions
          primaryAction={ROW.archive.action({ disabled: busy, onClick: onDone })}
          menuLabel={`Actions for ${item.title}`}
          busy={busy}
          secondaryActions={[
            ...REMINDERS.snooze.map((word) =>
              REMINDER_MOVES.snooze.action({
                detail: SNOOZE_LABEL[word],
                onClick: () => onSnooze(word),
              }),
            ),
            REMINDER_MOVES.edit.action({ dividerBefore: true, onClick: onEdit }),
          ]}
        />
      </div>
    </Card>
  );
}

export function RemindersCard() {
  const own = useStyles();
  const filterRow = useFilterRowStyles();
  const fieldStyles = useReminderFieldStyles();
  const styles = { ...own, ...filterRow, ...fieldStyles };
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
  // The Edit dialog: the reminder it opened on, and the entry as being typed.
  const [editing, setEditing] = useState<Reminder | null>(null);
  const [editTitle, setEditTitle] = useState("");
  const [editDate, setEditDate] = useState("");
  const [editTime, setEditTime] = useState("");
  const [editSource, setEditSource] = useState("");
  const [editRef, setEditRef] = useState("");
  const [editMessage, setEditMessage] = useState<string | null>(null);

  const all = data?.items ?? [];
  const shown = filter === "all" ? all : all.filter((r) => r.bucket === filter);
  const { page, totalPages, pageItems, setPage } = usePagination(shown, PAGE_SIZE);

  const choose = (next: BucketFilter) => {
    setStoredFilter(next);
    setPage(0);
  };

  useEffect(() => {
    if (
      typeof askedFor === "string" &&
      (REMINDERS.buckets as readonly string[]).includes(askedFor)
    ) {
      choose(askedFor as ReminderBucket);
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

  const openEdit = (item: Reminder) => {
    const parts = splitDue(item.due);
    setEditing(item);
    setEditTitle(item.title);
    setEditDate(parts.date);
    setEditTime(parts.time);
    setEditSource(item.source);
    setEditRef(item.ref);
    setEditMessage(null);
  };

  const editParams = editing
    ? buildReminderEditParams({
        id: editing.id,
        was: { title: editing.title, due: editing.due, source: editing.source, ref: editing.ref },
        now: {
          title: editTitle,
          due: joinDue({ date: editDate, time: editTime }),
          source: editSource,
          ref: editRef,
        },
      })
    : null;

  const saveEdit = async () => {
    if (!editParams) return;
    setEditMessage(null);
    try {
      const result = await runReminders({ params: editParams }).unwrap();
      if (result.status === "success") {
        setEditing(null);
        setOutcome(outcomeOf(result, "Updated."));
        return;
      }
      // A refusal stays in the dialog, in the verb's own words.
      setEditMessage(commandResultMessage(result, "Updated."));
    } catch {
      setEditMessage("Could not reach the agent. Nothing was changed.");
    }
  };

  const counts = data?.buckets;
  const chipLabel = (b: ReminderBucket) => BUCKET_LABEL[b];

  return (
    <>
      <PageCard
        scrollable
        loading={isLoading}
        loadingLabel="Loading reminders..."
        headerLeft={<Subtitle2>Reminders</Subtitle2>}
        headerRight={
          <>
            <RefreshButton onClick={refetch} isFetching={isFetching} />
            <Badge
              color="informative"
              appearance="filled"
              size="large"
              aria-label={`${all.length} open reminders`}
            >
              {all.length}
            </Badge>
          </>
        }
        toast={
          outcome ? (
            <StatusMessage
              status={outcome.ok ? "success" : "error"}
              onDismiss={() => setOutcome(null)}
            >
              {outcome.text}
            </StatusMessage>
          ) : undefined
        }
        footerCenter={
          totalPages > 1 ? (
            <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
          ) : undefined
        }
        footerRight={<CreateButton label="New Reminder" onClick={() => setAddOpen(true)} />}
      >
        <div className={styles.chips} role="group" aria-label="Filter reminders">
          <FilterBadge
            label="All"
            count={all.length}
            active={filter === "all"}
            onClick={() => choose("all")}
          />
          {REMINDERS.buckets.map((b) => (
            <FilterBadge
              key={b}
              label={chipLabel(b)}
              count={counts?.[b] ?? 0}
              active={filter === b}
              onClick={() => choose(b)}
            />
          ))}
        </div>
        {shown.length === 0 ? (
          isError ? (
            <EmptyState
              icon={<AlertRegular />}
              tone="error"
              title="Could not load your reminders"
              detail="The agent did not answer. Nothing was read."
            />
          ) : filter === "all" ? (
            <EmptyState
              icon={<AlertRegular />}
              title="Nothing to remember"
              detail="A note to yourself with a due date. The + below adds one."
            />
          ) : (
            <EmptyState
              icon={<AlertRegular />}
              tone="filtered"
              title={`Nothing ${BUCKET_LABEL[filter].toLowerCase()}`}
              detail="Others are hidden by the filter."
            />
          )
        ) : (
          pageItems.map((item) => (
            <ReminderRow
              key={item.filename}
              item={item}
              busy={acting}
              onSnooze={(word) => act(buildReminderSnoozeParams({ id: item.id, word }), "Snoozed.")}
              onEdit={() => openEdit(item)}
              onDone={() => act(buildReminderArchiveParams({ id: item.id }), "Done.")}
            />
          ))
        )}
      </PageCard>

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

      <Dialog
        open={editing !== null}
        onOpenChange={(_e, d) => {
          if (!d.open) setEditing(null);
        }}
      >
        <DialogSurface>
          <DialogBody>
            <DialogTitle action={<DialogDismiss />}>Edit Reminder</DialogTitle>
            <DialogContent>
              <div className={styles.fields}>
                <Field label="What" required>
                  <Input value={editTitle} onChange={(_, d) => setEditTitle(d.value)} />
                </Field>
                {/* A date and an optional time, not one datetime input: a
                    reminder due on a DAY has no time, and one input would
                    have to invent one (reminderEntry.ts). */}
                <div className={styles.pair}>
                  <Field label="Due date" hint="Empty for no due date.">
                    <Input type="date" value={editDate} onChange={(_, d) => setEditDate(d.value)} />
                  </Field>
                  <Field label="Time" hint="Optional. Local time.">
                    <Input
                      type="time"
                      value={editTime}
                      disabled={!editDate}
                      onChange={(_, d) => setEditTime(d.value)}
                    />
                  </Field>
                </div>
                <Field label="Source" required hint="A tag, such as manual, ado or goal.">
                  <Input value={editSource} onChange={(_, d) => setEditSource(d.value)} />
                </Field>
                <Field label="Ref" hint={`${REF_HINT} Empty for none.`}>
                  <Input value={editRef} onChange={(_, d) => setEditRef(d.value)} />
                </Field>
                {editMessage && (
                  <Caption1
                    role="alert"
                    style={{ color: tokens.colorPaletteRedForeground1, whiteSpace: "pre-wrap" }}
                  >
                    {editMessage}
                  </Caption1>
                )}
              </div>
            </DialogContent>
            <DialogActions>
              <DialogTrigger disableButtonEnhancement>
                <Button appearance="secondary">Cancel</Button>
              </DialogTrigger>
              <Button
                appearance="primary"
                onClick={saveEdit}
                disabled={!editParams || !editTitle.trim() || !editSource.trim() || acting}
              >
                {acting ? "Saving…" : "Save"}
              </Button>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>
    </>
  );
}
