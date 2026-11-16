import { Caption1, Subtitle2, makeStyles, mergeClasses, tokens } from "@fluentui/react-components";
import { DocumentTextRegular, OrganizationRegular } from "@fluentui/react-icons";
import { Link } from "react-router";
import { EmptyState } from "../../shared/EmptyState";
import type { EmptyMessage } from "../../shared/EmptyState";
import { PanelFrame } from "../../shared/PanelFrame";
import { RefinedBust, bustHeight } from "../../shared/refinedFaces";
import { promptPath } from "../studio/paths";
import { useGetOrgChartQuery } from "./api.solitaireAgile";
import type { OrgPosition, OrgRefusal } from "./api.solitaireAgile";
import { OfficeDoor, Plate, SeatCell } from "./OrgParts";
import type { PlacedOffice } from "./orgChart";
import {
  OFFICE_HEIGHT,
  POOL_WORD,
  SIZE,
  layoutChart,
  levelWall,
  plateWho,
  positionFaces,
  seatFace,
  seatWhere,
} from "./orgChart";
import { VacantSeat } from "./VacantSeat";

// The Org tab (docs/modules/solitaire-agile.md, "The web UI"): Team Agile's
// fourth page, after Standup, Triage and Releases. It draws the tree the agent
// serves from the hub's org.json (GET /api/ritual/org) and nothing else: offices
// by level, the walls coloured by level, each position centred over the ones
// that report to it, each seat a card with a bust and a plate. A staffed seat is
// in colour; a vacant one is VacantSeat; a position with no seats is a pool,
// one card with its default-model line; the owner's seat is a person.
//
// An office with a prompt is a link to it in the Studio's reading room
// (promptPath of the position's promptRef); the owner and the pool have none,
// and are not links. The page is a READ: it chooses no tree, draws no active
// state, and writes nothing.

const useStyles = makeStyles({
  body: { display: "flex", flexDirection: "column", minWidth: 0 },
  subtitle: { color: tokens.colorNeutralForeground3, alignSelf: "center" },
  // The chart is as wide as its tree; a narrow window scrolls it, not the page.
  scroller: {
    overflowX: "auto",
    paddingTop: tokens.spacingVerticalL,
    paddingBottom: tokens.spacingVerticalL,
  },
  chart: { position: "relative", marginLeft: "auto", marginRight: "auto" },
  lines: { position: "absolute", left: 0, top: 0, overflow: "visible" },
  office: {
    position: "absolute",
    boxSizing: "border-box",
    padding: `${SIZE.pad}px`,
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    borderRadius: "16px",
    color: "inherit",
    textDecorationLine: "none",
  },
  // Several seats in one office: a row of cards in a room of their own.
  room: {
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    outlineWidth: "1px",
    outlineStyle: "solid",
    outlineColor: tokens.colorNeutralStroke2,
  },
  link: {
    cursor: "pointer",
    ":hover": { backgroundColor: tokens.colorNeutralBackground1Hover },
    ":hover .org-sign-text": { textDecorationLine: "underline" },
    ":focus-visible": {
      outlineWidth: "2px",
      outlineStyle: "solid",
      outlineColor: tokens.colorStrokeFocus2,
    },
  },
  sign: {
    height: `${SIZE.sign}px`,
    display: "flex",
    alignItems: "flex-start",
    columnGap: tokens.spacingHorizontalXS,
    maxWidth: "100%",
    color: tokens.colorNeutralForeground2,
    fontSize: tokens.fontSizeBase200,
    lineHeight: tokens.lineHeightBase200,
    fontWeight: tokens.fontWeightSemibold,
    whiteSpace: "nowrap",
  },
  signText: { overflow: "hidden", textOverflow: "ellipsis" },
  seats: { display: "flex", columnGap: `${SIZE.seatGap}px` },
  poolLine: {
    marginTop: tokens.spacingVerticalS,
    maxWidth: `${SIZE.poolCell}px`,
    textAlign: "center",
    color: tokens.colorNeutralForeground2,
    fontSize: tokens.fontSizeBase200,
    lineHeight: tokens.lineHeightBase200,
  },
});

