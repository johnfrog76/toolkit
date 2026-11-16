import { CAST } from "./cast";
import { BUBBLE_MARGIN, BUBBLE_SIDES, HEADS, faceBox, leastOverlap, placeBubble } from "./geometry";
import type { Rect } from "./geometry";
import { CHAIR_CAST_ID, ROOM_WINDOWS } from "./seats";

// The bubble's place on the stage (docs/modules/solitaire-agile.md, "The played
// view"), over the room as the stage draws it at its usual size: a 3x3 grid of
// windows, each face where HEADS puts it, each plate at its window's bottom left.

const GRID = { w: 828, h: 707 };
const GAP = 10;
const COLS = 3;
const CELL = { w: (GRID.w - GAP * (COLS - 1)) / COLS, h: (GRID.h - GAP * (COLS - 1)) / COLS };
const pct = (v: string) => Number(v.replace("%", "")) / 100;

/** Each window of the room, its face and its plate, as the stage lays them out. */
function room() {
  return CAST.map((c, i) => {
    const win: Rect = {
      x: (i % COLS) * (CELL.w + GAP),
      y: Math.floor(i / COLS) * (CELL.h + GAP),
      w: CELL.w,
      h: CELL.h,
    };
    const head = HEADS[c.id];
    const face = faceBox(
      { x: win.x + win.w * pct(head.left), y: win.y + win.h * pct(head.top) },
      win,
    );
    // The plate: 10px in from the bottom left, its text a persona and a label.
    const words = c.id === CHAIR_CAST_ID ? "CHAIR · PM" : `${c.label} (label)`;
    const plate: Rect = {
      x: win.x + 10,
      y: win.y + win.h - 10 - 26,
      w: 36 + words.length * 7.4,
      h: 26,
    };
    // The thought button, at the window's left above the plate.
    const button: Rect = { x: win.x + 6, y: win.y + win.h - 30 - 26, w: 26, h: 26 };
    return { id: c.id, win, face, plate, button };
  });
}

/** A short turn (a name called) and a long one (a turn clamped at four lines), at the
 *  bubble's size: up to 260px wide, four lines of 0.6rem text and the padding. */
const SHORT = [{ w: 90, h: 38 }];
const LONG = [{ w: 260, h: 74 }];

/** Where each bubble lands at the stage's usual size: the side it takes. */
const SEEN = [
  "dev-hero short: above",
  "dev-hero long: after",
  "ops-dev short: above",
  "ops-dev long: above",
  "minimalist short: above",
  "minimalist long: above",
  "new-hire short: above",
  "new-hire long: above",
  "vibemancer short: above",
  "vibemancer long: above",
  "ultrawide short: before",
  "ultrawide long: before",
  "qa short: above",
  "qa long: above",
  "pm short: above",
  "pm long: above",
  "designer short: above",
  "designer long: above",
];
const overlaps = (a: Rect, b: Rect) =>
  Math.min(a.x + a.w, b.x + b.w) > Math.max(a.x, b.x) &&
  Math.min(a.y + a.h, b.y + b.h) > Math.max(a.y, b.y);

/** Place a speaker's bubble the way the stage does: each size in turn, the last taken whatever it overlaps. */
function placeFor(i: number, sizes: { w: number; h: number }[]) {
  const all = room();
  const me = all[i];
  const keepOut = [...all.map((r) => r.face), ...all.map((r) => r.plate), me.button];
  for (let s = 0; s < sizes.length; s++) {
    const args = { grid: GRID, face: me.face, size: sizes[s], keepOut };
    const found = placeBubble(args) ?? (s === sizes.length - 1 ? leastOverlap(args) : null);
    if (found) return { ...found, size: sizes[s], step: s, keepOut };
  }
  throw new Error("no place at all");
}

