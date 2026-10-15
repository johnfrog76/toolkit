/**
 * The skins (docs/modules/lounge.md, "The Skins dialog, and the grant").
 *
 * The FISH TANK's scenes are the aquarium-saver scapes, ported as
 * self-contained zero-JavaScript documents under public/lounge/aquarium/
 * (web/tools/port-aquarium.mjs) -- assets, not bundle, fetched only when one
 * mounts. Seven scapes, four fresh and three salt, each standing in its own
 * European living room at night. The saver "runs on its own slow clocks and
 * never asks you for anything" -- its words, and the room's law before the
 * room existed. The TEMPLE is its standalone twin, public/lounge/temple.html.
 *
 * Since M3 (D-L18) a skin is chosen in the Skins DIALOG, opened from the
 * Lounge, and worn product-wide at once; the room itself has no scene slot
 * and no skin of its own. The grant (shared/skinGrant.ts) is what the dialog
 * writes and the shell wears, without the shell ever importing this module.
 */

export interface TankScene {
  id: string;
  /** The caption, in the skin's voice: names what you are looking at. */
  caption: string;
  src: string;
}

/** Which SKIN_THEMES record a scene dresses the product in while worn. */
export type LoungeSkinId = "temple" | "tank";

export const TEMPLE_SCENE: TankScene = {
  id: "temple",
  caption: "offerings on the altar · the river in the mist",
  src: "/lounge/temple.html",
};

export const TANK_SCENES: TankScene[] = [
  {
    id: "nature",
    caption: "nature style · fresh water · nordic room",
    src: "/lounge/aquarium/nature.html",
  },
  {
    id: "iwagumi",
    caption: "iwagumi · fresh water · nordic room",
    src: "/lounge/aquarium/iwagumi.html",
  },
  {
    id: "dutch",
    caption: "dutch street · fresh water · vienna room",
    src: "/lounge/aquarium/dutch.html",
  },
  {
    id: "jungle",
    caption: "moss jungle · fresh water · paris room",
    src: "/lounge/aquarium/jungle.html",
  },
  {
    id: "reef",
    caption: "reef range · salt water · vienna room",
    src: "/lounge/aquarium/reef.html",
  },
  {
    id: "lagoon",
    caption: "lagoon · salt water · nordic room",
    src: "/lounge/aquarium/lagoon.html",
  },
  {
    id: "garden",
    caption: "coral garden · salt water · paris room",
    src: "/lounge/aquarium/garden.html",
  },
];

/** The collection the dialog shows, in its order: the temple, then the
 *  scapes. A grid, because there may one day be twenty. */
export const ALL_SKINS: Array<{ skinId: LoungeSkinId; scene: TankScene }> = [
  { skinId: "temple", scene: TEMPLE_SCENE },
  ...TANK_SCENES.map((scene) => ({ skinId: "tank" as LoungeSkinId, scene })),
];

/** The Animate switch's memory when no skin is worn -- per browser, so the
 *  next skin picked wears the person's last answer. A worn grant carries its
 *  own `animate`; this is only the switch's resting position. */
export const SKIN_ANIMATE_KEY = "toolkit-skin-animate";
