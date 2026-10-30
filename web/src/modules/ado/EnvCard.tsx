import { Subtitle2, Body1, Caption1, Badge, Tooltip, tokens } from "@fluentui/react-components";
import { PageCard } from "../../shared/PageCard";
import { RefreshButton } from "../../shared/RefreshButton";
import { useGetEnvQuery, useRefreshEnvMutation } from "../../shell/api";
import type { EnvCheck } from "../../shell/api";
import { uptimeWords } from "../../shared/uptime";
import { ChangeLink, useRowStyles } from "./settingRows";
import { PlugDisconnectedRegular } from "@fluentui/react-icons";
import { EmptyState } from "../../shared/EmptyState";
import { checkLabel, envBadge } from "./envBadge";
import { HubSyncRow } from "./HubSyncRow";

// A row that REPORTS a setting sends you to the place that changes it (the
// Change link, settingRows.tsx). The key is a config key.
function settingFor(check: string, activeSpace: string): string | undefined {
  switch (check) {
    case "promptsVolume":
    case "promptsWritable":
      return "promptsRoot";
    case "identity":
      return "email";
    case "adoReachable":
      return activeSpace ? `spaces.${activeSpace}.org` : undefined;
    case "orgState":
      return activeSpace ? `spaces.${activeSpace}.status` : undefined;
    default:
      return undefined;
  }
}

function CheckRow({ label, check, setting }: { label: string; check: EnvCheck; setting?: string }) {
  const styles = useRowStyles();
  return (
    <div className={styles.checkRow}>
      <span className={styles.checkIcon}>{check.ok ? "✓" : "✗"}</span>
      <Body1 className={styles.checkLabel}>
        <strong>{label}</strong>
      </Body1>
      <Caption1
        style={{
          color: check.ok ? tokens.colorNeutralForeground3 : tokens.colorPaletteRedForeground1,
        }}
      >
        {check.detail}
      </Caption1>
      {setting ? <ChangeLink label={label} setting={setting} /> : null}
    </div>
  );
}

// The add-ons' rows moved to ModulesCard: this card is the machine's
// story -- its checks, and the footer's metadata -- and nothing else.

export function EnvCard({ className }: { className?: string }) {
  const { data: env, isLoading: loading, isError: error, isFetching } = useGetEnvQuery();
  // Not refetch(): the agent holds the ADO reachability answer for 45s, and the
  // point of this button is to ask again rather than to re-read the same reply.
  const [refreshEnv, { isLoading: isRefreshing }] = useRefreshEnvMutation();
  // No Space switcher here: the avatar menu is the one place a
  // Space is switched, and the tip at the foot of Home says so.

  return (
    <PageCard
      className={className}
      loading={loading}
      loadingLabel="Checking environment..."
      headerLeft={<Subtitle2>Environment</Subtitle2>}
      headerRight={
        env ? (
          <>
            <RefreshButton
              onClick={() => void refreshEnv()}
              isFetching={isFetching || isRefreshing}
            />
            {/* The org's state, not the tier number: an archived org and a local one
                are tier 2 as well, and neither of them is a warning. */}
            <Tooltip content={envBadge(env).tooltip} relationship="description">
              <Badge color={envBadge(env).color} appearance="filled" size="large">
                {envBadge(env).label}
              </Badge>
            </Tooltip>
          </>
        ) : undefined
      }
      footerLeft={
        env ? (
          <div
            style={{
              display: "flex",
              gap: tokens.spacingHorizontalM,
              flexWrap: "wrap",
            }}
          >
            {/* Which build this is: consts.json's version, as the agent serves it. */}
            {env.version && <Caption1>Version {env.version}</Caption1>}
            <Caption1>{env.os}</Caption1>
            {env.pythonVersion && <Caption1>Python {env.pythonVersion}</Caption1>}
            {env.nodeVersion && <Caption1>Node {env.nodeVersion}</Caption1>}
            {env.container && <Caption1>Docker</Caption1>}
            <Caption1>up {uptimeWords(env.uptime)}</Caption1>
          </div>
        ) : undefined
      }
    >
      {error ? (
        <EmptyState
          icon={<PlugDisconnectedRegular />}
          tone="error"
          title="Could not read this machine's environment"
          detail="The agent did not answer. Nothing was read."
        />
      ) : env ? (
        <>
          <div style={{ marginTop: tokens.spacingVerticalS }}>
            {Object.entries(env.checks).map(([key, check]) => (
              <CheckRow
                key={key}
                label={checkLabel(key, env.tracker)}
                check={check}
                setting={settingFor(key, env.config?.activeSpace ?? "")}
              />
            ))}
            {/* storeSync, and under git the hub's distance from its remote and
                Sync the hub. Absent from an older agent. */}
            {env.hubSync ? <HubSyncRow sync={env.hubSync} /> : null}
          </div>
        </>
      ) : null}
    </PageCard>
  );
}
