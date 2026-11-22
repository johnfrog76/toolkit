/**
 * The settings-by-workflow list, read from the ONE file (D-W1, D-W8): its shape,
 * the rules an entry meets, and the half of the parity the web can hold without
 * PowerShell -- every module the registry declares has a question, and every
 * `features.<x>` an entry names is a module the web knows (or the ADO core).
 * The other half -- every inventory key has an entry -- is tkTestToolkit
 * -Environment's, against the real resolver.
 */
import fs from "node:fs";
import path from "node:path";
import {
  WORKFLOW_ENTRIES,
  answerChoices,
  answerLive,
  answerStored,
  answerTarget,
  asksHowIWork,
  entryAnchor,
  entryQuestion,
  entryAsking,
  entryConfigLines,
  entryRoute,
  entryState,
  spaceHasOwnTip,
  spaceTipEntries,
  tippableEntries,
} from "./settingsWorkflows";
import type { SurfaceRow } from "./api";
import { RITUALS } from "./consts";

const row = (key: string, state: SurfaceRow["state"]): SurfaceRow => ({
  key,
  state,
  title: key,
  config: `tkConfig -Set ${key}=x`,
  note: "",
  question: "q",
});

function registeredModuleFeatures(): string[] {
  const dir = path.join(__dirname, "..", "modules");
  return fs
    .readdirSync(dir)
    .map((m) => path.join(dir, m, "index.tsx"))
    .filter((f) => fs.existsSync(f))
    .map((f) => /feature: "([a-zA-Z]+)"/.exec(fs.readFileSync(f, "utf8"))?.[1])
    .filter((f): f is string => !!f);
}

describe("the list", () => {
  it("has entries with unique ids, a question, a sentence, at least one surface and a known door", () => {
    expect(WORKFLOW_ENTRIES.length).toBeGreaterThanOrEqual(12);
    const ids = new Set<string>();
    for (const e of WORKFLOW_ENTRIES) {
      expect(ids.has(e.id)).toBe(false);
      ids.add(e.id);
      expect(e.question.endsWith("?")).toBe(true);
      expect(e.sentence.length).toBeGreaterThan(20);
      expect(e.surfaces.length).toBeGreaterThan(0);
      expect(["change", "walk", "sentence"]).toContain(e.door);
      if (e.door === "change") expect(e.anchor).toBeTruthy();
    }
  });

  it("names every module the web registers, and no module the web does not", () => {
    const named = new Set(
      WORKFLOW_ENTRIES.flatMap((e) => e.surfaces)
        .filter((k) => k.startsWith("features."))
        .map((k) => k.slice("features.".length)),
    );
    for (const feature of registeredModuleFeatures()) expect(named.has(feature)).toBe(true);
    for (const feature of named) expect([...registeredModuleFeatures(), "ado"]).toContain(feature);
  });

  it("an entry that asks names the Space, writes a Space's key, and says why wherever an answer is not live", () => {
    const asking = WORKFLOW_ENTRIES.filter((e) => e.answers);
    expect(asking.map((e) => e.id)).toEqual(["team-size", "solitaireAgile"]);
    for (const e of asking) {
      expect(e.question).toMatch(/ in \{space\}\?$/);
      expect(e.door).toBe("change");
      expect(e.answerKey).toMatch(/^spaces\.\{slug\}\./);
      for (const a of e.answers!) expect(a.sentence.length).toBeGreaterThan(10);
      for (const t of ["github", "ado", "none"] as const)
        if (e.answers!.some((a) => !a.live.includes(t))) expect(e.why?.[t]).toBeTruthy();
    }
    const how = WORKFLOW_ENTRIES.find((e) => e.id === "solitaireAgile")!;
    expect(how.question).toBe("How do you want to work in {space}?");
    expect(how.anchor).toBe("features.solitaireAgile");
    expect(how.answerKey).toBe("spaces.{slug}.howIWork");
    expect(how.answers!.map((a) => [a.label, a.value])).toEqual([
      ["With agents", "agents"],
      ["Alone", "alone"],
      ["On a team in Azure", "team"],
    ]);
    // team is derived from an Azure DevOps address and never written.
    expect(how.answers!.find((a) => a.value === "team")!.live).toEqual([]);
    // The team size: the room's three sizes, the contract's (consts.json
    // rituals.teamSizes), live where Team Agile's standup runs.
    const team = WORKFLOW_ENTRIES.find((e) => e.id === "team-size")!;
    expect(team.question).toBe("How many are in my standup in {space}?");
    expect(team.anchor).toBe("spaces.{slug}.features.teamSize");
    expect(team.answerKey).toBe("spaces.{slug}.features.teamSize");
    expect(team.answers!.map((a) => a.value)).toEqual(RITUALS.teamSizes.map(String));
    for (const a of team.answers!) expect(a.live).toEqual(["github"]);
  });

  it("an answer other than howIWork is read off the Space's own entry, at its key", () => {
    const team = WORKFLOW_ENTRIES.find((e) => e.id === "team-size")!;
    const how = WORKFLOW_ENTRIES.find((e) => e.id === "solitaireAgile")!;
    expect(asksHowIWork(how)).toBe(true);
    expect(asksHowIWork(team)).toBe(false);
    expect(answerStored(team, { slug: "x", features: { teamSize: 6 } })).toBe("6");
    expect(answerStored(team, { slug: "x", features: {} })).toBeUndefined();
    expect(answerStored(team, { slug: "x" })).toBeUndefined();
    expect(answerStored(team, undefined)).toBeUndefined();
    expect(answerStored(how, { slug: "x", howIWork: "agents" })).toBe("agents");
  });

  // The radios carry the detail, so the words around them stay short: the
  // entry's sentence, each answer's and each tracker's reason, one line each.
  it("an entry that asks says it in one line, and so does each answer and each reason", () => {
    const ONE_LINE = 90;
    for (const e of WORKFLOW_ENTRIES.filter((x) => x.answers)) {
      const lines = [
        e.sentence,
        ...e.answers!.map((a) => a.sentence),
        ...Object.values(e.why ?? {}),
      ];
      for (const s of lines) expect({ s, ok: s.length <= ONE_LINE }).toEqual({ s, ok: true });
      expect(e.sentence.split(/(?<=[.?!]) /).length).toBe(1);
    }
  });

  it("fills the Space into a question that names it, and the slug into the key the answers write", () => {
    const how = WORKFLOW_ENTRIES.find((e) => e.id === "solitaireAgile")!;
    expect(entryQuestion(how, "Toolkit")).toBe("How do you want to work in Toolkit?");
    expect(entryQuestion(how)).toBe("How do you want to work in this Space?");
    expect(answerTarget(how, "toolkit")).toBe("spaces.toolkit.howIWork");
    const lounge = WORKFLOW_ENTRIES.find((e) => e.id === "lounge")!;
    expect(entryQuestion(lounge, "Toolkit")).toBe(lounge.question);
    expect(answerTarget(lounge, "toolkit")).toBeUndefined();
  });

  it("an answer is live only on its trackers, and never where the Space's answer is locked", () => {
    const how = WORKFLOW_ENTRIES.find((e) => e.id === "solitaireAgile")!;
    const [agents, alone, team] = how.answers!;
    expect([agents, alone, team].map((a) => answerLive(a, "github", false))).toEqual([
      true,
      true,
      false,
    ]);
    expect([agents, alone, team].map((a) => answerLive(a, "ado", true))).toEqual([
      false,
      false,
      false,
    ]);
    expect([agents, alone, team].map((a) => answerLive(a, "none", true))).toEqual([
      false,
      false,
      false,
    ]);
    expect(answerLive(agents, "github", true)).toBe(false);
  });

  it("puts the hub first (D-W7)", () => {
    expect(WORKFLOW_ENTRIES[0].surfaces).toEqual(["promptsRoot"]);
  });
});

