import { useId } from "react";
import type { ReactNode } from "react";

// ── The refined style, for the stage's own drawings ──────────────────────────
//
// The cast's busts are the shared refined faces (shared/refinedFaces.tsx). The
// stage draws more than busts -- a raised hand, a treadmill, eight drinks, an
// empty chair -- and these are that style's rules for everything else: soft
// shapes, no outlines, one shade on the right side, light from the top left and
// one soft drop shadow. A drawing here is flat colour plus the parts below.

const rgb = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));

/** `a` moved a fraction `t` of the way to `b`; both `#rrggbb`. */
export function mix(a: string, b: string, t: number): string {
  const to = rgb(b);
  return `#${rgb(a)
    .map((v, i) =>
      Math.round(v + (to[i] - v) * t)
        .toString(16)
        .padStart(2, "0"),
    )
    .join("")}`;
}

/** A colour's shade: a step toward the room's night. */
export const dark = (c: string, t = 0.15) => mix(c, "#0b1020", t);
/** A colour's lit side: a step toward white. */
export const lite = (c: string, t = 0.15) => mix(c, "#ffffff", t);

/** The style's one drop shadow, as CSS: light from the top left. */
export const SOFT_SHADOW = "4px 6px 9px rgba(4, 8, 20, 0.34)";
/** The same shadow on a drawing, which follows the drawing's own outline. */
export const DRAWING_SHADOW = "drop-shadow(2.6px 2.2px 2px rgba(4, 8, 20, 0.3))";

/** The wall behind a window: its tint, lit at the top left and shaded at the bottom right. */
export function wall(tint: string): string {
  return `linear-gradient(135deg, rgba(255,255,255,0.16) 0%, rgba(255,255,255,0) 55%, rgba(0,0,0,0.16) 100%), ${tint}`;
}

/** A side shade on a flat block: the block's colour, a step darker from four-fifths across. */
export function sideShade(color: string, t = 0.24): string {
  return `linear-gradient(90deg, ${color} 0%, ${color} 78%, ${dark(color, t)} 100%)`;
}

/** A unique, CSS-safe prefix for one drawing's ids, so two windows never share a clip. */
export function useDrawingId(prefix: string): string {
  return `${prefix}${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;
}

/**
 * The style's shading for any soft shape: the shape in its shade colour, then
 * the same shape, lit, slid up and left inside it. What is left showing is one
 * crescent of shade on the right.
 */
export function Soft({
  id,
  fill,
  shade,
  dx = -2.2,
  dy = -1,
  children,
}: {
  /** The clip's id: unique in the document. */
  id: string;
  fill: string;
  shade: string;
  dx?: number;
  dy?: number;
  /** The shape, with no fill of its own. */
  children: ReactNode;
}) {
  return (
    <>
      <clipPath id={id}>{children}</clipPath>
      <g fill={shade}>{children}</g>
      <g clipPath={`url(#${id})`}>
        <g fill={fill} transform={`translate(${dx} ${dy})`}>
          {children}
        </g>
      </g>
    </>
  );
}
