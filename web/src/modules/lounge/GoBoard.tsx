/**
 * The 9x9 coffee-house Go grid (D-L21, from
 * the owner's hub note).
 *
 * A PLACEMENT SANDBOX, not an engine: a grid of box-drawing glyphs, ● and ○
 * at the intersections, a ghost stone where the pointer rests, black and
 * white in turn, and a double-click clears a stone -- the note's manual
 * capture. No liberties, no ko, no suicide rule, no score, no captured
 * count (a count is a numeral, and the room has none), no coordinates.
 * The note's "3-second delay on play" is the deliberate placing: a short
 * settle, instant under reduced motion.
 *
 * Drives from the palette and the tokens (D-L23): grid lines, stones, ghost
 * and accent are the theme's own, so the board wears a skin for free. The
 * board persists per browser (usePersistedState's local flavour), so a game
 * left mid-way is there tomorrow; "Clear board" is the one quiet control.
 */
import { useState } from "react";
import {
  Button,
  Caption1,
  Subtitle2,
  makeStyles,
  mergeClasses,
  shorthands,
  tokens,
} from "@fluentui/react-components";
import { PageCard } from "../../shared/PageCard";
import { useLocalPersistedState } from "../../shared/usePersistedState";

export const GO_SIZE = 9;
export const GO_KEY = "toolkit-lounge-go";

export type Stone = "b" | "w";
export interface GoState {
  /** Row-major, GO_SIZE * GO_SIZE long. */
  board: (Stone | null)[];
  next: Stone;
}

export const EMPTY_GO: GoState = {
  board: Array<Stone | null>(GO_SIZE * GO_SIZE).fill(null),
  next: "b",
};

export function isGoState(v: unknown): v is GoState {
  const g = v as GoState;
  return (
    !!g &&
    typeof g === "object" &&
    Array.isArray(g.board) &&
    g.board.length === GO_SIZE * GO_SIZE &&
    g.board.every((s) => s === null || s === "b" || s === "w") &&
    (g.next === "b" || g.next === "w")
  );
}

const GLYPH: Record<Stone, string> = { b: "●", w: "○" };
const WORD: Record<Stone, string> = { b: "black", w: "white" };

/** The line glyph an EMPTY intersection draws, by where it sits. */
export function lineGlyph(row: number, col: number): string {
  const top = row === 0;
  const bottom = row === GO_SIZE - 1;
  const left = col === 0;
  const right = col === GO_SIZE - 1;
  if (top && left) return "┌";
  if (top && right) return "┐";
  if (bottom && left) return "└";
  if (bottom && right) return "┘";
  if (top) return "┬";
  if (bottom) return "┴";
  if (left) return "├";
  if (right) return "┤";
  return "┼";
}

// Letters both ways, so an intersection's name carries no numeral.
const ROWS = "abcdefghj";
const COLS = "ABCDEFGHJ";

