import fs from "node:fs";
import path from "node:path";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { StandupPlay } from "./StandupPlay";
import type { StandupResponse } from "../api.solitaireAgile";

// The played standup's route: the module's resolver hands the deck
// engine's SECOND resolver (deck/GeneratedDeckHost.tsx) a deck it built from
// the standup route -- and its two states before it has one, through the
// shared empty state. Nothing here touches the deck module's static list.

class BroadcastChannelStub {
  onmessage: ((e: MessageEvent) => void) | null = null;
  constructor(public name: string) {}
  postMessage() {}
  close() {}
}
beforeAll(() => {
  (globalThis as unknown as { BroadcastChannel: unknown }).BroadcastChannel = BroadcastChannelStub;
});

// The stage reads the chosen theme. The real hook reads matchMedia when it
// is imported, which jsdom has none of, so the theme is a stand-in the test sets.
const mockThemeId = "seaglass";
jest.mock("../../../hooks/useWornTheme", () => ({
  useWornTheme: () => {
    const active = jest.requireActual("../../../shell/themeList").themeById(mockThemeId);
    return { theme: active.mode, active, worn: null, chosen: active, setThemeId: () => {} };
  },
}));

let answer: { data?: unknown; error?: unknown; isLoading?: boolean } = {};
jest.mock("../api.solitaireAgile", () => ({
  useGetStandupQuery: () => ({ isLoading: false, ...answer }),
}));
jest.mock("../../../shell/api", () => ({
  useGetEnvQuery: () => ({ isLoading: false, data: { config: { activeSpace: "toolkit" } } }),
}));

/** The smallest response the contract allows: a tracker that did not answer. */
function noTracker(): StandupResponse {
  const golden = path.resolve(
    __dirname,
    "../../../../../Tests/fixtures/rituals/standup-no-tracker.txt",
  );
  return {
    ceremony: "standup",
    register: "real",
    asOf: "2026-10-02T09:00:00-04:00",
    since: "2026-10-01T00:00:00-04:00",
    space: "toolkit",
    tracker: { ok: false, reason: "no tracker connected" },
    chair: { open: "All green.", close: "Let's circle back." },
    queue: { walk: [], decide: [], look: [] },
    workers: [],
    text: fs.readFileSync(golden, "utf8"),
  };
}

const mount = () =>
  render(
    <MemoryRouter>
      <StandupPlay />
    </MemoryRouter>,
  );

beforeEach(() => {
  answer = {};
});

describe("the played standup's route", () => {
  it("while it reads, says so", () => {
    answer = { isLoading: true };
    mount();
    expect(screen.getByText(/Loading/)).toBeTruthy();
  });

  it("with no answer, says the agent did not answer rather than playing nothing", () => {
    answer = { error: { status: "FETCH_ERROR" } };
    mount();
    expect(screen.getByRole("alert").textContent).toMatch(/did not answer/);
  });

  it("with an answer, plays it in Suitcase at desktop width, prev and next beside the transport", () => {
    answer = { data: noTracker() };
    mount();
    expect(screen.getByRole("button", { name: "Pause" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Previous slide" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Next slide" })).toBeTruthy();
    expect(screen.getByTestId("stage-register").textContent).toBe("REGISTER · REAL");
  });
});
