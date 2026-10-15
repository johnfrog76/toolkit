import { useState } from "react";
import { useParams, useSearchParams } from "react-router";
import {
  Subtitle2,
  Caption1,
  Badge,
  Button,
  Spinner,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { RefreshButton } from "../../shared/RefreshButton";
import { CloudArrowUpRegular, SaveRegular } from "@fluentui/react-icons";
import { BackButton } from "../../shared/BackButton";
import { MarkdownBlock } from "../../shared/MarkdownBlock";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { PageCard } from "../../shared/PageCard";
import {
  useGetReviewPreviewQuery,
  useGetReviewDetailQuery,
  useRunCommandMutation,
} from "./api.ado";
import { DocumentSearchRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { FilePath } from "../../shared/FilePath";

const useStyles = makeStyles({
  page: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    width: "100%",
  },
  titleBlock: {
    display: "flex",
    flexDirection: "column" as const,
    gap: "2px",
    minWidth: 0,
  },
  resultBox: {
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackground3,
    borderRadius: tokens.borderRadiusMedium,
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase200,
    whiteSpace: "pre-wrap" as const,
    overflowX: "auto" as const,
  },
  metaLine: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    alignItems: "center",
    color: tokens.colorNeutralForeground3,
    marginTop: tokens.spacingVerticalXS,
    flexWrap: "wrap" as const,
  },
});

function periodFromFile(file: string): string {
  const match = file.match(/(\d{4}-\d{2}-\d{2})_(\d{4}-\d{2}-\d{2})/);
  if (!match) return "";
  return `${match[1]} – ${match[2]}`;
}

export function ReviewPage() {
  const styles = useStyles();
  const { folder: folderParam } = useParams<{ folder?: string }>();
  const [searchParams] = useSearchParams();
  const slugs = searchParams.get("slugs") ?? undefined;

  const { data, isLoading, isFetching, isError, refetch } = useGetReviewPreviewQuery();
  const [runCommand, { isLoading: isCommitting }] = useRunCommandMutation();
  const [commitResult, setCommitResult] = useState<string | null>(null);

  const pendingFiles = data?.files ?? [];
  const activeFolder = folderParam ?? null;

  const {
    data: reviewDetail,
    isLoading: detailLoading,
    isFetching: detailFetching,
  } = useGetReviewDetailQuery({ folder: activeFolder!, slugs }, { skip: !activeFolder });

  const commit = async (noPush: boolean) => {
    setCommitResult(null);
    const params = noPush ? ["-NoPush"] : [];
    try {
      const result = await runCommand({ name: "PublishWorkReview", params }).unwrap();
      setCommitResult(result.output ?? result.error ?? result.status);
      if (result.status === "success") refetch();
    } catch {}
  };

  return (
    <div className={styles.page}>
      <PageCard
        loading={isLoading || detailLoading}
        loadingLabel="Loading reviews..."
        empty={
          isError ? (
            <EmptyState
              icon={<DocumentSearchRegular />}
              tone="error"
              title="Could not load your reviews"
              detail="The agent did not answer. Nothing was read."
            />
          ) : !pendingFiles.length && !activeFolder ? (
            <EmptyState
              icon={<DocumentSearchRegular />}
              title="No reviews yet"
              detail="A review is written from a period's cards. The + on the Growth page makes one."
            />
          ) : undefined
        }
        headerLeft={
          <>
            <BackButton />
            <Badge color="brand" appearance="outline" size="small">
              Review
            </Badge>
            <div className={styles.titleBlock}>
              <Subtitle2 as="h1">
                {pendingFiles.length > 0
                  ? "Pending Review"
                  : reviewDetail
                    ? reviewDetail.title || reviewDetail.period
                    : "Reviews"}
              </Subtitle2>
              {pendingFiles.length === 0 && <FilePath path={reviewDetail?.path} />}
            </div>
            {pendingFiles.length > 0 && (
              <Badge color="warning" appearance="filled" size="medium">
                {pendingFiles.length} file{pendingFiles.length !== 1 ? "s" : ""}
              </Badge>
            )}
          </>
        }
        headerRight={
          pendingFiles.length > 0 ? (
            <>
              <RefreshButton onClick={refetch} isFetching={isFetching} />

              <Button
                icon={<SaveRegular />}
                size="small"
                appearance="subtle"
                disabled={isCommitting}
                onClick={() => commit(true)}
              >
                Commit only
              </Button>
              <Button
                icon={<CloudArrowUpRegular />}
                size="small"
                appearance="primary"
                disabled={isCommitting}
                onClick={() => commit(false)}
              >
                Commit &amp; Sync
              </Button>
            </>
          ) : null
        }
      >
        {pendingFiles.length > 0 ? (
          <>
            {pendingFiles.map((f) => (
              <div key={f.file}>
                <Caption1
                  style={{
                    display: "block",
                    color: tokens.colorNeutralForeground3,
                    marginTop: tokens.spacingVerticalS,
                    marginBottom: tokens.spacingVerticalXS,
                  }}
                >
                  {f.file}
                  {periodFromFile(f.file) && ` — ${periodFromFile(f.file)}`}
                </Caption1>
                <MarkdownBlock>{f.content}</MarkdownBlock>
              </div>
            ))}
            {commitResult && <div className={styles.resultBox}>{commitResult}</div>}
          </>
        ) : detailFetching ? (
          <div
            style={{
              padding: tokens.spacingVerticalL,
              display: "flex",
              justifyContent: "center",
            }}
          >
            <Spinner size="medium" aria-label="Loading the review..." />
          </div>
        ) : reviewDetail ? (
          <>
            <div className={styles.metaLine}>
              <Caption1>{reviewDetail.period}</Caption1>
              <Caption1>&middot;</Caption1>
              <Caption1>{reviewDetail.folder}</Caption1>
            </div>
            <MarkdownViewer
              content={reviewDetail.content}
              style={{ marginTop: tokens.spacingVerticalS }}
            />
          </>
        ) : null}
      </PageCard>
    </div>
  );
}
