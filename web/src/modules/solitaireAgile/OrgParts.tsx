import { useId } from "react";
import type { ReactNode } from "react";
import { Button, makeStyles, mergeClasses } from "@fluentui/react-components";
import { SIZE } from "./orgChart";

// The pieces every seat on the Org page is built from: the office door with its
// wall, and the plate under it. The colours are the cast-skin mock's: the
// frame, the cream plate and its ink. They are a picture's, the same in every
// theme; the page around them takes the theme's.

/** The mock's door frame, and its darker sill. */
export const FRAME = "#33416a";
export const FRAME_SILL = "#232e4d";
/** The plate: cream, dark ink for the position, a softer one for who sits there. */
const PLATE = "#f6f1e4";
const PLATE_INK = "#1c2434";
const PLATE_SOFT = "#56627f";
/** The mock's one card shadow, light from the top left. */
const CARD_SHADOW = "drop-shadow(4px 6px 4.5px rgba(4, 8, 20, 0.34))";

const useStyles = makeStyles({
  cell: {
    position: "relative",
    width: `${SIZE.cell}px`,
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    flexShrink: 0,
  },
  poolCell: { width: `${SIZE.poolCell}px` },
  door: { display: "block", filter: CARD_SHADOW },
  plate: {
    position: "relative",
    marginTop: `-${SIZE.plateLift}px`,
    height: `${SIZE.plate}px`,
    // One width for every plate a seat can have -- vacant with Assign, a model
    // with Change, a preview's with neither -- so nothing moves when it changes.
    minWidth: `${SIZE.plateWidth}px`,
    maxWidth: "100%",
    boxSizing: "border-box",
    paddingLeft: "12px",
    paddingRight: "12px",
    display: "flex",
    flexDirection: "column",
    justifyContent: "center",
    alignItems: "center",
    borderRadius: "7px",
    backgroundColor: PLATE,
    // The mock's plate has a thin darker band along its foot.
    boxShadow: "inset 0 -3.5px 0 rgba(0, 0, 0, 0.1)",
    filter: CARD_SHADOW,
    color: PLATE_INK,
    fontFamily: `-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif`,
    whiteSpace: "nowrap",
  },
  // Who sits there, and the seat's button: one line, as tall as the button
  // whether or not there is one, so a preview's plate and a saved org's match.
  line: {
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    columnGap: "6px",
    minHeight: "24px",
    maxWidth: "100%",
    fontSize: "12px",
    lineHeight: "16px",
    fontWeight: 700,
  },
  who: { overflow: "hidden", textOverflow: "ellipsis", minWidth: 0 },
  dot: { color: PLATE_SOFT, flexShrink: 0 },
  // A small subtle button in the plate's own ink: the plate is cream in every theme.
  plateButton: {
    flexShrink: 0,
    minWidth: "auto",
    height: "24px",
    paddingLeft: "4px",
    paddingRight: "4px",
    color: PLATE_INK,
    fontSize: "12px",
    fontWeight: 600,
    textDecorationLine: "underline",
    textUnderlineOffset: "2px",
    ":hover": { color: PLATE_INK, backgroundColor: "rgba(28, 36, 52, 0.08)" },
    ":hover:active": { color: PLATE_INK, backgroundColor: "rgba(28, 36, 52, 0.14)" },
  },
  where: {
    fontSize: "10.5px",
    lineHeight: "13px",
    fontWeight: 500,
    color: PLATE_SOFT,
    overflow: "hidden",
    textOverflow: "ellipsis",
    maxWidth: "100%",
  },
});

/** An arch: straight sides, rounded top corners, a flat foot. */
function arch(x: number, y: number, w: number, h: number, r: number): string {
  return `M ${x} ${y + h} V ${y + r} Q ${x} ${y} ${x + r} ${y} H ${x + w - r} Q ${x + w} ${y} ${x + w} ${y + r} V ${y + h} Z`;
}

