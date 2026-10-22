/**
 * The Studio's data.
 *
 * The foyer reads every GitHub Space's facts in ONE read, GET /api/studio/ledger
 * (consts.json studio.ledgerRoute): each Space's issue report, newest runs and
 * repository visibility, in the shapes /api/issue-report, /api/deploys and
 * /api/visibility answer -- one gh call for all of them on the agent, kept on
 * its disk for ten minutes (docs/modules/studio.md, "The routes") -- so it never
 * switches into a Space to read it; every other Space's row reads the core's own
 * GET /api/status, through its `space` argument for a Space you are
 * not in (FoyerCard). The seed drawer reads the hub's design/ notes
 * (GET /api/studio/design, /api/studio/design/{name}); the Prompts card reads
 * the agentic prompts (GET /api/studio/prompts, /api/studio/prompts/{ref}).
 *
 * The writes -- a new note, Promote, a new Space, and retiring or removing
 * one -- are the CLI's verbs through the bridge (POST /api/cmd/NewDesign,
 * POST /api/cmd/NewItem -FromDesign, POST /api/cmd/NewSpace, POST
 * /api/cmd/RetireSpace, POST /api/cmd/RemoveSpace): there is no native write route into the
 * hub, so there is no second writer to get the byte contract wrong. The New Space
 * dialog's picker reads GET /api/spaces/candidates, which is the same verb's
 * -Discover through the bridge.
 *
 * The Spaces card's reads, and the shell's visibility read, are kept for
 * the session (SESSION_CACHE): nothing re-reads them on a remount, a
 * focus or a timer -- only the card's Refresh, or a write that invalidates
 * Status (the cards) or Env (the Spaces, and so the ledger).
 *
 * The module owns these endpoints. The Studio is core (D-S13) but its pages are
 * still lazy parts, so this file arrives with the first Studio page drawn.
 */
import { api, API_BASE, CACHE_TTL, SESSION_CACHE } from "../../shell/api";
import type { HowIWork, SpaceVisibility } from "../../shell/api";
import { STUDIO } from "../../shell/consts";
import type {
  CommandResponse,
  DeploysResponse,
  Design,
  DesignNotShown,
  DesignSearchResponse,
  DesignStructure,
  IssueReport,
  StatusResponse,
} from "../ado/api.ado";

const encodePath = (path: string) => path.split("/").map(encodeURIComponent).join("/");

const spaceArg = (space: string) => `space=${encodeURIComponent(space)}`;

/** One hub design note, as GET /api/studio/design serves it. */
export interface DesignNote {
  name: string;
  title: string;
  description: string;
  /** The Space the note names in its frontmatter, "" when none. */
  space: string;
  /** The `> GitHub:` issue URL, "" when the note has no thread yet. */
  thread: string;
  thread_number: number | null;
  /** owner/name of the thread's repo. */
  thread_repo: string;
  /** The declared GitHub Space whose repos hold the thread, "" when none does. */
  thread_space: string;
}

export interface DesignNotesResponse {
  /** The hub's design folder's name, as the hub calls it. */
  folder: string;
  /** ... and its spec folder's (design lifecycle L2). Absent from an older agent. */
  specFolder?: string;
  /** False when the hub has no such folder -- a hub an older Start copied out.
   *  Absent from an older agent, which reads as "there". */
  exists?: boolean;
  /** The live notes in design/, as before: the + and Promote read these. */
  count: number;
  items: DesignNote[];
  /** The drawer's groups (L2): the hub's four folders grouped by id, each row's
   *  state read from where its files are -- the same shape GET /api/design
   *  answers for a repo, plus `space` and `thread_space` on a hub row. Absent
   *  from an older agent. */
  designs?: Design[];
  notShown?: DesignNotShown[];
  structure?: DesignStructure;
}

export interface DesignNoteDetail extends DesignNote {
  /** The file's hub-relative path, e.g. design/archive/old.md (L2). */
  path?: string;
  kind?: "note" | "spec" | string;
  archived?: boolean;
  body: string;
}

/** A way of working a shipped prompt belongs to: an answer to How do you want
 *  to work?, in the words /env's `howIWork` answers in. */
export type PromptWorkflow = HowIWork["answer"];

/** One agentic prompt's record, as GET /api/studio/prompts serves each row:
 *  everything but its text, which the one-prompt read carries (PromptRow). */
