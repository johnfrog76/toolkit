import { useMemo, useState } from "react";
import { useNavigate } from "react-router";
import {
  Badge,
  Body1,
  Button,
  Caption1,
  Dropdown,
  Option,
  ProgressBar,
  Spinner,
  makeStyles,
  mergeClasses,
  tokens,
} from "@fluentui/react-components";
import {
  AddRegular,
  CheckmarkCircleRegular,
  DocumentTextRegular,
  PinRegular,
} from "@fluentui/react-icons";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import { archiveWhat } from "./confirmWords";
import { EmptyState } from "../../shared/EmptyState";
import { StatusMessage } from "../../shared/StatusMessage";
import { thinScrollbar } from "../../shared/thinScrollbar";
import { useShellFilters } from "../../shell/cards";
import { STATUS } from "../../shell/consts";
import { useArchivePromptMutation, useGetStatusQuery, useMoveCardMutation } from "./api.ado";
import { ActionDialog } from "./ActionDialog";
import type { ActionDialogTab } from "./ActionDialog";
import { CardActionMenu, useCardActionContext } from "./CardActionMenu";
import type { CardActionContext } from "./cardActions";
import { billableOutcomeMessage, useBillableToggle } from "./useBillableToggle";
import type { CommandResponse, PromptInfo } from "./api.ado";
import { commandResultMessage } from "./cliBridge";
import { LANES, laneHint, legalMoves } from "./legalMoves";
import { laneConfigKey, useLaneLabel } from "./laneNames";
import { LaneLabelEditor } from "./LaneLabelEditor";
import { TrackerBadge, trackerName } from "./TrackerBadge";
import { BoardCover } from "./CardCover";
import { useGetEnvQuery } from "../../shell/api";
import type { Lane } from "./legalMoves";
import { filterPrompts, sprintsOf } from "./promptFilters";
import { cardPath } from "./paths";
import { countInPlay, inPlayLine } from "./inPlay";
import { useRemindAbout } from "./useRemindAbout";

// The board: the same cards as the list, arranged by where they ARE.
//
// "Cards are prompts, and agile lanes are a better view for how multiple items
// flow for human development." (the owner.) It is a self-contained
// component -- mount it on a route, in a tab, anywhere -- and it owns NO server
// state:
//
//   - it reads the SAME RTK Query cache entry the list reads (getStatus), so
//     the two cannot disagree and opening the board costs no second fetch;
//   - it polls that entry while it is mounted, because the point of the board
//     is that cards move BY THEMSELVES -- a commit, a pull request -- and a
//     board that needs a reload to notice is a poster;
//   - its one write is the existing Archive mutation, whose `invalidatesTags`
//     refetches Status. There is no optimistic update and no local copy of a
//     card: state is derived from the file, so the card moves when the file
//     says it has, and a refusal leaves it exactly where it was.

const POLL_MS = 15_000;
const DRAG_TYPE = "application/x-toolkit-card";

