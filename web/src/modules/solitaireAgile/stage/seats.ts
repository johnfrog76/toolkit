import type { StandupResponse, StandupWorker } from "../api.solitaireAgile";
import { CAST } from "./cast";
import { dealMugLooks } from "./EmptyDesk";
import type { MugLook } from "./EmptyDesk";

// ── The room (docs/modules/solitaire-agile.md, "The played view") ────────────
//
// The stage is always nine windows, the Zoom grid (D-TA17). The chair keeps
// its own window; the other eight are the members' windows, in CAST order. A
// label in KEPT_WINDOWS keeps its own persona's window; the rest of the team is
// DEALT onto the free windows by position. A window with nobody in it is an
// empty desk.
//
// The web never reads the team-size setting. It draws what the response gives
// it: the workers marked `present` (all of them, from an agent that predates
// the room), in their order, capped at the room. So a Space sized three draws
// two members and six desks because only two are present, not because the
// stage knows the number.

/** The room's windows, the chair's included: the 3x3 grid. Read everywhere; never typed again. */
export const ROOM_WINDOWS = 9;
/** The windows a member can sit in: the room less the chair's. */
export const MEMBER_SEATS = ROOM_WINDOWS - 1;

/** The cast member whose window is the chair's. */
export const CHAIR_CAST_ID = "pm";
/** The chair's plate. */
export const CHAIR_PLATE = "CHAIR · PM";
/** The plate on a window with nobody in it. */
export const EMPTY_DESK_PLATE = "EMPTY DESK";

/** One member window: its cast member and the persona on its plate. */
export interface MemberWindow {
  castId: string;
  persona: string;
}

/** The eight member windows, in CAST order: the faces, dealt by position. */
export const MEMBER_WINDOWS: readonly MemberWindow[] = CAST.filter(
  (c) => c.id !== CHAIR_CAST_ID,
).map((c) => ({ castId: c.id, persona: c.label }));

/** A member's plate: `PERSONA (label)`. */
export function memberPlate(window: MemberWindow, label: string): string {
  return `${window.persona} (${label})`;
}

/** The standup's day of the year, 1-based, from the date part of `asOf` as written
 *  (its own offset) -- the day the fills count. */
export function standupDayOfYear(asOf: string): number {
  const [y, m, d] = asOf.slice(0, 10).split("-").map(Number);
  if (!y || !m || !d) return 1;
  return Math.round((Date.UTC(y, m - 1, d) - Date.UTC(y, 0, 1)) / 86_400_000) + 1;
}

export interface Seated extends MemberWindow {
  worker: StandupWorker;
}

export interface EmptyWindow extends MemberWindow {
  look: MugLook;
}

export interface Room {
  /** The present members, in speaking order, each in its window. */
  members: Seated[];
  /** Every member window nobody sits in, in window order, with its mug. */
  desks: EmptyWindow[];
}

/**
 * The labels that keep a face of their own: each sits in its own persona's
 * window whatever the day, so its persona and tagline never change with who
 * else is in the room. The sample team is a model crew; any other label is
 * dealt by position. One label to a window.
 */
export const KEPT_WINDOWS: Readonly<Record<string, string>> = {
  fable: "dev-hero",
  opus: "vibemancer",
  sonnet: "minimalist",
};

/**
 * Seat today's standup.
 *
 * - The present members (every worker, from an agent that predates `present`),
 *   in the response's order, up to the room -- the order the round speaks them,
 *   whichever window each sits in.
 * - A present member whose label is in KEPT_WINDOWS sits in its own window.
 * - A kept window whose label is in the response but out today stays EMPTY, so
 *   no other face takes it and nobody moves when that member is back; a kept
 *   window whose label this Space does not have is an ordinary window.
 * - Every other present member takes the free windows in CAST order; only when
 *   those run out does it take a kept window left empty by an absent member, so
 *   no present member is ever dropped.
 * - The windows left are empty desks, dealt their mugs by the day in window order.
 */
export function dealRoom(data: Pick<StandupResponse, "asOf" | "workers">): Room {
  const workers = data.workers ?? [];
  const present = workers.filter((w) => w.present !== false).slice(0, MEMBER_SEATS);
  const keptOf = (w: StandupWorker) => KEPT_WINDOWS[w.label.toLowerCase()];
  const reserved = new Set(workers.map(keptOf).filter((id): id is string => !!id));
  const byCast = new Map<string, StandupWorker>();
  for (const w of present) {
    const own = keptOf(w);
    if (own && !byCast.has(own)) byCast.set(own, w);
  }
  const seatedKept = new Set(byCast.values());
  const free = MEMBER_WINDOWS.filter((m) => !reserved.has(m.castId));
  const spare = MEMBER_WINDOWS.filter((m) => reserved.has(m.castId) && !byCast.has(m.castId));
  const open = [...free, ...spare];
  for (const w of present) {
    if (seatedKept.has(w)) continue;
    const at = open.shift()!;
    byCast.set(at.castId, w);
  }
  const windowOf = new Map([...byCast].map(([castId, w]) => [w, castId]));
  const members = present.map((worker) => ({
    ...MEMBER_WINDOWS.find((m) => m.castId === windowOf.get(worker))!,
    worker,
  }));
  const empty = MEMBER_WINDOWS.filter((m) => !byCast.has(m.castId));
  const looks = dealMugLooks(standupDayOfYear(data.asOf), empty.length);
  return { members, desks: empty.map((w, i) => ({ ...w, look: looks[i] })) };
}
