import { tokens } from "@fluentui/react-components";
import { ScatterChart, Scatter, XAxis, YAxis, ZAxis, Tooltip as RTooltip } from "recharts";
import { ContentFlexFillWrapper } from "../../shared/ContentFlexFillWrapper";
import { useChartColors } from "../../hooks/chartPalette";
import { useWornTheme } from "../../hooks/useWornTheme";
import { useGetSprintActivityQuery } from "./api.ado";
import type { SprintActivityEntry, SprintActivityResponse } from "./api.ado";
import { localDay } from "../../utility/dates";

const SERIES = ["mine", "team"] as const;
const SERIES_LABELS: Record<string, string> = { mine: "Mine", team: "Team" };

interface ScatterPoint {
  x: number;
  y: number;
  z: number;
  date: string;
  label: string;
  series: string;
  matches: boolean;
}

function buildScatterData(
  startDate: string,
  endDate: string,
  mine: SprintActivityEntry[],
  team: SprintActivityEntry[],
  selectedDate: string,
): { points: ScatterPoint[]; dayLabels: string[] } {
  const mineMap = new Map(mine.map((d) => [d.date, d.count]));
  const teamMap = new Map(team.map((d) => [d.date, d.count]));
  const start = new Date(startDate + "T00:00:00");
  const end = new Date(endDate + "T00:00:00");
  const dayLabels: string[] = [];
  const points: ScatterPoint[] = [];
  const cursor = new Date(start);

  while (cursor <= end) {
    const dateStr = localDay(cursor);
    const label = cursor.toLocaleString("default", { weekday: "short", day: "numeric" });
    const dayIdx = dayLabels.length;
    dayLabels.push(label);
    const mineCount = mineMap.get(dateStr) ?? 0;
    const teamCount = teamMap.get(dateStr) ?? 0;
    if (mineCount > 0) {
      points.push({
        x: dayIdx,
        y: 0,
        z: mineCount,
        date: dateStr,
        label,
        series: "mine",
        matches: dateStr === selectedDate,
      });
    }
    if (teamCount > 0) {
      points.push({
        x: dayIdx,
        y: 1,
        z: teamCount,
        date: dateStr,
        label,
        series: "team",
        matches: dateStr === selectedDate,
      });
    }
    cursor.setDate(cursor.getDate() + 1);
  }

  return { points, dayLabels };
}

function BubbleShape(props: { cx?: number; cy?: number; payload?: ScatterPoint }) {
  const { cx = 0, cy = 0, payload } = props;
  if (!payload || payload.z === 0) return null;
  const r = Math.sqrt(payload.z) * 8;
  return (
    <circle
      cx={cx}
      cy={cy}
      r={r}
      fill={`url(#sv-rg-${payload.series})`}
      opacity={payload.matches ? 1 : 0.15}
      stroke="none"
    />
  );
}

function BubbleTooltip({
  active,
  payload,
}: {
  active?: boolean;
  payload?: Array<{ payload: ScatterPoint }>;
}) {
  if (!active || !payload?.length) return null;
  const p = payload[0].payload;
  return (
    <div
      style={{
        background: "rgba(0, 0, 0, 0.3)",
        backdropFilter: "blur(4px)",
        border: `1px solid ${tokens.colorNeutralStroke1}`,
        borderRadius: 4,
        padding: "6px 10px",
        fontSize: 12,
        color: tokens.colorNeutralForeground1,
      }}
    >
      <strong>{p.label}</strong>
      <div>
        {SERIES_LABELS[p.series]}: {p.z}
      </div>
    </div>
  );
}

export function SprintDayScatterChart({
  selectedDate,
  repo,
  activityOverride,
}: {
  selectedDate: string;
  repo?: string;
  activityOverride?: SprintActivityResponse;
}) {
  const colors = useChartColors();
  const { theme } = useWornTheme();
  const { data: fetched } = useGetSprintActivityQuery(repo, { skip: !!activityOverride });
  const activity = activityOverride ?? fetched;

  const topOp = theme === "dark" ? 0.85 : 0.95;
  const botOp = theme === "dark" ? 0.35 : 0.6;

  const seriesColors: Record<string, string> = {
    mine: colors.billingBar,
    team: colors.billingAvg,
  };

  const { points, dayLabels } = activity
    ? buildScatterData(
        activity.startDate,
        activity.endDate,
        activity.mine,
        activity.team,
        selectedDate,
      )
    : { points: [], dayLabels: [] };

  const chartWidth = Math.max(300, dayLabels.length * 52 + 48);

  return (
    <ContentFlexFillWrapper>
      <div style={{ overflowX: "auto", width: "100%" }}>
        <ScatterChart
          width={chartWidth}
          height={200}
          margin={{ top: 12, right: 16, bottom: 8, left: 0 }}
        >
          <defs>
            {SERIES.map((s) => (
              <radialGradient key={s} id={`sv-rg-${s}`} cx="35%" cy="35%" r="65%">
                <stop
                  offset="0%"
                  stopColor={seriesColors[s]}
                  stopOpacity={Math.min(topOp + 0.1, 1)}
                />
                <stop offset="100%" stopColor={seriesColors[s]} stopOpacity={botOp} />
              </radialGradient>
            ))}
          </defs>
          <XAxis
            dataKey="x"
            type="number"
            domain={[-0.5, dayLabels.length - 0.5]}
            ticks={dayLabels.map((_, i) => i)}
            tickFormatter={(i: number) => dayLabels[i] ?? ""}
            tick={{ fontSize: 10 }}
            axisLine={false}
            tickLine={false}
          />
          <YAxis
            dataKey="y"
            type="number"
            domain={[-0.5, SERIES.length - 0.5]}
            ticks={SERIES.map((_, i) => i)}
            tickFormatter={(i: number) => SERIES_LABELS[SERIES[i]] ?? ""}
            tick={{ fontSize: 10 }}
            axisLine={false}
            tickLine={false}
            width={40}
          />
          <ZAxis dataKey="z" range={[0, 1]} />
          <RTooltip content={<BubbleTooltip />} />
          <Scatter
            data={points}
            shape={(p: object) => <BubbleShape {...(p as Parameters<typeof BubbleShape>[0])} />}
          />
        </ScatterChart>
      </div>
    </ContentFlexFillWrapper>
  );
}