export interface PromptListRow {
  /** pr-ship -- the file's name before .prompt.md. */
  name: string;
  /** The reading room's address after /studio/prompts/: the name, yours/<name>, or space/<name>. */
  ref: string;
  /** ToolKit's (the package's agentic/), yours (the hub's, or agenticExtensionPath),
   *  or the active Space's (its repository's own agentic/, read through gh). */
  group: "toolkit" | "yours" | "space";
  /** Where it lives: agentic/pr-ship.prompt.md, or your folder's. */
  path: string;
  /** The absolute path on the agent's machine; for the Space's, the file's address on GitHub. */
  file_path: string;
  /** The record's title: the frontmatter's `title`, else its `# ` heading, else the name. */
  title: string;
  /** The frontmatter's description, "" when the prompt has none. */
  description: string;
  /** The record's purpose: the same one sentence. */
  purpose: string;
  /** Whose it is, worked out by the agent from where it lives: toolkit, yours,
   *  or the Space's slug. */
  owner: string;
  /** The index's category for a shipped prompt, else the frontmatter's
   *  `category` line; the agent says "uncategorized" for one with none. */
  category: string;
  /** The index's ways of working; [] for one of yours -- every way. */
  workflows: PromptWorkflow[];
  /** "by hand", else the verb or route that sends it; "" for one of yours. */
  sender: string;
  by_hand: boolean;
  /** core, or the add-on it comes with. */
  module: string;
  /** What it drives -- the verbs it calls, or what the sender does with it. */
  drives: string;
  /** One of yours, in agenticExtensionPath under a shipped name: it runs instead. */
  overrides: boolean;
  /** The local day it last changed; "" for the Space's, which the contents read does not carry. */
  changed: string;
  /** Its history on GitHub, "" when the folder is not a GitHub clone. */
  history: string;
}

/** One prompt, as GET /api/studio/prompts/{ref} serves it: the record and its text. */
export interface PromptRow extends PromptListRow {
  /** The whole file -- what Copy prompt copies. */
  body: string;
}

/** Which Space the list was read for, as the agent says it: the web works out
 *  nothing here. `repo` is "" when the address names none (a local Space, an
 *  Azure one, an owner-grained address); `isToolkit` when that repository is
 *  this package's own origin -- its agentic/ is the shipped set already. */
export interface PromptSpace {
  slug: string;
  name: string;
  repo: string;
  isToolkit: boolean;
}

export interface PromptsResponse {
  count: number;
  prompts: PromptListRow[];
  /** Absent from an older agent, which reads as no Space filter. */
  space?: PromptSpace;
  /** agentic/prompts.json's category vocabulary, in its order -- the card's
   *  category row draws in it. Absent from an older agent: every category
   *  reads as one outside the vocabulary. */
  categories?: string[];
}

/** One GitHub Space's row facts, in the shapes the three per-Space routes answer. */
export interface SpaceLedger {
  report: IssueReport;
  deploys: DeploysResponse;
  visibility: SpaceVisibility;
}

/** GET /api/studio/ledger -- every declared GitHub Space's facts, by slug. A
 *  Space that is not GitHub has no entry. */
export interface StudioLedger {
  spaces: Record<string, SpaceLedger>;
}

/** The Spaces card's one ledger read, under the api's base (consts.json studio.ledgerRoute). */
export const LEDGER_QUERY = STUDIO.ledgerRoute.startsWith(`${API_BASE}/`)
  ? STUDIO.ledgerRoute.slice(API_BASE.length + 1)
  : STUDIO.ledgerRoute;

/** The Prompts card's read, under the api's base (consts.json studio.promptsRoute). */
export const PROMPTS_QUERY = STUDIO.promptsRoute.startsWith(`${API_BASE}/`)
  ? STUDIO.promptsRoute.slice(API_BASE.length + 1)
  : STUDIO.promptsRoute;

/** One of your repositories, as GET /api/spaces/candidates serves it -- a row of
 *  `NewSpace -Discover -AsJson`, so the proposals are the verb's own. */
export interface SpaceCandidate {
  /** owner/name */
  repo: string;
  name: string;
  owner: string;
  /** PUBLIC | PRIVATE | INTERNAL, as gh says it. */
  visibility: string;
  /** GitHub has archived the repository: marked, listed last, still addable. */
  isArchived?: boolean;
  /** ADMIN | MAINTAIN | WRITE | TRIAGE | READ, "" when gh did not say. */
  viewerPermission?: string;
  /** You can read it and not write to it: marked, still addable. The
   *  verb's rule over viewerPermission -- the dialog only draws it. */
  readOnly?: boolean;
  description: string;
  proposedSlug: string;
  proposedName: string;
  /** The slug of the Space this repository already is, "" when none. */
  space: string;
  spaceName: string;
  command: string;
  /** Why gh said nothing of a typed repository (`?repo=`), in the verb's words --
   *  "not visible to this login: gh answered ..." -- and "" when it answered. */
  note?: string;
}

