import { useState, useMemo } from "react";
import {
  Badge,
  Subtitle2,
  Caption1,
  Tooltip,
  Option,
  Dropdown,
  Button,
  tokens,
} from "@fluentui/react-components";
import { TruncatedDropdown } from "../../shared/TruncatedDropdown";
import { OpenRegular } from "@fluentui/react-icons";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { StatTile, StatTiles } from "../../shared/StatTile";
import { SprintDailyChart } from "./SprintDailyChart";
import { SprintDayScatterChart } from "./SprintDayScatterChart";
import {
  useGetStressStatusQuery,
  useGetSprintActivityQuery,
  useGetStressReposQuery,
} from "./api.ado";
import type { StressStatusResponse, SprintActivityResponse, StressReposResponse } from "./api.ado";
import { daysRemainingHealthColor, deficitHealth, healthColor } from "../../shared/health";
import { localDay } from "../../utility/dates";

/**
 * Frozen data for deck use: pass a captured snapshot and the card renders it
 * verbatim, skipping every live query (and hiding the Run/Refresh controls) so
 * a presentation slide never drifts as sprints roll over or dates advance.
 */
export interface SprintVelocitySnapshot {
  repos: StressReposResponse;
  status: StressStatusResponse;
  activity: SprintActivityResponse;
  /**
   * Pins "today" (YYYY-MM-DD) for the elapsed-days math so the active-days
   * ratio freezes with the rest of the snapshot instead of tracking the wall
   * clock. Defaults to the real date when omitted (live use).
   */
  asOf?: string;
}

function repoHref(sourceRepo: string | null | undefined): string | undefined {
  if (!sourceRepo) return undefined;
  // An ADO SSH remote is not a browsable URL — new URL() rejects one outright,
  // which silently dropped the footer link for every repo cloned over SSH.
  // Convert it to the web URL instead.
  const sshMatch = sourceRepo.match(/^git@ssh\.dev\.azure\.com:v3\/([^/]+)\/([^/]+)\/([^/]+)$/); // portability-ok: an SSH remote prefix, not anyone's address
  if (sshMatch) {
    const [, org, project, repo] = sshMatch;
    return `https://dev.azure.com/${org}/${project}/_git/${repo}`;
  }
  try {
    const url = new URL(sourceRepo);
    return url.protocol === "https:" || url.protocol === "http:" ? sourceRepo : undefined;
  } catch {
    return undefined;
  }
}

function repoLabel(sourceRepo: string | null): string {
  if (!sourceRepo) return "";
  const cleaned = sourceRepo.replace(/\.git$/, "");
  const parts = cleaned.split(/[/\\]/).filter(Boolean);
  return parts[parts.length - 1] || cleaned;
}

