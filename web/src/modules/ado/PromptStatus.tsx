import { useState } from "react";
import { useUserRefetch } from "../../hooks/useUserRefetch";
import { useNavigate } from "react-router";
import {
  Card,
  Subtitle2,
  Body1,
  Caption1,
  Badge,
  ProgressBar,
  Tooltip,
  Select,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { FolderRegular } from "@fluentui/react-icons";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import { CreateButton } from "../../shared/CreateButton";
import { ActionDialog } from "./ActionDialog";
import { archiveWhat } from "./confirmWords";
import { CardActionMenu, useCardActionContext } from "./CardActionMenu";
import { commandResultMessage } from "./cliBridge";
import type { ActionDialogTab } from "./ActionDialog";
import { CardSpinner } from "../../shared/CardSpinner";
import { RefreshButton } from "../../shared/RefreshButton";
import { PageCard } from "../../shared/PageCard";
import { Pagination } from "../../shared/Pagination";
import { StatusMessage } from "../../shared/StatusMessage";
import { useGetStatusQuery, useArchivePromptMutation, useMoveCardMutation } from "./api.ado";
import { filterPrompts } from "./promptFilters";
import { billableOutcomeMessage, useBillableToggle } from "./useBillableToggle";
import { useLaneLabel } from "./laneNames";
import type { Lane } from "./legalMoves";
import type { CommandResponse, PromptInfo } from "./api.ado";
import { getProjectTag } from "./repoTags";
import { TrackerBadge } from "./TrackerBadge";
import { CoverThumb } from "./CardCover";
import { cardPath } from "./paths";
import { useRemindAbout } from "./useRemindAbout";
import { STATUS } from "../../shell/consts";
import { DocumentTextRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import type { EmptyMessage } from "../../shared/EmptyState";

const useStyles = makeStyles({
  promptCard: {
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
  },
  promptHeader: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalS,
  },
  promptTitle: {
    flex: 1,
    minWidth: 0,
    display: "-webkit-box",
    WebkitLineClamp: 2,
    WebkitBoxOrient: "vertical" as const,
    overflow: "hidden",
  },
  metaRow: {
    display: "flex",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
    marginTop: tokens.spacingVerticalXS,
  },
  progressRow: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    marginTop: tokens.spacingVerticalXS,
  },
  progressBar: {
    flex: 1,
    maxWidth: "200px",
  },
});