const useStyles = makeStyles({
  root: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalM, minWidth: 0 },
  bar: {
    display: "flex",
    alignItems: "center",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalM,
  },
  barSpacer: { flex: "1 1 auto" },
  quiet: { color: tokens.colorNeutralForeground3 },
  // The explain text gives way: it wraps inside itself so the sprint filter and
  // New card stay on its row, rather than the row wrapping New card under it.
  // Body1 (14px), not Caption1 (12px) -- the owner's rule: "12px is a bit
  // small". It is the line that explains the board to a first-time reader, so
  // it is read, not glanced at, and it gets room to be read in: 1rem 0.5rem,
  // his numbers the same day.
  barText: {
    flex: "1 1 20rem",
    minWidth: 0,
    padding: `${tokens.spacingVerticalL} ${tokens.spacingHorizontalS}`,
  },
  // Five lanes side by side, Backlog first; below that they scroll sideways INSIDE the board,
  // so the page itself never overflows (the UX audit's rule).
  //
  // The BOARD owns the height and every lane fills it -- the owner's rule: "they
  // all expand to fill the space; if I have 20 cards in a single lane each lane
  // has overflow-y." Until then lanes were top-aligned and grew with their
  // cards, so one busy lane made the whole page as tall as its longest column.
  // Now a lane's card list scrolls inside the lane, and the lane heads stay put.
  // The height is the viewport less the chrome above the board (nav, the
  // List | Boards toggle, the board's own bar), floored so a short window still
  // shows a lane, capped so a tall monitor does not draw an empty acre.
  lanes: {
    display: "grid",
    gridAutoFlow: "column",
    gridAutoColumns: "minmax(240px, 1fr)",
    gap: tokens.spacingHorizontalM,
    overflowX: "auto",
    scrollSnapType: "x proximity",
    paddingBottom: tokens.spacingVerticalS,
    alignItems: "stretch",
    height: "clamp(360px, calc(100vh - 290px), 1100px)",
    ...thinScrollbar,
  },
  lane: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalS,
    minWidth: 0,
    minHeight: 0,
    padding: tokens.spacingVerticalM,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusLarge,
    scrollSnapAlign: "start",
  },
  laneTarget: { border: `1px dashed ${tokens.colorBrandStroke1}` },
  laneOver: {
    backgroundColor: tokens.colorBrandBackground2,
    border: `2px solid ${tokens.colorBrandStroke1}`,
  },
  laneHead: { display: "flex", alignItems: "center", gap: tokens.spacingHorizontalS },
  // Indented under its lane's title, not flush with it.
  // The title is the lane; this is a sentence about it.
  laneHint: { paddingLeft: tokens.spacingHorizontalL },
  // The part of a lane that scrolls: the cards, and only the cards. minHeight: 0
  // is what lets a flex child shrink below its content and scroll instead.
  laneCards: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalS,
    flex: "1 1 auto",
    minHeight: 0,
    overflowY: "auto",
    // Room for the card's border and a focus ring at the right edge. The themed
    // scrollbar is a classic one (it takes its 6px beside the padding, not over
    // the cards), so the 2px still sits between a card and the bar.
    paddingRight: "2px",
    ...thinScrollbar,
  },
  card: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalXS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackground1,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusMedium,
    cursor: "grab",
  },
  cardBusy: { opacity: 0.55, cursor: "progress" },
  cardTop: { display: "flex", alignItems: "flex-start", gap: tokens.spacingHorizontalXS },
  cardName: {
    flex: "1 1 auto",
    minWidth: 0,
    textAlign: "left",
    font: "inherit",
    fontWeight: tokens.fontWeightSemibold,
    color: "inherit",
    background: "none",
    border: "none",
    padding: 0,
    cursor: "pointer",
    overflowWrap: "anywhere",
    ":hover": { textDecoration: "underline" },
    ":focus-visible": { outline: `2px solid ${tokens.colorStrokeFocus2}`, outlineOffset: "2px" },
  },
  cardMeta: {
    display: "flex",
    alignItems: "center",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalS,
  },
});

interface BoardCardProps {
  card: PromptInfo;
  busy: boolean;
  onOpen: () => void;
  onMove: (to: Lane) => void;
  onToggleBillable: () => void;
  onCreatePR: () => void;
  onRemind: () => void;
  context: CardActionContext;
}

