import {
  Subtitle2,
  Body1,
  Caption1,
  Badge,
  Button,
  Spinner,
  Tooltip,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { HairlineDivider } from "../../shared/HairlineDivider";
import { RefreshButton } from "../../shared/RefreshButton";
import { PageCard } from "../../shared/PageCard";
import { thinScrollbar } from "../../shared/thinScrollbar";
import {
  CheckmarkCircleRegular,
  DismissCircleRegular,
  WarningRegular,
} from "@fluentui/react-icons";
import { useMemo, useState } from "react";
import { useGetTestHistoryQuery, useRunCommandMutation } from "./api.ado";
import type { TestDay } from "./api.ado";
import { halfTiles } from "./testHalves";
import { useChartColors } from "../../hooks/chartPalette";
import { useWornTheme } from "../../hooks/useWornTheme";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip as RechartsTooltip,
  ResponsiveContainer,
} from "recharts";
import { ChartWrapper } from "../../shared/ChartWrapper";
import { BeakerRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { StatTile, StatTiles } from "../../shared/StatTile";
import type { EmptyMessage } from "../../shared/EmptyState";

const useStyles = makeStyles({
  card: {
    display: "flex",
    flexDirection: "column",
    maxHeight: "600px",
    overflow: "hidden",
    minWidth: 0,
  },
  chartArea: {
    maxHeight: "150px",
    paddingTop: tokens.spacingVerticalS,
    flexShrink: 0,
  },
  scrollArea: {
    flex: 1,
    paddingRight: tokens.spacingHorizontalXS,
    marginBottom: tokens.spacingVerticalM,
    minHeight: 0,
    minWidth: 0,
    overflowY: "auto",
    overflowX: "hidden",
    ...thinScrollbar,
  },
  suiteRow: {
    display: "grid",
    gridTemplateColumns: "auto 1fr auto auto",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    paddingTop: "4px",
    paddingBottom: "4px",
  },
  suiteIcon: {
    display: "flex",
    alignItems: "center",
  },
  suiteName: {
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap" as const,
    minWidth: 0,
  },
  suiteCount: {
    textAlign: "right" as const,
    whiteSpace: "nowrap" as const,
  },
});

function formatLastRun(timestamp: string | null): string {
  if (!timestamp) return "never";
  const d = new Date(timestamp);
  const now = new Date();
  const diffMs = now.getTime() - d.getTime();
  const diffDays = Math.floor(diffMs / 86400000);
  const timeStr = d.toLocaleTimeString([], {
    hour: "numeric",
    minute: "2-digit",
  });
  if (diffDays === 0) return `${timeStr} today`;
  if (diffDays === 1) return `${timeStr} yesterday`;
  return `${diffDays}d ago`;
}

interface ChartRow {
  label: string;
  pass: number;
  fail: number;
}

function buildChartData(days: TestDay[]): ChartRow[] {
  return days.map((d) => {
    const fail = d.total - d.passed;
    const date = new Date(d.date + "T00:00:00");
    const dayName = date.toLocaleDateString(undefined, { weekday: "short" });
    const dayNum = date.getDate();
    return { label: `${dayName} ${dayNum}`, pass: d.passed, fail };
  });
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
  const pass = payload.find((p) => p.dataKey === "pass")?.value ?? 0;
  const fail = payload.find((p) => p.dataKey === "fail")?.value ?? 0;
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
      <div style={{ color: tokens.colorPaletteGreenForeground1 }}>Pass: {pass}</div>
      {fail > 0 && <div style={{ color: tokens.colorPaletteRedForeground1 }}>Fail: {fail}</div>}
    </div>
  );
}