export function SprintVelocity({ snapshot }: { snapshot?: SprintVelocitySnapshot } = {}) {
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [selectedRepo, setSelectedRepo] = useState<string | null>(null);

  // A frozen deck snapshot short-circuits every live query so the card renders
  // deck-stable data that never drifts. skip: !!snapshot keeps the network idle.
  const frozen = !!snapshot;

  const { data: fetchedRepos } = useGetStressReposQuery(undefined, { skip: frozen });
  const stressRepos = snapshot?.repos ?? fetchedRepos;
  const activeRepo = selectedRepo ?? stressRepos?.defaultRepo ?? undefined;
  // `repos[].hasLocalCheckout` used to gate a "Run" button here. Nothing reads
  // it in this card any more -- see the note above the controls for why the
  // button went. The field stays on the API: it is what the footer's view-only
  // wording is derived from server-side.

  const {
    data: fetchedStatus,
    isLoading: statusLoading,
    isFetching: statusFetching,
    refetch: refetchStatus,
  } = useGetStressStatusQuery(activeRepo, { skip: frozen });
  const {
    data: fetchedActivity,
    isLoading: activityLoading,
    isFetching: activityFetching,
    refetch: refetchActivity,
  } = useGetSprintActivityQuery(activeRepo, { skip: frozen });
  const status = snapshot?.status ?? fetchedStatus;
  const activity = snapshot?.activity ?? fetchedActivity;

  const dateOptions = useMemo(() => {
    if (!activity) return [];
    const opts: { value: string; label: string }[] = [];
    const cursor = new Date(activity.startDate + "T00:00:00");
    const end = new Date(activity.endDate + "T00:00:00");
    while (cursor <= end) {
      opts.push({
        value: localDay(cursor),
        label: cursor.toLocaleString("default", { weekday: "short", day: "numeric" }),
      });
      cursor.setDate(cursor.getDate() + 1);
    }
    return opts;
  }, [activity]);
  const activityStats = useMemo(() => {
    if (!activity) return null;
    const mineMap = new Map(activity.mine.map((d) => [d.date, d.count]));
    const teamMap = new Map(activity.team.map((d) => [d.date, d.count]));
    const mineChurnMap = new Map(activity.mine.map((d) => [d.date, d.churn]));
    const teamChurnMap = new Map(activity.team.map((d) => [d.date, d.churn]));
    const mineTotal = activity.mine.reduce((sum, d) => sum + d.count, 0);
    const teamTotal = activity.team.reduce((sum, d) => sum + d.count, 0);
    // A pinned asOf freezes the elapsed-days window for a deck snapshot.
    const todayStr = snapshot?.asOf ?? localDay(new Date());
    const elapsedDates = dateOptions.map((o) => o.value).filter((d) => d <= todayStr);
    const activeDays = elapsedDates.filter((d) => (mineMap.get(d) ?? 0) > 0).length;
    const mine = selectedDate ? (mineMap.get(selectedDate) ?? 0) : mineTotal;
    const team = selectedDate ? (teamMap.get(selectedDate) ?? 0) : teamTotal;
    const mineChurn = selectedDate
      ? (mineChurnMap.get(selectedDate) ?? 0)
      : activity.mine.reduce((sum, d) => sum + d.churn, 0);
    const teamChurn = selectedDate
      ? (teamChurnMap.get(selectedDate) ?? 0)
      : activity.team.reduce((sum, d) => sum + d.churn, 0);
    // Sprint-window churn regardless of the date filter — gates the whole churn
    // row: a pre-churn history file is all zeros, and rendering those as real
    // values would misread "not recorded" as "nothing changed".
    const anyChurnRecorded =
      activity.mine.some((d) => d.churn > 0) || activity.team.some((d) => d.churn > 0);
    return {
      mine,
      team,
      activeDays,
      elapsedWorkdays: elapsedDates.length,
      mineChurn,
      teamChurn,
      anyChurnRecorded,
    };
  }, [activity, dateOptions, selectedDate, snapshot?.asOf]);

  // Last date with real recorded git activity in the committed history — true
  // regardless of whether a live stress-log exists on this machine, unlike
  // status.generatedAt (only present when detail === "ok").
  const lastRecordedDate = useMemo(() => {
    if (!activity) return null;
    let latest: string | null = null;
    for (const d of [...activity.mine, ...activity.team]) {
      if (d.count > 0 && (latest === null || d.date > latest)) {
        latest = d.date;
      }
    }
    return latest;
  }, [activity]);

  const isLoading = statusLoading || activityLoading;
  const isFetching = statusFetching || activityFetching;

  const handleRefresh = () => {
    refetchStatus();
    refetchActivity();
  };

  const ctx = status?.context ?? null;
  const daysRemaining = ctx?.daysRemaining ?? null;
  const sprintDaysHealthColor = daysRemainingHealthColor(daysRemaining);
  const hasLiveContext = status?.detail === "ok";
  const repo = repoLabel(status?.sourceRepo ?? null);

  if (status && !status.enabled) return null;

  const headerLeft = (
    <>
      <Subtitle2>Team</Subtitle2>
      {status?.org && (
        <Badge appearance="tint" color="brand" size="small">
          {status.org}
        </Badge>
      )}
    </>
  );

  const selectedDateLabel = selectedDate
    ? (dateOptions.find((o) => o.value === selectedDate)?.label ?? "All")
    : "All";

  const headerRight = (
    <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
      {dateOptions.length > 0 && (
        <Dropdown
          size="small"
          value={selectedDateLabel}
          selectedOptions={selectedDate ? [selectedDate] : [""]}
          onOptionSelect={(_, data) =>
            setSelectedDate(data.optionValue === "" ? null : (data.optionValue ?? null))
          }
          style={{ minWidth: "92px" }}
        >
          <Option value="">All</Option>
          {dateOptions.map((o) => (
            <Option key={o.value} value={o.value}>
              {o.label}
            </Option>
          ))}
        </Dropdown>
      )}
      {stressRepos && stressRepos.repos.length > 0 && (
        <TruncatedDropdown
          size="small"
          value={activeRepo ?? repo}
          selectedOptions={activeRepo ? [activeRepo] : []}
          maxToggleLength={22}
          disabled={stressRepos.repos.length < 2}
          onOptionSelect={(_, data) => setSelectedRepo(data.optionValue ?? null)}
          style={{ minWidth: "140px" }}
        >
          {stressRepos.repos.map((r) => (
            <Option key={r.name} value={r.name} text={r.name}>
              {r.name}
            </Option>
          ))}
        </TruncatedDropdown>
      )}
      {/* Live controls are meaningless against a frozen deck snapshot. */}
      {/*
        There was a "Run" button here. It posted { name: "StressCheck" } to the
        bridge, and StressCheck is not a key in $script:CommandMap -- the bridge's
        allowlist IS that table, so every press came back `status: rejected`. The
        refusal was the safety property working; the control was the defect. The
        name arrived with this card, not with a script, and nothing was building
        one.

        Decided: the card stops offering it rather than the CLI
        growing a verb to justify a button. SprintVelocity is a read of `status`
        and `activity`; refresh is the only write-shaped thing it needs. If a
        real StressCheck verb is ever wanted, what it would have to be is written
        down in the tracker, not
        lost with the button.
      */}
      {!frozen && <RefreshButton onClick={handleRefresh} isFetching={isFetching} />}
    </div>
  );

  // Two distinct footer shapes, not one unified format — because a live
  // reading and a view-only reading are genuinely different states, and
  // blending their content would blur that distinction:
  //  - live (detail === "ok"): "Last run <date>, <sprint> [link to repo]"
  //  - view-only: "Recorded as of <date>" + a Readonly badge, no link — the
  //    link's target (sourceRepo) is itself only known from a live log.
  // No date at all (zero data anywhere) renders nothing.
  const lastRunLabel = status?.generatedAt
    ? `Last run ${new Date(status.generatedAt).toLocaleString("default", {
        month: "2-digit",
        day: "2-digit",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      })}`
    : null;
  const recordedAsOfLabel = lastRecordedDate
    ? `Recorded as of ${new Date(lastRecordedDate + "T00:00:00").toLocaleDateString("default", {
        month: "2-digit",
        day: "2-digit",
        year: "numeric",
      })}`
    : null;

  const footerLeft =
    hasLiveContext && lastRunLabel ? (
      <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
        <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
          {lastRunLabel}
          {ctx?.sprintName ? `, ${ctx.sprintName}` : ""}
        </Caption1>
        {repoHref(status?.sourceRepo) && (
          <Button
            as="a"
            href={repoHref(status?.sourceRepo)}
            target="_blank"
            rel="noopener noreferrer"
            size="small"
            appearance="subtle"
            icon={<OpenRegular />}
            title={status?.sourceRepo ?? ""}
          />
        )}
      </div>
    ) : recordedAsOfLabel ? (
      <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
        <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>{recordedAsOfLabel}</Caption1>
        <Badge appearance="tint" color="subtle" size="small">
          Readonly
        </Badge>
      </div>
    ) : undefined;

  return (
    <PageCard
      loading={isLoading}
      loadingLabel="Loading sprint velocity..."
      headerLeft={headerLeft}
      headerRight={headerRight}
      footerLeft={footerLeft}
    >
      {(ctx || activityStats?.anyChurnRecorded) && (
        <StatTiles>
          {daysRemaining !== null && ctx && (
            <StatTile count={daysRemaining} label="days left" color={sprintDaysHealthColor} />
          )}
          {ctx && activityStats && (
            <>
              <StatTile count={activityStats.mine} label="commits" />
              <StatTile count={activityStats.team} label="merges" />
              {!selectedDate && (
                <>
                  <StatTile
                    count={`${activityStats.activeDays}/${activityStats.elapsedWorkdays}`}
                    label="active days"
                  />
                  {hasLiveContext && (
                    <>
                      <Tooltip
                        content="Commits in the last 3 days"
                        relationship="description"
                        withArrow
                      >
                        <StatTile
                          count={ctx.mergeVelocity}
                          label="velocity"
                          color={healthColor(deficitHealth(ctx.mergeVelocity, 6, 8))}
                        />
                      </Tooltip>
                      <Tooltip
                        content="Commits landed on origin/main since you branched"
                        relationship="description"
                        withArrow
                      >
                        <StatTile
                          count={ctx.upstreamMerges}
                          label="upstream merges"
                          color={healthColor(deficitHealth(ctx.upstreamMerges, 6, 11))}
                        />
                      </Tooltip>
                    </>
                  )}
                </>
              )}
            </>
          )}
          {/* Churn tiles — lines-changed counterpart to the commit counts. Hidden entirely when the history file predates churn
              collection: those zeros mean "not recorded", not "nothing changed". */}
          {activityStats?.anyChurnRecorded && (
            <>
              <Tooltip
                content="Lines added + deleted in your commits on the default branch"
                relationship="description"
                withArrow
              >
                <StatTile count={activityStats.mineChurn.toLocaleString()} label="my churn" />
              </Tooltip>
              <Tooltip
                content="Lines added + deleted across all commits on the default branch"
                relationship="description"
                withArrow
              >
                <StatTile count={activityStats.teamChurn.toLocaleString()} label="team churn" />
              </Tooltip>
              <Tooltip
                content="Your churn as a share of team churn"
                relationship="description"
                withArrow
              >
                <StatTile
                  count={
                    activityStats.teamChurn > 0
                      ? `${Math.round((activityStats.mineChurn / activityStats.teamChurn) * 100)}%`
                      : "0"
                  }
                  label="my share"
                />
              </Tooltip>
            </>
          )}
        </StatTiles>
      )}
      {selectedDate ? (
        <SprintDayScatterChart
          selectedDate={selectedDate}
          repo={activeRepo}
          activityOverride={snapshot?.activity}
        />
      ) : (
        <SprintDailyChart repo={activeRepo} activityOverride={snapshot?.activity} />
      )}
    </PageCard>
  );
}
