import { api, CACHE_TTL } from "../../shell/api";
import type { EnvStatus } from "../../shell/api";
import type { CommandResponse } from "../ado/api.ado";

// The communication module's half of the API slice.
//
// Injected into the shell's single `api` object rather than standing up a
// second store: the module owns its endpoints and the tag they invalidate, the
// shell owns `createApi` and /env. A module that is switched off is never
// imported, so none of this exists -- not "exists but goes unused".

// -- Types -------------------------------------------------------------------

export interface ManagerItem {
  filename: string; // "<date>.md", or "client-weekly-<date>.md" for a series
  /** The series -- which recurring meeting. "" is the 1:1, the default. */
  series?: string;
  date: string; // "<date>"
  stage: string; // "draft" | "prep" | "retro"
  folder: string; // "current" | "archive"
  summary: string;
}

export interface ManagerResponse {
  items: ManagerItem[];
}

export interface ManagerDetailResponse {
  filename: string;
  /** "" is the 1:1; otherwise the series slug. */
  series?: string;
  /** YYYY-MM-DD, read from the name by the contract's rule -- use this, not the filename. */
  date?: string;
  /** Absolute path on the agent's machine; absent from an older agent. */
  path?: string;
  /** "current" or "archive" (the contract's folder names). GET serves a closed
   *  session and PUT refuses one, so the send has to know which this is BEFORE
   *  it posts -- a message it cannot record is a message that invites a second
   *  press. Absent from an older agent. */
  folder?: string;
  stage: string; // record type -- "session" is the only one
  session_stage: string; // "draft" | "prep" | "retro"
  title: string;
  purpose: string;
  content: string;
  since: string;
  forward: string;
  retro_input: string;
  sent: string;
  /** The `## Carried from` check (docs/hub/manager.md, "Which session a record
   *  carries from"). The agent states the verdict and the sentence; the page
   *  only draws the sentence. All four are absent from an older agent. */
  carried_from?: string;
  carried_from_expected?: string;
  carried_from_verdict?: "ok" | "stale" | "missing" | "absent";
  /** The sentence to show; "" when the heading is right. */
  carried_from_note?: string;
}

export interface ManagerSaveRequest {
  date?: string;
  /** On create: "" or absent is the 1:1; otherwise a slug names another recurring meeting. */
  series?: string;
  since?: string;
  forward?: string;
  retro?: string;
  /** One line to add under `## Sent`, e.g. "Sent to manager: <date>". */
  append_sent?: string;
}

export interface CommsSection {
  heading: string;
  body: string;
}

export interface CommsSendRequest {
  caller: string;
  recipient: string;
  subject: string;
  sections: CommsSection[];
  tone: "broadcast" | "alert" | "personal";
  dryRun?: boolean;
}

/** The engine never throws; every outcome arrives as one of these six. */
export interface CommsSendResponse {
  status: "ok" | "dry-run" | "disabled" | "rejected" | "skipped" | "error";
  detail: string;
  target?: { recipient: string; display: string } | null;
  payload?: string | null;
}

/**
 * What /env carries for this module. It is declared here, not in the shell's
 * `EnvStatus`, because it is this module's vocabulary: the shell serves the
 * payload without knowing what is in this key, and a checkout without the
 * module never sees it at all.
 *
 * `configured` is gate 2 answered ahead of the click -- whether the recipient's
 * webhook variable is actually set. `scope` says which config block the entry
 * came from, because "the manager recipient is top-level and the team channels
 * are the org's" is a real property of the config and hiding it would make
 * switching org look like a bug.
 */
export interface CommunicationRecipient {
  key: string;
  display: string;
  type: string;
  scope: "managerWorkflow" | "org";
  webhookEnv: string;
  configured: boolean;
}

export interface CommunicationEnv {
  postRetroSummary: boolean;
  retroChannel: string;
  recipients: CommunicationRecipient[];
}

/** `EnvStatus` plus this module's block. Absent when the flag is off. */
export type EnvWithCommunication = EnvStatus & { communication?: CommunicationEnv };

// -- Endpoints ---------------------------------------------------------------

// `enhanceEndpoints` is how a module adds a tag type to a slice it did not
// create. Declaring "Manager" on the shell's `createApi` would put this
// module's vocabulary in the shell, which is the thing being avoided.
const communicationApi = api.enhanceEndpoints({ addTagTypes: ["Manager"] });

export const communicationEndpoints = communicationApi.injectEndpoints({
  endpoints: (builder) => ({
    // GET /api/manager
    getManager: builder.query<ManagerResponse, void>({
      query: () => "manager",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Manager"],
    }),

    // GET /api/manager/:filename
    getManagerDetail: builder.query<ManagerDetailResponse, string>({
      query: (filename) => `manager/${encodeURIComponent(filename)}`,
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Manager"],
    }),

    // POST /api/manager
    createManagerSession: builder.mutation<ManagerDetailResponse, ManagerSaveRequest>({
      query: (body) => ({ url: "manager", method: "POST", body }),
      invalidatesTags: ["Manager"],
    }),

    // PUT /api/manager/:filename -- the only PUT in the API. A session file is
    // the record, so the thing that changes it changes it in place.
    updateManagerSession: builder.mutation<
      ManagerDetailResponse,
      { filename: string } & ManagerSaveRequest
    >({
      query: ({ filename, ...body }) => ({
        url: `manager/${encodeURIComponent(filename)}`,
        method: "PUT",
        body,
      }),
      invalidatesTags: ["Manager"],
    }),

    // POST /api/comms/send -- not a mutation of anything local, and it
    // invalidates nothing: the write-back that records the send is a separate
    // PUT, so the file is what says it happened.
    sendComms: builder.mutation<CommsSendResponse, CommsSendRequest>({
      query: (body) => ({ url: "comms/send", method: "POST", body }),
    }),

    // POST /api/rewrite -- tidy a raw notes textarea.
    rewriteText: builder.mutation<{ text: string }, { text: string }>({
      query: (body) => ({ url: "rewrite", method: "POST", body }),
    }),

    // POST /api/cmd/MeetingAgenda -- the stage driver, through the bridge. The
    // one write in this module that goes the way every other write in the app
    // goes: the CLI verb runs, in a child pwsh, and this page only asks. The
    // argv is `buildMeetingAgendaParams` (../ado/cliBridge.ts), pinned by test.
    // A stage stamp or a close changes what GET /manager says, so both
    // invalidate the tag.
    runMeetingAgenda: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/MeetingAgenda", method: "POST", body: { params } }),
      invalidatesTags: ["Manager"],
    }),
  }),
});

export const {
  useGetManagerQuery,
  useGetManagerDetailQuery,
  useCreateManagerSessionMutation,
  useUpdateManagerSessionMutation,
  useSendCommsMutation,
  useRewriteTextMutation,
  useRunMeetingAgendaMutation,
} = communicationEndpoints;
