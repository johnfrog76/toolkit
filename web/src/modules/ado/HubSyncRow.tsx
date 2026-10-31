import { useEffect, useRef, useState } from "react";
import { Body1, Button, Caption1, tokens } from "@fluentui/react-components";
import { ArrowSyncRegular } from "@fluentui/react-icons";
import { useCheckHubSyncMutation } from "../../shell/api";
import type { HubSync } from "../../shell/api";
import { useRunCommandMutation } from "./api.ado";
import { commandResultMessage } from "./cliBridge";
import { OFF_WORDS, hubSyncWords } from "./hubSync";
import { ChangeLink, useRowStyles } from "./settingRows";

// The Environment card's store-sync row (docs/CONFIGURATION.md, "Syncing the
// hub from the web app"). Two states, the inventory's storeSync row:
//
//   on   storeSync is git. The row says how far the hub is from its remote and
//        offers Sync the hub, which runs the Sync verb through the bridge and
//        shows what the verb said -- what was pulled and pushed, or its own
//        refusal. A conflict is not resolved here: the verb refuses, the
//        terminal resolves.
//   off  anything else. The row says the folder is carried by whatever carries
//        it, and draws no button and no numbers.
//
// Opening this card is one of the only two things that fetch: once, on mount.
// Sync the hub is the other. Nothing here fetches on a timer.

/** The bridge verb Sync the hub runs: the CLI's own Sync (Scripts/Sync-Prompts.ps1). */
export const SYNC_VERB = "Sync";

const LABEL = "Store sync";

export function HubSyncRow({ sync }: { sync: HubSync }) {
  const styles = useRowStyles();
  const [check] = useCheckHubSyncMutation();
  const [runCommand, { isLoading: syncing }] = useRunCommandMutation();
  const [answer, setAnswer] = useState<string | null>(null);
  const on = sync.state === "on";

  // Once per opening of the page. The ref holds it to one through React's
  // development double-mount; the agent holds a second opening inside its TTL
  // to the answer it already has.
  const asked = useRef(false);
  useEffect(() => {
    if (!on || asked.current) return;
    asked.current = true;
    void check();
  }, [on, check]);

  const syncNow = async () => {
    setAnswer(null);
    try {
      const result = await runCommand({ name: SYNC_VERB }).unwrap();
      setAnswer(commandResultMessage(result, "Sync finished and said nothing."));
    } catch {
      setAnswer("✗ Failed: the agent did not answer, so nothing was synced.");
    }
    // Sync pulled and pushed (or refused); read where that left the hub.
    void check({ refresh: true });
  };

  const words = hubSyncWords(sync);
  const detail = on
    ? `git -- ${words ? words.parts.join(" and ") : ""}`
    : `${sync.storeSync} -- ${OFF_WORDS}`;

  return (
    <div data-testid="hub-sync-row">
      <div className={styles.checkRow}>
        <span className={styles.checkIcon}>{words?.warn ? "✗" : "✓"}</span>
        <Body1 className={styles.checkLabel}>
          <strong>{LABEL}</strong>
        </Body1>
        <Caption1
          style={{
            color: words?.warn ? tokens.colorPaletteRedForeground1 : tokens.colorNeutralForeground3,
          }}
        >
          {detail}
        </Caption1>
        <ChangeLink label={LABEL} setting="storeSync" />
      </div>
      {on && (
        <div style={{ paddingLeft: "28px", paddingBottom: tokens.spacingVerticalXS }}>
          <Button
            size="small"
            icon={<ArrowSyncRegular />}
            disabled={syncing}
            onClick={() => void syncNow()}
          >
            {syncing ? "Syncing the hub..." : "Sync the hub"}
          </Button>
          {answer != null && (
            <pre
              data-testid="hub-sync-answer"
              style={{
                whiteSpace: "pre-wrap",
                fontFamily: tokens.fontFamilyMonospace,
                fontSize: tokens.fontSizeBase200,
                margin: `${tokens.spacingVerticalXS} 0 0`,
                padding: tokens.spacingVerticalXS,
                background: tokens.colorNeutralBackground3,
                borderRadius: tokens.borderRadiusSmall,
              }}
            >
              {answer}
            </pre>
          )}
        </div>
      )}
    </div>
  );
}
