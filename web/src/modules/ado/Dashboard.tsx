import { useEffect, useState, useId } from "react";
import { Badge, Button, Caption1, Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { RefreshButton } from "../../shared/RefreshButton";
import { FilterBadge } from "../../shared/FilterBadge";
import { PageCard } from "../../shared/PageCard";
import {
  OpenRegular,
  CheckmarkCircleRegular,
  DismissCircleRegular,
  ClockRegular,
  SubtractCircleRegular,
  WarningRegular,
} from "@fluentui/react-icons";
import { PieChart, Pie, Cell, Tooltip as RTooltip, ResponsiveContainer } from "recharts";
import { HairlineDivider } from "../../shared/HairlineDivider";
import { useChartColors } from "../../hooks/chartPalette";
import { useWornTheme } from "../../hooks/useWornTheme";
import { getProjectTag } from "../../utility/abbreviate";
import { useGetDashboardQuery, useGetDashboardPipelinesQuery } from "./api.ado";
import { useGetEnvQuery } from "../../shell/api";
import { envBadge } from "./envBadge";
import type { PipelineRun } from "./api.ado";
import { DataTrendingRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { dueLabel } from "../../utility/dates";

const useStyles = makeStyles({
  repoTabs: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap" as const,
    marginBottom: tokens.spacingVerticalS,
    flexShrink: 0,
  },
  activeTitle: {
    marginTop: tokens.spacingVerticalXS,
    marginBottom: tokens.spacingVerticalS,
  },
  scrollArea: {
    minWidth: 0,
  },
  runRow: {
    display: "grid",
    gridTemplateColumns: "auto auto 30% 1fr auto auto",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    paddingTop: "4px",
    paddingBottom: "4px",
    minWidth: 0,
  },
  runIcon: {
    display: "flex",
    alignItems: "center",
  },
  runName: {
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap" as const,
    minWidth: 0,
  },
  runBranch: {
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap" as const,
    minWidth: 0,
  },
  runTime: {
    textAlign: "right" as const,
    whiteSpace: "nowrap" as const,
  },
  pipelineChart: {
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    gap: tokens.spacingHorizontalM,
    padding: "1.5rem",
  },
  pieLegend: {
    display: "flex",
    flexDirection: "column",
    gap: "2px",
  },
  legendRow: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalXS,
  },
  legendSwatch: {
    width: "10px",
    height: "10px",
    borderRadius: "2px",
    display: "inline-block",
    flexShrink: 0,
  },
  toggleBtn: {
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    width: "24px",
    height: "24px",
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusCircular,
    backgroundColor: "transparent",
    cursor: "pointer",
    fontSize: "14px",
    fontWeight: 600,
    lineHeight: 1,
    color: tokens.colorNeutralForeground2,
    marginTop: tokens.spacingVerticalXS,
    "&:hover": {
      backgroundColor: tokens.colorNeutralBackground1Hover,
    },
  },
  footer: {
    display: "flex",
    gap: tokens.spacingHorizontalL,
    flexWrap: "wrap" as const,
    paddingTop: tokens.spacingVerticalS,
    alignItems: "center",
    flexShrink: 0,
    borderTop: `1px solid ${tokens.colorNeutralStroke2}`,
    marginTop: tokens.spacingVerticalS,
  },
  footerItem: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalXS,
  },
});

function resultBadgeColor(
  result: string,
): "success" | "danger" | "warning" | "informative" | "important" {
  if (result === "succeeded") return "success";
  if (result === "failed") return "danger";
  if (result === "partiallySucceeded") return "warning";
  if (result === "canceled") return "important";
  return "informative";
}

function resultIcon(result: string) {
  if (result === "succeeded") return <CheckmarkCircleRegular />;
  if (result === "failed") return <DismissCircleRegular />;
  if (result === "canceled") return <SubtractCircleRegular />;
  if (result === "partiallySucceeded") return <WarningRegular />;
  return <ClockRegular />;
}

function resultLabel(result: string): string {
  if (result === "succeeded") return "Pass";
  if (result === "failed") return "Fail";
  if (result === "canceled") return "Canceled";
  if (result === "partiallySucceeded") return "Partial";
  return "Running";
}

function formatFinished(iso: string | null): string {
  if (!iso) return "Running...";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// The agent sends the last commit as local "YYYY-MM-DD HH:MM (author)"
// (agent/ado/accounting.py, on the reader's clock). Read through the one date
// helper, so it says WHICH day as well as the time: "Today 4:07 PM".
function formatCommitTime(raw: string): string {
  const m = /^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2})/.exec(raw);
  return (m && dueLabel(`${m[1]}T${m[2]}`)) || raw;
}

