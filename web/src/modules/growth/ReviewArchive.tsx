import { useState } from "react";
import { useDispatch } from "react-redux";
import {
  Card,
  Subtitle2,
  Body1,
  Body1Strong,
  Caption1,
  Badge,
  Button,
  Checkbox,
  Dropdown,
  Option,
  OptionGroup,
  Input,
  Spinner,
  Dialog,
  DialogSurface,
  DialogBody,
  DialogTitle,
  DialogContent,
  DialogActions,
  DialogTrigger,
  Field,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { AddRegular, DocumentSearchRegular, InfoRegular } from "@fluentui/react-icons";
import { useNavigate } from "react-router";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { CardActions, ROW, defineRowMoves } from "../../shared/CardActions";
import type { CardAction } from "../../shared/CardActions";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import { buildWorkReviewParams, commandResultMessage } from "../ado/cliBridge";
import { RefreshButton } from "../../shared/RefreshButton";
import { PageCard } from "../../shared/PageCard";
import { CreateButton } from "../../shared/CreateButton";
import { Pagination } from "../../shared/Pagination";
import { usePagination } from "../../hooks/usePagination";
import { useGetEnvQuery } from "../../shell/api";
import type { SpaceInfo } from "../../shell/api";
// growthApi, not the shell's api: "Resume" is this module's tag and only the
// enhanced slice knows it exists.
import {
  growthApi,
  useGetEngagementReviewsQuery,
  useGenerateReviewMutation,
  useGetResumeQuery,
  useRunWorkReviewMutation,
} from "./api.growth";
import type { EngagementReviewItem } from "./api.growth";
import { EmptyState } from "../../shared/EmptyState";
import { localToday, previousMonth } from "../../utility/dates";

const PAGE_SIZE = 4;

/** The resume's own moves, on no other record. */
const RESUME_MOVES = defineRowMoves("resume", {
  generate: { word: "Generate resume scaffold", icon: AddRegular },
  howItWorks: { word: "How resume updates work", icon: InfoRegular },
});

function prevMonthStart(): string {
  return previousMonth().start;
}

function prevMonthEnd(): string {
  return previousMonth().end;
}

function today(): string {
  return localToday();
}

type ReviewCollectionItem = EngagementReviewItem & { kind: "review" };
type ResumeCollectionItem = { kind: "resume"; lastModified: string };
type CollectionItem = ReviewCollectionItem | ResumeCollectionItem;

const useStyles = makeStyles({
  reviewCard: {
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
  },
  reviewHeader: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalS,
  },
  reviewTitle: {
    flex: 1,
    minWidth: 0,
  },
  metaRow: {
    display: "flex",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
    marginTop: tokens.spacingVerticalXS,
  },
  summary: {
    display: "block",
    marginTop: tokens.spacingVerticalXS,
    color: tokens.colorNeutralForeground2,
  },
  markdownBody: {
    lineHeight: "1.6",
    "& h3": {
      fontSize: tokens.fontSizeBase300,
      fontWeight: tokens.fontWeightSemibold,
      marginTop: tokens.spacingVerticalM,
      marginBottom: tokens.spacingVerticalXS,
    },
    "& p": { marginTop: 0, marginBottom: tokens.spacingVerticalS },
    "& ul": { paddingLeft: "1.5rem", marginBottom: tokens.spacingVerticalS },
    "& li": { marginBottom: tokens.spacingVerticalXS },
    "& strong": { fontWeight: tokens.fontWeightSemibold },
    "& code": {
      fontFamily: tokens.fontFamilyMonospace,
      fontSize: tokens.fontSizeBase200,
      backgroundColor: tokens.colorNeutralBackground3,
      padding: "1px 4px",
      borderRadius: tokens.borderRadiusSmall,
    },
  },
  dialogFields: {
    display: "flex",
    flexDirection: "column" as const,
    gap: tokens.spacingVerticalM,
    paddingTop: tokens.spacingVerticalS,
  },
  dateRow: {
    display: "flex",
    gap: tokens.spacingHorizontalM,
    alignItems: "flex-end",
  },
  successBox: {
    display: "flex",
    flexDirection: "column" as const,
    gap: tokens.spacingVerticalXS,
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackground3,
    borderRadius: tokens.borderRadiusMedium,
  },
});

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

