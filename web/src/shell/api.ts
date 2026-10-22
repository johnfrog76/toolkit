import type { WorkflowEntry } from "./settingsWorkflows";
import { createApi, fetchBaseQuery } from "@reduxjs/toolkit/query/react";

// The shell's half of the API slice.
//
// One store, one `createApi`, and exactly the endpoints the shell itself
// needs: /env, which every module is gated on, and /switch-mode, which
// changes which org the whole app is scoped to. Everything else is injected
// by whichever module owns it (see modules/ado/api.ado.ts) -- a module that
// is switched off contributes no endpoints, no cache keys and no tags.

// ── Environment types ───────────────────────────────────────────────────────

export interface EnvCheck {
  ok: boolean;
  detail: string;
}

/**
 * Which PowerShell the agent will start for `POST /cmd/{name}`. `pwsh` where it
 * exists, `powershell` on a Windows machine with only the 5.1 floor, and `null`
 * on a machine with neither -- where every write through the bridge fails, so
 * the shell is told rather than left to discover it on click.
 */
export interface BridgeHost {
  resolved: "pwsh" | "powershell" | null;
  path: string;
}

/**
 * Who the agent thinks "me" is, and where that came from. The three ADO routes
 * filter by this address, so a machine with no `email` in its own (gitignored)
 * config.local.json used to render a config gap as an empty PR list -- the
 * System card names the source instead.
 */
export interface Identity {
  email: string;
  /** "config" | "branchUser" | "az", or "" when nothing answered. */
  source: string;
}

export interface SpaceInfo {
  slug: string;
  name: string;
  status: "active" | "local" | "archive";
  /** The Space's address, as configured. Absent from an older agent. */
  org?: string;
  /** WHICH tracker that address names, derived by the agent (D-G2) -- the
   *  Studio's foyer draws a row for each `github` one. Absent from an older agent. */
  tracker?: "ado" | "github" | "none";
  /** True on a shipped example Space -- the demos. The Studio's Spaces card
   *  files these under Out of box. Absent means false. */
  example?: boolean;
  /** {contract word: display name} for THIS Space's lanes, resolved by the
   *  agent the way `config.laneNames` is for the active one. Absent
   *  from an older agent, which reads as the contract's own words. */
  laneNames?: Record<string, string>;
}

/** /env's `howIWork`: the active Space's answer to How do you want to work here? */
export interface HowIWork {
  answer: "alone" | "agents" | "team";
  source: "derived" | "chosen" | "default";
  tracker: "ado" | "github" | "none";
  locked: boolean;
  switch?: boolean | null;
}

