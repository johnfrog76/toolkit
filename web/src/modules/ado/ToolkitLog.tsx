import {
  Subtitle2,
  Caption1,
  Badge,
  Button,
  Select,
  Input,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { HairlineDivider } from "../../shared/HairlineDivider";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { DismissRegular } from "@fluentui/react-icons";
import { Pagination } from "../../shared/Pagination";
import { usePagination } from "../../hooks/usePagination";
import { useState, useMemo } from "react";
import { useUserRefetch } from "../../hooks/useUserRefetch";
import { LOG_LATEST, useGetLogEntriesQuery, useRunCommandMutation } from "./api.ado";
import type { LogEntry } from "./api.ado";
import { useChartColors } from "../../hooks/chartPalette";
import { useWornTheme } from "../../hooks/useWornTheme";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip as RechartsTooltip,
  ResponsiveContainer,
} from "recharts";
import { ChartWrapper } from "../../shared/ChartWrapper";
import { buildChartData, logBadge } from "./logChart";
import { HistoryRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { localToday, localDaysAgo } from "../../utility/dates";

const useStyles = makeStyles({
  filterRow: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    paddingTop: tokens.spacingVerticalS,
    paddingBottom: tokens.spacingVerticalS,
    flexWrap: "wrap" as const,
  },
  row: {
    display: "grid",
    gridTemplateColumns: "52px 44px 1fr",
    gap: tokens.spacingHorizontalS,
    alignItems: "baseline",
    paddingTop: tokens.spacingVerticalXS,
    paddingBottom: tokens.spacingVerticalXS,
    borderBottom: `1px solid ${tokens.colorNeutralStroke3}`,
  },
  time: {
    fontFamily: "monospace",
    fontSize: tokens.fontSizeBase200,
    color: tokens.colorNeutralForeground3,
    whiteSpace: "nowrap" as const,
  },
  detail: {
    fontSize: tokens.fontSizeBase200,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap" as const,
  },
  chartArea: {
    minHeight: "120px",
  },
});

function typeBadgeColor(type: string): "danger" | "warning" | "success" | "informative" {
  if (type === "ERR") return "danger";
  if (type === "WARN") return "warning";
  if (type === "INFO") return "informative";
  return "success"; // CMD
}

function ChartTooltipContent({
  active,
  payload,
  label,
}: {
  active?: boolean;
  payload?: Array<{ value: number; dataKey: string }>;
  label?: string;
}) {
  if (!active || !payload?.length) return null;
  const types = ["CMD", "INFO", "WARN", "ERR"] as const;
  return (
    <div
      style={{
        background: "rgba(0, 0, 0, 0.3)",
        backdropFilter: "blur(4px)",
        border: `1px solid ${tokens.colorNeutralStroke1}`,
        padding: "6px 10px",
        borderRadius: "4px",
        fontSize: "12px",
        color: tokens.colorNeutralForeground1,
      }}
    >
      <div style={{ fontWeight: 600 }}>{label}</div>
      {types.map((t) => {
        const v = payload.find((p) => p.dataKey === t)?.value ?? 0;
        return v > 0 ? (
          <div key={t}>
            {t}: {v}
          </div>
        ) : null;
      })}
    </div>
  );
}

