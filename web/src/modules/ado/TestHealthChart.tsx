import { useMemo } from "react";
import { Caption1, makeStyles, tokens } from "@fluentui/react-components";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip as RechartsTooltip,
  ResponsiveContainer,
} from "recharts";
import type { TestDay } from "./api.ado";
import { useChartColors } from "../../hooks/chartPalette";
import { useWornTheme } from "../../hooks/useWornTheme";
import { ChartWrapper } from "../../shared/ChartWrapper";
import { countAxisWidth, countTicks, formatCount } from "../../shared/formatCount";

// Test Health's chart: passes and failures by day. Its own file, like the Log's
// LogTypeChart, so the panel file fills ListPanel's slots and draws nothing.

const useStyles = makeStyles({
  chartArea: {
    maxHeight: "150px",
    paddingTop: tokens.spacingVerticalS,
    flexShrink: 0,
  },
});

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
      <div style={{ color: tokens.colorPaletteGreenForeground1 }}>Pass: {formatCount(pass)}</div>
      {fail > 0 && (
        <div style={{ color: tokens.colorPaletteRedForeground1 }}>Fail: {formatCount(fail)}</div>
      )}
    </div>
  );
}

export function TestHealthChart({ days }: { days: TestDay[] }) {
  const styles = useStyles();
  const chartColors = useChartColors();
  const { theme } = useWornTheme();
  const topOp = theme === "dark" ? 0.72 : 0.42;
  const botOp = theme === "dark" ? 0.28 : 0.14;
  const chartData = useMemo(() => buildChartData(days), [days]);
  // The y-axis is given its ticks, so it can be as wide as its widest label (formatCount.ts).
  const yTicks = useMemo(
    () => countTicks(chartData.reduce((m, d) => Math.max(m, d.pass + d.fail), 0)),
    [chartData],
  );
  return (
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
              <YAxis
                tick={{ fontSize: 10 }}
                width={countAxisWidth(yTicks, 10)}
                height={128}
                allowDecimals={false}
                ticks={yTicks}
                domain={[0, yTicks[yTicks.length - 1]]}
                tickFormatter={(v: number) => formatCount(v)}
              />
              <RechartsTooltip content={<ChartTooltipContent />} cursor={{ fill: "transparent" }} />
              <Bar dataKey="pass" stackId="a" fill="url(#hgPass)" radius={[0, 0, 0, 0]} />
              <Bar dataKey="fail" stackId="a" fill="url(#hgFail)" radius={[2, 2, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        ) : (
          <Caption1 style={{ display: "block", textAlign: "center", paddingTop: "2rem" }}>
            No test runs recorded yet -- press Run above, or run the Toolkit&apos;s tests from a
            terminal.
          </Caption1>
        )}
      </div>
    </ChartWrapper>
  );
}
