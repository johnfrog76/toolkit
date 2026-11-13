import { useState } from "react";
import { useUserRefetch } from "../../hooks/useUserRefetch";
import { useNavigate } from "react-router";
import { DocumentTextRegular, FolderRegular } from "@fluentui/react-icons";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import { ActionDialog } from "./ActionDialog";
import { archiveWhat } from "./confirmWords";
import { cardActionData, useCardActionContext } from "./CardActionMenu";
import { commandResultMessage } from "./cliBridge";
import type { ActionDialogTab } from "./ActionDialog";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { PanelStatus } from "../../shell/kinds/ListPanel";
import type { CardItemData, MetaItem } from "../../shell/CardItem";
import { useGetStatusQuery, useArchivePromptMutation, useMoveCardMutation } from "./api.ado";
import { filterPrompts } from "./promptFilters";
import { billableOutcomeMessage, useBillableToggle } from "./useBillableToggle";
import { useLaneLabel } from "./laneNames";
import type { Lane } from "./legalMoves";
import type { CommandResponse, PromptInfo } from "./api.ado";
import { getProjectTag } from "./repoTags";
import { trackerBadgeSpec } from "./TrackerBadge";
import { cardPath } from "./paths";
import { useLandCard } from "./useLandCard";
import { useRemindAbout } from "./useRemindAbout";
import { usePlanCard } from "./PlanCardDialog";
import { STATUS } from "../../shell/consts";
import type { EmptyMessage } from "../../shared/EmptyState";

