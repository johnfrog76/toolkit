import { Subtitle2, Body1, Caption1, Badge, makeStyles, tokens } from "@fluentui/react-components";
import { PageCard } from "../../shared/PageCard";
import { useGetEngagementSummaryQuery } from "./api.ado";
import { BuildingRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { StatTile, StatTiles } from "../../shared/StatTile";
import { useGetEnvQuery } from "../../shell/api";
import { summaryTiles } from "./summaryTiles";

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
  // Reviews are the growth module's: off, or not configured, the tile is absent (summaryTiles.ts).
  const { data: env } = useGetEnvQuery();
  const growth = Boolean(env?.features?.growth);

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
            {summaryTiles(data.stats, data.projects.length, { growth }).map((tile) => (
              <StatTile key={tile.label} count={tile.count} label={tile.label} />
            ))}
          </StatTiles>
        </>
      )}
    </PageCard>
  );
}
