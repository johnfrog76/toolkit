import { api, CACHE_TTL } from "../../shell/api";
import { workItemsPath } from "./issueAxes";
import { docsApiPath } from "./docRooms";
import type { IssueStateChoice } from "./issueAxes";
import {
  buildBillableParams,
  buildMoveParams,
  buildNewAdoItemParams,
  buildCloseWorkItemParams,
  buildEditWorkItemParams,
} from "./cliBridge";
import type {
  ConfigEditPayload,
  ConfigValueType,
  NewAdoItemFields,
  CloseWorkItemFields,
  EditWorkItemFields,
} from "./cliBridge";

// The ADO module's half of the API slice.
//
// Injected into the shell's single `api` object rather than standing up a
// second store (spec S8.5): the module owns its endpoints and the tags they
// invalidate, the shell owns `createApi` and /env. A module that is switched
// off never imports this file, so its endpoints, cache entries and tags do
// not exist.

// -- Types -------------------------------------------------------------------

export interface EngagementStats {
  daysBilled: number;
  prsReviewed: number;
  workItemsClosed: number;
  reviewsGenerated: number;
}

export interface EngagementSummaryResponse {
  client: string;
  role: string;
  startDate: string | null;
  endDate: string | null;
  totalDays: number;
  projects: Array<{ name: string; repo: string }>;
  stats: EngagementStats;
}

export interface WorkBreakdownByType {
  bug: number;
  story: number;
  feature: number;
  task: number;
  prReviews: number;
}

export interface WorkBreakdownSprintEntry {
  sprint: string;
  bug: number;
  story: number;
  feature: number;
  task: number;
}

export interface WorkBreakdownResponse {
  byType: WorkBreakdownByType;
  bySprint: WorkBreakdownSprintEntry[];
}

/** The Card model (docs/hub/cards.md, "The model, as the agent serves it") as `/api/status` serves it.
 *  `title` is the whole heading and predates the model; `id`, `type` and `name`
 *  are the same facts as FIELDS, so nothing here parses a sentence or a filename. */
export interface PromptInfo {
  file: string;
  /** "141" for a card with a work item, "K7M2" for one without. */
  id: string | null;
  /** A configured card type: Bug, User Story, Task, Feature, Spike, or a team's own. */
  type: string | null;
  /** What the work is called -- the heading after "Type id:". */
  name: string;
  /** A card with a link is an "ADO card". That is the whole difference. */
  linked: boolean;
  /** WHOSE ledger: the agent's tracker rule over the card's OWN link --
   *  "none" exactly when not linked. Absent from an older agent. */
  tracker?: "github" | "ado" | "none";
  /** False only when the card says `**Billable:** no`. No line means billable. */
  billable: boolean;
  /** Who takes it: the card's `**Assigned:**` line -- "me", or a size -- "" for
   *  nobody (D-AR10; `Route -Assign` writes it). Absent from an older agent. */
  assigned?: string;
  title: string;
  sprint: string;
  progress: string;
  checked: number;
  total: number;
  modified: string;
  ado_url: string | null;
  /** Its presence IS Code Review. The agent always sent it; this type dropped it. */
  pr_url: string | null;
  /**
   * Commit bullets in the file -- the git token, not a `**Started:**` line.
   * What Create PR is gated on (cardActions.ts). Absent from an older agent.
   */
  commits?: number;
  status: string;
  /** The tracker's own pin on the card's issue: true only on a GitHub
   *  Space at Tier 1. Absent from an older agent, which reads as unpinned. */
  pinned?: boolean;
  /** The card's picture: a URL of GET /api/assets/..., or null -- no
   *  `**Cover:**` line, or one whose file is missing. Absent from an older agent. */
  cover?: string | null;
  /** The other half of a before/after proof, the same way. */
  before?: string | null;
  /** The design the card was worked against, as its line says; unresolved here. */
  design?: CardDesign | null;
}

/** The design a card names (docs/hub/design.md): its
 *  Design line -- or the corpus's hand-written Spec line, read as written -- as
 *  the agent parsed it. On the card's own page the agent also resolves the id:
 *  `state`, `where` and `path` say what it found, "" when it could not read it,
 *  and the chip then shows the line as last written. */
export interface CardDesign {
  kind: "design" | "spec" | string;
  title: string;
  link: string;
  /** The design's id; "" for a hand-written Spec line. */
  id: string;
  short: string;
  /** What the line says after the link and the id, as written. */
  note: string;
  /** Design | Spec | Complete | Archived, once resolved. */
  state: string;
  /** hub | repo, once resolved: which reading room opens it. */
  where: "hub" | "repo" | "";
  /** The document to open: design/x.md, spec/archive/x.spec.md. */
  path: string;
}

/** A card worked against a design: every card whose Design line carries
 *  the design's id, read by the agent on every request. */
export interface BoundCard {
  file: string;
  id: string | null;
  title: string;
  status: string;
  /** The Space whose folder holds the card. */
  space: string;
  archived: boolean;
}

export interface StatusResponse {
  count: number;
  prompts: PromptInfo[];
}

