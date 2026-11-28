import fs from "node:fs";
import path from "node:path";
import { FACE_IDS } from "../../shared/refinedFaces";
import type { OrgPosition, OrgSeat } from "./api.solitaireAgile";
import { ORG } from "../../shell/consts";
import type { PlacedOffice } from "./orgChart";
import {
  LEVEL_FACES,
  LEVEL_WALLS,
  OFFICE_HEIGHT,
  POSITION_FACES,
  SIZE,
  layoutChart,
  levelWall,
  officeWidth,
  isChangedSince,
  plateTitle,
  plateWhere,
  plateWho,
  seatActionLabel,
  HELD_MODEL,
  isHeldModel,
  seatChoices,
  seatModelDefault,
  signTitle,
  viewLabel,
  positionFaces,
  seatFace,
  seatWhere,
  vacantMug,
  PORTRAIT_NAMES,
  defaultSeatFace,
  takesPortrait,
  isPortrait,
  portraitChoices,
  seatPortrait,
} from "./orgChart";
import { MUG_LOOKS } from "./stage/EmptyDesk";
import { chartNames, modelNameOf, orgResponse } from "./orgFixture";

// The Org page's rules apart from its drawing, over the shared table's charts
// (Tests/fixtures/org/charts/): which face sits where, the walls by level, what
// a plate says, and where each office goes.

describe("the position-to-face map", () => {
  it("names only faces the refined cast has", () => {
    const known = new Set<string>(FACE_IDS);
    for (const faces of [...Object.values(POSITION_FACES), ...LEVEL_FACES]) {
      expect(faces.length).toBeGreaterThan(0);
      for (const face of faces) expect(known).toContain(face);
    }
  });

  it("follows the mock: each position of ours has its own face, the leads three", () => {
    expect(POSITION_FACES).toEqual({
      owner: ["owner"],
      "vp-product": ["designer"],
      "vp-engineering": ["ultrawide"],
      pm: ["pm"],
      "team-lead": ["dev-hero", "ops-dev", "qa"],
      builder: ["minimalist", "new-hire", "vibemancer", "qa"],
    });
  });

  it.each(chartNames())("every position and seat of the %s chart has a face", (name) => {
    for (const p of orgResponse(name).tree.positions) {
      expect(positionFaces(p).length).toBeGreaterThan(0);
      p.seats.forEach((_, i) => expect(FACE_IDS).toContain(seatFace(p, i)));
    }
  });

  it("the lead's seats take its faces in turn; an unnamed position takes its level's", () => {
    const lead = orgResponse("valid").tree.positions.find((p) => p.id === "team-lead")!;
    expect(lead.seats.map((_, i) => seatFace(lead, i))).toEqual(["dev-hero", "ops-dev", "qa"]);
    const stranger = { ...lead, id: "not-in-the-map", prompt: null, level: 1 };
    expect(positionFaces(stranger, 0)[0]).toBe("designer");
    expect(positionFaces(stranger, 1)[0]).toBe("ultrawide");
    expect(positionFaces({ ...stranger, level: 9 })).toEqual(LEVEL_FACES[4]);
  });
});