const PAGE_SIZE = 5;

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
  const styles = useStyles();
  const navigate = useNavigate();
  const { data, isLoading, isError, isFetching, refetch } = useGetStatusQuery();
  const [archive] = useArchivePromptMutation();
  const [moveCard] = useMoveCardMutation();
  const billing = useBillableToggle();
  const remind = useRemindAbout();
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
  const [page, setPage] = useState(0);
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
  // the same order (see web/src/shell/consts.ts).
  const STATUS_ORDER: Record<string, number> = {
    [STATUS.active]: 0,
    [STATUS.inProgress]: 1,
    [STATUS.codeReview]: 2,
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
  const totalPages = Math.max(1, Math.ceil(searchFiltered.length / PAGE_SIZE));
  const pagePrompts = searchFiltered.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);

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

  // Said through the frame's `empty` slot, so every card says it one way.
  const cardIcon = <DocumentTextRegular />;
  const emptyMessage: EmptyMessage | undefined =
    isLoading || isFetching
      ? undefined
      : isError
        ? {
            icon: cardIcon,
            tone: "error",
            title: "Could not load your cards",
            detail: "The agent did not answer. Nothing was read.",
          }
        : prompts.length === 0
          ? {
              icon: cardIcon,
              title: "No cards in progress",
              detail:
                "A card you start lands here, and leaves when you archive it. The + below starts one.",
            }
          : searchFiltered.length === 0
            ? {
                icon: cardIcon,
                tone: "filtered",
                // "No cards are All" was the title when the type or the
                // linkedness row hid everything; a state is named only when one is set.
                title: filter
                  ? `No cards matching "${filter}"`
                  : activeStatus !== "All"
                    ? `No cards are ${activeStatus}`
                    : "No cards match the filters",
                detail: `${prompts.length} hidden by the filter.`,
              }
            : undefined;

  return (
    <>
      <PageCard
        scrollable
        empty={emptyMessage ? <EmptyState {...emptyMessage} /> : undefined}
        headerLeft={
          <>
            <FolderRegular />
            <Subtitle2>Active Cards</Subtitle2>
          </>
        }
        headerRight={
          <>
            <Select
              size="small"
              value={activeStatus}
              onChange={(_, d) => {
                setStatusFilter(d.value);
                setPage(0);
              }}
              disabled={globalActive || isError || isLoading || isFetching}
            >
              {stateOptions.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
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
        toast={
          billing.outcome ? (
            <StatusMessage
              status={billing.outcome.result.status === "success" ? "success" : "error"}
              onDismiss={billing.clearOutcome}
            >
              {billing.outcome.result.status === "success"
                ? billableOutcomeMessage(billing.outcome, billing.outcome.file)
                : commandResultMessage(
                    billing.outcome.result,
                    `${billing.outcome.file} was not changed`,
                  )}
            </StatusMessage>
          ) : remind.added ? (
            <StatusMessage status="success" onDismiss={remind.clearAdded}>
              {remind.added}
            </StatusMessage>
          ) : (
            toast && (
              <StatusMessage
                status={toast.result.status === "success" ? "success" : "error"}
                onDismiss={() => setToast(null)}
              >
                {toast.result.status === "success"
                  ? `✓ ${toast.result.command === "Move" ? "Moved" : "Archived"} ${toast.file}`
                  : `✗ ${commandResultMessage(
                      toast.result,
                      toast.result.command === "Move"
                        ? `${toast.file} was not moved`
                        : `Archive of ${toast.file} did not complete`,
                    )}`}
              </StatusMessage>
            )
          )
        }
        footerCenter={<Pagination page={page} totalPages={totalPages} onPageChange={setPage} />}
        footerRight={<CreateButton label="New card" onClick={() => openDialog("create")} />}
      >
        {isLoading || isFetching ? (
          <CardSpinner label="Loading prompts..." />
        ) : (
          pagePrompts.map((p) => (
            <Card key={p.file} className={styles.promptCard} size="small" appearance="outline">
              <div className={styles.promptHeader}>
                <div className={styles.promptTitle}>
                  {/* The card's model, as fields: what it is called, then what KIND of
                      thing it is and its id -- "Spike K7M2", "Bug 141". The file name used
                      to sit here; it is a fact about storage, so it is the tooltip now
                      (UX audit D7: "file name under every title is noise"). */}
                  <Body1>
                    <strong>{p.name || p.title || p.file}</strong>
                  </Body1>
                  <Caption1
                    title={p.file}
                    style={{
                      display: "block",
                      color: tokens.colorNeutralForeground3,
                    }}
                  >
                    {[p.type, p.id].filter(Boolean).join(" ") || p.file}
                  </Caption1>
                </div>
                <CardActionMenu
                  card={p}
                  context={actionContext}
                  busy={archiving === p.file || billing.busyFile === p.file}
                  onOpenCard={() => navigate(cardPath(p.file))}
                  onMove={(to) => void handleMove(p, to)}
                  onToggleBillable={() => billing.toggle(p)}
                  onCreatePR={() => openDialog("pr")}
                  onRemind={() => remind.open(p)}
                />
              </div>

              {p.total > 0 && (
                <div className={styles.progressRow}>
                  <ProgressBar
                    className={styles.progressBar}
                    value={p.checked / p.total}
                    thickness="large"
                    color={p.checked === p.total ? "success" : "brand"}
                  />
                  <Tooltip
                    content={`${p.checked} of ${p.total} checklist items completed in the prompt file`}
                    relationship="description"
                  >
                    <Caption1 style={{ cursor: "default" }}>{p.progress}</Caption1>
                  </Tooltip>
                </div>
              )}

              <div className={styles.metaRow}>
                {/* The cover as a thumbnail, inside the meta line: a row without
                    one draws nothing here and does not move. */}
                <CoverThumb cover={p.cover} label={p.name || p.title || p.file} />
                {/* WHERE first: whose ledger, from the card's own link. */}
                <TrackerBadge tracker={p.tracker} />
                <Caption1>Sprint: {p.sprint}</Caption1>
                <Caption1>Modified: {p.modified}</Caption1>
                <Badge
                  size="small"
                  appearance="tint"
                  color={
                    p.status === STATUS.codeReview
                      ? "warning"
                      : p.status === STATUS.inProgress
                        ? "success"
                        : "informative"
                  }
                >
                  {laneLabel(p.status)}
                </Badge>
                {/* Said only when it is the exception. */}
                {!p.billable && (
                  <Badge size="small" appearance="tint" color="subtle">
                    Not billable
                  </Badge>
                )}
                {p.ado_url &&
                  (() => {
                    const match = p.ado_url!.match(/dev\.azure\.com\/[^/]+\/([^/]+)/);
                    const project = match ? match[1] : null;
                    return project ? (
                      <Tooltip content={decodeURIComponent(project)} relationship="description">
                        <Badge color="informative" appearance="outline" size="small">
                          {getProjectTag(decodeURIComponent(project))}
                        </Badge>
                      </Tooltip>
                    ) : null;
                  })()}
              </div>
            </Card>
          ))
        )}
      </PageCard>
      <ActionDialog open={dialogState.open} onClose={closeDialog} tab={dialogState.tab} />
      {remind.dialog}
      <ConfirmDialog
        open={!!pending}
        what={archiveWhat(pending?.label ?? "")}
        onCancel={() => setPending(null)}
        onConfirm={confirmArchive}
      />
    </>
  );
}
