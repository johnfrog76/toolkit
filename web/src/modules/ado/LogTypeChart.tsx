import { useMemo } from "react";
import { makeStyles, tokens } from "@fluentui/react-components";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip as RechartsTooltip,
  ResponsiveContainer,
} from "recharts";
import { useChartColors } from "../../hooks/chartPalette";
import { useWornTheme } from "../../hooks/useWornTheme";
import { ChartWrapper } from "../../shared/ChartWrapper";
import type { LogEntry } from "./api.ado";
import { buildChartData } from "./logChart";

// The Log panel's lead: the entries by day and type, stacked.
const useStyles = makeStyles({
  chartArea: {
    minHeight: "120px",
  },
});

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

export function LogTypeChart({ entries }: { entries: LogEntry[] }) {
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
