/**
 * The settings list and its schema, kept for the session. Prefetched once the
 * app is up; a second opening of the drawer draws the stored list with no
 * loading state while the refresh is in flight; a save still refreshes it.
 */
import { fetched } from "./api.ado.tags.fetchStub";
import { act, cleanup, render, screen } from "@testing-library/react";
import { configureStore } from "@reduxjs/toolkit";
import { FluentProvider, webLightTheme } from "@fluentui/react-components";
import { Provider } from "react-redux";
import { api } from "../../shell/api";
import { adoEndpoints, prefetchSettings } from "./api.ado";
import type { ConfigResponse } from "./api.ado";
import { ConfigSettings } from "./ConfigSettings";

function makeStore() {
  return configureStore({
    reducer: { [api.reducerPath]: api.reducer },
    middleware: (getDefault) => getDefault().concat(api.middleware),
  });
}

const list = (value: string): ConfigResponse => ({
  activeSpace: "",
  files: {},
  error: null,
  settings: [{ key: "email", scope: "machine", file: "local", value, source: "local" }],
});

// A held answer per route: the test says when the agent replies.
type Held = { release: (body: unknown, status?: number) => void };
let held: Record<string, Held[]>;
const g = globalThis as unknown as { fetch: unknown; Response: new (t: string) => unknown };

function holdFetch() {
  held = {};
  g.fetch = (req: { url: string }) => {
    fetched.push(req.url);
    const route = req.url.replace(/^.*\/api\//, "");
    return new Promise((resolve) => {
      (held[route] ??= []).push({
        release: (body) => resolve(new g.Response(JSON.stringify(body))),
      });
    });
  };
}

const stored = (store: ReturnType<typeof makeStore>) =>
  adoEndpoints.endpoints.getConfig.select()(store.getState() as never);

const settle = () => act(async () => void (await new Promise((r) => setTimeout(r, 0))));

function drawerBody(store: ReturnType<typeof makeStore>) {
  return (
    <Provider store={store}>
      <FluentProvider theme={webLightTheme}>
        <ConfigSettings />
      </FluentProvider>
    </Provider>
  );
}

describe("the settings list in the store", () => {
  beforeEach(() => {
    fetched.length = 0;
    holdFetch();
  });
  afterEach(cleanup);

  it("is prefetched with its schema once, and a second prefetch asks for nothing", async () => {
    const store = makeStore();
    prefetchSettings(store.dispatch);
    await settle();
    held["config"][0].release(list("a@b.c"));
    held["config/schema"][0].release({ schema: [] });
    await settle();
    prefetchSettings(store.dispatch);
    await settle();
    expect(fetched.filter((u) => u.endsWith("/api/config"))).toHaveLength(1);
    expect(fetched.filter((u) => u.endsWith("/api/config/schema"))).toHaveLength(1);
    // Nothing subscribed to it, and it is still there: kept for the session.
    expect(stored(store).data).toEqual(list("a@b.c"));
  });

  it("a failed prefetch is silent", async () => {
    const store = makeStore();
    g.fetch = () => Promise.reject(new Error("agent away"));
    expect(() => prefetchSettings(store.dispatch)).not.toThrow();
    await settle();
    expect(stored(store).data).toBeUndefined();
  });

  it("opens from the prefetched list with no loading state, and refreshes in the background", async () => {
    const store = makeStore();
    prefetchSettings(store.dispatch);
    await settle();
    held["config"][0].release(list("old@b.c"));
    held["config/schema"][0].release({ schema: [] });
    await settle();

    render(drawerBody(store));
    await settle();
    // Drawn from the store at once; the refresh is the only thing in flight.
    expect(screen.queryByText(/Reading the settings files/)).toBeNull();
    expect(screen.getByText("Your work email")).toBeTruthy();
    expect(held["config"]).toHaveLength(2);

    // A change made from the command line shows once the refresh answers.
    await act(async () => held["config"][1].release(list("new@b.c")));
    await settle();
    expect(stored(store).data?.settings[0].value).toBe("new@b.c");
  });

  it("a second opening shows the stored list with no loading state while the refresh is in flight", async () => {
    const store = makeStore();
    const first = render(drawerBody(store));
    await settle();
    expect(screen.getByText(/Reading the settings files/)).toBeTruthy();
    held["config"][0].release(list("a@b.c"));
    held["config/schema"][0].release({ schema: [] });
    await settle();
    first.unmount();

    render(drawerBody(store));
    await settle();
    expect(held["config"]).toHaveLength(2); // asked again on opening, not yet answered
    expect(screen.queryByText(/Reading the settings files/)).toBeNull();
    expect(screen.getByText("Your work email")).toBeTruthy();
  });

  it("a save from the drawer still puts the re-read list in the store", async () => {
    const store = makeStore();
    prefetchSettings(store.dispatch);
    await settle();
    held["config"][0].release(list("old@b.c"));
    held["config/schema"][0].release({ schema: [] });
    await settle();
    const write = store.dispatch(
      adoEndpoints.endpoints.writeConfig.initiate({ set: { email: "new@b.c" } } as never),
    );
    await settle();
    held["config"][1].release({
      result: { status: "success", error: null, output: "" },
      config: list("new@b.c"),
    });
    await write;
    expect(stored(store).data?.settings[0].value).toBe("new@b.c");
  });
});