function TypeChart({ entries }: { entries: LogEntry[] }) {
  const styles = useStyles();
  const chartColors = useChartColors();
  const { theme } = useWornTheme();
  const chartData = useMemo(() => buildChartData(entries), [entries]);
  if (chartData.length === 0) return null;

  const topOp = theme === "dark" ? 0.72 : 0.42;
  const botOp = theme === "dark" ? 0.04 : 0.01;

  return (
    <ChartWrapper>
      <div className={styles.chartArea}>
        <ResponsiveContainer width="100%" height={102}>
          <AreaChart data={chartData}>
            <defs>
              <linearGradient id="lgCMD" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor={chartColors.CMD} stopOpacity={topOp} />
                <stop offset="95%" stopColor={chartColors.CMD} stopOpacity={botOp} />
              </linearGradient>
              <linearGradient id="lgINFO" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor={chartColors.INFO} stopOpacity={topOp} />
                <stop offset="95%" stopColor={chartColors.INFO} stopOpacity={botOp} />
              </linearGradient>
              <linearGradient id="lgWARN" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor={chartColors.WARN} stopOpacity={topOp} />
                <stop offset="95%" stopColor={chartColors.WARN} stopOpacity={botOp} />
              </linearGradient>
              <linearGradient id="lgERR" x1="0" y1="0" x2="0" y2="1">
                <stop
                  offset="5%"
                  stopColor={chartColors.ERR}
                  stopOpacity={Math.min(topOp + 0.1, 1)}
                />
                <stop offset="95%" stopColor={chartColors.ERR} stopOpacity={botOp} />
              </linearGradient>
            </defs>
            <XAxis
              dataKey="label"
              tick={{ fontSize: 10 }}
              interval={0}
              angle={-45}
              textAnchor="end"
              height={31}
            />
            <YAxis tick={{ fontSize: 10 }} width={28} allowDecimals={false} />
            <RechartsTooltip content={<ChartTooltipContent />} cursor={{ stroke: "transparent" }} />
            {/* Straight segments: a spline through four daily counts invents a dip
                between them that no day had. */}
            <Area
              type="linear"
              dataKey="CMD"
              stackId="a"
              stroke={chartColors.CMD}
              strokeWidth={1.5}
              fill="url(#lgCMD)"
            />
            <Area
              type="linear"
              dataKey="INFO"
              stackId="a"
              stroke={chartColors.INFO}
              strokeWidth={1.5}
              fill="url(#lgINFO)"
            />
            <Area
              type="linear"
              dataKey="WARN"
              stackId="a"
              stroke={chartColors.WARN}
              strokeWidth={1.5}
              fill="url(#lgWARN)"
            />
            <Area
              type="linear"
              dataKey="ERR"
              stackId="a"
              stroke={chartColors.ERR}
              strokeWidth={1.5}
              fill="url(#lgERR)"
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </ChartWrapper>
  );
}

function LogRow({ entry }: { entry: LogEntry }) {
  const styles = useStyles();
  const time = entry.timestamp.length >= 19 ? entry.timestamp.slice(11, 19) : entry.timestamp;
  return (
    <div className={styles.row}>
      <Caption1 className={styles.time}>{time}</Caption1>
      <Badge color={typeBadgeColor(entry.type)} appearance="outline" size="small">
        {entry.type}
      </Badge>
      <Caption1 className={styles.detail} title={`${entry.source} — ${entry.detail}`}>
        <strong>{entry.source}</strong> {entry.detail}
      </Caption1>
    </div>
  );
}

// Ten rows, and the number came from a neighbour, not from the log. On /system the
// shell's grid puts this card beside Environment, and grid children stretch: five
// rows left a band of empty space under the list and a pager reading "1 / 100".
// Environment's height is not fixed -- it grows with tier, the module flags and
// what the checks report -- so this was tuned against it at desktop
// width, and may want retuning if that pair drifts. It fits PageCard's 600px cap:
// a row is ~21px (a 12px caption, 2px padding each side, a 1px rule), so ten are
// ~210px under the header, the filter row (~40px) and the chart (120px), with room
// for the pager. Twelve would fit too; ten is what read right beside the neighbour.
const PAGE_SIZE = 10;
const TYPE_OPTIONS = ["All", "CMD", "ERR", "WARN", "INFO"];
const DAYS_OPTIONS = [
  { label: "All time", value: 0 },
  { label: "Today", value: 1 },
  { label: "7 days", value: 7 },
  { label: "30 days", value: 30 },
];

