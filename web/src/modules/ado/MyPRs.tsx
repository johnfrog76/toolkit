import { useState } from "react";
import { useUserRefetch } from "../../hooks/useUserRefetch";
import {
  Card,
  Subtitle2,
  Body1,
  Caption1,
  Badge,
  Select,
  Tooltip,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { RefreshButton } from "../../shared/RefreshButton";
import { PageCard } from "../../shared/PageCard";
import { CardActions, ROW, defineRowMoves } from "../../shared/CardActions";
import { trackerName } from "./TrackerBadge";
import { CommentRegular, CloudRegular } from "@fluentui/react-icons";
import { useGetPrsQuery, useFetchPrCommentsMutation } from "./api.ado";
import { getProjectTag } from "./repoTags";
import { BranchRequestRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import type { EmptyMessage } from "../../shared/EmptyState";

/** A pull request's own move. Its page is the tracker's, so the row's one
 *  exposed action is the vocabulary's external link. */
const PR_MOVES = defineRowMoves("pr", {
  fetchComments: { word: "Fetch PR comments", icon: CommentRegular },
});

const useStyles = makeStyles({
  prCard: {
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
  },
  prHeader: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalS,
  },
  prTitle: {
    flex: 1,
    minWidth: 0,
    display: "-webkit-box",
    WebkitLineClamp: 2,
    WebkitBoxOrient: "vertical" as const,
    overflow: "hidden",
  },
  metaRow: {
    display: "flex",
    gap: tokens.spacingHorizontalM,
    flexWrap: "wrap" as const,
    marginTop: tokens.spacingVerticalXS,
    alignItems: "center",
  },
  branchRow: {
    display: "flex",
    gap: tokens.spacingHorizontalXS,
    alignItems: "center",
    marginTop: tokens.spacingVerticalXS,
  },
  branchName: {
    fontFamily: "monospace",
    fontSize: tokens.fontSizeBase200,
  },
});

function roleBadgeColor(role: string): "brand" | "informative" {
  return role === "Author" ? "brand" : "informative";
}

export function MyPRs({
  filter = "",
  activeRepo = null,
}: {
  filter?: string;
  activeRepo?: string | null;
}) {
  const styles = useStyles();
  const { data, isLoading, error, isFetching, refetch } = useGetPrsQuery();
  const [fetchComments] = useFetchPrCommentsMutation();
  const [fetchingPrIds, setFetchingPrIds] = useState<Set<number>>(new Set());
  const [roleFilter, setRoleFilter] = useState("All");

  const [userRefetching, handleRefetch] = useUserRefetch(isFetching, refetch);

  const handleFetchComments = async (prId: number) => {
    setFetchingPrIds((prev: Set<number>) => new Set(prev).add(prId));
    try {
      await fetchComments({ pullRequestId: prId }).unwrap();
    } finally {
      setFetchingPrIds((prev: Set<number>) => {
        const next = new Set(prev);
        next.delete(prId);
        return next;
      });
    }
  };

  const allPrs = data?.prs ?? [];
  const repoFiltered = activeRepo ? allPrs.filter((pr) => pr.project === activeRepo) : allPrs;
  const roleFiltered =
    roleFilter === "All" ? repoFiltered : repoFiltered.filter((pr) => pr.role === roleFilter);
  const filteredPrs = filter
    ? roleFiltered.filter(
        (pr) =>
          pr.title.toLowerCase().includes(filter.toLowerCase()) ||
          pr.source_branch.toLowerCase().includes(filter.toLowerCase()),
      )
    : roleFiltered;

  const prIcon = <BranchRequestRegular />;
  const emptyMessage: EmptyMessage | undefined = error
    ? "status" in error && error.status === 503
      ? {
          icon: prIcon,
          tone: "error",
          title: "Azure DevOps is not set up",
          detail: "This Space has no address to ask. Give it one in Settings.",
        }
      : {
          icon: prIcon,
          tone: "error",
          title: "Could not load your pull requests",
          detail: "Azure DevOps did not answer. Nothing was read.",
        }
    : filteredPrs.length > 0
      ? undefined
      : allPrs.length === 0
        ? // A stated reason beats an empty state. The agent sends one only when
          // the emptiness is a gap the reader can close -- an identity it could
          // not resolve -- and rendering that as "No active PRs" is exactly the
          // silence this replaced. So the reason is the second line, under the fact.
          {
            icon: prIcon,
            title: "No active pull requests",
            detail: data?.reason ?? "Ones you open, and ones waiting on your review, show up here.",
          }
        : {
            icon: prIcon,
            tone: "filtered",
            title: filter
              ? `No pull requests matching "${filter}"`
              : roleFilter !== "All"
                ? `No ${roleFilter.toLowerCase()} pull requests`
                : "No matching pull requests",
            detail: `${allPrs.length} hidden by the filter.`,
          };

  return (
    <PageCard
      scrollable
      loading={isLoading || isFetching}
      loadingLabel="Fetching pull requests..."
      headerLeft={
        <>
          <CloudRegular />
          <Subtitle2>My Pull Requests</Subtitle2>
        </>
      }
      headerRight={
        <>
          <Select
            size="small"
            value={roleFilter}
            onChange={(_e, d) => setRoleFilter(d.value)}
            style={{ minWidth: 0 }}
            disabled={!!error || isLoading || isFetching}
          >
            <option value="All">All</option>
            <option value="Author">Author</option>
            <option value="Reviewer">Reviewer</option>
          </Select>
          <RefreshButton onClick={handleRefetch} isFetching={userRefetching} disabled={isLoading} />
          <Badge color="informative" appearance="filled" size="large">
            {filteredPrs.length}
          </Badge>
        </>
      }
      empty={emptyMessage ? <EmptyState {...emptyMessage} /> : undefined}
    >
      {filteredPrs.map((pr) => (
        <Card key={pr.pull_request_id} className={styles.prCard} size="small" appearance="outline">
          <div className={styles.prHeader}>
            <div className={styles.prTitle}>
              <Body1>
                <strong>{pr.title}</strong>
              </Body1>
            </div>
            <CardActions
              primaryAction={ROW.external.action({ detail: trackerName("ado"), href: pr.url })}
              menuLabel={`Actions for ${pr.title}`}
              secondaryActions={[
                PR_MOVES.fetchComments.action({
                  busy: fetchingPrIds.has(pr.pull_request_id) ? "Fetching comments..." : undefined,
                  disabled: fetchingPrIds.has(pr.pull_request_id),
                  onClick: () => handleFetchComments(pr.pull_request_id),
                }),
              ]}
            />
          </div>

          <div className={styles.metaRow}>
            <Tooltip
              content={`You are the ${pr.role.toLowerCase()} of this PR`}
              relationship="description"
            >
              <Badge color={roleBadgeColor(pr.role)} appearance="outline" size="medium">
                {pr.role}
              </Badge>
            </Tooltip>
            <Caption1>#{pr.pull_request_id}</Caption1>
            <Tooltip content={pr.project} relationship="description">
              <Badge color="informative" appearance="outline" size="small">
                {getProjectTag(pr.project)}
              </Badge>
            </Tooltip>
            <Caption1>{pr.created}</Caption1>
          </div>

          <div className={styles.branchRow}>
            <Caption1 className={styles.branchName}>{pr.source_branch}</Caption1>
            <Caption1>→</Caption1>
            <Caption1 className={styles.branchName}>{pr.target_branch}</Caption1>
          </div>
        </Card>
      ))}
    </PageCard>
  );
}
