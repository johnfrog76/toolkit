/**
 * The standup is sized by a setting (the team size), so a configuration write
 * marks it stale and it is read again the next time it is shown, with no hard
 * refresh. Pinned at the slice, like api.ado.tags.test.ts.
 */
import { fetched } from "../ado/api.ado.tags.fetchStub";
import { configureStore } from "@reduxjs/toolkit";
import { api } from "../../shell/api";
import { adoEndpoints } from "../ado/api.ado";
import { solitaireAgileEndpoints } from "./api.solitaireAgile";

const count = (path: string) => fetched.filter((u) => u.includes(path)).length;

async function settle() {
  for (let i = 0; i < 10; i++) await new Promise((r) => setTimeout(r, 0));
}

describe("a configuration write marks the standup stale", () => {
  it("refetches the standup a page is subscribed to", async () => {
    fetched.length = 0;
    const store = configureStore({
      reducer: { [api.reducerPath]: api.reducer },
      middleware: (getDefault) => getDefault().concat(api.middleware),
    });
    await store.dispatch(solitaireAgileEndpoints.endpoints.getStandup.initiate(""));
    expect(count("ritual/standup")).toBe(1);

    await store.dispatch(
      adoEndpoints.endpoints.writeConfig.initiate({
        key: "spaces.x.features.teamSize",
        value: 6,
      } as never),
    );
    await settle();
    expect(count("ritual/standup")).toBe(2);
  });
});