export interface PromptDetailResponse {
  filename: string;
  /** Absolute path on the agent's machine; absent from an older agent. */
  path?: string;
  id: string | null;
  type: string | null;
  name: string;
  linked: boolean;
  tracker?: "github" | "ado" | "none";
  title: string;
  sprint: string;
  status: string;
  ado_url: string | null;
  pr_url: string | null;
  checked: number;
  total: number;
  progress: string;
  content: string;
  /** The card's pictures, as on PromptInfo. */
  cover?: string | null;
  before?: string | null;
  /** The design it was worked against, its id resolved. Absent from an older agent. */
  design?: CardDesign | null;
}

export interface CommandResponse {
  command: string;
  status: string;
  exit_code: number;
  output: string | null;
  error: string | null;
  duration: number;
}

/** One row of the config schema, as Scripts/Get-ConfigSchema.ps1 emits it. */
export interface ConfigSchemaRow {
  key: string;
  /** machine -> config.local.json, org/hub -> the hub's hub.json, default -> never written. */
  scope: "machine" | "org" | "hub" | "default";
  type: ConfigValueType;
  allowed: string[];
  required: boolean;
  file: string;
  help: string;
}

export interface ConfigSchemaResponse {
  schema: ConfigSchemaRow[];
  /** Why the schema is empty, when it is. The card renders read-only then. */
  error: string | null;
}

/** One resolved setting: what is in force, and which file put it there. */
export interface ConfigSetting {
  key: string;
  scope: "machine" | "org" | "hub";
  file: string;
  value: string;
  source: "default" | "hub" | "local" | "env" | "unset";
}

export interface ConfigResponse {
  activeSpace: string;
  files: { default?: string; local?: string; hub?: string };
  settings: ConfigSetting[];
  error: string | null;
}

/** What PUT /api/config answers with: the CLI's own reply, and the re-read. */
export interface ConfigWriteResponse {
  result: CommandResponse;
  config: ConfigResponse;
}

export interface PRInfo {
  pull_request_id: number;
  title: string;
  role: string;
  project: string;
  repo: string;
  created: string;
  source_branch: string;
  target_branch: string;
  url: string;
}

export interface PRsResponse {
  count: number;
  prs: PRInfo[];
  /**
   * Why the list is empty, when it is empty for a reason the reader can fix --
   * today, an identity the agent could not resolve. Null at Tier 2/3, where an
   * empty list is the honest answer and the tier badge already explains it.
   * A card renders this INSTEAD of its empty state; rendering a config gap as
   * "no pull requests" is the bug it exists for.
   */
  reason?: string | null;
}

/** The pane's reports -- GitHub's own vocabulary, nothing else. */
export interface IssueReport {
  supported: boolean;
  open: number;
  closed: number;
  closed_recent: number;
  sev: Record<string, number>;
  kind: Record<string, number>;
  milestones: { title: string; open: number }[];
  reason?: string | null;
}

/** One GitHub milestone, read with its own counts. `reached` is the
 *  agent's derived word: every issue closed and at least one issue --
 *  GitHub's `state` is not consulted, so a reached milestone can be open. */
export interface Milestone {
  title: string;
  number: number;
  repo: string;
  url: string;
  state: "open" | "closed" | string;
  open: number;
  closed: number;
  /** The due day, "" when none is set. */
  due: string;
  /** The day GitHub closed it, "" while open. */
  closed_at: string;
  /** The day it was made, and the day GitHub last changed it (an issue closing
   *  in it is a change); "" from an agent that predates them. */
  created_at?: string;
  updated_at?: string;
  reached: boolean;
}

export interface MilestonesResponse {
  supported: boolean;
  milestones: Milestone[];
  reason?: string | null;
}

/** The last-deploy face: newest workflow runs per repo. */
export interface DeployRun {
  repo: string;
  title: string;
  status: string;
  conclusion: string;
  branch: string;
  when: string;
  url: string;
}

export interface DeploysResponse {
  supported: boolean;
  runs: DeployRun[];
  reason?: string | null;
}

/** One document in a GitHub Space's repo, `design/` or `spec/` (Studio S2,
 *  D-S11), read through the tracker. `thread` is the issue its
 *  `> GitHub:` line names, "" when none. */
export interface DesignDoc {
  /** design | design/archive | spec | spec/archive */
  folder: string;
  name: string;
  path: string;
  title: string;
  description: string;
  thread: string;
  thread_number: number | null;
  thread_repo: string;
  url: string;
  /** The lifecycle's reads (docs/hub/design.md, "State -- derived, never stored"): the
   *  frontmatter id ("" when the file has none), what the file is, whether it
   *  sits in an archive/, and the stamps -- all read by the agent. Absent from
   *  an older agent. */
  id?: string;
  kind?: "note" | "spec" | string;
  archived?: boolean;
  closed?: string;
  outcome?: string;
  docs?: string;
}

/** A file in one of the four folders that is not a design: no `id:`, or an id
 *  two notes (or two specs) share. Counted, named, never shown as a row. */
export interface DesignNotShown {
  path: string;
  reason: string;
}

/** Which of the two roots the repo (or the hub) has. Neither: the tab teaches
 *  the structure instead of going blank (D-DL11). */
export interface DesignStructure {
  design: boolean;
  spec: boolean;
}

/** One design: one id, a note and at most one spec, its state read from
 *  where the files are -- Design, Spec, Complete, Archived (`DESIGN.states`). */
