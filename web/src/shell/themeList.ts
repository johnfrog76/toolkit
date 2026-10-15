// The themes, as data. A theme here is like a Face: not a setting to get right
// but a mood to pick -- "sometimes I want something different". So there is a
// flat list of NAMED themes, each one either dark or light, and no "Auto": you
// choose by where you are sitting (the basement, the office), not by what the
// operating system says.
//
// Two KINDS, because both are wanted:
//   glass -- translucent cards over a gradient and paper grain. The look the
//            Toolkit has had from the start.
//   flat  -- opaque cards on a plain page. Functional, classic, and the right
//            answer on a projector or a bad monitor.
//
// No import from Fluent here, on purpose. useCurrentTheme reads this file, and
// that hook is pulled into vite-node by the deck voice-bake, outside a browser.
// shell/theme.ts turns one of these records into a Fluent theme.
//
// ADDING A THEME is adding a record. Check three things by eye: white text on
// `brand.background` (the primary button), `brand.foreground1` on the card
// (links), and the logo's word over `logo` (the face blob). And one by number:
// `brand.foreground2` is a tint badge's text, on the ramp's palest step in a
// light theme and its darkest in a dark one -- 4.5:1 at the badge's 10px, which
// themeList.test.ts holds for every record. Fluent's own order is the
// safe one: foreground2 a step DARKER than foreground1 in a light theme, a
// step LIGHTER in a dark one.

export type ThemeMode = "dark" | "light";

export interface ToolkitTheme {
  id: string;
  name: string;
  mode: ThemeMode;
  kind: "glass" | "flat";
  /** One line for the picker: what it is like, not what it is made of. */
  blurb: string;
  /** The document's background. `image` is "none" for a flat theme. */
  page: { color: string; image: string };
  /** Opacity of the paper grain over the page. 0 is none. */
  grain: number;
  /** The blob behind the logo's face. */
  logo: string;
  /** What a card is made of. Absent: Fluent's own translucent alpha. */
  card?: string;
  brand: {
    background: string;
    hover: string;
    pressed: string;
    foreground1: string;
    foreground2: string;
  };
}

export const THEMES: ToolkitTheme[] = [
  {
    id: "atlantis",
    name: "Atlantis",
    mode: "dark",
    kind: "glass",
    blurb: "Deep water. Blue into teal.",
    page: {
      color: "#0e171f",
      image: "linear-gradient(33deg, #0f766e52 0%, #0f548c8a 55%, #1e3a8a70 100%)",
    },
    grain: 0.45,
    logo: "rgba(34, 211, 238, 0.38)",
    brand: {
      background: "#0e7490",
      hover: "#0891b2",
      pressed: "#155e75",
      foreground1: "#67e8f9",
      foreground2: "#22d3ee",
    },
  },
  {
    id: "aurora",
    name: "Aurora",
    mode: "dark",
    kind: "glass",
    blurb: "Violet sky with a green edge. The showy one.",
    page: {
      color: "#1f1f1f",
      image: "linear-gradient(33deg, #5a25c147 0%, #0f548c8a 62%, #10b9812e 100%)",
    },
    grain: 0.45,
    logo: "rgba(129, 140, 248, 0.45)",
    brand: {
      background: "#4F46E5",
      hover: "#6366F1",
      pressed: "#4338CA",
      foreground1: "#818CF8",
      foreground2: "#A5B4FC",
    },
  },
  {
    id: "basement",
    name: "Basement",
    mode: "dark",
    kind: "flat",
    blurb: "Plain charcoal and one warm lamp. Easy at night.",
    page: { color: "#19191b", image: "none" },
    grain: 0,
    logo: "rgba(245, 158, 11, 0.50)",
    card: "#232326",
    brand: {
      background: "#b45309",
      hover: "#c2600c",
      pressed: "#92400e",
      foreground1: "#fbbf24",
      foreground2: "#f59e0b",
    },
  },
  {
    id: "seaglass",
    name: "Seaglass",
    mode: "light",
    kind: "glass",
    blurb: "Teal washing into lilac.",
    page: {
      color: "#ffffff",
      image: "linear-gradient(210deg, #34c5b845 0%, #5a25c175 100%)",
    },
    grain: 1,
    logo: "#c4768a",
    brand: {
      background: "#0F766E",
      hover: "#0D9488",
      pressed: "#115E59",
      foreground1: "#0F766E",
      foreground2: "#115E59",
    },
  },
  {
    id: "sunny",
    name: "Sunny",
    mode: "light",
    kind: "glass",
    blurb: "Warm cream, late-afternoon light.",
    page: {
      color: "#fffaf0",
      image: "linear-gradient(200deg, #fde68a70 0%, #fdba7452 50%, #fda4af5c 100%)",
    },
    grain: 1,
    logo: "#f4a533",
    brand: {
      background: "#be123c",
      hover: "#e11d48",
      pressed: "#9f1239",
      foreground1: "#be123c",
      foreground2: "#9f1239",
    },
  },
  {
    id: "office",
    name: "Office",
    mode: "light",
    kind: "flat",
    blurb: "Paper and one teal accent. Fine on a shared screen.",
    page: { color: "#f3f2f1", image: "none" },
    grain: 0,
    logo: "#7dd3c8",
    card: "#ffffff",
    brand: {
      background: "#0F766E",
      hover: "#0D9488",
      pressed: "#115E59",
      foreground1: "#0F766E",
      foreground2: "#115E59",
    },
  },
];

