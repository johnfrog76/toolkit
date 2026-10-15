import { useState } from "react";
import { useNavigate } from "react-router";
import {
  Card,
  Subtitle2,
  Body1Strong,
  Caption1,
  Badge,
  Button,
  Dropdown,
  Option,
  Input,
  Textarea,
  Dialog,
  DialogSurface,
  DialogBody,
  DialogTitle,
  DialogContent,
  DialogActions,
  DialogTrigger,
  Field,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { ArchiveRegular, ArrowRightRegular } from "@fluentui/react-icons";
import { RetireGoalDialog } from "./RetireGoal";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { CardActions } from "../../shared/CardActions";
import { RefreshButton } from "../../shared/RefreshButton";
import { PageCard } from "../../shared/PageCard";
import { CreateButton } from "../../shared/CreateButton";
import { Pagination } from "../../shared/Pagination";
import { usePagination } from "../../hooks/usePagination";
import { useGetGrowthQuery, useCreateGrowthMutation } from "./api.growth";
import type { GrowthItem, GrowthType } from "./api.growth";
import { TargetArrowRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { localToday } from "../../utility/dates";

const PAGE_SIZE = 3;

type StatusFilter = "all" | "new" | "active" | "complete";

const useStyles = makeStyles({
  itemCard: {
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
  },
  itemHeader: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalS,
  },
  itemBody: {
    flex: 1,
    minWidth: 0,
  },
  typeBadgeRow: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
  },
  metaRow: {
    display: "flex",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
    marginTop: tokens.spacingVerticalXS,
    alignItems: "center",
  },
  dialogFields: {
    display: "flex",
    flexDirection: "column" as const,
    gap: tokens.spacingVerticalM,
    paddingTop: tokens.spacingVerticalS,
  },
});

function statusBadge(status: GrowthItem["status"]) {
  if (status === "new")
    return (
      <Badge color="important" appearance="tint" size="small">
        New
      </Badge>
    );
  return (
    <Badge color="subtle" appearance="tint" size="small">
      {status === "complete" ? "Complete" : "Active"}
    </Badge>
  );
}