export interface Design {
  id: string;
  /** The first eight characters, as a person reads it. */
  short: string;
  state: string;
  title: string;
  description: string;
  thread: string;
  thread_number: number | null;
  thread_repo: string;
  /** A fact about a Complete or Archived design: the date it entered the archive. */
  closed: string;
  /** A fact about an Archived note without a spec: shipped or dropped, "" otherwise. */
  outcome: string;
  /** The two files disagree about where the design is -- the agent's sentence, or "". */
  mismatch: string;
  /** Where a Complete spec's durable part landed (`> Docs:`). */
  docs: string;
  note: DesignDoc | null;
  spec: DesignDoc | null;
  /** The hub's rows only: the Space a note names, and the Space that reads its thread. */
  space: string;
  thread_space: string;
  /** The cards worked against it, current/ first. Absent from an older agent. */
  cards?: BoundCard[];
}

/** The Space's checkout on this machine (`spaceCheckouts.<slug>.path`, #146),
 *  checked by the agent against the repo on every read. `ready`: a product
 *  row offers MoveDesign's roads, run in that clone through the bridge. */
export interface DesignCheckout {
  /** The Space it was checked for: what MoveDesign -Space takes. */
  space: string;
  /** The setting, spelled for Config -Set. */
  key: string;
  /** As written in config.local.json; "" when unset. */
  path: string;
  /** The clone's top level, when ready. */
  root: string;
  ready: boolean;
  /** Why not, a sentence that names the setting; "" when ready or unset. */
  reason: string;
}

export interface DesignListResponse {
  supported: boolean;
  repo: string;
  /** Absent from an older agent, and when no Space is active. */
  checkout?: DesignCheckout | null;
  /** Every file read, in folder then name order. */
  items: DesignDoc[];
  /** Grouped by id, in road order then by title (L2). Absent from an older agent. */
  designs?: Design[];
  notShown?: DesignNotShown[];
  structure?: DesignStructure;
  reason?: string | null;
}

export interface DesignDocDetail extends DesignDoc {
  supported: boolean;
  repo: string;
  body: string;
  reason?: string | null;
}

/** One file search inside found (design lifecycle L2b): the design it belongs
 *  to, its state, and the matching line. A file with no id is still a hit,
 *  with no state, so the search never hides what it found. */
export interface DesignSearchHit {
  path: string;
  name: string;
  line: string;
  url: string;
  id: string;
  title: string;
  state: string;
  kind: string;
  archived: boolean;
}

/** GET /api/design/search?q= (a repo, through the tracker's code search) and
 *  GET /api/studio/design/search?q= (the hub, on disk). Asked on request,
 *  never on the tab's first draw; `available: false` with `reason` when the
 *  engine could not answer, and `note` says what the search cannot see. */
export interface DesignSearchResponse {
  supported: boolean;
  repo: string;
  query: string;
  available: boolean;
  reason: string;
  note: string;
  hits: DesignSearchHit[];
}

/** POST /api/assets/upload (docs/hub/cards.md, "A card's pictures"): the
 *  browser's bytes in a temp file, its path for `Cover <card> <path>`. The
 *  route writes nothing into the hub; the verb is the one writer. */
export interface UploadResponse {
  path: string;
  name: string;
  bytes: number;
}

/** One document in a GitHub Space's repo that the Docs tab reads
 *  (D-S12): README.md, or a markdown file under docs/. `folder` is "" for the
 *  README. */
export interface DocEntry {
  path: string;
  name: string;
  folder: string;
  url: string;
}

export interface DocsListResponse {
  supported: boolean;
  repo: string;
  readme: DocEntry | null;
  items: DocEntry[];
  reason?: string | null;
}

export interface DocDetail extends DocEntry {
  supported: boolean;
  repo: string;
  title: string;
  body: string;
  /** The repository's issues on github.com; "" when it has none. */
  issues?: string;
  reason?: string | null;
}

/** The reading room's payload: one issue -- body, thread,
 *  timeline's high signal. `supported: false` on a space with no gh face. */
export interface IssueComment {
  author: string;
  when: string;
  body: string;
}

export interface TimelineItem {
  kind: string; // "commit" | "pr" | "xref"
  text: string;
  url: string;
  when: string;
}

export interface IssueDetail {
  supported: boolean;
  number: number;
  title: string;
  state: string;
  body: string;
  author: string;
  created: string;
  closed: string;
  url: string;
  labels: string[];
  kind: string;
  milestone: string;
  assignee: string;
  repo: string;
  /** GitHub's own pin; absent from an older agent reads as unpinned. */
  pinned?: boolean;
  comments: IssueComment[];
  timeline: TimelineItem[];
  reason?: string | null;
}

export interface WorkItemInfo {
  id: number;
  title: string;
  type: string;
  state: string;
  project: string;
  sprint: string;
  updated: string;
  url: string;
  /** Who holds it -- the GitHub path fills this for the ALL view; the ADO
   *  path leaves it empty (that view is assigned-to-me by construction). */
  assignee?: string;
  /** Raw label names, GitHub path only -- sev chips and the pane's filters. */
  labels?: string[];
  /** The label that routes the issue to a worker (opus, fable, sonnet...),
   *  read by the agent from the label's description. GitHub path only. */
  worker?: string;
  /** The day a closed issue closed; "" while open. GitHub path only. */
  closed?: string;
  /** Pinned on the tracker -- GitHub's own pin, `isPinned`. */
  pinned?: boolean;
}

