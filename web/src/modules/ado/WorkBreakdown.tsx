import { useState, useRef, useEffect } from "react";
import { Badge, Subtitle2, Dropdown, Option, tokens } from "@fluentui/react-components";
import { Tooltip as RTooltip, ScatterChart, Scatter, XAxis, YAxis, ZAxis } from "recharts";
import { PageCard } from "../../shared/PageCard";
import { ChartWrapper } from "../../shared/ChartWrapper";
import { useChartColors } from "../../hooks/chartPalette";
import { useWornTheme } from "../../hooks/useWornTheme";
import { useGetEngagementWorkBreakdownQuery } from "./api.ado";
import type { WorkBreakdownSprintEntry } from "./api.ado";

const SCATTER_TYPES = ["bug", "story", "feature", "task"] as const;

const TYPE_LABELS: Record<string, string> = {
  bug: "Bugs",
  story: "User Stories",
  feature: "Features",
  task: "Tasks",
};

const ALL = "All";
const SPRINT_WIDTH = 52; // px per sprint column
const LEFT_MARGIN = 80; // room for Y-axis labels

interface BubblePoint {
  x: number;
  y: number;
  z: number;
  sprint: string;
  type: string;
  matches: boolean;
}

function BubbleTooltip({
  active,
  payload,
}: {
  active?: boolean;
  payload?: Array<{ payload: BubblePoint }>;
}) {
  if (!active || !payload?.length) return null;
  const p = payload[0].payload;
  return (
    <div
      style={{
        background: tokens.colorNeutralBackground1,
        border: `1px solid ${tokens.colorNeutralStroke2}`,
        borderRadius: 4,
        padding: "4px 8px",
        fontSize: 12,
        color: tokens.colorNeutralForeground1,
      }}
    >
      <strong>{p.sprint}</strong>
      <br />
      {TYPE_LABELS[p.type]}: {p.z}
    </div>
  );
}

function BubbleShape(props: { cx?: number; cy?: number; payload?: BubblePoint }) {
  const { cx = 0, cy = 0, payload } = props;
  if (!payload || payload.z === 0) return null;
  const r = Math.sqrt(payload.z) * 6;
  return (
    <circle
      cx={cx}
      cy={cy}
      r={r}
      fill={`url(#rg-${payload.type})`}
      opacity={payload.matches ? 1 : 0.15}
      stroke="none"
    />
  );
}

export function WorkBreakdown({ slug, activeTag }: { slug: string; activeTag?: string | null }) {
  const colors = useChartColors();
  const { theme } = useWornTheme();
  const { data, isLoading, isError } = useGetEngagementWorkBreakdownQuery(slug);
  const [selectedSprint, setSelectedSprint] = useState(ALL);
  const containerRef = useRef<HTMLDivElement>(null);
  const [containerWidth, setContainerWidth] = useState(0);

  useEffect(() => {
    const updateWidth = () => {
      if (containerRef.current) {
        setContainerWidth(containerRef.current.clientWidth);
      }
    };

    // Trigger initial measurement after a frame to ensure layout is ready
    const timeoutId = setTimeout(updateWidth, 100);

    window.addEventListener("resize", updateWidth);
    return () => {
      clearTimeout(timeoutId);
      window.removeEventListener("resize", updateWidth);
    };
  }, []);

  if (isLoading)
    return (
      <PageCard
        loading
        loadingLabel="Loading work breakdown…"
        headerLeft={<Subtitle2>Work Breakdown</Subtitle2>}
      />
    );
  if (isError || !data) return null;

  const topOp = theme === "dark" ? 0.85 : 0.95;
  const botOp = theme === "dark" ? 0.35 : 0.6;

  const typeColors: Record<string, string> = {
    bug: colors.bug,
    story: colors.story,
    feature: colors.feature,
    task: colors.task,
  };

  const allSprints = data.bySprint.filter((s) => s.bug + s.story + s.feature + s.task > 0);
  const visibleSprints =
    selectedSprint === ALL ? allSprints : allSprints.filter((s) => s.sprint === selectedSprint);

  const total = Object.values(data.byType).reduce((a, b) => a + b, 0);
  if (total === 0) return null;

  const tagLower = activeTag?.toLowerCase() ?? null;

  const bubbleData: BubblePoint[] = visibleSprints.flatMap((s, sprintIdx) =>
    SCATTER_TYPES.map((type, typeIdx) => ({
      x: sprintIdx,
      y: typeIdx,
      z: s[type as keyof WorkBreakdownSprintEntry] as number,
      sprint: s.sprint,
      type,
      matches:
        tagLower === null ||
        TYPE_LABELS[type].toLowerCase().includes(tagLower) ||
        type.includes(tagLower),
    })).filter((p) => p.z > 0),
  );

  const chartWidth = Math.max(
    containerWidth,
    LEFT_MARGIN + visibleSprints.length * SPRINT_WIDTH + 16,
  );
  const chartHeight = 180;

  return (
    <PageCard
      headerLeft={<Subtitle2>Work</Subtitle2>}
      headerRight={
        <>
          {allSprints.length > 0 && (
            <Dropdown
              size="small"
              value={selectedSprint}
              selectedOptions={[selectedSprint]}
              onOptionSelect={(_e, d) => setSelectedSprint(d.optionValue as string)}
              style={{ minWidth: "110px" }}
            >
              <Option value={ALL} text={ALL}>
                {ALL}
              </Option>
              {allSprints.map((s) => (
                <Option key={s.sprint} value={s.sprint} text={s.sprint}>
                  {s.sprint}
                </Option>
              ))}
            </Dropdown>
          )}
          <Badge appearance="tint" color="subtle">
            {total}
          </Badge>
        </>
      }
    >
      <ChartWrapper>
        <div style={{ overflowX: "auto", width: "100%" }} ref={containerRef}>
          <ScatterChart
            width={chartWidth}
            height={chartHeight}
            margin={{ top: 12, right: 16, bottom: 8, left: 0 }}
          >
            <defs>
              {SCATTER_TYPES.map((type) => (
                <radialGradient key={type} id={`rg-${type}`} cx="35%" cy="35%" r="65%">
                  <stop
                    offset="0%"
                    stopColor={typeColors[type]}
                    stopOpacity={Math.min(topOp + 0.1, 1)}
                  />
                  <stop offset="100%" stopColor={typeColors[type]} stopOpacity={botOp} />
                </radialGradient>
              ))}
            </defs>
            <XAxis
              dataKey="x"
              type="number"
              domain={[-0.5, visibleSprints.length - 0.5]}
              ticks={visibleSprints.map((_, i) => i)}
              tickFormatter={(i: number) => visibleSprints[i]?.sprint ?? ""}
              tick={{ fontSize: 10 }}
              axisLine={false}
              tickLine={false}
            />
            <YAxis
              dataKey="y"
              type="number"
              domain={[-0.5, SCATTER_TYPES.length - 0.5]}
              ticks={SCATTER_TYPES.map((_, i) => i)}
              tickFormatter={(i: number) => TYPE_LABELS[SCATTER_TYPES[i]] ?? ""}
              tick={{ fontSize: 10 }}
              axisLine={false}
              tickLine={false}
              width={LEFT_MARGIN}
            />
            <ZAxis dataKey="z" range={[0, 1]} />
            <RTooltip content={<BubbleTooltip />} />
            <Scatter
              data={bubbleData}
              shape={(p: object) => <BubbleShape {...(p as Parameters<typeof BubbleShape>[0])} />}
            />
          </ScatterChart>
        </div>
      </ChartWrapper>
    </PageCard>
  );
}