function ReviewCard({ item, orgs }: { item: EngagementReviewItem; orgs: SpaceInfo[] }) {
  const styles = useStyles();
  const navigate = useNavigate();
  const folder = item.link.replace("/reviews/", "");
  const orgLabel = (slug: string) => orgDisplayName(slug, orgs);
  const [runWorkReview, { isLoading: isRunning }] = useRunWorkReviewMutation();
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteMessage, setDeleteMessage] = useState<string | null>(null);
  const [archiveMessage, setArchiveMessage] = useState<string | null>(null);

  // WorkReview through the bridge: the verb is the one writer, this only asks.
  // A success refetches the list (the mutation invalidates Reviews), so the row
  // simply leaves it; a refusal is said in the verb's own words.
  const runMove = async (move: "archive" | "delete"): Promise<string | null> => {
    try {
      const result = await runWorkReview({
        params: buildWorkReviewParams(item.review!, move),
      }).unwrap();
      return result.status === "success"
        ? null
        : commandResultMessage(result, move === "archive" ? "Archived." : "Deleted.");
    } catch {
      return "Could not reach the agent. Nothing was changed.";
    }
  };

  // A legacy review (no slug-set folder) has no name the verb takes: no moves.
  const moves: CardAction[] = [];
  if (item.review) {
    if (!item.archived) {
      moves.push(
        ROW.archive.action({
          onClick: async () => {
            setArchiveMessage(null);
            setArchiveMessage(await runMove("archive"));
          },
        }),
      );
    }
    moves.push(
      ROW.delete.action({
        detail: "the review",
        onClick: () => {
          setDeleteMessage(null);
          setConfirmDelete(true);
        },
      }),
    );
  }

  const renderSummary = (text: string) => {
    const parts = text.split(/\*\*(.+?)\*\*/g);
    return parts.map((part, i) =>
      i % 2 === 1 ? <Body1Strong key={i}>{part}</Body1Strong> : <Caption1 key={i}>{part}</Caption1>,
    );
  };

  return (
    <Card className={styles.reviewCard} size="small" appearance="outline">
      <div className={styles.reviewHeader}>
        <div className={styles.reviewTitle}>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: tokens.spacingHorizontalS,
            }}
          >
            <Badge color="brand" appearance="outline" size="small">
              Review
            </Badge>
            {item.archived && (
              <Badge color="subtle" appearance="outline" size="small">
                Archived
              </Badge>
            )}
            {item.spaces.map((org) => (
              <Badge key={org} color="informative" appearance="tint" size="small" title={org}>
                {orgLabel(org)}
              </Badge>
            ))}
            <Body1>
              <strong>{item.period}</strong>
            </Body1>
          </div>
          <div className={styles.metaRow}>
            {/* item.period is the reviewed RANGE; this is the day the review
                itself was written -- often the same day the range ends, which
                read as the same date twice with no word saying they differ. */}
            <Caption1>Generated {item.generatedDate}</Caption1>
          </div>
          {item.summary && (
            <Caption1 className={styles.summary}>{renderSummary(item.summary)}</Caption1>
          )}
          {item.artifactsScanned > 0 && (
            <div className={styles.metaRow}>
              <Caption1>{item.artifactsScanned} artifacts</Caption1>
            </div>
          )}
          {archiveMessage && (
            <Caption1
              role="alert"
              style={{
                display: "block",
                marginTop: tokens.spacingVerticalXS,
                color: tokens.colorPaletteRedForeground1,
                whiteSpace: "pre-wrap",
              }}
            >
              {archiveMessage}
            </Caption1>
          )}
        </div>
        <CardActions
          primaryAction={ROW.open.action({
            detail: "the review",
            onClick: () =>
              navigate(
                `/review/${encodeURIComponent(folder)}?slugs=${encodeURIComponent(item.spaces.join("+"))}${item.archived ? "&archived=true" : ""}`,
              ),
          })}
          secondaryActions={moves}
          menuLabel={`Actions for the review of ${item.period}`}
          busy={isRunning}
        />
      </div>
      <ConfirmDialog
        open={confirmDelete}
        what={deleteReviewWhat(item.period, item.spaces.map(orgLabel))}
        busy={isRunning}
        message={deleteMessage}
        onCancel={() => {
          setDeleteMessage(null);
          setConfirmDelete(false);
        }}
        onConfirm={async () => {
          const refused = await runMove("delete");
          if (refused) setDeleteMessage(refused);
          else setConfirmDelete(false);
        }}
      />
    </Card>
  );
}