export interface WorkItemsResponse {
  count: number;
  items: WorkItemInfo[];
  /** See PRsResponse.reason. */
  reason?: string | null;
}

export interface PRCommentSummary {
  file: string;
  title: string;
  pr_id: number;
  open_count: number;
  total_count: number;
}

export interface ListResponse {
  count: number;
  items: PRCommentSummary[];
}

export interface PRCommentItem {
  number: number;
  thread_id: number;
  file_path: string;
  line: number | null;
  published_date?: string;
  reviewer: string;
  severity: string;
  category: string;
  status: string;
  comment_text: string;
  code_suggestion: string;
  decision: string;
  reply: string;
  is_open: boolean;
}

export interface DetailResponse {
  file: string;
  title: string;
  pr_id: number;
  round_num: number;
  open_count: number;
  total_count: number;
  comments: PRCommentItem[];
}

// POST /api/pr-comments/:filename/suggest -- a draft reply to one thread, from
// the agent's provider profile. The body is the thread's own fields;
// the answer is a recommendation, how sure the model is, and the draft.
export interface SuggestRequest {
  thread_id: number;
  comment_text: string;
  file_path: string;
  line: number | null;
  reviewer: string;
  code_suggestion: string;
}

export interface SuggestResponse {
  recommendation: "take" | "reject" | "modify" | string;
  confidence: "high" | "medium" | "low" | string;
  draft_reply: string;
}

export interface LogEntry {
  timestamp: string;
  type: string;
  machine: string;
  source: string;
  detail: string;
}

export interface LogEntriesResponse {
  count: number;
  entries: LogEntry[];
}

/** How many entries the Log card asks the agent for: the newest this many. */
export const LOG_LATEST = 500;

export interface ReviewFile {
  file: string;
  content: string;
}

export interface ReviewPreviewResponse {
  files: ReviewFile[];
}

export interface ReviewDetailResponse {
  folder: string;
  period: string;
  title: string;
  content: string;
  /** Absolute path on the agent's machine; absent from an older agent. */
  path?: string;
}

export interface BillingItem {
  id: string;
  type: string;
  title: string;
  status: string;
}

export interface BillingDay {
  date: string;
  day_name: string;
  items: BillingItem[];
  raw: string;
  compact_raw: string;
}

export interface BillingResponse {
  days: BillingDay[];
  raw: string;
  compact: string;
  /** "stamps" (the cards' own dates) or "stamps+git" (plus the days git saw a card touched). */
  source?: string;
  /** Cards left off because they say `**Billable:** no`. */
  nonBillable?: number;
  /** Cards with no date on them: counted, never guessed. */
  unstamped?: number;
  /** Set only when the week could NOT be built. An empty week has no error. */
  error?: string;
}

export interface PipelineRun {
  pipeline_name: string;
  result: string;
  branch: string;
  finished: string | null;
  url: string;
  build_id: number;
}

export interface ProjectPipelines {
  project: string;
  repo: string;
  runs: PipelineRun[];
}

export interface ProjectInfo {
  project: string;
  repo: string;
}

export interface RepoHealth {
  last_commit: string | null;
  unpushed: number;
  uncommitted: number;
  recent_errors: number;
}

export interface DashboardResponse {
  tier: number;
  projects: ProjectInfo[];
  repo: RepoHealth;
  pr_count: number;
  work_item_count: number;
  prompt_count: number;
  /** See PRsResponse.reason. */
  reason?: string | null;
}

export interface SuiteResult {
  suite: string;
  result: "pass" | "fail" | "warn";
  passed: number;
  total: number;
  detail: string;
  description: string;
  /** Which of the three halves ran it: consts.json `tests.halves`. */
  half?: "agent" | "cli" | "web";
}

/** One half's record from the last run that touched it. A skip carries its reason. */
export interface HalfResult {
  half: "agent" | "cli" | "web";
  result: "pass" | "fail" | "skip";
  passed: number;
  failed: number;
  skipped: number;
  total: number;
  seconds: number;
  reason: string;
  timestamp: string;
}

export interface TestDay {
  date: string;
  passed: number;
  total: number;
  suites: SuiteResult[];
}

export interface TestSummaryMachine {
  machine: string;
  timestamp: string;
  suites: Record<string, SuiteResult>;
  /** The machine's three halves, in run order; a file from before them has the CLI's alone. */
  halves?: Partial<Record<"agent" | "cli" | "web", HalfResult>>;
}

export interface TestHistoryResponse {
  machine: string;
  active_space: string; // Space context the shown org-scoped results ran under
  days: TestDay[];
  last_run: string | null;
  streak: number;
  machines: TestSummaryMachine[];
}

export type StressLevel = "Low" | "Medium" | "High";

export interface StressDimension {
  level: StressLevel;
  reasons: string[];
}

export interface StressContext {
  sprintName: string;
  sprintFullName: string;
  daysRemaining: number | null;
  mergeVelocity: number;
  upstreamMerges: number;
  surfaceAreaChange: number;
  rebasePressure: StressLevel;
  conflictZones: string[];
  prBroadcasted: boolean;
  visibilityScore: number;
  updateCadence: string;
}

