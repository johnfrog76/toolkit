import { useMemo } from "react";
import {
  BeakerRegular,
  CheckmarkCircleRegular,
  DismissCircleRegular,
  PlayRegular,
  WarningRegular,
} from "@fluentui/react-icons";
import { useGetTestHistoryQuery, useRunCommandMutation } from "./api.ado";
import type { TestDay } from "./api.ado";

type TestSuite = TestDay["suites"][number];
import { halfTiles } from "./testHalves";
import { TestHealthChart } from "./TestHealthChart";
import { formatRatio } from "../../shared/formatCount";
import type { EmptyMessage } from "../../shared/EmptyState";
import type { LineItemData } from "../../shell/CardItem";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { StatRow } from "../../shell/kinds/ListPanel";

// Test Health: the last run's suites, one line each, paged like the Log's
// entries -- the run's totals and the machine's three halves as the lead's
// figures, the days as its chart, and the machine and the time in the foot.

function formatLastRun(timestamp: string | null): string {
  if (!timestamp) return "never";
  const d = new Date(timestamp);
  const now = new Date();
  const diffDays = Math.floor((now.getTime() - d.getTime()) / 86400000);
  const timeStr = d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  if (diffDays === 0) return `${timeStr} today`;
  if (diffDays === 1) return `${timeStr} yesterday`;
  return `${diffDays}d ago`;
}

function suiteItem(s: TestSuite): LineItemData {
  const pass = s.result === "pass";
  const warn = s.result === "warn";
  return {
    id: s.suite,
    title: s.suite,
    description: s.description || undefined,
    meta: [{ text: formatRatio(s.passed, s.total), mono: true }],
    badges: [
      {
        label: pass ? "Pass" : warn ? "Skip" : "Fail",
        color: pass ? "success" : warn ? "warning" : "danger",
        appearance: "filled",
        glyph: pass ? (
          <CheckmarkCircleRegular />
        ) : warn ? (
          <WarningRegular />
        ) : (
          <DismissCircleRegular />
        ),
      },
    ],
  };
}

export function TestHealth() {
  const { data, isLoading, isError, isFetching, refetch } = useGetTestHistoryQuery();
  const [runCommand, { isLoading: isRunning }] = useRunCommandMutation();
  const halves = useMemo(() => halfTiles(data), [data]);

  const latestDay = data?.days.length ? data.days[data.days.length - 1] : null;
  const hasData = !!data && data.days.length > 0;
  const anyFail = latestDay?.suites.some((s) => s.result === "fail") ?? false;
  const anyWarn = latestDay?.suites.some((s) => s.result === "warn") ?? false;

  const handleRunNow = async () => {
    try {
      await runCommand({ name: "TestToolkit" }).unwrap();
    } catch {
      // The run's outcome is the history it writes: read it again either way.
    }
    refetch();
  };

  const empty: EmptyMessage = isError
    ? {
        icon: <BeakerRegular />,
        tone: "error",
        title: "Could not load the test history",
        detail: "The agent did not answer. Nothing was read.",
      }
    : !hasData
      ? {
          icon: <BeakerRegular />,
          title: "No test runs recorded yet",
          detail:
            "Press Run above, or run the Toolkit's tests from a terminal. Each run lands here.",
        }
      : { icon: <BeakerRegular />, title: "The last run recorded no suites." };

  const stats: StatRow[] = [
    {
      label: "Last run",
      stats: [
        {
          id: "passed",
          count: formatRatio(latestDay?.passed ?? 0, latestDay?.total ?? 0),
          label: "Passed",
          tone: anyFail ? "fail" : anyWarn ? "warn" : "pass",
        },
        { id: "streak", count: data?.streak ?? 0, label: "Day streak" },
      ],
    },
  ];
  // The machine's three halves, from its test summary: what `Test` last ran
  // for the agent, the CLI and the web UI.
  if (halves.length > 0) {
    stats.push({
      label: "Halves",
      stats: halves.map((h) => ({
        id: h.half,
        count: h.count,
        label: h.label,
        tone: h.tone === "skip" ? ("warn" as const) : h.tone,
        detail: h.detail,
      })),
    });
  }

  const foot = hasData
    ? `${data.machine ?? "—"} | Last run ${formatLastRun(data.last_run ?? null)}${
        data.active_space ? `, in the ${data.active_space} Space` : ""
      }`
    : undefined;

  return (
    <ListPanel
      title="Test Health"
      icon={<BeakerRegular />}
      info="The Toolkit's tests on this machine: the last run's suites, and a bar for each day."
      items={hasData && latestDay ? latestDay.suites : []}
      density="line"
      item={suiteItem}
      empty={empty}
      lead={
        hasData && data
          ? {
              stats,
              chart: { label: "Tests by day", chart: <TestHealthChart days={data.days} /> },
            }
          : undefined
      }
      action={{
        label: "Run",
        glyph: <PlayRegular />,
        onClick: () => void handleRunNow(),
        disabled: isRunning,
        title: "Run all of the Toolkit's tests on this machine now",
      }}
      refresh={{ onClick: refetch, isFetching }}
      count={latestDay ? latestDay.suites.length : undefined}
      countLabel={latestDay ? `${latestDay.suites.length} suites` : undefined}
      footLeft={foot}
      loading={isLoading ? { label: "Loading test history..." } : undefined}
    />
  );
}
