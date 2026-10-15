/**
 * A write through the bridge names what it changed, and the store
 * refetches: "if I add an issue it should update the store, if I close issue
 * it should update the store". Pinned at the slice, not the
 * page: the tags are the contract, and a page that reads through a hook gets
 * the refetch for free.
 */
import { fetched } from "./api.ado.tags.fetchStub";
import { configureStore } from "@reduxjs/toolkit";
import { api } from "../../shell/api";
import { adoEndpoints } from "./api.ado";

function makeStore() {
  return configureStore({
    reducer: { [api.reducerPath]: api.reducer },
    middleware: (getDefault) => getDefault().concat(api.middleware),
  });
}

const count = (path: string) => fetched.filter((u) => u.endsWith(path)).length;

/** Let RTK Query's invalidation and its refetches run to quiet. */
async function settle() {
  for (let i = 0; i < 10; i++) await new Promise((r) => setTimeout(r, 0));
}

const e = adoEndpoints.endpoints;

describe("a write through the bridge invalidates the tracker's reads", () => {
  beforeEach(() => {
    fetched.length = 0;
  });

  async function subscribed() {
    const store = makeStore();
    await Promise.all([
      store.dispatch(e.getWorkItems.initiate({ all: true })),
      store.dispatch(e.getIssueReport.initiate()),
      store.dispatch(e.getIssueDetail.initiate({ id: 5 })),
      store.dispatch(e.getStatus.initiate()),
    ]);
    expect([
      count("work-items?all=1"),
      count("issue-report"),
      count("issue/5"),
      count("status"),
    ]).toEqual([1, 1, 1, 1]);
    return store;
  }

  it("NewItem refetches the issues list and the report, not a reading room", async () => {
    const store = await subscribed();
    await store.dispatch(e.createAdoItem.initiate({ type: "Bug", title: "x" }));
    await settle();
    expect([
      count("work-items?all=1"),
      count("issue-report"),
      count("issue/5"),
      count("status"),
    ]).toEqual([2, 2, 1, 1]);
  });

  it("CloseItem refetches the list, the report, that issue's reading room and the cards", async () => {
    const store = await subscribed();
    await store.dispatch(e.resolveBug.initiate({ workItemId: 5, comment: "done" }));
    await settle();
    expect([
      count("work-items?all=1"),
      count("issue-report"),
      count("issue/5"),
      count("status"),
    ]).toEqual([2, 2, 2, 2]);
  });

  it("EditItem refetches the list, the report and that issue -- another issue's room stays", async () => {
    const store = await subscribed();
    await store.dispatch(e.editWorkItem.initiate({ id: 9, addTag: "sev2" }));
    await settle();
    expect([
      count("work-items?all=1"),
      count("issue-report"),
      count("issue/5"),
      count("status"),
    ]).toEqual([2, 2, 1, 1]);
    await store.dispatch(e.editWorkItem.initiate({ id: 5, addTag: "sev1" }));
    await settle();
    expect(count("issue/5")).toBe(2);
  });

  it("a pin or an unpin through EditItem also refetches the cards -- the Board wears it", async () => {
    const store = await subscribed();
    await store.dispatch(e.editWorkItem.initiate({ id: 9, pinned: false }));
    await settle();
    expect([
      count("work-items?all=1"),
      count("issue-report"),
      count("issue/5"),
      count("status"),
    ]).toEqual([2, 2, 1, 2]);
  });
});
