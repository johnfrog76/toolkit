import fs from "node:fs";
import path from "node:path";
import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import type { HubSync } from "../../shell/api";
import { HubSyncLine } from "./HubSyncLine";
import { SYSTEM_PATH } from "./paths";

// The foot line on the cards that write into the hub. It reads the cached /env
// and nothing else: it never asks the agent to fetch.

let hubSync: HubSync | undefined;
const checkHubSync = jest.fn();
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { hubSync } }),
  useCheckHubSyncMutation: () => {
    checkHubSync();
    return [checkHubSync, { isLoading: false }];
  },
}));

function block(over: Partial<HubSync>): HubSync {
  return {
    storeSync: "git",
    state: "on",
    ahead: 0,
    behind: null,
    checkedAt: null,
    checkFailed: null,
    checking: false,
    error: null,
    ...over,
  };
}

function draw() {
  return render(
    <MemoryRouter initialEntries={["/studio"]}>
      <Routes>
        <Route path="/studio" element={<HubSyncLine />} />
        <Route path={SYSTEM_PATH} element={<p>the system page</p>} />
      </Routes>
    </MemoryRouter>,
  );
}

beforeEach(() => checkHubSync.mockClear());

describe("the hub-sync foot line", () => {
  it("is absent under storeSync none", () => {
    hubSync = block({ state: "off", storeSync: "none" });
    draw();
    expect(screen.queryByTestId("hub-sync-line")).toBeNull();
  });

  it("is absent from an older agent that sends no block", () => {
    hubSync = undefined;
    draw();
    expect(screen.queryByTestId("hub-sync-line")).toBeNull();
  });

  it("is absent once a fetch has found the hub in step", () => {
    hubSync = block({ behind: 0, checkedAt: "2026-10-29T10:42:00+00:00" });
    draw();
    expect(screen.queryByTestId("hub-sync-line")).toBeNull();
  });

  it("says ahead and behind, with the time it was checked, and links to the System page", () => {
    hubSync = block({ ahead: 2, behind: 1, checkedAt: "2026-10-29T10:42:00+00:00" });
    draw();
    const line = screen.getByTestId("hub-sync-line");
    expect(line.textContent).toMatch(/ahead by 2 and behind by 1, checked \d{2}:\d{2}/);
    fireEvent.click(screen.getByText("Sync on the System page"));
    expect(screen.getByText("the system page")).toBeTruthy();
  });

  it("says it has not checked yet rather than in step, before any fetch", () => {
    hubSync = block({});
    draw();
    expect(screen.getByTestId("hub-sync-line").textContent).toMatch(
      /not checked against the remote yet/,
    );
  });

  it("never asks for a fetch", () => {
    hubSync = block({ ahead: 1 });
    draw();
    expect(checkHubSync).not.toHaveBeenCalled();
  });
});

describe("the cards that write into the hub", () => {
  // Read from source, the way lazyModules.test.ts reads descriptors: rendering
  // each card is its own suite's business; this holds that each draws THE line.
  const root = path.resolve(__dirname, "..");
  it.each([
    "studio/FoyerCard.tsx",
    "studio/DesignsCard.tsx",
    "organize/RemindersCard.tsx",
    "growth/ReviewArchive.tsx",
  ])("%s draws the one shared foot line", (file) => {
    const src = fs.readFileSync(path.join(root, file), "utf8");
    expect(src).toContain('from "../ado/HubSyncLine"');
    expect(src).toContain("footNote={<HubSyncLine />}");
  });
});