describe("a seat's portrait", () => {
  const TABLE = JSON.parse(
    fs.readFileSync(
      path.resolve(__dirname, "../../../../Tests/fixtures/org/portraits.json"),
      "utf8",
    ),
  ) as {
    ids: { value: string; valid: boolean }[];
    tree: { positions: (Partial<OrgPosition> & { id: string; reportsTo?: string })[] };
    seats: { kind: string; seat: string; value: string; takes: boolean; outcome: string }[];
  };
  const asPosition = (p: (typeof TABLE.tree.positions)[number]): OrgPosition =>
    ({
      ...p,
      prompt: p.prompt ?? null,
      reportsTo: p.reportsTo ?? null,
      seats: p.seats ?? [],
    }) as OrgPosition;

  it("every portrait id of consts.json is a face the refined cast draws, with a name", () => {
    for (const id of ORG.portraits) {
      expect(FACE_IDS).toContain(id);
      expect(PORTRAIT_NAMES[id]).toBeTruthy();
    }
    expect(ORG.portraits).not.toContain("owner");
  });

  it("the choices: the seat's own default first, as no portrait, then the ids in their order", () => {
    const choices = portraitChoices("ultrawide");
    expect(choices.map((c) => c.value)).toEqual(["", ...ORG.portraits]);
    expect(choices[0]).toEqual({ value: "", face: "ultrawide", label: "Default" });
    expect(new Set(choices.map((c) => c.label)).size).toBe(choices.length);
  });

  it("an id is a portrait exactly as the shared table says (the page reads the served, trimmed id)", () => {
    for (const row of TABLE.ids) {
      if (row.value !== row.value.trim()) continue;
      expect([row.value, isPortrait(row.value)]).toEqual([row.value, row.valid]);
    }
  });

  it("the one rule names the seats that take a portrait, as the shared table's seat rows say", () => {
    for (const row of TABLE.seats) {
      const position = TABLE.tree.positions.find((p) => p.id === row.seat.split(".")[0])!;
      expect([row.kind, takesPortrait(asPosition(position))]).toEqual([row.kind, row.takes]);
    }
  });

  it("a seat that takes one draws its portrait; without one, its own face; a seat that takes none ignores it", () => {
    const chart = orgResponse("portrait-on-the-owner").tree;
    expect(seatFace(chart.positions[0], 0)).toBe("robot");
    expect(defaultSeatFace(chart.positions[0], 0)).toBe("owner");
    expect(seatPortrait(chart.positions[0].seats[0])).toBe("robot");
    const plain = orgResponse("valid").tree.positions[0];
    expect(seatFace(plain, 0)).toBe("owner");
    expect(seatPortrait(plain.seats[0])).toBe("");
    const odd = { ...plain, seats: [{ ...plain.seats[0], portrait: "mascot" }] };
    expect(seatFace(odd, 0)).toBe("owner");
    const pm = chart.positions[1];
    expect(seatFace({ ...pm, seats: [{ ...pm.seats[0], portrait: "alien" }] }, 0)).toBe(
      seatFace(pm, 0),
    );
  });
});

describe("the walls and the plates", () => {
  it("a wall per level, the builders' for anything deeper", () => {
    expect(LEVEL_WALLS.map((w) => w.wall)).toEqual([
      "#ecd3a2",
      "#a9d3ee",
      "#f0aa98",
      "#a8dbbb",
      "#c6c9e8",
    ]);
    expect(levelWall(7)).toBe(LEVEL_WALLS[4]);
  });

  it("a plate says the model by its name, the person, or vacant; and the Space, never a machine", () => {
    // An older file: families for models, and a machine on every seat that is never drawn.
    const seats = orgResponse("valid").tree.positions.flatMap((p) => p.seats);
    const by = (id: string) => seats.find((s) => s.id === id)!;
    expect(plateWho(by("owner"))).toBe("Sam");
    expect(plateWho(by("alpha"))).toBe(modelNameOf("fable"));
    expect(plateWho(by("alpha"))).not.toBe("fable");
    expect(plateWho(by("gamma"))).toBe("vacant");
    expect(seatWhere(by("alpha"))).toBe("alpha");
    expect(seatWhere(by("pm"))).toBe("");
    expect(seatWhere(by("owner"))).toBe("");
  });

  it("over the whole shape: a seat's roleTitle on its plate, the model map's name, an unknown id as written", () => {
    const positions = orgResponse("the-shape-complete").tree.positions;
    const lead = positions.find((p) => p.id === "team-lead")!;
    const [alpha, beta] = lead.seats;
    expect(plateTitle(lead, alpha)).toBe("Alpha lead");
    expect(plateTitle(lead, beta)).toBe("Team lead");
    expect(plateWho(alpha)).toBe("Opus 5.5");
    expect(plateWho(beta)).toBe("a-model-the-map-does-not-know");
    const vp = positions.find((p) => p.id === "vp-product")!;
    expect(plateWho(vp.seats[0])).toBe("Fable 5.2");
    expect(vp.seats[0].session).toBe("product-session");
  });
});

