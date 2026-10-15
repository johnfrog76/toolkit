import { useLayoutEffect, useRef, useState } from "react";
import { useCompactLayout } from "./useCompactLayout";
import { useDeck } from "./deckContext";
import { giveawayUrlFor } from "./deckLinks";

// The giveaway button — the one shared affordance every closing slide and the
// site's own footer carry, and the one place its look and behaviour are
// decided. No props about what it is; one prop about where it sits.
//
// Why no props: 106 deck
// files used to configure the old button by hand — six titles, two contrasts,
// three placements, and 55 local copies of the URL — so "the button has one
// purpose, globally" was held by a hundred call sites agreeing. Now:
//
//   - It is a LINK that opens the repo in a new tab, the way the footer's
//     mark already worked; copy-to-clipboard existed so the owner could paste the
//     URL into chat mid-presentation, and that need has passed.
//   - The target comes from the deck's `project` (deckContext + deckLinks):
//     a wasteland or connected-deck deck hands out connected-deck, a Toolkit
//     deck hands out the Toolkit. With no deck around it (the poster wall, the
//     details page, the footer) it is connected-deck.
//   - Contrast is read off the stage behind it, not declared per deck: the
//     first ancestor with an opaque background or a gradient decides dark or
//     light, and the house default with nothing to read is dark.
//   - The corner is the stage's bottom-right. `inline` is the one escape:
//     the composition positions it itself (Cybil owns the right corner in
//     the raven decks; the Universe mounts it inside a diegetic element).
//
// Compact viewports get the 84px tap floor for the same reason the old button
// did: a phone transform-scales the stage to ~0.55, which would shrink 36px
// to ~20px, under the 44px floor.

// GitHub mark as a pure inline SVG path (Octicons "mark-github", MIT-licensed)
// — no image asset, no external request, themeable via currentColor.
export function GitHubMark({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="currentColor" aria-hidden>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z" />
    </svg>
  );
}

// The disc the mark sits on, in both looks: a dark mark for light or warm
// grounds, a white mark on a light translucent disc for dark ones. Named once
// so nothing else can draw the disc differently.
export const GITHUB_MARK_DISC = {
  default: {
    background: "rgba(0,0,0,0.28)",
    backgroundHover: "rgba(0,0,0,0.42)",
    color: "rgba(0,0,0,0.82)",
  },
  inverse: {
    background: "rgba(255,255,255,0.14)",
    backgroundHover: "rgba(255,255,255,0.26)",
    color: "rgba(255,255,255,0.92)",
  },
} as const;

function parseColor(value: string): { r: number; g: number; b: number; a: number } | null {
  const rgb = /rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s/]+([\d.]+%?))?\s*\)/i.exec(
    value,
  );
  if (rgb) {
    const a =
      rgb[4] === undefined
        ? 1
        : rgb[4].endsWith("%")
          ? parseFloat(rgb[4]) / 100
          : parseFloat(rgb[4]);
    return { r: +rgb[1], g: +rgb[2], b: +rgb[3], a };
  }
  const hex = /^#([0-9a-f]{3,8})$/i.exec(value.trim());
  if (hex) {
    let h = hex[1];
    if (h.length === 3 || h.length === 4) h = [...h].map((c) => c + c).join("");
    const n = parseInt(h.slice(0, 6), 16);
    const a = h.length === 8 ? parseInt(h.slice(6, 8), 16) / 255 : 1;
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255, a };
  }
  return null;
}

function luminance(c: { r: number; g: number; b: number }): number {
  return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) / 255;
}

/**
 * Is the ground behind `el` dark? Walks up to the first ancestor that paints
 * something: an opaque background colour decides alone; a gradient decides by
 * the average of its colour stops. Nothing painted anywhere reads as dark,
 * which is the house register's stage.
 */
export function isDarkBehind(el: Element | null): boolean {
  for (let node = el?.parentElement ?? null; node; node = node.parentElement) {
    const cs = getComputedStyle(node);
    const bg = parseColor(cs.backgroundColor || "");
    if (bg && bg.a >= 0.5) return luminance(bg) < 0.5;
    const img = cs.backgroundImage;
    if (img && img !== "none") {
      const stops = [...img.matchAll(/rgba?\([^)]*\)|#[0-9a-f]{3,8}/gi)]
        .map((m) => parseColor(m[0]))
        .filter((c): c is NonNullable<typeof c> => c !== null && c.a >= 0.5);
      if (stops.length > 0) {
        const avg = stops.reduce((sum, c) => sum + luminance(c), 0) / stops.length;
        return avg < 0.5;
      }
    }
  }
  return true;
}

export const GIVEAWAY_TITLE = "Open the repo on GitHub";

export function GiveawayButton({ inline = false }: { inline?: boolean }) {
  const deck = useDeck();
  const url = giveawayUrlFor(deck?.project);
  const compact = useCompactLayout();
  const px = compact ? 84 : 36;
  const mark = compact ? 42 : 18;

  const ref = useRef<HTMLAnchorElement>(null);
  // Dark until measured: the flash a light stage would see is one frame, and
  // the alternative — a dark mark flashing on the far more common dark stage
  // — is the one a viewer would notice.
  const [dark, setDark] = useState(true);
  useLayoutEffect(() => {
    setDark(isDarkBehind(ref.current));
  }, []);
  const disc = dark ? GITHUB_MARK_DISC.inverse : GITHUB_MARK_DISC.default;

  return (
    <a
      ref={ref}
      href={url}
      target="_blank"
      rel="noopener noreferrer"
      title={GIVEAWAY_TITLE}
      aria-label={GIVEAWAY_TITLE}
      data-giveaway={deck?.project ?? "none"}
      style={{
        ...(inline ? {} : { position: "absolute", bottom: "28px", right: "36px" }),
        width: `${px}px`,
        height: `${px}px`,
        borderRadius: "50%",
        background: disc.background,
        color: disc.color,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        textDecoration: "none",
        transition: "background 0.15s ease, transform 0.15s ease",
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.background = disc.backgroundHover;
        e.currentTarget.style.transform = "scale(1.06)";
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.background = disc.background;
        e.currentTarget.style.transform = "scale(1)";
      }}
    >
      <GitHubMark size={mark} />
    </a>
  );
}
