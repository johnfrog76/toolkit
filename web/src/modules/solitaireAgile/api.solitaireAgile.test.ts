import { API_BASE } from "../../shell/api";
import { RITUALS } from "../../shell/consts";
import {
  ATTEND_QUERY,
  REMIND_QUERY,
  STANDUP_QUERY,
  TRIAGE_QUERY,
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
});