describe("reading an entry against the CLI's states", () => {
  const organize = WORKFLOW_ENTRIES.find((e) => e.id === "organize")!;
  const lounge = WORKFLOW_ENTRIES.find((e) => e.id === "lounge")!;

  it("is on if any surface is on, not configured if all are, else off", () => {
    expect(
      entryState(organize, [row("features.communication", "on"), row("features.organize", "off")]),
    ).toBe("on");
    expect(
      entryState(organize, [
        row("features.communication", "not configured"),
        row("features.organize", "not configured"),
      ]),
    ).toBe("not configured");
    expect(
      entryState(organize, [
        row("features.communication", "off"),
        row("features.organize", "not configured"),
      ]),
    ).toBe("off");
    expect(entryState(lounge, [])).toBe("not configured");
  });

  it("fills the active Space into the anchor, and into a walk's page", () => {
    const connect = WORKFLOW_ENTRIES.find((e) => e.id === "connect-azure")!;
    expect(entryAnchor(connect, "toolkit")).toBe("spaces.toolkit.org");
    expect(entryRoute(connect, "toolkit")).toBe("/connect/toolkit");
    expect(entryAnchor(lounge, "toolkit")).toBe("features.lounge");
  });

  it("carries the CLI line for the tooltip", () => {
    expect(entryConfigLines(lounge, [row("features.lounge", "off")])).toEqual([
      "tkConfig -Set features.lounge=x",
    ]);
  });

  it("a Space's own entry walks that Space when it is declared, else yours", () => {
    const gh = WORKFLOW_ENTRIES.find((e) => e.id === "connect-github")!;
    expect(entryRoute(gh, "toolkit", [{ slug: "github-demo", status: "local" }])).toBe(
      "/connect/github-demo",
    );
    expect(entryRoute(gh, "toolkit", [])).toBe("/connect/toolkit");
  });

  it("tips only from not configured, and only entries that carry a tip (D-W3)", () => {
    const all = WORKFLOW_ENTRIES.flatMap((e) => e.surfaces).map((k) => row(k, "not configured"));
    const ids = tippableEntries(all).map((e) => e.id);
    expect(ids).toContain("lounge");
    // Teams carries a tip (the webhook lives in .env); an entry with no tip never tips.
    expect(ids).toContain("teams");
    expect(ids).not.toContain("cards-live");
    const answeredNo = all.map((r) => (r.key === "features.lounge" ? row(r.key, "off") : r));
    expect(tippableEntries(answeredNo).map((e) => e.id)).not.toContain("lounge");
    // A Space's own tip is never read against the inventory.
    expect(ids).not.toContain("connect-github");
    expect(ids).not.toContain("demo");
  });
});

