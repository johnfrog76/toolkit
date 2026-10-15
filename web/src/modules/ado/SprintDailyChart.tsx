import { tokens } from "@fluentui/react-components";
import { BarChart, Bar, XAxis, YAxis, Tooltip as RTooltip, ResponsiveContainer } from "recharts";
import { ContentFlexFillWrapper } from "../../shared/ContentFlexFillWrapper";
import { useChartColors } from "../../hooks/chartPalette";
import { useWornTheme } from "../../hooks/useWornTheme";
import { useGetSprintActivityQuery } from "./api.ado";
import type { SprintActivityEntry, SprintActivityResponse } from "./api.ado";
import { localDay } from "../../utility/dates";

interface VelocityBar {
  label: string;
  mine: number;
  team: number;
}

function buildChartData(
  startDate: string,
  endDate: string,
  mine: SprintActivityEntry[],
  team: SprintActivityEntry[],
): VelocityBar[] {
  const mineMap = new Map(mine.map((d) => [d.date, d.count]));
  const teamMap = new Map(team.map((d) => [d.date, d.count]));
  const start = new Date(startDate + "T00:00:00");
  const end = new Date(endDate + "T00:00:00");
  const bars: VelocityBar[] = [];
  const cursor = new Date(start);
  while (cursor <= end) {
    const dateStr = localDay(cursor);
    bars.push({
      label: cursor.toLocaleString("default", { weekday: "short", day: "numeric" }),
      mine: mineMap.get(dateStr) ?? 0,
      team: teamMap.get(dateStr) ?? 0,
    });
    cursor.setDate(cursor.getDate() + 1);
  }
  return bars;
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
  const mine = payload.find((p) => p.dataKey === "mine")?.value ?? 0;
  const team = payload.find((p) => p.dataKey === "team")?.value ?? 0;
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
      <div style={{ fontWeight: 600 }}>{label}</div>
      {mine > 0 && (
        <div>
          Mine: {mine} commit{mine !== 1 ? "s" : ""}
        </div>
      )}
      {team > 0 && (
        <div>
          Team: {team} merge{team !== 1 ? "s" : ""}
        </div>
      )}
    </div>
  );
}

export function SprintDailyChart({
  repo,
  activityOverride,
}: { repo?: string; activityOverride?: SprintActivityResponse } = {}) {
  const colors = useChartColors();
  const { theme } = useWornTheme();
  // A frozen deck snapshot (activityOverride) short-circuits the live query so
  // the slide never drifts as sprints roll over.
  const { data: fetched } = useGetSprintActivityQuery(repo, { skip: !!activityOverride });
  const activity = activityOverride ?? fetched;

  const chartData = activity
    ? buildChartData(activity.startDate, activity.endDate, activity.mine, activity.team)
    : [];

  const topOp = theme === "dark" ? 0.72 : 0.42;
  const botOp = theme === "dark" ? 0.28 : 0.14;

  return (
    <ContentFlexFillWrapper>
      <ResponsiveContainer width="100%" height={128}>
        <BarChart data={chartData}>
          <defs>
            <linearGradient id="svMine" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={colors.billingBar} stopOpacity={topOp} />
              <stop offset="100%" stopColor={colors.billingBar} stopOpacity={botOp} />
            </linearGradient>
            <linearGradient id="svTeam" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={colors.billingAvg} stopOpacity={topOp} />
              <stop offset="100%" stopColor={colors.billingAvg} stopOpacity={botOp} />
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
          <YAxis tick={{ fontSize: 10 }} width={30} allowDecimals={false} />
          <RTooltip content={<ChartTooltipContent />} cursor={{ fill: "transparent" }} />
          <Bar dataKey="mine" stackId="a" fill="url(#svMine)" radius={[0, 0, 0, 0]} />
          <Bar dataKey="team" stackId="a" fill="url(#svTeam)" radius={[2, 2, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </ContentFlexFillWrapper>
  );
}
