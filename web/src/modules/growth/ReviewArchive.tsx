import { useState } from "react";
import { useDispatch } from "react-redux";
import { AddRegular, DocumentSearchRegular, InfoRegular } from "@fluentui/react-icons";
import { useNavigate } from "react-router";
import { ROW, defineRowMoves } from "../../shared/CardActions";
import type { CardAction } from "../../shared/CardActions";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import type { EmptyMessage } from "../../shared/EmptyState";
import { buildWorkReviewParams, commandResultMessage } from "../ado/cliBridge";
import { HubSyncLine } from "../ado/HubSyncLine";
import { useGetEnvQuery } from "../../shell/api";
import type { SpaceInfo } from "../../shell/api";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { FilterChip } from "../../shell/kinds/ListPanel";
import type { CardItemData, MetaItem } from "../../shell/CardItem";
// growthApi, not the shell's api: "Resume" is this module's tag and only the
// enhanced slice knows it exists.
import {
  growthApi,
  useGetEngagementReviewsQuery,
  useGetResumeQuery,
  useRunWorkReviewMutation,
} from "./api.growth";
import type { EngagementReviewItem } from "./api.growth";
import { GenerateResumeDialog, GenerateReviewDialog, ResumeInfoDialog } from "./ReviewDialogs";

/** The resume's own moves, on no other record. */
const RESUME_MOVES = defineRowMoves("resume", {
  generate: { word: "Generate resume scaffold", icon: AddRegular },
  howItWorks: { word: "How resume updates work", icon: InfoRegular },
});

type ReviewCollectionItem = EngagementReviewItem & { kind: "review" };
type ResumeCollectionItem = { kind: "resume"; lastModified: string };
type CollectionItem = ReviewCollectionItem | ResumeCollectionItem;

/** What the list shows: everything, one kind, or the reviews put away. An
 *  archived review (reviews/archive/, where WorkReview -Archive moves it) is
 *  read under its own chip and never on any other. */
type TypeFilter = "all" | "review" | "resume" | "archived";
const TYPE_FILTERS: { id: TypeFilter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "review", label: "Reviews" },
  { id: "resume", label: "Resume" },
  { id: "archived", label: "Archived" },
];
const ALL_SPACES = "all";

// A slug is what the file is keyed by; a person reads the board's name --
// "initech" printed raw was a fact about storage on a card meant to read
// as a name.
// Falls back to the slug itself for an org this machine no longer has
// configured, rather than showing nothing.
export function orgDisplayName(slug: string, orgs: SpaceInfo[]): string {
  return orgs.find((o) => o.slug === slug)?.name ?? slug;
}

/**
 * What the Delete confirm names: the range and the Spaces, so the person
 * confirms the review they meant -- the same range can exist for two slug-sets.
 */
export function deleteReviewWhat(period: string, spaceNames: string[]) {
  return (
    <>
      Delete the review of <strong>{period}</strong> for <strong>{spaceNames.join(", ")}</strong>.
      Its folder and every file in it are removed -- it does not go to the archive.
    </>
  );
}

/** A review's summary as plain words: the file's bold marks are not drawn. */
export function plainSummary(text: string): string {
  return text.replace(/\*\*(.+?)\*\*/g, "$1");
}

/** Where a review opens. */
function reviewPath(item: EngagementReviewItem): string {
  const folder = item.link.replace("/reviews/", "");
  return `/review/${encodeURIComponent(folder)}?slugs=${encodeURIComponent(item.spaces.join("+"))}${item.archived ? "&archived=true" : ""}`;
}