export type SprintSource = "ado-iteration" | "config-pinned" | "config" | "card" | "default";

export interface StressStatusResponse {
  enabled: boolean;
  org: string;
  detail: string;
  generatedAt: string | null;
  sourceRepo: string | null;
  sprintSource: SprintSource | null;
  context: StressContext | null;
  sprintStress: StressDimension | null;
  originStress: StressDimension | null;
  communicationStress: StressDimension | null;
  teamDynamicsStress: StressDimension | null;
}

export interface SprintActivityEntry {
  date: string;
  count: number;
  /** Lines added + deleted on the default branch that day; 0 = not recorded (pre-churn history). */
  churn: number;
}

export interface SprintActivityResponse {
  startDate: string;
  endDate: string;
  mine: SprintActivityEntry[];
  team: SprintActivityEntry[];
}

export interface StressRepoInfo {
  name: string;
  hasLocalCheckout: boolean;
  hasData: boolean;
}

export interface StressReposResponse {
  repos: StressRepoInfo[];
  defaultRepo: string | null;
}

// -- Endpoints ---------------------------------------------------------------

// `enhanceEndpoints` is how a module adds its own tag types to a slice it did
// not create. Declaring them on the shell's `createApi` would put every
// module's vocabulary in the shell.
// "Issues" is the tracker's list and its counts -- what NewItem, EditItem and
// CloseItem change; "Issue" is one reading room, by number. A write through
// the bridge names what it changed and the store refetches, so the Issues tab,
// the Issue Report and the open reading room are never a page reload behind
// the ledger ("if I close issue it should update the store").
const adoApi = api.enhanceEndpoints({
  addTagTypes: ["Status", "PrComments", "Config", "Billing", "Issues", "Issue", "Connect"],
});