describe("a vacant seat's mug", () => {
  it("comes from the seat's id: the same seat the same mug, every look reachable", () => {
    expect(vacantMug("gamma")).toBe("straw");
    expect(vacantMug("gamma")).toBe(vacantMug("gamma"));
    expect(vacantMug("")).toBe(MUG_LOOKS[0]);
    const seen = new Set(Array.from({ length: 64 }, (_, i) => vacantMug(`seat-${i}`)));
    expect(seen).toEqual(new Set(MUG_LOOKS));
  });
});

describe("the layout", () => {
  const layout = layoutChart(orgResponse("valid").tree.positions);
  const at = (id: string) => layout.offices.find((o) => o.position.id === id)!;

  it("one office a position, one row a level, top to bottom", () => {
    expect(layout.offices).toHaveLength(6);
    const tops = [0, 1, 2, 3, 4].map((level) =>
      layout.offices.filter((o) => o.position.level === level).map((o) => o.top),
    );
    for (const row of tops) expect(new Set(row).size).toBe(1);
    expect(tops.map((r) => r[0])).toEqual([...tops.map((r) => r[0])].sort((a, b) => a - b));
    expect(at("owner").top).toBe(0);
    expect(at("pm").top).toBe(2 * (OFFICE_HEIGHT + SIZE.rowGap));
  });

  it("the lead's three seats are one office, three cards wide; the pool one wide card", () => {
    expect(at("team-lead").width).toBe(officeWidth(at("team-lead").position));
    expect(at("team-lead").width).toBe(3 * SIZE.cell + 2 * SIZE.seatGap + 2 * SIZE.pad);
    expect(at("builder").width).toBe(SIZE.poolCell + 2 * SIZE.pad);
  });

  it("each position is centred over its reports, and a line runs to each", () => {
    expect(at("owner").cx).toBe((at("vp-product").cx + at("vp-engineering").cx) / 2);
    expect(at("pm").cx).toBe(at("vp-engineering").cx);
    expect(at("builder").cx).toBe(at("team-lead").cx);
    expect(layout.lines.map((l) => `${l.from.position.id}>${l.to.position.id}`).sort()).toEqual([
      "owner>vp-engineering",
      "owner>vp-product",
      "pm>team-lead",
      "team-lead>builder",
      "vp-engineering>pm",
    ]);
    for (const o of layout.offices) {
      expect(o.left).toBeGreaterThanOrEqual(0);
      expect(o.left + o.width).toBeLessThanOrEqual(layout.width);
    }
  });
});

// -- A team is one lead and its own builders (the M and L presets) ---------------

/** A preset file's positions in tree order with their level, as the route serves them. */
function presetPositions(file: string): OrgPosition[] {
  const raw = JSON.parse(
    fs.readFileSync(path.resolve(__dirname, "../../../../samples/org-presets", file), "utf8"),
  ) as {
    positions: {
      id: string;
      title?: string;
      prompt?: string;
      reportsTo?: string;
      seats?: { id: string }[];
    }[];
  };
  const out: OrgPosition[] = [];
  const walk = (id: string | undefined, level: number) => {
    for (const p of raw.positions.filter((x) => (x.reportsTo ?? undefined) === id)) {
      out.push({
        id: p.id,
        title: p.title ?? p.id,
        prompt: p.prompt ?? null,
        reportsTo: p.reportsTo ?? null,
        defaultModel: null,
        defaultModelName: null,
        recommend: [],
        level,
        seats: (p.seats ?? []).map((s) => ({
          id: s.id,
          roleTitle: null,
          model: null,
          modelName: null,
          person: null,
          session: null,
          merges: null,
          space: null,
          state: "vacant" as const,
        })),
        promptTitle: null,
        promptRef: null,
      });
      walk(p.id, level + 1);
    }
  };
  walk(undefined, 0);
  return out;
}