function BoardCard({
  card,
  busy,
  onOpen,
  onMove,
  onToggleBillable,
  onCreatePR,
  onRemind,
  context,
}: BoardCardProps) {
  const styles = useStyles();
  const moves = legalMoves(card.status);
  const label = card.name || card.title || card.file;
  return (
    <div
      className={mergeClasses(styles.card, busy && styles.cardBusy)}
      draggable={!busy && moves.length > 0}
      aria-busy={busy}
      onDragStart={(e) => {
        e.dataTransfer.setData(DRAG_TYPE, card.file);
        e.dataTransfer.effectAllowed = "move";
      }}
    >
      {/* The card at a glance: its cover as the top of the face. No cover, no
          gap -- BoardCover draws nothing, and the face is exactly what it was. */}
      <BoardCover cover={card.cover} label={label} />
      <div className={styles.cardTop}>
        <button type="button" className={styles.cardName} onClick={onOpen} title={card.file}>
          {label}
        </button>
        {/* Everything a drag can do, without a mouse -- and everything the list's row
            offers, because it is the SAME answer (cardActions.ts). Mandatory: a board
            that only works by dragging is closed to a keyboard and to a touch screen. */}
        <CardActionMenu
          card={card}
          context={context}
          busy={busy}
          onOpenCard={onOpen}
          onMove={onMove}
          onToggleBillable={onToggleBillable}
          onCreatePR={onCreatePR}
          onRemind={onRemind}
        />
      </div>
      <div className={styles.cardMeta}>
        {/* WHERE first: whose ledger, from the card's own link. */}
        <TrackerBadge tracker={card.tracker} />
        <Caption1 className={styles.quiet}>
          {[card.type, card.id].filter(Boolean).join(" ") || card.file}
        </Caption1>
        {card.sprint && card.sprint !== "--" && !card.sprint.startsWith("(") ? (
          <Badge appearance="outline" size="small">
            {card.sprint}
          </Badge>
        ) : null}
        {/* The tracker's own pin on the card's issue, served by the agent and
            read only here -- Pin and Unpin stay on the Issues row. In the meta line, so
            the card keeps its box. */}
        {card.pinned ? (
          <Badge appearance="tint" size="small" color="brand" icon={<PinRegular />} data-pinned="">
            {`Pinned on ${trackerName(card.tracker)}`}
          </Badge>
        ) : null}
        {/* Said only when it is the exception: a card is billable unless it says otherwise. */}
        {!card.billable ? (
          <Badge appearance="tint" color="subtle" size="small">
            Not billable
          </Badge>
        ) : null}
      </div>
      {card.total > 0 ? (
        <div className={styles.cardMeta}>
          <ProgressBar
            value={card.checked / card.total}
            thickness="medium"
            color={card.checked === card.total ? "success" : "brand"}
            aria-label={`${card.checked} of ${card.total} done`}
            style={{ flex: "1 1 auto" }}
          />
          <Caption1 className={styles.quiet}>{card.progress}</Caption1>
        </div>
      ) : null}
    </div>
  );
}

