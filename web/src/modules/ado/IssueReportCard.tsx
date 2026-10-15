/**
 * The pane's REPORTS: how the product's backlog stands, in
 * GitHub's OWN vocabulary -- open, closed, closed this week, severities,
 * kinds, milestones. Never an ADO word in a gh costume, and no dual-entry
 * ceremony: this card counts the ledger, it asks for nothing (the owner: "how
 * many closed, open, sev1 2 etc").
 *
 * Mounted only on a GitHub space (the caller gates on env.tracker); renders
 * nothing when the route says unsupported -- absent, not disabled.
 *
 * The severity and kind counts draw in the SAME tile as open/closed/closed
 * this week -- a second `StatTiles` row, the identical
 * `StatTile` component, GitHub's own words (`sev1`, `bug`, `feat`) as the
 * label. They used to be small monospace captions and a tinted `Badge`, a
 * different costume from the row above them for no reason the data gives:
 * "these items should match style of the other top three stats" (the owner). The
 * severity colour signal survives the move -- `SEV_COLOR` now names the same
 * three tokens `Badge`'s own `tint-danger`/`tint-severe`/`tint-warning`
 * presets draw their text in, passed through `StatTile`'s own `color` prop
 * rather than a semantic Badge colour name, since a tile has no such prop.
 */
import { Body1, Caption1, Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { DataUsageRegular } from "@fluentui/react-icons";
import { PageCard } from "../../shared/PageCard";
import { CardSpinner } from "../../shared/CardSpinner";
import { RefreshButton } from "../../shared/RefreshButton";
import { StatTile, StatTiles } from "../../shared/StatTile";
import { useGetIssueReportQuery } from "./api.ado";

const useStyles = makeStyles({
  milestone: {
    display: "flex",
    justifyContent: "space-between",
    columnGap: tokens.spacingHorizontalM,
    paddingTop: tokens.spacingVerticalXS,
    paddingBottom: tokens.spacingVerticalXS,
    borderBottom: `1px solid ${tokens.colorNeutralStroke3}`,
  },
});

// The same three foreground tokens Badge's tint-danger/severe/warning
// presets draw their text in (`@fluentui/react-badge`'s useBadgeStyles) --
// the severity signal, carried over rather than reinvented.
const SEV_COLOR: Record<string, string> = {
  sev1: tokens.colorPaletteRedForeground1,
  sev2: tokens.colorPaletteDarkOrangeForeground1,
  sev3: tokens.colorPaletteYellowForeground1,
};

export function IssueReportCard() {
  const styles = useStyles();
  const { data, isLoading, isFetching, refetch } = useGetIssueReportQuery();
  if (data && !data.supported) return null;
  return (
    <PageCard
      headerLeft={
        <>
          <DataUsageRegular />
          <Subtitle2>Issue Report</Subtitle2>
        </>
      }
      headerRight={<RefreshButton onClick={refetch} isFetching={isFetching} disabled={isLoading} />}
    >
      {isLoading || !data ? (
        <CardSpinner label="Counting the GitHub issues..." />
      ) : (
        <>
          <StatTiles>
            <StatTile count={data.open} label="open" />
            <StatTile count={data.closed} label="closed" />
            <StatTile count={data.closed_recent} label="closed this week" />
          </StatTiles>
          {data.sev.sev1 || data.sev.sev2 || data.sev.sev3 || data.kind.bug || data.kind.feat ? (
            <StatTiles>
              {(["sev1", "sev2", "sev3"] as const).map((sv) =>
                data.sev[sv] ? (
                  <StatTile key={sv} count={data.sev[sv]} label={sv} color={SEV_COLOR[sv]} />
                ) : null,
              )}
              {data.kind.bug ? <StatTile count={data.kind.bug} label="bug" /> : null}
              {data.kind.feat ? <StatTile count={data.kind.feat} label="feat" /> : null}
            </StatTiles>
          ) : null}
          {data.milestones.map((m) => (
            <div key={m.title} className={styles.milestone}>
              <Body1>{m.title}</Body1>
              <Caption1>{m.open} open</Caption1>
            </div>
          ))}
          {data.reason ? <Caption1>{data.reason}</Caption1> : null}
        </>
      )}
    </PageCard>
  );
}
