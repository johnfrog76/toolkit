import { Caption1, Badge, makeStyles, tokens } from "@fluentui/react-components";
import { DetailHeader } from "../../shared/DetailHeader";
import { PanelFrame } from "../../shared/PanelFrame";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
// growthApi, not the shell's api: "Resume" is this module's tag and only
// the enhanced slice knows it exists.
import { growthApi, useGetResumeQuery } from "./api.growth";
import { useDispatch } from "react-redux";
import { PersonStarRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";

const useStyles = makeStyles({
  page: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    width: "100%",
  },
});

export function SkillsPage() {
  const styles = useStyles();
  const dispatch = useDispatch();
  const { data: resumeData, isLoading, isFetching, isError } = useGetResumeQuery();

  return (
    <div className={styles.page}>
      <PanelFrame
        loading={isLoading}
        loadingLabel="Loading resume..."
        empty={
          isError ? (
            <EmptyState
              icon={<PersonStarRegular />}
              tone="error"
              title="Could not load your skills page"
              detail="The agent did not answer. Nothing was read."
            />
          ) : !resumeData?.content ? (
            <EmptyState
              icon={<PersonStarRegular />}
              title="No skills page yet"
              detail={
                <>
                  It is one file in your hub, <code>resume/resume.md</code>. Write it, or have your
                  assistant build it from your cards.
                </>
              }
            />
          ) : undefined
        }
        headerLeft={
          <DetailHeader
            title="Resume"
            meta={
              <>
                <Badge color="brand" appearance="outline" size="small">
                  Resume
                </Badge>
                {resumeData?.last_modified && (
                  <Caption1>Updated {resumeData.last_modified}</Caption1>
                )}
              </>
            }
            path={resumeData?.path}
            refresh={{
              onClick: () => dispatch(growthApi.util.invalidateTags(["Resume"])),
              isFetching,
              title: "Refresh resume",
            }}
          />
        }
      >
        {resumeData?.content && (
          <MarkdownViewer
            content={resumeData.content}
            style={{ marginTop: tokens.spacingVerticalS }}
          />
        )}
      </PanelFrame>
    </div>
  );
}