export interface EnvStatus {
  /** Which build the agent is: consts.json's `version`. Absent from an older agent. */
  version?: string;
  machine: string;
  os: string;
  nodeVersion?: string;
  pythonVersion?: string;
  container: boolean;
  tier: number;
  tierLabel: string;
  spaceStatus: "active" | "local" | "archive";
  features?: Record<string, boolean>;
  /**
   * Whether Azure DevOps is part of what is SHOWN. Derived by the agent --
   * `features.ado`, else on where the Space you are in is active AND its address names
   * Azure DevOps -- and never re-derived
   * here (docs/modules/ado.md, "The switch, and its scope"). `explicit` is true when someone set
   * the flag. Absent from an older agent, which reads as "on": what it always was.
   */
  ado?: { enabled: boolean; explicit: boolean };
  /** WHICH tracker the active board's address names -- derived by the agent
   *  (D-G2), never re-derived here.
   *  Absent from an older agent. */
  tracker?: "ado" | "github" | "none";
  /** How do you want to work in this Space? -- the active Space's
   *  answer, resolved by the agent (agent/core/config.py how_i_work) and never
   *  re-derived here. `team` and `alone` with no tracker are derived and
   *  `locked`; on GitHub the answer is `chosen`, or `default` (alone) when
   *  nobody has said. `switch` is Team Agile's own flag as set -- null when
   *  unset. Absent from an older agent. */
  howIWork?: HowIWork;
  /** Whether `StartWork <id> -Launch` can start a session on this machine -- the
   *  derived launch surface (D-AR13). The field's name is consts.json
   *  startWork.launchEnvFlag; an interface cannot take a computed name, so it is
   *  spelled here, and consts.test.ts holds this to be the one place it is. The hand-off box draws its second
   *  button only when this is true; absent (an agent without the launch) reads off. */
  startWorkLaunch?: boolean;
  anthropicConfigured: boolean;
  // The provider profile's model id, ai.model in config.
  aiModel?: string;
  bridgeHost?: BridgeHost;
  uptime: number;
  /** Who the nav bar's avatar is. Served by /env from config, never committed. */
  displayName?: string;
  /** The prefix every verb is typed with on this machine ("tk"), from config. */
  cliPrefix?: string;
  /** The configured card types -- Bug, User Story, Task, Feature, Spike, or a
   *  team's own -- in config's order. What "New card" offers. */
  cardTypes?: string[];
  /** Who the ADO routes filter by, and where it came from. */
  identity?: Identity;
  checks: Record<string, EnvCheck>;
  config: {
    org: string | null;
    projects: Array<{ name: string; repo: string }>;
    promptsFolder: string;
    activeSpace: string;
    spaces: SpaceInfo[];
    /** {contract word: display name} for the active org's four lanes. Display only. */
    laneNames?: Record<string, string>;
    /** `isDemoDismissed`: `spaces` above already leaves the demo Spaces out; this says why. */
    isDemoDismissed?: boolean;
    /** `firstRun.welcome`: the first-run banner is on. Set by tkStart, cleared by the banner. */
    firstRunWelcome?: boolean;
    /** `limits.inPlay`: the WIP number the Active column goes amber past; null when none is set. */
    inPlayLimit?: number | null;
  };
}

// ── API definition ──────────────────────────────────────────────────────────

/** seconds -- keep unused data cached for 30 minutes */
export const CACHE_TTL = 1800;

/** Kept for the whole session: never dropped for being unused, so a remount
 *  reads the store, not the agent. Only an explicit Refresh, or a write's tag
 *  invalidation, reads again -- the Studio's Spaces card's reads. RTK
 *  Query schedules no eviction at all for Infinity. */
export const SESSION_CACHE = Infinity;

/** One optional surface as the CLI's inventory reports it (Scripts/Get-OptionalSurfaces.ps1). */
export interface SurfaceRow {
  key: string;
  title: string;
  state: "on" | "off" | "not configured";
  /** The CLI line that changes it. */
  config: string;
  note: string;
  question: string;
}

/** GET /api/surfaces: the inventory with states, and the entries of
 *  Config/settings-workflows.json, in one answer. */
export interface SurfaceInventory {
  surfaces: SurfaceRow[];
  entries: WorkflowEntry[];
  activeSpace: string;
  prefix: string;
}

/** GET /api/visibility[?space=<slug>]: whether a GitHub Space's
 *  repository is public. `visibility` is VISIBILITY.public | .private |
 *  .unknown (shell/consts.ts) -- unknown when the tracker did not answer, never
 *  a guess. `supported: false` (and `visibility: ""`) for a Space whose tracker
 *  is not GitHub: it has no visibility, and nothing is drawn for it. */
export interface SpaceVisibility {
  supported: boolean;
  visibility: string;
  repos: Array<{ repo: string; visibility: string }>;
}

/** Where the agent's routes are mounted (agent/core/config.py API_PREFIX). The
 *  slice's base, and the one prefix a URL built outside it -- an image the
 *  reading room serves through /docs/asset -- starts with. */
export const API_BASE = "/api";

