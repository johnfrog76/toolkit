/**
 * Where the work is GOING: one row per GitHub milestone, beside the
 * Issue Report on a GitHub Space's Stats tab. The owner's rule: "would be
 * amazing in stats to get a feel for milestones reached". GitHub's own
 * counts, one call per repo (GET /api/milestones); "reached" is derived by
 * the agent the way a card's state is -- every issue closed and at least one
 * issue -- so a milestone nobody closed still reads reached, and says the one
 * thing left to do: "reached, not closed".
 *
 * Mounted only on a GitHub Space (the tab plan); renders nothing when the
 * route says unsupported -- absent, not disabled. Read only: making and
 * closing a milestone stays on the tracker.
 */
import {
  Body1,
  Button,
  Caption1,
  ProgressBar,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { FlagRegular, OpenRegular } from "@fluentui/react-icons";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { EmptyState } from "../../shared/EmptyState";
import { StatTile, StatTiles } from "../../shared/StatTile";
import { useGetMilestonesQuery } from "./api.ado";
import type { Milestone } from "./api.ado";
import {
  milestoneProgress,
  milestoneStage,
  milestoneStateWords,
  milestoneTally,
  orderMilestones,
} from "./milestones";

const useStyles = makeStyles({
  row: {
    display: "grid",
    gridTemplateColumns: "minmax(0, 1fr) auto",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalM,
    rowGap: tokens.spacingVerticalXXS,
    paddingTop: tokens.spacingVerticalS,
    paddingBottom: tokens.spacingVerticalS,
    borderBottom: `1px solid ${tokens.colorNeutralStroke3}`,
  },
  body: {
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXXS,
    minWidth: 0,
  },
  meta: {
    display: "flex",
    flexWrap: "wrap",
    columnGap: tokens.spacingHorizontalM,
    color: tokens.colorNeutralForeground3,
  },
  todo: { color: tokens.colorPaletteDarkOrangeForeground1 },
});

function MilestoneRow({ m }: { m: Milestone }) {
  const styles = useStyles();
  const stage = milestoneStage(m);
  const words = milestoneStateWords(m);
  return (
    <div className={styles.row} data-milestone={m.title}>
      <div className={styles.body}>
        <Body1>
          <strong>{m.title}</strong>
        </Body1>
        <ProgressBar
          value={milestoneProgress(m)}
          thickness="large"
          color={stage === "reached" ? "success" : "brand"}
          aria-label={`${m.title}: ${m.closed} of ${m.open + m.closed} closed`}
        />
        <div className={styles.meta}>
          <Caption1>{m.closed} closed</Caption1>
          <Caption1>{m.open} open</Caption1>
          {m.due ? <Caption1>due {m.due}</Caption1> : null}
          {words ? (
            <Caption1 className={m.state === "closed" ? undefined : styles.todo}>{words}</Caption1>
          ) : null}
        </div>
      </div>
      {/* The external link, last in the row, as external links are. */}
      <Button
        size="small"
        appearance="subtle"
        icon={<OpenRegular />}
        title="Open on GitHub"
        aria-label={`Open ${m.title} on GitHub`}
        as="a"
        href={m.url}
        target="_blank"
        rel="noopener noreferrer"
      />
    </div>
  );
}

export function MilestonesCard() {
  const { data, isLoading, isFetching, error, refetch } = useGetMilestonesQuery();
  if (data && !data.supported) return null;
  const list = orderMilestones(data?.milestones ?? []);
  const tally = milestoneTally(list);
  const icon = <FlagRegular />;
  const empty = isLoading ? undefined : error || !data ? (
    <EmptyState
      icon={icon}
      tone="error"
      title="Could not read the milestones"
      detail="GitHub did not answer. Nothing was read."
    />
  ) : data.reason && list.length === 0 ? (
    <EmptyState
      icon={icon}
      tone="error"
      title="Could not read the milestones"
      detail={data.reason}
    />
  ) : list.length === 0 ? (
    <EmptyState
      icon={icon}
      title="No GitHub milestones yet"
      detail="Milestones are made on GitHub; each one shows here with how far along it is."
    />
  ) : undefined;
  return (
    <PageCard
      loading={isLoading}
      loadingLabel="Reading the GitHub milestones..."
      empty={empty}
      headerLeft={
        <>
          {icon}
          <Subtitle2>Milestones</Subtitle2>
        </>
      }
      headerRight={<RefreshButton onClick={refetch} isFetching={isFetching} disabled={isLoading} />}
    >
      <StatTiles>
        <StatTile count={tally.reached} label="reached" />
        <StatTile count={tally.inFlight} label="in flight" />
        <StatTile count={tally.left} label="issues left" />
      </StatTiles>
      {list.map((m) => (
        <MilestoneRow key={`${m.repo}-${m.number}`} m={m} />
      ))}
    </PageCard>
  );
}
