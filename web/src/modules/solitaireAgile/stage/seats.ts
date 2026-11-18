import { RITUALS } from "../../../shell/consts";
import type { StandupResponse, StandupWorker } from "../api.solitaireAgile";
import { dealMugLooks } from "./EmptyDesk";
import type { MugLook } from "./EmptyDesk";

// ── The room (docs/modules/solitaire-agile.md, "The played view") ────────────
//
// The stage is always nine windows, the Zoom grid (D-TA17). The chair keeps
// its own window; the other eight are the members' windows, in grid order. The
// windows, their plates, the chair's, the windows three labels keep and the
// engineer's are the shared room (consts.json `rituals.room`): the terminal's
// Standup and the agent seat the same room from it, and one table
// (Tests/fixtures/rituals/standup-team.json, `room`) holds all three.
//
// The web never reads the team-size setting. It draws what the response gives
// it: the round (`work.workers`) -- the seated members in turn order, then the
// invented cast members that fill the seats the size still counts -- each in
// its window, capped at the room. So a Space sized three draws two members and
// six desks because the round has two, not because the stage knows the number.

const ROOM = RITUALS.room;

/** The room's windows, the chair's included: the 3x3 grid. Read everywhere; never typed again. */
export const ROOM_WINDOWS = ROOM.windows.length;
/** The windows a member can sit in: the room less the chair's. */
export const MEMBER_SEATS = ROOM_WINDOWS - 1;

/** The cast member whose window is the chair's. */
export const CHAIR_CAST_ID = ROOM.chair;
/** The chair's plate. */
export const CHAIR_PLATE = "CHAIR · PM";
/** The plate on a window with nobody in it. */
export const EMPTY_DESK_PLATE = "EMPTY DESK";

/** One member window: its cast member and the persona on its plate. */
export interface MemberWindow {
  castId: string;
  persona: string;
}

/** The eight member windows, in grid order: the room's, the chair's left out. */
export const MEMBER_WINDOWS: readonly MemberWindow[] = ROOM.windows
  .filter((w) => w.id !== CHAIR_CAST_ID)
  .map((w) => ({ castId: w.id, persona: w.plate }));

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
  /** An invented cast member: it sits in its own window and wears its persona alone. */
  cast: boolean;
}

export interface EmptyWindow extends MemberWindow {
  look: MugLook;
}

