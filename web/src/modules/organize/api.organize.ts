/**
 * The Organize add-on's data.
 *
 * One read -- GET /api/reminders, the open reminders with their buckets worked
 * out by the agent against the local clock -- and two writes, both the CLI's
 * verbs through the bridge (POST /api/cmd/{name}): there is no native write
 * route, so there is no second writer to get the byte contract wrong. The
 * module owns its endpoints and its tag, and a machine with the flag off never
 * imports this file's hooks into a mounted component, so nothing is fetched.
 */
import { api, CACHE_TTL } from "../../shell/api";
import type { CommandResponse } from "../ado/api.ado";
import type { REMINDERS } from "../../shell/consts";

export type ReminderBucket = (typeof REMINDERS.buckets)[number];

export interface Reminder {
  id: string;
  filename: string;
  title: string;
  /** Exactly as stored: "YYYY-MM-DD", "YYYY-MM-DDTHH:MM", or "" for none. */
  due: string;
  /** Derived by the agent at read time; never stored. */
  bucket: ReminderBucket;
  /** Where it came from -- a tag, shown and never followed. */
  source: string;
  /** Free text, exactly as stored; "" for none. */
  ref: string;
  created: string;
  /** The card `ref` names in the active Space, resolved by the agent; null (or
   *  absent, from an older agent) when the ref is prose or names no card there. */
  card?: ReminderCard | null;
}

/** The card a reminder's ref names (docs/modules/organize.md, "A ref that names a card"). */
export interface ReminderCard {
  id: string;
  /** What the work is called. */
  title: string;
  /** consts.json folders: current | archive. */
  folder: string;
  /** The card's filename -- the card page's address. */
  file: string;
}

export interface RemindersResponse {
  count: number;
  buckets: Record<ReminderBucket, number>;
  items: Reminder[];
  /** The local moment the buckets were worked out against. */
  asOf: string;
}

const organizeApi = api.enhanceEndpoints({ addTagTypes: ["Reminders"] });

export const organizeEndpoints = organizeApi.injectEndpoints({
  endpoints: (builder) => ({
    // GET /api/reminders
    getReminders: builder.query<RemindersResponse, void>({
      query: () => "reminders",
      providesTags: ["Reminders"],
      keepUnusedDataFor: CACHE_TTL,
    }),

    // POST /api/cmd/Reminders -- snooze or archive one, by id. The argv is
    // buildReminderSnoozeParams / buildReminderArchiveParams (../ado/cliBridge.ts).
    runReminders: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/Reminders", method: "POST", body: { params } }),
      invalidatesTags: ["Reminders"],
    }),

    // POST /api/cmd/NewReminder -- the quick add. The argv is buildNewReminderParams.
    runNewReminder: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/NewReminder", method: "POST", body: { params } }),
      invalidatesTags: ["Reminders"],
    }),
  }),
});

export const { useGetRemindersQuery, useRunRemindersMutation, useRunNewReminderMutation } =
  organizeEndpoints;
