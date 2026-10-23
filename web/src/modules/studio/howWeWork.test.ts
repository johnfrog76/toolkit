import { noteListed, pasteLine, writeHowWeWork } from "./howWeWork";
import type { HowWeWorkDeps } from "./howWeWork";
import type { PromptsResponse } from "./api.studio";
import type { CommandResponse } from "../ado/api.ado";

// The orchestrating answer's follow-up: the listing decides whether the verb is
// asked, and the verb's reply is shown as it came. The store wiring
// (writeHowWeWorkWith) is these same steps over the endpoints.
jest.mock("./api.studio", () => ({ studioEndpoints: {} }));
jest.mock("../ado/api.ado", () => ({ adoEndpoints: {} }));

const NOTE = { group: "yours" as const, path: "github-demo/agentic/how-we-work.md" };
const listing = (prompts: object[]): PromptsResponse => ({ prompts }) as unknown as PromptsResponse;
const reply = (o: Partial<CommandResponse>): CommandResponse => ({
  command: "HowWeWork",
  status: "success",
  exit_code: 0,
  output: "",
  error: null,
  duration: 1,
  ...o,
});

function deps(list: () => Promise<PromptsResponse>, answer: () => Promise<CommandResponse>) {
  const run = jest.fn((_name: string, _params: string[]) => answer());
  const d: HowWeWorkDeps = { listPrompts: list, runCommand: run };
  return { d, run };
}

describe("the Space's how-we-work note after With agents", () => {
  it("the listing already carries the note: no call", async () => {
    const { d, run } = deps(
      () => Promise.resolve(listing([{ group: "toolkit", path: "agentic/build.prompt.md" }, NOTE])),
      () => Promise.resolve(reply({})),
    );
    expect(await writeHowWeWork(d, "github-demo")).toEqual({ kind: "listed" });
    expect(run).not.toHaveBeenCalled();
  });

  it("not listed: HowWeWork <slug> through the bridge, and its AGENTS.md line on success", async () => {
    const out =
      "\n  [+] Wrote how we work in GitHub demo (github-demo)\n\n  Paste this line ...\n    How we work here: /hub/github-demo/agentic/how-we-work.md\n";
    const { d, run } = deps(
      () => Promise.resolve(listing([{ group: "toolkit", path: "agentic/build.prompt.md" }])),
      () => Promise.resolve(reply({ output: out })),
    );
    expect(await writeHowWeWork(d, "github-demo")).toEqual({
      kind: "written",
      line: "How we work here: /hub/github-demo/agentic/how-we-work.md",
    });
    expect(run).toHaveBeenCalledWith("HowWeWork", ["github-demo"]);
  });

  it("refused: the verb's own stated sentence, as the bridge returns it", async () => {
    const sentence =
      "/hub/github-demo/agentic/how-we-work.md is already there; tkHowWeWork never writes over it.";
    const { d } = deps(
      () => Promise.resolve(listing([])),
      () => Promise.resolve(reply({ status: "error", exit_code: 2, error: sentence })),
    );
    expect(await writeHowWeWork(d, "github-demo")).toEqual({ kind: "refused", sentence });
  });

  it("a listing that cannot be read is not a listed note: the verb is asked", async () => {
    const { d, run } = deps(
      () => Promise.reject(new Error("down")),
      () => Promise.resolve(reply({ output: "How we work here: /x" })),
    );
    expect((await writeHowWeWork(d, "s")).kind).toBe("written");
    expect(run).toHaveBeenCalled();
  });

  it("noteListed: one of yours at the note's path, nothing else", () => {
    expect(noteListed([NOTE])).toBe(true);
    expect(noteListed([{ group: "space" as const, path: NOTE.path }])).toBe(false);
    expect(noteListed([{ group: "yours" as const, path: "agentic/bench.prompt.md" }])).toBe(false);
  });

  it("pasteLine: the line by the contract's shape, '' when there is none", () => {
    expect(pasteLine("a\n   How we work here: /p\nb")).toBe("How we work here: /p");
    expect(pasteLine(null)).toBe("");
  });
});