export interface Room {
  /** Everyone in the room but the chair, in speaking order, each in its window. */
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
export const KEPT_WINDOWS: Readonly<Record<string, string>> = ROOM.kept;

/** The plate a seated member wears: `PERSONA (label)`, or the persona alone for
 *  an invented cast member, whose label is the persona's own id. */
export function seatedPlate(m: Seated): string {
  return m.cast ? m.persona : memberPlate(m, m.worker.label);
}

const MEMBER_IDS = MEMBER_WINDOWS.map((m) => m.castId);

/** The window a label owns: the one it keeps, or its own when the label is
 *  itself a member window's cast id (compared in lowercase); "" for neither. */
function ownWindow(label: string): string {
  const low = label.toLowerCase();
  return KEPT_WINDOWS[low] ?? (MEMBER_IDS.includes(low) ? low : "");
}

type Dealt = Pick<StandupResponse, "asOf" | "workers"> &
  Partial<Pick<StandupResponse, "work" | "space" | "source">>;

/** An invented cast member as the stage's worker: idle, named by its plate. Its
 *  turn is the round's own prose. */
function castWorker(label: string, name: string): StandupWorker {
  return {
    label,
    name,
    yesterday: [],
    today: [],
    blockers: [],
    empty: true,
    excuse: "",
    status: [],
  };
}

/** Who speaks, in turn order. The round the response carries (`work.workers`:
 *  the seated members in seat order, then the invented cast members) when it
 *  accounts for exactly the present members of the record; else -- no work
 *  grain, or an agent that predates the room -- the present members in the
 *  record's order. */
function roundOf(data: Dealt): { worker: StandupWorker; cast: boolean }[] {
  const record = data.workers ?? [];
  const present = record.filter((w) => w.present !== false);
  const byLabel = new Map(record.map((w) => [w.label, w]));
  const round = data.work?.workers;
  const said = (round ?? []).filter((w) => !w.cast);
  const whole =
    said.length === present.length &&
    said.every((w) => byLabel.has(w.label) && byLabel.get(w.label)!.present !== false);
  if (!round || !whole) return present.map((worker) => ({ worker, cast: false }));
  return round.map((w) =>
    w.cast
      ? { worker: castWorker(w.label, w.name), cast: true }
      : { worker: byLabel.get(w.label)!, cast: false },
  );
}

/**
 * Seat today's standup: the same rule the terminal and the agent seat by
 * (`room_seats`, `Get-P20StandupRoomSeats`), read off the response.
 *
 * - The round, in turn order, up to the room: the engineer first, the labelled
 *   workers, then the invented cast members. The order is the turns', whichever
 *   window each sits in.
 * - An invented cast member sits in its own window: its label is its cast id.
 * - A window is a member's own when its label is in KEPT_WINDOWS or is itself a
 *   member window's cast id. A seated member sits in its own window; one in the
 *   response but out today keeps it EMPTY, so no other face takes it and nobody
 *   moves when that member is back.
 * - The engineer -- the member the Space's own slug names, where cards fill the
 *   standup -- otherwise takes the engineer's window when no member owns it.
 * - Every other seated member takes the free windows in grid order, the
 *   engineer first and then the labels in the record's order, so a label's
 *   window does not move when its work does; only when the free ones run out
 *   does it take a window an absent member keeps, so nobody seated is dropped.
 * - The windows left are empty desks, dealt their mugs by the day in window order.
 */
export function dealRoom(data: Dealt): Room {
  const record = data.workers ?? [];
  const round = roundOf(data).slice(0, MEMBER_SEATS);
  const filled = data.source === "cards" || data.source === "both";
  const engineer = filled && data.space ? record.find((w) => w.label === data.space) : undefined;
  const people = [...(engineer ? [engineer] : []), ...record.filter((w) => w !== engineer)];
  const reserved = new Set(people.map((w) => ownWindow(w.label)).filter(Boolean));
  const seated = new Set(round.filter((r) => !r.cast).map((r) => r.worker));
  const dealing = people.filter((w) => seated.has(w));

  const windowOf = new Map<StandupWorker, string>();
  const taken = new Set<string>();
  const sit = (w: StandupWorker, castId: string) => {
    windowOf.set(w, castId);
    taken.add(castId);
  };
  for (const w of dealing) {
    const own = ownWindow(w.label);
    if (own && !taken.has(own)) sit(w, own);
  }
  if (engineer && seated.has(engineer) && !windowOf.has(engineer) && !reserved.has(ROOM.engineer))
    sit(engineer, ROOM.engineer);
  // The invented sit in their own windows before anyone is dealt: the rule
  // never invents a member for a window a seated or absent member owns.
  for (const r of round) {
    const own = r.cast ? ownWindow(r.worker.label) : "";
    if (own && !taken.has(own)) sit(r.worker, own);
  }
  const open = [
    ...MEMBER_IDS.filter((id) => !reserved.has(id) && !taken.has(id)),
    ...MEMBER_IDS.filter((id) => reserved.has(id) && !taken.has(id)),
  ];
  for (const w of [...dealing, ...round.filter((r) => r.cast).map((r) => r.worker)]) {
    if (!windowOf.has(w)) sit(w, open.shift()!);
  }

  const members = round.map(({ worker, cast }) => ({
    ...MEMBER_WINDOWS.find((m) => m.castId === windowOf.get(worker))!,
    worker,
    cast,
  }));
  const empty = MEMBER_WINDOWS.filter((m) => !taken.has(m.castId));
  const looks = dealMugLooks(standupDayOfYear(data.asOf), empty.length);
  return { members, desks: empty.map((w, i) => ({ ...w, look: looks[i] })) };
}