// -- One office's cards -----------------------------------------------------

const BUST_W = 96;
const POOL_BUST_W = 72;
const POOL_STEP = 42;

/** The bust's place in a door: centred, standing on the sill. */
const bustY = (width: number) => SIZE.door.height - 7 - bustHeight(width) + 2.5;

function StaffedSeat({
  position,
  seatIndex,
  order,
}: {
  position: OrgPosition;
  seatIndex: number;
  order: number;
}) {
  const seat = position.seats[seatIndex];
  const { wall, shade } = levelWall(position.level);
  const where = seatWhere(seat);
  return (
    <SeatCell state="staffed">
      <OfficeDoor wall={wall} shade={shade}>
        <RefinedBust
          face={seatFace(position, seatIndex, order)}
          width={BUST_W}
          x={(SIZE.door.width - BUST_W) / 2}
          y={bustY(BUST_W)}
        />
      </OfficeDoor>
      <Plate position={position.title} who={plateWho(seat)} where={where || undefined} />
    </SeatCell>
  );
}

/** A position with no seats: one wider card, a few of its faces side by side,
 *  `POSITION · pool` on the plate and its default-model line under it. */
function PoolSeat({ position, order }: { position: OrgPosition; order: number }) {
  const styles = useStyles();
  const { wall, shade } = levelWall(position.level);
  const faces = positionFaces(position, order);
  const span = (faces.length - 1) * POOL_STEP + POOL_BUST_W;
  const start = (SIZE.poolDoor.width - span) / 2;
  return (
    <SeatCell state="pool" pool>
      <OfficeDoor wall={wall} shade={shade} width={SIZE.poolDoor.width}>
        {faces.map((face, i) => (
          <RefinedBust
            key={`${face}-${i}`}
            face={face}
            width={POOL_BUST_W}
            x={start + i * POOL_STEP}
            y={bustY(POOL_BUST_W)}
          />
        ))}
      </OfficeDoor>
      <Plate position={position.title} who={POOL_WORD} />
      {position.defaultModel ? (
        <Caption1 className={styles.poolLine} data-testid="org-pool-line">
          {position.defaultModel}
        </Caption1>
      ) : null}
    </SeatCell>
  );
}

function Office({ office }: { office: PlacedOffice }) {
  const styles = useStyles();
  const p = office.position;
  const room = p.seats.length > 1;
  const style = { left: office.left, top: office.top, width: office.width };
  const body = (
    <>
      <div className={styles.sign}>
        {p.promptTitle ? (
          <>
            <DocumentTextRegular aria-hidden />
            <span className={mergeClasses("org-sign-text", styles.signText)}>{p.promptTitle}</span>
          </>
        ) : null}
      </div>
      <div className={styles.seats}>
        {p.seats.length === 0 ? (
          <PoolSeat position={p} order={office.order} />
        ) : (
          p.seats.map((seat, i) =>
            seat.state === "vacant" ? (
              <VacantSeat
                key={seat.id}
                seatId={seat.id}
                position={p.title}
                level={p.level}
                where={seatWhere(seat) || undefined}
              />
            ) : (
              <StaffedSeat key={seat.id} position={p} seatIndex={i} order={office.order} />
            ),
          )
        )}
      </div>
    </>
  );
  const className = mergeClasses(styles.office, room && styles.room);
  if (p.promptRef) {
    return (
      <Link
        to={promptPath(p.promptRef)}
        className={mergeClasses(className, styles.link)}
        style={style}
        title={`Open the prompt: ${p.promptTitle ?? p.title}`}
        data-testid="org-office"
        data-position={p.id}
      >
        {body}
      </Link>
    );
  }
  return (
    <div className={className} style={style} data-testid="org-office" data-position={p.id}>
      {body}
    </div>
  );
}

// -- The lines between offices ----------------------------------------------

/** From the foot of an office (its plate, or its room) down to the top of each
 *  office that reports to it: down, across, down. */