/** The two verbs a Space's row menu runs. */
export type SpaceLifecycleVerb = "RetireSpace" | "RemoveSpace";

/** GET /api/spaces/candidates -- never refused: `available: false` and a
 *  sentence when gh cannot answer, and the dialog offers a typed field. */
export interface SpaceCandidates {
  available: boolean;
  reason: string;
  hint: string;
  account: string;
  /** Whose repositories these are; the account when none was asked.
   *  Absent from an older agent. */
  owner?: string;
  /** The owners the dialog's selector offers, the verb's list: you, your
   *  organisations, then the repositories shared with you. Absent from an older agent. */
  owners?: SpaceOwner[];
  /** How many repositories one list is read to, the verb's ceiling. Absent or 0
   *  from an older agent. */
  ceiling?: number;
  /** The list stopped at the ceiling and there are more. */
  more?: boolean;
  repos: SpaceCandidate[];
}

/** One entry of the New Space dialog's owner selector -- `value` is what the
 *  verb's -Owner takes, so the dialog sends it back as it came. */
export interface SpaceOwner {
  value: string;
  label: string;
  kind: string;
}

// "Status" is the ado module's tag (api.ado.ts); named here too so this file's
// type knows it -- adding a tag type twice is harmless. "Env" and "Surfaces" are
// the shell's: a new Space is a new row in /env's spaces.
const studioApi = api.enhanceEndpoints({
  addTagTypes: ["DesignNotes", "Status", "Env", "Surfaces", "SpaceCandidates", "Prompts"],
});

