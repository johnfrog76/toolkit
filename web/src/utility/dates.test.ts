import { DateTime } from "luxon";
import * as fs from "fs";
import * as path from "path";
import {
  dueLabel,
  hasTime,
  localToday,
  parseLocal,
  localDay,
  localDaysAgo,
  nextWeekday,
  previousMonth,
  timeAgo,
} from "./dates";

// A zone WEST of UTC, late in the evening: the moment toISOString() gets the day
// wrong.
const PACIFIC = "America/Los_Angeles";
const at = (iso: string) => DateTime.fromISO(iso, { zone: PACIFIC });

describe("localToday", () => {
  it("is the LOCAL day at 23:30 west of UTC, where the UTC date is already tomorrow", () => {
    const late = at("2026-09-23T23:30");
    expect(late.toUTC().toFormat("yyyy-MM-dd")).toBe("2026-09-24");
    expect(localToday(late)).toBe("2026-09-23");
  });
});

describe("parseLocal", () => {
  it("reads a day and a moment, in the zone given", () => {
    expect(parseLocal("2026-09-23", PACIFIC)?.toISO()).toBe("2026-09-23T00:00:00.000-07:00");
    expect(parseLocal("2026-09-23T14:00", PACIFIC)?.hour).toBe(14);
  });
  it("is null for nothing, and for a date that is not one", () => {
    expect(parseLocal("")).toBeNull();
    expect(parseLocal("2026-02-30")).toBeNull();
    expect(parseLocal("soon")).toBeNull();
  });
  it("knows a moment from a day", () => {
    expect(hasTime("2026-09-23T14:00")).toBe(true);
    expect(hasTime("2026-09-23")).toBe(false);
  });
});

describe("dueLabel", () => {
  const now = at("2026-09-23T10:00");
  it.each([
    ["", ""],
    ["2026-09-23", "Today"],
    ["2026-09-23T14:00", "Today 2:00 PM"],
    ["2026-09-22", "Yesterday"],
    ["2026-09-22T18:00", "Yesterday 6:00 PM"],
    ["2026-09-24T09:00", "Tomorrow 9:00 AM"],
    ["2026-09-28T09:00", "Mon 28 Sep 9:00 AM"],
    ["2027-01-05", "5 Jan 2027"],
  ])("%s reads %s", (stored, words) => {
    expect(dueLabel(stored, now)).toBe(words);
  });
  it("counts days on the local calendar, not in 24-hour blocks", () => {
    expect(dueLabel("2026-09-24T00:30", at("2026-09-23T23:30"))).toBe("Tomorrow 12:30 AM");
  });
});

// Every helper the app now reads a day through, pinned at 23:30 Pacific --
// the evening hour when the UTC date is already tomorrow.
describe("the day helpers, at 23:30 west of UTC", () => {
  const late = at("2026-09-23T23:30"); // a Wednesday

  it("localDaysAgo counts back from the LOCAL day", () => {
    expect(localDaysAgo(0, late)).toBe("2026-09-23");
    expect(localDaysAgo(7, late)).toBe("2026-09-16");
  });

  it("nextWeekday is the next Thursday after a Wednesday evening, not two days on", () => {
    expect(nextWeekday(4, late)).toBe("2026-09-24");
  });

  it("nextWeekday on a Thursday is a week away", () => {
    expect(nextWeekday(4, at("2026-09-24T23:30"))).toBe("2026-10-01");
  });

  it("previousMonth is last month's first and last local day", () => {
    expect(previousMonth(late)).toEqual({ start: "2026-08-01", end: "2026-08-31" });
    // The last evening of a month is still that month locally.
    expect(previousMonth(at("2026-09-30T23:30"))).toEqual({
      start: "2026-08-01",
      end: "2026-08-31",
    });
  });

  it("localDay reads a JS Date on the local calendar", () => {
    expect(localDay(new Date(2026, 8, 23, 23, 30))).toBe("2026-09-23");
  });
});

describe("timeAgo", () => {
  const now = at("2026-09-23T12:00");
  it.each([
    ["2026-09-23T11:59:30-07:00", "just now"],
    ["2026-09-23T11:15:00-07:00", "45 minutes ago"],
    ["2026-09-23T11:00:00-07:00", "1 hour ago"],
    ["2026-09-22T12:00:00-07:00", "1 day ago"],
    ["2026-08-20T12:00:00-07:00", "1 month ago"],
    ["2024-09-01T12:00:00-07:00", "2 years ago"],
  ])("%s is %s", (iso, words) => {
    expect(timeAgo(iso, now)).toBe(words);
  });
});

// The guard that keeps the fix: nothing in web/src takes a DAY from toISOString
// again. A moment (toISOString() whole, with its Z) is still fine; slicing or
// splitting one down to its date is the bug.
describe("no day is read on the UTC clock", () => {
  const src = path.resolve(__dirname, "..");
  const files: string[] = [];
  const walk = (dir: string) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (/\.(ts|tsx)$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name))
        files.push(full);
    }
  };
  walk(src);

  it("finds the source", () => {
    expect(files.length).toBeGreaterThan(50);
  });

  it("slices or splits no toISOString() down to a date", () => {
    const hits = files.flatMap((f) =>
      fs
        .readFileSync(f, "utf8")
        .split("\n")
        .map((line, i) => ({ line, at: `${path.relative(src, f)}:${i + 1}` }))
        .filter(({ line }) => !line.trim().startsWith("*") && !line.trim().startsWith("//"))
        .filter(({ line }) => /toISOString\(\)\s*\.(slice|split|substring|substr)\(/.test(line))
        .map(({ at }) => at),
    );
    expect(hits).toEqual([]);
  });
});
