import { useState } from "react";
import { useUserRefetch } from "../../hooks/useUserRefetch";
import { useNavigate } from "react-router";
import {
  Card,
  Subtitle2,
  Body1,
  Caption1,
  Badge,
  Select,
  Tooltip,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import {
  CloudRegular,
  DocumentAddRegular,
  CheckmarkCircleRegular,
  PinRegular,
  PinOffRegular,
  FilterRegular,
} from "@fluentui/react-icons";
import { CardActions, ROW, defineRowMoves } from "../../shared/CardActions";
import { CreateButton } from "../../shared/CreateButton";
import type { CardAction } from "../../shared/CardActions";
import { CardSpinner } from "../../shared/CardSpinner";
import { RefreshButton } from "../../shared/RefreshButton";
import { PageCard } from "../../shared/PageCard";
import { Pagination } from "../../shared/Pagination";
import { ActionDialog } from "./ActionDialog";
import type { ActionDialogTab } from "./ActionDialog";
import { usePagination } from "../../hooks/usePagination";
import { useEditWorkItemMutation, useGetWorkItemsQuery } from "./api.ado";
import type { CommandResponse } from "./api.ado";
import { commandResultMessage } from "./cliBridge";
import { StatusMessage } from "../../shared/StatusMessage";
import { filterIssues, issueFilterSummary, issueMatches, pinnedFirst } from "./issueAxes";
import { effectiveIssueChoice, useIssueChoices } from "./useIssueChoices";
import { useGetEnvQuery } from "../../shell/api";
import type { WorkItemInfo } from "./api.ado";
import { getProjectTag } from "./repoTags";
import { TrackerBadge, trackerName } from "./TrackerBadge";
import { TaskListSquareLtrRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import type { EmptyMessage } from "../../shared/EmptyState";

/** A tracker item's own moves, on no other record. Close and Resolve read like
 *  Complete and are not it: they close the item on the tracker, and nothing in
 *  ToolKit moves. */
const ISSUE_MOVES = defineRowMoves("issue", {
  makeCard: { word: "Make a card", icon: DocumentAddRegular },
  close: {
    word: "Close issue",
    icon: CheckmarkCircleRegular,
    differentMove: "It closes the issue on the tracker; nothing in ToolKit is completed or moved.",
  },
  resolve: {
    word: "Resolve Work Item",
    icon: CheckmarkCircleRegular,
    differentMove:
      "It resolves the work item on the tracker; nothing in ToolKit is completed or moved.",
  },
  pin: { word: "Pin on", icon: PinRegular },
  unpin: { word: "Unpin", icon: PinOffRegular },
});

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
  itemTitle: {
    flex: 1,
    minWidth: 0,
    display: "-webkit-box",
    WebkitLineClamp: 2,
    WebkitBoxOrient: "vertical" as const,
    overflow: "hidden",
  },
  // The one line that says what the drawer's Issues filters are set to.
  summary: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalXS,
    marginBottom: tokens.spacingVerticalXS,
    color: tokens.colorNeutralForeground3,
  },
  metaRow: {
    display: "flex",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
    marginTop: tokens.spacingVerticalXS,
    alignItems: "center",
  },
});

const SEV_COLOR: Record<string, "danger" | "severe" | "warning"> = {
  sev1: "danger",
  sev2: "severe",
  sev3: "warning",
};

function typeBadgeColor(type: string): "brand" | "informative" | "warning" | "success" {
  if (type === "Bug") return "warning";
  if (type === "Feature" || type === "Epic") return "brand";
  if (type === "Task") return "informative";
  return "informative";
}

/** The issue list's nouns, in the tracker's own words. */
function trackerWords(isGithub: boolean) {
  return isGithub
    ? {
        tracker: trackerName("github"),
        address: "repo",
        items: "GitHub issues",
        Items: "Issues",
        short: "issues",
      }
    : {
        tracker: trackerName("ado"),
        address: "address",
        items: "ADO work items",
        Items: "Work items",
        short: "work items",
      };
}

