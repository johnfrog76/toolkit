/**
 * The 1:1 Workflow card: every session in the hub, filtered, paged, and a
 * dialog that scaffolds the next one.
 *
 * It was mounted unconditionally on the growth page, which is how a card for a
 * workflow you had never switched on ended up on your home screen. It now has
 * a route of its own under this module's nav entry, and the module's flag
 * decides whether any of it exists.
 */
import { useState, useEffect } from "react";
import { useNavigate } from "react-router";
import {
  Body1Strong,
  Caption1,
  Badge,
  Link,
  Button,
  Card,
  Input,
  Subtitle2,
  Dropdown,
  Option,
  Dialog,
  DialogSurface,
  DialogBody,
  DialogTitle,
  DialogContent,
  DialogActions,
  DialogTrigger,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { ArrowRightRegular, EditRegular } from "@fluentui/react-icons";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { Pagination } from "../../shared/Pagination";
import { usePagination } from "../../hooks/usePagination";
import { RefreshButton } from "../../shared/RefreshButton";
import { PageCard } from "../../shared/PageCard";
import { CreateButton } from "../../shared/CreateButton";
import { useGetManagerQuery, useCreateManagerSessionMutation } from "./api.communication";
import { oneOnOnePath, sessionPath } from "./paths";
import type { ManagerItem } from "./api.communication";
import { FOLDERS } from "../../shell/consts";
import { CloseMeetingButton } from "./CloseMeeting";
import { stageAfter, stageOf } from "./stages";
import { PeopleCommunityRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { nextWeekday } from "../../utility/dates";

const PAGE_SIZE = 4;
type SessionFilter = "all" | "current" | "past" | "archive";

const HOURS = Array.from({ length: 12 }, (_, i) => String(i + 1));

const MINUTES = [
  { value: "0", label: "00" },
  { value: "15", label: "15" },
  { value: "30", label: "30" },
  { value: "45", label: "45" },
];

function nextThursday(): string {
  return nextWeekday(4);
}

function formatSessionDate(iso: string): string {
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(year, month - 1, day).toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  });
}

const useStyles = makeStyles({
  itemCard: {
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
  },
  itemRow: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalS,
  },
  itemBody: {
    flex: 1,
    minWidth: 0,
  },
  itemHeading: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalXS,
  },
  itemActions: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalXS,
  },
  dialogFields: {
    display: "flex",
    flexDirection: "column" as const,
    gap: tokens.spacingVerticalM,
    paddingTop: tokens.spacingVerticalS,
  },
  timeRow: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    alignItems: "center",
  },
});

function SessionRow({ item }: { item: ManagerItem }) {
  const styles = useStyles();
  const navigate = useNavigate();
  const stage = stageOf(item.stage);
  const nextStage = stageAfter(item.stage);
  const isClosed = item.folder === FOLDERS.archive;

  return (
    <Card className={styles.itemCard} size="small" appearance="outline">
      <div className={styles.itemRow}>
        <div className={styles.itemBody}>
          <div className={styles.itemHeading}>
            <Badge color={stage.color} appearance="outline" size="small">
              {stage.label}
            </Badge>
            <Body1Strong>
              {item.series || "1:1"} — {formatSessionDate(item.date)}
            </Body1Strong>
          </div>
          <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
            {/* A closed session says so; a complete one is offered the Close
                button beside it, which runs MeetingAgenda -Close through the
                bridge -- the verb that moves the file to manager/archive/ AND
                writes the closed stamp. This line used to name the CLI
                command instead, and the last step of the flow needed a terminal. */}
            {isClosed
              ? "Closed"
              : nextStage
                ? `Next up: ${nextStage.label}`
                : "Complete — close it to move it to the archive"}
          </Caption1>
        </div>
        <div className={styles.itemActions}>
          {!isClosed && !nextStage && (
            <CloseMeetingButton
              compact
              filename={item.filename}
              date={item.date}
              series={item.series}
            />
          )}
          {/* Two destinations, and both are named: the read view, and the session
              page where the notes are edited and the retro is sent.
              Nothing in the UI once led to the second one -- the send
              button was reachable by typing its URL. */}
          <Button
            icon={<EditRegular />}
            size="small"
            appearance="subtle"
            title="Edit / send"
            aria-label="Edit / send"
            onClick={() => navigate(sessionPath(item.filename))}
          />
          <Button
            icon={<ArrowRightRegular />}
            size="small"
            appearance="subtle"
            title="View details"
            aria-label="View details"
            onClick={() => navigate(oneOnOnePath(item.filename))}
          />
        </div>
      </div>
    </Card>
  );
}