export const api = createApi({
  reducerPath: "api",
  baseQuery: fetchBaseQuery({ baseUrl: API_BASE, timeout: 120_000 }),
  tagTypes: ["Env", "Surfaces"],
  endpoints: (builder) => ({
    // GET /api/env
    getEnv: builder.query<EnvStatus, void>({
      query: () => "env",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Env"],
    }),

    // GET /api/surfaces -- the optional-surface inventory with its states and
    // the settings-by-workflow entries, as the CLI's resolver computed them
    // (D-W2). The drawer's "How do I"
    // section and the tips at the foot of Home read it; a config write
    // invalidates it (api.ado.ts, writeConfig).
    getSurfaces: builder.query<SurfaceInventory, void>({
      query: () => "surfaces",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Surfaces"],
    }),

    // GET /api/visibility -- whether a Space's repository is public.
    // "" is the Space you are in; a slug is that Space, read without switching
    // (the Spaces card's rows). The agent caches it per repository; here it is
    // kept for the session -- the Spaces card's Refresh asks again.
    getSpaceVisibility: builder.query<SpaceVisibility, string>({
      query: (space) => (space ? `visibility?space=${encodeURIComponent(space)}` : "visibility"),
      keepUnusedDataFor: SESSION_CACHE,
    }),

    // GET /api/visibility?space=<slug>&refresh=1 -- the same route, past the
    // agent's per-repository cache. A mutation for the reason refreshEnv
    // is one: it is the Spaces card's Refresh, it is never cached itself, and
    // its answer belongs in getSpaceVisibility's entry for that Space.
    refreshSpaceVisibility: builder.mutation<SpaceVisibility, string>({
      query: (space) => ({
        url: space
          ? `visibility?space=${encodeURIComponent(space)}&refresh=1`
          : "visibility?refresh=1",
        method: "GET",
      }),
      async onQueryStarted(space, { dispatch, queryFulfilled }) {
        try {
          const { data } = await queryFulfilled;
          dispatch(api.util.upsertQueryData("getSpaceVisibility", space, data));
        } catch {
          // An agent that did not answer leaves the last answer in place.
        }
      },
    }),

    // GET /api/health -- the shell's heartbeat. /env costs a probe and changes
    // every second (uptime); this is the cheap question "is the agent there?",
    // polled so an agent that dies mid-session is NOTICED instead of turning
    // every card into its own small, differently worded failure.
    getHealth: builder.query<{ status?: string }, void>({
      query: () => "health",
      keepUnusedDataFor: 0,
    }),

    // GET /api/env?refresh=1 -- the same route, past the agent's probe cache.
    //
    // A mutation rather than a second query: it is an ACTION (the System card's
    // refresh button), it must never be cached, and its answer belongs in the
    // getEnv cache rather than beside it. The agent caches the ADO reachability
    // probe for 45s because it costs a cold `az` start; a plain refetch would
    // read that cache, which is exactly what someone pressing Refresh does not
    // want.
    refreshEnv: builder.mutation<EnvStatus, void>({
      query: () => ({ url: "env?refresh=1", method: "GET" }),
      async onQueryStarted(_arg, { dispatch, queryFulfilled }) {
        const { data } = await queryFulfilled;
        dispatch(api.util.upsertQueryData("getEnv", undefined, data));
      },
    }),

    // POST /api/switch-mode
    switchMode: builder.mutation<EnvStatus, { mode: string }>({
      query: (body) => ({
        url: "switch-mode",
        method: "POST",
        body,
      }),
      async onQueryStarted(_arg, { dispatch, queryFulfilled }) {
        const { data } = await queryFulfilled;
        dispatch(api.util.resetApiState());
        dispatch(api.util.upsertQueryData("getEnv", undefined, data));
      },
    }),
  }),
});

export const {
  useGetEnvQuery,
  useGetSurfacesQuery,
  useGetSpaceVisibilityQuery,
  useRefreshSpaceVisibilityMutation,
  useGetHealthQuery,
  useRefreshEnvMutation,
  useSwitchModeMutation,
} = api;
