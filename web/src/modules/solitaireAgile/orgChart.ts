import type { FaceId } from "../../shared/refinedFaces";
import type { OrgPosition, OrgSeat } from "./api.solitaireAgile";
import { MUG_LOOKS } from "./stage/EmptyDesk";
import type { MugLook } from "./stage/EmptyDesk";

// The Org page's rules, apart from its drawing: which face sits in which seat,
// the colour of each level's walls, what a plate says, and where every office
// goes on the page. Pure, so the page test and the faces test read them as the
// page does.

// -- Which face goes where ------------------------------------------------
//
// The org file names positions and seats, never a face: a skin is a skin. The
// faces are the web's choice, and this is it -- each position as the cast-skin
// mock's org chart staffs it. A position with several seats takes its faces in
// turn, seat by seat; the mock's leads are dev-hero and ops-dev, and its
// re-staffing inset puts qa in a lead's office, so a third lead seat is qa.

/** The faces of the positions the mock draws, by the position's id. */
export const POSITION_FACES: Readonly<Record<string, readonly FaceId[]>> = {
  owner: ["owner"],
  "vp-product": ["designer"],
  "vp-engineering": ["ultrawide"],
  pm: ["pm"],
  "team-lead": ["dev-hero", "ops-dev", "qa"],
  builder: ["minimalist", "new-hire", "vibemancer", "qa"],
};

/** A position the map does not name takes the faces of its level in the mock,
 *  the deepest level's for anything below it. */
export const LEVEL_FACES: readonly (readonly FaceId[])[] = [
  ["owner"],
  ["designer", "ultrawide"],
  ["pm"],
  ["dev-hero", "ops-dev", "qa"],
  ["minimalist", "new-hire", "vibemancer", "qa"],
];

/** The faces a position's seats take in turn. `order` is the position's place
 *  among its level's positions, so two unnamed positions on one level differ. */
export function positionFaces(position: OrgPosition, order = 0): readonly FaceId[] {
  const named = POSITION_FACES[position.id];
  if (named) return named;
  const level = LEVEL_FACES[Math.min(Math.max(position.level, 0), LEVEL_FACES.length - 1)];
  return [...level.slice(order % level.length), ...level.slice(0, order % level.length)];
}

/** The face in one seat: the position's faces, in turn. */
export function seatFace(position: OrgPosition, seatIndex: number, order = 0): FaceId {
  const faces = positionFaces(position, order);
  return faces[seatIndex % faces.length];
}

// -- The walls ------------------------------------------------------------
//
// Office walls are coloured by level (the owner's call on the cast-skin mock):
// the mock's five, from the owner's down to the builders'. A deeper level takes
// the builders'. Each wall's shaded edge is the wall mixed 30% toward the
// mock's ink (#0b1020), as its generator mixes it.

export const LEVEL_WALLS: readonly { wall: string; shade: string }[] = [
  { wall: "#ecd3a2", shade: "#a9997b" },
  { wall: "#a9d3ee", shade: "#7a99b0" },
  { wall: "#f0aa98", shade: "#ab7c74" },
  { wall: "#a8dbbb", shade: "#799e8d" },
  { wall: "#c6c9e8", shade: "#8e92ac" },
];

export function levelWall(level: number): { wall: string; shade: string } {
  return LEVEL_WALLS[Math.min(Math.max(level, 0), LEVEL_WALLS.length - 1)];
}

// -- What a plate says ----------------------------------------------------

/** The word after the position on a vacant seat's plate. */
export const VACANT_WORD = "vacant";
/** The word after the position on a pool's plate. */
export const POOL_WORD = "pool";

/** The plate's second word: the model, the person (the owner), or vacant. */
export function plateWho(seat: OrgSeat): string {
  if (seat.state === "vacant") return VACANT_WORD;
  return seat.person ?? seat.model ?? VACANT_WORD;
}

/** Where a seat sits, where the file says: "toolkit on mini", "on laptop", or "". */
export function seatWhere(seat: OrgSeat): string {
  const on = seat.machine ? `on ${seat.machine}` : "";
  return [seat.space ?? "", on].filter(Boolean).join(" ");
}

/**
 * The mug on a vacant seat's empty desk, from the seat's id: the same seat
 * always has the same mug, and no clock is read. The standup deals its mugs by
 * the day; a chart is not a day's, so it deals by the seat.
 */
export function vacantMug(seatId: string): MugLook {
  let sum = 0;
  for (const ch of seatId) sum = (sum + (ch.codePointAt(0) ?? 0)) % MUG_LOOKS.length;
  return MUG_LOOKS[sum];
}

// -- Where each office goes -----------------------------------------------
//
// Offices by level, top to bottom, each position centred over the positions
// that report to it -- a tidy tree. A position is one office: one seat is one
// card, several are a row of cards inside it, and none (a pool) is one wider
// card. Every size is in CSS pixels, and the page draws with these numbers.