export const studioEndpoints = studioApi.injectEndpoints({
  endpoints: (builder) => ({
    // GET /api/studio/ledger -- every GitHub Space's report, runs and
    // visibility at once. Tagged Env: a Space added, retired or removed is a
    // changed /env, and the agent then reads only the Space it has not kept.
    getStudioLedger: builder.query<StudioLedger, void>({
      query: () => LEDGER_QUERY,
      keepUnusedDataFor: SESSION_CACHE,
      providesTags: ["Env"],
    }),
    // GET /api/studio/ledger?refresh=1 -- the card's Refresh, past the agent's
    // disk cache. A mutation as refreshSpaceVisibility is one: never cached
    // itself, its answer belongs in getStudioLedger's entry -- and each Space's
    // visibility in the shell's getSpaceVisibility entry for that Space.
    refreshStudioLedger: builder.mutation<StudioLedger, void>({
      query: () => ({ url: `${LEDGER_QUERY}?refresh=1`, method: "GET" }),
      async onQueryStarted(_arg, { dispatch, queryFulfilled }) {
        try {
          const { data } = await queryFulfilled;
          dispatch(studioEndpoints.util.upsertQueryData("getStudioLedger", undefined, data));
          for (const [slug, entry] of Object.entries(data.spaces)) {
            dispatch(api.util.upsertQueryData("getSpaceVisibility", slug, entry.visibility));
          }
        } catch {
          // An agent that did not answer leaves the last answer in place.
        }
      },
    }),
    // GET /api/status?space=<slug> -- another Space's cards in play, read from
    // its own folder without switching in. Tagged Status, so a card
    // moved anywhere refreshes the counts.
    getSpaceStatus: builder.query<StatusResponse, string>({
      query: (space) => `status?${spaceArg(space)}`,
      keepUnusedDataFor: SESSION_CACHE,
      providesTags: ["Status"],
    }),
    // GET /api/studio/design -- the seed drawer
    getDesignNotes: builder.query<DesignNotesResponse, void>({
      query: () => "studio/design",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["DesignNotes"],
    }),
    // GET /api/studio/design/{path} -- one note or spec, its reading room: a bare
    // name is the live note (as the route always read it), else the hub path --
    // design/archive/old.md, spec/x.spec.md (L2).
    getDesignNote: builder.query<DesignNoteDetail, string>({
      query: (path) => `studio/design/${encodePath(path)}`,
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["DesignNotes"],
    }),
    // GET /api/studio/design/search?q= -- search inside the hub's four folders,
    // on disk (L2b). Asked only when a person asks for it.
    searchHubDesigns: builder.query<DesignSearchResponse, string>({
      query: (q) => `studio/design/search?q=${encodeURIComponent(q)}`,
      providesTags: ["DesignNotes"],
    }),
    // GET /api/studio/prompts -- the Prompts card: ToolKit's, yours and the
    // Space's records, without their text (Copy prompt reads it: getPrompt).
    getPrompts: builder.query<PromptsResponse, void>({
      query: () => PROMPTS_QUERY,
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Prompts"],
    }),
    // GET /api/studio/prompts/{ref} -- one prompt's reading room.
    getPrompt: builder.query<PromptRow, string>({
      query: (ref) => `${PROMPTS_QUERY}/${encodePath(ref)}`,
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Prompts"],
    }),
    // POST /api/cmd/NewDesign -- the argv is buildNewDesignParams (../ado/cliBridge.ts)
    runNewDesign: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/NewDesign", method: "POST", body: { params } }),
      invalidatesTags: ["DesignNotes"],
    }),
    // GET /api/spaces/candidates -- the New Space dialog's picker. Asked
    // when the dialog opens, and kept briefly: it costs a PowerShell start and a gh call.
    // The owner is the verb's -Owner; "" is your own repositories.
    getSpaceCandidates: builder.query<SpaceCandidates, string | void>({
      query: (owner) =>
        owner ? `spaces/candidates?owner=${encodeURIComponent(owner)}` : "spaces/candidates",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["SpaceCandidates"],
    }),
    // GET /api/spaces/candidates?repo=owner/name -- the one repository typed into
    // the dialog's search, read before it is added (the verb's -Discover -Repo):
    // the Add owner/name row's visibility, or the verb's note when gh cannot see it.
    getTypedSpaceCandidate: builder.query<SpaceCandidates, string>({
      query: (repo) => `spaces/candidates?repo=${encodeURIComponent(repo)}`,
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["SpaceCandidates"],
    }),
    // POST /api/cmd/NewSpace -- the argv is buildNewSpaceParams (../ado/cliBridge.ts).
    // The new Space is a new row of /env's spaces, so /env is read again and the
    // row appears without a reload; the picker is read again too -- that
    // repository is a Space now. (A refusal re-reads them as well: harmless, and
    // the connect wizard's write does the same.)
    runNewSpace: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/NewSpace", method: "POST", body: { params } }),
      invalidatesTags: ["Env", "Surfaces", "SpaceCandidates"],
    }),
    // POST /api/cmd/RetireSpace|RemoveSpace -WhatIf -- the confirm's preview: the
    // verb's own lines for the keys that would go and the folder that stays.
    // Writes nothing, so it invalidates nothing.
    previewSpaceLifecycle: builder.mutation<
      CommandResponse,
      { verb: SpaceLifecycleVerb; params: string[] }
    >({
      query: ({ verb, params }) => ({ url: `cmd/${verb}`, method: "POST", body: { params } }),
    }),
    // POST /api/cmd/RetireSpace|RemoveSpace -- the argv is
    // buildSpaceLifecycleParams. A retired Space is a changed row of /env's spaces
    // and a removed one a missing row, so /env is read again; the picker too -- a
    // removed Space's repository can be added again.
    runSpaceLifecycle: builder.mutation<
      CommandResponse,
      { verb: SpaceLifecycleVerb; params: string[] }
    >({
      query: ({ verb, params }) => ({ url: `cmd/${verb}`, method: "POST", body: { params } }),
      invalidatesTags: ["Env", "Surfaces", "SpaceCandidates"],
    }),
    // POST /api/cmd/NewItem -- Promote: the argv is buildPromoteDesignParams.
    // The same verb the Backlog uses; the note comes back with its thread.
    runPromoteDesign: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/NewItem", method: "POST", body: { params } }),
      invalidatesTags: ["DesignNotes"],
    }),
    // POST /api/cmd/MoveDesign -- a hub design along its road (L3): the argv is
    // buildMoveDesignParams, always with -Hub. The drawer re-reads its groups.
    runMoveDesign: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/MoveDesign", method: "POST", body: { params } }),
      invalidatesTags: ["DesignNotes"],
    }),
  }),
});

export const {
  useGetStudioLedgerQuery,
  useRefreshStudioLedgerMutation,
  useGetSpaceStatusQuery,
  useGetDesignNotesQuery,
  useGetDesignNoteQuery,
  useGetPromptsQuery,
  useGetPromptQuery,
  useLazyGetPromptQuery,
  useLazySearchHubDesignsQuery,
  useRunNewDesignMutation,
  useRunPromoteDesignMutation,
  useRunMoveDesignMutation,
  useGetSpaceCandidatesQuery,
  useGetTypedSpaceCandidateQuery,
  useRunNewSpaceMutation,
  usePreviewSpaceLifecycleMutation,
  useRunSpaceLifecycleMutation,
} = studioEndpoints;
