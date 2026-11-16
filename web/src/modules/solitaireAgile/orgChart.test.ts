import { FACE_IDS } from "../../shared/refinedFaces";
import {
  LEVEL_FACES,
  LEVEL_WALLS,
  OFFICE_HEIGHT,
  POSITION_FACES,
  SIZE,
  layoutChart,
  levelWall,
  officeWidth,
  plateWho,
  positionFaces,
  seatFace,
  seatWhere,
} from "./orgChart";
import { chartNames, orgResponse } from "./orgFixture";

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
    const stranger = { ...lead, id: "not-in-the-map", level: 1 };
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

  it("a plate says the model, the person, or vacant; and where the seat is", () => {
    const seats = orgResponse("valid").tree.positions.flatMap((p) => p.seats);
    const by = (id: string) => seats.find((s) => s.id === id)!;
    expect(plateWho(by("owner"))).toBe("Sam");
    expect(plateWho(by("alpha"))).toBe("fable");
    expect(plateWho(by("gamma"))).toBe("vacant");
    expect(seatWhere(by("alpha"))).toBe("alpha on mini");
    expect(seatWhere(by("pm"))).toBe("on laptop");
    expect(seatWhere(by("owner"))).toBe("");
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