// The Reviews panel: every work review, and the resume beside them, each a
// card item whose one exposed action is its page and whose menu holds its
// moves. The chips split the list by what it holds; the Space picker narrows
// the reviews to one Space. A write's refusal is said once, on the panel.
export function ReviewArchive({ activeTag }: { activeTag?: string | null }) {
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const { data: env } = useGetEnvQuery();

  const orgs = env?.config.spaces ?? [];
  const activeSpace = env?.config.activeSpace ?? "";

  const [type, setType] = useState<TypeFilter>("all");
  const [space, setSpace] = useState<string>(ALL_SPACES);
  const isArchived = type === "archived";

  const { data, isLoading, isFetching, isError, refetch } = useGetEngagementReviewsQuery({
    slug: space,
    archived: isArchived,
  });
  const { data: resumeData, isFetching: isResumeFetching } = useGetResumeQuery();
  const [runWorkReview, { isLoading: isRunning }] = useRunWorkReviewMutation();

  // The review a move is running on, the one Delete is asking about, and what
  // a refused move said.
  const [target, setTarget] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<EngagementReviewItem | null>(null);
  const [deleteMessage, setDeleteMessage] = useState<string | null>(null);
  const [refusal, setRefusal] = useState<string | null>(null);
  const [dialog, setDialog] = useState<"review" | "resume" | "resumeInfo" | null>(null);

  const reviews = data ?? [];
  const tagLower = activeTag?.toLowerCase() ?? null;
  const filteredReviews = tagLower
    ? reviews.filter(
        (r) =>
          r.tags.some((t) => t.toLowerCase().includes(tagLower)) ||
          r.summary.toLowerCase().includes(tagLower),
      )
    : reviews;

  // The resume is the engineer's, not a Space's: it shows while no Space is picked.
  const hasResume = !!resumeData?.last_modified;
  const showResume = hasResume && space === ALL_SPACES && (type === "all" || type === "resume");
  const collection: CollectionItem[] = [
    ...(type !== "resume" ? filteredReviews.map((r) => ({ ...r, kind: "review" as const })) : []),
    ...(showResume ? [{ kind: "resume" as const, lastModified: resumeData!.last_modified! }] : []),
  ];

  // WorkReview through the bridge: the verb is the one writer, this only asks.
  // A success refetches the list (the mutation invalidates Reviews), so the row
  // simply leaves it; a refusal is said in the verb's own words.
  const runMove = async (
    item: EngagementReviewItem,
    move: "archive" | "delete",
  ): Promise<string | null> => {
    setTarget(item.link);
    try {
      const result = await runWorkReview({
        params: buildWorkReviewParams(item.review!, move),
      }).unwrap();
      return result.status === "success"
        ? null
        : commandResultMessage(result, move === "archive" ? "Archived." : "Deleted.");
    } catch {
      return "Could not reach the agent. Nothing was changed.";
    } finally {
      setTarget(null);
    }
  };

  const orgLabel = (slug: string) => orgDisplayName(slug, orgs);

  const reviewItem = (item: EngagementReviewItem): CardItemData => {
    // A legacy review (no slug-set folder) has no name the verb takes: no moves.
    const menu: CardAction[] = [];
    if (item.review) {
      if (!item.archived) {
        menu.push(
          ROW.archive.action({
            onClick: async () => {
              setRefusal(null);
              setRefusal(await runMove(item, "archive"));
            },
          }),
        );
      }
      menu.push(
        ROW.delete.action({
          detail: "the review",
          onClick: () => {
            setDeleteMessage(null);
            setDeleting(item);
          },
        }),
      );
    }
    const meta: MetaItem[] = [
      { badge: { label: "Review", color: "brand", appearance: "outline" } },
      ...item.spaces.map((slug) => ({
        badge: { label: orgLabel(slug), color: "informative" as const, title: slug },
      })),
      // The title is the reviewed RANGE; this is the day the review itself was
      // written -- often the day the range ends, so the word says which it is.
      { text: `Generated ${item.generatedDate}` },
    ];
    if (item.artifactsScanned > 0) meta.push({ text: `${item.artifactsScanned} artifacts` });
    return {
      id: item.link,
      title: item.period,
      name: `the review of ${item.period}`,
      badges: item.archived ? [{ label: "Archived", color: "subtle" }] : undefined,
      description: item.summary ? plainSummary(item.summary) : undefined,
      meta,
      primary: ROW.open.action({
        detail: "the review",
        onClick: () => navigate(reviewPath(item)),
      }),
      menu,
      busy: isRunning && target === item.link,
    };
  };

  const resumeItem = (lastModified: string): CardItemData => ({
    id: "resume",
    title: "Resume",
    name: "the resume",
    description: "Your skills page: one file in your hub, resume/resume.md.",
    meta: [
      { badge: { label: "Resume", color: "brand", appearance: "outline" } },
      { text: `Updated ${lastModified}` },
    ],
    primary: ROW.open.action({ detail: "the resume", onClick: () => navigate("/skills") }),
    menu: [
      RESUME_MOVES.generate.action({ onClick: () => setDialog("resume") }),
      RESUME_MOVES.howItWorks.action({ onClick: () => setDialog("resumeInfo") }),
    ],
  });

  const chips: FilterChip[] = TYPE_FILTERS.map((f) => ({
    id: f.id,
    label: f.label,
    active: type === f.id,
    onSelect: () => setType(f.id),
  }));

  const icon = <DocumentSearchRegular />;
  const empty: EmptyMessage = isError
    ? {
        icon,
        tone: "error",
        title: "Could not load your reviews",
        detail: "The agent did not answer. Nothing was read.",
      }
    : activeTag
      ? { icon, tone: "filtered", title: `No reviews matching "${activeTag}"` }
      : isArchived
        ? {
            icon,
            title: "No archived reviews",
            detail: "A review's Archive moves it here, out of the default list.",
          }
        : type === "resume"
          ? {
              icon,
              title: "No skills page yet",
              detail: "It is one file in your hub, resume/resume.md.",
            }
          : {
              icon,
              title: "No reviews yet",
              detail: "A review is written from a period's cards. The + below makes one.",
            };

  const isFiltered = activeTag != null || type !== "all" || space !== ALL_SPACES;
  const totalCount = reviews.length + (hasResume ? 1 : 0);

  return (
    <>
      <ListPanel
        title="Reviews"
        info="A review is a period's work, written up from its cards. An agent writes the full one: run /generate-review with a date range in your agent's chat. The + below makes a scaffold from git instead. Both land in your hub under reviews/, by Space and range."
        infoLabel="How reviews work"
        items={collection}
        item={(entry) =>
          entry.kind === "resume" ? resumeItem(entry.lastModified) : reviewItem(entry)
        }
        loading={isLoading ? { label: "Loading reviews..." } : undefined}
        empty={empty}
        filters={[{ label: "Filter reviews", chips }]}
        pickers={
          orgs.length > 0
            ? [
                {
                  label: "Space",
                  value: space,
                  options: [
                    { value: ALL_SPACES, label: "All Spaces" },
                    ...orgs.map((o) => ({ value: o.slug, label: o.name })),
                  ],
                  onChange: setSpace,
                },
              ]
            : undefined
        }
        refresh={{
          onClick: () => {
            refetch();
            dispatch(growthApi.util.invalidateTags(["Resume"]));
          },
          isFetching: isFetching || isResumeFetching,
        }}
        count={isFiltered ? `${collection.length} / ${totalCount}` : totalCount}
        status={
          refusal ? { tone: "error", text: refusal, onDismiss: () => setRefusal(null) } : undefined
        }
        create={{ label: "Generate Review", onClick: () => setDialog("review") }}
        footNote={<HubSyncLine />}
      />

      <ConfirmDialog
        open={deleting !== null}
        what={deleting ? deleteReviewWhat(deleting.period, deleting.spaces.map(orgLabel)) : null}
        busy={isRunning}
        message={deleteMessage}
        onCancel={() => {
          setDeleteMessage(null);
          setDeleting(null);
        }}
        onConfirm={async () => {
          if (!deleting) return;
          const refused = await runMove(deleting, "delete");
          if (refused) setDeleteMessage(refused);
          else setDeleting(null);
        }}
      />
      {dialog === "review" && (
        <GenerateReviewDialog
          orgs={orgs}
          activeSpace={activeSpace}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog === "resume" && (
        <GenerateResumeDialog activeSpace={activeSpace} onClose={() => setDialog(null)} />
      )}
      {dialog === "resumeInfo" && <ResumeInfoDialog onClose={() => setDialog(null)} />}
    </>
  );
}