export function Board() {
  const styles = useStyles();
  const navigate = useNavigate();
  const filters = useShellFilters();
  // The intro says what the Board IS: ToolKit's cards, never the tracker's
  // items. Where a card comes FROM is the last sentence, and only on a
  // tracker whose rows can make one -- and only while the tracker ANSWERS
  // (Tier 1): signed out there is no Issues tab and no work-item row, so the
  // sentence would point at a door that is not on the page.
  const { data: env } = useGetEnvQuery();
  const cardFrom =
    env?.tier !== 1
      ? null
      : env?.tracker === "github"
        ? "An issue gets a card from the Issues tab: Make a card."
        : env?.tracker === "ado"
          ? "A work item gets a card from the Focus tab: Make a card."
          : null;
  // The SAME cache entry the list reads; polled while the board is on screen.
  const { data, isLoading, isError, refetch } = useGetStatusQuery(undefined, {
    pollingInterval: POLL_MS,
    skipPollingIfUnfocused: true,
  });
  const [archive] = useArchivePromptMutation();
  const [moveCard] = useMoveCardMutation();
  const laneLabel = useLaneLabel();
  // The pencil writes spaces.<slug>.laneNames.<key> for the ACTIVE org, so it
  // needs one: absent for an archived org's retrospective (read-only, by the
  // same rule every other write on that view follows) or the moment before
  // /env has answered at all.
  const activeSlug = env?.config?.activeSpace;
  const canEditLaneNames = Boolean(activeSlug) && env?.spaceStatus !== "archive";
  const actionContext = useCardActionContext();
  const billing = useBillableToggle();
  const remind = useRemindAbout();
  const [sprint, setSprint] = useState("All");
  // Which lane a dragged card is over, if any -- every lane ahead of the card is
  // a target now, not only Done.
  const [over, setOver] = useState<Lane | null>(null);
  // The board can be the ONLY view of Home (an org with no Azure DevOps has no
  // list), so making a card cannot live on the list alone.
  // ...and, since every card offers Create PR through the one action model, the
  // same dialog opens on its "pr" tab from a card's menu.
  const [dialogTab, setDialogTab] = useState<ActionDialogTab | null>(null);
  const [pending, setPending] = useState<PromptInfo | null>(null);
  const [moving, setMoving] = useState<string | null>(null);
  const [outcome, setOutcome] = useState<{ file: string; result: CommandResponse } | null>(null);

  const all = useMemo(() => data?.prompts ?? [], [data]);
  // The WIP line counts every card in play, filters or no: a filtered view is
  // not fewer cards in play. The limit comes from /env, once.
  const inPlay = useMemo(
    () => inPlayLine(countInPlay(all), env?.config?.inPlayLimit),
    [all, env?.config?.inPlayLimit],
  );
  const sprints = useMemo(() => sprintsOf(all), [all]);
  const shown = useMemo(
    () =>
      filterPrompts(all, {
        activeRepo: filters.activeRepo,
        status: filters.stateFilter,
        text: filters.filterValue,
        sprint,
        type: filters.typeFilter,
        link: filters.linkFilter,
      }),
    [
      all,
      filters.activeRepo,
      filters.stateFilter,
      filters.filterValue,
      filters.typeFilter,
      filters.linkFilter,
      sprint,
    ],
  );

  // Pinned cards first within a lane, each group in the order it had.
  const byLane = (lane: Lane) => {
    const inLane = shown.filter((p) => p.status === lane);
    return [...inLane.filter((p) => p.pinned), ...inLane.filter((p) => !p.pinned)];
  };
  const open = (p: PromptInfo) => navigate(cardPath(p.file));

  const runArchive = async () => {
    if (!pending) return;
    const card = pending;
    setPending(null);
    setMoving(card.file);
    setOutcome(null);
    try {
      // The mutation invalidates Status; the refetch is what moves the card.
      const result = await archive({ file: card.file }).unwrap();
      setOutcome({ file: card.file, result });
    } catch {
      setOutcome({
        file: card.file,
        result: {
          command: "Archive",
          status: "error",
          exit_code: -1,
          output: null,
          error: "Could not reach the agent. Nothing was archived.",
          duration: 0,
        },
      });
    } finally {
      setMoving(null);
    }
  };

  // A person's move: Done asks first (archiving is the one move that changes
  // where the file IS); the other lanes write a line through the Move verb and
  // the refetch moves the card. No optimistic update, no copy of the answer.
  const runMove = async (card: PromptInfo, to: Lane) => {
    if (to === STATUS.done) {
      setPending(card);
      return;
    }
    setMoving(card.file);
    setOutcome(null);
    try {
      const result = await moveCard({ file: card.file, to }).unwrap();
      setOutcome({ file: card.file, result });
    } catch {
      setOutcome({
        file: card.file,
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
      setMoving(null);
    }
  };

  const onDropOn = (lane: Lane) => (e: React.DragEvent) => {
    e.preventDefault();
    setOver(null);
    const file = e.dataTransfer.getData(DRAG_TYPE);
    const card = all.find((p) => p.file === file);
    if (card && legalMoves(card.status).includes(lane)) void runMove(card, lane);
  };

  if (isLoading) return <Spinner label="Loading the board..." />;
  if (isError) {
    return (
      <EmptyState
        icon={<DocumentTextRegular />}
        tone="error"
        title="Could not load your cards"
        detail="The agent did not answer. Nothing was read."
        action={<Button onClick={() => refetch()}>Try again</Button>}
      />
    );
  }

  return (
    <section className={styles.root} aria-label="Board">
      <div className={styles.bar}>
        <Body1 className={mergeClasses(styles.quiet, styles.barText)}>
          ToolKit cards move by themselves: a new card is {laneLabel(STATUS.backlog)}, a commit is{" "}
          {laneLabel(STATUS.inProgress)}, a pull request is {laneLabel(STATUS.codeReview)}. Drop a
          card on a lane to move it yourself; on {laneLabel(STATUS.done)}, to archive it.
          {cardFrom ? ` ${cardFrom}` : ""}
        </Body1>
        <span className={styles.barSpacer} />
        {sprints.length > 0 ? (
          <Dropdown
            size="small"
            aria-label="Sprint"
            value={sprint === "All" ? "All sprints" : sprint}
            selectedOptions={[sprint]}
            onOptionSelect={(_e, d) => setSprint(d.optionValue ?? "All")}
          >
            <Option value="All">All sprints</Option>
            {sprints.map((s) => (
              <Option key={s} value={s}>
                {s}
              </Option>
            ))}
          </Dropdown>
        ) : null}
        {/* Last on the row: "New card button always follows the explain text"
            -- after the sprint filter, at the row's end. */}
        <Button
          size="small"
          appearance="primary"
          icon={<AddRegular />}
          onClick={() => setDialogTab("create")}
        >
          New card
        </Button>
      </div>

      {/* The result of the one write, said once, and announced. */}
      <div aria-live="polite">
        {outcome ? (
          <StatusMessage
            status={outcome.result.status === "success" ? "success" : "error"}
            onDismiss={() => setOutcome(null)}
          >
            {outcome.result.status === "success"
              ? outcome.result.command === "Move"
                ? `Moved ${outcome.file}`
                : `Archived ${outcome.file}`
              : commandResultMessage(outcome.result, `${outcome.file} was not moved`)}
          </StatusMessage>
        ) : null}
        {billing.outcome ? (
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
        ) : null}
        {remind.added ? (
          <StatusMessage status="success" onDismiss={remind.clearAdded}>
            {remind.added}
          </StatusMessage>
        ) : null}
      </div>

      <div className={styles.lanes}>
        {LANES.map((lane) => {
          const isDone = lane === STATUS.done;
          const cards = isDone ? [] : byLane(lane);
          return (
            <div
              key={lane}
              role="group"
              aria-label={`${laneLabel(lane)}, ${isDone ? "drop a card here to archive it" : `${cards.length} cards`}`}
              className={mergeClasses(
                styles.lane,
                isDone && styles.laneTarget,
                over === lane && styles.laneOver,
              )}
              // Every lane is a target now: Backlog takes an Active card back, Active
              // takes a planned one into play. What a drop may do is legalMoves'
              // answer for the card, checked in onDropOn -- a drag cannot be read
              // until it lands.
              onDragOver={(e) => {
                if (e.dataTransfer.types.includes(DRAG_TYPE)) {
                  e.preventDefault();
                  setOver(lane);
                }
              }}
              onDragLeave={() => setOver(null)}
              onDrop={onDropOn(lane)}
            >
              <div className={styles.laneHead}>
                <LaneLabelEditor
                  label={laneLabel(lane)}
                  configKey={
                    canEditLaneNames && activeSlug ? laneConfigKey(activeSlug, lane) : null
                  }
                />
                {!isDone ? (
                  <Badge appearance="filled" color="informative" size="small">
                    {cards.length}
                  </Badge>
                ) : null}
                {/* The WIP line rides the Active column's head: every lane of
                    current/ counted, amber (the warning tokens) past the number.
                    A line the board says, never a gate -- no drop is refused. */}
                {lane === STATUS.active && inPlay ? (
                  <Badge
                    appearance={inPlay.past ? "filled" : "tint"}
                    color={inPlay.past ? "warning" : "subtle"}
                    size="small"
                    data-in-play={inPlay.past ? "past" : "within"}
                  >
                    {inPlay.text}
                  </Badge>
                ) : null}
              </div>
              {!isDone ? (
                <Caption1 className={mergeClasses(styles.quiet, styles.laneHint)}>
                  {laneHint(lane)}
                </Caption1>
              ) : null}
              {isDone ? (
                <EmptyState
                  icon={<CheckmarkCircleRegular />}
                  title="Drop a card here"
                  detail="It is archived, with today's date. Done is a place cards go, not a list this page keeps."
                />
              ) : cards.length === 0 ? (
                <EmptyState
                  icon={<DocumentTextRegular />}
                  tone={all.length > 0 && shown.length < all.length ? "filtered" : "empty"}
                  title={`Nothing ${laneLabel(lane).toLowerCase()}`}
                />
              ) : (
                <div className={styles.laneCards}>
                  {cards.map((p) => (
                    <BoardCard
                      key={p.file}
                      card={p}
                      busy={moving === p.file || billing.busyFile === p.file}
                      onOpen={() => open(p)}
                      onMove={(to) => void runMove(p, to)}
                      onToggleBillable={() => billing.toggle(p)}
                      onCreatePR={() => setDialogTab("pr")}
                      onRemind={() => remind.open(p)}
                      context={actionContext}
                    />
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>

      <ConfirmDialog
        open={pending !== null}
        what={archiveWhat(pending?.name || pending?.title || pending?.file || "")}
        onCancel={() => setPending(null)}
        onConfirm={runArchive}
      />
      <ActionDialog
        open={dialogTab !== null}
        onClose={() => setDialogTab(null)}
        tab={dialogTab ?? "create"}
      />
      {remind.dialog}
    </section>
  );
}
