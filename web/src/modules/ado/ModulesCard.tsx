/**
 * Modules -- the add-ons for ToolKit, and what each one's state is
 * (the owner: "new section called Modules (add-ons for ToolKit)";
 * these rows lived at the foot of the Environment card until then).
 *
 * Off means absent -- a module whose flag is false contributes no route, no
 * nav entry and no card -- but absent must not mean unmentionable: a machine
 * has to be able to say what it is not doing, which is the CLI's `Opt in by
 * configuration` block and this card (AGENTS.md, "Opt in by configuration").
 *
 * The list is the registry's own: every module that declares a `feature` is
 * opt in, so one added tomorrow appears here with no edit. The nav shortcuts,
 * the other opt-in surface, are a CLI thing -- a shell `cd` has no web form --
 * so they are named by `tkEnv`, not here.
 *
 * `off` and `not configured` are different answers: the flag resolved false,
 * or nothing has been set anywhere. /env reports the merged block, so a key
 * that is present and false is `off` and a key nobody has written is `not
 * configured`.
 */
import { Body1, Caption1, Subtitle2, tokens } from "@fluentui/react-components";
import { PageCard } from "../../shared/PageCard";
import { useGetEnvQuery } from "../../shell/api";
import type { EnvStatus } from "../../shell/api";
import { modules } from "../../shell/registry";
import { ChangeLink, useRowStyles } from "./settingRows";

export function surfaceState(env: EnvStatus | undefined, feature: string): string {
  const features = env?.features;
  if (!features || !(feature in features)) return "not configured";
  return features[feature] ? "on" : "off";
}

function SurfaceRow({ label, state, setting }: { label: string; state: string; setting: string }) {
  const styles = useRowStyles();
  return (
    <div className={styles.checkRow}>
      <span className={styles.checkIcon}>{state === "on" ? "✓" : "·"}</span>
      <Body1 className={styles.checkLabel}>
        <strong>{label}</strong>
      </Body1>
      {/* It used to read "on -- features.deck in config.local.json": a file to
          go and edit. The switch is one click away now, so it says the state. */}
      <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>{state}</Caption1>
      <ChangeLink label={label} setting={setting} />
    </div>
  );
}

export function ModulesCard({ className }: { className?: string }) {
  const { data: env, isLoading } = useGetEnvQuery();
  return (
    <PageCard
      className={className}
      loading={isLoading}
      loadingLabel="Reading the add-ons..."
      headerLeft={<Subtitle2>Modules</Subtitle2>}
      footerLeft={
        <Caption1>
          Add-ons for ToolKit. Off means absent: no tab, no verb, nothing fetched.
        </Caption1>
      }
    >
      <div style={{ marginTop: tokens.spacingVerticalS }}>
        {modules
          .filter((m) => m.feature)
          .map((m) => (
            <SurfaceRow
              key={m.id}
              label={`${m.id.charAt(0).toUpperCase()}${m.id.slice(1)} module`}
              state={surfaceState(env, m.feature as string)}
              setting={`features.${m.feature}`}
            />
          ))}
      </div>
    </PageCard>
  );
}
