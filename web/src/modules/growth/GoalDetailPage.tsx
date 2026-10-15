import { useParams } from "react-router";
import { Subtitle2, Badge, makeStyles, tokens } from "@fluentui/react-components";
import { BackButton } from "../../shared/BackButton";
import { PageCard } from "../../shared/PageCard";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { useGetGrowthDetailQuery } from "./api.growth";
import { TargetArrowRegular } from "@fluentui/react-icons";
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
});

export function GoalDetailPage() {
  const styles = useStyles();
  const { filename } = useParams<{ filename: string }>();

  const { data, isLoading, isError } = useGetGrowthDetailQuery(filename ?? "", {
    skip: !filename,
  });

  const isPresentation = data?.type === "presentation";

  return (
    <div className={styles.page}>
      <PageCard
        loading={isLoading}
        loadingLabel="Loading goal..."
        empty={
          isError ? (
            <EmptyState
              icon={<TargetArrowRegular />}
              tone="error"
              title="Could not open this goal"
              detail={
                <>
                  The agent did not answer, or there is no such file: <code>{filename}</code>
                </>
              }
            />
          ) : undefined
        }
        headerLeft={
          <>
            <BackButton />
            {data && (
              <>
                <Badge
                  color={isPresentation ? "brand" : "success"}
                  appearance="outline"
                  size="small"
                >
                  {isPresentation ? "Presentation" : "Training"}
                </Badge>
                <div className={styles.titleBlock}>
                  <Subtitle2>{data.title}</Subtitle2>
                  <FilePath path={data.path} />
                </div>
              </>
            )}
          </>
        }
        headerRight={
          data ? (
            <Badge
              color={
                data.status === "complete"
                  ? "success"
                  : data.status === "new"
                    ? "important"
                    : "subtle"
              }
              appearance="tint"
              size="small"
            >
              {data.status === "complete" ? "Complete" : data.status === "new" ? "New" : "Active"}
            </Badge>
          ) : undefined
        }
      >
        {data && (
          <MarkdownViewer content={data.content} style={{ marginTop: tokens.spacingVerticalS }} />
        )}
      </PageCard>
    </div>
  );
}