function WorkItemRow({
  item,
  isGithub,
  tracker,
  onCreateFrom,
  onResolve,
  onTogglePin,
  pinBusy = false,
}: {
  item: WorkItemInfo;
  isGithub: boolean;
  /** The Space's tracker's NAME ("GitHub"), for the pin's words. */
  tracker: string;
  onCreateFrom: (id: string) => void;
  onResolve: (id: string, type: string) => void;
  onTogglePin?: (item: WorkItemInfo) => void;
  pinBusy?: boolean;
}) {
  const styles = useStyles();
  const navigate = useNavigate();
  const external: CardAction = ROW.external.action({ detail: tracker, href: item.url });
  // The pin: the tracker's own, so the words name the tracker. What is
  // pinned can be unpinned from the same place -- a closed issue still pinned
  // keeps its Unpin, so a pin is never stuck.
  const pin: CardAction | null = onTogglePin
    ? item.pinned
      ? ISSUE_MOVES.unpin.action({ onClick: () => onTogglePin(item), disabled: pinBusy })
      : ISSUE_MOVES.pin.action({
          detail: tracker,
          onClick: () => onTogglePin(item),
          disabled: pinBusy,
        })
    : null;
  // The same act on both trackers, so the same words: the row is
  // already the place, the card is the thing it makes.
  const pickUp: CardAction = ISSUE_MOVES.makeCard.action({
    onClick: () => onCreateFrom(String(item.id)),
  });
  const close: CardAction = (isGithub ? ISSUE_MOVES.close : ISSUE_MOVES.resolve).action({
    onClick: () => onResolve(String(item.id), item.type),
  });
  return (
    <Card className={styles.itemCard} size="small" appearance="outline">
      <div className={styles.itemHeader}>
        <div className={styles.itemTitle}>
          <Body1>
            <strong>{item.title}</strong>
          </Body1>
        </div>
        {/* The house row: the title is text, the one exposed action goes
            somewhere, the menu holds the rest. On a gh space that action is
            the reading room (the house row), repo hint riding along -- github.com
            is in the menu, never the requirement. An ADO space has no
            reading room, so its row still opens the board. */}
        <CardActions
          primaryAction={
            isGithub
              ? ROW.open.action({
                  detail: "the issue",
                  onClick: () =>
                    navigate(`/issue/${item.id}?repo=${encodeURIComponent(item.project)}`),
                })
              : external
          }
          menuLabel={`Actions for ${item.title}`}
          secondaryActions={
            isGithub ? [pickUp, close, ...(pin ? [pin] : []), external] : [pickUp, close]
          }
        />
      </div>
      <div className={styles.metaRow}>
        {/* the chip grammar worn as BADGES (the owner:
            "parenthetical can be badges"): where, what, how pressing. The
            WHERE chip is the one a card wears too (TrackerBadge), so an issue
            and the card picked up from it read the same. */}
        {isGithub && (
          <>
            <TrackerBadge tracker="github" />
            <Badge appearance="outline" size="small" color={typeBadgeColor(item.type)}>
              {item.type === "Feature" ? "feat" : item.type.toLowerCase()}
            </Badge>
            {(item.labels ?? [])
              .filter((l) => /^sev[123]$/.test(l))
              .map((l) => (
                <Badge key={l} appearance="outline" size="small" color={SEV_COLOR[l]}>
                  {l}
                </Badge>
              ))}
            {/* WHO WORKS IT: "I want the system to show who gets what". */}
            {item.worker ? (
              <Tooltip content={`Worked by ${item.worker}`} relationship="description">
                <Badge appearance="tint" size="small" color="brand">
                  {item.worker}
                </Badge>
              </Tooltip>
            ) : null}
            {/* A closed row wears its state, as the reading room does. */}
            {item.state === "closed" ? (
              <Badge appearance="tint" size="small" color="informative">
                {item.closed ? `closed ${item.closed}` : "closed"}
              </Badge>
            ) : null}
            {/* Pinned on the tracker, where a closed row wears its
                date -- the tracker's pin, so the words name the tracker. */}
            {item.pinned ? (
              <Badge
                appearance="tint"
                size="small"
                color="brand"
                icon={<PinRegular />}
                data-pinned=""
              >
                {`Pinned on ${tracker}`}
              </Badge>
            ) : null}
          </>
        )}
        {!isGithub && (
          <Badge color={typeBadgeColor(item.type)} appearance="outline" size="medium">
            {item.type}
          </Badge>
        )}
        <Caption1>#{item.id}</Caption1>
        {!isGithub && <Caption1>{item.state}</Caption1>}
        <Tooltip content={item.project} relationship="description">
          <Badge color="informative" appearance="outline" size="small">
            {getProjectTag(item.project)}
          </Badge>
        </Tooltip>
        {item.sprint && <Caption1>{item.sprint}</Caption1>}
        {item.assignee ? <Caption1>{item.assignee}</Caption1> : null}
        <Caption1>{item.updated}</Caption1>
      </div>
    </Card>
  );
}

const PAGE_SIZE = 5;