function ResumeItemCard({ lastModified }: { lastModified: string }) {
  const styles = useStyles();
  const navigate = useNavigate();
  const { data: env } = useGetEnvQuery();
  const activeSlug = env?.config?.activeSpace ?? "";
  const [generateResume, { isLoading: isGenerating }] = useGenerateReviewMutation();

  const [infoOpen, setInfoOpen] = useState(false);
  const [generateOpen, setGenerateOpen] = useState(false);
  const [startDate, setStartDate] = useState(prevMonthStart);
  const [endDate, setEndDate] = useState(prevMonthEnd);
  const [generateError, setGenerateError] = useState<string | null>(null);
  const [generateMeta, setGenerateMeta] = useState<{
    filePath: string;
    filesIncluded: number;
  } | null>(null);

  const resetGenerate = () => {
    setStartDate(prevMonthStart());
    setEndDate(prevMonthEnd());
    setGenerateError(null);
    setGenerateMeta(null);
  };

  const handleGenerate = async () => {
    setGenerateError(null);
    setGenerateMeta(null);
    try {
      const data = await generateResume({
        start_date: startDate,
        end_date: endDate,
        slugs: activeSlug ? [activeSlug] : [],
      }).unwrap();
      setGenerateMeta({ filePath: data.file_path, filesIncluded: data.files_included });
    } catch (e) {
      const err = e as { data?: { detail?: string }; error?: string };
      setGenerateError(err.data?.detail ?? err.error ?? "Generation failed");
    }
  };

  return (
    <>
      <Card className={styles.reviewCard} size="small" appearance="outline">
        <div className={styles.reviewHeader}>
          <div className={styles.reviewTitle}>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: tokens.spacingHorizontalS,
              }}
            >
              <Badge color="brand" appearance="outline" size="small">
                Resume
              </Badge>
              <Body1>
                <strong>Updated {lastModified}</strong>
              </Body1>
            </div>
          </div>
          {/* The house row: the title is text, Open the resume the one
              exposed action, the rest in the menu. The scaffold and the
              how-to used to sit as two bare icons inside the title. */}
          <CardActions
            primaryAction={ROW.open.action({
              detail: "the resume",
              onClick: () => navigate("/skills"),
            })}
            menuLabel="Actions for the resume"
            secondaryActions={[
              RESUME_MOVES.generate.action({ onClick: () => setGenerateOpen(true) }),
              RESUME_MOVES.howItWorks.action({ onClick: () => setInfoOpen(true) }),
            ]}
          />
        </div>
      </Card>

      <Dialog open={infoOpen} onOpenChange={(_e, d) => setInfoOpen(d.open)}>
        <DialogSurface>
          <DialogBody>
            <DialogTitle action={<DialogDismiss />}>Updating Your Resume</DialogTitle>
            <DialogContent>
              <div className={styles.markdownBody}>
                <p>
                  Resume updates use an <strong>agentic workflow</strong> in Copilot Chat. The agent
                  scans your work artifacts, reads review reports, and patches{" "}
                  <code>resume/resume.md</code> with new accomplishments.
                </p>
                <h3>Slash command (recommended)</h3>
                <p>In Copilot Chat, type:</p>
                <code>/update-resume since January 2026</code>
                <p style={{ marginTop: tokens.spacingVerticalS }}>
                  The agent will scan <code>archive/</code>, <code>spec/</code>,{" "}
                  <code>reviews/</code>, and <code>growth/</code> for work in that date range, then
                  update the <strong>Recent Work</strong> section of your resume.
                </p>
                <h3>Workflow</h3>
                <ol>
                  <li>
                    Use <strong>Generate scaffold</strong> (via the overflow menu on the resume
                    card) to scaffold what artifacts exist for a date range
                  </li>
                  <li>
                    Run <code>/update-resume</code> in Copilot Chat — the agent reads the scaffold +
                    existing resume and writes updates
                  </li>
                  <li>Review changes, then commit via the Review page</li>
                </ol>
                <h3>Output</h3>
                <p>
                  Changes are written directly to <code>resume/resume.md</code> and appear in the
                  Resume viewer.
                </p>
              </div>
            </DialogContent>
            <DialogActions>
              <DialogTrigger disableButtonEnhancement>
                <Button appearance="secondary">Close</Button>
              </DialogTrigger>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>

      <Dialog
        open={generateOpen}
        onOpenChange={(_e, d) => {
          setGenerateOpen(d.open);
          if (!d.open) resetGenerate();
        }}
      >
        <DialogSurface>
          <DialogBody>
            <DialogTitle action={<DialogDismiss />}>Generate Resume Scaffold</DialogTitle>
            <DialogContent>
              <div className={styles.dialogFields}>
                <div className={styles.dateRow}>
                  <Field label="Start date">
                    <Input
                      type="date"
                      size="small"
                      value={startDate}
                      max={endDate}
                      onChange={(_, d) => setStartDate(d.value)}
                      style={{ width: "145px" }}
                    />
                  </Field>
                  <Field label="End date">
                    <Input
                      type="date"
                      size="small"
                      value={endDate}
                      min={startDate}
                      max={today()}
                      onChange={(_, d) => setEndDate(d.value)}
                      style={{ width: "145px" }}
                    />
                  </Field>
                </div>
                {generateError && (
                  <Body1 style={{ color: tokens.colorPaletteRedForeground1 }}>
                    {generateError}
                  </Body1>
                )}
                {generateMeta && (
                  <div className={styles.successBox}>
                    <Body1>
                      <strong>{generateMeta.filesIncluded}</strong> artifacts found
                    </Body1>
                    <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
                      {generateMeta.filePath}
                    </Caption1>
                    <Caption1 style={{ marginTop: tokens.spacingVerticalXS }}>
                      Now run{" "}
                      <code style={{ fontFamily: tokens.fontFamilyMonospace }}>/update-resume</code>{" "}
                      in Copilot Chat.
                    </Caption1>
                  </div>
                )}
              </div>
            </DialogContent>
            <DialogActions>
              <DialogTrigger disableButtonEnhancement>
                <Button appearance="secondary" disabled={isGenerating}>
                  {generateMeta ? "Done" : "Cancel"}
                </Button>
              </DialogTrigger>
              {!generateMeta && (
                <Button
                  icon={
                    isGenerating ? (
                      <Spinner size="tiny" aria-label="Generating..." />
                    ) : (
                      <DocumentSearchRegular />
                    )
                  }
                  appearance="primary"
                  disabled={isGenerating || !startDate || !endDate}
                  onClick={handleGenerate}
                >
                  {isGenerating ? "Generating…" : "Generate"}
                </Button>
              )}
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>
    </>
  );
}