export const adoEndpoints = adoApi.injectEndpoints({
  endpoints: (builder) => ({
    // GET /api/status  (prompt cards — fetched once, paginated client-side)
    getStatus: builder.query<StatusResponse, void>({
      query: () => "status",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Status"],
    }),

    // GET /api/status/:filename
    getPromptDetail: builder.query<PromptDetailResponse, string>({
      query: (filename) => `status/${encodeURIComponent(filename)}`,
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/prs
    getPrs: builder.query<PRsResponse, void>({
      query: () => "prs",
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/work-items
    getIssueReport: builder.query<IssueReport, void>({
      query: () => "issue-report",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Issues"],
    }),
    // GET /api/milestones -- where the work is going. Beside the
    // report's tag: closing an issue moves a milestone, so a write that
    // invalidates the list and the report invalidates this too.
    getMilestones: builder.query<MilestonesResponse, void>({
      query: () => "milestones",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Issues"],
    }),
    // GET /api/deploys -- the last-deploy face
    // GET /api/design -- the Design tab (Studio S2): the repo's design/ then spec/
    getDesign: builder.query<DesignListResponse, void>({
      query: () => "design",
      keepUnusedDataFor: CACHE_TTL,
    }),
    // GET /api/design/search?q= -- search inside the repo's four folders (L2b),
    // through the tracker's code search. Asked only when a person asks for it.
    searchDesign: builder.query<DesignSearchResponse, string>({
      query: (q) => `design/search?q=${encodeURIComponent(q)}`,
    }),
    // GET /api/design/{folder}/{name} -- one document, its reading room
    getDesignDoc: builder.query<DesignDocDetail, { folder: string; name: string }>({
      // The folder may be a root or its archive (design/archive), so each segment is encoded on its own.
      query: ({ folder, name }) =>
        `design/${folder.split("/").map(encodeURIComponent).join("/")}/${encodeURIComponent(name)}`,
      keepUnusedDataFor: CACHE_TTL,
    }),
    // GET /api/docs -- the Docs tab: the repo's README.md and docs/ tree
    getDocs: builder.query<DocsListResponse, void>({
      query: () => "docs",
      keepUnusedDataFor: CACHE_TTL,
    }),
    // GET /api/docs/{path} -- one document, its reading room
    getDoc: builder.query<DocDetail, string>({
      query: (path) => docsApiPath(path),
      keepUnusedDataFor: CACHE_TTL,
    }),
    getDeploys: builder.query<DeploysResponse, void>({
      query: () => "deploys",
      keepUnusedDataFor: CACHE_TTL,
    }),
    // GET /api/issue/{number} -- the reading room. `space` reads
    // the issue through ANOTHER Space than the active one -- a hub design
    // note's thread, from the Studio (S2b); absent, the active Space's.
    getIssueDetail: builder.query<IssueDetail, { id: number; repo?: string; space?: string }>({
      query: ({ id, repo, space }) => {
        const args = [
          repo ? `repo=${encodeURIComponent(repo)}` : "",
          space ? `space=${encodeURIComponent(space)}` : "",
        ].filter(Boolean);
        return `issue/${id}${args.length ? `?${args.join("&")}` : ""}`;
      },
      keepUnusedDataFor: CACHE_TTL,
      providesTags: (_result, _error, { id }) => [{ type: "Issue", id }],
    }),
    getWorkItems: builder.query<
      WorkItemsResponse,
      { all?: boolean; state?: IssueStateChoice } | void
    >({
      // ?all=1 is the ISSUES TAB on a GitHub space: the
      // unassigned many, not just the items with your name on them. ?state=
      // is the other axis: open by default; closed or all is the
      // opt-in that pulls the closed ones. Two axes, two parameters.
      query: (arg) => workItemsPath(arg || undefined),
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Issues"],
    }),

    // GET /api/log-entries -- the latest LOG_LATEST, newest first. Asked for by
    // number so the badge that says "latest 500" names the number it asked for,
    // not one it assumes the agent defaults to.
    getLogEntries: builder.query<LogEntriesResponse, void>({
      query: () => `log-entries?count=${LOG_LATEST}`,
      keepUnusedDataFor: 0, // always fresh
    }),

    // GET /api/review-preview
    getReviewPreview: builder.query<ReviewPreviewResponse, void>({
      query: () => "review-preview",
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/reviews/:folder (full content)
    // `archived` reads reviews/archive/, where WorkReview -Archive moves a review.
    getReviewDetail: builder.query<
      ReviewDetailResponse,
      { folder: string; slugs?: string; archived?: boolean }
    >({
      query: ({ folder, slugs, archived }) => {
        const q = new URLSearchParams();
        if (slugs) q.set("slugs", slugs);
        if (archived) q.set("archived", "true");
        const qs = q.toString();
        return `reviews/${encodeURIComponent(folder)}${qs ? `?${qs}` : ""}`;
      },
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/billing?week=current|last
    getBilling: builder.query<BillingResponse, string>({
      query: (week) => `billing?week=${week}`,
      keepUnusedDataFor: CACHE_TTL,
      // Daily is built from the cards, so what changes a card's place on it
      // -- marking it not billable, archiving it -- has to drop this cache.
      providesTags: ["Billing"],
    }),

    // GET /api/dashboard
    getDashboard: builder.query<DashboardResponse, void>({
      query: () => "dashboard",
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/dashboard/pipelines/:project?repo=... (lazy per-tab fetch, cached per project+repo)
    getDashboardPipelines: builder.query<ProjectPipelines, { project: string; repo: string }>({
      query: ({ project, repo }) =>
        `dashboard/pipelines/${encodeURIComponent(project)}?repo=${encodeURIComponent(repo)}`,
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/test-history
    getTestHistory: builder.query<TestHistoryResponse, void>({
      query: () => "test-history",
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/stress-status (sprint awareness; read-only, reads stress-log.json)
    getStressStatus: builder.query<StressStatusResponse, string | undefined>({
      query: (repo) => (repo ? `stress-status?repo=${encodeURIComponent(repo)}` : "stress-status"),
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/stress-sprint-activity (sprint velocity grid; reads stress-history.json)
    getSprintActivity: builder.query<SprintActivityResponse, string | undefined>({
      query: (repo) =>
        repo ? `stress-sprint-activity?repo=${encodeURIComponent(repo)}` : "stress-sprint-activity",
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/stress-repos (list of repoPaths keys for the active org, for the dropdown)
    getStressRepos: builder.query<StressReposResponse, void>({
      query: () => "stress-repos",
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/pr-comments
    getPrComments: builder.query<ListResponse, void>({
      query: () => "pr-comments",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["PrComments"],
    }),

    // GET /api/pr-comments/:filename
    getPrCommentDetail: builder.query<DetailResponse, string>({
      query: (filename) => `pr-comments/${encodeURIComponent(filename)}`,
      keepUnusedDataFor: CACHE_TTL,
    }),

    // POST /api/pr-comments/:filename/suggest -- the model drafts a reply; nothing
    // is written. Posting the reply is ReplyPR through the bridge (runCommand),
    // which is the card's one writer. 412 is the agent saying what is missing
    // (no key, no SDK); the page shows that sentence.
    suggestReply: builder.mutation<SuggestResponse, { filename: string; body: SuggestRequest }>({
      query: ({ filename, body }) => ({
        url: `pr-comments/${encodeURIComponent(filename)}/suggest`,
        method: "POST",
        body,
      }),
    }),

    // The connect wizard (settings by workflow, W2): the verb reports the four
    // steps with -AsJson, and each step is the same verb with one switch. A
    // POST is a query here because the report has no side effect; a step is a
    // mutation and invalidates the report, /env and the inventory.
    getConnectState: builder.query<CommandResponse, string>({
      query: (slug) => ({
        url: "cmd/Connect",
        method: "POST",
        body: { params: [slug, "-AsJson"] },
      }),
      providesTags: (_r, _e, slug) => [{ type: "Connect", id: slug }],
    }),
    connectStep: builder.mutation<CommandResponse, { slug: string; params: string[] }>({
      query: ({ slug, params }) => ({
        url: "cmd/Connect",
        method: "POST",
        body: { params: [slug, ...params, "-AsJson"] },
      }),
      invalidatesTags: (_r, _e, { slug }) => [{ type: "Connect", id: slug }, "Env", "Surfaces"],
    }),

    // POST /api/cmd/Archive
    // POST /api/cmd/:name — generic allowlisted command
    runCommand: builder.mutation<CommandResponse, { name: string; params?: string[] }>({
      query: ({ name, params }) => ({
        url: `cmd/${name}`,
        method: "POST",
        body: { params: params ?? [] },
      }),
    }),

    // POST /api/cmd/Archive
    archivePrompt: builder.mutation<CommandResponse, { file: string }>({
      query: ({ file }) => ({
        url: "cmd/Archive",
        method: "POST",
        body: { params: ["-File", file] },
      }),
      // Billing too: archiving stamps the card Closed, and that is a day on Daily.
      invalidatesTags: ["Status", "Billing"],
    }),

    // POST /api/cmd/Land -- the merge recorded, the issue closed, the card
    // archived, by the CLI's Land verb, which asks the tracker whether the pull
    // request merged. A refusal (not merged yet) comes back as the verb's own
    // sentence.
    landCard: builder.mutation<CommandResponse, { file: string }>({
      query: ({ file }) => ({
        url: "cmd/Land",
        method: "POST",
        body: { params: ["-Card", file] },
      }),
      invalidatesTags: ["Status", "Billing"],
    }),

    // POST /api/cmd/Move -- a person's move to a lane, written as a line by the
    // CLI. Dropping a card on the board runs this; the board keeps no copy of
    // the answer, the refetch is what moves the card.
    moveCard: builder.mutation<CommandResponse, { file: string; to: string }>({
      query: (fields) => ({
        url: "cmd/Move",
        method: "POST",
        body: { params: buildMoveParams(fields) },
      }),
      invalidatesTags: ["Status", "Billing"],
    }),

    // POST /api/cmd/Billable -- the one writer of a card's Billable line is the
    // CLI; this is a form over it, like every other write in this file.
    setBillable: builder.mutation<CommandResponse, { file: string; billable: boolean }>({
      query: (fields) => ({
        url: "cmd/Billable",
        method: "POST",
        body: { params: buildBillableParams(fields) },
      }),
      invalidatesTags: ["Status", "Billing"],
    }),

    // POST /api/cmd/NewPrompt
    createPrompt: builder.mutation<CommandResponse, { params: string[] }>({
      query: (body) => ({
        url: "cmd/NewPrompt",
        method: "POST",
        body,
      }),
      invalidatesTags: ["Status"],
    }),

    // POST /api/assets/upload?name= -- the browser's picture into a temp file
    // (C2). The body is the file itself, not JSON; the agent answers the
    // path, and the verb below is what writes into the hub. Nothing to invalidate:
    // the hub has not changed.
    uploadAsset: builder.mutation<UploadResponse, { file: File }>({
      query: ({ file }) => ({
        url: `assets/upload?name=${encodeURIComponent(file.name)}`,
        method: "POST",
        body: file,
        headers: { "Content-Type": file.type || "application/octet-stream" },
      }),
    }),

    // POST /api/cmd/Cover -- the one writer of a card's picture is the CLI's
    // Cover; this is a form over it (buildCoverParams). The board's faces and the
    // list's thumbnails read Status; the card page re-reads itself.
    attachCover: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/Cover", method: "POST", body: { params } }),
      invalidatesTags: ["Status"],
    }),

    // POST /api/cmd/GetPRComments
    fetchPrComments: builder.mutation<
      CommandResponse,
      { pullRequestId?: number; branchName?: string }
    >({
      query: ({ pullRequestId, branchName }) => {
        const params: string[] = [];
        if (pullRequestId) params.push(String(pullRequestId));
        else if (branchName) params.push("-BranchName", branchName);
        return {
          url: "cmd/GetPRComments",
          method: "POST",
          body: { params },
        };
      },
      invalidatesTags: ["Status", "PrComments"],
    }),

    // POST /api/cmd/NewPR
    createPR: builder.mutation<
      CommandResponse,
      {
        workItemId: number;
        targetBranch?: string;
        draft: boolean;
        autoComplete: boolean;
        skipWorkItem: boolean;
      }
    >({
      query: ({ workItemId, targetBranch, draft, autoComplete, skipWorkItem }) => {
        const params: string[] = [String(workItemId)];
        if (targetBranch) params.push("-TargetBranch", targetBranch);
        if (draft) params.push("-Draft");
        if (autoComplete) params.push("-AutoComplete");
        if (skipWorkItem) params.push("-SkipWorkItem");
        return { url: "cmd/NewPR", method: "POST", body: { params } };
      },
      invalidatesTags: ["Status"],
    }),

    // POST /api/cmd/EditItem -- the edit flow, same verb as the CLI
    editWorkItem: builder.mutation<CommandResponse, EditWorkItemFields>({
      query: (fields) => ({
        url: "cmd/EditItem",
        method: "POST",
        body: { params: buildEditWorkItemParams(fields) },
      }),
      // A pin changes what the Board's cards wear, so the cards list
      // refetches too -- only when this edit was a pin or an unpin.
      invalidatesTags: (_result, _error, { id, pinned }) => [
        "Issues",
        { type: "Issue", id },
        ...(pinned === undefined ? [] : (["Status"] as const)),
      ],
    }),

    // POST /api/cmd/NewItem
    // Was POST /api/create-ado-item, a native route that built its own command
    // string. Spec S7.1/S9 retired it as a duplicate of the bridge call; the
    // frontend change is the URL and the param builder.
    createAdoItem: builder.mutation<CommandResponse, NewAdoItemFields>({
      query: (fields) => ({
        url: "cmd/NewItem",
        method: "POST",
        body: { params: buildNewAdoItemParams(fields) },
      }),
      invalidatesTags: ["Issues"],
    }),

    // POST /api/cmd/CloseItem
    // Was POST /api/resolve-bug. Same retirement, same reason. The name stays
    // `resolveBug` because the cards call it that; the command closes every
    // work item type, not only Bugs.
    resolveBug: builder.mutation<CommandResponse, CloseWorkItemFields>({
      query: (fields) => ({
        url: "cmd/CloseItem",
        method: "POST",
        body: { params: buildCloseWorkItemParams(fields) },
      }),
      // Status too: a card linked to the item reads its state from the ledger.
      invalidatesTags: (_result, _error, { workItemId }) => [
        "Status",
        "Issues",
        { type: "Issue", id: workItemId },
      ],
    }),

    // GET /api/config/schema -- what may be set, from `Config -Schema -AsJson`
    // through the bridge. Cached by the agent for the life of its process, so
    // this is one round trip per session rather than one PowerShell start.
    getConfigSchema: builder.query<ConfigSchemaResponse, void>({
      query: () => "config/schema",
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/config -- every resolved setting with its source.
    getConfig: builder.query<ConfigResponse, void>({
      query: () => "config",
      providesTags: ["Config"],
    }),

    // PUT /api/config -- the only write path. The agent runs `Config -Set` in
    // the CLI, so the browser never touches a config file; what comes back is
    // the CommandResponse (refusals included, typed like every bridge call) and
    // the re-read list, which is why this needs no refetch of its own.
    //
    // Env is invalidated because a config change is what /env reports: the
    // identity row, the org list, the feature flags. The agent clears its two
    // 45-second caches on a successful write for the same reason.
    writeConfig: builder.mutation<
      ConfigWriteResponse,
      ConfigEditPayload & { local?: boolean; hub?: boolean }
    >({
      query: (body) => ({ url: "config", method: "PUT", body }),
      // The reply IS the re-read list, so it goes straight into getConfig's
      // cache. Invalidating "Config" instead meant a second trip through the
      // CLI (~2 s), and for those two seconds a saved row showed its OLD value:
      // the draft was gone and the new list had not arrived. A refused write
      // returns the unchanged list, so this is right in both cases.
      async onQueryStarted(_arg, { dispatch, queryFulfilled }) {
        try {
          const { data } = await queryFulfilled;
          if (data?.config) {
            dispatch(adoEndpoints.util.updateQueryData("getConfig", undefined, () => data.config));
          }
        } catch {
          // The request itself failed; the caller's unwrap() reports it and the
          // cached list is still the last true one.
        }
      },
      // A write changes what the inventory says (D-W2): the "How do I" rows and the tips re-read it.
      invalidatesTags: ["Env", "Surfaces"],
    }),

    // GET /api/engagement/:slug/summary
    getEngagementSummary: builder.query<EngagementSummaryResponse, string>({
      query: (slug) => `engagement/${encodeURIComponent(slug)}/summary`,
      keepUnusedDataFor: CACHE_TTL,
    }),

    // GET /api/engagement/:slug/work-breakdown
    getEngagementWorkBreakdown: builder.query<WorkBreakdownResponse, string>({
      query: (slug) => `engagement/${encodeURIComponent(slug)}/work-breakdown`,
      keepUnusedDataFor: CACHE_TTL,
    }),
  }),
});

export const {
  useGetConnectStateQuery,
  useConnectStepMutation,
  useGetStatusQuery,
  useGetPromptDetailQuery,
  useGetPrsQuery,
  useGetWorkItemsQuery,
  useGetIssueReportQuery,
  useGetMilestonesQuery,
  useGetDeploysQuery,
  useGetDesignQuery,
  useGetDesignDocQuery,
  useLazySearchDesignQuery,
  useGetDocsQuery,
  useGetDocQuery,
  useGetIssueDetailQuery,
  useEditWorkItemMutation,
  useGetLogEntriesQuery,
  useGetReviewPreviewQuery,
  useGetReviewDetailQuery,
  useGetBillingQuery,
  useGetDashboardQuery,
  useGetDashboardPipelinesQuery,
  useGetTestHistoryQuery,
  useGetStressStatusQuery,
  useGetSprintActivityQuery,
  useGetStressReposQuery,
  useGetPrCommentsQuery,
  useGetPrCommentDetailQuery,
  useSuggestReplyMutation,
  useRunCommandMutation,
  useLandCardMutation,
  useArchivePromptMutation,
  useSetBillableMutation,
  useMoveCardMutation,
  useCreatePromptMutation,
  useUploadAssetMutation,
  useAttachCoverMutation,
  useFetchPrCommentsMutation,
  useCreatePRMutation,
  useCreateAdoItemMutation,
  useResolveBugMutation,
  useGetEngagementSummaryQuery,
  useGetEngagementWorkBreakdownQuery,
  useGetConfigSchemaQuery,
  useGetConfigQuery,
  useWriteConfigMutation,
} = adoEndpoints;
