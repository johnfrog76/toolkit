import type { ReactNode } from "react";
import { render } from "@testing-library/react";
import { tokens } from "@fluentui/react-components";
import { IssueReportCard } from "./IssueReportCard";

// The severity colour signal moved from a tinted Badge onto StatTile's
// own `color` prop. Checked against the PROP StatTile receives, not the
// rendered CSS: the colour is a design token (`var(--colorPaletteRedForeground1)`,
// resolved by the theme in a real browser), and jsdom's `cssstyle` validates
// `color` as a concrete value and drops an unresolved `var(...)` outright --
// it never reaches `style.color`, `style.cssText` or `getAttribute("style")`,
// all empty, in this jest setup. A real-prop check is also the more direct
// one: it is the value IssueReportCard hands down that is the fix, not
// whatever a browser goes on to paint with it.
type Call = { label: ReactNode; color?: string };
const calls: Call[] = [];
jest.mock("../../shared/StatTile", () => ({
  StatTiles: ({ children }: { children: ReactNode }) => <div>{children}</div>,
  StatTile: (props: Call) => {
    calls.push({ label: props.label, color: props.color });
    return null;
  },
}));
jest.mock("./api.ado", () => ({
  useGetIssueReportQuery: () => ({
    data: {
      supported: true,
      open: 1,
      closed: 0,
      closed_recent: 0,
      sev: { sev1: 1, sev2: 0, sev3: 4 },
      kind: { bug: 2, feat: 1 },
      milestones: [],
      reason: null,
    },
    isLoading: false,
    isFetching: false,
    refetch: jest.fn(),
  }),
}));

test("passes the severity colour token to sev tiles, and none to a kind tile", () => {
  render(<IssueReportCard />);
  const byLabel = new Map(calls.map((c) => [c.label, c.color]));
  expect(byLabel.get("sev1")).toBe(tokens.colorPaletteRedForeground1);
  expect(byLabel.get("sev3")).toBe(tokens.colorPaletteYellowForeground1);
  expect(byLabel.get("bug")).toBeUndefined();
  expect(byLabel.get("feat")).toBeUndefined();
  // sev2 is zero -- absent, same rule as before.
  expect(byLabel.has("sev2")).toBe(false);
});
