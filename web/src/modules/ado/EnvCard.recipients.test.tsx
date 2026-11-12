import { render, screen } from "@testing-library/react";
import { EnvCard } from "./EnvCard";

// The Environment card lists each Teams recipient /env serves, with where it
// was declared and whether its webhook variable is set.
let env: Record<string, unknown>;
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: env, isLoading: false, isError: false, isFetching: false }),
  useRefreshEnvMutation: () => [jest.fn(), { isLoading: false }],
  useCheckHubSyncMutation: () => [jest.fn(), { isLoading: false }],
}));
jest.mock("./api.ado", () => ({
  useRunCommandMutation: () => [jest.fn(), { isLoading: false }],
}));

// Set by the stand-in the module-off test registers for the rows' chunk: its
// factory runs only when that chunk is fetched.
let rowsChunkLoaded = false;

const base = {
  os: "Linux",
  uptime: 60,
  tier: 2,
  tierLabel: "Local (Tier 2)",
  spaceStatus: "local",
  container: false,
  machine: "box",
  checks: {},
  config: {},
};
const communication = {
  postRetroSummary: true,
  retroChannel: "manager",
  recipients: [
    {
      key: "manager",
      display: "My Manager",
      type: "channel",
      scope: "managerWorkflow",
      webhookEnv: "TEAMS_WEBHOOK_MANAGER",
      configured: true,
    },
    {
      key: "team",
      display: "Team Channel",
      type: "channel",
      scope: "org",
      webhookEnv: "TEAMS_WEBHOOK_TEAM",
      configured: false,
    },
  ],
};

describe("the Environment card's Teams recipients", () => {
  it("labels a managerWorkflow recipient Every Space, with its variable set", async () => {
    env = { ...base, features: { communication: true }, communication };
    render(<EnvCard />);
    expect(await screen.findByText("My Manager")).toBeTruthy();
    expect(screen.getByText("Every Space")).toBeTruthy();
    expect(screen.getByText("TEAMS_WEBHOOK_MANAGER is set")).toBeTruthy();
  });

  it("labels an org recipient This Space and names an unset variable", async () => {
    env = { ...base, features: { communication: true }, communication };
    render(<EnvCard />);
    expect(await screen.findByText("Team Channel")).toBeTruthy();
    expect(screen.getByText("This Space")).toBeTruthy();
    expect(
      screen.getByText("Set TEAMS_WEBHOOK_TEAM to this recipient's webhook URL."),
    ).toBeTruthy();
  });

  it("draws no recipient rows, and fetches none, with the module off", async () => {
    // A fresh registry for the whole render, with a stand-in for the rows'
    // chunk whose factory runs only if this render fetches it. Testing Library
    // registers hooks when it loads, so this test mounts the card itself.
    rowsChunkLoaded = false;
    env = { ...base, features: { communication: false }, communication };
    (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
    const host = document.createElement("div");
    document.body.appendChild(host);
    jest.doMock("../communication/EnvRecipients", () => {
      rowsChunkLoaded = true;
      return { EnvRecipients: () => null };
    });
    await jest.isolateModulesAsync(async () => {
      const React = await import("react");
      const { createRoot } = await import("react-dom/client");
      const { EnvCard: FreshCard } = await import("./EnvCard");
      const root = createRoot(host);
      await React.act(async () => {
        root.render(React.createElement(FreshCard));
        await new Promise((resolve) => setTimeout(resolve, 50));
      });
      expect(host.textContent).toContain("Linux");
      for (const text of ["My Manager", "Team Channel", "Every Space", "This Space"]) {
        expect(host.textContent).not.toContain(text);
      }
      await React.act(async () => root.unmount());
    });
    jest.dontMock("../communication/EnvRecipients");
    host.remove();
    expect(rowsChunkLoaded).toBe(false);
  });
});