function resultGroupColor(result: string, palette: Record<string, string>): string {
  return palette[result] ?? palette.running;
}

interface PieSlice {
  name: string;
  result: string;
  count: number;
  pct: number;
}

function PieTooltipContent({
  active,
  payload,
}: {
  active?: boolean;
  payload?: Array<{ payload: PieSlice }>;
}) {
  if (!active || !payload?.length) return null;
  const d = payload[0].payload;
  return (
    <div
      style={{
        background: tokens.colorNeutralBackground1,
        border: `1px solid ${tokens.colorNeutralStroke2}`,
        borderRadius: 4,
        padding: "4px 8px",
        fontSize: 12,
      }}
    >
      {d.name}: {d.count} ({d.pct}%)
    </div>
  );
}

export function PipelineChart({ runs }: { runs: PipelineRun[] }) {
  const styles = useStyles();
  const palette = useChartColors();
  const { theme } = useWornTheme();
  const uid = useId();

  const topOp = theme === "dark" ? 0.95 : 1.0;
  const botOp = theme === "dark" ? 0.35 : 0.6;

  const counts: Record<string, number> = {};
  for (const r of runs) {
    const key = r.result || "running";
    counts[key] = (counts[key] || 0) + 1;
  }
  const total = runs.length;
  const slices: PieSlice[] = Object.entries(counts).map(([result, count]) => ({
    name: resultLabel(result),
    result,
    count,
    pct: Math.round((count / total) * 100),
  }));

  return (
    <div className={styles.pipelineChart}>
      <div style={{ width: 96, height: 96, flexShrink: 0 }}>
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <defs>
              {slices.map((s) => (
                <radialGradient
                  key={s.result}
                  id={`${uid}-rg-${s.result}`}
                  cx="33"
                  cy="33"
                  r="55"
                  gradientUnits="userSpaceOnUse"
                >
                  <stop
                    offset="0%"
                    stopColor={resultGroupColor(s.result, palette)}
                    stopOpacity={topOp}
                  />
                  <stop
                    offset="100%"
                    stopColor={resultGroupColor(s.result, palette)}
                    stopOpacity={botOp}
                  />
                </radialGradient>
              ))}
            </defs>
            <Pie
              data={slices}
              dataKey="count"
              cx="50%"
              cy="50%"
              innerRadius={24}
              outerRadius={45}
              strokeWidth={1}
              stroke={tokens.colorNeutralBackground1}
            >
              {slices.map((s) => (
                <Cell key={s.result} fill={`url(#${uid}-rg-${s.result})`} />
              ))}
            </Pie>
            <RTooltip content={<PieTooltipContent />} />
          </PieChart>
        </ResponsiveContainer>
      </div>
      <div className={styles.pieLegend}>
        {slices.map((s) => (
          <div key={s.result} className={styles.legendRow}>
            <span
              className={styles.legendSwatch}
              style={{
                background: `radial-gradient(circle at 35% 35%, ${resultGroupColor(s.result, palette)}, color-mix(in srgb, ${resultGroupColor(s.result, palette)} 55%, transparent))`,
              }}
            />
            <Caption1>
              {s.name} {s.pct}%
            </Caption1>
          </div>
        ))}
        <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>{total} runs</Caption1>
      </div>
    </div>
  );
}

const VISIBLE_ROWS = 3;

