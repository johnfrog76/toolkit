import type { StandupResponse, StandupWorker } from "../api.solitaireAgile";
import { CAST } from "./cast";
import { dealMugLooks } from "./EmptyDesk";
import type { MugLook } from "./EmptyDesk";

// ── The room (docs/modules/solitaire-agile.md, "The played view") ────────────
//
// The stage is always nine windows, the Zoom grid (D-TA17). The chair keeps
// its own window; the other eight are the members' windows, in CAST order, and
// the team is DEALT onto them by position: member i, in the response's order,
// sits in member window i. A window with nobody in it is an empty desk.
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
 * Seat today's standup. The present members (every worker, from an agent that
 * predates `present`) take the member windows in the response's order -- the
 * order the round speaks them -- up to the room. The windows left are empty
 * desks, dealt their mugs by the day in window order, so the desks in one room
 * all differ and the same day always deals the same.
 */
export function dealRoom(data: Pick<StandupResponse, "asOf" | "workers">): Room {
  const present = (data.workers ?? []).filter((w) => w.present !== false).slice(0, MEMBER_SEATS);
  const members = present.map((worker, i) => ({ ...MEMBER_WINDOWS[i], worker }));
  const open = MEMBER_WINDOWS.slice(members.length);
  const looks = dealMugLooks(standupDayOfYear(data.asOf), open.length);
  return { members, desks: open.map((w, i) => ({ ...w, look: looks[i] })) };
}
