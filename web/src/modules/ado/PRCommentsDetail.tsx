import { useState } from "react";
import { useParams, useNavigate } from "react-router";
import ReactMarkdown from "react-markdown";
import { markdownPlugins } from "../../shared/markdownPlugins";
import {
  Card,
  Title2,
  Title3,
  Body1,
  Body2,
  Caption1,
  Badge,
  Button,
  Spinner,
  Tooltip,
  Textarea,
  Dropdown,
  Option,
  Field,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { HairlineDivider } from "../../shared/HairlineDivider";
import { timeAgo, formatDate } from "../../utility/dates";
import { RefreshButton } from "../../shared/RefreshButton";
import {
  ArrowLeftRegular,
  CheckmarkCircleRegular,
  CircleRegular,
  BotRegular,
  PersonRegular,
  CheckmarkRegular,
  SparkleRegular,
  SendRegular,
} from "@fluentui/react-icons";

import {
  useGetPrCommentDetailQuery,
  useRunCommandMutation,
  useSuggestReplyMutation,
} from "./api.ado";
import type { PRCommentItem } from "./api.ado";
import { useGetEnvQuery } from "../../shell/api";
import { logWebError } from "./logError";
import { TOKENS } from "../../shell/consts";

// ── Styles ────────────────────────────────────────────────────────────────────

const useStyles = makeStyles({
  page: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalL,
  },
  topBar: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
  },
  titleArea: {
    flex: 1,
    minWidth: 0,
  },
  progressRow: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    marginTop: tokens.spacingVerticalXS,
    flexWrap: "wrap" as const,
  },
  commentCard: {
    padding: `${tokens.spacingVerticalM} ${tokens.spacingHorizontalM}`,
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    position: "relative" as const,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
  },
  commentHeader: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
  },
  commentHeaderLeft: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap" as const,
  },
  statusIndicator: {
    position: "absolute" as const,
    top: tokens.spacingVerticalS,
    right: tokens.spacingHorizontalM,
    display: "flex",
    alignItems: "center",
    gap: "4px",
  },
  metaRow: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap" as const,
    alignItems: "center",
  },
  mdContent: {
    backgroundColor: tokens.colorNeutralBackground2,
    borderRadius: tokens.borderRadiusMedium,
    padding: `${tokens.spacingVerticalS} ${tokens.spacingHorizontalM}`,
    fontSize: tokens.fontSizeBase300,
    lineHeight: tokens.lineHeightBase300,
    overflowX: "auto" as const,
    "& pre": { margin: 0, overflowX: "auto" },
    "& code": {
      fontFamily: tokens.fontFamilyMonospace,
      fontSize: tokens.fontSizeBase200,
    },
  },
  codeBlock: {
    backgroundColor: tokens.colorNeutralBackground3,
    borderRadius: tokens.borderRadiusMedium,
    padding: `${tokens.spacingVerticalS} ${tokens.spacingHorizontalM}`,
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase200,
    lineHeight: "1.5",
    overflowX: "auto" as const,
    whiteSpace: "pre" as const,
  },
  decisionBox: {
    backgroundColor: tokens.colorNeutralBackground2,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusMedium,
    padding: `${tokens.spacingVerticalS} ${tokens.spacingHorizontalM}`,
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalXS,
  },
  actionRow: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap" as const,
  },
  guideCard: {
    padding: `${tokens.spacingVerticalM} ${tokens.spacingHorizontalL}`,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
  },
  // The guide's headings are h2 under the page's h1 (the card's title, axe's
  // heading-order), drawn at the size they had as h3.
  guideContent: {
    "& h2": {
      fontSize: tokens.fontSizeBase400,
      lineHeight: tokens.lineHeightBase400,
      marginTop: tokens.spacingVerticalM,
      marginBottom: tokens.spacingVerticalXS,
    },
    "& ol, & ul": {
      paddingLeft: tokens.spacingHorizontalL,
      margin: `${tokens.spacingVerticalXS} 0`,
    },
    "& li": { marginBottom: tokens.spacingVerticalXS },
    "& code": {
      fontFamily: tokens.fontFamilyMonospace,
      fontSize: tokens.fontSizeBase200,
      backgroundColor: tokens.colorNeutralBackground3,
      padding: "1px 4px",
      borderRadius: tokens.borderRadiusSmall,
    },
    "& p": { margin: `${tokens.spacingVerticalXS} 0` },
  },
  errorText: {
    color: tokens.colorPaletteRedForeground1,
    fontSize: tokens.fontSizeBase200,
  },
  successText: {
    color: tokens.colorPaletteGreenForeground1,
    fontSize: tokens.fontSizeBase200,
    display: "flex",
    alignItems: "center",
    gap: "4px",
  },
  pageErrorBanner: {
    padding: tokens.spacingVerticalM,
    color: tokens.colorPaletteRedForeground1,
    backgroundColor: tokens.colorPaletteRedBackground1,
    borderRadius: tokens.borderRadiusMedium,
  },
});

