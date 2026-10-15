import { Subtitle2, Body1, Caption1, Badge, makeStyles, tokens } from "@fluentui/react-components";
import { PageCard } from "../../shared/PageCard";
import { useGetEngagementSummaryQuery } from "./api.ado";
import { BuildingRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { StatTile, StatTiles } from "../../shared/StatTile";

const useStyles = makeStyles({
  meta: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalXS,
  },
});

export function EngagementSummary({ slug, isArchived }: { slug: string; isArchived?: boolean }) {
  const styles = useStyles();
  const { data, isLoading } = useGetEngagementSummaryQuery(slug);

  return (
    <PageCard
      loading={isLoading}
      loadingLabel="Loading engagement summary..."
      headerLeft={<Subtitle2>Space</Subtitle2>}
      empty={
        !data ? (
          <EmptyState
            icon={<BuildingRegular />}
            title="Nothing recorded for this Space yet"
            detail="Its totals are counted from its cards. Start one and they appear here."
          />
        ) : undefined
      }
    >
      {data && (
        <>
          <div className={styles.meta}>
            <div style={{ display: "flex", alignItems: "center", gap: tokens.spacingHorizontalS }}>
              <Body1>
                <strong>{data.client}</strong>
                {data.role ? ` — ${data.role}` : ""}
              </Body1>
              {isArchived && (
                <Badge appearance="tint" color="warning">
                  Archived
                </Badge>
              )}
            </div>
            {data.startDate && data.endDate && (
              <Caption1>
                {data.startDate} – {data.endDate}
              </Caption1>
            )}
          </div>

          <StatTiles>
            <StatTile count={data.stats.workItemsClosed} label="Items closed" />
            <StatTile count={data.stats.reviewsGenerated} label="Reviews" />
            {data.stats.prsReviewed > 0 && (
              <StatTile count={data.stats.prsReviewed} label="PRs reviewed" />
            )}
            {data.projects.length > 0 && <StatTile count={data.projects.length} label="Repos" />}
          </StatTiles>
        </>
      )}
    </PageCard>
  );
}