export function ToolkitLog() {
  const styles = useStyles();
  const { data, isLoading, isFetching, error, refetch } = useGetLogEntriesQuery();
  const [runCommand] = useRunCommandMutation();

  const [typeFilter, setTypeFilter] = useState("All");
  const [daysFilter, setDaysFilter] = useState(7);
  const [sourceSearch, setSourceSearch] = useState("");
  const [acking, setAcking] = useState(false);

  const [userRefetching, handleRefetch] = useUserRefetch(isFetching, refetch);

  const resetPage = () => setPage(0);

  // The log's timestamps are local; so is its "today" (never the UTC date).
  const today = localToday();

  const filtered = useMemo(() => {
    let entries = data?.entries ?? [];
    if (typeFilter !== "All") entries = entries.filter((e) => e.type === typeFilter);
    if (daysFilter === 1) {
      entries = entries.filter((e) => e.timestamp.startsWith(today));
    } else if (daysFilter > 1) {
      const cutoffStr = localDaysAgo(daysFilter);
      entries = entries.filter((e) => e.timestamp.slice(0, 10) >= cutoffStr);
    }
    if (sourceSearch.trim()) {
      const q = sourceSearch.trim().toLowerCase();
      entries = entries.filter(
        (e) => e.source.toLowerCase().includes(q) || e.detail.toLowerCase().includes(q),
      );
    }
    return entries;
  }, [data, typeFilter, daysFilter, sourceSearch, today]);

  const { page, totalPages, pageItems: pageEntries, setPage } = usePagination(filtered, PAGE_SIZE);

  const handleAck = async () => {
    setAcking(true);
    try {
      await runCommand({ name: "Log", params: ["-Ack"] });
      refetch();
    } finally {
      setAcking(false);
    }
  };

  return (
    <PageCard
      scrollable
      loading={isLoading}
      loadingLabel="Loading log..."
      headerLeft={<Subtitle2>Log</Subtitle2>}
      headerRight={
        <>
          <Button
            size="small"
            appearance="subtle"
            icon={<DismissRegular />}
            title="Acknowledge errors (Log -Ack)"
            disabled={acking || !data}
            onClick={handleAck}
          >
            Dismiss Errors
          </Button>
          <RefreshButton onClick={handleRefetch} isFetching={userRefetching} disabled={isLoading} />
          <Badge color="informative" appearance="filled" size="large">
            {data ? logBadge(filtered.length, data.entries.length, LOG_LATEST) : 0}
          </Badge>
        </>
      }
      footerCenter={
        totalPages > 1 ? (
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        ) : undefined
      }
    >
      {error ? (
        <EmptyState
          icon={<HistoryRegular />}
          tone="error"
          title="Could not load the log"
          detail="The agent did not answer. Nothing was read."
        />
      ) : data ? (
        <>
          <div className={styles.filterRow}>
            <Select
              size="small"
              aria-label="Entry type"
              value={typeFilter}
              onChange={(_e, d) => {
                setTypeFilter(d.value);
                resetPage();
              }}
              style={{ minWidth: 0 }}
            >
              {TYPE_OPTIONS.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </Select>
            <Select
              size="small"
              aria-label="Period"
              value={String(daysFilter)}
              onChange={(_e, d) => {
                setDaysFilter(Number(d.value));
                resetPage();
              }}
              style={{ minWidth: 0 }}
            >
              {DAYS_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </Select>
            <Input
              size="small"
              placeholder="source or detail…"
              value={sourceSearch}
              onChange={(_e, d) => {
                setSourceSearch(d.value);
                resetPage();
              }}
              style={{ flex: 1, minWidth: "100px" }}
            />
          </div>

          <TypeChart entries={filtered} />

          <HairlineDivider />

          {filtered.length === 0 ? (
            (data?.entries ?? []).length === 0 ? (
              <EmptyState
                icon={<HistoryRegular />}
                title="Nothing logged yet"
                detail="Every command you run, from the terminal or from this page, leaves a line here."
              />
            ) : (
              <EmptyState
                icon={<HistoryRegular />}
                tone="filtered"
                title="No entries match the filters"
                detail={`${(data?.entries ?? []).length} hidden by the filters.`}
              />
            )
          ) : (
            pageEntries.map((entry, i) => <LogRow key={page * PAGE_SIZE + i} entry={entry} />)
          )}
        </>
      ) : null}
    </PageCard>
  );
}
