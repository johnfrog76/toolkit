/**
 * The burn tile's read: GET /api/usage/burn, kept for the session, and the
 * Refresh that asks with refresh=1 -- past the agent's hour -- and puts its
 * answer where the read keeps its own. Nothing polls: a second subscriber, and a
 * subscriber after the first has gone, read the store.
 */
import { fetched } from "./api.ado.tags.fetchStub";
import { configureStore } from "@reduxjs/toolkit";
import { api } from "../../shell/api";
import { USAGE } from "../../shell/consts";
import { BURN_QUERY, usageEndpoints } from "./api.usage";

function makeStore() {
  return configureStore({
    reducer: { [api.reducerPath]: api.reducer },
    middleware: (getDefault) => getDefault().concat(api.middleware),
  });
}

async function settle() {
  for (let i = 0; i < 10; i++) await new Promise((r) => setTimeout(r, 0));
}

const e = usageEndpoints.endpoints;

describe("the burn read", () => {
  beforeEach(() => {
    fetched.length = 0;
  });

  it("asks the contract's route", () => {
    expect(`/api/${BURN_QUERY}`).toBe(USAGE.burnRoute);
  });

  it("is read once for the session, then from the store", async () => {
    const store = makeStore();
    const first = store.dispatch(e.getBurn.initiate());
    await first;
    first.unsubscribe();
    await settle();
    await store.dispatch(e.getBurn.initiate());
    await settle();
    expect(fetched.filter((u) => u.endsWith(USAGE.burnRoute))).toHaveLength(1);
  });

  it("Refresh asks with refresh=1 and nothing else", async () => {
    const store = makeStore();
    await store.dispatch(e.getBurn.initiate());
    await store.dispatch(e.refreshBurn.initiate());
    await settle();
    expect(fetched.filter((u) => u.includes(USAGE.burnRoute))).toEqual([
      expect.stringMatching(/\/api\/usage\/burn$/),
      expect.stringMatching(/\/api\/usage\/burn\?refresh=1$/),
    ]);
  });
});