/**
 * An office door: the frame, the wall in its level's colour lit from the top
 * left, whatever stands in it (`children`, drawn in the door's own pixels), and
 * the sill. `dim` darkens the wall, for a seat nobody sits in.
 */
export function OfficeDoor({
  wall,
  shade,
  width = SIZE.door.width,
  dim = false,
  children,
}: {
  wall: string;
  shade: string;
  width?: number;
  dim?: boolean;
  children?: ReactNode;
}) {
  const styles = useStyles();
  const h = SIZE.door.height;
  const id = `od${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;
  const inner = arch(7, 7, width - 14, h - 14, 28);
  return (
    <svg
      className={styles.door}
      width={width}
      height={h}
      viewBox={`0 0 ${width} ${h}`}
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <clipPath id={`${id}-in`}>
          <path d={inner} />
        </clipPath>
        <linearGradient id={`${id}-wall`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#fff" stopOpacity="0.16" />
          <stop offset="0.55" stopColor="#fff" stopOpacity="0" />
          <stop offset="1" stopColor="#000" stopOpacity="0.16" />
        </linearGradient>
      </defs>
      <path d={arch(0, 0, width, h, 34)} fill={FRAME} />
      <path d={inner} fill={shade} />
      <g clipPath={`url(#${id}-in)`}>
        <path d={inner} fill={wall} transform="translate(5 5)" />
        <rect width={width} height={h} fill={`url(#${id}-wall)`} />
        {dim ? <rect width={width} height={h} fill="#0d121e" opacity="0.55" /> : null}
        {children}
      </g>
      <rect x="0" y={h - 7} width={width} height="7" fill={FRAME_SILL} />
    </svg>
  );
}

/** What a plate says on hover: its line, where the seat is, and the session it is. */
export function plateHover(line: string, where?: string, session?: string): string {
  const at = where ? `${line}, ${where}` : line;
  return session ? `${at}. Session: ${session}` : at;
}

/** The plate: who sits there -- vacant, the model, the person, or pool -- and
 *  the seat's button beside it (`vacant · Assign`, a model's name and `Change`), where
 *  the seat serves under it, and the whole of it, the position's title first,
 *  with the seat's session, on hover. The title itself is the sign's. */
export function Plate({
  position,
  who,
  where,
  session,
  space,
  action,
}: {
  position: string;
  who: string;
  where?: string;
  session?: string;
  /** The Space the seat serves, for the hover; `where` otherwise. */
  space?: string;
  /** The seat's Assign or Change button; absent on a preview and a pool. */
  action?: ReactNode;
}) {
  const styles = useStyles();
  return (
    <div
      className={styles.plate}
      data-testid="org-plate"
      title={plateHover(`${position} · ${who}`, space ?? where, session)}
    >
      <span className={styles.line} data-testid="org-plate-line">
        <span className={styles.who} data-testid="org-plate-who">
          {who}
        </span>
        {action ? (
          <>
            <span className={styles.dot} aria-hidden="true">
              ·
            </span>
            {action}
          </>
        ) : null}
      </span>
      {where ? (
        <span className={styles.where} data-testid="org-plate-where">
          {where}
        </span>
      ) : null}
    </div>
  );
}

/** Assign or Change, on a plate: a small subtle button with the seat in its name. */
export function PlateButton({
  label,
  children,
  disabled,
  onClick,
}: {
  label: string;
  children: ReactNode;
  disabled?: boolean;
  onClick: () => void;
}) {
  const styles = useStyles();
  return (
    <Button
      size="small"
      appearance="subtle"
      className={styles.plateButton}
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      data-testid="org-seat-action"
    >
      {children}
    </Button>
  );
}

/** One seat's column: its door, its plate, and anything under them. */
export function SeatCell({
  pool = false,
  state,
  children,
}: {
  pool?: boolean;
  state: "staffed" | "vacant" | "pool";
  children: ReactNode;
}) {
  const styles = useStyles();
  return (
    <div
      className={mergeClasses(styles.cell, pool && styles.poolCell)}
      data-testid="org-seat"
      data-state={state}
    >
      {children}
    </div>
  );
}