export const SIZE = {
  /** The padding around an office's cards. */
  pad: 10,
  /** The sign above the door: the prompt's title. */
  sign: 22,
  door: { width: 124, height: 104 },
  /** A pool's door holds a few small busts side by side. */
  poolDoor: { width: 212, height: 104 },
  /** The plate rises this far over the door's sill. */
  plateLift: 5,
  plate: 40,
  /** One seat's column, wide enough for its plate. */
  cell: 196,
  /** A pool's column, wide enough for its default-model line. */
  poolCell: 260,
  seatGap: 12,
  siblingGap: 32,
  /** Between one level's offices and the next's: where the lines run. */
  rowGap: 44,
  /** Under a pool's plate: its default-model line. */
  poolCaption: 52,
} as const;

/** An office's height, sign to the bottom of its plate, padding included. */
export const OFFICE_HEIGHT =
  SIZE.pad + SIZE.sign + SIZE.door.height - SIZE.plateLift + SIZE.plate + SIZE.pad;

export const isPool = (position: OrgPosition): boolean => position.seats.length === 0;

export function officeWidth(position: OrgPosition): number {
  const n = position.seats.length;
  const inner = n === 0 ? SIZE.poolCell : n * SIZE.cell + (n - 1) * SIZE.seatGap;
  return inner + 2 * SIZE.pad;
}

export interface PlacedOffice {
  position: OrgPosition;
  /** The office's place among its level's offices, left to right. */
  order: number;
  left: number;
  top: number;
  width: number;
  /** The office's centre line, where its lines meet it. */
  cx: number;
}

export interface ChartLayout {
  offices: PlacedOffice[];
  /** A line from each office down to each office that reports to it. */
  lines: { from: PlacedOffice; to: PlacedOffice }[];
  width: number;
  height: number;
}

/** Where every office of the tree goes. The positions come in tree order with
 *  their level (docs/hub/org.md, "The response"): one root, each with its reports. */
export function layoutChart(positions: OrgPosition[]): ChartLayout {
  const reports = new Map<string, OrgPosition[]>();
  for (const p of positions) {
    const up = p.reportsTo ?? "";
    reports.set(up, [...(reports.get(up) ?? []), p]);
  }
  const known = new Set(positions.map((p) => p.id));
  const roots = positions.filter((p) => !p.reportsTo || !known.has(p.reportsTo));

  const depth = Math.max(0, ...positions.map((p) => p.level));
  const rowHeight = Array.from({ length: depth + 1 }, (_, level) =>
    positions.some((p) => p.level === level && isPool(p))
      ? OFFICE_HEIGHT + SIZE.poolCaption
      : OFFICE_HEIGHT,
  );
  const rowTop = rowHeight.map((_, level) =>
    rowHeight.slice(0, level).reduce((sum, h) => sum + h + SIZE.rowGap, 0),
  );

  const spans = new Map<string, number>();
  const span = (p: OrgPosition): number => {
    const cached = spans.get(p.id);
    if (cached !== undefined) return cached;
    const kids = reports.get(p.id) ?? [];
    const kidsWidth =
      kids.reduce((sum, k) => sum + span(k), 0) + Math.max(0, kids.length - 1) * SIZE.siblingGap;
    const width = Math.max(officeWidth(p), kidsWidth);
    spans.set(p.id, width);
    return width;
  };

  const offices: PlacedOffice[] = [];
  const lines: ChartLayout["lines"] = [];
  const perLevel = new Map<number, number>();
  const place = (p: OrgPosition, left: number): PlacedOffice => {
    const width = span(p);
    const kids = reports.get(p.id) ?? [];
    const kidsWidth =
      kids.reduce((sum, k) => sum + span(k), 0) + Math.max(0, kids.length - 1) * SIZE.siblingGap;
    const own = officeWidth(p);
    const office: PlacedOffice = {
      position: p,
      order: 0,
      left: 0,
      top: rowTop[p.level] ?? 0,
      width: own,
      cx: left + width / 2,
    };
    offices.push(office);
    let x = left + (width - kidsWidth) / 2;
    const placedKids = kids.map((k) => {
      const kid = place(k, x);
      x += span(k) + SIZE.siblingGap;
      return kid;
    });
    if (placedKids.length > 0) {
      office.cx = (placedKids[0].cx + placedKids[placedKids.length - 1].cx) / 2;
    }
    office.left = Math.min(Math.max(office.cx - own / 2, left), left + width - own);
    office.cx = office.left + own / 2;
    for (const kid of placedKids) lines.push({ from: office, to: kid });
    return office;
  };
  let x = 0;
  for (const root of roots) {
    place(root, x);
    x += span(root) + SIZE.siblingGap;
  }
  for (const office of [...offices].sort((a, b) => a.left - b.left)) {
    const level = office.position.level;
    office.order = perLevel.get(level) ?? 0;
    perLevel.set(level, office.order + 1);
  }
  const width = Math.max(0, x - SIZE.siblingGap);
  const height = rowTop[depth] + rowHeight[depth];
  return { offices, lines, width, height };
}
