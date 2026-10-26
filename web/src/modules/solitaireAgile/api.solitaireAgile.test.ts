import { API_BASE } from "../../shell/api";
import { RITUALS } from "../../shell/consts";
import {
  ATTEND_QUERY,
  MILESTONES_QUERY,
  REMIND_QUERY,
  STANDUP_QUERY,
  TRIAGE_QUERY,
  milestonesQuery,
  standupQuery,
  triageQuery,
} from "./api.solitaireAgile";

// The route is the contract's (consts.json rituals.route), and the slice's base
// is API_BASE: what this module asks for, put under the base, is the route.
describe("the standup query", () => {
  it("is the contract's route under the slice's base", () => {
    expect(`${API_BASE}/${STANDUP_QUERY}`).toBe(RITUALS.route);
  });

  it("and so are the reminder's two routes", () => {
    expect(`${API_BASE}/${ATTEND_QUERY}`).toBe(RITUALS.attendRoute);
    expect(`${API_BASE}/${REMIND_QUERY}`).toBe(RITUALS.remindRoute);
  });

  it("asks about the Space you are in, by slug, the way the Studio asks the pane's routes", () => {
    expect(standupQuery("toolkit")).toBe(`${STANDUP_QUERY}?space=toolkit`);
    expect(standupQuery("a b")).toBe(`${STANDUP_QUERY}?space=a%20b`);
    expect(standupQuery("")).toBe(STANDUP_QUERY);
  });
});

describe("the triage query", () => {
  it("is the contract's triageRoute under the slice's base", () => {
    expect(`${API_BASE}/${TRIAGE_QUERY}`).toBe(RITUALS.triageRoute);
  });

  it("asks about a Space by slug, and the one you are in with none", () => {
    expect(triageQuery("toolkit")).toBe(`${TRIAGE_QUERY}?space=toolkit`);
    expect(triageQuery("")).toBe(TRIAGE_QUERY);
  });

  it("asks past the agent's kept read when it is the page's Refresh", () => {
    expect(triageQuery("toolkit", true)).toBe(`${TRIAGE_QUERY}?space=toolkit&refresh=1`);
    expect(triageQuery("", true)).toBe(`${TRIAGE_QUERY}?refresh=1`);
  });
});

describe("the milestones query", () => {
  it("is the contract's milestonesRoute under the slice's base", () => {
    expect(`${API_BASE}/${MILESTONES_QUERY}`).toBe(RITUALS.milestonesRoute);
  });

  it("asks about a Space by slug, and the one you are in with none", () => {
    expect(milestonesQuery("toolkit")).toBe(`${MILESTONES_QUERY}?space=toolkit`);
    expect(milestonesQuery("")).toBe(MILESTONES_QUERY);
  });
});
