import { Subtitle2, Caption1, Badge, makeStyles, tokens } from "@fluentui/react-components";
import { RefreshButton } from "../../shared/RefreshButton";
import { BackButton } from "../../shared/BackButton";
import { PageCard } from "../../shared/PageCard";
import { MarkdownViewer } from "../../shared/MarkdownViewer";
// growthApi, not the shell's api: "Resume" is this module's tag and only
// the enhanced slice knows it exists.
import { growthApi, useGetResumeQuery } from "./api.growth";
import { useDispatch } from "react-redux";
import { PersonStarRegular } from "@fluentui/react-icons";
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
  pathLine: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap" as const,
  },
});

export function SkillsPage() {
  const styles = useStyles();
  const dispatch = useDispatch();
  const { data: resumeData, isLoading, isFetching, isError } = useGetResumeQuery();

  return (
    <div className={styles.page}>
      <PageCard
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
          <>
            <BackButton />
            <Badge color="brand" appearance="outline" size="small">
              Resume
            </Badge>
            <div className={styles.titleBlock}>
              <Subtitle2>Resume</Subtitle2>
              <div className={styles.pathLine}>
                <FilePath path={resumeData?.path} />
                {resumeData?.last_modified && (
                  <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
                    Updated {resumeData.last_modified}
                  </Caption1>
                )}
              </div>
            </div>
          </>
        }
        headerRight={
          <RefreshButton
            onClick={() => dispatch(growthApi.util.invalidateTags(["Resume"]))}
            isFetching={isFetching}
            title="Refresh resume"
          />
        }
      >
        {resumeData?.content && (
          <MarkdownViewer
            content={resumeData.content}
            style={{ marginTop: tokens.spacingVerticalS }}
          />
        )}
      </PageCard>
    </div>
  );
}