/**
 * The SKIN themes -- what a granted skin dresses the whole product in
 * (docs/modules/lounge.md, "The Skins dialog, and the grant"). Not in THEMES on purpose:
 * they are not pickable, they are WORN -- the Lounge grants one and the
 * shell wears it, theme included, until the room takes it back. Each is the
 * house theme shape derived from its scene's own palette, dark by nature (a
 * lamp over dark water, a temple at dusk), with a night-glass `card` so the
 * scene glows through at full strength and the SURFACES carry legibility --
 * no scrim dials the background back.
 */
export const SKIN_THEMES: Record<"temple" | "tank", ToolkitTheme> = {
  temple: {
    id: "skin-temple",
    name: "Zen Temple",
    mode: "dark",
    kind: "glass",
    blurb: "Worn by the Lounge. Lacquer, gilt and incense jade.",
    page: { color: "#251c10", image: "none" },
    grain: 0.35,
    logo: "rgba(233, 200, 122, 0.4)",
    // Dark lacquered wood -- the altar's own material, same rule as the
    // tank's cabinet below.
    card: "rgba(38, 25, 13, 0.72)",
    brand: {
      background: "#a53030",
      hover: "#b84a3c",
      pressed: "#7c2424",
      foreground1: "#e9c87a",
      foreground2: "#e8d9b0",
    },
  },
  tank: {
    id: "skin-tank",
    name: "Fish Tank",
    mode: "dark",
    kind: "glass",
    blurb: "Worn by the Lounge. A night room lit by its own lamp.",
    page: { color: "#0d0b16", image: "none" },
    grain: 0.35,
    logo: "rgba(127, 212, 192, 0.4)",
    // Nordic WOOD, not night glass (the owner: "containers pick up nordic wood
    // panels") -- the tank stands on a cabinet, and the cards are its
    // furniture. This token carries the TONE; the panel treatment itself
    // (grain, bevel) needs a backgroundImage the card token cannot hold, and
    // is the first item of the hand-tuning pass with the owner.
    card: "rgba(46, 33, 21, 0.72)",
    brand: {
      background: "#147d70",
      hover: "#189183",
      pressed: "#0f5f56",
      foreground1: "#7fd4c0",
      foreground2: "#8fe8cc",
    },
  },
};

/** What a browser that has never chosen shows: by the system, once. */
export const FIRST_DARK = "atlantis";
export const FIRST_LIGHT = "seaglass";

// What the key held before themes had names.
const LEGACY: Record<string, string> = { dark: "aurora", light: "seaglass" };

export function themeById(id: string | null | undefined): ToolkitTheme | undefined {
  if (!id) return undefined;
  return THEMES.find((t) => t.id === (LEGACY[id] ?? id));
}
