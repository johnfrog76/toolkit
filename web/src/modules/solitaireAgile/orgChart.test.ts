import fs from "node:fs";
import path from "node:path";
import { FACE_IDS } from "../../shared/refinedFaces";
import type { OrgPosition } from "./api.solitaireAgile";
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
  plateTitle,
  plateWho,
  positionFaces,
  seatFace,
  seatWhere,
  vacantMug,
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