// ── Helpers ───────────────────────────────────────────────────────────────────

function decisionColor(d: string): "success" | "danger" | "warning" | "informative" {
  if (d === "take") return "success";
  if (d === "reject") return "danger";
  if (d === "modify") return "warning";
  return "informative";
}

// ReplyPR's -Status values, in the verb's own spelling (Scripts/Send-PRReply.ps1).
export const REPLY_STATUSES = [
  "fixed",
  "active",
  "pending",
  "byDesign",
  "wontFix",
  "closed",
] as const;
export type ReplyStatus = (typeof REPLY_STATUSES)[number];

// What a model's recommendation means for the thread's status: taking the
// comment fixes it, rejecting it is "won't fix", modifying it is still pending.
export function statusFor(recommendation: string): ReplyStatus {
  if (recommendation === "take") return "fixed";
  if (recommendation === "reject") return "wontFix";
  if (recommendation === "modify") return "pending";
  return "fixed";
}

interface ReplyDraft {
  reply: string;
  status: ReplyStatus;
  hint?: string;
}

const WORKFLOW_GUIDE = `## How to triage PR comments

1. **Answer a thread here** — type a reply, or let **Suggest a reply** draft one, pick the thread's status and **Post reply**: it goes to the tracker and into the card's \`${TOKENS.prReviewHeading}\` section in one step
2. **Or triage in the file** — open the card in VS Code and ask Copilot Chat to triage using the ado-comments workflow; it reads the code, recommends decisions and drafts replies into the card
3. **Review each comment** — confirm or edit the decision (\`take\` / \`reject\` / \`modify\`) and reply text
4. **Make code changes** for \`take\` and \`modify\` decisions
5. **Commit and push** — the commit hash gets added to the prompt file
6. **Come back here** and click **Resolve** on each triaged comment to post its reply

## Quick start

Paste this into Copilot Chat with the prompt file open:

\`\`\`
Please triage the PR review comments in this file using the ado-comments workflow
\`\`\`
`;

// ── Component ─────────────────────────────────────────────────────────────────