function Lines({ lines, width, height }: ReturnType<typeof layoutChart>) {
  const styles = useStyles();
  const foot = (o: PlacedOffice) =>
    o.top + (o.position.seats.length > 1 ? OFFICE_HEIGHT : OFFICE_HEIGHT - SIZE.pad);
  // Into a room at its top; into a single office at its sign, or at its door
  // where it has no sign (no prompt), so the line never stops short.
  const head = (o: PlacedOffice) =>
    o.top + (o.position.seats.length > 1 ? 0 : SIZE.pad + (o.position.promptTitle ? 0 : SIZE.sign));
  return (
    <svg className={styles.lines} width={width} height={height} aria-hidden="true">
      {lines.map(({ from, to }) => {
        const y1 = foot(from);
        const y2 = head(to);
        const mid = Math.round((y1 + y2) / 2);
        return (
          <path
            key={`${from.position.id}-${to.position.id}`}
            d={`M ${from.cx} ${y1} V ${mid} H ${to.cx} V ${y2}`}
            fill="none"
            stroke={tokens.colorNeutralStrokeAccessible}
            strokeWidth="2.2"
            strokeLinejoin="round"
            strokeLinecap="round"
          />
        );
      })}
    </svg>
  );
}

// -- The page ---------------------------------------------------------------

/** What the agent said when it served no chart: its status and its detail. */
export function orgRefusal(error: unknown): { status?: number | string } & Partial<OrgRefusal> {
  const e = error as { status?: number | string; data?: { detail?: unknown } } | undefined;
  const detail = e?.data?.detail;
  if (detail && typeof detail === "object") {
    const d = detail as Partial<OrgRefusal>;
    return { status: e?.status, kind: d.kind, message: d.message };
  }
  return { status: e?.status, message: typeof detail === "string" ? detail : undefined };
}

/** What the page says for a tree the org file does not have. */
export const UNKNOWN_TREE_DETAIL =
  "The chart asked for is not one of the trees in the hub's org.json. Nothing was drawn.";

/** The no-chart states: no file (404), a file that fails its checks (409), a
 *  tree the file does not have (422, said in the page's words: the agent's
 *  sentence is the terminal's), and anything else as the error it is. */
function noChart(error: unknown, icon: EmptyMessage["icon"]): EmptyMessage {
  const r = orgRefusal(error);
  if (r.status === 404 && (r.kind === "missing" || r.kind === "no-hub")) {
    return { icon, title: "No org chart yet", detail: r.message };
  }
  if (r.status === 409 && r.kind) {
    return { icon, tone: "error", title: "The org chart could not be read", detail: r.message };
  }
  if (r.status === 422 && r.kind === "unknown-tree") {
    return {
      icon,
      tone: "error",
      title: "That org chart is not in the file",
      detail: UNKNOWN_TREE_DETAIL,
    };
  }
  return {
    icon,
    tone: "error",
    title: "Could not read the org chart",
    detail: r.message ?? "The agent did not answer. Nothing was read.",
  };
}

export function OrgPage() {
  const styles = useStyles();
  const { data, isLoading, error } = useGetOrgChartQuery();
  const icon = <OrganizationRegular />;
  const layout = data && !error ? layoutChart(data.tree.positions) : null;
  const empty = isLoading ? undefined : !data || error ? (
    <EmptyState {...noChart(error, icon)} />
  ) : undefined;

  return (
    <div className={styles.body}>
      <PanelFrame
        loading={isLoading}
        loadingLabel="Reading the org chart..."
        empty={empty}
        headerLeft={
          <>
            {icon}
            <Subtitle2 as="h1">Org chart</Subtitle2>
            {data && !error ? (
              <Caption1 className={styles.subtitle} data-testid="org-subtitle">
                {data.tree.name}
              </Caption1>
            ) : null}
          </>
        }
      >
        {layout ? (
          <div className={styles.scroller}>
            <div
              className={styles.chart}
              style={{ width: layout.width, height: layout.height }}
              data-testid="org-chart"
            >
              <Lines {...layout} />
              {layout.offices.map((o) => (
                <Office key={o.position.id} office={o} />
              ))}
            </div>
          </div>
        ) : null}
      </PanelFrame>
    </div>
  );
}