describe("the demo Spaces' tips", () => {
  // As tkStart leaves a machine: Demo and the GitHub demo from the sample hub,
  // the Azure demo (slug `azure-demo`, `test` before the rename) from config.default.json -- all three local.
  const shipped = [
    { slug: "azure-demo", status: "local" },
    { slug: "demo", status: "local" },
    { slug: "github-demo", status: "local" },
  ];

  it("in Demo, the three tips in the list's order: connect-github, connect-azure, demo", () => {
    expect(spaceTipEntries(shipped, "demo").map((e) => e.id)).toEqual([
      "connect-github",
      "connect-azure",
      "demo",
    ]);
  });

  it("the Azure demo's tip walks the Azure demo, and retires once it is connected", () => {
    const azure = spaceTipEntries(shipped, "demo").find((e) => e.id === "connect-azure")!;
    expect(entryRoute(azure, "demo", shipped)).toBe("/connect/azure-demo");
    const connected = shipped.map((s) =>
      s.slug === "azure-demo" ? { ...s, status: "active" } : s,
    );
    expect(spaceTipEntries(connected, "demo").map((e) => e.id)).not.toContain("connect-azure");
  });

  it("a journey tips while its Space is declared and still local; connecting retires it", () => {
    expect(spaceTipEntries(shipped, "demo").map((e) => e.id)).toContain("connect-github");
    const connected = shipped.map((s) =>
      s.slug === "github-demo" ? { ...s, status: "active" } : s,
    );
    expect(spaceTipEntries(connected, "demo").map((e) => e.id)).not.toContain("connect-github");
    // Hide Demo leaves the Space out of the declared list, and its tip goes with it.
    expect(
      spaceTipEntries([{ slug: "mine", status: "active" }], "mine").map((e) => e.id),
    ).not.toContain("connect-github");
  });

  it("the Demo's tip is said only while you are in Demo", () => {
    expect(spaceTipEntries(shipped, "demo").map((e) => e.id)).toContain("demo");
    expect(spaceTipEntries(shipped, "github-demo").map((e) => e.id)).not.toContain("demo");
  });

  it("connect-github rotates first", () => {
    expect(spaceTipEntries(shipped, "demo")[0].id).toBe("connect-github");
  });

  it("names the Spaces that carry their own tip, so the generic connect tip stands aside there", () => {
    expect(spaceHasOwnTip("github-demo")).toBe(true);
    expect(spaceHasOwnTip("azure-demo")).toBe(true);
    expect(spaceHasOwnTip("demo")).toBe(true);
    expect(spaceHasOwnTip("mine")).toBe(false);
  });
});

// The way back to unset, as the drawer's radios draw it: first, for every asking
// entry but How do you want to work? (whose checked answer is the agent's, never
// unset), named as the select names it, live where an answer is.
describe("answerChoices: Default first, but not for howIWork", () => {
  const team = WORKFLOW_ENTRIES.find((e) => e.id === "team-size")!;
  const how = WORKFLOW_ENTRIES.find(asksHowIWork)!;

  it("the standup's size opens on Default (the contract's size), then its answers", () => {
    const choices = answerChoices(team);
    expect(choices.map((a) => a.label)).toEqual([
      `Default (${RITUALS.teamSizeDefault})`,
      ...team.answers!.map((a) => a.label),
    ]);
    expect(choices[0].value).toBe("");
    expect(choices[0].live).toEqual(["github"]);
  });

  it("How do you want to work? is its answers alone", () => {
    expect(answerChoices(how)).toEqual(how.answers);
  });

  it("an entry is found by the schema key it asks", () => {
    expect(entryAsking("spaces.<slug>.features.teamSize")?.id).toBe("team-size");
    expect(entryAsking("spaces.<slug>.status")).toBeUndefined();
  });
});
