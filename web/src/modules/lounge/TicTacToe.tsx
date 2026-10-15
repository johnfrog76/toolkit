/**
 * Tic-tac-toe (D-L21; the owner: "a
 * game of tic-tac-toe. Idk", and later: "Tic-tac-toe -- perfect").
 *
 * You are ✕; a POLITE opponent plays ○ at random the moment you move -- it
 * is company, not competition. The footer says whose move it is, or how it
 * ended, in the caption voice; New game clears it. No tally, no streak, no
 * numerals (the room has none). Drives from the palette and the tokens
 * (D-L23), in the Go grid's glyph register. The board persists per browser.
 */
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

export const TTT_KEY = "toolkit-lounge-tictactoe";

export type Mark = "x" | "o";
export interface TttState {
  board: (Mark | null)[];
}

export const EMPTY_TTT: TttState = { board: Array<Mark | null>(9).fill(null) };

export function isTttState(v: unknown): v is TttState {
  const s = v as TttState;
  return (
    !!s &&
    typeof s === "object" &&
    Array.isArray(s.board) &&
    s.board.length === 9 &&
    s.board.every((m) => m === null || m === "x" || m === "o")
  );
}

const LINES: [number, number, number][] = [
  [0, 1, 2],
  [3, 4, 5],
  [6, 7, 8],
  [0, 3, 6],
  [1, 4, 7],
  [2, 5, 8],
  [0, 4, 8],
  [2, 4, 6],
];

export function winner(board: (Mark | null)[]): Mark | null {
  for (const [a, b, c] of LINES) {
    if (board[a] && board[a] === board[b] && board[a] === board[c]) return board[a];
  }
  return null;
}

/** The polite opponent: any empty cell, by chance. */
export function politeReply(board: (Mark | null)[], random: () => number = Math.random): number {
  const empty = board.map((m, i) => (m === null ? i : -1)).filter((i) => i >= 0);
  return empty[Math.floor(random() * empty.length)] ?? -1;
}

const GLYPH: Record<Mark, string> = { x: "✕", o: "○" };
const ROWS = "abc";
const COLS = "ABC";

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
  // The grid is DRAWN by the cells' own edges, in the stroke token, so the
  // lines meet the cells exactly whatever the font; typed rules of dashes
  // never lined up with them (the owner: "the game ascii not right").
  colEdge: {
    ...shorthands.borderRight("1px", "solid", tokens.colorNeutralStroke1),
  },
  rowEdge: {
    ...shorthands.borderBottom("1px", "solid", tokens.colorNeutralStroke1),
  },
  cell: {
    position: "relative",
    width: "2em",
    height: "2em",
    padding: 0,
    margin: 0,
    border: "none",
    background: "transparent",
    font: "inherit",
    lineHeight: 1,
    color: "inherit",
    cursor: "pointer",
    ":focus-visible": {
      outline: `1px solid ${tokens.colorBrandForeground2}`,
      outlineOffset: "-2px",
    },
  },
  empty: {
    ":hover": {
      color: "transparent",
    },
    ":hover::after": {
      content: "attr(data-ghost)",
      position: "absolute",
      inset: 0,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      color: tokens.colorBrandForeground2,
      opacity: 0.5,
    },
  },
  mark: {
    color: tokens.colorNeutralForeground1,
  },
  settle: {
    animationName: {
      from: { opacity: 0, transform: "scale(0.6)" },
      to: { opacity: 1, transform: "scale(1)" },
    },
    animationDuration: "0.4s",
    animationTimingFunction: "ease-out",
    "@media (prefers-reduced-motion: reduce)": {
      animationDuration: "0.01s",
    },
  },
  status: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase100,
    letterSpacing: "0.12em",
    textTransform: "uppercase",
    color: tokens.colorNeutralForeground3,
  },
});

export function TicTacToe() {
  const styles = useStyles();
  const { value: game, setValue: setGame } = useLocalPersistedState<TttState>(
    TTT_KEY,
    EMPTY_TTT,
    isTttState,
  );
  const won = winner(game.board);
  const full = game.board.every((m) => m !== null);
  const over = won !== null || full;

  const play = (ix: number) => {
    if (over || game.board[ix] !== null) return;
    const board = game.board.slice();
    board[ix] = "x";
    if (!winner(board) && board.some((m) => m === null)) {
      const reply = politeReply(board);
      if (reply >= 0) board[reply] = "o";
    }
    setGame({ board });
  };

  const status =
    won === "x" ? "✕ wins" : won === "o" ? "○ wins" : full ? "a draw" : "your move · ✕";

  return (
    <PageCard
      scrollable
      headerLeft={<Subtitle2>Tic-tac-toe</Subtitle2>}
      headerRight={
        <Button size="small" appearance="subtle" onClick={() => setGame(EMPTY_TTT)}>
          New game
        </Button>
      }
      footerLeft={<span className={styles.status}>{status}</span>}
      footerRight={<Caption1>a polite opponent · it plays where it likes</Caption1>}
    >
      <div className={styles.board} role="group" aria-label="Tic-tac-toe board">
        {[0, 1, 2].map((r) => (
          <div key={r} className={styles.row}>
            {[0, 1, 2].map((c) => {
              const ix = r * 3 + c;
              const mark = game.board[ix];
              return (
                <button
                  key={c}
                  type="button"
                  className={mergeClasses(
                    styles.cell,
                    c < 2 && styles.colEdge,
                    r < 2 && styles.rowEdge,
                    mark ? styles.mark : styles.empty,
                    !!mark && styles.settle,
                  )}
                  aria-label={`${ROWS[r]}${COLS[c]}${mark ? `, ${mark === "x" ? "yours" : "theirs"}` : ""}`}
                  data-ghost={mark || over ? undefined : GLYPH.x}
                  disabled={over && !mark}
                  onClick={() => play(ix)}
                >
                  {mark ? GLYPH[mark] : "·"}
                </button>
              );
            })}
          </div>
        ))}
      </div>
    </PageCard>
  );
}
