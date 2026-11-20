import { Body1, Caption1, tokens } from "@fluentui/react-components";
import { InfoTip } from "../../shared/InfoTip";
import { useRowStyles } from "../ado/settingRows";
import type { CommunicationEnv, CommunicationRecipient } from "./api.communication";
import {
  RECIPIENTS_TITLE,
  RECIPIENT_STATE_LABEL,
  recipientHowTo,
  recipientLabel,
  recipientState,
} from "./recipientState";

/** Where a recipient was declared, in the words a person uses. */
export const SCOPE_LABEL: Record<CommunicationRecipient["scope"], string> = {
  managerWorkflow: "Every Space",
  org: "This Space",
};

/**
 * One row per Teams recipient /env serves, drawn on the Environment card.
 *
 * A row says what the recipient does and which of its states it is in, in a
 * few neutral words (recipientState.ts, shared with the send button). None is
 * red and none is an instruction: how to set a webhook up, and the variable's
 * name, are behind the row's info icon. The webhook URL never reaches the page.
 */
export function EnvRecipients({ communication }: { communication: CommunicationEnv }) {
  const styles = useRowStyles();
  const { recipients, retroChannel, sendingOff } = communication;
  if (recipients.length === 0) return null;
  return (
    <div style={{ marginTop: tokens.spacingVerticalS }}>
      <Caption1 as="h3" block style={{ margin: 0, color: tokens.colorNeutralForeground3 }}>
        {RECIPIENTS_TITLE}
      </Caption1>
      {recipients.map((r) => {
        const state = recipientState(r, sendingOff);
        const label = recipientLabel(r, retroChannel);
        return (
          <div
            key={`${r.scope}:${r.key}`}
            className={styles.checkRow}
            style={{ flexWrap: "wrap" }}
            data-recipient={r.key}
            data-state={state}
          >
            <span className={styles.checkIcon} aria-hidden="true">
              {state === "ready" ? "✓" : "–"}
            </span>
            <Body1>
              <strong>{label}</strong>
            </Body1>
            <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
              {SCOPE_LABEL[r.scope]}
            </Caption1>
            <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
              {RECIPIENT_STATE_LABEL[state]}
            </Caption1>
            <InfoTip label={`About ${label}`} content={recipientHowTo(r, state)} />
          </div>
        );
      })}
    </div>
  );
}
