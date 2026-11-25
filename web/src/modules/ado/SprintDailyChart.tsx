import { tokens } from "@fluentui/react-components";
import { BarChart, Bar, XAxis, YAxis, Tooltip as RTooltip, ResponsiveContainer } from "recharts";
import { ContentFlexFillWrapper } from "../../shared/ContentFlexFillWrapper";
import { useChartColors } from "../../hooks/chartPalette";
import { useWornTheme } from "../../hooks/useWornTheme";
import { useGetSprintActivityQuery } from "./api.ado";
import type { SprintActivityResponse } from "./api.ado";
import { SPRINT_WORDS, buildSprintBars } from "./sprintActivity";
import type { SprintBar } from "./sprintActivity";

// The tooltip states the record as it has it: my commits, and the team's total
// (which includes mine) -- not the two drawn parts of the bar.
export function ChartTooltipContent({
  active,
  payload,
}: {
  active?: boolean;
  payload?: Array<{ payload: SprintBar }>;
}) {
  if (!active || !payload?.length) return null;
  const { label, mine, team } = payload[0].payload;
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
          Team: {team} commit{team !== 1 ? "s" : ""}
        </div>
      )}
    </div>
  );
}

/** What the chart draws, for a screen reader: one bar a day, the team's total in two parts. */
export const SPRINT_CHART_DESCRIPTION = `Commits per day. Each bar is the ${SPRINT_WORDS.team} for the day, drawn as ${SPRINT_WORDS.mine} and the ${SPRINT_WORDS.rest}.`;

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
    ? buildSprintBars(activity.startDate, activity.endDate, activity.mine, activity.team)
    : [];

  const topOp = theme === "dark" ? 0.72 : 0.42;
  const botOp = theme === "dark" ? 0.28 : 0.14;

  return (
    <ContentFlexFillWrapper>
      <div role="img" aria-label={SPRINT_CHART_DESCRIPTION} style={{ width: "100%" }}>
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
            <Bar dataKey="rest" stackId="a" fill="url(#svTeam)" radius={[2, 2, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </ContentFlexFillWrapper>
  );
}
