import { halfTiles } from "./testHalves";
import type { HalfResult, TestSummaryMachine } from "./api.ado";

// The Health card's three halves: this machine's record only, in run
// order, a skip as a skip with its reason, and nothing for a half never run.

const machine = (name: string, halves: TestSummaryMachine["halves"]): TestSummaryMachine => ({
  machine: name,
  timestamp: "2026-10-06T12:00:00",
  suites: {},
  halves,
});

const rec = (half: HalfResult["half"], over: Partial<HalfResult> = {}): HalfResult => ({
  half,
  result: "pass",
  passed: 10,
  failed: 0,
  skipped: 0,
  total: 10,
  seconds: 1,
  reason: "",
  timestamp: "",
  ...over,
});

describe("halfTiles", () => {
  it("draws this machine's halves in the order Test runs them", () => {
    const tiles = halfTiles({
      machine: "PC",
      machines: [
        machine("MAC", { cli: rec("cli", { passed: 1 }) }),
        machine("PC", { web: rec("web"), cli: rec("cli"), agent: rec("agent", { skipped: 3 }) }),
      ],
    });
    expect(tiles.map((t) => t.label)).toEqual(["Agent", "CLI", "Web UI"]);
    expect(tiles[0]).toMatchObject({
      count: "10/10",
      tone: "pass",
      detail: "10 passed, 0 failed, 3 skipped",
    });
  });

  it("a failed half is a failure, counted over what ran", () => {
    const [cli] = halfTiles({
      machine: "PC",
      machines: [machine("PC", { cli: rec("cli", { result: "fail", passed: 9, failed: 1 }) })],
    });
    expect(cli).toMatchObject({ count: "9/10", tone: "fail" });
  });

  it("a skipped half says so, with its reason -- never a pass", () => {
    const [web] = halfTiles({
      machine: "PC",
      machines: [
        machine("PC", {
          web: rec("web", {
            result: "skip",
            passed: 0,
            total: 0,
            reason: "web/node_modules is missing -- run npm ci in web/",
          }),
        }),
      ],
    });
    expect(web).toMatchObject({ count: "Skipped", tone: "skip" });
    expect(web.detail).toContain("node_modules");
  });

  it("a half with no record, or a machine with none, draws nothing", () => {
    expect(
      halfTiles({ machine: "PC", machines: [machine("PC", { cli: rec("cli") })] }).map(
        (t) => t.half,
      ),
    ).toEqual(["cli"]);
    expect(halfTiles({ machine: "PC", machines: [machine("MAC", { cli: rec("cli") })] })).toEqual(
      [],
    );
    expect(halfTiles(undefined)).toEqual([]);
  });
});
