import { Body1, Caption1, tokens } from "@fluentui/react-components";
import { useRowStyles } from "../ado/settingRows";
import type { CommunicationRecipient } from "./api.communication";

/** Where a recipient was declared, in the words a person uses. */
export const SCOPE_LABEL: Record<CommunicationRecipient["scope"], string> = {
  managerWorkflow: "Every Space",
  org: "This Space",
};

/** Gate 2 answered ahead of the click. Only the variable's NAME is ever shown,
 *  worded as the send button words it; the webhook URL never reaches the page. */
function webhookState(r: CommunicationRecipient): string {
  return r.configured
    ? `${r.webhookEnv} is set`
    : `Set ${r.webhookEnv} to this recipient's webhook URL.`;
}

/** One row per Teams recipient /env serves, drawn on the Environment card. */
export function EnvRecipients({ recipients }: { recipients: CommunicationRecipient[] }) {
  const styles = useRowStyles();
  if (recipients.length === 0) return null;
  return (
    <div style={{ marginTop: tokens.spacingVerticalS }}>
      {recipients.map((r) => (
        <div key={`${r.scope}:${r.key}`} className={styles.checkRow}>
          <span className={styles.checkIcon}>{r.configured ? "✓" : "✗"}</span>
          <Body1 className={styles.checkLabel}>
            <strong>{r.display}</strong>
          </Body1>
          <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
            {SCOPE_LABEL[r.scope]}
          </Caption1>
          <Caption1
            style={{
              color: r.configured
                ? tokens.colorNeutralForeground3
                : tokens.colorPaletteRedForeground1,
            }}
          >
            {webhookState(r)}
          </Caption1>
        </div>
      ))}
    </div>
  );
}
