import type { StandupWorker } from "../api.solitaireAgile";

// ── The nine seats (docs/modules/solitaire-agile.md, "The played view") ──────
//
// The stage always has nine tiles in the Remote Standup's composition
// (D-TA17, D-TA18); the team is DEALT onto them. Three are workers' seats, one
// is the chair's, three are the human's queue kinds, and two are derived reads
// -- the tracker and the week -- which V1 draws ghosted with their plate (the
// tracker's lights only when it could not be read, to say so).
//
// The plate carries all three names: the role, the
// persona, then the worker label in parentheses -- the label is the real noun,
// the same word the issue carries, so a tile can always be read back to the
// tracker.

export type SeatKind = "worker" | "chair" | "walk" | "decide" | "look" | "tracker" | "week";

export interface Seat {
  /** The cast member whose tile this is (./cast.tsx). */
  castId: string;
  kind: SeatKind;
  /** The role on the plate, before the persona; none for a plain worker seat. */
  role?: string;
  /** The persona on the plate. */
  persona: string;
  /** A worker seat's own label: the worker this seat is kept for. */
  workerLabel?: string;
}

/** In the card's seat order: the workers, the chair, the queue, the reads. */
export const SEATS: readonly Seat[] = [
  {
    castId: "dev-hero",
    kind: "worker",
    role: "TEAM LEAD",
    persona: "DEV-HERO",
    workerLabel: "fable",
  },
  { castId: "vibemancer", kind: "worker", persona: "AI VIBEMANCER", workerLabel: "opus" },
  { castId: "minimalist", kind: "worker", persona: "MINIMALIST", workerLabel: "sonnet" },
  { castId: "pm", kind: "chair", role: "CHAIR", persona: "PM" },
  { castId: "qa", kind: "walk", role: "WALK", persona: "QA ALCHEMIST" },
  { castId: "new-hire", kind: "decide", role: "DECIDE", persona: "NEW HIRE" },
  { castId: "designer", kind: "look", role: "LOOK", persona: "DESIGNER" },
  { castId: "ops-dev", kind: "tracker", role: "TRACKER", persona: "OPS-DEV" },
  { castId: "ultrawide", kind: "week", role: "THE WEEK", persona: "ULTRAWIDE OVERLORD" },
];

export function seatOf(kind: Exclude<SeatKind, "worker">): Seat {
  const s = SEATS.find((x) => x.kind === kind);
  if (!s) throw new Error(`no ${kind} seat`);
  return s;
}

/** `ROLE · PERSONA (label)`, each part only when it is there. */
export function plateFor(seat: Seat, label?: string): string {
  const name = seat.role ? `${seat.role} · ${seat.persona}` : seat.persona;
  return label ? `${name} (${label})` : name;
}

export interface Dealt {
  /** Each worker seat that has someone in it today, in seat order. */
  seated: { seat: Seat; worker: StandupWorker }[];
  /** Workers with no seat left: the chair counts them (nine is the ceiling). */
  standing: StandupWorker[];
}

/**
 * Deal today's workers onto the three worker seats. A worker whose label a
 * seat is kept for sits there; any other worker takes the first free worker
 * seat, in the response's (label) order; past three, the worker is standing.
 * "A worker is many" -- one seat per running instance -- waits on the agent
 * half knowing its workers (the card's open item), so V1 is one tile a label.
 */
export function dealSeats(workers: readonly StandupWorker[]): Dealt {
  const workerSeats = SEATS.filter((s) => s.kind === "worker");
  const taken = new Map<string, StandupWorker>();
  const rest: StandupWorker[] = [];
  for (const w of workers) {
    const own = workerSeats.find((s) => s.workerLabel === w.label.toLowerCase());
    if (own && !taken.has(own.castId)) taken.set(own.castId, w);
    else rest.push(w);
  }
  const standing: StandupWorker[] = [];
  for (const w of rest) {
    const free = workerSeats.find(
      (s) => !taken.has(s.castId) && !workers.some((x) => x.label.toLowerCase() === s.workerLabel),
    );
    if (free) taken.set(free.castId, w);
    else standing.push(w);
  }
  const seated = workerSeats
    .filter((s) => taken.has(s.castId))
    .map((seat) => ({ seat, worker: taken.get(seat.castId)! }));
  return { seated, standing };
}
