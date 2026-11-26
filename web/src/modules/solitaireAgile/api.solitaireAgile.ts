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
import type { CommandResponse, Milestone } from "../ado/api.ado";

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
  /** The distinct commits its card threads -- on a GitHub Space, only those
   *  authored inside the window; 0 with no card. */
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
  /** Commits the dates read could not date: not in `commits`, said beside them.
   *  Absent from an agent that predates it. */
  undated?: number;
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
  /** The empty worker's status sentence: the first of `status`, kept for a reader that
   *  knows only this field. The name is historical. */
  excuse: string;
  /** The empty worker's two made-up items, `[yesterday, today]` (the `nothing` and
   *  `nothingToday` families); `[]` for a worker with something to say. */
  status: string[];
  /** In the room today (the team size, docs/modules/solitaire-agile.md, "The team
   *  size: who is in the room"): the round -- `work.workers`, the stage -- is the
   *  present only; the detail and the brief keep every worker. Absent from an agent
   *  that predates the room, which reads as present. */
  present?: boolean;
  /** The plate a member a card names wears when its family keeps no window
   *  (`GROK`, an unknown id in capitals); `""` or absent for everyone else, who
   *  wears their window's persona. */
  plate?: string;
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
  /** The prose: this worker's turn, in order -- `turnOpen`, one sentence a
   *  group, a slot with nothing beside one with something its fixed line
   *  (`proseYesterdayNone`, `proseYesterdayWorked`, `proseTodayNone`), a worker
   *  with nothing at all its two made-up items, then `proseBlockersNone` when
   *  nothing blocks it, then `turnClose`. */
  prose: string[];
  /** An invented cast member (the team size, docs/modules/solitaire-agile.md, "The
   *  team size: who is in the room"): it fills a seat the size counts and no member
   *  takes. Its label is its cast id, its name the plate, its turn made-up status;
   *  it is in the round only, never in `workers`. Absent from an agent that predates it. */
  cast?: boolean;
}

/** The standup at the grain of the work: the same items, grouped, and its text. */
export interface StandupWork {
  queue: { walk: WorkGroup[]; decide: WorkGroup[]; look: WorkGroup[] };
  workers: WorkWorker[];
  /** The prose: the queue's sentences, one a group, kind by kind. */
  queueProse: string[];
  /** The chair's own turn, last, in the workers' frame and its own first person:
   *  `turnOpen`, its yesterday (what you walked, else a made-up line), its today
   *  (what waits, kind by kind, or `chairTodayNone`), `proseBlockersNone`,
   *  `turnClose`. Never the queue's sentences again. Absent from an agent that predates it. */
  chairProse?: string[];
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
  /** ok false: no tracker answered. The ritual still happens (principle 3).
   * workerLabels: how many worker labels the tracker answered (0 where none was read). */
  tracker: { ok: boolean; reason: string; workerLabels?: number };
  /** The chair's two phrasebook lines, and `walked`: the walk items closed inside
   *  the window, by number -- what the chair's turn says it walked. `walked` is
   *  absent from an agent that predates it. */
  chair: { open: string; close: string; walked?: RitualItem[] };
  /** The room: its windows, the chair included (`spaces.<slug>.features.teamSize`,
   *  3, 6 or 9, unset 9) -- `size - 1` workers sit. The web never reads the setting;
   *  it draws what this says. Absent from an agent that predates it. */
  team?: { size: number };
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
  /** The suggestion (docs/modules/solitaire-agile.md, "The suggestion: one next
   *  move, derived"): every candidate in the rule's order -- dismiss one and the
   *  page shows the next -- and the first. Empty and null with the Space's switch
   *  off; absent from an agent that predates it. */
  suggestions?: Suggestion[];
  suggestion?: Suggestion | null;
  /** The PM Corner (docs/modules/solitaire-agile.md, "The PM Corner: the line, the
   *  chevron, the confetti"): one derived line for the head of the page. Null where
   *  the suggestion is off or the tracker did not answer; absent from an older agent. */
  corner?: Corner | null;
  /** The Agenda (docs/modules/solitaire-agile.md, "The page"): what moved in the window
   *  and what is waiting on you, as the page's tiles draw them. The agent's alone
   *  (`Standup -AsJson` has no such key); absent from an agent that predates it. */
  agenda?: Agenda;
}

