import { useUserRefetch } from "../../hooks/useUserRefetch";
import { useNavigate } from "react-router";
import {
  Card,
  Subtitle2,
  Caption1,
  Badge,
  Button,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { RefreshButton } from "../../shared/RefreshButton";
import { PageCard } from "../../shared/PageCard";
import { CommentRegular, ArrowRightRegular, FolderRegular } from "@fluentui/react-icons";
import { useGetEnvQuery } from "../../shell/api";
import { useGetPrCommentsQuery, useGetPrsQuery } from "./api.ado";
import { EmptyState } from "../../shared/EmptyState";
import type { EmptyMessage } from "../../shared/EmptyState";

const useStyles = makeStyles({
  list: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
  },
  itemCard: {
    padding: `${tokens.spacingVerticalM} ${tokens.spacingHorizontalM}`,
    cursor: "pointer",
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    "&:hover": {
      backgroundColor: tokens.colorNeutralBackground1Hover,
    },
  },
  itemRow: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalM,
  },
  itemMeta: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    marginTop: tokens.spacingVerticalXS,
    flexWrap: "wrap" as const,
  },
  titleClamp: {
    flex: 1,
    minWidth: 0,
    display: "-webkit-box",
    WebkitLineClamp: 2,
    WebkitBoxOrient: "vertical" as const,
    overflow: "hidden",
  },
  errorBanner: {
    padding: tokens.spacingVerticalM,
    color: tokens.colorPaletteRedForeground1,
    backgroundColor: tokens.colorPaletteRedBackground1,
    borderRadius: tokens.borderRadiusMedium,
  },
});

export function PRCommentsList({
  filter = "",
  activeRepo = null,
}: {
  filter?: string;
  activeRepo?: string | null;
}) {
  const styles = useStyles();
  const navigate = useNavigate();
  const { data: env } = useGetEnvQuery();
  const { data, isLoading: loading, isError, error, isFetching, refetch } = useGetPrCommentsQuery();
  const { data: prsData } = useGetPrsQuery(undefined, {
    skip: !env || env.tier > 1,
  });

  const [userRefetching, handleRefetch] = useUserRefetch(isFetching, refetch);

  const errorMsg = isError
    ? error && "status" in error
      ? `API error ${error.status}`
      : "Failed to load"
    : null;

  const allItems = data?.items ?? [];
  const repoFiltered = activeRepo
    ? allItems.filter((i) => {
        const pr = (prsData?.prs ?? []).find((p) => p.pull_request_id === i.pr_id);
        return pr ? pr.project === activeRepo : true;
      })
    : allItems;
  const filteredItems = filter
    ? repoFiltered.filter(
        (i) =>
          i.file.toLowerCase().includes(filter.toLowerCase()) ||
          i.title.toLowerCase().includes(filter.toLowerCase()) ||
          i.pr_id.toString().includes(filter),
      )
    : repoFiltered;
  const totalOpen = filteredItems.reduce((sum, i) => sum + i.open_count, 0);

  // Said through the frame's `empty` slot, so every card says it one way.
  const emptyMessage: EmptyMessage | undefined = errorMsg
    ? {
        icon: <CommentRegular />,
        tone: "error",
        title: "Could not load PR comments",
        detail: errorMsg,
      }
    : filteredItems.length > 0
      ? undefined
      : filter
        ? { icon: <CommentRegular />, tone: "filtered", title: `No comments matching "${filter}"` }
        : {
            icon: <CommentRegular />,
            title: "No open PR comments",
            detail:
              "Review comments you fetch for a pull request wait here until each has a decision.",
          };

  return (
    <PageCard
      scrollable
      empty={emptyMessage ? <EmptyState {...emptyMessage} /> : undefined}
      loading={loading || userRefetching}
      loadingLabel="Loading PR comments..."
      headerLeft={
        <>
          <FolderRegular />
          <Subtitle2>PR Comments</Subtitle2>
          {!loading && !userRefetching && !errorMsg && data && data.count > 0 && (
            <Badge appearance="filled" color="danger" size="medium">
              {totalOpen} open
            </Badge>
          )}
        </>
      }
      headerRight={
        <RefreshButton
          onClick={handleRefetch}
          isFetching={userRefetching}
          disabled={loading || userRefetching}
        />
      }
    >
      {!errorMsg && filteredItems.length > 0 && (
        <div className={styles.list}>
          {[...filteredItems].reverse().map((item) => (
            <Card
              key={item.file}
              className={styles.itemCard}
              appearance="outline"
              onClick={() => navigate(`/pr-comments/${encodeURIComponent(item.file)}`)}
            >
              <div className={styles.itemRow}>
                <div className={styles.titleClamp}>
                  <Subtitle2>{item.title || item.file}</Subtitle2>
                </div>
                <Button
                  appearance="subtle"
                  size="small"
                  icon={<ArrowRightRegular />}
                  aria-label="Open"
                  onClick={(e) => {
                    e.stopPropagation();
                    navigate(`/pr-comments/${encodeURIComponent(item.file)}`);
                  }}
                />
              </div>
              <div className={styles.itemMeta}>
                <Badge appearance="filled" color="danger" size="medium">
                  {item.open_count} open
                </Badge>
                <Badge appearance="outline" color="informative" size="medium">
                  {item.total_count} total
                </Badge>
                <Caption1>PR {item.pr_id}</Caption1>
              </div>
            </Card>
          ))}
        </div>
      )}
    </PageCard>
  );
}
