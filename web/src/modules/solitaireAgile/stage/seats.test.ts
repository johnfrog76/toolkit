import fs from "node:fs";
import path from "node:path";
import { RITUALS } from "../../../shell/consts";
import type { StandupResponse, StandupWorker, WorkWorker } from "../api.solitaireAgile";
import { CAST } from "./cast";
import {
  CHAIR_CAST_ID,
  KEPT_WINDOWS,
  MEMBER_SEATS,
  MEMBER_WINDOWS,
  ROOM_WINDOWS,
  dealRoom,
  seatedPlate,
} from "./seats";

// The stage is the third reader of the shared room table
// (Tests/fixtures/rituals/standup-team.json): the terminal's Standup and the
// agent seat each row (tkTestToolkit -Rituals, Tests/test_rituals.py), and the
// stage must put every speaker in the window the same row names. The stage
// does not decide who is in the room -- the response's round does -- so each
// row is given to it as the response would carry it: the record with who is
// present, and the round in turn order. Nothing below types a window.

const FIXTURES = path.resolve(__dirname, "../../../../../Tests/fixtures/rituals");

interface Speaker {
  label: string;
  cast: boolean;
  window?: string;
  name?: string;
}
interface RoomRow {
  name: string;
  size: number;
  engineer: { label: string; empty: boolean } | null;
  labels: { label: string; empty: boolean }[];
  present: string[];
  round: Required<Pick<Speaker, "label" | "cast" | "window">>[];
  desks: string[];
}
interface TeamCase {
  name: string;
  space?: string;
  expected: {
    team: { size: number };
    workers: { label: string; name: string; empty: boolean; present: boolean }[];
    round: Speaker[];
  };
}
const table = JSON.parse(fs.readFileSync(path.join(FIXTURES, "standup-team.json"), "utf8")) as {
  room: RoomRow[];
  cases: TeamCase[];
};

const AS_OF = "2026-10-02T09:00:00-04:00";
const worker = (label: string, empty: boolean, present: boolean, name = label): StandupWorker => ({
  label,
  name,
  yesterday: [],
  today: [],
  blockers: [],
  empty,
  excuse: "",
  status: [],
  present,
});
const plateOf = new Map(RITUALS.room.windows.map((w) => [w.id, w.plate]));
const spoken = (s: Speaker): WorkWorker => ({
  label: s.label,
  name: s.name ?? (s.cast ? plateOf.get(s.label)! : s.label),
  yesterday: [],
  today: [],
  blockers: [],
  prose: ["A turn."],
  cast: s.cast,
});

/** A row as the response carries it: the record is the labels in label order
 *  and then the engineer, as both fills keep it; the round is the row's own. */
function responseOf(
  record: StandupWorker[],
  round: Speaker[],
  engineer: string | null,
): Pick<StandupResponse, "asOf" | "workers" | "work" | "space" | "source"> {
  return {
    asOf: AS_OF,
    space: engineer ?? "",
    source: engineer ? "both" : "issues",
    workers: record,
    work: {
      queue: { walk: [], decide: [], look: [] },
      workers: round.map(spoken),
      queueProse: [],
      text: "",
    },
  };
}

describe("the room's data is the shared room", () => {
  it("the stage's windows, chair and kept windows are consts.json's", () => {
    expect(ROOM_WINDOWS).toBe(RITUALS.room.windows.length);
    expect(MEMBER_SEATS).toBe(ROOM_WINDOWS - 1);
    expect(CHAIR_CAST_ID).toBe(RITUALS.room.chair);
    expect(KEPT_WINDOWS).toEqual(RITUALS.room.kept);
    expect(MEMBER_WINDOWS.map((w) => [w.castId, w.persona])).toEqual(
      RITUALS.room.windows.filter((w) => w.id !== RITUALS.room.chair).map((w) => [w.id, w.plate]),
    );
  });

  it("every window of the room has its drawing, in the same order and under the same plate", () => {
    // cast.tsx keys each scene by its cast id and carries the persona for the
    // copy panel: the art's own list. It is held to the room here, so a window
    // the room names is never one the stage cannot draw.
    expect(CAST.map((c) => [c.id, c.label])).toEqual(
      RITUALS.room.windows.map((w) => [w.id, w.plate]),
    );
  });
});

describe("the stage seats every row of the shared room table", () => {
  it("the table has rows for the stage to read", () => {
    expect(table.room.length).toBeGreaterThan(0);
    expect(table.cases.length).toBeGreaterThan(0);
  });

  for (const row of table.room) {
    it(row.name, () => {
      const present = new Set(row.present);
      const record = [
        ...row.labels.map((l) => worker(l.label, l.empty, present.has(l.label))),
        ...(row.engineer ? [worker(row.engineer.label, row.engineer.empty, true)] : []),
      ];
      const room = dealRoom(responseOf(record, row.round, row.engineer?.label ?? null));
      // Each speaker, in turn order, in the window the table names.
      expect(room.members.map((m) => [m.worker.label, m.cast, m.castId])).toEqual(
        row.round.map((r) => [r.label, r.cast, r.window]),
      );
      // Empty desks are only the windows past the size.
      expect(room.desks.map((d) => d.castId)).toEqual(row.desks);
      expect(room.members.length + room.desks.length).toBe(MEMBER_SEATS);
      // An invented member wears its persona alone; a member, its persona and label.
      for (const m of room.members)
        expect(seatedPlate(m)).toBe(
          m.cast ? plateOf.get(m.castId) : `${plateOf.get(m.castId)} (${m.worker.label})`,
        );
    });
  }

  for (const c of table.cases) {
    it(`the ${c.name} case: its round in turn order, a cast member in its own window, ${
      ROOM_WINDOWS - Math.max(c.expected.team.size, 1 + c.expected.round.length)
    } desks`, () => {
      const record = c.expected.workers.map((w) => worker(w.label, w.empty, w.present, w.name));
      const room = dealRoom(responseOf(record, c.expected.round, c.space ?? null));
      expect(room.members.map((m) => [m.worker.label, m.cast])).toEqual(
        c.expected.round.map((r) => [r.label, r.cast]),
      );
      for (const m of room.members.filter((x) => x.cast)) expect(m.castId).toBe(m.worker.label);
      expect(new Set(room.members.map((m) => m.castId)).size).toBe(room.members.length);
      // A room the size fills has exactly the windows past the size as desks.
      if (c.expected.round.length === c.expected.team.size - 1)
        expect(room.desks).toHaveLength(ROOM_WINDOWS - c.expected.team.size);
    });
  }
});

describe("a response the round does not account for is seated by its record", () => {
  const record = [worker("a", true, true), worker("b", true, false), worker("c", true, true)];

  it("no work grain: the present, in the record's order", () => {
    const room = dealRoom({ asOf: AS_OF, workers: record });
    expect(room.members.map((m) => m.worker.label)).toEqual(["a", "c"]);
    expect(room.members.every((m) => !m.cast)).toBe(true);
  });

  it("a round that names someone the record does not, or leaves a present member out", () => {
    const stray = responseOf(
      record,
      [
        { label: "a", cast: false },
        { label: "z", cast: false },
      ],
      null,
    );
    expect(dealRoom(stray).members.map((m) => m.worker.label)).toEqual(["a", "c"]);
    const short = responseOf(record, [{ label: "a", cast: false }], null);
    expect(dealRoom(short).members.map((m) => m.worker.label)).toEqual(["a", "c"]);
  });
});