describe("the faces of a team, by its role", () => {
  it("a lead's office is a lead's faces whatever it is called, and every pool is builders", () => {
    for (const file of ["branch-office.json", "corporate-headquarters.json"]) {
      const positions = presetPositions(file);
      for (const p of positions.filter((x) => x.id.startsWith("lead-team"))) {
        expect(positionFaces(p)).toBe(POSITION_FACES["team-lead"]);
      }
      for (const p of positions.filter((x) => x.id.startsWith("builders-team"))) {
        expect(positionFaces(p)).toBe(POSITION_FACES.builder);
      }
    }
  });
});

describe("the layout of a team: one lead, its own pool", () => {
  it.each([
    ["branch-office.json", [["lead-team", "builders-team"]]],
    [
      "corporate-headquarters.json",
      [
        ["lead-team-1", "builders-team-1"],
        ["lead-team-2", "builders-team-2"],
      ],
    ],
  ])(
    "%s: each lead is a bare one-seat office, with a line to its own pool under it",
    (file, teams) => {
      const layout = layoutChart(presetPositions(file));
      const at = (id: string) => layout.offices.find((o) => o.position.id === id)!;
      const lines = layout.lines.map((l) => `${l.from.position.id}>${l.to.position.id}`);
      for (const [lead, pool] of teams) {
        expect(at(lead).width).toBe(SIZE.cell + 2 * SIZE.pad);
        expect(at(pool).width).toBe(SIZE.poolCell + 2 * SIZE.pad);
        expect(at(pool).cx).toBe(at(lead).cx);
        expect(lines.filter((l) => l.endsWith(`>${pool}`))).toEqual([`${lead}>${pool}`]);
        expect(lines.filter((l) => l.startsWith(`${lead}>`))).toEqual([`${lead}>${pool}`]);
      }
      for (const o of layout.offices) {
        expect(o.left).toBeGreaterThanOrEqual(0);
        expect(o.left + o.width).toBeLessThanOrEqual(layout.width);
      }
      // No two offices on a row overlap: a column a team.
      const rows = new Map<number, PlacedOffice[]>();
      for (const o of layout.offices) rows.set(o.top, [...(rows.get(o.top) ?? []), o]);
      for (const row of rows.values()) {
        const sorted = [...row].sort((a, b) => a.left - b.left);
        for (let i = 1; i < sorted.length; i++) {
          expect(sorted[i].left).toBeGreaterThanOrEqual(sorted[i - 1].left + sorted[i - 1].width);
        }
      }
    },
  );
});

