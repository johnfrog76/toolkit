import { useState } from "react";
import {
  Body1,
  Button,
  Caption1,
  Checkbox,
  Input,
  Subtitle2,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { StatusMessage } from "../../shared/StatusMessage";
import { RITUALS } from "../../shell/consts";
import { buildStandupRemindParams, commandResultMessage } from "../ado/cliBridge";
import { useGetStandupRemindQuery, useRunStandupRemindMutation } from "./api.solitaireAgile";

/**
 * Team Agile's section of the settings drawer: the reminder to attend
 * (D-TA15). One row -- a time and the days -- and its Save is `Standup -Remind`
 * through `POST /api/cmd/Standup`: the CLI writes the reminder through
 * Organize's own verbs, so this section writes nothing and knows no file.
 *
 * The reminder is an Organize reminder, so the row needs Organize: with
 * `features.organize` off it says so and offers nothing to set. What is set is
 * read back from `GET /api/ritual/standup/remind` -- the open reminder's due and
 * the cadence on its Ref line. Attending re-arms it (the standup page), and
 * archiving it in Organize stops it.
 *
 * The anchor `standup.remind` is where the "How do I…" entry "Can it remind me
 * to attend?" opens the drawer.
 */

export const STANDUP_REMIND_ANCHOR = "standup.remind";

const useStyles = makeStyles({
  section: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalXS },
  hint: { color: tokens.colorNeutralForeground3, lineHeight: tokens.lineHeightBase300 },
  row: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    paddingTop: tokens.spacingVerticalS,
  },
  days: { display: "flex", flexWrap: "wrap", columnGap: tokens.spacingHorizontalXS },
});

/** The cadence `-Days` defaults to, as day names: `Mon-Fri` -> Mon..Fri. */
export function defaultDays(): string[] {
  const [from, to] = RITUALS.remindDays.split("-");
  const a = RITUALS.weekdays.indexOf(from);
  const b = RITUALS.weekdays.indexOf(to ?? from);
  return a < 0 || b < a ? [] : RITUALS.weekdays.slice(a, b + 1);
}

/** A stored due, an ISO timestamp, as "Mon 5 Oct, 09:00"; a date alone, without the time. */
export function describeDue(due: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}:\d{2}))?$/.exec(due);
  if (!m) return due;
  const day = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  const name = RITUALS.weekdays[(day.getDay() + 6) % 7];
  const month = day.toLocaleString("en-GB", { month: "short" });
  return `${name} ${day.getDate()} ${month}${m[4] ? `, ${m[4]}` : ""}`;
}

export function StandupRemindSettings() {
  const styles = useStyles();
  const { data, isLoading, error } = useGetStandupRemindQuery();
  const [run, { isLoading: saving }] = useRunStandupRemindMutation();
  // Drafts, not copies: the form shows the reminder's own cadence until the
  // person edits it, and a successful save hands the field back to what was
  // stored -- so no effect copies server state into local state.
  const [timeDraft, setTimeDraft] = useState<string | null>(null);
  const [daysDraft, setDaysDraft] = useState<string[] | null>(null);
  const [result, setResult] = useState<{ status: "success" | "error"; text: string } | null>(null);

  const reminder = data?.reminder ?? null;
  const time = timeDraft ?? (reminder?.time || "09:00");
  const days = daysDraft ?? (reminder?.days.length ? reminder.days : defaultDays());
  const setTime = (t: string) => setTimeDraft(t);

  const toggle = (day: string, on: boolean) =>
    setDaysDraft(RITUALS.weekdays.filter((d) => (d === day ? on : days.includes(d))));

  const save = async () => {
    setResult(null);
    try {
      const res = await run({ params: buildStandupRemindParams({ time, days }) }).unwrap();
      const ok = res.status === "success";
      if (ok) {
        setTimeDraft(null);
        setDaysDraft(null);
      }
      setResult({
        status: ok ? "success" : "error",
        text: commandResultMessage(res, "Reminder set."),
      });
    } catch {
      setResult({ status: "error", text: "The agent did not answer. Nothing was set." });
    }
  };

  let body;
  if (isLoading) body = <Caption1 className={styles.hint}>Loading...</Caption1>;
  else if (error || !data)
    body = (
      <Caption1 className={styles.hint}>
        The agent did not answer; the reminder cannot be read.
      </Caption1>
    );
  else if (!data.organize)
    body = (
      <Caption1 className={styles.hint}>
        The reminder is an Organize reminder, so it needs Organize: turn on features.organize first,
        then set it here.
      </Caption1>
    );
  else
    body = (
      <>
        <Caption1 className={styles.hint}>
          {reminder
            ? `Next: ${describeDue(reminder.due)}${reminder.ref ? ` (${reminder.ref})` : ""}. Opening the standup re-arms it; archiving it in Organize stops it.`
            : "Not set. The bell wakes when the standup is due, and opening the standup re-arms it for the next day."}
        </Caption1>
        <div className={styles.row}>
          <Input
            type="time"
            aria-label="Remind me at"
            value={time}
            onChange={(_e, d) => setTime(d.value)}
          />
          <div className={styles.days} role="group" aria-label="On these days">
            {RITUALS.weekdays.map((day) => (
              <Checkbox
                key={day}
                label={day}
                checked={days.includes(day)}
                onChange={(_e, d) => toggle(day, !!d.checked)}
              />
            ))}
          </div>
          <Button
            appearance="primary"
            disabled={saving || !time || days.length === 0}
            onClick={save}
          >
            {reminder ? "Update" : "Remind me"}
          </Button>
        </div>
        {result && (
          <StatusMessage status={result.status} onDismiss={() => setResult(null)}>
            {result.text}
          </StatusMessage>
        )}
      </>
    );

  return (
    <section
      className={styles.section}
      aria-labelledby="settings-team-agile-heading"
      data-settings-anchor={STANDUP_REMIND_ANCHOR}
    >
      <Subtitle2 id="settings-team-agile-heading">Team Agile</Subtitle2>
      <Body1>Remind me to attend the standup</Body1>
      {body}
    </section>
  );
}