// Three types, and the badge reads the item rather than asking whether it is a
// presentation. It used to be a boolean, which was true of the two types that
// existed then and silently labelled the third one "Training".
const TYPE_LABEL: Record<GrowthType, string> = {
  training: "Training",
  presentation: "Presentation",
  goal: "Goal",
};
const TYPE_COLOUR: Record<GrowthType, "success" | "brand" | "informative"> = {
  training: "success",
  presentation: "brand",
  goal: "informative",
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

function GoalCard({ item }: { item: GrowthItem }) {
  const styles = useStyles();
  const navigate = useNavigate();
  const [retireOpen, setRetireOpen] = useState(false);
  const isTraining = item.type === "training";
  const dueLabel = item.due_date ? `Due: ${item.due_date}` : item.date || null;
  const noRealTitle = isUntitledGrowthItem(item.title, item.filename);

  return (
    <Card className={styles.itemCard} size="small" appearance="outline">
      <div className={styles.itemHeader}>
        <div className={styles.itemBody}>
          <div className={styles.typeBadgeRow}>
            <Badge color={TYPE_COLOUR[item.type]} appearance="outline" size="small">
              {TYPE_LABEL[item.type]}
            </Badge>
            {statusBadge(item.status)}
          </div>
          <Body1Strong style={{ display: "block", marginTop: tokens.spacingVerticalXS }}>
            {noRealTitle ? `Untitled ${TYPE_LABEL[item.type]}` : item.title}
          </Body1Strong>
          {noRealTitle && (
            <Caption1
              title={item.filename}
              style={{ display: "block", color: tokens.colorNeutralForeground3 }}
            >
              {item.filename}
            </Caption1>
          )}
          <div className={styles.metaRow}>
            {isTraining && item.provider && <Caption1>{item.provider}</Caption1>}
            {isTraining && item.hours && item.hours !== "TBD" && <Caption1>{item.hours}h</Caption1>}
            {dueLabel && <Caption1>{dueLabel}</Caption1>}
          </div>
        </div>
        <CardActions
          primaryAction={{
            icon: <ArrowRightRegular />,
            label: "View goal",
            onClick: () => navigate(`/growth/goals/${encodeURIComponent(item.filename)}`),
          }}
          menuLabel={`Actions for ${item.title}`}
          secondaryActions={[
            {
              icon: <ArchiveRegular />,
              label: "Retire",
              onClick: () => setRetireOpen(true),
            },
          ]}
        />
      </div>
      <RetireGoalDialog
        filename={item.filename}
        title={item.title}
        open={retireOpen}
        onOpenChange={setRetireOpen}
      />
    </Card>
  );
}

function todayIso(): string {
  return localToday();
}

export function Goals() {
  const styles = useStyles();
  const navigate = useNavigate();
  const { data, isLoading, isFetching, isError, refetch } = useGetGrowthQuery();
  const [createGrowth, { isLoading: creating }] = useCreateGrowthMutation();
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [dialogOpen, setDialogOpen] = useState(false);
  const [newType, setNewType] = useState<GrowthType>("training");
  const [newTitle, setNewTitle] = useState("");
  const [newDate, setNewDate] = useState(todayIso);
  const [newDueDate, setNewDueDate] = useState("");
  const [newProvider, setNewProvider] = useState("");
  const [newHours, setNewHours] = useState("");
  const [newNotes, setNewNotes] = useState("");

  const allItems = data?.items ?? [];
  const filtered =
    statusFilter === "all" ? allItems : allItems.filter((i) => i.status === statusFilter);
  const { page, totalPages, pageItems, setPage } = usePagination(filtered, PAGE_SIZE);

  const newCount = allItems.filter((i) => i.status === "new").length;
  const activeCount = allItems.filter((i) => i.status === "active").length;
  const completeCount = allItems.filter((i) => i.status === "complete").length;

  const handleFilter = (f: StatusFilter) => {
    setStatusFilter(f);
    setPage(0);
  };

  const resetDialog = () => {
    setNewType("training");
    setNewTitle("");
    setNewDate(todayIso());
    setNewDueDate("");
    setNewProvider("");
    setNewHours("");
    setNewNotes("");
  };

  const handleSubmit = async () => {
    try {
      const result = await createGrowth({
        type: newType,
        title: newTitle.trim(),
        date: newDate,
        due_date: newDueDate || undefined,
        provider: newProvider.trim() || undefined,
        hours: newHours.trim() || undefined,
        notes: newNotes.trim() || undefined,
      }).unwrap();
      setDialogOpen(false);
      resetDialog();
      navigate(`/growth/goals/${encodeURIComponent(result.filename)}`);
    } catch {}
  };

  const filterLabel: Record<StatusFilter, string> = {
    all: "All",
    new: `New (${newCount})`,
    active: `Active (${activeCount})`,
    complete: `Complete (${completeCount})`,
  };

  return (
    <>
      <PageCard
        scrollable
        loading={isLoading}
        loadingLabel="Loading goals..."
        headerLeft={<Subtitle2>Goals</Subtitle2>}
        headerRight={
          <>
            <Dropdown
              size="small"
              aria-label="Status"
              value={statusFilter === "all" ? "All" : filterLabel[statusFilter]}
              selectedOptions={[statusFilter]}
              onOptionSelect={(_e, d) => handleFilter(d.optionValue as StatusFilter)}
              style={{ minWidth: "130px" }}
            >
              <Option value="all">All</Option>
              <Option value="new">{filterLabel.new}</Option>
              <Option value="active">{filterLabel.active}</Option>
              <Option value="complete">{filterLabel.complete}</Option>
            </Dropdown>
            <RefreshButton onClick={refetch} isFetching={isFetching} />
            <Badge color="informative" appearance="filled" size="large">
              {statusFilter === "all" ? allItems.length : `${filtered.length} / ${allItems.length}`}
            </Badge>
          </>
        }
        footerCenter={
          totalPages > 1 ? (
            <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
          ) : undefined
        }
        footerRight={<CreateButton label="New Growth Item" onClick={() => setDialogOpen(true)} />}
      >
        {filtered.length === 0 ? (
          isError ? (
            <EmptyState
              icon={<TargetArrowRegular />}
              tone="error"
              title="Could not load your goals"
              detail="The agent did not answer. Nothing was read."
            />
          ) : statusFilter === "all" ? (
            <EmptyState
              icon={<TargetArrowRegular />}
              title="No goals yet"
              detail="A goal, a course or a talk you are preparing. The + below starts one."
            />
          ) : (
            <EmptyState
              icon={<TargetArrowRegular />}
              tone="filtered"
              title={`No ${statusFilter} goals`}
              detail="Others are hidden by the filter."
            />
          )
        ) : (
          pageItems.map((item) => <GoalCard key={item.filename} item={item} />)
        )}
      </PageCard>

      <Dialog
        open={dialogOpen}
        onOpenChange={(_e, d) => {
          setDialogOpen(d.open);
          if (!d.open) resetDialog();
        }}
      >
        <DialogSurface>
          <DialogBody>
            <DialogTitle action={<DialogDismiss />}>New Growth Item</DialogTitle>
            <DialogContent>
              <div className={styles.dialogFields}>
                <Field label="Type">
                  <Dropdown
                    size="small"
                    value={TYPE_LABEL[newType]}
                    selectedOptions={[newType]}
                    onOptionSelect={(_e, d) => setNewType(d.optionValue as GrowthType)}
                    style={{ minWidth: "150px" }}
                  >
                    <Option value="training">Training</Option>
                    <Option value="presentation">Presentation</Option>
                    <Option value="goal">Goal</Option>
                  </Dropdown>
                </Field>
                <Field label="Title">
                  <Input
                    size="small"
                    value={newTitle}
                    onChange={(_, d) => setNewTitle(d.value)}
                    placeholder="Course or talk title"
                    style={{ width: "100%" }}
                  />
                </Field>
                {newType === "training" ? (
                  <div
                    style={{
                      display: "flex",
                      gap: tokens.spacingHorizontalM,
                      alignItems: "flex-end",
                    }}
                  >
                    <Field label="Start date">
                      <Input
                        type="date"
                        size="small"
                        value={newDate}
                        onChange={(_, d) => setNewDate(d.value)}
                        style={{ width: "145px" }}
                      />
                    </Field>
                    {/* Required, and the field says so -- the Create button is
                        already disabled without it, which told the user nothing
                        about WHY. The CLI refuses the same case by name. */}
                    <Field label="Due date (required)" required>
                      <Input
                        type="date"
                        size="small"
                        value={newDueDate}
                        onChange={(_, d) => setNewDueDate(d.value)}
                        style={{ width: "145px" }}
                      />
                    </Field>
                  </div>
                ) : (
                  <Field label="Date">
                    <Input
                      type="date"
                      size="small"
                      value={newDate}
                      onChange={(_, d) => setNewDate(d.value)}
                      style={{ width: "150px" }}
                    />
                  </Field>
                )}
                {newType === "training" && (
                  <div
                    style={{
                      display: "flex",
                      gap: tokens.spacingHorizontalM,
                      alignItems: "flex-end",
                    }}
                  >
                    <Field label="Provider">
                      <Input
                        size="small"
                        value={newProvider}
                        onChange={(_, d) => setNewProvider(d.value)}
                        placeholder="Udemy, Pluralsight, internal…"
                        style={{ width: "220px" }}
                      />
                    </Field>
                    <Field label="Hours">
                      <Input
                        size="small"
                        value={newHours}
                        onChange={(_, d) => setNewHours(d.value)}
                        placeholder="TBD"
                        style={{ width: "70px" }}
                      />
                    </Field>
                  </div>
                )}
                <Field label="Notes">
                  <Textarea
                    size="small"
                    rows={3}
                    resize="vertical"
                    value={newNotes}
                    onChange={(_, d) => setNewNotes(d.value)}
                    placeholder={
                      newType === "training"
                        ? "What it covers, why you enrolled…"
                        : newType === "goal"
                          ? "Why this matters, and what it would change…"
                          : "Context, audience, key message…"
                    }
                  />
                </Field>
              </div>
            </DialogContent>
            <DialogActions>
              <DialogTrigger disableButtonEnhancement>
                <Button appearance="secondary">Cancel</Button>
              </DialogTrigger>
              <Button
                appearance="primary"
                onClick={handleSubmit}
                disabled={
                  creating ||
                  !newTitle.trim() ||
                  !newDate ||
                  (newType === "training" && !newDueDate)
                }
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
