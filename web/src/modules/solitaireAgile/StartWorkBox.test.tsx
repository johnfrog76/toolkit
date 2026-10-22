import fs from "node:fs";
import path from "node:path";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { STARTWORK } from "../../shell/consts";
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
let launchReply: () => Promise<unknown> = () => Promise.resolve({});
const runStartWork = jest.fn((arg: { id: string; launch?: boolean }) => ({
  unwrap: () => (arg.launch ? launchReply() : reply()),
}));
jest.mock("./api.solitaireAgile", () => ({
  useRunStartWorkMutation: () => [runStartWork, { isLoading: false }],
}));
// /env: whether the launch exists (D-AR13). Absent is off -- what every agent
// without the launch serves.
let env: Record<string, unknown> = {};
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ isLoading: false, data: env }),
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
  env = {};
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
    const sentence =
      "Card 4D9K is archived: widgets/archive/Task4D9K-an-old-card.prompt.md is Done.";
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

  it("offers no second button while /env does not say the launch is on", async () => {
    reply = () => Promise.resolve(ok(`${BLOCK}\n`));
    for (const e of [{}, { [STARTWORK.launchEnvFlag]: false }]) {
      env = e;
      const { unmount } = render(<StartWorkBox id="23A3" onClose={() => undefined} />);
      await screen.findByTestId("start-work-block");
      expect(screen.queryByRole("button", { name: "Launch" })).toBeNull();
      unmount();
    }
  });

  it("where /env says the launch is on, Launch runs the same verb with -Launch and shows what it said", async () => {
    env = { [STARTWORK.launchEnvFlag]: true };
    reply = () => Promise.resolve(ok(`${BLOCK}\n`));
    launchReply = () => Promise.resolve(ok("Started PID 4242. Log: crew-23A3.log\n"));
    render(<StartWorkBox id="23A3" onClose={() => undefined} />);
    await screen.findByTestId("start-work-block");
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Launch" }));
    });
    expect(runStartWork).toHaveBeenLastCalledWith({ id: "23A3", launch: true });
    expect(runStartWork).toHaveBeenCalledTimes(2);
    expect(screen.getByTestId("start-work-launched").textContent).toBe(
      "Started PID 4242. Log: crew-23A3.log",
    );
  });

  it("a launch refused shows the verb's sentence", async () => {
    env = { [STARTWORK.launchEnvFlag]: true };
    reply = () => Promise.resolve(ok(`${BLOCK}\n`));
    const sentence = "claude is not on the PATH.";
    launchReply = () =>
      Promise.resolve({ ...ok(""), status: "error", exit_code: 1, output: null, error: sentence });
    render(<StartWorkBox id="23A3" onClose={() => undefined} />);
    await screen.findByTestId("start-work-block");
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Launch" }));
    });
    expect(screen.getByTestId("start-work-launched").textContent).toBe(sentence);
    expect(screen.getByTestId("start-work-launched").getAttribute("role")).toBe("alert");
  });
});
