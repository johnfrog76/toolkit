import { fireEvent, render, screen } from "@testing-library/react";
import { Billing } from "./Billing";
import { billingPath, type BillingResponse, type BillingWeek } from "./api.ado";
import { dailyWeek, mondayOf } from "./billingWeek";

// Daily Activity steps back through the weeks: this week and last week by
// name, any week before that as its Monday-to-Friday window.

jest.mock("react-markdown", () => ({ __esModule: true, default: () => null }));
jest.mock("remark-gfm", () => ({ __esModule: true, default: () => null }));

const asked: BillingWeek[] = [];
let data: BillingResponse | undefined;
const last = (): BillingWeek => asked[asked.length - 1];

jest.mock("./api.ado", () => ({
  ...jest.requireActual("./api.ado"),
  useGetBillingQuery: (arg: BillingWeek) => {
    asked.push(arg);
    return { data, isLoading: false, isFetching: false, isError: false, refetch: jest.fn() };
  },
}));

function answer(o: Partial<BillingResponse> = {}): BillingResponse {
  return {
    days: [],
    raw: "No activity found.",
    compact: "",
    source: "stamps",
    nonBillable: 0,
    unstamped: 0,
    error: "",
    ...o,
  } as BillingResponse;
}

// Wednesday 11 November 2026, local time. Only Date is faked: the page's own
// timers stay real.
const WEDNESDAY = new Date(2026, 10, 11, 12, 0, 0);

beforeEach(() => {
  jest.useFakeTimers({
    now: WEDNESDAY,
    doNotFake: [
      "setTimeout",
      "clearTimeout",
      "setInterval",
      "clearInterval",
      "setImmediate",
      "clearImmediate",
      "nextTick",
      "queueMicrotask",
      "requestAnimationFrame",
      "cancelAnimationFrame",
      "requestIdleCallback",
      "cancelIdleCallback",
      "performance",
      "hrtime",
    ],
  });
  asked.length = 0;
  data = answer();
});

afterEach(() => jest.useRealTimers());

describe("Daily Activity's week", () => {
  it("opens on this week, and Later week is disabled there", () => {
    render(<Billing />);
    expect(screen.getByText("This week")).toBeTruthy();
    expect(last()).toEqual({ week: "current" });
    expect(screen.getByRole("button", { name: "Later week" })).toHaveProperty("disabled", true);
  });

  it("asks week=last one week back, and a window three weeks back", () => {
    render(<Billing />);
    const earlier = screen.getByRole("button", { name: "Earlier week" });
    fireEvent.click(earlier);
    expect(screen.getByText("Last week")).toBeTruthy();
    expect(billingPath(last())).toBe("billing?week=last");
    fireEvent.click(earlier);
    fireEvent.click(earlier);
    expect(screen.getByText("Week of 19 Oct")).toBeTruthy();
    expect(billingPath(last())).toBe("billing?since=2026-10-19&until=2026-10-23");
    const later = screen.getByRole("button", { name: "Later week" });
    expect(later).toHaveProperty("disabled", false);
    fireEvent.click(later);
    expect(billingPath(last())).toBe("billing?since=2026-10-26&until=2026-10-30");
  });

  it("shows the agent's sentence when the week could not be built", () => {
    data = answer({ error: "-Since and -Until go together." });
    render(<Billing />);
    expect(screen.getByText("This week could not be built")).toBeTruthy();
    expect(screen.getByText("-Since and -Until go together.")).toBeTruthy();
  });

  it("points an empty week at the earlier ones", () => {
    render(<Billing />);
    expect(screen.getByText(/Try an earlier week, above\./)).toBeTruthy();
  });
});

describe("dailyWeek", () => {
  it("finds Monday the way the script does: a Sunday ends the week before it", () => {
    const sunday = new Date(2026, 10, 15, 23, 30);
    expect(mondayOf(0, sunday)).toEqual(new Date(2026, 10, 9));
    expect(dailyWeek(2, sunday).arg).toEqual({ since: "2026-10-26", until: "2026-10-30" });
    const monday = new Date(2026, 10, 9, 0, 5);
    expect(mondayOf(0, monday)).toEqual(new Date(2026, 10, 9));
  });

  it("names the year of a week in another year, and crosses it", () => {
    const week = dailyWeek(2, new Date(2026, 0, 7));
    expect(week.arg).toEqual({ since: "2025-12-22", until: "2025-12-26" });
    expect(week.label).toBe("Week of 22 Dec 2025");
  });
});
