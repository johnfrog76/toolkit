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

  it("draws no recipient rows with the module off", () => {
    env = { ...base, features: { communication: false } };
    render(<EnvCard />);
    expect(screen.queryByText("Every Space")).toBeNull();
    expect(screen.queryByText("This Space")).toBeNull();
  });
});
