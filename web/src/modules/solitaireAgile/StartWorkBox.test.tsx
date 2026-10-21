import fs from "node:fs";
import path from "node:path";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { StartWorkBox, blockTitle } from "./StartWorkBox";

// The hand-off block's copy box (AR-1): one bridge call, the block shown
// verbatim, one Copy button, and a refusal shown as the verb's own sentence.
// The block is the shared fixture's (Tests/fixtures/start-work/expected-card.md),
// the same bytes Tests/Test-StartWork.ps1 and Tests/test_bridge.py compare.

// The golden runs to the prompt's heading; the prompt is the shipped agentic/build.prompt.md.
const FIXTURE = path.resolve(__dirname, "../../../../Tests/fixtures/start-work/expected-card.md");
const PROMPT = path.resolve(__dirname, "../../../../agentic/build.prompt.md");
const lf = (p: string) => fs.readFileSync(p, "utf8").replace(/\r\n/g, "\n").replace(/\s+$/, "");
const BLOCK = `${lf(FIXTURE)}\n${lf(PROMPT)}`;

let reply: () => Promise<unknown> = () => Promise.resolve({});
const runStartWork = jest.fn((_arg: { id: string }) => ({ unwrap: () => reply() }));
jest.mock("./api.solitaireAgile", () => ({
  useRunStartWorkMutation: () => [runStartWork, { isLoading: false }],
}));
const copyMock = jest.fn((_t: string) => Promise.resolve());
jest.mock("../../shared/copyText", () => ({ copyText: (t: string) => copyMock(t) }));

const ok = (output: string) => ({
  command: "StartWork",
  status: "success",
  exit_code: 0,
  output,
  error: null,
  duration: 1,
});

beforeEach(() => {
  runStartWork.mockClear();
  copyMock.mockClear();
});

describe("blockTitle", () => {
  it("reads the block's title by the head line's shape", () => {
    expect(blockTitle(BLOCK)).toBe("Task 23A3 -- Route the remaining raw git calls");
  });
  it("and is null for text that is not a block", () => {
    expect(blockTitle("Error: something")).toBeNull();
  });
});

describe("StartWorkBox", () => {
  it("asks the bridge once and shows the block verbatim, its title the block's own", async () => {
    reply = () => Promise.resolve(ok(`${BLOCK}\n`));
    render(<StartWorkBox id="23A3" onClose={() => undefined} />);
    const block = await screen.findByTestId("start-work-block");
    expect(block.textContent).toBe(BLOCK);
    expect(runStartWork).toHaveBeenCalledTimes(1);
    expect(runStartWork).toHaveBeenCalledWith({ id: "23A3" });
    expect(
      screen.getByText("Task 23A3 -- Route the remaining raw git calls", { exact: true }),
    ).toBeTruthy();
  });

  it("has one action, Copy, and it copies exactly the block", async () => {
    reply = () => Promise.resolve(ok(`${BLOCK}\n`));
    render(<StartWorkBox id="23A3" onClose={() => undefined} />);
    await screen.findByTestId("start-work-block");
    const copy = screen.getByRole("button", { name: "Copy" });
    await act(async () => {
      fireEvent.click(copy);
    });
    expect(copyMock).toHaveBeenCalledWith(BLOCK);
    expect(screen.getByRole("button", { name: "Copied!" })).toBeTruthy();
  });

  it("shows a refusal as the sentence the verb stated, and offers no Copy", async () => {
    const sentence = "Card 4D9K is archived: widgets/archive/Task4D9K-an-old-card.prompt.md is Done.";
    reply = () =>
      Promise.resolve({ ...ok(""), status: "error", exit_code: 1, output: null, error: sentence });
    render(<StartWorkBox id="4D9K" onClose={() => undefined} />);
    const refusal = await screen.findByTestId("start-work-refusal");
    expect(refusal.textContent).toBe(sentence);
    expect(screen.queryByRole("button", { name: "Copy" })).toBeNull();
    expect(screen.queryByTestId("start-work-block")).toBeNull();
  });

  it("says the agent did not answer when the call fails", async () => {
    reply = () => Promise.reject(new Error("offline"));
    render(<StartWorkBox id="23A3" onClose={() => undefined} />);
    await waitFor(() =>
      expect(screen.getByTestId("start-work-refusal").textContent).toBe(
        "The agent did not answer. Nothing was read.",
      ),
    );
  });
});
