/**
 * The row grammar the System cards share: an icon, a bold label, a quiet
 * detail, and -- for a row that REPORTS a setting -- a Change link at the
 * end that opens Settings at that key. The Environment card reports the
 * machine's checks this way and the Modules card the add-ons' flags;
 * one file so the two cannot drift apart.
 */
import { Button, makeStyles, tokens } from "@fluentui/react-components";
import { useOpenSettings } from "../../shell/cards";

export const useRowStyles = makeStyles({
  checkRow: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    paddingTop: tokens.spacingVerticalXS,
    paddingBottom: tokens.spacingVerticalXS,
  },
  checkIcon: {
    width: "20px",
    textAlign: "center" as const,
    flexShrink: 0,
  },
  checkLabel: {
    width: "120px",
    flexShrink: 0,
  },
  // Quiet until wanted: at the end of the row, the accent only on hover/focus.
  change: {
    marginLeft: "auto",
    flexShrink: 0,
    minWidth: "auto",
    color: tokens.colorNeutralForeground3,
    ":hover": { color: tokens.colorBrandForeground1 },
  },
});

// A row that REPORTS a setting sends you to the place that changes it. These
// cards are where the wish to change something occurs -- "that is the wrong
// hub", "turn that module on" -- so the way there starts here. The key is a
// config key; the drawer marks every row with its own (`data-settings-anchor`).
export function ChangeLink({ label, setting }: { label: string; setting: string }) {
  const styles = useRowStyles();
  const openSettings = useOpenSettings();
  return (
    <Button
      className={styles.change}
      appearance="transparent"
      size="small"
      aria-label={`Change ${label} in Settings`}
      onClick={() => openSettings(setting)}
    >
      Change
    </Button>
  );
}