const useStyles = makeStyles({
  board: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: "1.35rem",
    lineHeight: 1,
    color: tokens.colorNeutralForeground3,
    display: "inline-block",
    userSelect: "none",
    padding: tokens.spacingVerticalS,
  },
  row: {
    display: "flex",
    alignItems: "center",
  },
  // The lines are DRAWN, one horizontal and one vertical hairline through
  // each intersection in the stroke token, so they meet exactly; typed
  // box-drawing glyphs read as dashes between the cells.
  cell: {
    position: "relative",
    width: "1.4em",
    height: "1.4em",
    padding: 0,
    margin: 0,
    border: "none",
    background: "transparent",
    font: "inherit",
    lineHeight: 1,
    color: "inherit",
    cursor: "pointer",
    borderRadius: tokens.borderRadiusSmall,
    ":focus-visible": {
      outline: `1px solid ${tokens.colorBrandForeground2}`,
    },
    "::before": {
      content: '""',
      position: "absolute",
      top: "50%",
      left: 0,
      right: 0,
      height: "1px",
      backgroundColor: tokens.colorNeutralStroke1,
    },
    "::after": {
      content: '""',
      position: "absolute",
      left: "50%",
      top: 0,
      bottom: 0,
      width: "1px",
      backgroundColor: tokens.colorNeutralStroke1,
    },
  },
  firstCol: { "::before": { left: "50%" } },
  lastCol: { "::before": { right: "50%" } },
  firstRow: { "::after": { top: "50%" } },
  lastRow: { "::after": { bottom: "50%" } },
  // A stone IS a disc, sitting on the lines and covering the crossing
  // beneath it: black is the foreground token filled, white the background
  // token with the foreground as its rim. The glyphs stay in the row's
  // words and the labels, not on the board.
  disc: {
    position: "relative",
    // Above the button's own ::after, which is painted after its children.
    zIndex: 1,
    display: "inline-block",
    width: "1em",
    height: "1em",
    borderRadius: "50%",
    boxSizing: "border-box",
  },
  discBlack: {
    backgroundColor: tokens.colorNeutralForeground1,
  },
  discWhite: {
    backgroundColor: tokens.colorNeutralBackground1,
    ...shorthands.border("1px", "solid", tokens.colorNeutralForeground1),
  },
  // The ghost stone: where the pointer rests on an empty point, the next
  // colour's glyph, faint, in the accent.
  empty: {
    ":hover .p20-go-ghost": {
      opacity: 0.5,
    },
  },
  ghost: {
    position: "relative",
    opacity: 0,
    color: tokens.colorBrandForeground2,
    pointerEvents: "none",
  },
  stone: {
    color: tokens.colorNeutralForeground1,
  },
  // The deliberate placing: a stone arrives, it does not appear.
  settle: {
    animationName: {
      from: { opacity: 0, transform: "scale(0.6)" },
      to: { opacity: 1, transform: "scale(1)" },
    },
    animationDuration: "0.5s",
    animationTimingFunction: "ease-out",
    "@media (prefers-reduced-motion: reduce)": {
      animationDuration: "0.01s",
    },
  },
  turn: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase100,
    letterSpacing: "0.12em",
    textTransform: "uppercase",
    color: tokens.colorNeutralForeground3,
    background: "transparent",
    border: "none",
    padding: 0,
    cursor: "pointer",
  },
});

export function GoBoard() {
  const styles = useStyles();
  const { value: game, setValue: setGame } = useLocalPersistedState<GoState>(
    GO_KEY,
    EMPTY_GO,
    isGoState,
  );
  const [settling, setSettling] = useState<number | null>(null);

  const place = (ix: number) => {
    if (game.board[ix] !== null) return;
    const board = game.board.slice();
    board[ix] = game.next;
    setGame({ board, next: game.next === "b" ? "w" : "b" });
    setSettling(ix);
  };
  const lift = (ix: number) => {
    if (game.board[ix] === null) return;
    const board = game.board.slice();
    board[ix] = null;
    setGame({ ...game, board });
    setSettling(null);
  };
  const pass = () => setGame({ ...game, next: game.next === "b" ? "w" : "b" });
  const clear = () => {
    setGame(EMPTY_GO);
    setSettling(null);
  };

  return (
    <PageCard
      scrollable
      headerLeft={<Subtitle2>Go</Subtitle2>}
      headerRight={
        <Button size="small" appearance="subtle" onClick={clear}>
          Clear board
        </Button>
      }
      footerLeft={
        <button
          type="button"
          className={styles.turn}
          onClick={pass}
          aria-label={`${WORD[game.next]} to play; pass`}
        >
          {GLYPH[game.next]} {WORD[game.next]} to play
        </button>
      }
      footerRight={<Caption1>a place to put stones · double-click lifts one</Caption1>}
    >
      <div className={styles.board} role="group" aria-label="Go board">
        {Array.from({ length: GO_SIZE }, (_, r) => (
          <div key={r} className={styles.row}>
            {Array.from({ length: GO_SIZE }, (_, c) => {
              const ix = r * GO_SIZE + c;
              const stone = game.board[ix];
              return (
                <button
                  key={c}
                  type="button"
                  className={mergeClasses(
                    styles.cell,
                    c === 0 && styles.firstCol,
                    c === GO_SIZE - 1 && styles.lastCol,
                    r === 0 && styles.firstRow,
                    r === GO_SIZE - 1 && styles.lastRow,
                    stone ? styles.stone : styles.empty,
                  )}
                  aria-label={`${ROWS[r]}${COLS[c]}${stone ? `, ${WORD[stone]}` : ""}`}
                  onClick={() => place(ix)}
                  onDoubleClick={() => lift(ix)}
                >
                  {stone ? (
                    <span
                      className={mergeClasses(
                        styles.disc,
                        stone === "b" ? styles.discBlack : styles.discWhite,
                        settling === ix && styles.settle,
                      )}
                      aria-hidden
                    />
                  ) : (
                    <span className={mergeClasses(styles.ghost, "p20-go-ghost")} aria-hidden>
                      {GLYPH[game.next]}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        ))}
      </div>
    </PageCard>
  );
}
