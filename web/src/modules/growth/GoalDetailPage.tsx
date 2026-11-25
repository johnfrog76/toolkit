import { useNavigate, useParams } from "react-router";
import { Badge, makeStyles, tokens } from "@fluentui/react-components";
import { DetailHeader } from "../../shared/DetailHeader";
import { PanelFrame } from "../../shared/PanelFrame";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
import { useGetGrowthDetailQuery } from "./api.growth";
import { TargetArrowRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { GoalActions } from "./GoalActions";

const useStyles = makeStyles({
  page: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    width: "100%",
  },
});

export function GoalDetailPage() {
  const styles = useStyles();
  const { filename } = useParams<{ filename: string }>();

  const navigate = useNavigate();
  const { data, isLoading, isFetching, isError, refetch } = useGetGrowthDetailQuery(
    filename ?? "",
    { skip: !filename },
  );

  const isPresentation = data?.type === "presentation";
  // A goal's badge used to read "Training": the page asked only whether it was a talk.
  const isGoal = data?.type === "goal";

  return (
    <div className={styles.page}>
      <PanelFrame
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
          <DetailHeader
            title={data?.title}
            meta={
              data ? (
                <Badge
                  color={isPresentation ? "brand" : isGoal ? "informative" : "success"}
                  appearance="outline"
                  size="small"
                >
                  {isPresentation ? "Presentation" : isGoal ? "Goal" : "Training"}
                </Badge>
              ) : undefined
            }
            path={data?.path}
            refresh={data ? { onClick: refetch, isFetching } : undefined}
            actions={
              data ? (
                <>
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
                    {data.status === "complete"
                      ? "Complete"
                      : data.status === "new"
                        ? "New"
                        : "Active"}
                  </Badge>
                  {/* The row's moves, on the page where the progress log is read:
                  Complete while the goal is not complete, Archive either way. */}
                  <GoalActions item={data} onArchived={() => navigate("/growth")} />
                </>
              ) : undefined
            }
          />
        }
      >
        {data && (
          <MarkdownViewer content={data.content} style={{ marginTop: tokens.spacingVerticalS }} />
        )}
      </PanelFrame>
    </div>
  );
}