describe("the bubble's place on the stage", () => {
  it("models the room the stage draws: nine windows", () => {
    expect(room()).toHaveLength(ROOM_WINDOWS);
  });

  // The table: every window, a short and a long turn. Each row is where the bubble
  // goes and at which size; every one is clean -- no face, no plate, no button --
  // and inside the grid with its margin.
  const table = room().flatMap((r, i) =>
    (
      [
        ["short", SHORT],
        ["long", LONG],
      ] as const
    ).map(([turn, sizes]) => [r.id, turn, placeFor(i, [...sizes])] as const),
  );

  it.each(table)("%s, a %s turn: a clean place inside the grid", (_id, _turn, p) => {
    expect(p.overlap).toBe(0);
    const rect = { x: p.left, y: p.top, w: p.size.w, h: p.size.h };
    for (const k of p.keepOut) expect(overlaps(rect, k)).toBe(false);
    expect(rect.x).toBeGreaterThanOrEqual(BUBBLE_MARGIN);
    expect(rect.y).toBeGreaterThanOrEqual(BUBBLE_MARGIN);
    expect(rect.x + rect.w).toBeLessThanOrEqual(GRID.w - BUBBLE_MARGIN);
    expect(rect.y + rect.h).toBeLessThanOrEqual(GRID.h - BUBBLE_MARGIN);
  });

  it("prefers above the speaker: a short turn sits above in every window but the one with a neighbour's face right above it", () => {
    const sides = room().map((r, i) => [r.id, placeFor(i, SHORT).side]);
    expect(sides.filter(([, side]) => side !== "above")).toEqual([["ultrawide", "before"]]);
    // ...and that one is blocked above by the face in the window over it.
    const all = room();
    const me = all.find((r) => r.id === "ultrawide")!;
    const over = all.find((r) => r.id === "minimalist")!;
    expect(over.face.y + over.face.h).toBeGreaterThan(me.face.y - 10 - SHORT[0].h);
  });

  it("records where each bubble lands, so a change to the room is seen", () => {
    expect(table.map(([id, turn, p]) => `${id} ${turn}: ${p.side}`)).toEqual(SEEN);
  });

  it("tries the sides in order -- above, after, before, below -- and slides along a side to clear a keep-out", () => {
    expect(BUBBLE_SIDES).toEqual(["above", "after", "before", "below"]);
    const face = { x: 200, y: 200, w: 60, h: 60 };
    const grid = { w: 600, h: 600 };
    const size = { w: 100, h: 40 };
    expect(placeBubble({ grid, face, size, keepOut: [] })!.side).toBe("above");
    // A keep-out right above the face's centre: the bubble slides along the top, still above.
    const slid = placeBubble({ grid, face, size, keepOut: [{ x: 150, y: 140, w: 20, h: 40 }] })!;
    expect(slid.side).toBe("above");
    expect(slid.overlap).toBe(0);
    // Everything above blocked: the next side.
    const after = placeBubble({ grid, face, size, keepOut: [{ x: 0, y: 0, w: 600, h: 195 }] })!;
    expect(after.side).toBe("after");
  });

  it("finds nothing when every side is blocked; the least overlap is the last resort", () => {
    const face = { x: 200, y: 200, w: 60, h: 60 };
    const grid = { w: 600, h: 600 };
    const size = { w: 100, h: 40 };
    const keepOut = [{ x: 0, y: 0, w: 600, h: 600 }];
    expect(placeBubble({ grid, face, size, keepOut })).toBeNull();
    expect(leastOverlap({ grid, face, size, keepOut })!.overlap).toBeGreaterThan(0);
  });

  it("the tail stays on the face's side of the bubble, at the face", () => {
    const face = { x: 200, y: 200, w: 60, h: 60 };
    const p = placeBubble({
      grid: { w: 600, h: 600 },
      face,
      size: { w: 100, h: 40 },
      keepOut: [],
    })!;
    expect(p.left + p.tail).toBe(face.x + face.w / 2);
  });
});