describe("the seat dialog's rules", () => {
  const position = (over: Partial<OrgPosition> = {}): OrgPosition => ({
    id: "p",
    title: "P",
    prompt: null,
    reportsTo: "owner",
    defaultModel: null,
    recommend: [],
    level: 1,
    seats: [],
    promptTitle: null,
    promptRef: null,
    defaultModelName: null,
    defaultModelFamily: null,
    ...over,
  });
  const seat = (over: Partial<OrgSeat> = {}): OrgSeat => ({
    id: "s",
    roleTitle: null,
    model: null,
    modelName: null,
    modelFamily: null,
    person: null,
    session: null,
    merges: null,
    space: null,
    state: "vacant",
    ...over,
  });

  it("a vacant seat starts on its position's defaultModel, else its role's, else none", () => {
    expect(seatModelDefault(position({ defaultModelFamily: "haiku" }), seat())).toBe("haiku");
    expect(seatModelDefault(position({ prompt: ORG.roles.vpEngineering }), seat())).toBe(
      ORG.steps.vpEngineering,
    );
    expect(seatModelDefault(position({ prompt: ORG.roles.vpProduct }), seat())).toBe(
      ORG.steps.vpProduct,
    );
    for (const [role, family] of Object.entries(ORG.roleDefaults)) {
      expect(seatModelDefault(position({ prompt: role }), seat())).toBe(family);
    }
    expect(seatModelDefault(position({ prompt: "pm.prompt.md" }), seat())).toBe("");
  });

  it("a person in a seat with no model starts on no model", () => {
    const vp = position({ prompt: ORG.roles.vpEngineering });
    expect(seatModelDefault(vp, seat({ person: "Kim", state: "staffed" }))).toBe("");
  });

  const NAMES = { fable: "Fable 5.2", opus: "Opus 5.5", sonnet: "Sonnet 5.5", haiku: "Haiku 5.5" };
  const ALL = ["fable", "opus", "sonnet", "haiku"];

  it("a VP is offered three choices by their current models' names, Sonnet not recommended, no Haiku", () => {
    const vp = position({ prompt: ORG.roles.vpEngineering, recommend: ["opus", "fable"] });
    expect(seatChoices(vp, seat(), ALL, NAMES)).toEqual([
      { value: "opus", label: "Opus 5.5" },
      { value: "fable", label: "Fable 5.2" },
      { value: "sonnet", label: "Sonnet 5.5 (not recommended)" },
    ]);
  });

  it("any other seat is offered the four current families, by name", () => {
    expect(seatChoices(position(), seat(), ALL, NAMES).map((c) => c.label)).toEqual([
      "Fable 5.2",
      "Opus 5.5",
      "Sonnet 5.5",
      "Haiku 5.5",
    ]);
  });

  it("a seat holding a model that is not its family's current one keeps it as a choice of its own, chosen", () => {
    const older = seat({
      model: "claude-opus-5",
      modelName: "Opus 5",
      modelFamily: "opus",
      state: "staffed",
    });
    expect(isHeldModel(older, NAMES)).toBe(true);
    expect(seatChoices(position(), older, ALL, NAMES)[0]).toEqual({
      value: HELD_MODEL,
      label: "Opus 5",
    });
    expect(seatModelDefault(position(), older, NAMES)).toBe(HELD_MODEL);
    // Another provider's, or one the map does not know: as written, held the same way.
    const unknown = seat({ model: "x-model", modelName: "x-model", state: "staffed" });
    expect(seatChoices(position(), unknown, ALL, NAMES)[0]).toEqual({
      value: HELD_MODEL,
      label: "x-model",
    });
    expect(seatModelDefault(position(), unknown, NAMES)).toBe(HELD_MODEL);
    // The current model, or its family's word, is no held model.
    const current = seat({
      model: "claude-opus-5-5",
      modelName: "Opus 5.5",
      modelFamily: "opus",
      state: "staffed",
    });
    const word = seat({
      model: "opus",
      modelName: "Opus 5.5",
      modelFamily: "opus",
      state: "staffed",
    });
    for (const s of [current, word]) {
      expect(isHeldModel(s, NAMES)).toBe(false);
      expect(seatModelDefault(position(), s, NAMES)).toBe("opus");
      expect(seatChoices(position(), s, ALL, NAMES)).toHaveLength(4);
    }
  });

  it("the sign is the one seat's label, a room's position title; a room's plate carries a seat's own label", () => {
    const one = position({
      title: "Team lead",
      seats: [seat({ roleTitle: "Toolkit lead", space: "toolkit" })],
    });
    expect(signTitle(one)).toBe("Toolkit lead");
    expect(plateWhere(one, one.seats[0])).toBe("toolkit");
    const room = position({
      title: "Team lead",
      seats: [seat({ id: "a", roleTitle: "A lead", space: "a" }), seat({ id: "b" })],
    });
    expect(signTitle(room)).toBe("Team lead");
    expect(plateWhere(room, room.seats[0])).toBe("A lead · a");
    expect(plateWhere(room, room.seats[1])).toBe("");
  });

  it("the button's name: Assign the seat, or Change it naming who sits there", () => {
    const vp = position({ title: "VP of engineering" });
    expect(seatActionLabel(vp, seat())).toBe("Assign VP of engineering");
    expect(seatActionLabel(vp, seat({ model: "m", modelName: "Opus 5.5", state: "staffed" }))).toBe(
      "Change VP of engineering, Opus 5.5",
    );
    expect(viewLabel(position({ title: "PM", promptTitle: "The PM" }))).toBe(
      "View the The PM role",
    );
  });

  it("finds Staff's -IfMatch refusal by its words", () => {
    expect(isChangedSince(`org.json ${ORG.changedSince}; reload and try again.`)).toBe(true);
    expect(isChangedSince("Some other refusal.")).toBe(false);
    expect(isChangedSince(null)).toBe(false);
  });
});
