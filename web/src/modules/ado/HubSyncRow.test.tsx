import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import type { HubSync } from "../../shell/api";
import { HubSyncRow, SYNC_VERB } from "./HubSyncRow";
import { OFF_WORDS } from "./hubSync";

// The Environment card's store-sync row: under git it fetches once when the
// page opens, offers Sync the hub, and shows what the verb said; under none it
// says what carries the folder and draws no button and no numbers.

const check = jest.fn();
const runCommand = jest.fn();
jest.mock("../../shell/api", () => ({
  useCheckHubSyncMutation: () => [check, { isLoading: false }],
}));
jest.mock("./api.ado", () => ({
  useRunCommandMutation: () => [runCommand, { isLoading: false }],
}));
// The Change link opens the settings drawer; not this test's subject.
jest.mock("./settingRows", () => ({
  ...jest.requireActual("./settingRows"),
  ChangeLink: () => null,
}));

function block(over: Partial<HubSync>): HubSync {
  return {
    storeSync: "git",
    state: "on",
    ahead: 1,
    behind: null,
    checkedAt: null,
    checkFailed: null,
    checking: false,
    error: null,
    ...over,
  };
}

function draw(sync: HubSync) {
  return render(
    <MemoryRouter>
      <HubSyncRow sync={sync} />
    </MemoryRouter>,
  );
}

beforeEach(() => {
  check.mockReset();
  runCommand.mockReset();
});

describe("under storeSync git", () => {
  it("fetches once when the page opens, not again on a re-render", () => {
    const { rerender } = draw(block({}));
    rerender(
      <MemoryRouter>
        <HubSyncRow sync={block({ checking: true })} />
      </MemoryRouter>,
    );
    expect(check).toHaveBeenCalledTimes(1);
    expect(check).toHaveBeenCalledWith();
  });

  it("shows ahead at once, and has not checked yet before the fetch answers", () => {
    draw(block({ ahead: 2 }));
    expect(screen.getByTestId("hub-sync-row").textContent).toMatch(
      /git -- ahead by 2 and not checked against the remote yet/,
    );
  });

  it("runs the Sync verb and shows its answer in its own words, then checks past the cache", async () => {
    runCommand.mockReturnValue({
      unwrap: () =>
        Promise.resolve({
          command: SYNC_VERB,
          status: "success",
          exit_code: 0,
          output:
            "Syncing prompts repo (/hub)...\nRebase failed - aborting to leave repo unchanged.\n",
          error: null,
          duration: 10,
        }),
    });
    draw(block({}));
    fireEvent.click(screen.getByText("Sync the hub"));
    await waitFor(() => expect(screen.getByTestId("hub-sync-answer")).toBeTruthy());
    expect(runCommand).toHaveBeenCalledWith({ name: "Sync" });
    expect(screen.getByTestId("hub-sync-answer").textContent).toBe(
      "Syncing prompts repo (/hub)...\nRebase failed - aborting to leave repo unchanged.",
    );
    expect(check).toHaveBeenLastCalledWith({ refresh: true });
  });

  it("says the agent did not answer when the bridge call itself fails", async () => {
    runCommand.mockReturnValue({ unwrap: () => Promise.reject(new Error("network")) });
    draw(block({}));
    fireEvent.click(screen.getByText("Sync the hub"));
    await waitFor(() =>
      expect(screen.getByTestId("hub-sync-answer").textContent).toMatch(/agent did not answer/),
    );
  });
});

describe("under storeSync none", () => {
  it("says what carries the folder, and draws no button and no numbers", () => {
    draw({ ...block({}), state: "off", storeSync: "none", ahead: null });
    expect(screen.getByTestId("hub-sync-row").textContent).toContain(`none -- ${OFF_WORDS}`);
    expect(screen.queryByText("Sync the hub")).toBeNull();
    expect(screen.queryByText(/ahead|behind/)).toBeNull();
    expect(check).not.toHaveBeenCalled();
  });
});
