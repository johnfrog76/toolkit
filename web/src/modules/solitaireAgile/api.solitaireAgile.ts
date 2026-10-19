/**
 * Solitaire Agile's data (docs/modules/solitaire-agile.md, "The routes").
 *
 * One read in M0 -- the standup route, today's standup for the Space you are
 * in, passed as `?space=<slug>` the way the Studio asks the pane's routes about
 * a Space. The route is the contract's (`consts.json` `rituals.route`), read
 * through `@consts` and never retyped. The ceremonies keep no state (D-TA2).
 *
 * The reminder to attend (D-TA15) is an Organize reminder, and the web
 * writes none of it: `POST rituals.attendRoute` re-arms it (the agent runs
 * Organize's own verbs through the bridge), `GET rituals.remindRoute` reads it
 * for the settings row, and setting it is `Standup -Remind` through
 * `POST /api/cmd/Standup`. Each write invalidates Organize's `Reminders` tag,
 * so the bell counts the reminder it just re-armed.
 *
 * The module owns this endpoint; a machine with the flag off never imports
 * this file into a mounted component, so nothing is fetched.
 */
import { API_BASE, api, CACHE_TTL } from "../../shell/api";
import { RITUALS } from "../../shell/consts";
import type { CommandResponse } from "../ado/api.ado";

/** One item in a slot, as the route serves it: an issue (a number and a url)
 *  or, from a local Space, a card (an id and a path, number null, url ""). */
export interface RitualItem {
  number: number | null;
  id?: string | null;
  title: string;
  url: string;
  path?: string;
  /** What moved (RITUALS.motions): closed, started or inProgress -- already said
   *  in `text` after the ref. Absent from an agent that predates it. */
  motion?: string;
  /** The distinct commits its card threads; 0 with no card. */
  commits?: number;
}

/** One worker's motion in the window, or the total's (label and name ""). */
export interface MotionCount {
  label: string;
  name: string;
  closed: number;
  started: number;
  inProgress: number;
  commits: number;
}

/** A walk item also names the worker it is routed to. */
export interface QueueItem extends RitualItem {
  worker?: string;
}

export interface StandupWorker {
  /** The tracker label that routes to this worker ("fable"). */
  label: string;
  /** The name the label's description gives ("<worker>"). */
  name: string;
  yesterday: RitualItem[];
  today: RitualItem[];
  blockers: RitualItem[];
  /** All three slots empty: the worker renders the mug and its one status sentence. */
  empty: boolean;
  /** The empty worker's status sentence (the `nothing` family). The name is historical. */
  excuse: string;
}

/** One group at the work grain (D-TA20): what a slot's items belong to --
 *  a milestone, a design card, a card type or the titles' common stem -- how many,
 *  which, and the phrase the ritual says for it ("Team Agile, three closed"). */
export interface WorkGroup {
  name: string;
  by: string;
  count: number;
  /** `#<n>` for an issue, the id for a card, in the slot's order. */
  refs: string[];
  phrase: string;
}

export interface WorkWorker {
  label: string;
  name: string;
  yesterday: WorkGroup[];
  today: WorkGroup[];
  blockers: WorkGroup[];
  /** The prose: this worker's sentences, in order -- one a group, then
   *  "Nothing blocked." when it has something to say and no blockers; empty
   *  for a worker with nothing, who is its status sentence. */
  prose: string[];
}

/** The standup at the grain of the work: the same items, grouped, and its text. */
export interface StandupWork {
  queue: { walk: WorkGroup[]; decide: WorkGroup[]; look: WorkGroup[] };
  workers: WorkWorker[];
  /** The prose: the queue's sentences, one a group, kind by kind. */
  queueProse: string[];
  /** One line for the queue and one a worker, each its sentences, LF-joined --
   *  the same string `Standup -Grain work` prints. */
  text: string;
}

/** The dress: each worker's sentences as the stage says them -- the work
 *  row's prose, with each sentence a model re-said in the standup register and
 *  the guard let through in its place. Present only when a model answered. */
export interface StandupSpoken {
  model: string;
  workers: { label: string; prose: string[] }[];
  /** Sentences in the model's words, and sentences where the prose stood. */
  dressed: number;
  refused: number;
}

export interface StandupResponse {
  ceremony: "standup";
  register: "real";
  asOf: string;
  since: string;
  space: string;
  /** Which source filled it: an active GitHub Space's issues and cards joined
   * on the id ("both"), a local Space's cards, or none when nothing answered
   * (an ADO Space, gh down). "issues" is what an agent that predates the join says. */
  source?: "issues" | "cards" | "both" | "none";
  /** false: no tracker answered. The ritual still happens (principle 3). */
  tracker: { ok: boolean; reason: string };
  chair: { open: string; close: string };
  queue: { walk: QueueItem[]; decide: QueueItem[]; look: QueueItem[] };
  workers: StandupWorker[];
  /** The work grain: the items grouped, one phrase a group. Absent from
   *  an agent that predates it; the stage then speaks the items one by one. */
  work?: StandupWork;
  /** The dress: null with no model key (the stage speaks `work`), absent
   *  from an agent that predates it. */
  spoken?: StandupSpoken | null;
  /** The rendering, LF-joined -- the same string the CLI's Standup prints. */
  text: string;
  /** The chair's reading: a few lines, each a count or a derived fact, LF-joined.
   *  Absent from an agent that predates it. */
  brief?: string;
  /** The "both" source: where a card and its issue disagree, one sentence each
   *  (already in `text`). Absent from an agent that predates the join. */
  checks?: string[];
  /** The "both" source: each card joined to its issue, with the card's lane. */
  links?: { number: number; id: string; lane: string; path: string }[];
  /** What moved in the window, per worker and in total -- a hash counted once
   *  however many cards thread it. The brief's first line says the total.
   *  Absent from an agent that predates it. */
  counts?: { workers: MotionCount[]; total: MotionCount };
}