/** One tile of the Agenda, as the agent serves it (agent/solitaire/agenda.py). */
export interface AgendaItem {
  /** `#<n>` for an issue, the card's id. */
  ref: string;
  number: number | null;
  id: string | null;
  kind: "issue" | "card";
  title: string;
  /** The issue's; "" for a card of its own. */
  url: string;
  path: string;
  /** The card's filename while it is in current/ -- what the card page opens; "" otherwise. */
  file: string;
  /** The card's lane (consts.json `status`), "" for an issue with no card. */
  lane: string;
  /** The day the fact line names (yyyy-MM-dd), "" when the record has none. */
  day: string;
  /** Waiting on a review or a merge: the action is Review it, not Work it now. */
  review: boolean;
  cover: string | null;
  checked: number;
  total: number;
  progress: string;
}

export interface Agenda {
  /** What moved in the window: issues closed, cards archived. No action. */
  moved: AgendaItem[];
  /** What is waiting on you, the suggestion's pick first. */
  waiting: AgendaItem[];
}

/** The PM Corner's line, derived by the agent and never re-derived here. */
export interface Corner {
  /** One of consts.json rituals.cornerShapes: oneLeft, manyLeft, reached, nothingInReach. */
  shape: string;
  /** The milestone's title, whole; "" with nothing in reach. */
  milestone: string;
  /** The open items that name it, once per id. */
  remaining: number;
  /** The pick the chevron starts: `#<n>` or the card's id; "" with no pick. */
  ref: string;
  number: number | null;
  id: string | null;
  kind: string;
  noun: string;
  /** The sentence, shown verbatim. */
  line: string;
  /** `StartWork <arg>`, unprefixed; "" with no pick. */
  command: string;
  /** The brief's last line -- the page sets it aside, because it draws the Corner. */
  brief: string;
}

/** One derived next move. `line` is the chair's Next line, shown verbatim. */
export interface Suggestion {
  /** How the standup names it: `#<n>` for an issue, the card's id. */
  ref: string;
  number: number | null;
  id: string | null;
  kind: "issue" | "card";
  /** One of consts.json rituals.suggestShapes: start, delegate, route. */
  shape: string;
  sentence: string;
  /** The verb and its argument, unprefixed: `StartWork 141`, or Route's for a route. */
  command: string;
  line: string;
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
      providesTags: ["Standup"],
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
  /** The first GitHub assignee's login, "" when none. Absent from an older agent. */
  assignee?: string;
  /** Who has it (D-AR10): "me" (RITUALS.assignMe -- the signed-in gh user),
   *  "@<login>", the size, or "" for nobody. Absent from an older agent. */
  who?: string;
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

/** The query for one Space's triage; "" asks for the Space you are in.
 *  `refresh` asks the agent to read the tracker again past its kept read. */
export function triageQuery(space: string, refresh = false): string {
  const params = [
    ...(space ? [`space=${encodeURIComponent(space)}`] : []),
    ...(refresh ? ["refresh=1"] : []),
  ];
  return params.length ? `${TRIAGE_QUERY}?${params.join("&")}` : TRIAGE_QUERY;
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

    // GET /api/ritual/triage?space=<slug>&refresh=1 -- the page's Refresh. The
    // agent keeps each tracker read for 60 seconds, so a plain refetch would be
    // that read again, which is exactly what pressing Refresh does not want. A
    // mutation for the reason refreshEnv is one; it invalidates getTriage, whose
    // refetch is then served the read this one just made.
    refreshTriage: builder.mutation<TriageResponse, string>({
      query: (space) => ({ url: triageQuery(space, true), method: "GET" }),
      invalidatesTags: ["Triage"],
    }),

    // POST /api/cmd/Route -- one answer; the argv is buildRouteParams
    runRoute: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/Route", method: "POST", body: { params } }),
      invalidatesTags: ["Triage"],
    }),
  }),
});