export function PRCommentsDetail({
  filename: filenameProp,
  hideGuide,
}: { filename?: string; hideGuide?: boolean } = {}) {
  const params = useParams<{ filename: string }>();
  const filename = filenameProp ?? params.filename;
  const navigate = useNavigate();
  const styles = useStyles();

  const {
    data: detail,
    isLoading: loading,
    isError,
    error: queryError,
    isFetching,
    refetch,
  } = useGetPrCommentDetailQuery(filename ?? "", { skip: !filename });

  const [runCommand] = useRunCommandMutation();
  const [suggestReply] = useSuggestReplyMutation();
  const { data: env } = useGetEnvQuery();
  // The model is offered only when the agent says it has a key; without one
  // the box still works, and says what would switch the button on.
  const modelReady = Boolean(env?.anthropicConfigured);
  const [resolvingThreads, setResolvingThreads] = useState<Set<number>>(new Set());
  const [resolvedThreads, setResolvedThreads] = useState<Set<number>>(new Set());
  const [resolveErrors, setResolveErrors] = useState<Record<number, string>>({});
  // The reply box: one draft per open thread, kept here until it is
  // posted. Nothing is written until Post reply runs ReplyPR through the
  // bridge, which posts to the tracker and fills the card's Reply: slot.
  const [drafts, setDrafts] = useState<Record<number, ReplyDraft>>({});
  const [suggestingThreads, setSuggestingThreads] = useState<Set<number>>(new Set());

  function draftFor(threadId: number): ReplyDraft {
    return drafts[threadId] ?? { reply: "", status: "fixed" };
  }

  function setDraft(threadId: number, patch: Partial<ReplyDraft>) {
    setDrafts((prev) => ({
      ...prev,
      [threadId]: { ...draftFor(threadId), ...prev[threadId], ...patch },
    }));
  }

  function setError(threadId: number, msg: string | null) {
    setResolveErrors((prev) => {
      const next = { ...prev };
      if (msg === null) delete next[threadId];
      else next[threadId] = msg;
      return next;
    });
  }

  function errorText(e: unknown, fallback: string): string {
    if (e && typeof e === "object" && "data" in e) {
      const data = (e as { data?: { detail?: string } }).data;
      if (data?.detail) return data.detail;
    }
    if (e && typeof e === "object" && "status" in e)
      return `API error ${(e as { status: number }).status}`;
    return e instanceof Error ? e.message : fallback;
  }

  async function suggestFor(comment: PRCommentItem) {
    if (!filename) return;
    const threadId = comment.thread_id;
    setSuggestingThreads((prev) => new Set(prev).add(threadId));
    setError(threadId, null);
    try {
      const answer = await suggestReply({
        filename,
        body: {
          thread_id: threadId,
          comment_text: comment.comment_text,
          file_path: comment.file_path,
          line: comment.line,
          reviewer: comment.reviewer,
          code_suggestion: comment.code_suggestion,
        },
      }).unwrap();
      setDraft(threadId, {
        reply: answer.draft_reply,
        status: statusFor(answer.recommendation),
        hint: `Suggested: ${answer.recommendation} (${answer.confidence} confidence). Edit it before you post.`,
      });
    } catch (e: unknown) {
      const msg = errorText(e, "Suggest failed");
      logWebError(`web/pr-comments/suggest/${filename}/${threadId}`, msg);
      setError(threadId, msg);
    } finally {
      setSuggestingThreads((prev) => {
        const next = new Set(prev);
        next.delete(threadId);
        return next;
      });
    }
  }

  async function postReply(comment: PRCommentItem) {
    if (!detail) return;
    const threadId = comment.thread_id;
    const draft = draftFor(threadId);
    if (!draft.reply.trim()) return;
    setResolvingThreads((prev: Set<number>) => new Set(prev).add(threadId));
    setError(threadId, null);
    try {
      await runCommand({
        name: "ReplyPR",
        params: [
          String(detail.pr_id),
          String(threadId),
          "-Reply",
          draft.reply.trim(),
          "-Status",
          draft.status,
        ],
      }).unwrap();
      setResolvedThreads((prev: Set<number>) => new Set(prev).add(threadId));
      refetch();
    } catch (e: unknown) {
      const msg = errorText(e, "Post failed");
      logWebError(`web/pr-comments/reply/${filename}/${threadId}`, msg);
      setError(threadId, msg);
    } finally {
      setResolvingThreads((prev: Set<number>) => {
        const next = new Set(prev);
        next.delete(threadId);
        return next;
      });
    }
  }

  const pageError = isError
    ? queryError && "status" in queryError
      ? `API error ${(queryError as { status: number }).status}`
      : "Failed to load"
    : null;

  async function resolveComment(comment: PRCommentItem) {
    if (!detail) return;
    const threadId = comment.thread_id;

    setResolvingThreads((prev: Set<number>) => new Set(prev).add(threadId));
    setResolveErrors((prev) => {
      const next = { ...prev };
      delete next[threadId];
      return next;
    });

    try {
      await runCommand({
        name: "ReplyPR",
        params: [
          String(detail.pr_id),
          String(threadId),
          "-Reply",
          comment.reply,
          "-Status",
          "fixed",
        ],
      }).unwrap();
      setResolvedThreads((prev: Set<number>) => new Set(prev).add(threadId));
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Resolve failed";
      logWebError(`web/pr-comments/resolve/${filename}/${threadId}`, msg);
      setResolveErrors((prev) => ({ ...prev, [threadId]: msg }));
    } finally {
      setResolvingThreads((prev: Set<number>) => {
        const next = new Set(prev);
        next.delete(threadId);
        return next;
      });
    }
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  if (loading) {
    return <Spinner size="tiny" label="Loading comments..." />;
  }

  if (pageError) {
    return (
      <div>
        <Button appearance="subtle" icon={<ArrowLeftRegular />} onClick={() => navigate("/")}>
          Back
        </Button>
        <div className={styles.pageErrorBanner} style={{ marginTop: "1rem" }}>
          <Body1>{pageError}</Body1>
        </div>
      </div>
    );
  }

  if (!detail) return null;

  const openCount = detail.comments.filter(
    (c) => c.is_open && !resolvedThreads.has(c.thread_id),
  ).length;

  return (
    <div className={styles.page}>
      {/* ── Top bar ── */}
      <div className={styles.topBar}>
        <Button appearance="subtle" icon={<ArrowLeftRegular />} onClick={() => navigate("/")}>
          Back
        </Button>
        <div className={styles.titleArea}>
          <Title2 as="h1">{detail.title || detail.file}</Title2>
          <div className={styles.progressRow}>
            <Badge appearance="filled" color={openCount > 0 ? "danger" : "success"} size="medium">
              {openCount} open
            </Badge>
            <Badge appearance="outline" color="informative" size="medium">
              {detail.total_count} total
            </Badge>
            <Caption1>PR {detail.pr_id}</Caption1>
            {detail.round_num > 1 && <Caption1>Round {detail.round_num}</Caption1>}
          </div>
        </div>
        <RefreshButton onClick={() => refetch()} isFetching={isFetching} />
      </div>

      <HairlineDivider />

      {/* ── Workflow guide ── */}
      {!hideGuide && (
        <Card className={styles.guideCard} appearance="outline">
          <div className={styles.guideContent}>
            <ReactMarkdown {...markdownPlugins}>{WORKFLOW_GUIDE}</ReactMarkdown>
          </div>
        </Card>
      )}

      {/* ── Comment cards ── */}
      {[...detail.comments].reverse().map((comment) => {
        const hasDecision = comment.decision && comment.decision !== "take / reject / modify";
        const hasReply = comment.reply && comment.reply.trim().length > 0;
        const triaged = hasDecision && hasReply;
        const justResolved = resolvedThreads.has(comment.thread_id);
        const resolving = resolvingThreads.has(comment.thread_id);
        const suggesting = suggestingThreads.has(comment.thread_id);
        const resolved = !comment.is_open || justResolved;
        const isBot =
          comment.reviewer.toLowerCase().includes("bot") ||
          comment.reviewer.toLowerCase().includes("assistant") ||
          comment.reviewer.toLowerCase().includes("ai code review");

        return (
          <Card key={comment.thread_id} className={styles.commentCard} appearance="outline">
            {/* Status indicator */}
            <div
              className={styles.statusIndicator}
              style={{
                color: resolved
                  ? tokens.colorPaletteGreenForeground1
                  : tokens.colorNeutralForeground3,
              }}
            >
              {resolved ? (
                <CheckmarkCircleRegular fontSize={18} />
              ) : (
                <CircleRegular fontSize={18} />
              )}
              <Caption1
                style={{
                  color: resolved
                    ? tokens.colorPaletteGreenForeground1
                    : tokens.colorNeutralForeground3,
                }}
              >
                {resolved ? "Resolved" : triaged ? "Triaged" : "Needs triage"}
              </Caption1>
            </div>

            {/* Header */}
            <div className={styles.commentHeader}>
              <div className={styles.commentHeaderLeft}>
                {isBot ? <BotRegular fontSize={20} /> : <PersonRegular fontSize={20} />}
                <Title3>Comment {comment.number}</Title3>
                {comment.published_date && (
                  <Tooltip content={formatDate(comment.published_date)} relationship="label">
                    <Caption1 style={{ color: tokens.colorNeutralForeground3, cursor: "default" }}>
                      {timeAgo(comment.published_date)}
                    </Caption1>
                  </Tooltip>
                )}
              </div>
            </div>

            {/* Meta */}
            <div className={styles.metaRow}>
              <Caption1>
                <strong>Reviewer:</strong> {comment.reviewer}
              </Caption1>
              {comment.severity && (
                <Badge appearance="outline" size="small">
                  {comment.severity}
                </Badge>
              )}
              {comment.category && (
                <Badge appearance="tint" color="informative" size="small">
                  {comment.category}
                </Badge>
              )}
              <Badge
                appearance="outline"
                color={comment.status === "active" ? "warning" : "success"}
                size="small"
              >
                {comment.status}
              </Badge>
            </div>

            {/* File + line */}
            <Caption1
              style={{
                color: tokens.colorNeutralForeground3,
                wordBreak: "break-all",
              }}
            >
              {comment.file_path}
              {comment.line != null ? ` L${comment.line}` : ""}
            </Caption1>

            <HairlineDivider />

            {/* Comment body */}
            <div>
              <Body2>
                <strong>Comment</strong>
              </Body2>
              <div className={styles.mdContent}>
                <ReactMarkdown {...markdownPlugins}>{comment.comment_text}</ReactMarkdown>
              </div>
            </div>

            {/* Code suggestion */}
            {comment.code_suggestion && (
              <div>
                <Body2>
                  <strong>Code suggestion</strong>
                </Body2>
                <pre className={styles.codeBlock}>{comment.code_suggestion}</pre>
              </div>
            )}

            {/* Decision + Reply (read-only, from prompt file) */}
            {triaged && (
              <>
                <HairlineDivider />
                <div className={styles.decisionBox}>
                  <div className={styles.metaRow}>
                    <Body2>
                      <strong>Decision:</strong>
                    </Body2>
                    <Badge
                      appearance="filled"
                      color={decisionColor(comment.decision)}
                      size="medium"
                    >
                      {comment.decision}
                    </Badge>
                  </div>
                  <Body2>
                    <strong>Reply:</strong>
                  </Body2>
                  <div className={styles.mdContent}>
                    <ReactMarkdown {...markdownPlugins}>{comment.reply}</ReactMarkdown>
                  </div>
                </div>
              </>
            )}

            {/* Reply box: an open thread with no reply in the card yet */}
            {!triaged && !resolved && (
              <>
                <HairlineDivider />
                <div className={styles.decisionBox} data-testid={`reply-box-${comment.thread_id}`}>
                  <Field label="Reply" hint={draftFor(comment.thread_id).hint} size="small">
                    <Textarea
                      value={draftFor(comment.thread_id).reply}
                      onChange={(_, d) => setDraft(comment.thread_id, { reply: d.value })}
                      placeholder="What you did about it, in a sentence or two."
                      resize="vertical"
                      aria-label={`Reply to comment ${comment.number}`}
                    />
                  </Field>
                  <div className={styles.actionRow}>
                    <Dropdown
                      aria-label={`Status for comment ${comment.number}`}
                      size="small"
                      value={draftFor(comment.thread_id).status}
                      selectedOptions={[draftFor(comment.thread_id).status]}
                      onOptionSelect={(_, d) =>
                        setDraft(comment.thread_id, {
                          status: (d.optionValue as ReplyStatus) ?? "fixed",
                        })
                      }
                    >
                      {REPLY_STATUSES.map((value) => (
                        <Option key={value} value={value}>
                          {value}
                        </Option>
                      ))}
                    </Dropdown>
                    {modelReady ? (
                      <Button
                        size="small"
                        icon={
                          suggesting ? (
                            <Spinner size="tiny" aria-label="Suggesting a reply..." />
                          ) : (
                            <SparkleRegular />
                          )
                        }
                        disabled={suggesting}
                        onClick={() => suggestFor(comment)}
                      >
                        {suggesting ? "Drafting..." : "Suggest a reply"}
                      </Button>
                    ) : (
                      <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
                        Set ANTHROPIC_API_KEY in the agent&apos;s environment to draft replies here.
                      </Caption1>
                    )}
                    <Button
                      appearance="primary"
                      size="small"
                      icon={
                        resolving ? (
                          <Spinner size="tiny" aria-label="Posting the reply..." />
                        ) : (
                          <SendRegular />
                        )
                      }
                      disabled={resolving || !draftFor(comment.thread_id).reply.trim()}
                      onClick={() => postReply(comment)}
                    >
                      {resolving ? "Posting..." : "Post reply"}
                    </Button>
                  </div>
                </div>
              </>
            )}

            {/* Actions */}
            <div className={styles.actionRow}>
              {triaged && !resolved && (
                <Button
                  appearance="primary"
                  size="small"
                  icon={
                    resolving ? (
                      <Spinner size="tiny" aria-label="Resolving..." />
                    ) : (
                      <CheckmarkRegular />
                    )
                  }
                  disabled={resolving}
                  onClick={() => resolveComment(comment)}
                >
                  {resolving ? "Resolving..." : "Resolve"}
                </Button>
              )}

              {justResolved && (
                <span className={styles.successText}>
                  <CheckmarkCircleRegular fontSize={14} />
                  Reply posted &amp; thread resolved
                </span>
              )}

              {resolveErrors[comment.thread_id] && (
                <Caption1 className={styles.errorText}>{resolveErrors[comment.thread_id]}</Caption1>
              )}
            </div>
          </Card>
        );
      })}
    </div>
  );
}
