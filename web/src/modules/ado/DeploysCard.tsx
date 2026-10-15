/**
 * The pane's LAST DEPLOY (its final row): the newest workflow runs per
 * repo, from GET /api/deploys. The CLI's Dashboard grew these rows in tracker
 * M1 step 7; this is their web face. Mounted only on a GitHub space; renders
 * nothing when the route says unsupported -- absent, not disabled. A space
 * whose repos run no workflows says so in one line rather than hiding: a
 * deploy you cannot see is indistinguishable from one that never ran.
 */
import {
  Badge,
  Body1,
  Caption1,
  Link,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { RocketRegular } from "@fluentui/react-icons";
import { PageCard } from "../../shared/PageCard";
import { CardSpinner } from "../../shared/CardSpinner";
import { RefreshButton } from "../../shared/RefreshButton";
import { EmptyState } from "../../shared/EmptyState";
import { useGetDeploysQuery } from "./api.ado";

const useStyles = makeStyles({
  row: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalM,
    paddingTop: tokens.spacingVerticalXS,
    paddingBottom: tokens.spacingVerticalXS,
    borderBottom: `1px solid ${tokens.colorNeutralStroke3}`,
  },
  grow: { flexGrow: 1, minWidth: 0 },
  mono: { fontFamily: "Consolas, monospace", opacity: 0.85 },
});

const RUN_COLOR: Record<string, "success" | "danger" | "warning" | "informative"> = {
  success: "success",
  failure: "danger",
  cancelled: "warning",
};

export function DeploysCard() {
  const styles = useStyles();
  const { data, isLoading, isFetching, refetch } = useGetDeploysQuery();
  if (data && !data.supported) return null;
  return (
    <PageCard
      headerLeft={
        <>
          <RocketRegular />
          <Subtitle2>Deploys</Subtitle2>
        </>
      }
      headerRight={<RefreshButton onClick={refetch} isFetching={isFetching} disabled={isLoading} />}
    >
      {isLoading ? (
        <CardSpinner label="Reading the runs..." />
      ) : data?.reason ? (
        <Body1>{data.reason}</Body1>
      ) : (data?.runs ?? []).length === 0 ? (
        // The house empty state, naming the tracker and the thing.
        <EmptyState
          icon={<RocketRegular />}
          title="No GitHub Actions runs yet"
          detail="This Space's repos have run no workflows. Each run lands here, newest first."
        />
      ) : (
        (data?.runs ?? []).map((r, i) => (
          <div key={i} className={styles.row}>
            <Badge
              color={
                r.status !== "completed"
                  ? "informative"
                  : (RUN_COLOR[r.conclusion] ?? "informative")
              }
              appearance="outline"
              size="small"
            >
              {r.status !== "completed" ? r.status : r.conclusion || "done"}
            </Badge>
            <span className={styles.grow}>
              <Link href={r.url} target="_blank" rel="noreferrer">
                {r.title || "workflow"}
              </Link>
            </span>
            <Caption1 className={styles.mono}>
              {r.repo} · {r.branch} · {r.when}
            </Caption1>
          </div>
        ))
      )}
    </PageCard>
  );
}