export const { useGetTriageQuery, useRefreshTriageMutation, useRunRouteMutation } = triageEndpoints;

// -- StartWork (AR-1 of the agent in the room) ------------------------------
//
// The hand-off block: how we work in the Space, the card or issue, and its
// prompt, as ONE markdown block. The CLI's `StartWork` builds it, and this half
// asks for it through the bridge (POST /api/cmd/StartWork) -- no route of this
// module's assembles it (D-AR6). It writes nothing, so it invalidates nothing.

/** StartWork's launch switch (D-AR12): a session in a worktree. The CLI's own
 *  parameter name, sent through the bridge like any other argument. */
export const STARTWORK_LAUNCH_SWITCH = "-Launch";

export const startWorkEndpoints = api.injectEndpoints({
  endpoints: (builder) => ({
    // POST /api/cmd/StartWork -- argv is [<id>]: a card id, or an issue number;
    // [<id>, "-Launch"] for the copy box's second button, which is drawn only where
    // /env says the launch is on (consts.json startWork.launchEnvFlag).
    runStartWork: builder.mutation<CommandResponse, { id: string; launch?: boolean }>({
      query: ({ id, launch }) => ({
        url: "cmd/StartWork",
        method: "POST",
        body: { params: launch ? [id, STARTWORK_LAUNCH_SWITCH] : [id] },
      }),
    }),
  }),
});

export const { useRunStartWorkMutation } = startWorkEndpoints;

// -- Milestones (the Releases tab) ----------------------------------------
//
// The Space's tracker milestones with the tracker's own counts. Each row is the
// ado core's own Milestone -- the shape GET /api/milestones serves the Stats
// tab's card, with its one reached rule (every issue closed, and at least one
// issue) -- under Team Agile's gate, scoped to a Space and kept a minute by the
// agent. A READ: the award's seen mark is this browser's (award.ts).

export interface MilestonesResponse {
  ceremony: "milestones";
  space: string;
  /** false: no tracker answered; `reason` says why, and there are no rows. */
  tracker: { ok: boolean; reason: string };
  milestones: Milestone[];
}

export const MILESTONES_QUERY = underBase(RITUALS.milestonesRoute);

/** The query for one Space's milestones; "" asks for the Space you are in. */
export function milestonesQuery(space: string): string {
  return space ? `${MILESTONES_QUERY}?space=${encodeURIComponent(space)}` : MILESTONES_QUERY;
}

export const milestonesEndpoints = api.injectEndpoints({
  endpoints: (builder) => ({
    // GET /api/ritual/milestones?space=<slug> -- every milestone, the tracker's counts
    getRitualMilestones: builder.query<MilestonesResponse, string>({
      query: milestonesQuery,
      keepUnusedDataFor: CACHE_TTL,
    }),
  }),
});

export const { useGetRitualMilestonesQuery } = milestonesEndpoints;

// -- The org chart (the Org tab) ------------------------------------------
//
// The hub's org.json, the tree in use, as GET /api/ritual/org serves it
// (docs/hub/org.md, "The response"): the positions in tree order, each with its
// level and seats, and the fields only the agent adds -- the prompt's title and
// the ref that opens it in the Studio's reading room, and each seat's model by
// its models.json name. A READ: nothing here writes, and there is no Space
// parameter -- the file is the engineer's. No machine is served: a machine is
// not a boundary in an org, so the file's retired machine keys never reach here.

/** One seat of a position: a model, or a person (the owner), or nobody. */
export interface OrgSeat {
  id: string;
  /** The seat's own label where it differs from the position's title; the plate shows it instead. */
  roleTitle: string | null;
  /** As the file says it: a models.json id, a family, or any text. Never parsed. */
  model: string | null;
  /** What the model is called: models.json's name, looked up by the agent; as written with no row. */
  modelName: string | null;
  person: string | null;
  /** The session's name: the address readies and messages route to. Shown on hover. */
  session: string | null;
  /** True on the seat that holds the merge; null when the file does not say. */
  merges: boolean | null;
  space: string | null;
  /** Derived by the reader: vacant is a seat with no model and no person. */
  state: "staffed" | "vacant";
}

