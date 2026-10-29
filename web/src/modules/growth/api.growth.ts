import { api, CACHE_TTL } from "../../shell/api";
import type { CommandResponse } from "../ado/api.ado";

// The growth module's half of the API slice.
//
// Injected into the shell's single `api` object rather than standing up a
// second store (ADO spec S8.5): the module owns its endpoints and the tags they
// invalidate, the shell owns `createApi` and /env. A module that is switched
// off never imports this file, so its endpoints, cache entries and tags do not
// exist -- which is also why the tag types are added with `enhanceEndpoints`
// here rather than written into the shell's `tagTypes`.

// -- Types -------------------------------------------------------------------

export type GrowthType = "training" | "presentation" | "goal";
export type GrowthStatus = "new" | "active" | "complete";

export interface GrowthItem {
  filename: string;
  type: GrowthType;
  title: string;
  /** the date string as written in the file, e.g. "<start> to <end>" */
  date: string;
  due_date: string | null;
  status: GrowthStatus;
  provider: string | null;
  hours: string | null;
}

/** Where the quarter stands against the active Space's training requirement. */
export interface TrainingQuarter {
  /** "Q3 2026" */
  quarter: string;
  /** hours of complete trainings dated inside the quarter */
  hours: number;
  required: number;
  daysLeft: number;
  /** hours of trainings dated inside it that are not complete yet */
  planned: number;
}

export interface GrowthResponse {
  items: GrowthItem[];
  /** null, or absent from an older agent, when the Space states no requirement */
  trainingQuarter?: TrainingQuarter | null;
}

export interface GrowthDetailResponse {
  filename: string;
  /** Absolute path on the agent's machine; absent from an older agent. */
  path?: string;
  title: string;
  type: string;
  status: string;
  content: string;
}

export interface ResumeResponse {
  content: string;
  last_modified: string | null;
  /** Absolute path on the agent's machine; absent from an older agent. */
  path?: string;
}

/** One uncommitted file, as the CLI's -Preview reports it. */
export interface PendingFile {
  file: string;
  content: string;
}

export interface ResumePreviewResponse {
  files: PendingFile[];
}

export interface ReviewListItem {
  period: string;
  folder: string;
  start_date: string;
  end_date: string;
  title: string;
}

export interface ReviewsListResponse {
  count: number;
  reviews: ReviewListItem[];
}

export interface ReviewGenerateRequest {
  start_date: string; // YYYY-MM-DD
  end_date: string; // YYYY-MM-DD
  slugs: string[]; // non-empty; every entry must be a known org slug
}

export interface ReviewGenerateResponse {
  review: string;
  file_path: string;
  files_scanned: number;
  files_included: number;
}

export interface EngagementReviewItem {
  period: string;
  generatedDate: string;
  artifactsScanned: number;
  link: string;
  summary: string;
  tags: string[];
  /** member org slugs, sorted ascending; at least one entry */
  spaces: string[];
  /**
   * `<slug-set>/<start>_<end>`, with `archive/` in front for an archived one --
   * the name the `WorkReview` verb takes. "" (or absent, from an older agent)
   * for a legacy review with no slug-set folder: its row offers no move.
   */
  review?: string;
  /** In reviews/archive/ -- read only under the list's Archived filter. */
  archived?: boolean;
}

export type EngagementReviewsResponse = EngagementReviewItem[];

export interface SkillGroups {
  Languages: string[];
  Frameworks: string[];
  Domains: string[];
  Tools: string[];
  A11y: string[];
  Auth: string[];
  Patterns: string[];
}

export interface SkillsSnapshotResponse {
  groups: SkillGroups;
}

// -- Endpoints ---------------------------------------------------------------

// `enhanceEndpoints` is how a module adds its own tag types to a slice it did
// not create. Editing the shell's `tagTypes` to name growth's tags would make
// the shell know about a module it is not supposed to know about.
export const growthApi = api.enhanceEndpoints({ addTagTypes: ["Growth", "Resume", "Reviews"] });

export const growthEndpoints = growthApi.injectEndpoints({
  endpoints: (builder) => ({
    // GET /api/growth
    getGrowth: builder.query<GrowthResponse, void>({
      query: () => "growth",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Growth"],
    }),

    // GET /api/growth/:filename
    getGrowthDetail: builder.query<GrowthDetailResponse, string>({
      query: (filename) => `growth/${encodeURIComponent(filename)}`,
      keepUnusedDataFor: CACHE_TTL,
    }),

    // POST /api/cmd/NewGrowth -- every growth write goes the way every other
    // write in the app goes: the CLI verb runs, in a child pwsh, and this page
    // only asks. A new item is `buildNewGrowthParams`; `-Close <file>` retires
    // one to growth/archive/ and stamps it, `buildGrowthCloseParams`
    // (../ado/cliBridge.ts). There is no native create: the verb is the one
    // writer, so the browser and the terminal write the same file.
    runNewGrowth: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/NewGrowth", method: "POST", body: { params } }),
      invalidatesTags: ["Growth"],
    }),

    // GET /api/resume
    getResume: builder.query<ResumeResponse, void>({
      query: () => "resume",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Resume"],
    }),

    // GET /api/resume-preview -- the uncommitted diff, via the CLI
    getResumePreview: builder.query<ResumePreviewResponse, void>({
      query: () => "resume-preview",
    }),

    // GET /api/reviews
    getReviews: builder.query<ReviewsListResponse, void>({
      query: () => "reviews",
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Reviews"],
    }),

    // POST /api/review/generate
    generateReview: builder.mutation<ReviewGenerateResponse, ReviewGenerateRequest>({
      query: (body) => ({ url: "review/generate", method: "POST", body }),
      invalidatesTags: ["Reviews"],
    }),

    // GET /api/engagement/:slug/reviews -- one engagement's generated reviews.
    // Served by the ADO module's reporting routes over this module's data;
    // the endpoint is declared here because ReviewArchive is the only caller.
    // `archived` is the list's Archived filter: reviews/archive/ and nothing else.
    getEngagementReviews: builder.query<
      EngagementReviewsResponse,
      { slug: string; archived?: boolean }
    >({
      query: ({ slug, archived }) =>
        `engagement/${encodeURIComponent(slug)}/reviews${archived ? "?archived=true" : ""}`,
      keepUnusedDataFor: CACHE_TTL,
      providesTags: ["Reviews"],
    }),

    // POST /api/cmd/WorkReview -- a review's row's Archive and Delete. The verb
    // is the one writer (`buildWorkReviewParams`, ../ado/cliBridge.ts); this only
    // asks, and the list refetches.
    runWorkReview: builder.mutation<CommandResponse, { params: string[] }>({
      query: ({ params }) => ({ url: "cmd/WorkReview", method: "POST", body: { params } }),
      invalidatesTags: ["Reviews"],
    }),

    // GET /api/engagement/:slug/skills -- tag counts over one org's archive.
    // Card data, so the route stays in the ADO module; SkillsSnapshot is this
    // module's component and is its only caller.
    getEngagementSkills: builder.query<SkillsSnapshotResponse, string>({
      query: (slug) => `engagement/${encodeURIComponent(slug)}/skills`,
      keepUnusedDataFor: CACHE_TTL,
    }),
  }),
});

export const {
  useGetGrowthQuery,
  useGetGrowthDetailQuery,
  useRunNewGrowthMutation,
  useGetResumeQuery,
  useGetResumePreviewQuery,
  useGetReviewsQuery,
  useGenerateReviewMutation,
  useGetEngagementReviewsQuery,
  useRunWorkReviewMutation,
  useGetEngagementSkillsQuery,
} = growthEndpoints;