export function OneOnOne() {
  const styles = useStyles();
  const navigate = useNavigate();
  const { data, isLoading, isFetching, isError, refetch } = useGetManagerQuery();
  const [createSession, { isLoading: creating }] = useCreateManagerSessionMutation();
  const [sessionFilter, setSessionFilter] = useState<SessionFilter>("all");
  const [dialogOpen, setDialogOpen] = useState(false);
  const [newDate, setNewDate] = useState(nextThursday);
  const [newHour, setNewHour] = useState("10");
  const [newMinute, setNewMinute] = useState("0");
  const [newAmPm, setNewAmPm] = useState("AM");

  const allItems = data?.items ?? [];
  // `sessionFilter` is this card's own vocabulary; `i.folder` is the agent's, and
  // the two folder names are the contract file's (web/src/shell/consts.ts). They
  // read alike and are not the same thing -- "past" is a current/ session that
  // has reached retro.
  const filtered = allItems.filter((i) => {
    if (sessionFilter === "all") return true;
    if (sessionFilter === "archive") return i.folder === FOLDERS.archive;
    if (sessionFilter === "current") return i.folder === FOLDERS.current && i.stage !== "retro";
    if (sessionFilter === "past") return i.folder === FOLDERS.current && i.stage === "retro";
    return true;
  });

  const { page, totalPages, pageItems: pagedItems, setPage } = usePagination(filtered, PAGE_SIZE);

  // setPage is stable (usePagination hands back its own setter), so naming it
  // here costs nothing and keeps the dependency list honest.
  useEffect(() => {
    setPage(0);
  }, [sessionFilter, setPage]);

  const filterLabel: Record<SessionFilter, string> = {
    all: "All",
    current: "Current",
    past: "Past",
    archive: "Archive",
  };

  // Another recurring meeting than the 1:1 -- a series. An IC with one meeting
  // never meets the word: the field is behind one link, and blank means the 1:1
  // (docs/modules/communication.md, "The frontend").
  const [anotherMeeting, setAnotherMeeting] = useState(false);
  const [newSeries, setNewSeries] = useState("");
  const seriesSlug = newSeries.trim().toLowerCase().replace(/\s+/g, "-");
  const seriesOk = seriesSlug === "" || /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(seriesSlug);

  const handleSubmit = async () => {
    try {
      const result = await createSession({ date: newDate, series: seriesSlug }).unwrap();
      setDialogOpen(false);
      navigate(oneOnOnePath(result.filename));
    } catch {}
  };

  return (
    <>
      <PageCard
        scrollable
        loading={isLoading}
        loadingLabel="Loading meetings..."
        headerLeft={<Subtitle2>Meetings</Subtitle2>}
        headerRight={
          <>
            <Dropdown
              size="small"
              aria-label="Sessions"
              value={filterLabel[sessionFilter]}
              selectedOptions={[sessionFilter]}
              onOptionSelect={(_e, d) => setSessionFilter(d.optionValue as SessionFilter)}
              style={{ minWidth: "90px" }}
            >
              <Option value="all">All</Option>
              <Option value="current">Current</Option>
              <Option value="past">Past</Option>
              <Option value="archive">Archive</Option>
            </Dropdown>
            <RefreshButton onClick={refetch} isFetching={isFetching} />
            <Badge color="informative" appearance="filled" size="medium">
              {filtered.length ?? 0}
            </Badge>
          </>
        }
        footerCenter={<Pagination page={page} totalPages={totalPages} onPageChange={setPage} />}
        footerRight={<CreateButton label="New 1:1" onClick={() => setDialogOpen(true)} />}
      >
        {filtered.length === 0 ? (
          // Failed is not empty: "No meetings yet" for a request that was never
          // answered is the untruth Daily had.
          isError ? (
            <EmptyState
              icon={<PeopleCommunityRegular />}
              tone="error"
              title="Could not load your meetings"
              detail="The agent did not answer. Nothing was read."
            />
          ) : sessionFilter === "all" ? (
            <EmptyState
              icon={<PeopleCommunityRegular />}
              title="No meetings yet"
              detail="Plan your next 1:1 with the + below. It carries forward what the last one left open."
            />
          ) : (
            <EmptyState
              icon={<PeopleCommunityRegular />}
              tone="filtered"
              title={`No ${filterLabel[sessionFilter].toLowerCase()} meetings`}
              detail="Others are hidden by the filter."
            />
          )
        ) : (
          pagedItems.map((item) => <SessionRow key={item.filename} item={item} />)
        )}
      </PageCard>

      <Dialog open={dialogOpen} onOpenChange={(_e, d) => setDialogOpen(d.open)}>
        <DialogSurface>
          <DialogBody>
            <DialogTitle action={<DialogDismiss />}>
              {seriesSlug ? `New ${seriesSlug}` : "New 1:1"}
            </DialogTitle>
            <DialogContent>
              <div className={styles.dialogFields}>
                <Input
                  type="date"
                  size="small"
                  value={newDate}
                  onChange={(_, d) => setNewDate(d.value)}
                  aria-label="Session date"
                  style={{ width: "150px" }}
                />
                {anotherMeeting ? (
                  <Input
                    size="small"
                    value={newSeries}
                    onChange={(_, d) => setNewSeries(d.value)}
                    aria-label="Which meeting"
                    placeholder="which meeting? e.g. client-weekly"
                    style={{ width: "220px" }}
                  />
                ) : (
                  <Link as="button" onClick={() => setAnotherMeeting(true)}>
                    Another meeting than the 1:1?
                  </Link>
                )}
                <div className={styles.timeRow}>
                  <Dropdown
                    size="small"
                    value={newHour}
                    selectedOptions={[newHour]}
                    onOptionSelect={(_e, d) => setNewHour(d.optionValue ?? "10")}
                    style={{ minWidth: "60px" }}
                    aria-label="Hour"
                  >
                    {HOURS.map((h) => (
                      <Option key={h} value={h}>
                        {h}
                      </Option>
                    ))}
                  </Dropdown>
                  <Dropdown
                    size="small"
                    value={MINUTES.find((m) => m.value === newMinute)?.label ?? ""}
                    selectedOptions={[newMinute]}
                    onOptionSelect={(_e, d) => setNewMinute(d.optionValue ?? "0")}
                    style={{ minWidth: "60px" }}
                    aria-label="Minute"
                  >
                    {MINUTES.map((m) => (
                      <Option key={m.value} value={m.value}>
                        {m.label}
                      </Option>
                    ))}
                  </Dropdown>
                  <Dropdown
                    size="small"
                    value={newAmPm}
                    selectedOptions={[newAmPm]}
                    onOptionSelect={(_e, d) => setNewAmPm(d.optionValue ?? "AM")}
                    style={{ minWidth: "65px" }}
                    aria-label="AM or PM"
                  >
                    <Option value="AM">AM</Option>
                    <Option value="PM">PM</Option>
                  </Dropdown>
                </div>
              </div>
            </DialogContent>
            <DialogActions>
              <DialogTrigger disableButtonEnhancement>
                <Button appearance="secondary">Cancel</Button>
              </DialogTrigger>
              <Button
                appearance="primary"
                onClick={handleSubmit}
                disabled={!seriesOk || creating || !newDate}
              >
                {creating ? "Creating…" : "Submit"}
              </Button>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>
    </>
  );
}
