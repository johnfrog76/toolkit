import { useState } from "react";
import { useUserRefetch } from "../../hooks/useUserRefetch";
import { useNavigate } from "react-router";
import {
  CloudRegular,
  DocumentAddRegular,
  CheckmarkCircleRegular,
  PinRegular,
  PinOffRegular,
} from "@fluentui/react-icons";
import { ROW, defineRowMoves } from "../../shared/CardActions";
import { ActionDialog } from "./ActionDialog";
import type { ActionDialogTab } from "./ActionDialog";
import { useEditWorkItemMutation, useGetWorkItemsQuery } from "./api.ado";
import type { CommandResponse } from "./api.ado";
import { commandResultMessage } from "./cliBridge";
import { filterIssues, issueFilterSummary, issueMatches, pinnedFirst } from "./issueAxes";
import { effectiveIssueChoice, useIssueChoices } from "./useIssueChoices";
import { useGetEnvQuery } from "../../shell/api";
import type { WorkItemInfo } from "./api.ado";
import { getProjectTag } from "./repoTags";
import { trackerBadgeSpec, trackerName } from "./TrackerBadge";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { CompactItemData, MetaItem } from "../../shell/CardItem";
import { TaskListSquareLtrRegular } from "@fluentui/react-icons";
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
  const navigate = useNavigate();
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
  const workIcon = <TaskListSquareLtrRegular />;
  // Every state names the tracker and the thing, in the tracker's own words.
  const words = trackerWords(isGithub);
  const reading = isLoading || isFetching;
  const empty: EmptyMessage = error
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
    : // A stated reason beats an empty state -- see MyPRs.
      isGithub && showAll
      ? issueState === "open"
        ? {
            icon: workIcon,
            title: "No open GitHub issues",
            detail: data?.reason ?? "The repo's open issues show up here, ready to become a card.",
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
        };
  const filteredEmpty: EmptyMessage | undefined =
    !error && allItems.length > 0
      ? {
          icon: workIcon,
          tone: "filtered",
          title: filter
            ? `No ${words.short} matching "${filter}"`
            : isGithub
              ? "No GitHub issues match the filters"
              : `No ${stateFilter.toLowerCase()} ${words.short}`,
          detail: `${allItems.length} hidden by the filter.`,
        }
      : undefined;

  // A tracker item, as a compact card item -- the list carries no description,
  // so the panel is compact and no item keeps an empty band: the title is text, the one exposed action
  // goes somewhere, the menu holds the rest. On a GitHub Space that action is
  // the reading room and github.com is in the menu, last; an Azure DevOps
  // Space has no reading room, so its item still opens the board.
  const toItem = (item: WorkItemInfo): CompactItemData => {
    const external = ROW.external.action({ detail: words.tracker, href: item.url });
    const pickUp = ISSUE_MOVES.makeCard.action({
      onClick: () => openDialog("create", String(item.id)),
    });
    const close = (isGithub ? ISSUE_MOVES.close : ISSUE_MOVES.resolve).action({
      onClick: () => openDialog("resolve", String(item.id), item.type),
    });
    // The pin is the tracker's own, so the words name the tracker. What is
    // pinned can be unpinned from the same place, so a pin is never stuck.
    const pin = item.pinned
      ? ISSUE_MOVES.unpin.action({
          onClick: () => void togglePin(item),
          disabled: pinning !== null,
        })
      : ISSUE_MOVES.pin.action({
          detail: words.tracker,
          onClick: () => void togglePin(item),
          disabled: pinning !== null,
        });
    const project: MetaItem = {
      badge: {
        label: getProjectTag(item.project),
        appearance: "outline",
        color: "informative",
        title: item.project,
      },
    };
    // The chip grammar, worn as badges: where, what, how pressing.
    const meta: MetaItem[] = [];
    if (isGithub) {
      const where = trackerBadgeSpec("github");
      if (where) meta.push({ badge: where });
      meta.push({
        badge: {
          label: item.type === "Feature" ? "feat" : item.type.toLowerCase(),
          appearance: "outline",
          color: typeBadgeColor(item.type),
        },
      });
      for (const l of (item.labels ?? []).filter((x) => /^sev[123]$/.test(x))) {
        meta.push({ badge: { label: l, appearance: "outline", color: SEV_COLOR[l] } });
      }
      // Who works it.
      if (item.worker) {
        meta.push({
          badge: { label: item.worker, color: "brand", title: `Worked by ${item.worker}` },
        });
      }
      // A closed item wears its state, as the reading room does.
      if (item.state === "closed") {
        meta.push({ badge: { label: item.closed ? `closed ${item.closed}` : "closed" } });
      }
      if (item.pinned) {
        meta.push({
          badge: { label: `Pinned on ${words.tracker}`, color: "brand", glyph: <PinRegular /> },
        });
      }
      meta.push({ text: `#${item.id}` }, project);
    } else {
      meta.push(
        { badge: { label: item.type, appearance: "outline", color: typeBadgeColor(item.type) } },
        { text: `#${item.id}` },
        { text: item.state },
        project,
      );
    }
    if (item.sprint) meta.push({ text: item.sprint });
    if (item.assignee) meta.push({ text: item.assignee });
    meta.push({ text: item.updated });
    return {
      id: `${item.project}-${item.id}`,
      title: item.title,
      meta,
      primary: isGithub
        ? ROW.open.action({
            detail: "the issue",
            onClick: () => navigate(`/issue/${item.id}?repo=${encodeURIComponent(item.project)}`),
          })
        : external,
      menu: isGithub ? [pickUp, close, pin, external] : [pickUp, close],
    };
  };

  return (
    <>
      <ListPanel
        title={isGithub ? (showAll ? "GitHub Issues" : "GitHub issues assigned to me") : "My Work"}
        icon={<CloudRegular />}
        density="compact"
        items={error ? [] : searchFiltered}
        item={toItem}
        empty={empty}
        filteredEmpty={filteredEmpty}
        loading={
          reading
            ? { label: isGithub ? "Fetching issues..." : "Fetching work items..." }
            : undefined
        }
        // An Azure DevOps Space picks a state here; a GitHub Space's filters
        // are the drawer's, and the foot says what they are set to.
        pickers={
          isGithub
            ? undefined
            : [
                {
                  label: "State",
                  value: activeState,
                  options: stateOptions.map((s) => ({ value: s, label: s })),
                  onChange: setStateFilter,
                  disabled: globalActive || !!error || reading,
                },
              ]
        }
        refresh={{ onClick: handleRefetch, isFetching: userRefetching, disabled: isLoading }}
        count={searchFiltered.length}
        status={
          pinRefusal
            ? {
                tone: "error",
                text: commandResultMessage(
                  pinRefusal.result,
                  `The pin on #${pinRefusal.id} was not changed.`,
                ),
                onDismiss: () => setPinRefusal(null),
              }
            : undefined
        }
        footLeft={isGithub ? issueFilterSummary(issueChoice, filter) : undefined}
        create={{
          label: isGithub ? "New GitHub Issue" : "New ADO Item",
          onClick: () => openDialog("new-item"),
        }}
      />
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