/** The standup reminder, as `GET /api/ritual/standup/remind` reads it. */
export interface StandupReminder {
  id: string;
  /** As stored: "YYYY-MM-DDTHH:MM", "YYYY-MM-DD" or "". */
  due: string;
  /** The reminder's Ref line: its cadence, `HH:mm <days>`. */
  ref: string;
  /** The cadence read back; "" and [] when ref is not one. */
  time: string;
  days: string[];
}

export interface RemindState {
  /** features.organize: without it there is no reminder to set. */
  organize: boolean;
  reminder: StandupReminder | null;
}

/** What attending did: off | absent | none | rearm | unreadable | error. */
export interface AttendResponse {
  organize: boolean;
  action: string;
  archived: string[];
  next: string;
  reason: string;
}

/** The contract names a route from the server's root; the slice's base is
 *  already API_BASE, so the query is the part under it. */
export function underBase(route: string): string {
  return route.startsWith(`${API_BASE}/`) ? route.slice(API_BASE.length + 1) : route;
}

export const STANDUP_QUERY = underBase(RITUALS.route);
export const ATTEND_QUERY = underBase(RITUALS.attendRoute);
export const REMIND_QUERY = underBase(RITUALS.remindRoute);

/** The query for one Space's standup; "" asks for the Space you are in. */
export function standupQuery(space: string): string {
  return space ? `${STANDUP_QUERY}?space=${encodeURIComponent(space)}` : STANDUP_QUERY;
}

// "Reminders" is Organize's tag: a write here re-arms an Organize reminder, and
// the bell and the Organize card read it under that tag.
const ritualsApi = api.enhanceEndpoints({ addTagTypes: ["StandupRemind", "Reminders"] });

export const solitaireAgileEndpoints = ritualsApi.injectEndpoints({
  endpoints: (builder) => ({
    // GET /api/ritual/standup?space=<slug> -- today's standup, derived now
    getStandup: builder.query<StandupResponse, string>({
      query: standupQuery,
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/ritual/standup/remind -- the reminder to attend, as it stands
    getStandupRemind: builder.query<RemindState, void>({
      query: () => REMIND_QUERY,
      providesTags: ["StandupRemind"],
      keepUnusedDataFor: CACHE_TTL,
    }),

    // POST /api/ritual/standup/attend -- attending re-arms it, once a day
    attendStandup: builder.mutation<AttendResponse, void>({
      query: () => ({ url: ATTEND_QUERY, method: "POST" }),
      invalidatesTags: ["StandupRemind", "Reminders"],
    }),

    // POST /api/cmd/Standup -- Standup -Remind; the argv is buildStandupRemindParams
    runStandupRemind: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/Standup", method: "POST", body: { params } }),
      invalidatesTags: ["StandupRemind", "Reminders"],
    }),
  }),
});

export const {
  useGetStandupQuery,
  useGetStandupRemindQuery,
  useAttendStandupMutation,
  useRunStandupRemindMutation,
} = solitaireAgileEndpoints;

// -- Triage (V1) ----------------------------------------------------------
//
// The open issues by milestone, the group with no milestone first -- the read
// the Triage page asks one issue at a time. Its answers are WRITES, and a write
// is the CLI's `Route` through the bridge (POST /api/cmd/Route, argv from
// cliBridge.ts's buildRouteParams), never a route of this module's (D-TA2).

/** One open issue, with the answers it already carries. */
export interface TriageIssue {
  number: number;
  title: string;
  url: string;
  /** The worker's name ("<worker>"), "" when no label routes it. */
  worker: string;
  /** The worker LABEL -- the size (D-TA3) -- "" when none. */
  size: string;
  /** The severity label it carries, "" when none. */
  severity: string;
  deepWater: boolean;
}

export interface TriageGroup {
  /** "" is the group with no milestone; it comes first. */
  milestone: string;
  open: number;
  routed: number;
  unrouted: number;
  /** "N open, M routed, K unrouted" -- the agent's words, from ceremonies.json. */
  context: string;
  issues: TriageIssue[];
}

export interface TriageResponse {
  ceremony: "triage";
  space: string;
  /** false: no tracker answered; `reason` says why, and there are no groups. */
  tracker: { ok: boolean; reason: string };
  /** The three questions, in order: milestone, severity, size. */
  slots: string[];
  severities: string[];
  deepWaterLabel: string;
  /** The repo's worker labels: what a size answer may be. */
  sizes: { label: string; name: string }[];
  groups: TriageGroup[];
  /** The rendering, LF-joined -- the same string the CLI's Triage prints. */
  text: string;
}

export const TRIAGE_QUERY = underBase(RITUALS.triageRoute);

/** The query for one Space's triage; "" asks for the Space you are in. */
export function triageQuery(space: string): string {
  return space ? `${TRIAGE_QUERY}?space=${encodeURIComponent(space)}` : TRIAGE_QUERY;
}

const triageApi = api.enhanceEndpoints({ addTagTypes: ["Triage"] });

export const triageEndpoints = triageApi.injectEndpoints({
  endpoints: (builder) => ({
    // GET /api/ritual/triage?space=<slug> -- the open issues by milestone, derived now
    getTriage: builder.query<TriageResponse, string>({
      query: triageQuery,
      providesTags: ["Triage"],
      keepUnusedDataFor: CACHE_TTL,
    }),

    // POST /api/cmd/Route -- one answer; the argv is buildRouteParams
    runRoute: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/Route", method: "POST", body: { params } }),
      invalidatesTags: ["Triage"],
    }),
  }),
});

export const { useGetTriageQuery, useRunRouteMutation } = triageEndpoints;
