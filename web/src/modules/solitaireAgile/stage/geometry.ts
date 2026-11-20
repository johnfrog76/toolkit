// ── Where a speech bubble goes (docs/modules/solitaire-agile.md, "The played view") ──
//
// The stage is a fixed 3x3 grid of windows. A speech bubble may lie over another
// window's background or props, but never over a FACE (any window's, its own
// speaker's included) or a PLATE (the name at every window's bottom left), and
// never over its own window's thought button. This file is the rule, pure: the
// rectangles in, the placement out. The stage measures the rectangles and asks.

/** A rectangle in the grid's own coordinates (px from the grid's top left). */
export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** A side of the speaker's face the bubble can sit on, in the order it is tried. */
export type BubbleSide = "above" | "after" | "before" | "below";
export const BUBBLE_SIDES: readonly BubbleSide[] = ["above", "after", "before", "below"];

export interface Placement {
  side: BubbleSide;
  /** The bubble's top left, in grid coordinates. */
  left: number;
  top: number;
  /** Where the tail sits along the bubble's edge that faces the speaker, px from that edge's start. */
  tail: number;
  /** Keep-out area the bubble still overlaps, px² (0 for a clean placement). */
  overlap: number;
}

/**
 * Where each scene's head is, as the top of the head in its window (percent of the
 * window): the nine scenes are drawn differently (the minimalist sits low, the
 * ultrawide's head is near the top), so one fixed spot would land on a different
 * part of each. The bubble's tail points here.
 */
export const HEADS: Record<string, { left: string; top: string }> = {
  "dev-hero": { left: "50%", top: "38%" },
  "ops-dev": { left: "50%", top: "58%" },
  minimalist: { left: "50%", top: "66%" },
  "new-hire": { left: "23%", top: "60%" },
  vibemancer: { left: "50%", top: "53%" },
  ultrawide: { left: "50%", top: "16%" },
  qa: { left: "44%", top: "45%" },
  pm: { left: "50%", top: "45%" },
  designer: { left: "50%", top: "42%" },
};
export const HEAD_FALLBACK = { left: "50%", top: "40%" } as const;

/** The face around a head anchor (the top of the head), sized by its window: the
 *  head and the shoulders' top, with a little room, so a bubble never touches it. */
export function faceBox(anchor: { x: number; y: number }, window: Rect): Rect {
  const halfW = window.w * 0.15;
  return {
    x: anchor.x - halfW,
    y: anchor.y - window.h * 0.03,
    w: halfW * 2,
    h: window.h * 0.4,
  };
}

/** The gap kept between a bubble and the edge of the grid, and between it and the face it speaks for. */
export const BUBBLE_MARGIN = 8;
export const BUBBLE_GAP = 10;

const area = (a: Rect, b: Rect) => {
  const w = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
  const h = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
  return w > 0 && h > 0 ? w * h : 0;
};

const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));

/**
 * The bubble's place: the first side, in BUBBLE_SIDES order, where a bubble of
 * `size` fits inside the grid (with BUBBLE_MARGIN) next to the speaker's `face`
 * and overlaps none of `keepOut`; slid along that side as far as it needs to
 * clear them. Null when no side is clean -- the caller then shrinks the bubble
 * and asks again, and only at its last size takes `leastOverlap`.
 */
export function placeBubble(args: {
  grid: { w: number; h: number };
  face: Rect;
  size: { w: number; h: number };
  keepOut: readonly Rect[];
}): Placement | null {
  const all = candidates(args);
  return all.find((p) => p.overlap === 0) ?? null;
}

/** Every side's best spot, clean or not, the least-overlapping first: the last resort. */
export function leastOverlap(args: {
  grid: { w: number; h: number };
  face: Rect;
  size: { w: number; h: number };
  keepOut: readonly Rect[];
}): Placement | null {
  const all = candidates(args);
  if (all.length === 0) return null;
  return [...all].sort((a, b) => a.overlap - b.overlap)[0];
}

function candidates({
  grid,
  face,
  size,
  keepOut,
}: {
  grid: { w: number; h: number };
  face: Rect;
  size: { w: number; h: number };
  keepOut: readonly Rect[];
}): Placement[] {
  const out: Placement[] = [];
  const minX = BUBBLE_MARGIN;
  const maxX = grid.w - BUBBLE_MARGIN - size.w;
  const minY = BUBBLE_MARGIN;
  const maxY = grid.h - BUBBLE_MARGIN - size.h;
  if (maxX < minX || maxY < minY) return out;
  // The tail points at the head: its centre across, and a fifth of the way down the face beside it.
  const cx = face.x + face.w / 2;
  const cy = face.y + face.h * 0.2;
  for (const side of BUBBLE_SIDES) {
    // The main axis is fixed by the side; the cross axis slides, nearest the face's centre first.
    let fixed: number;
    let lo: number;
    let hi: number;
    let ideal: number;
    if (side === "above" || side === "below") {
      fixed = side === "above" ? face.y - BUBBLE_GAP - size.h : face.y + face.h + BUBBLE_GAP;
      if (fixed < minY || fixed > maxY) continue;
      // The tail stays over the face: the bubble's span must cover the face's centre.
      lo = Math.max(minX, cx - size.w + 16);
      hi = Math.min(maxX, cx - 16);
      ideal = clamp(cx - size.w / 2, lo, hi);
    } else {
      fixed = side === "after" ? face.x + face.w + BUBBLE_GAP : face.x - BUBBLE_GAP - size.w;
      if (fixed < minX || fixed > maxX) continue;
      lo = Math.max(minY, cy - size.h + 12);
      hi = Math.min(maxY, cy - 12);
      ideal = clamp(cy - size.h / 2, lo, hi);
    }
    if (hi < lo) continue;
    // Slide in 4px steps outward from the ideal, both ways; keep the least overlap.
    let best: Placement | null = null;
    for (let d = 0; d <= hi - lo + 4; d += 4) {
      for (const s of d === 0 ? [ideal] : [ideal - d, ideal + d]) {
        if (s < lo || s > hi) continue;
        const rect =
          side === "above" || side === "below"
            ? { x: s, y: fixed, w: size.w, h: size.h }
            : { x: fixed, y: s, w: size.w, h: size.h };
        const overlap = keepOut.reduce((sum, k) => sum + area(rect, k), 0);
        if (!best || overlap < best.overlap) {
          const tail =
            side === "above" || side === "below"
              ? clamp(cx - rect.x, 16, size.w - 16)
              : clamp(cy - rect.y, 12, size.h - 12);
          best = { side, left: rect.x, top: rect.y, tail, overlap };
        }
        if (best.overlap === 0) break;
      }
      if (best?.overlap === 0) break;
    }
    if (best) out.push(best);
  }
  return out;
}
