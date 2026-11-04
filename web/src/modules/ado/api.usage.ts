/**
 * The current Claude Code burn: GET /api/usage/burn (consts.json usage.burnRoute).
 *
 * Today and this week, as the CLI's `Burn -AsJson` answers it -- the agent runs the
 * verb through the bridge and keeps the answer on its disk for an hour
 * (docs/hub/usage.md, "Today and this week"). Here it is kept for the browser
 * session (SESSION_CACHE): nothing re-reads it on a remount, a focus or a timer,
 * and nothing polls. Only the tile's Refresh asks again, with refresh=1, past the
 * agent's cache too.
 *
 * Asked only where /env says this machine has Claude Code session files
 * (`env[USAGE.envFlag]`): the System page draws no tile otherwise, and the route
 * is 404 there.
 */
import { api, API_BASE, SESSION_CACHE } from "../../shell/api";
import { USAGE } from "../../shell/consts";

/** One bucket of tokens, as the record and the burn carry it. `costUsdDerived` is
 *  list-price arithmetic, never what anyone paid; null when no model in it is priced. */
export interface BurnFields {
  input: number;
  output: number;
  /** The part of `output` that was thinking -- already inside it. */
  thinking: number;
  cacheWrite5m: number;
  cacheWrite1h: number;
  cacheRead: number;
  messages: number;
  costUsdDerived: number | null;
}

export interface BurnModelRow extends BurnFields {
  model: string;
}

/** Which machine said what: this one from its session files, another from the
 *  day records it logged (`days`, its dates). */
export interface BurnMachineRow {
  machine: string;
  source: "session-files" | "usage-records";
  days: string[];
  messages: number;
  costUsdDerived: number | null;
}

/** Today, or this week: `from` and `to` are UTC instants. */
export interface BurnWindow {
  from: string;
  to: string;
  totals: BurnFields;
  byModel: BurnModelRow[];
  unpriced: string[];
  machines: BurnMachineRow[];
}

export interface BurnResponse {
  burn: number;
  machine: string;
  timezone: string;
  utcOffset: string;
  asOf: string;
  nextBoundaryAt: string;
  weekStarts: string;
  sessionFiles: boolean;
  hub: boolean;
  today: BurnWindow;
  week: BurnWindow;
  cost: {
    derived: boolean;
    currency: string;
    priceTableAsOf: string;
    note: string;
    /** What a price row says about its own price -- a lower rate card, say. */
    priceNotes: Array<{ model: string; note: string }>;
  };
  skipped: { lines: number; records: number };
  /** When the verb ran (the agent adds it), and whether this answer is the agent's kept one. */
  fetchedAt: string;
  fromCache: boolean;
}

/** The route under the api's base. */
export const BURN_QUERY = USAGE.burnRoute.startsWith(`${API_BASE}/`)
  ? USAGE.burnRoute.slice(API_BASE.length + 1)
  : USAGE.burnRoute;

export const usageEndpoints = api.injectEndpoints({
  endpoints: (builder) => ({
    // GET /api/usage/burn -- kept for the session.
    getBurn: builder.query<BurnResponse, void>({
      query: () => BURN_QUERY,
      keepUnusedDataFor: SESSION_CACHE,
    }),
    // GET /api/usage/burn?refresh=1 -- the tile's Refresh, past the agent's hour.
    // A mutation, as the Spaces card's refresh is: never cached itself, its answer
    // belongs in getBurn's entry.
    refreshBurn: builder.mutation<BurnResponse, void>({
      query: () => ({ url: `${BURN_QUERY}?refresh=1`, method: "GET" }),
      async onQueryStarted(_arg, { dispatch, queryFulfilled }) {
        try {
          const { data } = await queryFulfilled;
          dispatch(usageEndpoints.util.upsertQueryData("getBurn", undefined, data));
        } catch {
          // An agent that did not answer leaves the last answer in place.
        }
      },
    }),
  }),
});

export const { useGetBurnQuery, useRefreshBurnMutation } = usageEndpoints;