export function ReviewArchive({ activeTag }: { activeTag?: string | null }) {
  const styles = useStyles();
  const dispatch = useDispatch();
  const { data: env } = useGetEnvQuery();

  const orgs = env?.config.spaces ?? [];
  const activeSpace = env?.config.activeSpace ?? "";

  // filter is one of: "all" | "review" | "resume" | "archived" | <org slug>.
  // "archived" is its own value, the way a card list's archive is: an archived
  // review (reviews/archive/, where WorkReview -Archive moves it) is read under
  // it and never on any other -- the default list leaves it out.
  const [filter, setFilter] = useState<string>("all");

  const isArchivedFilter = filter === "archived";
  const isOrgFilter =
    filter !== "all" && filter !== "review" && filter !== "resume" && !isArchivedFilter;
  const orgQueryArg = isOrgFilter ? filter : "all";

  const { data, isLoading, isFetching, isError, refetch } = useGetEngagementReviewsQuery({
    slug: orgQueryArg,
    archived: isArchivedFilter,
  });
  const { data: resumeData, isFetching: isResumeFetching } = useGetResumeQuery();
  const [generateReview, { isLoading: isGenerating }] = useGenerateReviewMutation();

  const reviews = data ?? [];
  const tagLower = activeTag?.toLowerCase() ?? null;

  const filteredReviews = tagLower
    ? reviews.filter(
        (r) =>
          r.tags.some((t) => t.toLowerCase().includes(tagLower)) ||
          r.summary.toLowerCase().includes(tagLower),
      )
    : reviews;

  const reviewItems: ReviewCollectionItem[] = filteredReviews.map((r) => ({
    ...r,
    kind: "review" as const,
  }));

  const hasResume = !!resumeData?.last_modified;
  const showResume = hasResume && (filter === "all" || filter === "resume");
  const showReviews = filter !== "resume";

  const collection: CollectionItem[] = [
    ...(showReviews ? reviewItems : []),
    ...(showResume ? [{ kind: "resume" as const, lastModified: resumeData!.last_modified! }] : []),
  ];

  const { page, totalPages, pageItems, setPage } = usePagination(collection, PAGE_SIZE);

  const [infoOpen, setInfoOpen] = useState(false);
  const [generateOpen, setGenerateOpen] = useState(false);
  const [startDate, setStartDate] = useState(prevMonthStart);
  const [endDate, setEndDate] = useState(prevMonthEnd);
  const [generateError, setGenerateError] = useState<string | null>(null);
  const [selectedSlugs, setSelectedSlugs] = useState<Set<string>>(new Set());

  const resetGenerate = () => {
    setStartDate(prevMonthStart());
    setEndDate(prevMonthEnd());
    setGenerateError(null);
    setSelectedSlugs(activeSpace ? new Set([activeSpace]) : new Set());
  };

  const toggleSlug = (s: string, checked: boolean) => {
    setSelectedSlugs((prev) => {
      const next = new Set(prev);
      if (checked) next.add(s);
      else next.delete(s);
      return next;
    });
  };

  const handleGenerate = async () => {
    setGenerateError(null);
    try {
      await generateReview({
        start_date: startDate,
        end_date: endDate,
        slugs: Array.from(selectedSlugs),
      }).unwrap();
      setGenerateOpen(false);
      resetGenerate();
    } catch (e) {
      const err = e as { data?: { detail?: string }; error?: string };
      setGenerateError(err.data?.detail ?? err.error ?? "Generation failed");
    }
  };

  const handleFilterChange = (value: string) => {
    setFilter(value);
    setPage(0);
  };

  const filterLabel =
    filter === "all"
      ? "All"
      : filter === "review"
        ? "Reviews"
        : filter === "resume"
          ? "Resume"
          : isArchivedFilter
            ? "Archived"
            : (orgs.find((o) => o.slug === filter)?.name ?? filter);

  const isFiltered = activeTag != null || filter !== "all";
  const totalCount = reviews.length + (hasResume ? 1 : 0);
  const filteredCount = collection.length;

  return (
    <>
      <PageCard
        scrollable
        loading={isLoading}
        loadingLabel="Loading reviews..."
        headerLeft={
          <>
            <Subtitle2>Reviews</Subtitle2>
            <Button
              icon={<InfoRegular />}
              size="small"
              appearance="subtle"
              title="How reviews work"
              onClick={() => setInfoOpen(true)}
            />
          </>
        }
        headerRight={
          <>
            <Dropdown
              size="small"
              aria-label="Space or type"
              value={filterLabel}
              selectedOptions={[filter]}
              onOptionSelect={(_e, d) => handleFilterChange(d.optionValue as string)}
              style={{ minWidth: "110px" }}
            >
              <Option value="all" text="All">
                All
              </Option>
              {orgs.length > 0 && (
                <OptionGroup label="Space">
                  {orgs.map((o) => (
                    <Option key={o.slug} value={o.slug} text={o.name}>
                      {o.name}
                    </Option>
                  ))}
                </OptionGroup>
              )}
              <OptionGroup label="Type">
                <Option value="review" text="Reviews">
                  Reviews
                </Option>
                <Option value="resume" text="Resume">
                  Resume
                </Option>
                <Option value="archived" text="Archived">
                  Archived
                </Option>
              </OptionGroup>
            </Dropdown>
            <RefreshButton
              onClick={() => {
                refetch();
                dispatch(growthApi.util.invalidateTags(["Resume"]));
              }}
              isFetching={isFetching || isResumeFetching}
            />
            <Badge color="informative" appearance="filled" size="large">
              {isFiltered ? `${filteredCount} / ${totalCount}` : totalCount}
            </Badge>
          </>
        }
        footerCenter={
          totalPages > 1 ? (
            <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
          ) : undefined
        }
        footerRight={
          <CreateButton
            label="Generate Review"
            onClick={() => {
              setSelectedSlugs(activeSpace ? new Set([activeSpace]) : new Set());
              setGenerateOpen(true);
            }}
          />
        }
      >
        {collection.length === 0 ? (
          isError ? (
            <EmptyState
              icon={<DocumentSearchRegular />}
              tone="error"
              title="Could not load your reviews"
              detail="The agent did not answer. Nothing was read."
            />
          ) : activeTag ? (
            <EmptyState
              icon={<DocumentSearchRegular />}
              tone="filtered"
              title={`No reviews matching "${activeTag}"`}
            />
          ) : isArchivedFilter ? (
            <EmptyState
              icon={<DocumentSearchRegular />}
              title="No archived reviews"
              detail="A review's Archive moves it here, out of the default list."
            />
          ) : filter === "resume" ? (
            <EmptyState
              icon={<DocumentSearchRegular />}
              title="No skills page yet"
              detail="It is one file in your hub, resume/resume.md."
            />
          ) : (
            <EmptyState
              icon={<DocumentSearchRegular />}
              title="No reviews yet"
              detail="A review is written from a period's cards. The + below makes one."
            />
          )
        ) : (
          pageItems.map((item) =>
            item.kind === "resume" ? (
              <ResumeItemCard key="resume" lastModified={item.lastModified} />
            ) : (
              <ReviewCard key={item.link} item={item} orgs={orgs} />
            ),
          )
        )}
      </PageCard>

      <Dialog open={infoOpen} onOpenChange={(_e, d) => setInfoOpen(d.open)}>
        <DialogSurface>
          <DialogBody>
            <DialogTitle action={<DialogDismiss />}>Generating Reviews</DialogTitle>
            <DialogContent>
              <div className={styles.markdownBody}>
                <p>
                  Reviews are generated with an <strong>agentic workflow</strong> in Copilot Chat.
                  The agent scans your git history, reads archived prompts, and writes a structured
                  review report.
                </p>
                <h3>Slash command (recommended)</h3>
                <p>In Copilot Chat, type:</p>
                <code>/generate-review Jan 1 through April 18</code>
                <p style={{ marginTop: tokens.spacingVerticalS }}>
                  The agent will scan <code>archive/</code>, <code>current/</code>,{" "}
                  <code>spec/</code>, and <code>growth/</code> for work items in that date range,
                  then produce two files:
                </p>
                <ul>
                  <li>
                    <strong>summary.md</strong> &mdash; detailed personal reference with full task
                    inventory
                  </li>
                  <li>
                    <strong>review.md</strong> &mdash; impact-oriented shareable report (1&ndash;2
                    pages)
                  </li>
                </ul>
                <h3>Quick scaffold</h3>
                <p>
                  The <strong>Generate</strong> button (+ below) creates a data scaffold from git
                  stats &mdash; useful as a starting point, but the slash command produces the full
                  prose review.
                </p>
                <h3>Output</h3>
                <p>
                  Files are saved to{" "}
                  <code>reviews/&lt;slugs&gt;/&lt;YYYY&gt;/&lt;START&gt;_&lt;END&gt;/</code> and
                  appear here once committed.
                </p>
              </div>
            </DialogContent>
            <DialogActions>
              <DialogTrigger disableButtonEnhancement>
                <Button appearance="secondary">Close</Button>
              </DialogTrigger>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>

      <Dialog
        open={generateOpen}
        onOpenChange={(_e, d) => {
          setGenerateOpen(d.open);
          if (!d.open) resetGenerate();
        }}
      >
        <DialogSurface>
          <DialogBody>
            <DialogTitle action={<DialogDismiss />}>Generate Review</DialogTitle>
            <DialogContent>
              <div className={styles.dialogFields}>
                <div className={styles.dateRow}>
                  <Field label="Start date">
                    <Input
                      type="date"
                      size="small"
                      value={startDate}
                      max={endDate}
                      onChange={(_, d) => setStartDate(d.value)}
                      style={{ width: "145px" }}
                    />
                  </Field>
                  <Field label="End date">
                    <Input
                      type="date"
                      size="small"
                      value={endDate}
                      min={startDate}
                      max={today()}
                      onChange={(_, d) => setEndDate(d.value)}
                      style={{ width: "145px" }}
                    />
                  </Field>
                </div>
                {orgs.length > 0 && (
                  <Field label="Spaces" hint="Select one or more spaces to include in this review.">
                    <div
                      style={{
                        display: "flex",
                        flexDirection: "column",
                        gap: tokens.spacingVerticalXS,
                      }}
                    >
                      {orgs.map((o) => (
                        <Checkbox
                          key={o.slug}
                          label={<Caption1>{o.name}</Caption1>}
                          checked={selectedSlugs.has(o.slug)}
                          onChange={(_e, data) => toggleSlug(o.slug, !!data.checked)}
                          disabled={isGenerating}
                        />
                      ))}
                    </div>
                  </Field>
                )}
                {generateError && (
                  <Body1 style={{ color: tokens.colorPaletteRedForeground1 }}>
                    {generateError}
                  </Body1>
                )}
              </div>
            </DialogContent>
            <DialogActions>
              <DialogTrigger disableButtonEnhancement>
                <Button appearance="secondary" disabled={isGenerating}>
                  Cancel
                </Button>
              </DialogTrigger>
              <Button
                icon={
                  isGenerating ? (
                    <Spinner size="tiny" aria-label="Generating..." />
                  ) : (
                    <DocumentSearchRegular />
                  )
                }
                appearance="primary"
                disabled={isGenerating || !startDate || !endDate || selectedSlugs.size === 0}
                onClick={handleGenerate}
              >
                {isGenerating ? "Generating…" : "Generate"}
              </Button>
            </DialogActions>
          </DialogBody>
        </DialogSurface>
      </Dialog>
    </>
  );
}
