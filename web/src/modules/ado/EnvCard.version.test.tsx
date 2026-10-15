import { render, screen } from "@testing-library/react";
import consts from "@consts";
import { EnvCard } from "./EnvCard";

// The System page's Environment card says which build this is: one line in its
// footer, the version /api/env serves (consts.json's), and no badge in the header.
let version: string | undefined = consts.version;
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({
    data: {
      version,
      os: "Windows AMD64",
      pythonVersion: "3.12.0",
      uptime: 60,
      tier: 2,
      tierLabel: "Local (Tier 2)",
      spaceStatus: "local",
      container: false,
      machine: "box",
      checks: {},
      config: {},
    },
    isLoading: false,
    isError: false,
    isFetching: false,
  }),
  useRefreshEnvMutation: () => [jest.fn(), { isLoading: false }],
}));

describe("the Environment card's version line", () => {
  it("shows the version the agent serves, once, in the footer", () => {
    version = consts.version;
    render(<EnvCard />);
    expect(screen.getAllByText(`Version ${consts.version}`)).toHaveLength(1);
  });

  it("draws no version line for an agent that serves none", () => {
    version = undefined;
    render(<EnvCard />);
    expect(screen.queryByText(/^Version /)).toBeNull();
  });
});