export function PromptStatus({
  filter = "",
  globalState = "All",
  stateOptions = ["All"],
  activeRepo = null,
  typeFilter = "All",
  linkFilter = "All",
}: {
  filter?: string;
  globalState?: string;
  stateOptions?: string[];
  activeRepo?: string | null;
  typeFilter?: string;
  linkFilter?: string;
}) {
  const navigate = useNavigate();
  const { data, isLoading, isError, isFetching, refetch } = useGetStatusQuery();
  const [archive] = useArchivePromptMutation();
  const [moveCard] = useMoveCardMutation();
  const billing = useBillableToggle();
  const remind = useRemindAbout();
  const land = useLandCard();
  const plan = usePlanCard();
  const laneLabel = useLaneLabel();
  // What this row may do is the action model's answer, not this file's: the
  // board draws the same one (cardActions.ts, CardActionMenu.tsx).
  const actionContext = useCardActionContext();
  const [archiving, setArchiving] = useState<string | null>(null);
  const [pending, setPending] = useState<{ file: string; title: string; label: string } | null>(
    null,
  );
  const [toast, setToast] = useState<{
    file: string;
    result: CommandResponse;
  } | null>(null);
  const [statusFilter, setStatusFilter] = useState("All");
  const [dialogState, setDialogState] = useState<{
    open: boolean;
    tab: ActionDialogTab;
  }>({ open: false, tab: "pr" });

  const openDialog = (tab: ActionDialogTab) => setDialogState({ open: true, tab });
  const closeDialog = () => setDialogState((s) => ({ ...s, open: false }));

  const [userRefetching, handleRefetch] = useUserRefetch(isFetching, refetch);

  // The state vocabulary is the contract file's, not this card's -- the CLI's
  // Get-PromptStatus.ps1 and agent/core/parsers.py sort by the same three, in
  // the same order (see web/src/shell/consts.ts): the cards in play, then the
  // backlog -- the ledger is still the cards in play.
  const STATUS_ORDER: Record<string, number> = {
    [STATUS.active]: 0,
    [STATUS.inProgress]: 1,
    [STATUS.codeReview]: 2,
    [STATUS.backlog]: 3,
  };
  const prompts = [...(data?.prompts ?? [])].sort(
    (a, b) => (STATUS_ORDER[a.status] ?? 99) - (STATUS_ORDER[b.status] ?? 99),
  );
  // ONE set of predicates, shared with the board (promptFilters.ts): two pictures
  // of the same cards must never be able to show different cards.
  const globalActive = globalState !== "All";
  const activeStatus = globalActive ? globalState : statusFilter;
  const searchFiltered = filterPrompts(prompts, {
    activeRepo,
    status: activeStatus,
    text: filter,
    type: typeFilter,
    link: linkFilter,
  });

  const confirmArchive = async () => {
    if (!pending) return;
    const { file } = pending;
    setPending(null);
    await handleArchive(file);
  };

  const handleArchive = async (file: string) => {
    setArchiving(file);
    setToast(null);
    try {
      const result = await archive({ file }).unwrap();
      setToast({ file, result });
    } catch {
      setToast({
        file,
        result: {
          command: "Archive",
          status: "error",
          exit_code: -1,
          output: null,
          error: "Network error",
          duration: 0,
        },
      });
    } finally {
      setArchiving(null);
    }
  };

  // Done is the archive, and asks first; every other lane writes a person's line
  // through the Move verb. No optimistic update -- the refetch moves the card, and
  // a refusal comes back as the verb's own sentence (commandResultMessage).
  const requestArchive = (p: PromptInfo) => {
    const title = p.title || p.file;
    const id = p.ado_url?.match(/\/(\d+)(?:[?#]|$)/)?.[1];
    const truncated = title.length > 35 ? title.slice(0, 35) + "…" : title;
    const label = id ? `#${id} ${truncated}` : truncated;
    setPending({ file: p.file, title, label });
  };

  const handleMove = async (p: PromptInfo, to: Lane) => {
    if (to === STATUS.done) {
      requestArchive(p);
      return;
    }
    setArchiving(p.file);
    setToast(null);
    try {
      const result = await moveCard({ file: p.file, to }).unwrap();
      setToast({ file: p.file, result });
    } catch {
      setToast({
        file: p.file,
        result: {
          command: "Move",
          status: "error",
          exit_code: -1,
          output: null,
          error: "Could not reach the agent. The card was not moved.",
          duration: 0,
        },
      });
    } finally {
      setArchiving(null);
    }
  };

  const cardIcon = <DocumentTextRegular />;
  const empty: EmptyMessage = isError
    ? {
        icon: cardIcon,
        tone: "error",
        title: "Could not load your cards",
        detail: "The agent did not answer. Nothing was read.",
      }
    : {
        icon: cardIcon,
        title: "No cards in progress",
        detail:
          "A card you start lands here, and leaves when you archive it. The + below starts one.",
      };
  const filteredEmpty: EmptyMessage | undefined =
    !isError && prompts.length > 0
      ? {
          icon: cardIcon,
          tone: "filtered",
          // A state is named only when one is set: the type or the linkedness
          // row can hide everything too.
          title: filter
            ? `No cards matching "${filter}"`
            : activeStatus !== "All"
              ? `No cards are ${activeStatus}`
              : "No cards match the filters",
          detail: `${prompts.length} hidden by the filter.`,
        }
      : undefined;

  // One line at a time: what the last write on a card came to.
  const status: PanelStatus | undefined = billing.outcome
    ? {
        tone: billing.outcome.result.status === "success" ? "success" : "error",
        text:
          billing.outcome.result.status === "success"
            ? billableOutcomeMessage(billing.outcome, billing.outcome.file)
            : commandResultMessage(
                billing.outcome.result,
                `${billing.outcome.file} was not changed`,
              ),
        onDismiss: billing.clearOutcome,
      }
    : remind.added
      ? { tone: "success", text: remind.added, onDismiss: remind.clearAdded }
      : land.landed
        ? { tone: "success", text: land.landed, onDismiss: land.clearLanded }
        : plan.done
          ? { tone: "success", text: plan.done, onDismiss: plan.clearDone }
          : toast
            ? {
                tone: toast.result.status === "success" ? "success" : "error",
                text:
                  toast.result.status === "success"
                    ? `✓ ${toast.result.command === "Move" ? "Moved" : "Archived"} ${toast.file}`
                    : `✗ ${commandResultMessage(
                        toast.result,
                        toast.result.command === "Move"
                          ? `${toast.file} was not moved`
                          : `Archive of ${toast.file} did not complete`,
                      )}`,
                onDismiss: () => setToast(null),
              }
            : undefined;

  // A prompt file, as a card item: what it is called, then what KIND of thing
  // it is and its id -- "Spike K7M2", "Bug 141" -- and its facts in the meta
  // band, the checklist's progress among them. What the item may do is the
  // action model's answer, not this file's: the board draws the same one.
  const toItem = (p: PromptInfo): CardItemData => {
    const name = p.name || p.title || p.file;
    const meta: MetaItem[] = [];
    // WHERE first: whose ledger, from the card's own link.
    const tracker = trackerBadgeSpec(p.tracker);
    if (tracker) meta.push({ badge: tracker });
    meta.push({ text: `Sprint: ${p.sprint}` }, { text: `Modified: ${p.modified}` });
    meta.push({
      badge: {
        label: laneLabel(p.status),
        color:
          p.status === STATUS.codeReview
            ? "warning"
            : p.status === STATUS.inProgress
              ? "success"
              : "informative",
      },
    });
    // Said only when it is the exception.
    if (!p.billable) meta.push({ badge: { label: "Not billable", color: "subtle" } });
    const project = p.ado_url?.match(/dev\.azure\.com\/[^/]+\/([^/]+)/)?.[1];
    if (project) {
      const full = decodeURIComponent(project);
      meta.push({
        badge: {
          label: getProjectTag(full),
          appearance: "outline",
          color: "informative",
          title: full,
        },
      });
    }
    return {
      id: p.file,
      title: name,
      description: [p.type, p.id].filter(Boolean).join(" ") || p.file,
      thumb: p.cover ? { url: p.cover, label: `Cover of ${name}` } : undefined,
      progress: p.total > 0 ? { done: p.checked, total: p.total } : undefined,
      meta,
      busy: archiving === p.file || billing.busyFile === p.file,
      ...cardActionData(p, actionContext, {
        onOpenCard: () => navigate(cardPath(p.file)),
        onMove: (to) => void handleMove(p, to),
        onToggleBillable: () => billing.toggle(p),
        onCreatePR: () => openDialog("pr"),
        onRemind: () => remind.open(p),
        onLand: () => land.open(p),
        onPlan: (kind) => plan.open(p, kind),
      }),
    };
  };

  const reading = isLoading || isFetching;
  return (
    <>
      <ListPanel
        title="Active Cards"
        icon={<FolderRegular />}
        items={isError ? [] : searchFiltered}
        item={toItem}
        empty={empty}
        filteredEmpty={filteredEmpty}
        loading={reading ? { label: "Loading prompts..." } : undefined}
        pickers={[
          {
            label: "State",
            value: activeStatus,
            options: stateOptions.map((s) => ({ value: s, label: s })),
            onChange: setStatusFilter,
            disabled: globalActive || isError || reading,
          },
        ]}
        refresh={{ onClick: handleRefetch, isFetching: userRefetching, disabled: isLoading }}
        count={searchFiltered.length}
        status={status}
        create={{ label: "New card", onClick: () => openDialog("create") }}
      />
      <ActionDialog open={dialogState.open} onClose={closeDialog} tab={dialogState.tab} />
      {remind.dialog}
      {land.dialog}
      {plan.dialog}
      <ConfirmDialog
        open={!!pending}
        what={archiveWhat(pending?.label ?? "")}
        onCancel={() => setPending(null)}
        onConfirm={confirmArchive}
      />
    </>
  );
}
