import { Body1, Button, Caption1, Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { DataUsageRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { StatTile, StatTiles } from "../../shared/StatTile";
import { useGetBurnQuery, useRefreshBurnMutation } from "./api.usage";
import type { BurnResponse, BurnWindow } from "./api.usage";

/**
 * The System page's Claude Code burn: today and this week, as `Burn` prints them
 * in a terminal (docs/hub/usage.md, "Today and this week") -- the same figures,
 * because the agent serves the verb's own `-AsJson`.
 *
 * Facts only, the owner's rule: tokens by model, and a cost marked derived. No
 * colour says good or bad, no word does, and nothing is a share of the plan's
 * allocation, which nothing here knows.
 *
 * Drawn only where /env's `claudeUsage` is true (the ado module's systemCards):
 * with no session files on this machine there is no tile and nothing is fetched.
 */

const useStyles = makeStyles({
  card: { display: "flex", flexDirection: "column", minWidth: 0 },
  window: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalXS,
    paddingTop: tokens.spacingVerticalS,
  },
  table: {
    width: "100%",
    borderCollapse: "collapse" as const,
    fontSize: tokens.fontSizeBase200,
    "& th, & td": {
      textAlign: "right" as const,
      padding: "2px 4px",
      whiteSpace: "nowrap" as const,
    },
    "& th:first-child, & td:first-child": { textAlign: "left" as const },
    "& th": { fontWeight: tokens.fontWeightRegular, color: tokens.colorNeutralForeground3 },
  },
  notes: {
    display: "flex",
    flexDirection: "column",
    gap: "2px",
    paddingTop: tokens.spacingVerticalS,
    color: tokens.colorNeutralForeground3,
  },
});

const TOKENS = new Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 });

/** A derived cost, or the fact that nothing in it is priced. */
export function costText(value: number | null): string {
  return value == null ? "no priced model" : `$${value.toFixed(2)}`;
}

/** "from Fri 30 Oct, 05:00" -- a window's start on this browser's clock. */
export function fromText(iso: string): string {
  const d = new Date(iso);
  const day = d.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" });
  const time = d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  return `from ${day}, ${time}`;
}

/** Which machines a window counts, and from what: "mini (session files); laptop (2 day records)". */
export function machinesText(w: BurnWindow): string {
  return w.machines
    .map((m) =>
      m.source === "session-files"
        ? `${m.machine} (session files)`
        : `${m.machine} (${m.days.length} day record${m.days.length === 1 ? "" : "s"})`,
    )
    .join("; ");
}

function Window({ title, w }: { title: string; w: BurnWindow }) {
  const styles = useStyles();
  return (
    <div className={styles.window} data-burn-window={title}>
      <Body1>
        <strong>{title}</strong> <Caption1>{fromText(w.from)}</Caption1>
      </Body1>
      <StatTiles>
        <StatTile count={w.totals.messages} label="Messages" />
        <StatTile count={costText(w.totals.costUsdDerived)} label="Cost, derived" />
      </StatTiles>
      {w.byModel.length > 0 && (
        <table className={styles.table}>
          <thead>
            <tr>
              <th>Model</th>
              <th>Msgs</th>
              <th>In</th>
              <th>Out</th>
              <th>Cache write</th>
              <th>Cache read</th>
              <th>Derived</th>
            </tr>
          </thead>
          <tbody>
            {w.byModel.map((m) => (
              <tr key={m.model}>
                <td>{m.model}</td>
                <td>{m.messages}</td>
                <td>{TOKENS.format(m.input)}</td>
                <td>{TOKENS.format(m.output)}</td>
                <td>{TOKENS.format(m.cacheWrite5m + m.cacheWrite1h)}</td>
                <td>{TOKENS.format(m.cacheRead)}</td>
                <td>{m.costUsdDerived == null ? "unpriced" : `$${m.costUsdDerived.toFixed(2)}`}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {w.machines.length > 0 && <Caption1>{machinesText(w)}</Caption1>}
    </div>
  );
}

function Notes({ data }: { data: BurnResponse }) {
  const styles = useStyles();
  const unpriced = [...new Set([...data.today.unpriced, ...data.week.unpriced])];
  const read = new Date(data.fetchedAt).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });
  return (
    <div className={styles.notes}>
      <Caption1>
        Cost derived from list prices as of {data.cost.priceTableAsOf}; not the plan&apos;s
        allocation. The week starts {data.weekStarts} (burn.weekStarts).
      </Caption1>
      {data.cost.priceNotes.map((n) => (
        <Caption1 key={n.model}>
          {n.model} is {n.note}.
        </Caption1>
      ))}
      {unpriced.length > 0 && <Caption1>Counted without a cost: {unpriced.join(", ")}.</Caption1>}
      {!data.hub && (
        <Caption1>No hub usage/ folder: no other machine&apos;s records read.</Caption1>
      )}
      <Caption1>
        Read at {read}
        {data.fromCache ? ", kept by the agent for up to an hour" : ""}.
      </Caption1>
    </div>
  );
}

export function BurnCard() {
  const styles = useStyles();
  const { data, isLoading, isError } = useGetBurnQuery();
  const [refresh, { isLoading: refreshing }] = useRefreshBurnMutation();
  const onRefresh = () => {
    void refresh();
  };

  return (
    <PageCard
      className={styles.card}
      loading={isLoading}
      loadingLabel="Reading Claude Code usage..."
      headerLeft={<Subtitle2>Claude Code burn</Subtitle2>}
      headerRight={
        <RefreshButton
          onClick={onRefresh}
          isFetching={refreshing}
          title="Read again, past the agent's hour"
        />
      }
      empty={
        isError && !data ? (
          <EmptyState
            icon={<DataUsageRegular />}
            tone="error"
            title="Could not read the burn"
            detail="The agent did not answer, or Burn did not run. Nothing was read."
            action={
              <Button size="small" appearance="primary" onClick={onRefresh}>
                Try again
              </Button>
            }
          />
        ) : undefined
      }
    >
      {data && (
        <>
          <Window title="Today" w={data.today} />
          <Window title="This week" w={data.week} />
          <Notes data={data} />
        </>
      )}
    </PageCard>
  );
}