export function Dashboard() {
  const styles = useStyles();
  const { data, isLoading, isFetching, refetch } = useGetDashboardQuery();
  const { data: env } = useGetEnvQuery();
  // A tab is a project+repo pair — one ADO project can host several repos, so
  // project name alone is not a unique tab identity.
  const [activeTab, setActiveTab] = useState<{ project: string; repo: string } | null>(null);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    if (data?.projects.length && !activeTab) {
      const first = data.projects[0];
      setActiveTab({ project: first.project, repo: first.repo }); //eslint-disable-line react-hooks/set-state-in-effect
    }
  }, [data, activeTab]);

  // Lazy per-tab pipeline fetch: only the active tab's runs are requested,
  // and RTK Query caches each project+repo result independently, so switching
  // back to a previously-viewed tab is free (no re-fetch).
  const {
    data: activeProj,
    isLoading: pipelinesLoading,
    isFetching: pipelinesFetching,
  } = useGetDashboardPipelinesQuery(activeTab ?? { project: "", repo: "" }, {
    skip: !activeTab,
  });

  // Waits for /env too: without the org's status a local org would flash "Offline".
  const badge =
    data && env
      ? envBadge({ tier: data.tier, spaceStatus: env.spaceStatus, tracker: env.tracker })
      : null;

  return (
    <PageCard
      headerLeft={
        <>
          <Subtitle2>Build</Subtitle2>
          {/* The Environment card's word and colour, not a second copy of the
              rule: this hard-coded "Local" in yellow for any org below Tier 1. */}
          {badge && (
            <Badge color={badge.color} appearance="filled" size="small">
              {badge.label}
            </Badge>
          )}
        </>
      }
      headerRight={
        <RefreshButton
          onClick={refetch}
          isFetching={isFetching && !isLoading}
          disabled={isLoading || isFetching}
        />
      }
      loading={isLoading || isFetching}
      loadingLabel="Loading dashboard..."
      empty={
        !data ? (
          <EmptyState
            icon={<DataTrendingRegular />}
            tone="error"
            title="Could not load the dashboard"
            detail="Azure DevOps did not answer. Nothing was read."
          />
        ) : undefined
      }
    >
      {data && (
        <>
          {/* ── Repo Tabs ──────────────────────────────────── */}
          {data.projects.length > 0 && (
            <div className={styles.repoTabs}>
              {data.projects.map((proj) => (
                <FilterBadge
                  key={`${proj.project}/${proj.repo}`}
                  label={`${getProjectTag(proj.project)} / ${proj.repo}`}
                  active={activeTab?.project === proj.project && activeTab?.repo === proj.repo}
                  onClick={() => {
                    setActiveTab({ project: proj.project, repo: proj.repo });
                    setExpanded(false);
                  }}
                />
              ))}
            </div>
          )}

          {/* ── Active Repo Content ────────────────────────── */}
          {pipelinesLoading || pipelinesFetching ? (
            <Caption1
              style={{ color: tokens.colorNeutralForeground3, marginTop: tokens.spacingVerticalS }}
            >
              Loading builds...
            </Caption1>
          ) : activeProj ? (
            <>
              <Subtitle2 className={styles.activeTitle}>
                {activeProj.project} &mdash; {activeProj.repo}
              </Subtitle2>

              <PipelineChart runs={activeProj.runs} />

              <HairlineDivider />

              <div className={styles.scrollArea}>
                {(expanded ? activeProj.runs : activeProj.runs.slice(0, VISIBLE_ROWS)).map((r) => (
                  <div key={r.build_id} className={styles.runRow}>
                    <span className={styles.runIcon}>{resultIcon(r.result)}</span>
                    <Badge
                      color={resultBadgeColor(r.result)}
                      appearance="tint"
                      size="small"
                      style={{ whiteSpace: "nowrap" }}
                    >
                      {resultLabel(r.result)}
                    </Badge>
                    <Caption1 className={styles.runName}>{r.pipeline_name}</Caption1>
                    <Caption1 className={styles.runBranch}>{r.branch.trim()}</Caption1>
                    <Caption1 className={styles.runTime}>{formatFinished(r.finished)}</Caption1>
                    <a href={r.url} target="_blank" rel="noopener noreferrer">
                      <Button
                        icon={<OpenRegular />}
                        size="small"
                        appearance="subtle"
                        title="Open build"
                      />
                    </a>
                  </div>
                ))}
                {activeProj.runs.length > VISIBLE_ROWS && (
                  <button
                    className={styles.toggleBtn}
                    title={expanded ? "show less" : "show more"}
                    onClick={() => setExpanded((prev) => !prev)}
                  >
                    {expanded ? "−" : "+"}
                  </button>
                )}
              </div>
            </>
          ) : null}

          {data.tier >= 2 && data.projects.length === 0 && (
            <Caption1
              style={{
                color: tokens.colorNeutralForeground3,
                marginTop: tokens.spacingVerticalS,
              }}
            >
              ADO unavailable -- pipeline data not shown
            </Caption1>
          )}

          {/* ── Repo Health Footer ─────────────────────────── */}
          <div className={styles.footer}>
            {data.repo.last_commit && (
              <div className={styles.footerItem}>
                <Caption1>Last commit: {formatCommitTime(data.repo.last_commit)}</Caption1>
              </div>
            )}
            <div className={styles.footerItem}>
              <Caption1>Unpushed: {data.repo.unpushed}</Caption1>
            </div>
            <div className={styles.footerItem}>
              <Caption1>Uncommitted: {data.repo.uncommitted}</Caption1>
            </div>
            <div className={styles.footerItem}>
              <Caption1>Errors (24h): </Caption1>
              {data.repo.recent_errors > 0 ? (
                <Badge color="danger" appearance="filled" size="small">
                  {data.repo.recent_errors}
                </Badge>
              ) : (
                <Caption1>0</Caption1>
              )}
            </div>
          </div>
        </>
      )}
    </PageCard>
  );
}
