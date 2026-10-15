/**
 * The connect wizard page (W2, D-W12 to D-W17): reads the verb's report,
 * says the grain on step 1, says the sign-in command and never runs it,
 * writes a step as the same verb with one switch, and shows a refusal's
 * sentence. The report shapes come from Scripts/Connect-Space.ps1's -AsJson.
 */
import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { ConnectPage, parseReport } from "./ConnectPage";
import type { ConnectReport } from "./ConnectPage";
import type { CommandResponse } from "./api.ado";

const stepSpy = jest.fn();
let current: ConnectReport;

function response(report: ConnectReport, status = "success"): CommandResponse {
  return {
    command: "Connect",
    status,
    exit_code: 0,
    output: "noise\n" + JSON.stringify(report),
    error: null,
    duration: 1,
  };
}

jest.mock("./api.ado", () => ({
  useGetConnectStateQuery: () => ({
    data: response(current),
    isFetching: false,
    refetch: jest.fn(),
  }),
  useConnectStepMutation: () => [
    (arg: unknown) => {
      stepSpy(arg);
      return { unwrap: () => Promise.resolve(response(current)) };
    },
    { isLoading: false },
  ],
}));
jest.mock("../../shared/BackButton", () => ({ BackButton: () => null }));

const base: ConnectReport = {
  slug: "acme",
  name: "Acme",
  active: true,
  example: false,
  address: "",
  tracker: "none",
  grain: "your cards alone -- no tracker",
  status: "local",
  steps: {
    address: { done: false, yours: true },
    signIn: { done: false, yours: true, tool: "", installed: false, identity: "", command: "" },
    projects: { done: false, yours: false, configured: [], available: [] },
    sprint: { done: false, yours: false, on: false },
  },
  did: [],
  whatIf: false,
};

function renderAt(slug = "acme") {
  stepSpy.mockClear();
  render(
    <MemoryRouter initialEntries={[`/connect/${slug}`]}>
      <Routes>
        <Route path="/connect/:slug" element={<ConnectPage />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("parseReport", () => {
  it("takes the verb's one JSON line out of whatever else it printed", () => {
    expect(parseReport(response(base))?.slug).toBe("acme");
    expect(parseReport({ ...response(base), output: "no json here" })).toBeNull();
    expect(parseReport(undefined)).toBeNull();
  });
});

describe("ConnectPage", () => {
  it("a Space with no address is a whole shape, and step 2 waits for step 1", () => {
    current = base;
    renderAt();
    expect(screen.getByText(/works from your cards alone/)).toBeTruthy();
    expect(screen.getAllByText("After the address.").length).toBe(2);
  });

  it("saves the address as the verb's step, and says the grain once it has one", () => {
    current = base;
    renderAt();
    fireEvent.change(screen.getByLabelText("Address"), {
      target: { value: "https://dev.azure.com/acme" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save address" }));
    expect(stepSpy).toHaveBeenCalledWith({
      slug: "acme",
      params: ["-Address", "https://dev.azure.com/acme"],
    });
  });

  it("a Space shipped with an address and still local is one click from connected", () => {
    current = {
      ...base,
      slug: "github-demo",
      name: "GitHub demo",
      example: true,
      address: "https://github.com/johnfrog76/recipe-box-demo",
      tracker: "github",
      grain: "one GitHub repo",
      status: "local",
    };
    renderAt("github-demo");
    expect(screen.getByText(/local until you connect it/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Connect" }));
    expect(stepSpy).toHaveBeenCalledWith({
      slug: "github-demo",
      params: ["-Address", "https://github.com/johnfrog76/recipe-box-demo"],
    });
  });

  it("an Azure DevOps Space says it is an organisation, names az login and never runs it", () => {
    current = {
      ...base,
      address: "https://dev.azure.com/acme",
      tracker: "ado",
      grain: "an Azure DevOps organisation, projects inside it",
      status: "active",
      steps: {
        ...base.steps,
        address: { done: true, yours: true },
        signIn: {
          done: false,
          yours: true,
          tool: "az",
          installed: true,
          identity: "",
          command: "az login",
        },
      },
    };
    renderAt();
    expect(screen.getByText(/an Azure DevOps organisation, projects inside it/)).toBeTruthy();
    expect(screen.getByText("az login")).toBeTruthy();
    expect(screen.getByText(/never signs in for you/)).toBeTruthy();
    expect(
      (screen.getByRole("button", { name: "List the projects" }) as HTMLButtonElement).disabled,
    ).toBe(true);
  });

  it("a GitHub Space is one repo: no sprint step, the address is the repo", () => {
    current = {
      ...base,
      address: "https://github.com/johnfrog76/toolkit",
      tracker: "github",
      grain: "one GitHub repo",
      status: "active",
      steps: {
        ...base.steps,
        address: { done: true, yours: true },
        signIn: {
          done: true,
          yours: true,
          tool: "gh",
          installed: true,
          identity: "johnfrog76",
          command: "gh auth login",
        },
      },
    };
    renderAt();
    expect(screen.getByText(/This Space is johnfrog76\/toolkit/)).toBeTruthy();
    expect(screen.getByText(/milestones, not sprints/)).toBeTruthy();
    expect(screen.getByText(/as johnfrog76/)).toBeTruthy();
  });

  it("sprint awareness is the verb's last step", () => {
    current = {
      ...base,
      address: "https://dev.azure.com/acme",
      tracker: "ado",
      grain: "an Azure DevOps organisation, projects inside it",
      steps: {
        ...base.steps,
        address: { done: true, yours: true },
        signIn: {
          done: true,
          yours: true,
          tool: "az",
          installed: true,
          identity: "me",
          command: "az login",
        },
      },
    };
    renderAt();
    fireEvent.click(screen.getByRole("switch"));
    expect(stepSpy).toHaveBeenCalledWith({ slug: "acme", params: ["-Sprint", "true"] });
  });

  it("a shipped demo Space -- the Azure demo -- offers to become yours (D-W15)", () => {
    current = { ...base, example: true, name: "Azure demo" };
    renderAt();
    expect(screen.getByText(/Azure demo is one of the shipped demo Spaces/)).toBeTruthy();
    fireEvent.change(screen.getByLabelText("Your slug"), { target: { value: "mine" } });
    fireEvent.click(screen.getByRole("button", { name: "Make it mine" }));
    expect(stepSpy).toHaveBeenCalledWith({ slug: "acme", params: ["-As", "mine"] });
  });
});