export function MyWork({
  filter = "",
  globalState = "All",
  stateOptions = ["All"],
  activeRepo = null,
}: {
  filter?: string;
  globalState?: string;
  stateOptions?: string[];
  activeRepo?: string | null;
}) {
  // On a GitHub space this card IS the Issues tab ("Backlog" before): default
  // ALL -- "until I assign something we see nothing" was the pain -- with a
  // Mine toggle. On ADO nothing changes: assigned-to-me, as it always was.
  const styles = useStyles();
  const { data: env } = useGetEnvQuery();
  const isGithub = env?.tracker === "github";
  // The Issues tab's filters live in the FILTER DRAWER (the owner: "no
  // reason why GitHub issues tags and filters not live in here"); this list
  // reads the same choices (useIssueChoices, shared per browser) and says
  // them in one line. Two axes the AGENT answers: which state gh lists,
  // and whose -- open issues, assigned to anyone, until a chip is chosen.
  const issueChoices = useIssueChoices();
  const issueState = issueChoices.stored.state;
  const showAll = issueChoices.stored.assignee !== "me";
  const { data, isLoading, isFetching, error, refetch } = useGetWorkItemsQuery(
    isGithub ? issueChoices.queryArg : undefined,
  );
  const globalActive = globalState !== "All";
  const [stateFilter, setStateFilter] = useState("All");
  const activeState = globalActive ? globalState : stateFilter;
  const [dialogState, setDialogState] = useState<{
    open: boolean;
    tab: ActionDialogTab;
    workItemId: string;
    workItemType: string;
  }>({ open: false, tab: "create", workItemId: "", workItemType: "" });

  const [userRefetching, handleRefetch] = useUserRefetch(isFetching, refetch);

  const openDialog = (tab: ActionDialogTab, workItemId = "", workItemType = "") =>
    setDialogState({ open: true, tab, workItemId, workItemType });

  const closeDialog = () => setDialogState((s) => ({ ...s, open: false }));

  // The pin goes through the CLI like every write from the web:
  // POST /api/cmd/EditItem with -Pin / -Unpin. The mutation invalidates the
  // list, so the refetch is what moves the row; a refusal -- GitHub's fourth
  // pin among them -- comes back as the verb's own sentence.
  const [editWorkItem] = useEditWorkItemMutation();
  const [pinning, setPinning] = useState<number | null>(null);
  const [pinRefusal, setPinRefusal] = useState<{ id: number; result: CommandResponse } | null>(
    null,
  );
  const togglePin = async (item: WorkItemInfo) => {
    setPinning(item.id);
    setPinRefusal(null);
    try {
      const result = await editWorkItem({ id: item.id, pinned: !item.pinned }).unwrap();
      if (result.status !== "success") setPinRefusal({ id: item.id, result });
    } catch {
      setPinRefusal({
        id: item.id,
        result: {
          command: "EditItem",
          status: "error",
          exit_code: -1,
          output: null,
          error: "Could not reach the agent. The pin was not changed.",
          duration: 0,
        },
      });
    } finally {
      setPinning(null);
    }
  };

  const allItems = data?.items ?? [];
  // A remembered worker or milestone the list no longer carries reads as all.
  const { choice: issueChoice } = effectiveIssueChoice(issueChoices.stored, allItems);
  // On GitHub the list answers ITS OWN filters -- the drawer's Issues section
  // (labels, worker) and search over number, title and labels
  // (issueMatches). The shell's lane and repo filters are card filters
  // with no control on this tab, so they never reach it: a lane chosen on the
  // Board cannot silently empty the Issues. ADO keeps its rows as they were.
  const searched = isGithub
    ? filterIssues(allItems, issueChoice).filter((i) => issueMatches(i, filter))
    : (() => {
        const repoFiltered = activeRepo
          ? allItems.filter((i) => i.project === activeRepo)
          : allItems;
        const filtered =
          activeState === "All"
            ? repoFiltered
            : repoFiltered.filter((i) => i.state === activeState);
        return filter
          ? filtered.filter(
              (i) =>
                i.id.toString().includes(filter) ||
                i.title.toLowerCase().includes(filter.toLowerCase()),
            )
          : filtered;
      })();
  // Pinned rows first, within whatever the filters kept.
  const searchFiltered = isGithub ? pinnedFirst(searched) : searched;
  // Full-width list, fuller page (the owner: "pagesize 10") -- the
  // half-width ADO face keeps the house five.
  const { page, totalPages, pageItems, setPage } = usePagination(
    searchFiltered,
    isGithub ? 10 : PAGE_SIZE,
  );

  const handleStateChange = (val: string) => {
    setStateFilter(val);
    setPage(0);
  };

  // Said through the frame's `empty` slot, so every card says it one way.
  const workIcon = <TaskListSquareLtrRegular />;
  // Every state names the tracker and the thing: on a gh space this
  // list said "work items" and "Azure DevOps did not answer" -- ADO words on
  // gh soil (D-G13).
  const words = trackerWords(isGithub);
  const emptyMessage: EmptyMessage | undefined =
    isLoading || isFetching
      ? undefined
      : error
        ? "status" in error && error.status === 503
          ? {
              icon: workIcon,
              tone: "error",
              title: `${words.tracker} is not set up`,
              detail: `This Space has no ${words.address} to ask. Give it one in Settings.`,
            }
          : {
              icon: workIcon,
              tone: "error",
              title: `Could not load the ${words.items}`,
              detail: `${words.tracker} did not answer. Nothing was read.`,
            }
        : searchFiltered.length > 0
          ? undefined
          : allItems.length === 0
            ? // A stated reason beats an empty state -- see MyPRs.
              isGithub && showAll
              ? issueState === "open"
                ? {
                    icon: workIcon,
                    title: "No open GitHub issues",
                    detail:
                      data?.reason ??
                      "The repo's open issues show up here, ready to become a card.",
                  }
                : {
                    icon: workIcon,
                    title: issueState === "closed" ? "No closed GitHub issues" : "No GitHub issues",
                    detail: data?.reason ?? "The repo has not closed anything yet.",
                  }
              : {
                  icon: workIcon,
                  title: `No ${words.items} assigned to you`,
                  detail:
                    data?.reason ??
                    `${words.Items} assigned to you in ${words.tracker} show up here, ready to become a card.`,
                }
            : {
                icon: workIcon,
                tone: "filtered",
                title: filter
                  ? `No ${words.short} matching "${filter}"`
                  : isGithub
                    ? "No GitHub issues match the filters"
                    : `No ${stateFilter.toLowerCase()} ${words.short}`,
                detail: `${allItems.length} hidden by the filter.`,
              };

  // The chips live in the drawer; the tab says what they are set to in
  // ONE line, above an empty list too -- a filter that hid everything is
  // named, and the drawer above is where it is undone.
  const chipRows = isGithub ? (
    <div className={styles.summary} data-issue-summary="">
      <FilterRegular aria-hidden />
      <Caption1>{issueFilterSummary(issueChoice, filter)}</Caption1>
    </div>
  ) : null;

  return (
    <>
      <PageCard
        scrollable
        toast={
          pinRefusal ? (
            <StatusMessage status="error" onDismiss={() => setPinRefusal(null)}>
              {commandResultMessage(
                pinRefusal.result,
                `The pin on #${pinRefusal.id} was not changed.`,
              )}
            </StatusMessage>
          ) : undefined
        }
        empty={
          emptyMessage ? (
            <>
              {chipRows}
              <EmptyState {...emptyMessage} />
            </>
          ) : undefined
        }
        headerLeft={
          <>
            <CloudRegular />
            <Subtitle2>
              {isGithub ? (showAll ? "GitHub Issues" : "GitHub issues assigned to me") : "My Work"}
            </Subtitle2>
          </>
        }
        headerRight={
          <>
            {/* New issue moved to the module's plain-plus FAB and the create
                dialog's third door (the owner: "I don't know if we need third
                button primary in the module header") -- the header keeps the
                filters and the count. */}
            {/* The kind, sev and milestone Selects that stood here moved into
                the filter drawer with the chip groups: one place for
                every Issues filter, and the summary line under the header. */}
            {/* The ADO State Select is banned furniture on a gh space --
                "no bunch of ADO filters wearing a gh costume". The gh
                pane's own filters are its own: labels, milestones, search. */}
            {!isGithub && (
              <Select
                size="small"
                value={activeState}
                onChange={(_e, d) => handleStateChange(d.value)}
                disabled={globalActive || !!error || isLoading || isFetching}
                style={{ minWidth: 0 }}
              >
                {stateOptions.map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </Select>
            )}
            <RefreshButton
              onClick={handleRefetch}
              isFetching={userRefetching}
              disabled={isLoading}
            />
            <Badge color="informative" appearance="filled" size="large">
              {searchFiltered.length}
            </Badge>
          </>
        }
        footerCenter={
          totalPages > 1 ? (
            <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
          ) : undefined
        }
        footerRight={
          <CreateButton
            label={isGithub ? "New GitHub Issue" : "New ADO Item"}
            onClick={() => openDialog("new-item")}
          />
        }
      >
        {chipRows}
        {isLoading || isFetching ? (
          <CardSpinner label={isGithub ? "Fetching issues..." : "Fetching work items..."} />
        ) : (
          pageItems.map((item) => (
            <WorkItemRow
              isGithub={isGithub}
              tracker={words.tracker}
              key={`${item.project}-${item.id}`}
              item={item}
              onCreateFrom={(id) => openDialog("create", id)}
              onResolve={(id, type) => openDialog("resolve", id, type)}
              onTogglePin={isGithub ? togglePin : undefined}
              pinBusy={pinning !== null}
            />
          ))
        )}
      </PageCard>
      <ActionDialog
        open={dialogState.open}
        onClose={closeDialog}
        tab={dialogState.tab}
        initialWorkItemId={dialogState.workItemId}
        initialWorkItemType={dialogState.workItemType}
      />
    </>
  );
}
