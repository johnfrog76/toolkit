/**
 * A stored due, split for the Edit dialog's two inputs and joined back.
 *
 * A reminder's due is either a DAY ("yyyy-mm-dd", due at the end of it) or a
 * MOMENT ("yyyy-mm-ddThh:mm"). One datetime-local input cannot hold a day
 * without inventing a time -- and a day with 23:59 written into it is a
 * different reminder. So the dialog has a date and an optional time, and this
 * is the one place the two are taken apart and put together. String work only:
 * no clock is read, so it does not belong in utility/dates.ts.
 */
export interface DueParts {
  /** "YYYY-MM-DD", or "" for no due date. */
  date: string;
  /** "HH:MM", or "" for a day with no time. */
  time: string;
}

export function splitDue(due: string): DueParts {
  const m = /^(\d{4}-\d{2}-\d{2})(?:T(\d{2}:\d{2}))?$/.exec(due.trim());
  if (!m) return { date: "", time: "" };
  return { date: m[1], time: m[2] ?? "" };
}

/** A time with no date is no due: there is nothing to put it on. */
export function joinDue(parts: DueParts): string {
  const date = parts.date.trim();
  const time = parts.time.trim();
  if (!date) return "";
  return time ? `${date}T${time}` : date;
}
