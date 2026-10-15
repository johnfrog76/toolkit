/**
 * The one place the web UI reads the clock and turns a stored date into words.
 *
 * A utility, not a hook: plain functions over Luxon, no React state. The two
 * older formatters from dateFormat.ts (timeAgo, formatDate) live here too, so
 * there is one file for "what time is it" and "how do we say it".
 *
 * Luxon, local zone throughout. A day in this product is the engineer's LOCAL
 * day: `new Date().toISOString().slice(0, 10)` is the UTC date, which is
 * tomorrow from 5 pm Pacific.
 * Fixing that moved the rest of the app onto this file. Nothing in web/src calls
 * toISOString for a DAY; src/utility/dates.test.ts greps for it. Every function takes an
 * optional `now` so a test can pin the clock -- and the zone -- instead of
 * reading the machine's.
 *
 * Stored values are the hub's shape: "YYYY-MM-DD" (a day) or "YYYY-MM-DDTHH:MM"
 * (a moment), local, no offset. This file formats them; it never decides a
 * reminder's bucket -- the agent does, against the same local clock.
 */
import { DateTime } from "luxon";

const DAY = "yyyy-MM-dd";
const MOMENT = "yyyy-MM-dd'T'HH:mm";

/** Now, in the local zone. */
export function localNow(): DateTime {
  return DateTime.local();
}

/** Today's local date as "YYYY-MM-DD" -- never the UTC one. */
export function localToday(now: DateTime = localNow()): string {
  return now.toFormat(DAY);
}

/** A stored "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM" as a local DateTime, or null. */
export function parseLocal(stored: string, zone?: string): DateTime | null {
  if (!stored) return null;
  const opts = zone ? { zone } : {};
  const at = stored.includes("T")
    ? DateTime.fromFormat(stored, MOMENT, opts)
    : DateTime.fromFormat(stored, DAY, opts);
  return at.isValid ? at : null;
}

/** True when the stored value carries a time, not only a day. */
export function hasTime(stored: string): boolean {
  return stored.includes("T");
}

/**
 * A due value in words, relative to `now`: "Today", "Today 2:00 PM",
 * "Yesterday", "Tomorrow 9:00 AM", "Mon 28 Sep", "5 Jan 2027". "" for none.
 */
export function dueLabel(stored: string, now: DateTime = localNow()): string {
  const at = parseLocal(stored, now.zoneName ?? undefined);
  if (!at) return "";
  const days = Math.round(at.startOf("day").diff(now.startOf("day"), "days").days);
  const time = hasTime(stored) ? ` ${at.toFormat("h:mm a")}` : "";
  if (days === 0) return `Today${time}`;
  if (days === -1) return `Yesterday${time}`;
  if (days === 1) return `Tomorrow${time}`;
  const day = at.year === now.year ? at.toFormat("ccc d LLL") : at.toFormat("d LLL yyyy");
  return `${day}${time}`;
}

/** A JS Date's LOCAL day as "YYYY-MM-DD" -- for code that walks days with Date. */
export function localDay(d: Date): string {
  return DateTime.fromJSDate(d).toFormat(DAY);
}

/** The local day `days` before `now`, as "YYYY-MM-DD". */
export function localDaysAgo(days: number, now: DateTime = localNow()): string {
  return now.minus({ days }).toFormat(DAY);
}

/**
 * The next given weekday strictly AFTER today, as "YYYY-MM-DD" -- Luxon's
 * weekday numbering, Monday 1 to Sunday 7. On a Thursday, the next Thursday is
 * a week away, as the 1:1 default always meant.
 */
export function nextWeekday(weekday: number, now: DateTime = localNow()): string {
  const ahead = (weekday - now.weekday + 7) % 7 || 7;
  return now.plus({ days: ahead }).toFormat(DAY);
}

/** Last calendar month, as its first and last local day. */
export function previousMonth(now: DateTime = localNow()): { start: string; end: string } {
  const start = now.minus({ months: 1 }).startOf("month");
  return { start: start.toFormat(DAY), end: start.endOf("month").toFormat(DAY) };
}

/**
 * An ISO moment (with its offset) as "5 minutes ago", "1 day ago", "2 years
 * ago". Months are 30 days and years 12 months, as the text always was.
 */
export function timeAgo(iso: string, now: DateTime = localNow()): string {
  const minutes = Math.floor(now.diff(DateTime.fromISO(iso), "minutes").minutes);
  if (minutes < 60) return minutes <= 1 ? "just now" : `${minutes} minutes ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return hours === 1 ? "1 hour ago" : `${hours} hours ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return days === 1 ? "1 day ago" : `${days} days ago`;
  const months = Math.floor(days / 30);
  if (months < 12) return months === 1 ? "1 month ago" : `${months} months ago`;
  const years = Math.floor(months / 12);
  return years === 1 ? "1 year ago" : `${years} years ago`;
}

/** An ISO moment as a local date and time, in the reader's locale. */
export function formatDate(iso: string): string {
  return DateTime.fromISO(iso).toLocal().toLocaleString({
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}