export interface OrgPosition {
  id: string;
  title: string;
  prompt: string | null;
  reportsTo: string | null;
  defaultModel: string | null;
  /** The model families the picker offers without a "not recommended" note. */
  recommend: string[];
  /** The root is 0. */
  level: number;
  /** Empty for a pool (the builders): its default-model line is what it says. */
  seats: OrgSeat[];
  /** The prompt's title, as the reading room reads it; null with no prompt. */
  promptTitle: string | null;
  /** The address after /studio/prompts/ (promptPath); null with no prompt, or one
   *  the reading room does not list. */
  promptRef: string | null;
  /** The defaultModel line by its models.json name where it is a model id or a
   *  family (a pool's id reads as the model's name); as written otherwise; null with none. */
  defaultModelName: string | null;
}

export interface OrgTree {
  id: string;
  /** What the org is called: the file's title, else an older file's name, else the id. */
  title: string;
  size: string | null;
  shortDescription: string | null;
  description: string | null;
  teamSize: number | null;
  /** The preset the tree was started from. */
  preset: string | null;
  positions: OrgPosition[];
}

/** One tree of the hub's file, as the route lists them: every saved org. */
export interface OrgTreeSummary {
  id: string;
  title: string;
  size: string | null;
  /** The preset the tree was saved from. */
  preset: string | null;
  /** True on the one tree in use (the file's activeTree, or its only tree). */
  active: boolean;
}

export interface OrgResponse {
  activeTree: string;
  tree: OrgTree;
  /** Every tree of the file, in its order: added by GET /api/ritual/org alone
   *  (a preset's chart has none). */
  trees?: OrgTreeSummary[];
}

/** A refusal's detail: the kind is the contract, the message the sentence. */
export interface OrgRefusal {
  kind: string;
  message: string;
}

export const ORG_QUERY = underBase(RITUALS.orgRoute);

/** The org file's tag: Staff's writes invalidate every chart read. */
const orgApi = api.enhanceEndpoints({ addTagTypes: ["Org"] });

export const orgEndpoints = orgApi.injectEndpoints({
  endpoints: (builder) => ({
    // GET /api/ritual/org[?tree=<id>] -- the tree in use (""), or another saved
    // tree of the hub's org.json; each answer lists every tree of the file.
    getOrgChart: builder.query<OrgResponse, string>({
      query: (tree) => (tree ? `${ORG_QUERY}?tree=${encodeURIComponent(tree)}` : ORG_QUERY),
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Org"],
    }),

    // POST /api/cmd/Staff -- the org file's one writer, through the bridge: a
    // preset saved as a draft (buildStaffPresetParams) or the tree in use chosen
    // (buildStaffActivateParams). Either way every chart is read again.
    runStaff: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/Staff", method: "POST", body: { params } }),
      invalidatesTags: ["Org"],
    }),
  }),
});

export const { useGetOrgChartQuery, useRunStaffMutation } = orgEndpoints;

// -- The org presets (the Org tab's dropdown) ------------------------------
//
// The starting orgs the toolkit ships (docs/hub/org.md, "Org presets"), as
// GET /api/ritual/org/presets serves them: each with its words and its chart in
// the response shape above. The page previews one; nothing writes it.

export interface OrgPreset {
  id: string;
  size: string;
  title: string;
  shortDescription: string;
  description: string;
  /** The standup room it suggests (3, 6 or 9); the Space's own setting decides. */
  teamSize: number | null;
  chart: OrgResponse;
}

export interface OrgPresetsResponse {
  presets: OrgPreset[];
}

export const ORG_PRESETS_QUERY = underBase(RITUALS.orgPresetsRoute);

export const orgPresetEndpoints = api.injectEndpoints({
  endpoints: (builder) => ({
    // GET /api/ritual/org/presets -- the shipped presets, read from the package
    getOrgPresets: builder.query<OrgPresetsResponse, void>({
      query: () => ORG_PRESETS_QUERY,
      keepUnusedDataFor: CACHE_TTL,
    }),
  }),
});

export const { useGetOrgPresetsQuery } = orgPresetEndpoints;
