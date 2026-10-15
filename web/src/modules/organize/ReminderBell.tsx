/**
 * The header bell: the Organize add-on's one mark outside its own tab.
 *
 * Soft grey in both states -- a nudge, not an alarm. Asleep (a bell with "zz")
 * when nothing is past due; awake, with the count, when something is. A click
 * goes to the Organize tab with the Reminders card on Overdue, where Snooze and
 * Done already are: the bell lists nothing itself.
 *
 * Contributed through the registry's `headerItems`, so with features.organize
 * off there is no bell and nothing is fetched.
 */
import { Button, CounterBadge, Tooltip, makeStyles, tokens } from "@fluentui/react-components";
import { AlertRegular, AlertSnoozeRegular } from "@fluentui/react-icons";
import { useNavigate } from "react-router";
import { REMINDERS_BUCKET_STATE, ROUTES } from "./paths";
import { useOverdueReminders } from "./useOverdueReminders";
import type { OverdueState } from "./useOverdueReminders";

const useStyles = makeStyles({
  wrap: { position: "relative", display: "inline-flex" },
  // appearance="transparent" gives no background and no border,
  // but still paints the icon brand on hover and press -- which
  // turned a soft nudge teal. So the icon is held grey here.
  bell: {
    color: tokens.colorNeutralForeground3,
    "& .fui-Button__icon": { color: tokens.colorNeutralForeground3 },
    ":hover .fui-Button__icon": { color: tokens.colorNeutralForeground2 },
    ":hover:active .fui-Button__icon": { color: tokens.colorNeutralForeground2 },
  },
  badge: {
    position: "absolute",
    top: "-2px",
    right: "-4px",
    pointerEvents: "none",
  },
});

/** The words the button is named by, and the tooltip says. */
export function bellLabel(state: OverdueState): string {
  if (state.status === "checking") return "Checking reminders";
  if (state.status === "unknown") return "Could not check reminders";
  if (state.count === 0) return "No past-due reminders";
  return state.count === 1 ? "1 past-due reminder" : `${state.count} past-due reminders`;
}

/** The bell without its data, so a test can hand it any state. */
export function ReminderBellView({ state, onOpen }: { state: OverdueState; onOpen: () => void }) {
  const styles = useStyles();
  const count = state.status === "known" ? state.count : 0;
  const label = bellLabel(state);
  return (
    <span className={styles.wrap}>
      <Tooltip content={label} relationship="label" withArrow>
        <Button
          appearance="transparent"
          size="small"
          className={styles.bell}
          icon={count > 0 ? <AlertRegular /> : <AlertSnoozeRegular />}
          data-bell={count > 0 ? "awake" : "asleep"}
          onClick={onOpen}
        />
      </Tooltip>
      {count > 0 && (
        <CounterBadge
          className={styles.badge}
          count={count}
          overflowCount={99}
          size="small"
          appearance="filled"
          color="informative"
          aria-hidden
        />
      )}
    </span>
  );
}

export function ReminderBell() {
  const state = useOverdueReminders();
  const navigate = useNavigate();
  return (
    <ReminderBellView
      state={state}
      onOpen={() => navigate(ROUTES.home, { state: { [REMINDERS_BUCKET_STATE]: "overdue" } })}
    />
  );
}
