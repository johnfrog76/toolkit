/**
 * The past-due reminders, for anything outside the Reminders card that needs
 * to say "you have some" -- today the header bell.
 *
 * A selector over the one read the card already makes (GET /api/reminders), so
 * there is no second route and no second cache entry: a Snooze or Done on the
 * card invalidates the tag and the bell follows. The bucket is the agent's,
 * worked out against the local clock at read time; this does not re-derive it.
 *
 * It polls because a reminder BECOMES overdue with no write to invalidate
 * anything -- 2:00 PM passes and nothing on the page changes. A minute is the
 * finest a due time is written to.
 */
import { useGetRemindersQuery } from "./api.organize";
import type { Reminder, RemindersResponse } from "./api.organize";

export const OVERDUE_POLL_MS = 60_000;

/** What the bell shows: still checking, could not check, or a count. */
export type OverdueState =
  | { status: "checking" }
  | { status: "unknown" }
  | { status: "known"; count: number; items: Reminder[] };

/** The overdue slice of one /api/reminders answer. Pure, so it is tested alone. */
export function overdueOf(data: RemindersResponse | undefined, isError: boolean): OverdueState {
  if (data) {
    const items = data.items.filter((r) => r.bucket === "overdue");
    return { status: "known", count: data.buckets?.overdue ?? items.length, items };
  }
  return isError ? { status: "unknown" } : { status: "checking" };
}

export function useOverdueReminders(): OverdueState {
  const { data, isError } = useGetRemindersQuery(undefined, { pollingInterval: OVERDUE_POLL_MS });
  return overdueOf(data, isError);
}
