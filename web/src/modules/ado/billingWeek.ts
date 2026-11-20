/**
 * Which week Daily Activity shows, as a number of weeks back from this one.
 *
 * 0 and 1 ask the route for `week=current` and `week=last`, so the script works
 * out those two weeks itself, as it always has. Two or more back, the page sends
 * the window -- that week's Monday to Friday, in local time -- because the route
 * has no name for it. Monday is found the way the script finds it: a Sunday
 * belongs to the week that started six days before.
 */
import { DateTime } from "luxon";
import type { BillingWeek } from "./api.ado";
import { localDay } from "../../utility/dates";

export interface DailyWeek {
  arg: BillingWeek;
  label: string;
}

/** That week's Monday, `back` weeks before the week `today` is in. */
export function mondayOf(back: number, today: Date): Date {
  const sinceMonday = (today.getDay() + 6) % 7;
  return new Date(today.getFullYear(), today.getMonth(), today.getDate() - sinceMonday - 7 * back);
}

export function dailyWeek(back: number, today: Date = new Date()): DailyWeek {
  if (back <= 0) return { arg: { week: "current" }, label: "This week" };
  if (back === 1) return { arg: { week: "last" }, label: "Last week" };
  const monday = mondayOf(back, today);
  const friday = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 4);
  // The day and month, as the reminders' due labels write them; the year too in another year.
  const shown = DateTime.fromJSDate(monday).toFormat(
    monday.getFullYear() === today.getFullYear() ? "d LLL" : "d LLL yyyy",
  );
  return { arg: { since: localDay(monday), until: localDay(friday) }, label: `Week of ${shown}` };
}