export function TestHealth() {
  const styles = useStyles();
  const { data, isLoading, isError, isFetching, refetch } = useGetTestHistoryQuery();
  const [runCommand, { isLoading: isRunning }] = useRunCommandMutation();
  const chartColors = useChartColors();
  const { theme } = useWornTheme();
  const topOp = theme === "dark" ? 0.72 : 0.42;
  const botOp = theme === "dark" ? 0.28 : 0.14;
  const [_runResult, setRunResult] = useState<{
    ok: boolean;
    msg: string;
  } | null>(null);

  const chartData = useMemo(() => (data ? buildChartData(data.days) : []), [data]);
  const halves = useMemo(() => halfTiles(data), [data]);

  const latestDay = data?.days.length ? data.days[data.days.length - 1] : null;
  const totalPassed = latestDay?.passed ?? 0;
  const totalTotal = latestDay?.total ?? 0;
  const anyFail = latestDay?.suites.some((s) => s.result === "fail") ?? false;
  const anyWarn = latestDay?.suites.some((s) => s.result === "warn") ?? false;
  const allGreen = latestDay ? !anyFail && !anyWarn : false;
  const hasData = data && data.days.length > 0;

  const handleRunNow = async () => {
    setRunResult(null);
    try {
      const res = await runCommand({ name: "TestToolkit" }).unwrap();
      if (res.status === "success") {
        setRunResult({ ok: true, msg: "The Toolkit's tests ran. The run is below." });
      } else {
        setRunResult({
          ok: false,
          msg: res.error || `Exit code ${res.exit_code}`,
        });
      }
    } catch {
      setRunResult({ ok: false, msg: "The tests did not start: the agent did not answer." });
    }
    refetch();
  };

  const headerLeft = (
    <>
      <Subtitle2>Test Health</Subtitle2>
      {hasData && data?.active_space && (
        <Badge
          appearance="tint"
          color="brand"
          size="small"
          title={`The Space the last run was in: ${data.active_space}`}
        >
          {data.active_space}
        </Badge>
      )}
    </>
  );

  const headerRight = isError ? (
    <RefreshButton onClick={refetch} title="Retry" />
  ) : !hasData ? (
    <Button
      size="small"
      appearance="subtle"
      title="Run all of the Toolkit's tests on this machine now"
      disabled={isRunning}
      onClick={handleRunNow}
    >
      {isRunning ? <Spinner size="tiny" /> : "Run"}
    </Button>
  ) : (
    <>
      <Button
        size="small"
        appearance="subtle"
        title="Run all of the Toolkit's tests on this machine now"
        disabled={isRunning}
        onClick={handleRunNow}
      >
        {isRunning ? <Spinner size="tiny" /> : "Run"}
      </Button>
      <RefreshButton onClick={refetch} isFetching={isFetching} />
    </>
  );

  const emptyMessage: EmptyMessage | undefined = isError
    ? {
        icon: <BeakerRegular />,
        tone: "error",
        title: "Could not load the test history",
        detail: "The agent did not answer. Nothing was read.",
        action: (
          <Button size="small" appearance="primary" onClick={refetch}>
            Try again
          </Button>
        ),
      }
    : !hasData
      ? {
          icon: <BeakerRegular />,
          title: "No test runs recorded yet",
          detail:
            "Press Run above, or run the Toolkit's tests from a terminal. Each run lands here.",
        }
      : undefined;

  return (
    <PageCard
      className={styles.card}
      loading={isLoading}
      loadingLabel="Loading test history..."
      headerLeft={headerLeft}
      headerRight={headerRight}
      empty={emptyMessage ? <EmptyState {...emptyMessage} /> : undefined}
    >
      {hasData && (
        <>
          {/* Summary tiles */}
          <StatTiles>
            <StatTile
              count={`${totalPassed}/${totalTotal}`}
              label="Passed"
              color={
                allGreen
                  ? tokens.colorPaletteGreenForeground1
                  : anyFail
                    ? tokens.colorPaletteRedForeground1
                    : tokens.colorPaletteDarkOrangeForeground1
              }
            />
            <StatTile count={data?.streak ?? 0} label="Day streak" />
          </StatTiles>

          {/* The machine's three halves, from its test summary: what
              `Test` last ran for the agent, the CLI and the web UI. */}
          {halves.length > 0 && (
            <StatTiles>
              {halves.map((h) => (
                <Tooltip key={h.half} content={h.detail} relationship="description" withArrow>
                  <StatTile
                    count={h.count}
                    label={h.label}
                    data-half={h.half}
                    color={
                      h.tone === "pass"
                        ? tokens.colorPaletteGreenForeground1
                        : h.tone === "fail"
                          ? tokens.colorPaletteRedForeground1
                          : tokens.colorPaletteDarkOrangeForeground1
                    }
                  />
                </Tooltip>
              ))}
            </StatTiles>
          )}

          <ChartWrapper>
            <div className={styles.chartArea}>
              {chartData.length > 0 ? (
                <ResponsiveContainer width="100%" height={128}>
                  <BarChart data={chartData}>
                    <defs>
                      <linearGradient id="hgPass" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor={chartColors.pass} stopOpacity={topOp} />
                        <stop offset="100%" stopColor={chartColors.pass} stopOpacity={botOp} />
                      </linearGradient>
                      <linearGradient id="hgFail" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor={chartColors.fail} stopOpacity={topOp} />
                        <stop offset="100%" stopColor={chartColors.fail} stopOpacity={botOp} />
                      </linearGradient>
                    </defs>
                    <XAxis
                      dataKey="label"
                      tick={{ fontSize: 10 }}
                      interval={0}
                      angle={-45}
                      textAnchor="end"
                      height={34}
                    />
                    <YAxis tick={{ fontSize: 10 }} width={30} height={128} allowDecimals={false} />
                    <RechartsTooltip
                      content={<ChartTooltipContent />}
                      cursor={{ fill: "transparent" }}
                    />
                    <Bar dataKey="pass" stackId="a" fill="url(#hgPass)" radius={[0, 0, 0, 0]} />
                    <Bar dataKey="fail" stackId="a" fill="url(#hgFail)" radius={[2, 2, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <Caption1 style={{ display: "block", textAlign: "center", paddingTop: "2rem" }}>
                  No test runs recorded yet -- press Run above, or run the Toolkit&apos;s tests from
                  a terminal.
                </Caption1>
              )}
            </div>
          </ChartWrapper>

          {/* Suite results grid */}
          <div className={styles.scrollArea}>
            {latestDay && latestDay.suites.length > 0 ? (
              latestDay.suites.map((s) => (
                <div key={s.suite} className={styles.suiteRow}>
                  <span className={styles.suiteIcon}>
                    {s.result === "pass" ? (
                      <CheckmarkCircleRegular
                        style={{ color: tokens.colorPaletteGreenForeground1 }}
                      />
                    ) : s.result === "warn" ? (
                      <WarningRegular style={{ color: tokens.colorPaletteDarkOrangeForeground1 }} />
                    ) : (
                      <DismissCircleRegular style={{ color: tokens.colorPaletteRedForeground1 }} />
                    )}
                  </span>
                  <Tooltip content={s.description || s.suite} relationship="description" withArrow>
                    <Body1 className={styles.suiteName}>{s.suite}</Body1>
                  </Tooltip>
                  <Caption1 className={styles.suiteCount}>
                    {s.passed}/{s.total}
                  </Caption1>
                  <Badge
                    color={
                      s.result === "pass" ? "success" : s.result === "warn" ? "warning" : "danger"
                    }
                    appearance="filled"
                    size="small"
                  >
                    {s.result === "pass" ? "Pass" : s.result === "warn" ? "Skip" : "Fail"}
                  </Badge>
                </div>
              ))
            ) : (
              <Caption1 style={{ display: "block", padding: tokens.spacingVerticalS }}>
                The last run recorded no suites.
              </Caption1>
            )}
          </div>

          <HairlineDivider />

          <Caption1>
            {data?.machine ?? "—"}
            {" | Last run "}
            {formatLastRun(data?.last_run ?? null)}
            {data?.active_space && `, in the ${data.active_space} Space`}
          </Caption1>
        </>
      )}
    </PageCard>
  );
}
